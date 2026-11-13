import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// 하단 떠 있는 액션 버튼(운동/통계/찍기, 오늘의 로그의 물)이 공유하는 크기·모양·그림자.
/// 버튼마다 높이와 그림자가 달라 보이던 것을 한 군데에서 맞춘다.
class ActionButtonMetrics {
  ActionButtonMetrics._();

  static const double height = 44;
  static const double radius = 14;
  static const double elevation = 3;
  static const double gap = 10;
  static const double iconSize = 18;
}

ButtonStyle _actionStyle({required Color background, required Color foreground, EdgeInsetsGeometry? padding}) {
  return FilledButton.styleFrom(
    backgroundColor: background,
    foregroundColor: foreground,
    elevation: ActionButtonMetrics.elevation,
    shadowColor: AppColors.buttonShadow,
    minimumSize: const Size(ActionButtonMetrics.height, ActionButtonMetrics.height),
    maximumSize: const Size(double.infinity, ActionButtonMetrics.height),
    padding: padding ?? const EdgeInsets.symmetric(horizontal: 16),
    iconSize: ActionButtonMetrics.iconSize,
    textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ActionButtonMetrics.radius)),
  );
}

/// 아이콘 + 라벨 버튼(운동·찍기). 공간이 모자라면 라벨이 잘리지 않고 작아진다.
class ActionPillButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color background;
  final Color foreground;
  final VoidCallback onPressed;

  const ActionPillButton({
    super.key,
    required this.icon,
    required this.label,
    required this.background,
    required this.onPressed,
    this.foreground = AppColors.onAccent,
  });

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onPressed,
      style: _actionStyle(background: background, foreground: foreground),
      icon: Icon(icon),
      label: FittedBox(fit: BoxFit.scaleDown, child: Text(label, maxLines: 1)),
    );
  }
}

/// 아이콘만 있는 정사각 버튼(통계·물). 라벨 대신 [tooltip]이 스크린리더 라벨이 된다.
class ActionSquareButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color background;
  final Color foreground;
  final VoidCallback onPressed;

  const ActionSquareButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.background,
    required this.foreground,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      // 보이는 크기는 44×44, 터치 영역은 Material 기본값(48×48)으로 패딩된다.
      child: FilledButton(
        onPressed: onPressed,
        style: _actionStyle(background: background, foreground: foreground, padding: EdgeInsets.zero).copyWith(
          fixedSize: const WidgetStatePropertyAll(Size.square(ActionButtonMetrics.height)),
        ),
        child: Icon(icon),
      ),
    );
  }
}

/// 홈 하단 가운데(centerDocked)의 운동 · 통계 · 찍기 버튼 묶음. 운동(틸)과 찍기(코랄)만
/// 강조색이고, 통계는 중립 톤이다. 좁은 화면·긴 라벨에서는 양쪽 버튼이 줄어든다.
class HomeActionButtons extends StatelessWidget {
  final String exerciseLabel;
  final String statsTooltip;
  final String cameraLabel;
  final VoidCallback onExercise;
  final VoidCallback onStats;
  final VoidCallback onCamera;

  const HomeActionButtons({
    super.key,
    required this.exerciseLabel,
    required this.statsTooltip,
    required this.cameraLabel,
    required this.onExercise,
    required this.onStats,
    required this.onCamera,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: ActionPillButton(
              icon: Icons.fitness_center,
              label: exerciseLabel,
              background: AppColors.exerciseTealStrong,
              onPressed: onExercise,
            ),
          ),
          const SizedBox(width: ActionButtonMetrics.gap),
          ActionSquareButton(
            icon: Icons.bar_chart,
            tooltip: statsTooltip,
            background: AppColors.neutralButtonBg,
            foreground: AppColors.neutralButtonFg,
            onPressed: onStats,
          ),
          const SizedBox(width: ActionButtonMetrics.gap),
          Flexible(
            child: ActionPillButton(
              icon: Icons.camera_alt,
              label: cameraLabel,
              background: AppColors.foodCoralStrong,
              onPressed: onCamera,
            ),
          ),
        ],
      ),
    );
  }
}
