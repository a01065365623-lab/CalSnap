import 'package:calsnap/models/daily_log_entry.dart';
import 'package:calsnap/theme/app_colors.dart';
import 'package:calsnap/utils/macro_targets.dart';
import 'package:calsnap/widgets/macro_progress_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

DailyLogEntry entry(LogType type, {double? c, double? p, double? f}) => DailyLogEntry(
      datetime: DateTime(2026, 11, 14, 12),
      type: type,
      name: 'x',
      calories: 0,
      carbsG: c,
      proteinG: p,
      fatG: f,
    );

Future<void> pump(WidgetTester tester, Widget child, {Locale locale = const Locale('ko')}) async {
  tester.view.physicalSize = const Size(320, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.3)),
      child: child!,
    ),
    home: Scaffold(body: SingleChildScrollView(child: child)),
  ));
  await tester.pump();
}

void main() {
  test('목표 칼로리 2000 → 탄 250g · 단 100g · 지 66.7g, 없거나 0이면 null', () {
    final t = macroTargetsFor(2000)!;
    expect(t.carbsG, 250);
    expect(t.proteinG, 100);
    expect(t.fatG, closeTo(66.67, 0.01));
    expect(macroTargetsFor(null), isNull);
    expect(macroTargetsFor(0), isNull);
  });

  test('합계는 음식 기록만, null은 0', () {
    final m = sumMacros([
      entry(LogType.food, c: 30, p: 10, f: 5),
      entry(LogType.food, c: 20),
      entry(LogType.exercise, c: 999),
      entry(LogType.water, p: 999),
    ]);
    expect(m.carbs, 50);
    expect(m.protein, 10);
    expect(m.fat, 5);
  });

  testWidgets('영양소별 색 막대가 목표 대비 비율로 채워지고, 넘으면 꽉 찬다', (tester) async {
    await pump(
      tester,
      MacroProgressCard(
        entries: [entry(LogType.food, c: 125, p: 120, f: 0)],
        goalCalories: 2000,
      ),
    );
    final bars = tester.widgetList<LinearProgressIndicator>(find.byType(LinearProgressIndicator)).toList();
    expect(bars, hasLength(3));
    expect(bars[0].value, 0.5);
    expect(bars[0].color, AppColors.foodCoral);
    expect(bars[1].value, 1.0, reason: '단백질 120/100g → 꽉 참');
    expect(bars[1].color, AppColors.exerciseTeal);
    expect(bars[2].value, 0);
    expect(bars[2].color, AppColors.statsGray);
    expect(find.text('125 / 250g'), findsOneWidget);
    expect(find.text('120 / 100g'), findsOneWidget);
    expect(find.text('0 / 67g'), findsOneWidget);
  });

  testWidgets('목표 칼로리가 없으면 막대 없이 섭취량만', (tester) async {
    await pump(tester, MacroProgressCard(entries: [entry(LogType.food, c: 40)], goalCalories: null));
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.text('40g'), findsOneWidget);
  });

  for (final locale in AppLocalizations.supportedLocales) {
    testWidgets('탄단지 막대 — ${locale.languageCode} 320px ×1.3 overflow 없음', (tester) async {
      await pump(
        tester,
        MacroProgressCard(entries: [entry(LogType.food, c: 1234, p: 567, f: 890)], goalCalories: 12345),
        locale: locale,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
