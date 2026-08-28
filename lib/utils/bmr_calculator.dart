enum Gender { male, female }

/// Mifflin-St Jeor 공식으로 기초대사량(BMR, kcal/day)을 계산한다.
/// 남성: 10*체중 + 6.25*키 - 5*나이 + 5
/// 여성: 10*체중 + 6.25*키 - 5*나이 - 161
double calculateBmr({
  required Gender gender,
  required int age,
  required double heightCm,
  required double weightKg,
}) {
  final base = 10 * weightKg + 6.25 * heightCm - 5 * age;
  return gender == Gender.male ? base + 5 : base - 161;
}

/// 활동계수 기본값("보통" 수준의 활동량).
const double defaultActivityFactor = 1.55;

/// BMR에 활동계수를 곱한 하루 목표 칼로리(kcal/day).
double calculateGoalCalories({
  required Gender gender,
  required int age,
  required double heightCm,
  required double weightKg,
  double activityFactor = defaultActivityFactor,
}) {
  return calculateBmr(gender: gender, age: age, heightCm: heightCm, weightKg: weightKg) * activityFactor;
}

/// 체중(kg) 기준 하루 권장 수분 섭취량(ml) 계수. "체중 × 32ml"이 흔히 쓰이는 기준.
const double defaultWaterGoalMlPerKg = 32;

/// 체중 × [mlPerKg]로 계산한 하루 권장 수분 섭취량(ml).
double calculateWaterGoalMl({
  required double weightKg,
  double mlPerKg = defaultWaterGoalMlPerKg,
}) {
  return weightKg * mlPerKg;
}

/// 체질량지수(BMI, kg/m²)를 계산한다.
double calculateBmi({required double weightKg, required double heightCm}) {
  final heightM = heightCm / 100;
  return weightKg / (heightM * heightM);
}

/// 대한비만학회 기준 BMI 분류. 문자열이 아닌 enum을 반환해, 화면(UI 레이어)에서
/// AppLocalizations로 언어별 라벨을 붙이도록 한다(이 파일은 Flutter 의존성 없는
/// 순수 계산 유틸로 유지).
enum BmiCategory { underweight, normal, overweight, obese }

BmiCategory getBmiCategory(double bmi) {
  if (bmi < 18.5) return BmiCategory.underweight;
  if (bmi < 23) return BmiCategory.normal;
  if (bmi < 25) return BmiCategory.overweight;
  return BmiCategory.obese;
}
