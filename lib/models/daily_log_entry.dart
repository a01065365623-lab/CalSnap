enum LogType { food, exercise, water }

enum LogMode { quick, precision }

class DailyLogEntry {
  final int? id;
  final DateTime datetime;
  final LogType type;
  final String name;
  final double calories; // food: +, exercise: -, water: 0
  final double? amount; // g, 분, ml 등
  final LogMode? mode; // food 전용, null 가능

  const DailyLogEntry({
    this.id,
    required this.datetime,
    required this.type,
    required this.name,
    required this.calories,
    this.amount,
    this.mode,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'datetime': datetime.toIso8601String(),
      'type': type.name,
      'name': name,
      'calories': calories,
      'amount': amount,
      'mode': mode?.name,
    };
  }

  factory DailyLogEntry.fromMap(Map<String, dynamic> map) {
    return DailyLogEntry(
      id: map['id'] as int?,
      datetime: DateTime.parse(map['datetime'] as String),
      type: LogType.values.byName(map['type'] as String),
      name: map['name'] as String,
      calories: (map['calories'] as num).toDouble(),
      amount: (map['amount'] as num?)?.toDouble(),
      mode: map['mode'] != null ? LogMode.values.byName(map['mode'] as String) : null,
    );
  }
}

class DailySummary {
  final String date; // yyyy-MM-dd
  final double totalIntake;
  final double totalBurned;
  double get netCalories => totalIntake - totalBurned;

  const DailySummary({
    required this.date,
    required this.totalIntake,
    required this.totalBurned,
  });
}
