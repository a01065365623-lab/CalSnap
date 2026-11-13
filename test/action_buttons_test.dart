import 'package:calsnap/theme/app_colors.dart';
import 'package:calsnap/widgets/action_buttons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> pumpButtons(WidgetTester tester, Locale locale, {List<String>? taps}) async {
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
    home: Builder(builder: (context) {
      final l10n = AppLocalizations.of(context)!;
      return Scaffold(
        body: const SizedBox.expand(),
        floatingActionButton: HomeActionButtons(
          exerciseLabel: l10n.homeExerciseFabLabel,
          statsTooltip: l10n.statsAppBarTitle,
          cameraLabel: l10n.homeCameraFabLabel,
          onExercise: () => taps?.add('exercise'),
          onStats: () => taps?.add('stats'),
          onCamera: () => taps?.add('camera'),
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      );
    }),
  ));
  await tester.pump();
}

Color? bg(WidgetTester tester, Finder button) =>
    tester.widget<FilledButton>(button).style?.backgroundColor?.resolve({});

void main() {
  testWidgets('운동·찍기만 강조색, 통계는 중립 톤 / 높이·그림자 통일 / 탭 동작 유지', (tester) async {
    final taps = <String>[];
    await pumpButtons(tester, const Locale('ko'), taps: taps);
    final ko = lookupAppLocalizations(const Locale('ko'));

    final buttons = find.byWidgetPredicate((w) => w is FilledButton);
    expect(buttons, findsNWidgets(3));
    expect(bg(tester, buttons.at(0)), AppColors.exerciseTealStrong);
    expect(bg(tester, buttons.at(1)), AppColors.neutralButtonBg);
    expect(bg(tester, buttons.at(2)), AppColors.foodCoralStrong);

    for (var i = 0; i < 3; i++) {
      // 보이는 버튼은 44, 터치 영역은 Material 기본값(48)으로 패딩된다.
      final visual = find.descendant(of: buttons.at(i), matching: find.byType(Material)).first;
      expect(tester.getSize(visual).height, ActionButtonMetrics.height);
      expect(tester.getSize(buttons.at(i)).height, greaterThanOrEqualTo(48));
      final style = tester.widget<FilledButton>(buttons.at(i)).style!;
      expect(style.elevation?.resolve({}), ActionButtonMetrics.elevation);
    }

    await tester.tap(find.text(ko.homeExerciseFabLabel));
    await tester.tap(find.byTooltip(ko.statsAppBarTitle));
    await tester.tap(find.text(ko.homeCameraFabLabel));
    expect(taps, ['exercise', 'stats', 'camera']);
  });

  for (final locale in AppLocalizations.supportedLocales) {
    testWidgets('하단 버튼 — ${locale.languageCode} 320px ×1.3 overflow 없음', (tester) async {
      await pumpButtons(tester, locale);
      expect(tester.takeException(), isNull);
      final row = tester.getRect(find.byType(HomeActionButtons));
      expect(row.left, greaterThanOrEqualTo(0));
      expect(row.right, lessThanOrEqualTo(320));
    });
  }
}
