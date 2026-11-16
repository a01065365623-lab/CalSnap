import 'package:calsnap/models/micro_nutrient.dart';
import 'package:calsnap/services/micro_nutrient_db.dart';
import 'package:calsnap/widgets/micro_nutrient_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

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

const withData = MicroNutrientSummary(
  totals: {
    MicroNutrient.vitaminD: 5, // 10µg 기준 → 50%
    MicroNutrient.vitaminB12: 4.8, // 2.4µg → 200%
    MicroNutrient.vitaminA: 210, // 30%
    MicroNutrient.vitaminC: 25,
    MicroNutrient.iron: 3, // 25%
    MicroNutrient.calcium: 1234.5,
    MicroNutrient.zinc: 2.55,
    // 칼륨: 매칭된 음식에 값이 없음 → 정보 없음
  },
  foodEntryCount: 4,
  unmatchedCount: 2,
);

void main() {
  final ko = lookupAppLocalizations(const Locale('ko'));

  test('기준치 대비 %와 표시 형식', () {
    expect(microNutrientPercent(MicroNutrient.vitaminD, 5), 50);
    expect(microNutrientPercent(MicroNutrient.calcium, 1400), 200);
    expect(microNutrientPercent(MicroNutrient.iron, 0), 0);
    expect(formatMicroAmount(2.55), '2.5');
    expect(formatMicroAmount(1234.5), '1235');
  });

  testWidgets('8개 항목 2열, % 막대, 값 없는 항목은 정보 없음, 미매칭 끼 수와 안내 문구', (tester) async {
    await pump(tester, const MicroNutrientCard(summary: withData));

    for (final n in MicroNutrient.values) {
      expect(find.text(microNutrientLabel(ko, n)), findsOneWidget);
    }
    expect(find.text('5.0 µg'), findsOneWidget);
    expect(find.text('50%'), findsOneWidget);
    expect(find.text('200%'), findsOneWidget);
    expect(find.text('1235 mg'), findsOneWidget);

    final bars = tester.widgetList<LinearProgressIndicator>(find.byType(LinearProgressIndicator)).toList();
    expect(bars, hasLength(7), reason: '칼륨은 값이 없어 막대 없음');
    expect(bars.first.value, 0.5);
    expect(bars[1].value, 1.0, reason: '100% 넘으면 막대는 꽉 참');

    expect(find.text(ko.microNutrientNoData), findsOneWidget);
    expect(find.text(ko.microNutrientUnmatchedMeals(2)), findsOneWidget);
    expect(find.text('2끼는 영양 정보가 없어요'), findsOneWidget);
    expect(find.text(ko.microNutrientBasisNote), findsOneWidget);
    expect(find.text(ko.microNutrientDisclaimer), findsOneWidget);

    // 2열: 비타민 D와 B12가 같은 줄
    final d = tester.getTopLeft(find.text(ko.microNutrientVitaminD));
    final b12 = tester.getTopLeft(find.text(ko.microNutrientVitaminB12));
    expect(d.dy, b12.dy);
    expect(b12.dx, greaterThan(d.dx));
  });

  testWidgets('비슷한 음식 값이 합산에 들어가면 안내 문구', (tester) async {
    await pump(
      tester,
      const MicroNutrientCard(
        summary: MicroNutrientSummary(
          totals: {MicroNutrient.iron: 2},
          foodEntryCount: 2,
          unmatchedCount: 0,
          approxCount: 1,
        ),
      ),
    );
    expect(find.text(ko.microNutrientApproxNote), findsOneWidget);
    expect(find.text('일부는 비슷한 음식 값으로 계산했어요.'), findsOneWidget);
  });

  testWidgets('비슷한 음식이 없으면 안내 없음', (tester) async {
    await pump(tester, const MicroNutrientCard(summary: withData));
    expect(find.text(ko.microNutrientApproxNote), findsNothing);
  });

  testWidgets('기록이 없으면 카드 전체가 정보 없음(미매칭 안내 없음)', (tester) async {
    await pump(
      tester,
      const MicroNutrientCard(summary: MicroNutrientSummary(totals: {}, foodEntryCount: 0, unmatchedCount: 0)),
    );
    expect(find.text(ko.microNutrientNoData), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.textContaining('끼는'), findsNothing);
    expect(find.text(ko.microNutrientDisclaimer), findsOneWidget);
  });

  testWidgets('전부 매칭 실패면 정보 없음 + N끼 안내', (tester) async {
    await pump(
      tester,
      const MicroNutrientCard(summary: MicroNutrientSummary(totals: {}, foodEntryCount: 3, unmatchedCount: 3)),
    );
    expect(find.text(ko.microNutrientNoData), findsOneWidget);
    expect(find.text('3끼는 영양 정보가 없어요'), findsOneWidget);
  });

  testWidgets('영어 복수형', (tester) async {
    final en = lookupAppLocalizations(const Locale('en'));
    expect(en.microNutrientUnmatchedMeals(1), '1 meal has no nutrition data');
    expect(en.microNutrientUnmatchedMeals(3), '3 meals have no nutrition data');
  });

  for (final locale in AppLocalizations.supportedLocales) {
    testWidgets('비타민·미네랄 카드 — ${locale.languageCode} 320px ×1.3 overflow 없음', (tester) async {
      const big = MicroNutrientSummary(
        totals: {
          MicroNutrient.vitaminD: 123.4,
          MicroNutrient.vitaminB12: 98.7,
          MicroNutrient.vitaminA: 76543,
          MicroNutrient.vitaminC: 1234,
          MicroNutrient.iron: 99.9,
          MicroNutrient.calcium: 99999,
          MicroNutrient.zinc: 88.8,
          MicroNutrient.potassium: 123456,
        },
        foodEntryCount: 30,
        unmatchedCount: 21,
        approxCount: 5,
      );
      await pump(tester, const MicroNutrientCard(summary: big), locale: locale);
      expect(tester.takeException(), isNull);
      await pump(
        tester,
        const MicroNutrientCard(summary: MicroNutrientSummary(totals: {}, foodEntryCount: 2, unmatchedCount: 2)),
        locale: locale,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
