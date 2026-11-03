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

  // 바텀시트는 루트 Navigator 아래에 뜨므로, 시트 안의 문구가 이 화면과 같은 언어로
  // 나오도록 호출한 위젯의 context에서 l10n을 미리 가져온다(Wedi에서 고친 방식과 동일).
  final l10n = AppLocalizations.of(context)!;
  final confirmed = await showModalBottomSheet<bool>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.shopLinkConfirmTitle, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 10),
            // 실제로 이동할 URL을 그대로 보여준다(쿠팡파트너스 심사 요건).
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(link.url, style: const TextStyle(fontSize: 13, color: Colors.black87)),
            ),
            const SizedBox(height: 10),
            // 제휴 링크 고지(수수료를 받을 수 있음).
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, size: 14, color: Colors.grey.shade600),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    l10n.shopAffiliateNotice,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: Text(l10n.cancelButton),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: Text(l10n.shopLinkGoButton),
                  ),
                ),
              ],
            ),
          ],
        ),
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
