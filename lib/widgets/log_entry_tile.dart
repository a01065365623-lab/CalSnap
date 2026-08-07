import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/daily_log_entry.dart';

class LogEntryTile extends StatelessWidget {
  final DailyLogEntry entry;
  final VoidCallback? onDelete;

  const LogEntryTile({super.key, required this.entry, this.onDelete});

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

  @override
  Widget build(BuildContext context) {
    final time = DateFormat('HH:mm').format(entry.datetime);
    return ListTile(
      leading: Icon(_icon),
      title: Text(entry.name),
      subtitle: Text(time),
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
