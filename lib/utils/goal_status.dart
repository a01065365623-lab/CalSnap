enum GoalStatus {
  /// 목표 칼로리 대비 순칼로리가 ±10% 이내.
  met,

  /// 목표 칼로리보다 10% 초과.
  over,

  /// 목표 칼로리가 설정되지 않았거나, 아직 그날 섭취 기록이 없거나,
  /// 목표보다 10% 넘게 적게 먹은 경우(해당하는 멘트 카테고리가 없음).
  unknown,
}

/// 목표 칼로리 대비 오늘 순칼로리 상태를 판단한다. TTS 격려 멘트(goal_met/goal_over)
/// 재생 여부를 결정하는 데 사용한다.
GoalStatus evaluateGoalStatus({
  required double netCalories,
  required double? goalCalories,
  required bool hasIntake,
}) {
  if (!hasIntake || goalCalories == null || goalCalories <= 0) return GoalStatus.unknown;

  final diffRatio = (netCalories - goalCalories) / goalCalories;
  if (diffRatio.abs() <= 0.1) return GoalStatus.met;
  if (diffRatio > 0.1) return GoalStatus.over;
  return GoalStatus.unknown;
}
