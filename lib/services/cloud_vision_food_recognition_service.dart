import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'food_recognition_service.dart';
import 'nutrition_api_service.dart';

/// Cloud Vision을 클라이언트에서 직접 호출하지 않고, API 키를 보관하는
/// 자체 백엔드 프록시(backend/, Flask + Railway)를 거쳐 결과를 받아온다.
///
/// 프록시 계약 — POST {proxyBaseUrl}/recognize
///   헤더: Content-Type: application/json, X-API-Key: <apiKey>
///   요청 바디: {"image": "<base64 인코딩 이미지>"}
///   응답 예시: {"labels": [{"description": "Kimchi stew", "score": 0.91}, ...]}
///
/// proxyBaseUrl / apiKey는 소스에 하드코딩하지 않고 컴파일 타임에 주입한다:
///   flutter run --dart-define=PROXY_BASE_URL=https://your-proxy.up.railway.app \
///               --dart-define=PROXY_API_KEY=your-secret-key
/// 또는 .env 스타일 파일로 한 번에 (Flutter 3.7+):
///   flutter run --dart-define-from-file=env.json
///   // env.json: {"PROXY_BASE_URL": "...", "PROXY_API_KEY": "..."}
class CloudVisionFoodRecognitionService implements FoodRecognitionService {
  static const String _defaultProxyBaseUrl = String.fromEnvironment(
    'PROXY_BASE_URL',
    defaultValue: 'https://TODO-railway-proxy-url',
  );
  static const String _defaultProxyApiKey =
      String.fromEnvironment('PROXY_API_KEY');

  final String proxyBaseUrl;
  final String apiKey;
  final http.Client _client;
  final NutritionApiService _nutritionApiService;

  CloudVisionFoodRecognitionService({
    this.proxyBaseUrl = _defaultProxyBaseUrl,
    this.apiKey = _defaultProxyApiKey,
    http.Client? client,
    NutritionApiService? nutritionApiService,
  })  : _client = client ?? http.Client(),
        _nutritionApiService = nutritionApiService ?? NutritionApiService();

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
      throw Exception('Cloud Vision 프록시 호출 실패: ${res.statusCode}');
    }

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final labels = ((data['labels'] as List?) ?? [])
        .cast<Map<String, dynamic>>();

    if (labels.isEmpty) {
      return const FoodRecognitionResult(
        foodName: '알 수 없음',
        estimatedCalories: 0,
        confidence: 0,
      );
    }

    final top = labels.reduce((a, b) {
      final scoreA = (a['score'] as num?)?.toDouble() ?? 0;
      final scoreB = (b['score'] as num?)?.toDouble() ?? 0;
      return scoreB > scoreA ? b : a;
    });

    final foodName = top['description'] as String? ?? '알 수 없음';
    final confidence = (top['score'] as num?)?.toDouble() ?? 0;
    final calories = await _lookupCaloriesPer100g(foodName);

    return FoodRecognitionResult(
      foodName: foodName,
      // 식약처 DB에 매칭되는 항목이 없으면 0으로 둔다 (추후 UI에서 "칼로리 정보 없음" 처리 가능).
      estimatedCalories: calories ?? 0,
      confidence: confidence,
    );
  }

  Future<double?> _lookupCaloriesPer100g(String foodName) async {
    try {
      final results = await _nutritionApiService.searchFood(foodName);
      if (results.isEmpty) return null;
      return results.first.caloriesPer100g;
    } catch (_) {
      // 식약처 API 실패는 인식 자체를 막지 않고 칼로리 미상 처리로 넘어간다.
      return null;
    }
  }
}
