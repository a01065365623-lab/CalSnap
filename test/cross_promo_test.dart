import 'dart:io';

import 'package:calsnap/config/cross_promo.dart';
import 'package:calsnap/widgets/cross_promo_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher/url_launcher.dart';

CrossPromoApp get wedi => crossPromoApps.singleWhere((a) => a.packageName == 'com.wedi.app');

void main() {
  test('Wedi 항목의 스토어 링크와 아이콘이 맞고, 현재 앱(CalSnap)은 목록에서 빠진다', () {
    expect(wedi.marketUri.toString(), 'market://details?id=com.wedi.app');
    expect(wedi.webUri.toString(), 'https://play.google.com/store/apps/details?id=com.wedi.app');
    expect(wedi.iconAsset, 'assets/promo/wedi.png');
    expect(visibleCrossPromoApps.map((a) => a.packageName), isNot(contains(currentAppPackageName)));
  });

  test('음주일기장·카데일리가 활성 상태로 Wedi 뒤에 노출된다', () {
    expect(visibleCrossPromoApps.map((a) => a.packageName),
        ['com.wedi.app', 'com.kbraingames.drinkdiary', 'com.kbraingames.cardaily']);
    expect(crossPromoApps.where((a) => a.packageName == currentAppPackageName), isEmpty);
    final drink = crossPromoApps.singleWhere((a) => a.packageName == 'com.kbraingames.drinkdiary');
    final car = crossPromoApps.singleWhere((a) => a.packageName == 'com.kbraingames.cardaily');
    expect(drink.iconAsset, 'assets/promo/drinkdiary.png');
    expect(car.iconAsset, 'assets/promo/cardaily.png');
    expect(drink.webUri.toString(), 'https://play.google.com/store/apps/details?id=com.kbraingames.drinkdiary');
    expect(car.marketUri.toString(), 'market://details?id=com.kbraingames.cardaily');
    for (final app in crossPromoApps) {
      expect(File(app.iconAsset).existsSync(), isTrue, reason: '${app.iconAsset} 파일이 있어야 함');
    }
    expect(crossPromoApps.every((a) => a.enabled), isTrue);
  });

  test('14개 언어 모두 새 소개 문구가 비어 있지 않다', () {
    expect(AppLocalizations.supportedLocales, hasLength(14));
    for (final locale in AppLocalizations.supportedLocales) {
      final l10n = lookupAppLocalizations(locale);
      for (final app in visibleCrossPromoApps) {
        expect(app.tagline(l10n).trim(), isNotEmpty, reason: '${locale.languageCode} ${app.name}');
      }
    }
  });

  group('openPlayStoreListing', () {
    test('market:// 링크가 열리면 웹 링크는 열지 않는다', () async {
      final calls = <Uri>[];
      final ok = await openPlayStoreListing(wedi, launcher: (uri, {mode = LaunchMode.platformDefault}) async {
        calls.add(uri);
        return true;
      });
      expect(ok, isTrue);
      expect(calls, [wedi.marketUri]);
    });

    test('market:// 실행이 false거나 예외면 웹 스토어 링크로 연다', () async {
      for (final failMarket in <Future<bool> Function()>[() async => false, () async => throw Exception('no store')]) {
        final calls = <Uri>[];
        final ok = await openPlayStoreListing(wedi, launcher: (uri, {mode = LaunchMode.platformDefault}) {
          calls.add(uri);
          return uri.scheme == 'market' ? failMarket() : Future.value(true);
        });
        expect(ok, isTrue);
        expect(calls, [wedi.marketUri, wedi.webUri]);
      }
    });

    test('둘 다 실패하면 false', () async {
      final ok = await openPlayStoreListing(wedi, launcher: (uri, {mode = LaunchMode.platformDefault}) async => false);
      expect(ok, isFalse);
    });
  });

  testWidgets('설정 섹션에 Wedi·음주일기장·카데일리 카드(아이콘·이름·소개·스토어 버튼)가 그려진다', (tester) async {
    final l10n = lookupAppLocalizations(const Locale('ko'));
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('ko'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: ListView(children: [CrossPromoSection()])),
    ));
    await tester.pumpAndSettle();

    expect(find.text(l10n.crossPromoSectionTitle), findsOneWidget);
    expect(find.text('Wedi'), findsOneWidget);
    expect(find.text('DrinkDiary'), findsOneWidget);
    expect(find.text('CarDaily'), findsOneWidget);
    expect(find.text(l10n.crossPromoWediTagline), findsOneWidget);
    expect(find.text(l10n.crossPromoDrinkDiaryTagline), findsOneWidget);
    expect(find.text(l10n.crossPromoCarDailyTagline), findsOneWidget);
    expect(find.text(l10n.crossPromoViewOnPlayButton), findsNWidgets(3));
    final icons = tester.widgetList<Image>(find.byType(Image)).map((i) => (i.image as AssetImage).assetName);
    expect(icons, ['assets/promo/wedi.png', 'assets/promo/drinkdiary.png', 'assets/promo/cardaily.png']);
    expect(tester.takeException(), isNull, reason: '아이콘 에셋이 pubspec에 등록돼 있어야 함');
  });

  testWidgets('14개 언어, 좁은 화면(320px)·큰 글꼴(1.3배)에서도 카드 3개가 overflow 없이 그려진다', (tester) async {
    tester.view.physicalSize = const Size(320, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    for (final locale in AppLocalizations.supportedLocales) {
      await tester.pumpWidget(MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MediaQuery(
          data: const MediaQueryData(size: Size(320, 1600), textScaler: TextScaler.linear(1.3)),
          child: Scaffold(body: ListView(children: [CrossPromoSection()])),
        ),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '${locale.languageCode}에서 overflow 없어야 함');
      expect(find.byType(Card), findsNWidgets(3), reason: locale.languageCode);

      // 카드 사이 간격이 모두 같아야 한다(아래 여백 8 + 위 여백 4 = 12px).
      // Card 위젯 영역은 margin을 포함하므로, 실제로 보이는 카드 면(Material)으로 잰다.
      Finder surface(int i) =>
          find.descendant(of: find.byType(Card).at(i), matching: find.byType(Material)).first;
      final gaps = [
        for (var i = 0; i < 2; i++) tester.getTopLeft(surface(i + 1)).dy - tester.getBottomLeft(surface(i)).dy,
      ];
      expect(gaps, everyElement(moreOrLessEquals(12.0)), reason: locale.languageCode);
    }
  });
}
