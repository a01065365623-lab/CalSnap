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

/// 오늘의 로그 상단 요약 카드. 순칼로리를 가장 크게, 그 아래에 섭취(코랄)·소모(틸)를
/// 아이콘과 함께 보여주고, 왼쪽에 목표 대비 진행률 링을 둔다. 목표 칼로리가 아직
/// 없으면(온보딩 전 등) 링 없이 숫자만 보여준다.
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
              const SizedBox(width: 16),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _NetCalories(label: l10n.netCaloriesLabel, value: net),
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _SubStat(
                          icon: Icons.restaurant,
                          label: l10n.dailyLogIntakeLabel,
                          value: intake,
                          iconColor: AppColors.foodCoral,
                          valueColor: AppColors.foodCoralStrong,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _SubStat(
                          icon: Icons.local_fire_department,
                          label: l10n.dailyLogBurnedLabel,
                          value: burned,
                          iconColor: AppColors.exerciseTeal,
                          valueColor: AppColors.exerciseTealStrong,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
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
    // 링은 비텍스트(3:1)라 기본 코랄, 가운데 퍼센트 글자는 4.5:1을 넘는 진한 코랄.
    final color = isOver ? AppColors.goalOverRed : AppColors.foodCoral;
    final textColor = isOver ? AppColors.goalOverRed : AppColors.foodCoralStrong;
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
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: textColor),
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
                color: isOver ? AppColors.goalOverRed : AppColors.textMuted,
                fontWeight: isOver ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 요약 카드의 주인공 숫자: 순칼로리(가장 크게).
class _NetCalories extends StatelessWidget {
  final String label;
  final double value;
  const _NetCalories({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.balance, size: 16, color: AppColors.textMuted),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
              ),
            ),
          ],
        ),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.centerStart,
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: value.toStringAsFixed(0),
                  style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800, height: 1.15),
                ),
                const TextSpan(
                  text: ' kcal',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// 순칼로리 아래의 보조 숫자(섭취·소모). 아이콘과 숫자에 카테고리 색을 입힌다.
class _SubStat extends StatelessWidget {
  final IconData icon;
  final String label;
  final double value;
  final Color iconColor;
  final Color valueColor;

  const _SubStat({
    required this.icon,
    required this.label,
    required this.value,
    required this.iconColor,
    required this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: iconColor),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
            ),
          ],
        ),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.centerStart,
          child: Text(
            value.toStringAsFixed(0),
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: valueColor),
          ),
        ),
      ],
    );
  }
}
