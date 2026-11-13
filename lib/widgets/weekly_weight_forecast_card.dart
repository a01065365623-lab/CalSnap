import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../theme/app_colors.dart';
import '../utils/unit_converter.dart';
import '../utils/weight_forecast.dart';

/// 주간 체중 변화를 부호가 붙은 체중 문자열("-0.5kg", "+1.1lb", "0.0kg")로 만든다.
/// 반올림 결과가 0이면 "-0.0" 같은 표시가 나오지 않게 부호를 뺀다.
String formatWeeklyWeightChange(double changeKg, UnitSystem unit) {
  final value = unit == UnitSystem.imperial ? kgToLb(changeKg) : changeKg;
  final suffix = unit == UnitSystem.imperial ? 'lb' : 'kg';
  final rounded = double.parse(value.toStringAsFixed(1));
  if (rounded == 0) return '0.0$suffix';
  final sign = rounded > 0 ? '+' : '-';
  return '$sign${rounded.abs().toStringAsFixed(1)}$suffix';
}

/// "체중 기록" 카드 아래에 붙는 주간 체중 변화 예상 카드. 계산은
/// [estimateWeeklyWeightChange]가 하고, 여기서는 결과만 보여준다.
class WeeklyWeightForecastCard extends StatelessWidget {
  final WeeklyWeightForecast forecast;
  final double targetCalories;
  final UnitSystem unitSystem;

  const WeeklyWeightForecastCard({
    super.key,
    required this.forecast,
    required this.targetCalories,
    required this.unitSystem,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final change = forecast.weeklyChangeKg;
    final theme = Theme.of(context);

    final IconData icon;
    if (change == null) {
      icon = Icons.insights_outlined;
    } else if (change < -0.05) {
      icon = Icons.trending_down;
    } else if (change > 0.05) {
      icon = Icons.trending_up;
    } else {
      icon = Icons.trending_flat;
    }

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              backgroundColor: AppColors.weightTealBg,
              child: Icon(icon, color: AppColors.weightTeal),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.weeklyForecastTitle, style: theme.textTheme.titleSmall),
                  const SizedBox(height: 4),
                  if (change == null) ...[
                    Text(
                      l10n.weeklyForecastNeedMoreData,
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      l10n.weeklyForecastNeedMoreDataHint(
                        weightForecastWindowDays,
                        weightForecastMinRecordedDays,
                        forecast.recordedDays,
                      ),
                      style: theme.textTheme.bodySmall,
                    ),
                  ] else ...[
                    Text(
                      forecast.exceedsDisplayCap
                          ? l10n.weeklyForecastValueOverCap(
                              formatWeeklyWeightChange(change.sign * weightForecastDisplayCapKg, unitSystem),
                            )
                          : l10n.weeklyForecastValue(formatWeeklyWeightChange(change, unitSystem)),
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      l10n.weeklyForecastBasis(
                        forecast.averageNetCalories!.round(),
                        targetCalories.round(),
                        forecast.recordedDays,
                      ),
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                  const SizedBox(height: 6),
                  Text(
                    l10n.weeklyForecastDisclaimer,
                    style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
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
