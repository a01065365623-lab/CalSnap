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

  testWidgets('설정 섹션에 Wedi 카드(아이콘·이름·소개·스토어 버튼)가 그려진다', (tester) async {
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
    expect(find.text(l10n.crossPromoWediTagline), findsOneWidget);
    expect(find.text(l10n.crossPromoViewOnPlayButton), findsOneWidget);
    final icon = tester.widget<Image>(find.byType(Image));
    expect((icon.image as AssetImage).assetName, 'assets/promo/wedi.png');
    expect(tester.takeException(), isNull, reason: '아이콘 에셋이 pubspec에 등록돼 있어야 함');
  });
}
