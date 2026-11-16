import 'package:calsnap/models/daily_log_entry.dart';
import 'package:calsnap/models/micro_nutrient.dart';
import 'package:calsnap/services/micro_nutrient_db.dart';
import 'package:calsnap/services/micro_nutrient_miss_log.dart';
import 'package:flutter_test/flutter_test.dart';

final db = MicroNutrientDb.fromJson({
  'foods': [
    {
      'ko': '쌀밥',
      'en': 'rice',
      'aliases': <String>[],
      'per100g': {for (final n in MicroNutrient.values) n.jsonKey: 1},
    },
  ],
});

DailyLogEntry meal(int? id, String name, {double? grams = 200}) => DailyLogEntry(
      id: id,
      datetime: DateTime(2026, 11, 16, 12),
      type: LogType.food,
      name: name,
      calories: 300,
      amount: grams,
    );

void main() {
  final log = MicroNutrientMissLog.instance;
  setUp(log.clear);

  test('이름 매칭 실패만 센다(양 없음·매칭 성공은 제외)', () {
    final s = summarizeMicroNutrients([
      meal(1, '김치찌개'),
      meal(2, '쌀밥'),
      meal(3, '쌀밥', grams: null),
      meal(4, '마라탕'),
    ], db);
    expect(s.nameMissEntries.map((e) => e.name), ['김치찌개', '마라탕']);
    expect(s.unmatchedCount, 3);
    expect(log.record(s), 2);
    expect(log.countOf('김치찌개'), 1);
    expect(log.countOf('쌀밥'), 0);
  });

  test('같은 기록 id는 화면을 다시 그려도 한 번만', () {
    final entries = [meal(10, '김치찌개'), meal(11, '김치찌개')];
    expect(recordMissesFromEntries(entries, db), 2);
    expect(recordMissesFromEntries(entries, db), 0);
    expect(recordMissesFromEntries([...entries, meal(12, ' 김치찌개 ')], db), 1);
    expect(log.countOf('김치찌개'), 3);
    expect(log.topMisses.first.key, '김치찌개');
  });

  test('id 없는 기록·빈 이름은 세지 않는다', () {
    expect(recordMissesFromEntries([meal(null, '마라탕'), meal(20, '   ')], db), 0);
  });

  test('이름 수는 상한까지만 기억(많이 나온 것 유지)', () {
    var id = 1000;
    for (var i = 0; i < 3; i++) {
      recordMissesFromEntries([meal(id++, '자주먹는음식')], db);
    }
    recordMissesFromEntries([for (var i = 0; i < MicroNutrientMissLog.maxNames + 50; i++) meal(id++, '음식$i')], db);
    expect(log.topMisses.length, MicroNutrientMissLog.maxNames);
    expect(log.countOf('자주먹는음식'), 3);
  });
}
