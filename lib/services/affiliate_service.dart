import 'package:url_launcher/url_launcher.dart';

/// 쿠팡파트너스 / 네이버 스마트스토어 / 아마존 어소시에이트 딥링크 관리.
/// 웨디(com.wedi.app)에서 검증된 패턴을 그대로 이식:
/// - 쿠팡: 링크가 화면에 텍스트로 노출되지 않으면 파트너스 심사 반려되므로,
///   탭 시 실제 URL을 보여주는 확인 바텀시트(confirmLink)를 거친다.
/// - 네이버/아마존: 확인 절차 없이 바로 이동.
enum AffiliatePlatform { coupang, naver, amazon }

class AffiliateLink {
  final AffiliatePlatform platform;
  final String label; // 예: "쿠팡에서 주방저울 보기"
  final String url; // 실제 딥링크 (제휴 태그 포함)
  final bool requiresConfirm; // 쿠팡은 true

  const AffiliateLink({
    required this.platform,
    required this.label,
    required this.url,
    this.requiresConfirm = false,
  });

  factory AffiliateLink.coupang({required String label, required String url}) =>
      AffiliateLink(platform: AffiliatePlatform.coupang, label: label, url: url, requiresConfirm: true);

  factory AffiliateLink.naver({required String label, required String url}) =>
      AffiliateLink(platform: AffiliatePlatform.naver, label: label, url: url);

  factory AffiliateLink.amazon({required String label, required String url}) =>
      AffiliateLink(platform: AffiliatePlatform.amazon, label: label, url: url);
}

class AffiliateService {
  /// requiresConfirm이 true면 호출부(위젯)에서 확인 바텀시트를 먼저 띄워야 함.
  /// (실제 바텀시트 UI는 widgets/shop_button.dart 참고)
  Future<void> launch(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw Exception('링크를 열 수 없습니다: $url');
    }
  }

  /// TODO: CalSnap 전용 제휴 태그로 교체
  /// - 쿠팡파트너스 채널ID, 네이버 제휴 파라미터, 아마존 Associates StoreID
  static const String coupangChannelId = 'YOUR_COUPANG_CHANNEL_ID';
  static const String amazonStoreId = 'YOUR_AMAZON_STORE_ID';

  /// 정밀모드 사용자에게 주방저울 등 추천 (사용 패턴 기반 추천 로직은 추후 구현)
  List<AffiliateLink> recommendationsFor({required bool usesPrecisionMode}) {
    final links = <AffiliateLink>[];
    if (usesPrecisionMode) {
      links.add(AffiliateLink.coupang(
        label: '쿠팡에서 주방저울 보기',
        url: 'https://link.coupang.com/a/REPLACE_ME',
      ));
    }
    return links;
  }
}
