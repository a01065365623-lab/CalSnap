// 앱 스모크 테스트: 첫 실행 화면(온보딩)이 실제 다국어 리소스로 그려지고, 필수 입력을
// 채워야만 시작 버튼이 활성화되는지 확인한다.
//
// CalSnapApp 전체를 띄우지 않는 이유: 시작 게이트(_AppStartupGate)가 sqflite DB를
// 열 때까지 기다리는데, 위젯 테스트 환경에는 sqflite 플러그인이 없어 실패한다.
// 온보딩 화면은 SharedPreferences만 쓰므로 목(mock) 값으로 그대로 검증할 수 있다.

import 'package:calsnap/screens/onboarding_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('온보딩 화면이 한국어로 그려지고, 입력을 채워야 시작 버튼이 켜진다', (tester) async {
    final l10n = lookupAppLocalizations(const Locale('ko'));

    await tester.pumpWidget(const MaterialApp(
      locale: Locale('ko'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: OnboardingScreen(),
    ));
    await tester.pumpAndSettle();

    expect(find.text(l10n.onboardingIntro), findsOneWidget);
    expect(find.text(l10n.genderMale), findsOneWidget);
    expect(find.text(l10n.genderFemale), findsOneWidget);

    ElevatedButton startButton() => tester.widget<ElevatedButton>(
          find.ancestor(of: find.text(l10n.onboardingStartButton), matching: find.byType(ElevatedButton)),
        );
    expect(startButton().onPressed, isNull, reason: '아무것도 입력하지 않으면 시작할 수 없다');

    await tester.tap(find.text(l10n.genderFemale));
    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(3)); // 나이, 키, 체중
    await tester.enterText(fields.at(0), '30');
    await tester.enterText(fields.at(1), '165');
    await tester.enterText(fields.at(2), '58');
    await tester.pump();

    expect(startButton().onPressed, isNotNull, reason: '성별·나이·키·체중을 모두 채우면 시작할 수 있다');
  });
}
