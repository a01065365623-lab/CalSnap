import 'dart:math';

import '../db/database_helper.dart';
import '../models/daily_log_entry.dart';
import '../models/exercise_type.dart';

/// 시드로 생성한 로그 이름 앞에 붙이는 표시자.
/// [clearSeedData]가 이 접두사로 시작하는 항목만 골라 지워서 실제 기록은 건드리지 않는다.
const String seedTag = '[SEED]';

const List<String> _foodNames = [
  '김치찌개',
  '된장찌개',
  '제육볶음',
  '비빔밥',
  '닭가슴살 샐러드',
  '라면',
  '초밥 세트',
  '토마토 파스타',
  '삼겹살',
  '김밥',
  '떡볶이',
  '순두부찌개',
  '치킨',
  '불고기 정식',
  '샌드위치',
];

/// 오늘로부터 과거 [days]일치 더미 DailyLogEntry를 생성해 한 번에 삽입한다.
/// 하루 2~4건, 음식(+kcal)과 운동(-kcal)을 섞어서 만들고 사진 데이터는 없다.
Future<int> seedOneYearOfLogs({int days = 365}) async {
  final random = Random(42); // 재현 가능하도록 고정 시드 사용
  final today = DateTime.now();
  final entries = <DailyLogEntry>[];

  for (int i = 0; i < days; i++) {
    final date = today.subtract(Duration(days: i));
    final entryCount = 2 + random.nextInt(3); // 2~4건

    for (int j = 0; j < entryCount; j++) {
      final hour = (7 + j * 5 + random.nextInt(3)).clamp(0, 23);
      final minute = random.nextInt(60);
      final datetime = DateTime(date.year, date.month, date.day, hour, minute);

      // 마지막 슬롯은 절반 확률로 운동, 나머지는 항상 음식.
      final isExercise = j == entryCount - 1 && random.nextBool();

      if (isExercise) {
        final exercise = exerciseTypes[random.nextInt(exerciseTypes.length)];
        final minutes = 15 + random.nextInt(46); // 15~60분
        final calories = calculateCaloriesBurned(
          met: exercise.met,
          weightKg: defaultWeightKg,
          minutes: minutes,
        );
        entries.add(DailyLogEntry(
          datetime: datetime,
          type: LogType.exercise,
          name: '$seedTag ${exercise.emoji} ${exercise.id}',
          calories: -calories,
          amount: minutes.toDouble(),
        ));
      } else {
        final foodName = _foodNames[random.nextInt(_foodNames.length)];
        final calories = (250 + random.nextInt(650)).toDouble(); // 250~900kcal
        entries.add(DailyLogEntry(
          datetime: datetime,
          type: LogType.food,
          name: '$seedTag $foodName',
          calories: calories,
          mode: random.nextBool() ? LogMode.quick : LogMode.precision,
        ));
      }
    }
  }

  await DatabaseHelper.instance.insertLogsBulk(entries);
  return entries.length;
}

/// [seedOneYearOfLogs]가 만든 항목만 골라서 삭제한다. 실제 기록은 영향받지 않는다.
Future<int> clearSeedData() async {
  return DatabaseHelper.instance.deleteLogsWhereNameStartsWith(seedTag);
}
