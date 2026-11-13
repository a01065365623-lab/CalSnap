import 'package:calsnap/services/food_recognition_service.dart';
import 'package:calsnap/services/photo_quota_notice_service.dart';
import 'package:calsnap/widgets/photo_quota_notice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

RecognitionUsage photoUsage(int used, int limit) => RecognitionUsage(
      photo: UsageQuota(used: used, limit: limit, remaining: limit > 0 ? (limit - used).clamp(0, limit) : null),
    );

void main() {
  group('photoQuotaNoticeLimit', () {
    const today = '2026-11-14';

    test('오늘 두 번째 사진 인식부터 서버 한도를 돌려준다', () {
      expect(photoQuotaNoticeLimit(usage: photoUsage(1, 3), lastShownDate: null, today: today), isNull);
      expect(photoQuotaNoticeLimit(usage: photoUsage(2, 3), lastShownDate: null, today: today), 3);
      expect(photoQuotaNoticeLimit(usage: photoUsage(3, 3), lastShownDate: null, today: today), 3);
      expect(photoQuotaNoticeLimit(usage: photoUsage(2, 5), lastShownDate: null, today: today), 5,
          reason: 'N은 서버가 내려준 한도');
    });

    test('오늘 이미 보여줬거나 닫았으면 숨김, 어제 기록은 무시', () {
      expect(photoQuotaNoticeLimit(usage: photoUsage(2, 3), lastShownDate: today, today: today), isNull);
      expect(photoQuotaNoticeLimit(usage: photoUsage(2, 3), lastShownDate: '2026-11-13', today: today), 3);
    });

    test('한도 없음(무제한)·사용량 모름이면 안내 없음', () {
      expect(photoQuotaNoticeLimit(usage: photoUsage(2, 0), lastShownDate: null, today: today), isNull);
      expect(photoQuotaNoticeLimit(usage: null, lastShownDate: null, today: today), isNull);
      expect(photoQuotaNoticeLimit(usage: const RecognitionUsage(), lastShownDate: null, today: today), isNull);
    });
  });

  group('PhotoQuotaNoticeService', () {
    final day1 = DateTime(2026, 11, 14, 12);
    final day2 = DateTime(2026, 11, 15, 8);

    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('하루 1회: 보여준 뒤 같은 날 다음 결과에서는 안 보이고, 다음 날 다시 보인다', () async {
      final service = PhotoQuotaNoticeService.instance;
      expect(await service.takeNoticeLimitForToday(photoUsage(1, 3), now: day1), isNull);
      expect(await service.takeNoticeLimitForToday(photoUsage(2, 3), now: day1), 3);
      expect(await service.takeNoticeLimitForToday(photoUsage(3, 3), now: day1), isNull);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(PhotoQuotaNoticeService.keyLastShownDate), '2026-11-14');

      expect(await service.takeNoticeLimitForToday(photoUsage(2, 3), now: day2), 3);
    });

    test('닫으면 그날 날짜가 저장돼 다시 안 보인다', () async {
      final service = PhotoQuotaNoticeService.instance;
      await service.dismissForToday(now: day1);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(PhotoQuotaNoticeService.keyLastShownDate), '2026-11-14');
      expect(await service.takeNoticeLimitForToday(photoUsage(2, 3), now: day1), isNull);
    });

    test('안내 조건이 아니면 날짜를 남기지 않는다(첫 번째 결과)', () async {
      await PhotoQuotaNoticeService.instance.takeNoticeLimitForToday(photoUsage(1, 3), now: day1);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(PhotoQuotaNoticeService.keyLastShownDate), isNull);
    });
  });

  group('PhotoQuotaNotice', () {
    Future<void> pump(WidgetTester tester, Widget child, Locale locale) async {
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
        home: Scaffold(body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: child)),
      ));
      await tester.pump();
    }

    testWidgets('서버 한도 N을 넣은 문구 + X로 닫기', (tester) async {
      var dismissed = false;
      await pump(tester, PhotoQuotaNotice(dailyLimit: 3, onDismiss: () => dismissed = true), const Locale('ko'));
      expect(find.text('사진 인식은 AI 비용 때문에 하루 3회 무료예요. 직접 입력은 계속 무료예요.'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.close));
      expect(dismissed, isTrue);
    });

    for (final locale in AppLocalizations.supportedLocales) {
      testWidgets('안내 한 줄 — ${locale.languageCode} 320px ×1.3 overflow 없음', (tester) async {
        await pump(tester, PhotoQuotaNotice(dailyLimit: 3, onDismiss: () {}), locale);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
