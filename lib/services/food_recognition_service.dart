import 'dart:io';

import 'cloud_vision_food_recognition_service.dart';
import 'food_recognition/on_device_food_matcher.dart';

/// 사진 한 장을 분석해 음식 카테고리와 추정 칼로리를 반환하는 서비스.
class FoodRecognitionResult {
  final String foodName;
  final double estimatedCalories;
  final double confidence; // 0.0 ~ 1.0

  const FoodRecognitionResult({
    required this.foodName,
    required this.estimatedCalories,
    required this.confidence,
  });
}

abstract class FoodRecognitionService {
  Future<FoodRecognitionResult> recognize(File imageFile);
}

/// 실제 API 연동 전까지 사용할 더미 구현.
class MockFoodRecognitionService implements FoodRecognitionService {
  @override
  Future<FoodRecognitionResult> recognize(File imageFile) async {
    await Future.delayed(const Duration(milliseconds: 500));
    return const FoodRecognitionResult(
      foodName: '김치찌개 (추정)',
      estimatedCalories: 450,
      confidence: 0.75,
    );
  }
}

/// 1차: 온디바이스 MobileNetV2 임베딩 매칭. 유사도가 낮으면 Cloud Vision으로 폴백한다.
class HybridFoodRecognitionService implements FoodRecognitionService {
  /// 코사인 유사도가 이 값 미만이면 온디바이스 매칭 결과를 신뢰하지 않고 폴백한다.
  static const double similarityThreshold = 0.75;

  final OnDeviceFoodMatcher _onDeviceMatcher;
  final CloudVisionFoodRecognitionService _cloudFallback;

  HybridFoodRecognitionService({
    CloudVisionFoodRecognitionService? cloudFallback,
    OnDeviceFoodMatcher? onDeviceMatcher,
  })  : _cloudFallback = cloudFallback ?? CloudVisionFoodRecognitionService(),
        _onDeviceMatcher = onDeviceMatcher ?? OnDeviceFoodMatcher();

  @override
  Future<FoodRecognitionResult> recognize(File imageFile) async {
    try {
      final match = await _onDeviceMatcher.match(imageFile);
      if (match != null && match.similarity >= similarityThreshold) {
        return FoodRecognitionResult(
          foodName: match.food.foodName,
          estimatedCalories: match.food.caloriesPer100g,
          confidence: match.similarity,
        );
      }
    } catch (_) {
      // 모델/DB 로드 실패 등 온디바이스 매칭 불가 시에도 앱이 죽지 않고 폴백한다.
    }
    return _cloudFallback.recognize(imageFile);
  }

  void dispose() => _onDeviceMatcher.dispose();
}
