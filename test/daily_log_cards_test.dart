// 오늘의 로그 화면 카드들의 동작 + 레이아웃 테스트.
//
// overflow 테스트는 14개 언어 전부를 가장 좁은 기준 폭(320px)과 1.3배 글꼴로
// 그려서, RenderFlex overflow 같은 레이아웃 예외가 하나도 나지 않는지 본다.
// (DailyLogScreen 전체는 sqflite를 열어야 해서 위젯 테스트에서 띄울 수 없으므로,
// DB와 무관한 카드 위젯을 직접 그린다.)

import 'package:calsnap/models/daily_log_entry.dart';
import 'package:calsnap/theme/app_colors.dart';
import 'package:calsnap/utils/unit_converter.dart';
import 'package:calsnap/utils/weight_forecast.dart';
import 'package:calsnap/widgets/daily_log_empty_state.dart';
import 'package:calsnap/widgets/daily_summary_card.dart';
import 'package:calsnap/widgets/weekly_weight_forecast_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

const _narrowSize = Size(320, 640);
const _largeText = TextScaler.linear(1.3);

Future<void> pumpCard(WidgetTester tester, Widget child, {Locale locale = const Locale('ko')}) async {
  tester.view.physicalSize = _narrowSize;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: _largeText),
      child: child!,
    ),
    home: Scaffold(body: SingleChildScrollView(child: child)),
  ));
  await tester.pump();
}

/// 14개 언어 모두 320px·1.3배 글꼴에서 레이아웃 예외 없이 그려지는지 확인한다.
void expectNoOverflowInAllLocales(String description, Widget Function() build) {
  for (final locale in AppLocalizations.supportedLocales) {
    testWidgets('$description — ${locale.languageCode} 320px ×1.3 overflow 없음', (tester) async {
      await pumpCard(tester, build(), locale: locale);
      expect(tester.takeException(), isNull);
    });
  }
}

DailySummary summary(double intake, double burned, {String date = '2026-11-14'}) =>
    DailySummary(date: date, totalIntake: intake, totalBurned: burned);

void main() {
  group('goalProgressRatio', () {
    test('순칼로리/목표, 목표 없거나 0이면 null, 음수는 0', () {
      expect(goalProgressRatio(netCalories: 1000, goalCalories: 2000), 0.5);
      expect(goalProgressRatio(netCalories: 2500, goalCalories: 2000), 1.25);
      expect(goalProgressRatio(netCalories: -200, goalCalories: 2000), 0);
      expect(goalProgressRatio(netCalories: 1000, goalCalories: null), isNull);
      expect(goalProgressRatio(netCalories: 1000, goalCalories: 0), isNull);
    });
  });

  group('DailySummaryCard', () {
    final ko = lookupAppLocalizations(const Locale('ko'));

    testWidgets('목표 이하: 코랄 링 + 퍼센트, 기존 섭취/소모/순칼로리 숫자 유지', (tester) async {
      await pumpCard(tester, DailySummaryCard(summary: summary(1500, 300), goalCalories: 2000));

      expect(find.text('60%'), findsOneWidget);
      expect(find.text(ko.dailyLogGoalProgressLabel), findsOneWidget);
      expect(find.text('1500'), findsOneWidget);
      expect(find.text('300'), findsOneWidget);
      expect(find.text('1200 kcal'), findsOneWidget);
      final ring = tester.widget<CircularProgressIndicator>(find.byType(CircularProgressIndicator));
      expect(ring.value, closeTo(0.6, 1e-9));
      expect(ring.color, AppColors.foodCoral);
    });

    testWidgets('순칼로리가 가장 크고, 섭취는 코랄·소모는 틸 숫자 + 아이콘', (tester) async {
      await pumpCard(tester, DailySummaryCard(summary: summary(1500, 300), goalCalories: 2000));

      final intake = tester.widget<Text>(find.text('1500'));
      final burned = tester.widget<Text>(find.text('300'));
      expect(intake.style?.color, AppColors.foodCoralStrong);
      expect(burned.style?.color, AppColors.exerciseTealStrong);

      final netSize = tester.getSize(find.text('1200 kcal')).height;
      expect(netSize, greaterThan(tester.getSize(find.text('1500')).height));

      expect(find.byIcon(Icons.restaurant), findsOneWidget);
      expect(find.byIcon(Icons.local_fire_department), findsOneWidget);
      expect(find.byIcon(Icons.balance), findsOneWidget);
    });

    testWidgets('목표 초과: 링은 꽉 차고 주의색, 라벨은 "목표 초과"', (tester) async {
      await pumpCard(tester, DailySummaryCard(summary: summary(2600, 100), goalCalories: 2000));

      expect(find.text('125%'), findsOneWidget);
      expect(find.text(ko.dailyLogGoalOverLabel), findsOneWidget);
      final ring = tester.widget<CircularProgressIndicator>(find.byType(CircularProgressIndicator));
      expect(ring.value, 1.0);
      expect(ring.color, AppColors.goalOverRed);
    });

    testWidgets('목표가 없으면 링 없이 숫자만', (tester) async {
      await pumpCard(tester, DailySummaryCard(summary: summary(500, 0), goalCalories: null));
      expect(find.byType(GoalProgressRing), findsNothing);
      expect(find.text('500'), findsOneWidget); // 섭취
      expect(find.text('500 kcal'), findsOneWidget); // 순칼로리
    });

    expectNoOverflowInAllLocales(
      '요약 카드(목표 초과, 큰 숫자)',
      () => DailySummaryCard(summary: summary(12345, 2345), goalCalories: 2000),
    );
  });

  group('estimateWeeklyWeightChange', () {
    final today = DateTime(2026, 11, 14);

    test('일평균 순칼로리와 목표 차이 × 7 / 7700', () {
      final f = estimateWeeklyWeightChange(
        today: today,
        targetCalories: 2000,
        summaries: [
          summary(1600, 0, date: '2026-11-11'),
          summary(1500, 100, date: '2026-11-12'), // 순 1400
          summary(1500, 0, date: '2026-11-13'),
        ],
      );
      expect(f.recordedDays, 3);
      expect(f.averageNetCalories, 1500);
      expect(f.weeklyChangeKg, closeTo(-500 * 7 / 7700, 1e-9)); // ≈ -0.45kg
    });

    test('기록이 3일 미만이면 예상치 없음', () {
      final f = estimateWeeklyWeightChange(
        today: today,
        targetCalories: 2000,
        summaries: [summary(1600, 0, date: '2026-11-12'), summary(1700, 0, date: '2026-11-13')],
      );
      expect(f.hasEnoughData, isFalse);
      expect(f.recordedDays, 2);
    });

    test('오늘·7일보다 이전·섭취 0인 날(물만 기록)은 세지 않는다', () {
      final f = estimateWeeklyWeightChange(
        today: today,
        targetCalories: 2000,
        summaries: [
          summary(5000, 0, date: '2026-11-14'), // 오늘: 진행 중
          summary(5000, 0, date: '2026-11-06'), // 8일 전: 기간 밖
          summary(0, 0, date: '2026-11-12'), // 물만 마신 날
          summary(2000, 0, date: '2026-11-07'), // 7일 전: 기간 안 첫날
          summary(2300, 0, date: '2026-11-10'),
          summary(2400, 0, date: '2026-11-13'),
        ],
      );
      expect(f.recordedDays, 3);
      expect(f.averageNetCalories, closeTo(2233.33, 0.01));
      expect(f.weeklyChangeKg! > 0, isTrue);
    });

    test('섭취 500kcal 미만인 날은 평균에서 제외(500은 포함)', () {
      final f = estimateWeeklyWeightChange(
        today: today,
        targetCalories: 2000,
        summaries: [
          summary(499, 0, date: '2026-11-09'), // 제외
          summary(300, 0, date: '2026-11-10'), // 제외
          summary(500, 0, date: '2026-11-11'), // 경계: 포함
          summary(2000, 0, date: '2026-11-12'),
          summary(2600, 0, date: '2026-11-13'),
        ],
      );
      expect(f.recordedDays, 3);
      expect(f.averageNetCalories, closeTo(1700, 1e-9));
    });

    test('500kcal 미만인 날을 빼면 3일이 안 되면 기록 부족', () {
      final f = estimateWeeklyWeightChange(
        today: today,
        targetCalories: 2000,
        summaries: [
          summary(200, 0, date: '2026-11-11'),
          summary(1800, 0, date: '2026-11-12'),
          summary(1900, 0, date: '2026-11-13'),
        ],
      );
      expect(f.hasEnoughData, isFalse);
      expect(f.recordedDays, 2);
    });

    test('표시 상한: |변화| > 1.0kg일 때만', () {
      expect(const WeeklyWeightForecast(recordedDays: 3, averageNetCalories: 0, weeklyChangeKg: -1.2).exceedsDisplayCap, isTrue);
      expect(const WeeklyWeightForecast(recordedDays: 3, averageNetCalories: 0, weeklyChangeKg: 1.01).exceedsDisplayCap, isTrue);
      expect(const WeeklyWeightForecast(recordedDays: 3, averageNetCalories: 0, weeklyChangeKg: -1.0).exceedsDisplayCap, isFalse);
      expect(const WeeklyWeightForecast(recordedDays: 2).exceedsDisplayCap, isFalse);
    });

    test('월 경계도 날짜로 계산', () {
      final f = estimateWeeklyWeightChange(
        today: DateTime(2026, 12, 2),
        targetCalories: 2000,
        summaries: [
          summary(1800, 0, date: '2026-11-25'),
          summary(1800, 0, date: '2026-11-30'),
          summary(1800, 0, date: '2026-12-01'),
        ],
      );
      expect(f.recordedDays, 3);
    });
  });

  group('formatWeeklyWeightChange', () {
    test('부호·단위, 0은 부호 없이', () {
      expect(formatWeeklyWeightChange(-0.4545, UnitSystem.metric), '-0.5kg');
      expect(formatWeeklyWeightChange(0.31, UnitSystem.metric), '+0.3kg');
      expect(formatWeeklyWeightChange(-0.02, UnitSystem.metric), '0.0kg');
      expect(formatWeeklyWeightChange(-0.5, UnitSystem.imperial), '-1.1lb');
    });
  });

  group('WeeklyWeightForecastCard', () {
    final ko = lookupAppLocalizations(const Locale('ko'));
    const enough = WeeklyWeightForecast(recordedDays: 5, averageNetCalories: 1450, weeklyChangeKg: -0.5);
    const notEnough = WeeklyWeightForecast(recordedDays: 2);

    testWidgets('예상치 + 근거 + 추정치 안내', (tester) async {
      await pumpCard(
        tester,
        const WeeklyWeightForecastCard(forecast: enough, targetCalories: 2000, unitSystem: UnitSystem.metric),
      );
      expect(find.text('주 약 -0.5kg 예상'), findsOneWidget);
      expect(find.text(ko.weeklyForecastBasis(1450, 2000, 5)), findsOneWidget);
      expect(find.text(ko.weeklyForecastDisclaimer), findsOneWidget);
    });

    testWidgets('-1.0kg/주를 넘으면 "-1.0kg 이상"', (tester) async {
      await pumpCard(
        tester,
        const WeeklyWeightForecastCard(
          forecast: WeeklyWeightForecast(recordedDays: 4, averageNetCalories: 600, weeklyChangeKg: -1.27),
          targetCalories: 2000,
          unitSystem: UnitSystem.metric,
        ),
      );
      expect(find.text('주 -1.0kg 이상 예상'), findsOneWidget);
      expect(find.textContaining('1.3'), findsNothing, reason: '상한을 넘으면 실제 숫자는 보여주지 않는다');
    });

    testWidgets('+1.0kg/주를 넘으면 "+1.0kg 이상", imperial은 lb로', (tester) async {
      const over = WeeklyWeightForecast(recordedDays: 4, averageNetCalories: 3400, weeklyChangeKg: 1.27);
      await pumpCard(
        tester,
        const WeeklyWeightForecastCard(forecast: over, targetCalories: 2000, unitSystem: UnitSystem.metric),
      );
      expect(find.text('주 +1.0kg 이상 예상'), findsOneWidget);

      await pumpCard(
        tester,
        const WeeklyWeightForecastCard(forecast: over, targetCalories: 2000, unitSystem: UnitSystem.imperial),
      );
      expect(find.text('주 +2.2lb 이상 예상'), findsOneWidget);
    });

    testWidgets('정확히 -1.0kg이면 상한 표시 없이 그대로', (tester) async {
      await pumpCard(
        tester,
        const WeeklyWeightForecastCard(
          forecast: WeeklyWeightForecast(recordedDays: 4, averageNetCalories: 900, weeklyChangeKg: -1.0),
          targetCalories: 2000,
          unitSystem: UnitSystem.metric,
        ),
      );
      expect(find.text('주 약 -1.0kg 예상'), findsOneWidget);
    });

    testWidgets('기록 부족: "기록이 더 필요해요"', (tester) async {
      await pumpCard(
        tester,
        const WeeklyWeightForecastCard(forecast: notEnough, targetCalories: 2000, unitSystem: UnitSystem.metric),
      );
      expect(find.text(ko.weeklyForecastNeedMoreData), findsOneWidget);
      expect(find.text(ko.weeklyForecastNeedMoreDataHint(7, 3, 2)), findsOneWidget);
      expect(find.text(ko.weeklyForecastDisclaimer), findsOneWidget);
    });

    expectNoOverflowInAllLocales(
      '주간 예상 카드(예상치)',
      () => const WeeklyWeightForecastCard(forecast: enough, targetCalories: 2000, unitSystem: UnitSystem.imperial),
    );
    expectNoOverflowInAllLocales(
      '주간 예상 카드(±1.0kg 이상)',
      () => const WeeklyWeightForecastCard(
        forecast: WeeklyWeightForecast(recordedDays: 4, averageNetCalories: 600, weeklyChangeKg: -1.27),
        targetCalories: 2000,
        unitSystem: UnitSystem.imperial,
      ),
    );
    expectNoOverflowInAllLocales(
      '주간 예상 카드(기록 부족)',
      () => const WeeklyWeightForecastCard(forecast: notEnough, targetCalories: 2000, unitSystem: UnitSystem.metric),
    );
  });

  group('DailyLogEmptyState', () {
    final ko = lookupAppLocalizations(const Locale('ko'));

    testWidgets('큰 카메라 버튼 + 직접 입력 + 최근 먹은 음식, 각각 콜백 호출', (tester) async {
      final taps = <String>[];
      await pumpCard(
        tester,
        DailyLogEmptyState(
          onCamera: () => taps.add('camera'),
          onManualEntry: () => taps.add('manual'),
          onRecentFoods: () => taps.add('recent'),
        ),
      );
      expect(find.text(ko.dailyLogEmptyToday), findsOneWidget);

      await tester.tap(find.text(ko.dailyLogEmptyCameraButton));
      await tester.tap(find.text(ko.quickModeManualEntryButton));
      await tester.tap(find.text(ko.quickModeRecentFoodsTitle));
      expect(taps, ['camera', 'manual', 'recent']);

      final camera = tester.getSize(find.ancestor(
        of: find.text(ko.dailyLogEmptyCameraButton),
        matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
      ));
      expect(camera.height, greaterThanOrEqualTo(64), reason: '카메라 버튼은 크게');
    });

    testWidgets('저장된 음식이 없으면 "최근 먹은 음식" 숨김', (tester) async {
      await pumpCard(tester, DailyLogEmptyState(onCamera: () {}, onManualEntry: () {}));
      expect(find.text(ko.quickModeRecentFoodsTitle), findsNothing);
      expect(find.text(ko.quickModeManualEntryButton), findsOneWidget);
    });

    expectNoOverflowInAllLocales(
      '빈 화면 바로가기',
      () => DailyLogEmptyState(onCamera: () {}, onManualEntry: () {}, onRecentFoods: () {}),
    );
  });
}
