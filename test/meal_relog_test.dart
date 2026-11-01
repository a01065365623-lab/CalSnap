import 'package:calsnap/models/daily_log_entry.dart';
import 'package:calsnap/services/meal_log_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('relogEntry: 같은 음식·양·영양으로 새 시각에, 출처는 myFood', () {
    final original = DailyLogEntry(
      id: 42,
      datetime: DateTime(2026, 10, 20, 12, 30),
      type: LogType.food,
      name: '비빔밥',
      calories: 560,
      amount: 400,
      mode: LogMode.precision,
      carbsG: 80,
      proteinG: 18,
      fatG: 15,
      source: LogSource.photo,
      photoPath: '/photos/meal_old.jpg',
    );
    final at = DateTime(2026, 11, 1, 9);
    final copy = relogEntry(original, at, '/photos/meal_new.jpg');

    expect(copy.id, isNull, reason: '새 기록으로 저장');
    expect(copy.datetime, at);
    expect(copy.type, LogType.food);
    expect(copy.name, '비빔밥');
    expect(copy.calories, 560);
    expect(copy.amount, 400);
    expect(copy.mode, LogMode.precision);
    expect([copy.carbsG, copy.proteinG, copy.fatG], [80, 18, 15]);
    expect(copy.source, LogSource.myFood, reason: 'AI 인식 없이 다시 기록한 항목');
    expect(copy.photoPath, '/photos/meal_new.jpg', reason: '원본 사진이 아니라 복사본');
    expect(copy.toMap()['source'], 'myFood');
  });

  test('relogEntry: 사진 없는 직접 입력 기록도 myFood로', () {
    final copy = relogEntry(
      DailyLogEntry(
        datetime: DateTime(2026, 10, 20),
        type: LogType.food,
        name: 'apple',
        calories: 95,
        source: LogSource.manual,
      ),
      DateTime(2026, 11, 1),
      null,
    );
    expect(copy.source, LogSource.myFood);
    expect(copy.photoPath, isNull);
    expect(copy.mode, LogMode.quick);
  });
}
