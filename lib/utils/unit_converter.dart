/// 사용자에게 보여줄 단위계. 내부 저장(DB, SharedPreferences)은 항상 미터법(g/kg)을
/// 기준으로 하고, 이 값은 화면 표시/입력 변환에만 사용한다.
enum UnitSystem { metric, imperial }

const double gramsPerOz = 28.349523125;
const double kgPerLb = 0.45359237;

double gramsToOz(double grams) => grams / gramsPerOz;

double ozToGrams(double oz) => oz * gramsPerOz;

double kgToLb(double kg) => kg / kgPerLb;

double lbToKg(double lb) => lb * kgPerLb;

/// 음식/식품 중량(g)을 [unit]에 맞춰 "350g" 또는 "12.3oz" 형태로 표시한다.
String formatWeight(double grams, UnitSystem unit) {
  if (unit == UnitSystem.imperial) {
    return '${gramsToOz(grams).toStringAsFixed(1)}oz';
  }
  return '${grams.toStringAsFixed(0)}g';
}

/// 체중(kg)을 [unit]에 맞춰 "65.0kg" 또는 "143.3lb" 형태로 표시한다.
String formatBodyWeight(double kg, UnitSystem unit) {
  if (unit == UnitSystem.imperial) {
    return '${kgToLb(kg).toStringAsFixed(1)}lb';
  }
  return '${kg.toStringAsFixed(1)}kg';
}
