import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../theme/app_colors.dart';

/// 빠른 측정 결과 아래에 붙는 작은 안내 한 줄: "사진 인식은 AI 비용 때문에 하루 N회
/// 무료예요. 직접 입력은 계속 무료예요." 팝업이 아니라 결과 흐름 안의 텍스트이고,
/// 오른쪽 X로 닫을 수 있다.
class PhotoQuotaNotice extends StatelessWidget {
  final int dailyLimit;
  final VoidCallback onDismiss;

  const PhotoQuotaNotice({super.key, required this.dailyLimit, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      padding: const EdgeInsets.only(left: 10),
      decoration: BoxDecoration(
        color: AppColors.statsGrayBg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 16, color: AppColors.statsGray),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              l10n.quickModePhotoQuotaNotice(dailyLimit),
              style: const TextStyle(fontSize: 12, color: AppColors.statsGray),
            ),
          ),
          IconButton(
            onPressed: onDismiss,
            tooltip: l10n.quickModePhotoQuotaNoticeDismiss,
            icon: const Icon(Icons.close, size: 16, color: AppColors.statsGray),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}
