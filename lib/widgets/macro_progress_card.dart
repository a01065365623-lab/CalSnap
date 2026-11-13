import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../models/daily_log_entry.dart';
import '../theme/app_colors.dart';
import '../utils/macro_targets.dart';

/// 그날 음식 기록들의 탄수화물/단백질/지방 합계. 각 항목의 값은 이미 실제 섭취량
/// 기준으로 환산되어 저장돼 있으므로(calories와 동일한 방식) 그대로 더하면 된다.
/// 운동/물 기록은 제외하고, 값이 없는(null) 과거 기록은 0으로 취급한다.
({double carbs, double protein, double fat}) sumMacros(Iterable<DailyLogEntry> entries) {
  double carbs = 0, protein = 0, fat = 0;
  for (final e in entries) {
    if (e.type != LogType.food) continue;
    carbs += e.carbsG ?? 0;
    protein += e.proteinG ?? 0;
    fat += e.fatG ?? 0;
  }
  return (carbs: carbs, protein: protein, fat: fat);
}

/// 탄단지를 영양소별 색 막대로 보여준다. 목표 칼로리가 있으면 [macroTargetsFor]의
/// 표시용 목표 대비 비율을 막대로 채우고("45 / 250g"), 없으면 섭취량만 보여준다.
/// 색은 통계 화면 매크로 비율 차트와 같은 계열(탄수화물 코랄·단백질 틸·지방 그레이)이다.
class MacroProgressCard extends StatelessWidget {
  final List<DailyLogEntry> entries;
  final double? goalCalories;

  const MacroProgressCard({super.key, required this.entries, required this.goalCalories});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final totals = sumMacros(entries);
    final targets = macroTargetsFor(goalCalories);

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          children: [
            MacroProgressRow(
              icon: Icons.grain,
              label: l10n.macroCarbsLabel,
              grams: totals.carbs,
              targetGrams: targets?.carbsG,
              barColor: AppColors.foodCoral,
              trackColor: AppColors.foodCoralBg,
              textColor: AppColors.foodCoralStrong,
            ),
            const SizedBox(height: 12),
            MacroProgressRow(
              icon: Icons.set_meal,
              label: l10n.macroProteinLabel,
              grams: totals.protein,
              targetGrams: targets?.proteinG,
              barColor: AppColors.exerciseTeal,
              trackColor: AppColors.exerciseTealBg,
              textColor: AppColors.exerciseTealStrong,
            ),
            const SizedBox(height: 12),
            MacroProgressRow(
              icon: Icons.opacity,
              label: l10n.macroFatLabel,
              grams: totals.fat,
              targetGrams: targets?.fatG,
              barColor: AppColors.statsGray,
              trackColor: AppColors.statsGrayBg,
              textColor: AppColors.statsGray,
            ),
          ],
        ),
      ),
    );
  }
}

class MacroProgressRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final double grams;
  final double? targetGrams;
  final Color barColor;
  final Color trackColor;
  final Color textColor;

  const MacroProgressRow({
    super.key,
    required this.icon,
    required this.label,
    required this.grams,
    required this.targetGrams,
    required this.barColor,
    required this.trackColor,
    required this.textColor,
  });

  /// 목표 대비 비율(막대 채움). 목표를 넘으면 막대는 꽉 찬 상태로 멈춘다.
  double? get progress {
    final target = targetGrams;
    if (target == null || target <= 0) return null;
    return (grams / target).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final target = targetGrams;
    final amount = target == null
        ? '${grams.toStringAsFixed(0)}g'
        : '${grams.toStringAsFixed(0)} / ${target.toStringAsFixed(0)}g';
    final value = progress;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: barColor),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textColor),
              ),
            ),
            const SizedBox(width: 8),
            Text(amount, style: const TextStyle(fontSize: 13, color: AppColors.textMuted)),
          ],
        ),
        if (value != null) ...[
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: value,
              minHeight: 8,
              color: barColor,
              backgroundColor: trackColor,
            ),
          ),
        ],
      ],
    );
  }
}
