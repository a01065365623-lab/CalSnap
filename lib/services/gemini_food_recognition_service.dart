import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'food_recognition_service.dart';

/// Gemini(gemini-2.0-flash)를 클라이언트에서 직접 호출하지 않고, API 키를 보관하는
/// 자체 백엔드 프록시(backend/, Flask + Railway)를 거쳐 결과를 받아온다.
///
/// 프록시 계약 — POST {proxyBaseUrl}/recognize
///   헤더: Content-Type: application/json, X-API-Key: <apiKey>
///   요청 바디: {"image": "<base64 인코딩 이미지>"}
///   응답 예시: {"foodName": "김치찌개", "caloriesPer100g": 90, "estimatedWeightG": 400}
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
    defaultValue: 'https://TODO-railway-proxy-url',
  );
  static const String _defaultProxyApiKey =
      String.fromEnvironment('PROXY_API_KEY');

  /// Gemini의 JSON 텍스트 응답에는 확률적 신뢰도 점수가 없어 고정값을 사용한다.
  static const double _placeholderConfidence = 0.7;

  final String proxyBaseUrl;
  final String apiKey;
  final http.Client _client;

  GeminiFoodRecognitionService({
    this.proxyBaseUrl = _defaultProxyBaseUrl,
    this.apiKey = _defaultProxyApiKey,
    http.Client? client,
  }) : _client = client ?? http.Client();

  @override
  Future<FoodRecognitionResult> recognize(File imageFile) async {
    final uri = Uri.parse('$proxyBaseUrl/recognize');
    final base64Image = base64Encode(await imageFile.readAsBytes());

    final res = await _client.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'X-API-Key': apiKey,
      },
      body: jsonEncode({'image': base64Image}),
    );

    if (res.statusCode != 200) {
      throw Exception('Gemini 프록시 호출 실패: ${res.statusCode}');
    }

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final foodName = data['foodName'] as String? ?? '알 수 없음';
    final caloriesPer100g = (data['caloriesPer100g'] as num?)?.toDouble() ?? 0;
    final estimatedWeightG = (data['estimatedWeightG'] as num?)?.toDouble() ?? 0;

    return FoodRecognitionResult(
      foodName: foodName,
      caloriesPer100g: caloriesPer100g,
      estimatedWeightG: estimatedWeightG,
      confidence: _placeholderConfidence,
    );
  }
}
