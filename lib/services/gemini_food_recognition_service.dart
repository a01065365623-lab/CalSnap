import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

import 'package:http/http.dart' as http;

import 'food_recognition_service.dart';

/// Gemini(gemini-2.0-flash)를 클라이언트에서 직접 호출하지 않고, API 키를 보관하는
/// 자체 백엔드 프록시(backend/, Flask + Railway)를 거쳐 결과를 받아온다.
///
/// 프록시 계약 — POST {proxyBaseUrl}/recognize
///   헤더: Content-Type: application/json, X-API-Key: <apiKey>
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

  GeminiFoodRecognitionService({
    this.proxyBaseUrl = _defaultProxyBaseUrl,
    this.apiKey = _defaultProxyApiKey,
    http.Client? client,
  }) : _client = client ?? http.Client();

  @override
  Future<FoodRecognitionResult> recognize(File imageFile, {String? hint}) async {
    final uri = Uri.parse('$proxyBaseUrl/recognize');
    final base64Image = base64Encode(await imageFile.readAsBytes());
    final trimmedHint = hint?.trim();
    // 기기 언어 코드(예: 'ko', 'en', 'ja')만 보낸다. 지원 여부 판단·영어 폴백은
    // 백엔드 프롬프트에서 처리하므로 여기서는 별도 검증 없이 그대로 전달한다.
    final languageCode = PlatformDispatcher.instance.locale.languageCode;

    final http.Response res;
    try {
      res = await _client
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'X-API-Key': apiKey,
            },
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
    }

    if (res.statusCode == 401) {
      throw const FoodRecognitionException(
        FoodRecognitionFailure.unauthorized,
        'Gemini 프록시 인증 실패 (401) — PROXY_API_KEY 불일치',
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
}
