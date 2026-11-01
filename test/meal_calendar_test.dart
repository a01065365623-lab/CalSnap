import 'package:calsnap/models/daily_log_entry.dart';
import 'package:calsnap/screens/meal_calendar_screen.dart';
import 'package:calsnap/widgets/food_photo_thumbnail.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

DailyLogEntry food(DateTime t, double kcal, {String? photo, LogType type = LogType.food}) => DailyLogEntry(
      datetime: t,
      type: type,
      name: 'meal',
      calories: kcal,
      photoPath: photo,
    );

Future<void> pumpCell(WidgetTester tester, MealCalendarDay? meals) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(width: 50, height: 62, child: MealCalendarDayCell(day: 5, meals: meals)),
          ),
        ),
      ),
    );

void main() {
  group('groupMealsByDay', () {
    test('음식 기록만 날짜별로 묶고, 첫 사진은 시간순 첫 사진 식사', () {
      final days = groupMealsByDay([
        food(DateTime(2026, 11, 3, 19), 600, photo: '/p/dinner.jpg'),
        food(DateTime(2026, 11, 3, 8), 300),
        food(DateTime(2026, 11, 3, 12), 500, photo: '/p/lunch.jpg'),
        food(DateTime(2026, 11, 3, 18), -200, type: LogType.exercise),
        food(DateTime(2026, 11, 3, 9), 0, type: LogType.water),
        food(DateTime(2026, 11, 4, 9), 250),
        food(DateTime(2026, 11, 5, 9), 0, type: LogType.water),
      ]);
      expect(days.keys, unorderedEquals(['2026-11-03', '2026-11-04']));

      final third = days['2026-11-03']!;
      expect(third.meals, hasLength(3));
      expect(third.firstPhotoPath, '/p/lunch.jpg');
      expect(third.photoCount, 2);
      expect(third.totalCalories, 1400);

      final fourth = days['2026-11-04']!;
      expect(fourth.firstPhotoPath, isNull, reason: '직접 입력만 한 날');
      expect(fourth.totalCalories, 250);
    });
  });

  group('MealCalendarDayCell', () {
    testWidgets('사진이 여러 장이면 썸네일 + 개수 배지', (tester) async {
      await pumpCell(
        tester,
        MealCalendarDay([
          food(DateTime(2026, 11, 5, 8), 300, photo: '/missing/a.jpg'),
          food(DateTime(2026, 11, 5, 12), 500, photo: '/missing/b.jpg'),
          food(DateTime(2026, 11, 5, 19), 600, photo: '/missing/c.jpg'),
        ]),
      );
      final thumb = tester.widget<FoodPhotoThumbnail>(find.byType(FoodPhotoThumbnail));
      expect(thumb.path, '/missing/a.jpg');
      expect(thumb.size, thumb.size.floorToDouble(), reason: '정수 크기라 cacheWidth가 칸마다 같다');
      expect(find.byKey(const ValueKey('meal-photo-count')), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('1400'), findsNothing, reason: '사진이 있으면 칼로리 숫자 대신 사진');
      expect(tester.takeException(), isNull);
    });

    testWidgets('사진이 한 장이면 배지 없음', (tester) async {
      await pumpCell(tester, MealCalendarDay([food(DateTime(2026, 11, 5, 8), 300, photo: '/missing/a.jpg')]));
      expect(find.byType(FoodPhotoThumbnail), findsOneWidget);
      expect(find.byKey(const ValueKey('meal-photo-count')), findsNothing);
    });

    testWidgets('직접 입력만 한 날은 칼로리 숫자만', (tester) async {
      await pumpCell(
        tester,
        MealCalendarDay([food(DateTime(2026, 11, 5, 8), 300), food(DateTime(2026, 11, 5, 12), 520)]),
      );
      expect(find.byType(FoodPhotoThumbnail), findsNothing);
      expect(find.text('820'), findsOneWidget);
    });

    testWidgets('기록 없는 날은 날짜만', (tester) async {
      await pumpCell(tester, null);
      expect(find.text('5'), findsOneWidget);
      expect(find.byType(FoodPhotoThumbnail), findsNothing);
    });
  });
}
