// 오늘의 로그 화면 카드들의 동작 + 레이아웃 테스트.
//
// overflow 테스트는 14개 언어 전부를 가장 좁은 기준 폭(320px)과 1.3배 글꼴로
// 그려서, RenderFlex overflow 같은 레이아웃 예외가 하나도 나지 않는지 본다.
// (DailyLogScreen 전체는 sqflite를 열어야 해서 위젯 테스트에서 띄울 수 없으므로,
// DB와 무관한 카드 위젯을 직접 그린다.)

import 'package:calsnap/models/daily_log_entry.dart';
import 'package:calsnap/theme/app_colors.dart';
import 'package:calsnap/widgets/daily_summary_card.dart';
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

DailySummary summary(double intake, double burned) =>
    DailySummary(date: '2026-11-14', totalIntake: intake, totalBurned: burned);

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
}
