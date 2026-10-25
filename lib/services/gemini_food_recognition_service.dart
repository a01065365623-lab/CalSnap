import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/foundation.dart' show ValueListenable, ValueNotifier, debugPrint, kReleaseMode;
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

import 'food_recognition_service.dart';
import 'user_profile_service.dart';

/// Gemini(gemini-2.0-flash)를 클라이언트에서 직접 호출하지 않고, API 키를 보관하는
/// 자체 백엔드 프록시(backend/, Flask + Railway)를 거쳐 결과를 받아온다.
///
/// 업로드 전에 이미지를 최대 [_maxUploadDimension]px로 리사이즈하고 JPEG 품질
/// [_jpegQuality]%로 재인코딩한다(원본 카메라 사진은 수 MB인데 인식에는 그럴
/// 필요가 없어서, 이게 인식 왕복 시간의 주된 병목이었음). 압축 전/후 바이트 크기와
/// 업로드+응답 소요 시간을 debugPrint로 남기니 flutter run 로그로 확인 가능.
///
/// 프록시 계약 — POST {proxyBaseUrl}/recognize
///   헤더: Content-Type: application/json, X-API-Key: <apiKey>,
///         X-User-Id: <온보딩 때 생성된 임의 UUID — 서버의 기기별 일일 사용 제한 집계용>
///   기기별 일일 한도 초과 시: 403 {"code": "daily_limit_exceeded", "usage": {...}, ...}
///   성공 응답과 한도 초과 응답에는 오늘 사용량 "usage": {"photo": {"used", "limit",
///   "remaining"}, "text": {...}}가 함께 오고, [usage]로 화면에 노출한다.
///   요청 바디: {"image": "<base64 인코딩 이미지>", "hint": "<선택, 사용자가 아는 음식 이름>",
///             "language": "<선택, 기기 언어 코드(예: ko/en/ja). foodName만 이 언어로 응답>"}
///   응답 예시: {"foodName": "김치찌개", "caloriesPer100g": 90, "estimatedWeightG": 400,
///             "carbsG": 6, "proteinG": 8, "fatG": 4}  (carbsG/proteinG/fatG는 100g 기준,
///             foodName 외 값들은 언어와 무관한 숫자)
///
/// proxyBaseUrl / apiKey는 소스에 하드코딩하지 않고 컴파일 타임에 주입한다:
///   flutter run --dart-define=PROXY_BASE_URL=https://your-proxy.up.railway.app \
///               --dart-define=PROXY_API_KEY=your-secret-key
/// 또는 .env 스타일 파일로 한 번에 (Flutter 3.7+):
///   flutter run --dart-define-from-file=env.json
///   // env.json: {"PROXY_BASE_URL": "...", "PROXY_API_KEY": "..."}
class GeminiFoodRecognitionService implements FoodRecognitionService {
  static const String _defaultProxyBaseUrl = String.fromEnvironment(
    'PROXY_BASE_URL',
    defaultValue: 'https://calsnap-production-1689.up.railway.app',
  );
  static const String _defaultProxyApiKey =
      String.fromEnvironment('PROXY_API_KEY');

  /// Gemini의 JSON 텍스트 응답에는 확률적 신뢰도 점수가 없어 고정값을 사용한다.
  static const double _placeholderConfidence = 0.7;

  /// 업로드 전 리사이즈 기준 최대 가로/세로 픽셀. 최신 폰 카메라 원본(가로 3000px+,
  /// 수 MB)을 그대로 올리면 업로드 자체가 인식 지연의 주 원인이 되는데, 음식 인식은
  /// 이 정도 해상도로도 충분해서 체감 속도 개선 대비 정확도 손실이 거의 없다.
  static const int _maxUploadDimension = 768;

  /// 리사이즈 후 JPEG 재인코딩 품질(0~100). 80%는 육안으로는 화질 차이가 거의 없으면서
  /// 파일 크기를 크게 줄여주는 통상적인 절충값.
  static const int _jpegQuality = 80;

  /// 프록시 서버(Railway 무료 티어 콜드스타트 포함)가 응답하지 않을 때 무한 대기하지
  /// 않도록 두는 상한. 이 시간을 넘기면 TimeoutException을 던져 호출자가 에러 처리를
  /// 할 수 있게 한다.
  ///
  /// 실측 결과 Gemini 응답이 5~21초까지 편차가 커서(백엔드 Procfile의 gunicorn
  /// --timeout 45s보다 짧게 잡아, 서버가 워커를 죽이기 전에 클라이언트가 먼저
  /// 친절한 타임아웃 메시지를 보여주도록 함) 20초보다 여유를 뒀다.
  static const Duration _timeout = Duration(seconds: 35);

  final String proxyBaseUrl;
  final String apiKey;
  final http.Client _client;
  final ValueNotifier<RecognitionUsage?> _usage = ValueNotifier(null);

  @override
  ValueListenable<RecognitionUsage?> get usage => _usage;

  GeminiFoodRecognitionService({
    this.proxyBaseUrl = _defaultProxyBaseUrl,
    this.apiKey = _defaultProxyApiKey,
    http.Client? client,
  }) : _client = client ?? http.Client() {
    // release 빌드를 --dart-define(-from-file)=env.json 없이 만들면 apiKey가 빈
    // 문자열로 컴파일되어, 모든 요청이 서버에서 조용히 401로 거부된다(2026-08-17
    // 발견 사례: 앱이 정상적으로 켜지고 화면도 다 뜨는데 인식만 매번 실패해서
    // 원인 파악이 늦어졌음). assert는 release에서 제거되므로 여기서는 일반 if로
    // 검사해 즉시 크래시시킨다 — 사용자에게 조용히 실패하는 것보다, 빌드/QA 단계에서
    // 크게 터지는 편이 훨씬 빨리 원인을 찾을 수 있다.
    if (kReleaseMode && apiKey.isEmpty) {
      throw StateError(
        'PROXY_API_KEY가 비어 있는 채로 release 빌드가 만들어졌습니다. '
        'scripts/build_release.sh(.ps1)로 다시 빌드하거나, '
        '`--dart-define-from-file=env.json`을 직접 지정하세요. '
        '(README.md "Release 빌드" 섹션 참고)',
      );
    }
  }

  @override
  Future<FoodRecognitionResult> recognize(File imageFile, {String? hint}) async {
    final uri = Uri.parse('$proxyBaseUrl/recognize');

    final originalBytes = await imageFile.readAsBytes();
    final compressStopwatch = Stopwatch()..start();
    final uploadBytes = _compressForUpload(originalBytes);
    compressStopwatch.stop();
    debugPrint(
      '[GeminiFoodRecognitionService] 이미지 압축: '
      '${originalBytes.length}B → ${uploadBytes.length}B '
      '(${compressStopwatch.elapsedMilliseconds}ms, 최대 ${_maxUploadDimension}px/품질 $_jpegQuality%)',
    );
    final base64Image = base64Encode(uploadBytes);
    final trimmedHint = hint?.trim();
    // 기기 언어 코드(예: 'ko', 'en', 'ja')만 보낸다. 지원 여부 판단·영어 폴백은
    // 백엔드 프롬프트에서 처리하므로 여기서는 별도 검증 없이 그대로 전달한다.
    final languageCode = PlatformDispatcher.instance.locale.languageCode;

    final http.Response res;
    final requestStopwatch = Stopwatch()..start();
    try {
      res = await _client
          .post(
            uri,
            headers: await _headers(),
            body: jsonEncode({
              'image': base64Image,
              if (trimmedHint != null && trimmedHint.isNotEmpty) 'hint': trimmedHint,
              'language': languageCode,
            }),
          )
          .timeout(_timeout);
    } on TimeoutException {
      throw FoodRecognitionException(
        FoodRecognitionFailure.timeout,
        'Gemini 프록시 응답 시간 초과 (${_timeout.inSeconds}s)',
      );
    } on SocketException catch (e) {
      throw FoodRecognitionException(FoodRecognitionFailure.network, '네트워크 연결 실패: $e');
    } on http.ClientException catch (e) {
      throw FoodRecognitionException(FoodRecognitionFailure.network, '네트워크 연결 실패: $e');
    } finally {
      requestStopwatch.stop();
      debugPrint(
        '[GeminiFoodRecognitionService] 업로드+인식 응답 시간: '
        '${requestStopwatch.elapsedMilliseconds}ms (전송 ${uploadBytes.length}B)',
      );
    }

    if (res.statusCode == 401) {
      throw const FoodRecognitionException(
        FoodRecognitionFailure.unauthorized,
        'Gemini 프록시 인증 실패 (401) — PROXY_API_KEY 불일치',
      );
    }
    _updateUsageFrom(res);
    if (_isDailyLimitExceeded(res)) {
      throw FoodRecognitionException(
        FoodRecognitionFailure.dailyLimitExceeded,
        '일일 사용 한도 초과: ${res.body}',
      );
    }
    if (res.statusCode == 429) {
      throw FoodRecognitionException(
        FoodRecognitionFailure.rateLimited,
        'Gemini rate limit (429): ${res.body}',
      );
    }
    if (res.statusCode != 200) {
      throw FoodRecognitionException(
        FoodRecognitionFailure.server,
        'Gemini 프록시 호출 실패: ${res.statusCode} ${res.body}',
      );
    }

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final foodName = data['foodName'] as String? ?? '알 수 없음';
    final caloriesPer100g = (data['caloriesPer100g'] as num?)?.toDouble() ?? 0;
    final estimatedWeightG = (data['estimatedWeightG'] as num?)?.toDouble() ?? 0;
    final carbsG = (data['carbsG'] as num?)?.toDouble() ?? 0;
    final proteinG = (data['proteinG'] as num?)?.toDouble() ?? 0;
    final fatG = (data['fatG'] as num?)?.toDouble() ?? 0;

    return FoodRecognitionResult(
      foodName: foodName,
      caloriesPer100g: caloriesPer100g,
      estimatedWeightG: estimatedWeightG,
      confidence: _placeholderConfidence,
      carbsG: carbsG,
      proteinG: proteinG,
      fatG: fatG,
    );
  }

  /// 프록시 계약 — POST {proxyBaseUrl}/recognize-text
  ///   헤더: Content-Type: application/json, X-API-Key: <apiKey>
  ///   요청 바디: {"foodName": "<사용자가 입력한 음식 이름>", "amount": <숫자>,
  ///             "unit": "g|ml|serving|piece", "language": "<선택, 기기 언어 코드>"}
  ///   응답 스키마는 /recognize와 동일하다: {"foodName", "caloriesPer100g",
  ///   "estimatedWeightG", "carbsG", "proteinG", "fatG"} — estimatedWeightG는
  ///   서버가 amount+unit을 그램으로 환산한 값이다(예: "라면 1개" → 약 120g).
  @override
  Future<FoodRecognitionResult> recognizeFromText({
    required String foodName,
    required double amount,
    required String unit,
  }) async {
    final uri = Uri.parse('$proxyBaseUrl/recognize-text');
    final languageCode = PlatformDispatcher.instance.locale.languageCode;

    final http.Response res;
    try {
      res = await _client
          .post(
            uri,
            headers: await _headers(),
            body: jsonEncode({
              'foodName': foodName,
              'amount': amount,
              'unit': unit,
              'language': languageCode,
            }),
          )
          .timeout(_timeout);
    } on TimeoutException {
      throw FoodRecognitionException(
        FoodRecognitionFailure.timeout,
        'Gemini 프록시 응답 시간 초과 (${_timeout.inSeconds}s)',
      );
    } on SocketException catch (e) {
      throw FoodRecognitionException(FoodRecognitionFailure.network, '네트워크 연결 실패: $e');
    } on http.ClientException catch (e) {
      throw FoodRecognitionException(FoodRecognitionFailure.network, '네트워크 연결 실패: $e');
    }

    if (res.statusCode == 401) {
      throw const FoodRecognitionException(
        FoodRecognitionFailure.unauthorized,
        'Gemini 프록시 인증 실패 (401) — PROXY_API_KEY 불일치',
      );
    }
    _updateUsageFrom(res);
    if (_isDailyLimitExceeded(res)) {
      throw FoodRecognitionException(
        FoodRecognitionFailure.dailyLimitExceeded,
        '일일 사용 한도 초과: ${res.body}',
      );
    }
    if (res.statusCode == 429) {
      throw FoodRecognitionException(
        FoodRecognitionFailure.rateLimited,
        'Gemini rate limit (429): ${res.body}',
      );
    }
    if (res.statusCode != 200) {
      throw FoodRecognitionException(
        FoodRecognitionFailure.server,
        'Gemini 프록시 호출 실패: ${res.statusCode} ${res.body}',
      );
    }

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return FoodRecognitionResult(
      foodName: data['foodName'] as String? ?? foodName,
      caloriesPer100g: (data['caloriesPer100g'] as num?)?.toDouble() ?? 0,
      estimatedWeightG: (data['estimatedWeightG'] as num?)?.toDouble() ?? 0,
      confidence: _placeholderConfidence,
      carbsG: (data['carbsG'] as num?)?.toDouble() ?? 0,
      proteinG: (data['proteinG'] as num?)?.toDouble() ?? 0,
      fatG: (data['fatG'] as num?)?.toDouble() ?? 0,
    );
  }

  /// 프록시 계약 — GET {proxyBaseUrl}/usage → {"usage": {"photo": {...}, "text": {...}}}
  @override
  Future<void> refreshUsage() async {
    try {
      final res = await _client
          .get(Uri.parse('$proxyBaseUrl/usage'), headers: await _headers())
          .timeout(const Duration(seconds: 10));
      _updateUsageFrom(res);
    } catch (e) {
      // 남은 횟수 표시는 부가 정보라 실패해도 조용히 넘어간다(표시만 생략됨).
      debugPrint('[GeminiFoodRecognitionService] 사용량 조회 실패: $e');
    }
  }

  void _updateUsageFrom(http.Response res) {
    if (res.statusCode != 200 && res.statusCode != 403) return;
    try {
      final data = jsonDecode(res.body);
      if (data is! Map) return;
      final usage = RecognitionUsage.fromJson(data['usage']);
      if (usage != null) _usage.value = usage;
    } on FormatException {
      // 본문 파싱 실패는 아래 상태 코드 처리에서 다룬다.
    }
  }

  Future<Map<String, String>> _headers() async {
    // 온보딩 전이라 ID가 없으면 헤더를 생략한다 — 서버는 그 경우 IP 기준으로 센다.
    final userId = await UserProfileService.instance.getUserId();
    return {
      'Content-Type': 'application/json',
      'X-API-Key': apiKey,
      if (userId != null && userId.isNotEmpty) 'X-User-Id': userId,
    };
  }

  /// 서버의 기기별 일일 한도 초과 응답(403 + code=daily_limit_exceeded)인지 판별한다.
  /// Gemini 쿼터 소진(429, 잠시 후 재시도 가능)과는 안내 문구가 달라 따로 구분한다.
  static bool _isDailyLimitExceeded(http.Response res) {
    if (res.statusCode != 403) return false;
    try {
      final data = jsonDecode(res.body);
      return data is Map && data['code'] == 'daily_limit_exceeded';
    } on FormatException {
      return false;
    }
  }

  /// 가로/세로 중 긴 쪽이 [_maxUploadDimension]을 넘으면 비율을 유지한 채 줄이고,
  /// JPEG 품질 [_jpegQuality]로 재인코딩한다. 디코딩에 실패하면(지원 안 하는 포맷 등)
  /// 원본을 그대로 반환해 인식 자체는 계속 시도할 수 있게 한다.
  static Uint8List _compressForUpload(Uint8List originalBytes) {
    final decoded = img.decodeImage(originalBytes);
    if (decoded == null) return originalBytes;

    final longestSide = decoded.width > decoded.height ? decoded.width : decoded.height;
    final resized = longestSide > _maxUploadDimension
        ? img.copyResize(
            decoded,
            width: decoded.width >= decoded.height ? _maxUploadDimension : null,
            height: decoded.height > decoded.width ? _maxUploadDimension : null,
          )
        : decoded;

    return Uint8List.fromList(img.encodeJpg(resized, quality: _jpegQuality));
  }
}
