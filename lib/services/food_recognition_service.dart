import 'dart:io';

import 'package:flutter_gen/gen_l10n/app_localizations.dart';

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

  /// 사진 없이 음식 이름과 양(직접 입력 모드)만으로 칼로리/영양소를 추정한다.
  /// [unit]은 [ManualAmountUnitX.apiValue] 값('g'/'ml'/'serving'/'piece')을 그대로 받는다.
  Future<FoodRecognitionResult> recognizeFromText({
    required String foodName,
    required double amount,
    required String unit,
  });
}

enum FoodRecognitionFailure {
  /// 프록시가 401을 반환. X-API-Key(PROXY_API_KEY)가 서버와 불일치 — 재시도로는 해결 안 됨.
  unauthorized,

  /// 클라이언트 타임아웃(20초) 초과. Gemini 응답 지연 또는 네트워크 불안정.
  timeout,

  /// 소켓/DNS/연결 실패 등 요청 자체가 서버에 도달하지 못함.
  network,

  /// 프록시가 429를 반환 — Gemini 쪽 rate limit(쿼터 소진)에 걸림. 서버측 문제인
  /// server/unknown과 구분해야 "지금 다시 시도해도 될지"를 사용자에게 정확히
  /// 안내할 수 있다.
  rateLimited,

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

/// 사진 기반/텍스트 기반 인식 화면 양쪽에서 공유하는 에러 메시지 매핑.
String friendlyRecognitionErrorMessage(AppLocalizations l10n, Object error) {
  if (error is FoodRecognitionException) {
    switch (error.failure) {
      case FoodRecognitionFailure.unauthorized:
        return l10n.recognitionErrorUnauthorized;
      case FoodRecognitionFailure.timeout:
        return l10n.recognitionErrorTimeout;
      case FoodRecognitionFailure.network:
        return l10n.recognitionErrorNetwork;
      case FoodRecognitionFailure.rateLimited:
        return l10n.recognitionErrorRateLimited;
      case FoodRecognitionFailure.server:
      case FoodRecognitionFailure.unknown:
        return l10n.recognitionErrorGeneric;
    }
  }
  return l10n.recognitionErrorGeneric;
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

  @override
  Future<FoodRecognitionResult> recognizeFromText({
    required String foodName,
    required double amount,
    required String unit,
  }) async {
    await Future.delayed(const Duration(milliseconds: 500));
    return FoodRecognitionResult(
      foodName: foodName,
      caloriesPer100g: 90,
      estimatedWeightG: amount,
      confidence: 0.75,
      carbsG: 8,
      proteinG: 7,
      fatG: 5,
    );
  }
}
