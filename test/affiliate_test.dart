import 'package:calsnap/config/affiliate_config.dart';
import 'package:calsnap/services/affiliate_service.dart';
import 'package:flutter_test/flutter_test.dart';

List<AffiliatePlatform> platforms(List<AffiliateLink> links) => links.map((l) => l.platform).toList();

void main() {
  final service = AffiliateService.instance;

  group('지역 분기', () {
    test('한국어 앱이면 쿠팡·네이버', () {
      final links = service.shoppingLinksFor(query: '김밥', languageCode: 'ko', countryCode: 'US');
      expect(platforms(links), [AffiliatePlatform.coupang, AffiliatePlatform.naver]);
    });

    test('앱 언어가 한국어가 아니어도 기기 지역이 KR이면 쿠팡·네이버', () {
      final links = service.shoppingLinksFor(query: 'kimbap', languageCode: 'en', countryCode: 'KR');
      expect(platforms(links), [AffiliatePlatform.coupang, AffiliatePlatform.naver]);
    });

    test('해외는 아마존 플래그가 꺼져 있으면 링크 없음(버튼 숨김)', () {
      final links = service.shoppingLinksFor(query: 'salad', languageCode: 'en', countryCode: 'US', amazonEnabled: false);
      expect(links, isEmpty);
    });

    test('해외는 아마존 플래그가 켜져 있으면 아마존 하나', () {
      final links = service.shoppingLinksFor(query: 'salad', languageCode: 'en', countryCode: 'US', amazonEnabled: true);
      expect(platforms(links), [AffiliatePlatform.amazon]);
      expect(links.single.url, startsWith('https://www.amazon.com/s?k=salad&tag='));
    });

    test('현재 출시 설정은 아마존 꺼짐(계정 비활성)', () {
      expect(kAmazonAffiliateEnabled, isFalse);
      expect(service.shoppingLinksFor(query: 'salad', languageCode: 'ja', countryCode: 'JP'), isEmpty);
    });

    test('검색어가 비어 있으면 링크 없음', () {
      expect(service.shoppingLinksFor(query: '   ', languageCode: 'ko'), isEmpty);
    });
  });

  test('모든 링크는 이동 전 확인 시트를 거친다', () {
    final all = [
      ...service.shoppingLinksFor(query: '김밥', languageCode: 'ko'),
      ...service.shoppingLinksFor(query: 'salad', languageCode: 'en', amazonEnabled: true),
    ];
    expect(all, hasLength(3));
    expect(all.every((l) => l.requiresConfirm), isTrue);
  });

  test('인식된 음식명을 앞뒤 공백 제거 후 URL 인코딩해 검색어로 쓴다', () {
    final links = service.shoppingLinksFor(query: ' 닭가슴살 샐러드&소스 ', languageCode: 'ko');
    const encoded = '%EB%8B%AD%EA%B0%80%EC%8A%B4%EC%82%B4%20%EC%83%90%EB%9F%AC%EB%93%9C%26%EC%86%8C%EC%8A%A4';
    expect(links[0].url, 'https://www.coupang.com/np/search?q=$encoded');
    expect(links[1].url, 'https://search.shopping.naver.com/search/all?query=$encoded');
  });
}
