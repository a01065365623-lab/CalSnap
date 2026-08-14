import 'package:url_launcher/url_launcher.dart';

import '../config/affiliate_config.dart';

/// 쿠팡파트너스 / 네이버 / 아마존 어소시에이트 검색 딥링크 관리.
/// 웨디(com.wedi.app)에서 검증된 패턴을 그대로 이식: 링크가 화면에 실제 URL
/// 텍스트로 노출되지 않으면 쿠팡파트너스 심사에서 반려된 이력이 있어, 세 플랫폼
/// 모두 탭 시 실제 이동 URL을 보여주는 확인 바텀시트(위젯 쪽 confirmAndLaunchAffiliateLink)를
/// 거친 뒤에만 이동한다.
enum AffiliatePlatform { coupang, naver, amazon }

class AffiliateLink {
  final AffiliatePlatform platform;
  final String label; // 디버그/폴백용 설명. 실제 UI 라벨은 platform 기준으로 로케일에 맞게 표시한다.
  final String url; // 실제 딥링크(검색 결과 URL, 제휴 태그 포함)
  final bool requiresConfirm;

  const AffiliateLink({
    required this.platform,
    required this.label,
    required this.url,
    this.requiresConfirm = false,
  });

  factory AffiliateLink.coupang({required String label, required String url}) =>
      AffiliateLink(platform: AffiliatePlatform.coupang, label: label, url: url, requiresConfirm: true);

  factory AffiliateLink.naver({required String label, required String url}) =>
      AffiliateLink(platform: AffiliatePlatform.naver, label: label, url: url, requiresConfirm: true);

  factory AffiliateLink.amazon({required String label, required String url}) =>
      AffiliateLink(platform: AffiliatePlatform.amazon, label: label, url: url, requiresConfirm: true);
}

String _coupangSearchUrl(String query) => 'https://www.coupang.com/np/search?q=${Uri.encodeComponent(query)}';

String _naverSearchUrl(String query) =>
    'https://search.shopping.naver.com/search/all?query=${Uri.encodeComponent(query)}';

String _amazonSearchUrl(String query) =>
    'https://www.amazon.com/s?k=${Uri.encodeComponent(query)}&tag=${AffiliateConfig.amazonAssociateTag}';

class AffiliateService {
  AffiliateService._internal();
  static final AffiliateService instance = AffiliateService._internal();

  /// 기기 locale에 따라 쇼핑 제휴 링크 후보를 만든다.
  /// - 한국어(ko): 쿠팡 + 네이버 두 곳 중에서 고를 수 있게 반환.
  /// - 그 외 언어: 아마존 검색 링크 하나만 반환(선택 단계 없이 바로 확인 후 이동).
  List<AffiliateLink> shoppingLinksFor({required String query, required String languageCode}) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];

    if (languageCode == 'ko') {
      return [
        AffiliateLink.coupang(label: 'Coupang', url: _coupangSearchUrl(trimmed)),
        AffiliateLink.naver(label: 'Naver', url: _naverSearchUrl(trimmed)),
      ];
    }
    return [AffiliateLink.amazon(label: 'Amazon', url: _amazonSearchUrl(trimmed))];
  }

  Future<void> launch(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw Exception('링크를 열 수 없습니다: $url');
    }
  }
}
