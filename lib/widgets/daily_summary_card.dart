import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../models/daily_log_entry.dart';
import '../theme/app_colors.dart';

/// 순칼로리 / 목표 칼로리 비율(0 이상). 목표가 없거나 0 이하면 null.
/// 운동으로 순칼로리가 음수가 되면 0으로 본다.
double? goalProgressRatio({required double netCalories, required double? goalCalories}) {
  if (goalCalories == null || goalCalories <= 0) return null;
  final ratio = netCalories / goalCalories;
  return ratio < 0 ? 0 : ratio;
}

/// 오늘의 로그 상단 요약 카드. 섭취/소모/순칼로리 숫자 옆에 목표 대비 진행률 링을
/// 보여준다. 목표 칼로리가 아직 없으면(온보딩 전 등) 링 없이 숫자만 보여준다.
class DailySummaryCard extends StatelessWidget {
  final DailySummary? summary;
  final double? goalCalories;

  const DailySummaryCard({super.key, required this.summary, required this.goalCalories});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final intake = summary?.totalIntake ?? 0;
    final burned = summary?.totalBurned ?? 0;
    final net = summary?.netCalories ?? 0;
    final ratio = goalProgressRatio(netCalories: net, goalCalories: goalCalories);

    return Card(
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            if (ratio != null) ...[
              GoalProgressRing(ratio: ratio),
              const SizedBox(width: 12),
            ],
            Expanded(child: _StatColumn(label: l10n.dailyLogIntakeLabel, value: intake)),
            Expanded(child: _StatColumn(label: l10n.dailyLogBurnedLabel, value: burned)),
            Expanded(child: _StatColumn(label: l10n.netCaloriesLabel, value: net, highlight: true)),
          ],
        ),
      ),
    );
  }
}

/// 순칼로리/목표 칼로리 원형 진행률. 100%를 넘으면 링·숫자·라벨을 주의색으로 바꾼다
/// (링 자체는 100%에서 꽉 찬 상태로 멈추고, 숫자는 실제 비율을 그대로 보여준다).
class GoalProgressRing extends StatelessWidget {
  final double ratio;
  const GoalProgressRing({super.key, required this.ratio});

  bool get isOver => ratio > 1;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final percent = (ratio * 100).round();
    final color = isOver ? AppColors.goalOverRed : AppColors.foodCoral;
    final trackColor = isOver ? AppColors.goalOverRedBg : AppColors.foodCoralBg;

    return Semantics(
      label: l10n.dailyLogGoalProgressSemantics(percent),
      excludeSemantics: true,
      child: SizedBox(
        width: 68,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 60,
              height: 60,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CircularProgressIndicator(
                    value: ratio.clamp(0.0, 1.0),
                    strokeWidth: 6,
                    backgroundColor: trackColor,
                    color: color,
                    strokeCap: StrokeCap.round,
                  ),
                  Padding(
                    padding: const EdgeInsets.all(9),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        '$percent%',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: color),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              isOver ? l10n.dailyLogGoalOverLabel : l10n.dailyLogGoalProgressLabel,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: isOver ? AppColors.goalOverRed : Colors.grey,
                fontWeight: isOver ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatColumn extends StatelessWidget {
  final String label;
  final double value;
  final bool highlight;
  const _StatColumn({required this.label, required this.value, this.highlight = false});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.grey),
        ),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value.toStringAsFixed(0),
            style: TextStyle(
              fontSize: 20,
              fontWeight: highlight ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ],
    );
  }
}
