import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../theme/app_colors.dart';

/// 오늘의 로그에 아직 기록이 없을 때 보여주는 영역. 안내 문구 아래에 큰 카메라
/// 버튼과 "직접 입력"/"최근 먹은 음식" 바로가기를 둔다. "최근 먹은 음식"은 저장된
/// 음식이 하나도 없으면 [onRecentFoods]를 null로 넘겨 숨긴다.
class DailyLogEmptyState extends StatelessWidget {
  final VoidCallback onCamera;
  final VoidCallback onManualEntry;
  final VoidCallback? onRecentFoods;

  const DailyLogEmptyState({
    super.key,
    required this.onCamera,
    required this.onManualEntry,
    this.onRecentFoods,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final shortcuts = [
      _ShortcutButton(icon: Icons.edit_note, label: l10n.quickModeManualEntryButton, onPressed: onManualEntry),
      if (onRecentFoods != null)
        _ShortcutButton(icon: Icons.history, label: l10n.quickModeRecentFoodsTitle, onPressed: onRecentFoods!),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        children: [
          Text(l10n.dailyLogEmptyToday, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onCamera,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.foodCoralStrong,
                foregroundColor: AppColors.onAccent,
                minimumSize: const Size.fromHeight(64),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              icon: const Icon(Icons.camera_alt, size: 28),
              label: Text(l10n.dailyLogEmptyCameraButton, textAlign: TextAlign.center),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (var i = 0; i < shortcuts.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(child: shortcuts[i]),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _ShortcutButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  const _ShortcutButton({required this.icon, required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.foodCoralStrong,
        side: const BorderSide(color: AppColors.foodCoral),
        minimumSize: const Size.fromHeight(48),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      ),
      icon: Icon(icon, size: 20),
      label: Text(label, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
    );
  }
}
