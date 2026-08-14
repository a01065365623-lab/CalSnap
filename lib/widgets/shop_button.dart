import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../services/affiliate_service.dart';

/// 웨디의 _ShopBtn / confirmLink 패턴 이식.
/// 실제 이동 URL을 텍스트로 보여주는 확인 바텀시트를 반드시 거친 뒤에만 이동한다
/// (쿠팡파트너스는 이 흐름이 없으면 심사 반려된 이력이 있고, CalSnap에서는 네이버·
/// 아마존까지 모두 동일한 흐름으로 통일했다).
Future<void> confirmAndLaunchAffiliateLink(BuildContext context, AffiliateLink link) async {
  if (!link.requiresConfirm) {
    await _launch(context, link.url);
    return;
  }

  final l10n = AppLocalizations.of(context)!;
  final confirmed = await showModalBottomSheet<bool>(
    context: context,
    builder: (ctx) => Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.shopLinkConfirmTitle, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),
          Text(link.url, style: const TextStyle(color: Colors.blueGrey)),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l10n.cancelButton)),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(l10n.shopLinkGoButton),
              ),
            ],
          ),
        ],
      ),
    ),
  );
  if (confirmed != true || !context.mounted) return;
  await _launch(context, link.url);
}

Future<void> _launch(BuildContext context, String url) async {
  try {
    await AffiliateService.instance.launch(url);
  } catch (_) {
    if (context.mounted) {
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.shopLinkOpenFailed)));
    }
  }
}

/// 단일 제휴 링크 하나를 버튼으로 보여준다. 탭하면 [confirmAndLaunchAffiliateLink]
/// 흐름(필요 시 확인 바텀시트)을 거쳐 이동한다.
class ShopButton extends StatelessWidget {
  final AffiliateLink link;

  const ShopButton({super.key, required this.link});

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: () => confirmAndLaunchAffiliateLink(context, link),
      child: Text(link.label),
    );
  }
}
