import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/daily_log_entry.dart';
import '../utils/unit_converter.dart';

class LogEntryTile extends StatelessWidget {
  final DailyLogEntry entry;
  final UnitSystem unitSystem;
  final VoidCallback? onDelete;

  const LogEntryTile({super.key, required this.entry, required this.unitSystem, this.onDelete});

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

  String get _calorieLabel {
    if (entry.type == LogType.water) return '';
    final sign = entry.calories >= 0 ? '+' : '';
    return '$sign${entry.calories.toStringAsFixed(0)} kcal';
  }

  /// 시각 옆에 운동 시간(분)/음식 중량(g 또는 oz)/물 양(ml) 등 운동량·섭취량을 덧붙여 보여준다.
  /// 음식 중량은 설정된 표시 단위([unitSystem])에 맞춰 변환해서 보여준다.
  String get _subtitle {
    final time = DateFormat('HH:mm').format(entry.datetime);
    final amount = entry.amount;
    if (amount == null) return time;
    final amountLabel = switch (entry.type) {
      LogType.food => formatWeight(amount, unitSystem),
      LogType.exercise => '${amount.toStringAsFixed(0)}분',
      LogType.water => '${amount.toStringAsFixed(0)}ml',
    };
    return '$time · $amountLabel';
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(_icon),
      title: Text(entry.name),
      subtitle: Text(_subtitle),
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
