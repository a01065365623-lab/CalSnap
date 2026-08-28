enum LogType { food, exercise, water }

enum LogMode { quick, precision }

/// 음식 기록이 사진(카메라/갤러리) 기반인지, 사진 없이 직접 입력했는지 구분한다.
/// food 전용 필드이며, exercise/water나 이 필드가 생기기 전(구버전) 기록은 null이다.
enum LogSource { photo, manual }

class DailyLogEntry {
  final int? id;
  final DateTime datetime;
  final LogType type;
  final String name;
  final double calories; // food: +, exercise: -, water: 0
  final double? amount; // g, 분, ml 등
  final LogMode? mode; // food 전용, null 가능
  // food 전용 영양소(g). calories와 마찬가지로 이미 실제 중량 기준으로 환산된
  // 절대값이다(100g당 값이 아님). exercise/water나 영양소 정보가 없던 과거 기록은 null.
  final double? carbsG;
  final double? proteinG;
  final double? fatG;
  final LogSource? source;

  const DailyLogEntry({
    this.id,
    required this.datetime,
    required this.type,
    required this.name,
    required this.calories,
    this.amount,
    this.mode,
    this.carbsG,
    this.proteinG,
    this.fatG,
    this.source,
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
      'carbsG': carbsG,
      'proteinG': proteinG,
      'fatG': fatG,
      'source': source?.name,
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
      carbsG: (map['carbsG'] as num?)?.toDouble(),
      proteinG: (map['proteinG'] as num?)?.toDouble(),
      fatG: (map['fatG'] as num?)?.toDouble(),
      source: map['source'] != null ? LogSource.values.byName(map['source'] as String) : null,
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

/// 하루치 운동(LogType.exercise) 기록 집계. 그 날 운동 기록이 없으면 결과에서 생략된다.
class ExerciseSummary {
  final String date; // yyyy-MM-dd
  final double caloriesBurned;
  final double minutes;

  const ExerciseSummary({
    required this.date,
    required this.caloriesBurned,
    required this.minutes,
  });
}

/// 하루치 음식(LogType.food) 탄단지(g) 합산. 그 날 음식 기록이 없으면 결과에서 생략된다.
class NutrientSummary {
  final String date; // yyyy-MM-dd
  final double carbsG;
  final double proteinG;
  final double fatG;

  const NutrientSummary({
    required this.date,
    required this.carbsG,
    required this.proteinG,
    required this.fatG,
  });
}

/// 사진과 함께 저장된 체중 기록 한 건(사진 비교 화면의 날짜 선택용).
class WeightPhotoRecord {
  final String date; // yyyy-MM-dd
  final double weightKg;
  final String photoPath;

  const WeightPhotoRecord({
    required this.date,
    required this.weightKg,
    required this.photoPath,
  });
}
