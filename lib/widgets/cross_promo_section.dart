import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/cross_promo.dart';

/// URL 실행 함수 시그니처(테스트에서 교체 가능). url_launcher의 launchUrl과 같다.
typedef UrlLauncher = Future<bool> Function(Uri uri, {LaunchMode mode});

/// Play 스토어 앱(market://)으로 먼저 열고, 실패하면 웹 스토어 페이지로 연다.
/// 둘 다 실패하면 false.
Future<bool> openPlayStoreListing(CrossPromoApp app, {UrlLauncher launcher = launchUrl}) async {
  try {
    if (await launcher(app.marketUri, mode: LaunchMode.externalNonBrowserApplication)) return true;
  } catch (_) {
    // Play 스토어 앱이 없는 기기 등: 웹 링크로 넘어간다.
  }
  try {
    return await launcher(app.webUri, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}

/// 설정 화면의 "K-Brain Games Lab 다른 앱" 섹션. 목록은 lib/config/cross_promo.dart.
class CrossPromoSection extends StatelessWidget {
  final List<CrossPromoApp> apps;

  CrossPromoSection({super.key, List<CrossPromoApp>? apps}) : apps = apps ?? visibleCrossPromoApps;

  @override
  Widget build(BuildContext context) {
    if (apps.isEmpty) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(
            l10n.crossPromoSectionTitle,
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey.shade700),
          ),
        ),
        for (final app in apps) _CrossPromoCard(app: app),
      ],
    );
  }
}

class _CrossPromoCard extends StatelessWidget {
  final CrossPromoApp app;
  const _CrossPromoCard({required this.app});

  Future<void> _open(BuildContext context) async {
    final opened = await openPlayStoreListing(app);
    if (!opened && context.mounted) {
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.settingsActionFailed(app.webUri.toString()))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.asset(app.iconAsset, width: 52, height: 52, fit: BoxFit.cover),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(app.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  Text(
                    app.tagline(l10n),
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => _open(context),
                    icon: const Icon(Icons.shop, size: 18),
                    label: Text(l10n.crossPromoViewOnPlayButton),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
