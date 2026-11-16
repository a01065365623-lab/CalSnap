import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../models/micro_nutrient.dart';
import '../services/micro_nutrient_db.dart';
import '../theme/app_colors.dart';

String microNutrientLabel(AppLocalizations l10n, MicroNutrient n) => switch (n) {
      MicroNutrient.vitaminD => l10n.microNutrientVitaminD,
      MicroNutrient.vitaminB12 => l10n.microNutrientVitaminB12,
      MicroNutrient.vitaminA => l10n.microNutrientVitaminA,
      MicroNutrient.vitaminC => l10n.microNutrientVitaminC,
      MicroNutrient.iron => l10n.microNutrientIron,
      MicroNutrient.calcium => l10n.microNutrientCalcium,
      MicroNutrient.zinc => l10n.microNutrientZinc,
      MicroNutrient.potassium => l10n.microNutrientPotassium,
    };

/// 1일 기준치 대비 비율(%), 0 이상. 기준치가 없으면 null.
double? microNutrientPercent(MicroNutrient n, double amount) {
  final reference = microNutrientDailyReference[n];
  if (reference == null || reference <= 0) return null;
  final pct = amount / reference * 100;
  return pct.isFinite && pct > 0 ? pct : 0;
}

/// 섭취량 표시: 10 미만은 소수점 한 자리, 그 이상은 정수.
String formatMicroAmount(double amount) => amount < 10 ? amount.toStringAsFixed(1) : amount.toStringAsFixed(0);

/// 오늘의 로그 "비타민·미네랄" 카드. 8개 항목을 2열로, 1일 기준치 대비 막대와 %로 보여준다.
/// 계산할 음식이 없으면 "정보 없음", 영양 정보를 못 붙인 음식이 있으면 그 개수를 알린다.
class MicroNutrientCard extends StatelessWidget {
  final MicroNutrientSummary summary;

  const MicroNutrientCard({super.key, required this.summary});

  static const _vitamins = {
    MicroNutrient.vitaminD,
    MicroNutrient.vitaminB12,
    MicroNutrient.vitaminA,
    MicroNutrient.vitaminC,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    const nutrients = MicroNutrient.values;

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.eco_outlined, size: 18, color: AppColors.weightTealStrong),
                const SizedBox(width: 6),
                Expanded(child: Text(l10n.microNutrientCardTitle, style: theme.textTheme.titleSmall)),
              ],
            ),
            const SizedBox(height: 12),
            if (!summary.hasData)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  l10n.microNutrientNoData,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 14, color: AppColors.textMuted),
                ),
              )
            else
              for (var i = 0; i < nutrients.length; i += 2) ...[
                if (i > 0) const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _tile(l10n, nutrients[i])),
                    const SizedBox(width: 12),
                    Expanded(child: i + 1 < nutrients.length ? _tile(l10n, nutrients[i + 1]) : const SizedBox()),
                  ],
                ),
              ],
            if (summary.hasData && summary.approxCount > 0) ...[
              const SizedBox(height: 12),
              _Notice(text: l10n.microNutrientApproxNote),
            ],
            if (summary.unmatchedCount > 0) ...[
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline, size: 14, color: AppColors.textMuted),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      l10n.microNutrientUnmatchedMeals(summary.unmatchedCount),
                      style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 10),
            Text(l10n.microNutrientBasisNote, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
            const SizedBox(height: 2),
            Text(l10n.microNutrientDisclaimer, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
          ],
        ),
      ),
    );
  }

  Widget _tile(AppLocalizations l10n, MicroNutrient n) {
    final isVitamin = _vitamins.contains(n);
    return MicroNutrientTile(
      label: microNutrientLabel(l10n, n),
      unit: n.unit,
      amount: summary.totals[n],
      percent: summary.totals[n] == null ? null : microNutrientPercent(n, summary.totals[n]!),
      noDataLabel: l10n.microNutrientNoData,
      barColor: isVitamin ? AppColors.goalOrange : AppColors.waterBlue,
      trackColor: isVitamin ? AppColors.goalOrangeBg : AppColors.waterBlueBg,
    );
  }
}

class _Notice extends StatelessWidget {
  final String text;
  const _Notice({required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.info_outline, size: 14, color: AppColors.textMuted),
        const SizedBox(width: 4),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 12, color: AppColors.textMuted))),
      ],
    );
  }
}

class MicroNutrientTile extends StatelessWidget {
  final String label;
  final String unit;
  final double? amount;
  final double? percent;
  final String noDataLabel;
  final Color barColor;
  final Color trackColor;

  const MicroNutrientTile({
    super.key,
    required this.label,
    required this.unit,
    required this.amount,
    required this.percent,
    required this.noDataLabel,
    required this.barColor,
    required this.trackColor,
  });

  @override
  Widget build(BuildContext context) {
    final value = amount;
    final pct = percent;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.statsGray),
        ),
        const SizedBox(height: 2),
        if (value == null)
          Text(noDataLabel, maxLines: 2, style: const TextStyle(fontSize: 12, color: AppColors.textMuted))
        else ...[
          Row(
            children: [
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: Text('${formatMicroAmount(value)} $unit', style: const TextStyle(fontSize: 13)),
                ),
              ),
              if (pct != null) ...[
                const SizedBox(width: 4),
                Text(
                  '${pct.round()}%',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textMuted),
                ),
              ],
            ],
          ),
          if (pct != null) ...[
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: (pct / 100).clamp(0.0, 1.0),
                minHeight: 6,
                color: barColor,
                backgroundColor: trackColor,
              ),
            ),
          ],
        ],
      ],
    );
  }
}
