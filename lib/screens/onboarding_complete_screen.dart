import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../theme/app_colors.dart';
import 'home_screen.dart';
import 'settings_screen.dart';

/// 온보딩 완료 직후 보여주는 중간 화면. 시크릿 모드(앱 잠금) 설정을 자연스럽게
/// 유도한 뒤 홈 화면(오늘의 로그)으로 넘어간다. 앱 오픈 TTS 인사는 HomeScreen이
/// 자체적으로 재생하므로 여기서 다시 재생하지 않는다.
class OnboardingCompleteScreen extends StatelessWidget {
  const OnboardingCompleteScreen({super.key});

  void _goHome(BuildContext context) {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.check_circle, size: 64, color: AppColors.foodCoral),
              const SizedBox(height: 16),
              Text(l10n.onboardingCompleteTitle, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                icon: const Icon(Icons.lock_outline),
                label: Text(l10n.onboardingCompleteSecretModeButton),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                ),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => _goHome(context),
                  child: Text(l10n.onboardingCompleteStartButton),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
