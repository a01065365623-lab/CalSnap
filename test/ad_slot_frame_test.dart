import 'package:calsnap/theme/app_colors.dart';
import 'package:calsnap/widgets/banner_ad_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('광고 위아래 구분선 + 아래 콘텐츠와 간격, 320px에서 넘치지 않음', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const adKey = Key('ad');
    const contentKey = Key('content');
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            AdSlotFrame(child: SizedBox(key: adKey, width: 320, height: 50)),
            SizedBox(key: contentKey, height: 10, width: 100),
          ],
        ),
      ),
    ));
    expect(tester.takeException(), isNull);

    final dividers = tester.widgetList<Divider>(find.byType(Divider)).toList();
    expect(dividers, hasLength(2));
    expect(dividers.every((d) => d.color == AppColors.adDivider), isTrue);

    final ad = tester.getRect(find.byKey(adKey));
    final top = tester.getRect(find.byType(Divider).first);
    final bottom = tester.getRect(find.byType(Divider).last);
    final content = tester.getRect(find.byKey(contentKey));
    expect(top.bottom, lessThanOrEqualTo(ad.top));
    expect(bottom.top, greaterThanOrEqualTo(ad.bottom));
    expect(content.top - bottom.bottom, AdSlotFrame.bottomGap);
  });
}
