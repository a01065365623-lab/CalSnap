/// 오늘의 로그 탄단지 진행 바의 "목표" 값. 앱에 탄단지 목표를 따로 저장하지 않으므로,
/// 저장된 하루 목표 칼로리를 흔히 쓰는 기본 비율(탄수화물 50% · 단백질 20% · 지방 30%)로
/// 나눠 g으로 환산한 표시용 기준이다(1g당 탄수화물·단백질 4kcal, 지방 9kcal).
class MacroTargets {
  final double carbsG;
  final double proteinG;
  final double fatG;

  const MacroTargets({required this.carbsG, required this.proteinG, required this.fatG});
}

const double carbsCalorieShare = 0.5;
const double proteinCalorieShare = 0.2;
const double fatCalorieShare = 0.3;

/// 목표 칼로리가 없거나 0 이하면 null(진행 바 없이 섭취량만 보여준다).
MacroTargets? macroTargetsFor(double? goalCalories) {
  if (goalCalories == null || goalCalories <= 0) return null;
  return MacroTargets(
    carbsG: goalCalories * carbsCalorieShare / 4,
    proteinG: goalCalories * proteinCalorieShare / 4,
    fatG: goalCalories * fatCalorieShare / 9,
  );
}
