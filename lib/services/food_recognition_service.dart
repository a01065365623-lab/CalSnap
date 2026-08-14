import 'dart:io';

import 'food_recognition/on_device_food_matcher.dart';
import 'gemini_food_recognition_service.dart';

/// 사진 한 장을 분석해 음식 카테고리와 추정 칼로리를 반환하는 서비스.
class FoodRecognitionResult {
  final String foodName;
  final double caloriesPer100g;
  final double estimatedWeightG;
  final double confidence; // 0.0 ~ 1.0
  final double carbsG; // 100g당 탄수화물(g)
  final double proteinG; // 100g당 단백질(g)
  final double fatG; // 100g당 지방(g)

  const FoodRecognitionResult({
    required this.foodName,
    required this.caloriesPer100g,
    required this.estimatedWeightG,
    required this.confidence,
    this.carbsG = 0,
    this.proteinG = 0,
    this.fatG = 0,
  });
}

abstract class FoodRecognitionService {
  /// [hint]: 사용자가 알고 있는 음식 이름(선택). 인식 정확도를 높이는 참고용이며 비어있어도 된다.
  Future<FoodRecognitionResult> recognize(File imageFile, {String? hint});
}

enum FoodRecognitionFailure {
  /// 프록시가 401을 반환. X-API-Key(PROXY_API_KEY)가 서버와 불일치 — 재시도로는 해결 안 됨.
  unauthorized,

  /// 클라이언트 타임아웃(20초) 초과. Gemini 응답 지연 또는 네트워크 불안정.
  timeout,

  /// 소켓/DNS/연결 실패 등 요청 자체가 서버에 도달하지 못함.
  network,

  /// 프록시가 4xx/5xx(401 제외)를 반환 — Gemini 호출 실패, 응답 파싱 실패 등 서버측 문제.
  server,

  /// 위에 해당하지 않는 예기치 못한 오류.
  unknown,
}

class FoodRecognitionException implements Exception {
  final FoodRecognitionFailure failure;
  final String message;

  const FoodRecognitionException(this.failure, this.message);

  @override
  String toString() => message;
}

/// 실제 API 연동 전까지 사용할 더미 구현.
class MockFoodRecognitionService implements FoodRecognitionService {
  @override
  Future<FoodRecognitionResult> recognize(File imageFile, {String? hint}) async {
    await Future.delayed(const Duration(milliseconds: 500));
    return const FoodRecognitionResult(
      foodName: '김치찌개 (추정)',
      caloriesPer100g: 90,
      estimatedWeightG: 500,
      confidence: 0.75,
      carbsG: 8,
      proteinG: 7,
      fatG: 5,
    );
  }
}

/// 1차: 온디바이스 MobileNetV2 임베딩 매칭. 유사도가 낮으면 Gemini로 폴백한다.
class HybridFoodRecognitionService implements FoodRecognitionService {
  /// 코사인 유사도가 이 값 미만이면 온디바이스 매칭 결과를 신뢰하지 않고 폴백한다.
  static const double similarityThreshold = 0.75;

  /// 온디바이스 매칭은 중량을 추정하지 않으므로 사용하는 기본 1인분 중량(g).
  static const double _defaultEstimatedWeightG = 300;

  final OnDeviceFoodMatcher _onDeviceMatcher;
  final GeminiFoodRecognitionService _geminiFallback;

  HybridFoodRecognitionService({
    GeminiFoodRecognitionService? geminiFallback,
    OnDeviceFoodMatcher? onDeviceMatcher,
  })  : _geminiFallback = geminiFallback ?? GeminiFoodRecognitionService(),
        _onDeviceMatcher = onDeviceMatcher ?? OnDeviceFoodMatcher();

  @override
  Future<FoodRecognitionResult> recognize(File imageFile, {String? hint}) async {
    // 사용자가 힌트를 제공한 경우, 이름을 확신할 수 없는 온디바이스 매칭보다
    // 힌트를 반영할 수 있는 Gemini 폴백이 더 정확하므로 곧바로 폴백한다.
    if (hint == null || hint.trim().isEmpty) {
      try {
        final match = await _onDeviceMatcher.match(imageFile);
        if (match != null && match.similarity >= similarityThreshold) {
          // 온디바이스 참조 DB(FoodEmbedding)에는 탄단지 정보가 없어 0으로 채운다.
          return FoodRecognitionResult(
            foodName: match.food.foodName,
            caloriesPer100g: match.food.caloriesPer100g,
            estimatedWeightG: _defaultEstimatedWeightG,
            confidence: match.similarity,
          );
        }
      } catch (_) {
        // 모델/DB 로드 실패 등 온디바이스 매칭 불가 시에도 앱이 죽지 않고 폴백한다.
      }
    }
    return _geminiFallback.recognize(imageFile, hint: hint);
  }

  void dispose() => _onDeviceMatcher.dispose();
}
