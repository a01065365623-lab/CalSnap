import 'package:flutter/material.dart';

import '../services/affiliate_service.dart';

/// 웨디의 _ShopBtn 패턴 이식.
/// 쿠팡 링크는 confirmLink 바텀시트("이동할 링크")를 거쳐야 파트너스 심사에 통과함.
class ShopButton extends StatelessWidget {
  final AffiliateLink link;
  final AffiliateService service;

  const ShopButton({super.key, required this.link, required this.service});

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: () => link.requiresConfirm ? _showConfirmSheet(context) : service.launch(link.url),
      child: Text(link.label),
    );
  }

  void _showConfirmSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('이동할 링크', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            Text(link.url, style: const TextStyle(color: Colors.blueGrey)),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    service.launch(link.url);
                  },
                  child: const Text('이동'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
