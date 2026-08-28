import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:intl/intl.dart';

import '../models/daily_log_entry.dart';
import '../theme/app_colors.dart';
import '../utils/unit_converter.dart';

class LogEntryTile extends StatelessWidget {
  final DailyLogEntry entry;
  final UnitSystem unitSystem;
  final VoidCallback? onDelete;
  final VoidCallback? onTap;

  const LogEntryTile({
    super.key,
    required this.entry,
    required this.unitSystem,
    this.onDelete,
    this.onTap,
  });

  IconData get _icon {
    switch (entry.type) {
      case LogType.food:
        return Icons.restaurant;
      case LogType.exercise:
        return Icons.directions_run;
      case LogType.water:
        return Icons.water_drop;
    }
  }

  /// 항목 종류별 포인트 컬러: 음식=코랄, 운동=틸. 물은 카테고리 강조 대상이 아니라 중립 톤을 쓴다.
  Color get _iconColor {
    switch (entry.type) {
      case LogType.food:
        return AppColors.foodCoral;
      case LogType.exercise:
        return AppColors.exerciseTeal;
      case LogType.water:
        return Colors.blueGrey.shade400;
    }
  }

  Color get _iconBackground {
    switch (entry.type) {
      case LogType.food:
        return AppColors.foodCoralBg;
      case LogType.exercise:
        return AppColors.exerciseTealBg;
      case LogType.water:
        return Colors.blueGrey.shade50;
    }
  }

  String get _calorieLabel {
    if (entry.type == LogType.water) return '';
    final sign = entry.calories >= 0 ? '+' : '';
    return '$sign${entry.calories.toStringAsFixed(0)} kcal';
  }

  /// 시각 옆에 운동 시간(분)/음식 중량(g 또는 oz)/물 양(ml) 등 운동량·섭취량을 덧붙여 보여준다.
  /// 음식 중량은 설정된 표시 단위([unitSystem])에 맞춰 변환해서 보여준다.
  String _subtitle(AppLocalizations l10n) {
    final time = DateFormat('HH:mm').format(entry.datetime);
    final amount = entry.amount;
    if (amount == null) return time;
    final amountLabel = switch (entry.type) {
      LogType.food => formatWeight(amount, unitSystem),
      LogType.exercise => '${amount.toStringAsFixed(0)}${l10n.minutesSuffix}',
      LogType.water => '${amount.toStringAsFixed(0)}ml',
    };
    return '$time · $amountLabel';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ListTile(
      leading: Stack(
        clipBehavior: Clip.none,
        children: [
          CircleAvatar(
            backgroundColor: _iconBackground,
            foregroundColor: _iconColor,
            child: Icon(_icon, color: _iconColor),
          ),
          // 카메라로 찍은 기록과 구분할 수 있도록, 직접 입력한 기록에만 작은 편집
          // 아이콘 배지를 붙인다(사진 기반 기록은 배지 없음).
          if (entry.source == LogSource.manual)
            Positioned(
              right: -2,
              bottom: -2,
              child: Tooltip(
                message: l10n.manualEntrySourceLabel,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  child: const Icon(Icons.edit, size: 10, color: Colors.grey),
                ),
              ),
            ),
        ],
      ),
      title: Text(entry.name),
      subtitle: Text(_subtitle(l10n)),
      onTap: onTap,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_calorieLabel),
          if (onDelete != null)
            IconButton(icon: const Icon(Icons.close, size: 18), onPressed: onDelete),
        ],
      ),
    );
  }
}
