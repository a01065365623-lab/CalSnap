import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../services/affiliate_service.dart';
import '../services/user_profile_service.dart';
import '../theme/app_colors.dart';
import 'shop_button.dart';

String _platformLabel(AppLocalizations l10n, AffiliatePlatform platform) {
  switch (platform) {
    case AffiliatePlatform.coupang:
      return l10n.shopPlatformCoupang;
    case AffiliatePlatform.naver:
      return l10n.shopPlatformNaver;
    case AffiliatePlatform.amazon:
      return l10n.shopPlatformAmazon;
  }
}

IconData _platformIcon(AffiliatePlatform platform) {
  switch (platform) {
    case AffiliatePlatform.coupang:
      return Icons.local_shipping_outlined;
    case AffiliatePlatform.naver:
      return Icons.storefront_outlined;
    case AffiliatePlatform.amazon:
      return Icons.shopping_cart_outlined;
  }
}

/// "관련 상품 보기" 진입 버튼. 지역(AffiliateService.shoppingLinksFor)에 따라:
/// - 한국(앱 언어 한국어 또는 기기 지역 KR)이면 쿠팡/네이버 중 고르는 바텀시트를 먼저 보여준다.
/// - 그 외 지역이면 후보가 아마존 하나뿐이라 고르는 단계 없이 바로 확인 흐름으로 넘어간다.
///   kAmazonAffiliateEnabled가 false면 후보가 없으므로 버튼 자체를 그리지 않는다.
/// 두 경우 모두 실제 이동 URL을 보여주는 확인 바텀시트(confirmAndLaunchAffiliateLink)를
/// 거친 뒤에만 실제로 이동한다.
class RelatedProductsButton extends StatelessWidget {
  /// 검색어(음식/재료명)를 탭하는 시점에 읽어온다. 값을 문자열로 바로 받지 않고
  /// getter로 받는 이유: quick_mode_screen에서는 사용자가 이름 입력창을 직접
  /// 수정할 수 있는데, 그 컨트롤러가 매 입력마다 이 위젯을 다시 빌드시키지 않으므로
  /// build 시점 문자열은 오래된 값일 수 있다. 탭할 때 그때그때 읽어야 항상 최신
  /// 값(예: 사용자가 방금 수정한 이름)을 검색어로 쓸 수 있다.
  final String Function() queryBuilder;

  const RelatedProductsButton({super.key, required this.queryBuilder});

  @override
  Widget build(BuildContext context) {
    // 설정의 "제휴 쇼핑 추천 표시"를 끄면 즉시 숨긴다.
    return ValueListenableBuilder<bool>(
      valueListenable: UserProfileService.instance.affiliateEnabled,
      builder: (context, enabled, _) => enabled ? _buildButton(context) : const SizedBox.shrink(),
    );
  }

  Widget _buildButton(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    if (_linksFor(context, queryBuilder()).isEmpty) return const SizedBox.shrink();
    // 저장/닫기 버튼 등 기본 테마색 버튼들 사이에서 눈에 띄도록 코랄(음식 카테고리
    // 컬러)로 꽉 채운 버튼을 쓰고, 폭도 꽉 채워서 존재감을 키운다.
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: () => _onPressed(context),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.foodCoral,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        icon: const Icon(Icons.shopping_bag_outlined),
        label: Text(l10n.shopRelatedProductsButton, style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }

  /// 앱 언어(Localizations)와 기기 지역(국가 코드)으로 링크 후보를 고른다. 지원 언어
  /// 목록에는 국가 코드가 없어서, 지역은 기기 locale에서 직접 읽는다.
  static List<AffiliateLink> _linksFor(BuildContext context, String query) =>
      AffiliateService.instance.shoppingLinksFor(
        query: query,
        languageCode: Localizations.localeOf(context).languageCode,
        countryCode: WidgetsBinding.instance.platformDispatcher.locale.countryCode,
      );

  Future<void> _onPressed(BuildContext context) async {
    final links = _linksFor(context, queryBuilder());
    if (links.isEmpty) return;

    if (links.length == 1) {
      await confirmAndLaunchAffiliateLink(context, links.first);
      return;
    }

    final l10n = AppLocalizations.of(context)!;
    final selected = await showModalBottomSheet<AffiliateLink>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  l10n.shopPickPlatformTitle,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            ),
            for (final link in links)
              ListTile(
                leading: Icon(_platformIcon(link.platform)),
                title: Text(_platformLabel(l10n, link.platform)),
                onTap: () => Navigator.pop(ctx, link),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (selected == null || !context.mounted) return;
    await confirmAndLaunchAffiliateLink(context, selected);
  }
}
