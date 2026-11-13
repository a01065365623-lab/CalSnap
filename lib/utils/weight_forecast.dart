import '../models/daily_log_entry.dart';

/// 체지방 1kg ≈ 7700kcal로 보는 흔한 근사치. 실제 체중 변화(수분·근육 등)와는
/// 다를 수 있어서 화면에는 항상 "추정치" 안내를 같이 보여준다.
const double kcalPerKgBodyWeight = 7700;

/// 예상 계산에 쓰는 기간(일). 오늘은 아직 끝나지 않은 날이라 넣지 않고, 어제까지의
/// 7일을 본다(오늘을 넣으면 아침에는 순칼로리가 낮게 잡혀 감량이 과장된다).
const int weightForecastWindowDays = 7;

/// 이보다 기록한 날이 적으면 평균이 의미가 없어서 예상치를 보여주지 않는다.
const int weightForecastMinRecordedDays = 3;

class WeeklyWeightForecast {
  /// 기간 내 음식 섭취 기록이 있는 날 수.
  final int recordedDays;

  /// 기록한 날들의 일평균 순칼로리. 기록이 부족하면 null.
  final double? averageNetCalories;

  /// 목표(유지) 칼로리 대비 일평균 순칼로리 차이를 7일치로 환산한 주간 체중 변화(kg).
  /// 음수면 감량, 양수면 증량. 기록이 부족하면 null.
  final double? weeklyChangeKg;

  const WeeklyWeightForecast({
    required this.recordedDays,
    this.averageNetCalories,
    this.weeklyChangeKg,
  });

  bool get hasEnoughData => weeklyChangeKg != null;
}

/// [today] 전날까지 [weightForecastWindowDays]일의 일별 요약으로 주간 체중 변화를
/// 추정한다. 섭취 기록이 없는 날(물만 마셨거나 기록을 다 지운 날 포함)은 평균에서
/// 빼서, 기록을 빼먹은 날이 "0kcal 먹은 날"로 계산돼 감량이 부풀려지지 않게 한다.
WeeklyWeightForecast estimateWeeklyWeightChange({
  required Iterable<DailySummary> summaries,
  required double targetCalories,
  required DateTime today,
}) {
  final todayKey = _dateKey(today);
  final firstKey = _dateKey(DateTime(today.year, today.month, today.day - weightForecastWindowDays));

  final netByDate = <String, double>{};
  for (final s in summaries) {
    if (s.totalIntake <= 0) continue;
    if (s.date.compareTo(firstKey) < 0 || s.date.compareTo(todayKey) >= 0) continue;
    netByDate[s.date] = s.netCalories;
  }

  final days = netByDate.length;
  if (days < weightForecastMinRecordedDays) return WeeklyWeightForecast(recordedDays: days);

  final average = netByDate.values.reduce((a, b) => a + b) / days;
  final weeklyKg = (average - targetCalories) * 7 / kcalPerKgBodyWeight;
  return WeeklyWeightForecast(recordedDays: days, averageNetCalories: average, weeklyChangeKg: weeklyKg);
}

String _dateKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
