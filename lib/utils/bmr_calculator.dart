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

/// 체질량지수(BMI, kg/m²)를 계산한다.
double calculateBmi({required double weightKg, required double heightCm}) {
  final heightM = heightCm / 100;
  return weightKg / (heightM * heightM);
}

/// 대한비만학회 기준 BMI 분류.
String getBmiCategory(double bmi) {
  if (bmi < 18.5) return '저체중';
  if (bmi < 23) return '정상';
  if (bmi < 25) return '과체중';
  return '비만';
}
