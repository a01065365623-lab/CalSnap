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
      expect(find.text('1200'), findsOneWidget);
      final ring = tester.widget<CircularProgressIndicator>(find.byType(CircularProgressIndicator));
      expect(ring.value, closeTo(0.6, 1e-9));
      expect(ring.color, AppColors.foodCoral);
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
      expect(find.text('500'), findsNWidgets(2)); // 섭취 = 순칼로리
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
      '주간 예상 카드(기록 부족)',
      () => const WeeklyWeightForecastCard(forecast: notEnough, targetCalories: 2000, unitSystem: UnitSystem.metric),
    );
  });
}
