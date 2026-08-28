import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../db/database_helper.dart';
import '../services/app_lock_service.dart';
import '../services/user_profile_service.dart';
import '../services/weight_photo_service.dart';
import '../theme/app_colors.dart';
import 'home_screen.dart';
import 'onboarding_screen.dart';

/// 시크릿 모드가 켜져 있을 때 콜드 스타트마다 가장 먼저 보여주는 잠금 화면(앱의
/// 루트 라우트). 2자리 숫자 비밀번호를 맞추면 홈 화면으로 넘어간다.
class AppLockScreen extends StatefulWidget {
  const AppLockScreen({super.key});

  @override
  State<AppLockScreen> createState() => _AppLockScreenState();
}

class _AppLockScreenState extends State<AppLockScreen> {
  String _input = '';
  bool _error = false;
  bool _checking = false;

  Future<void> _onDigit(String digit) async {
    if (_checking || _input.length >= 2) return;
    setState(() {
      _input += digit;
      _error = false;
    });
    if (_input.length < 2) return;

    setState(() => _checking = true);
    final correct = await AppLockService.instance.verifyPassword(_input);
    if (!mounted) return;
    if (correct) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
      return;
    }
    setState(() {
      _input = '';
      _error = true;
      _checking = false;
    });
  }

  void _onBackspace() {
    if (_input.isEmpty) return;
    setState(() {
      _input = _input.substring(0, _input.length - 1);
      _error = false;
    });
  }

  Future<void> _onForgotPassword() async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.appLockResetDialogTitle),
        content: Text(l10n.appLockResetDialogContent),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.cancelButton)),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.settingsResetProfileConfirmButton),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    // 앱의 모든 흔적(기록·프로필·잠금 설정)을 지우고 온보딩부터 다시 시작한다.
    await DatabaseHelper.instance.resetAllData();
    await WeightPhotoService.instance.deleteAllPhotos();
    await UserProfileService.instance.resetProfile();
    await AppLockService.instance.disable();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const OnboardingScreen()),
      (route) => false,
    );
  }

  Widget _buildDot(bool filled) {
    return Container(
      width: 16,
      height: 16,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: filled ? AppColors.statsGray : Colors.transparent,
        border: Border.all(color: AppColors.statsGray, width: 1.5),
      ),
    );
  }

  Widget _buildKey({required VoidCallback onTap, String? label, IconData? icon}) {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 72,
          height: 72,
          child: Center(
            child: icon != null
                ? Icon(icon)
                : Text(label ?? '', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w500)),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    const keypadRows = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
    ];

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const Spacer(),
              const Icon(Icons.lock_outline, size: 40, color: AppColors.statsGray),
              const SizedBox(height: 16),
              Text(l10n.appLockTitle, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(l10n.appLockSubtitle, style: TextStyle(color: Colors.grey.shade600)),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildDot(_input.isNotEmpty),
                  _buildDot(_input.length > 1),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 20,
                child: _error
                    ? Text(l10n.appLockWrongPassword, style: const TextStyle(color: Colors.red, fontSize: 13))
                    : null,
              ),
              const Spacer(),
              for (final row in keypadRows)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [for (final d in row) _buildKey(label: d, onTap: () => _onDigit(d))],
                ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  const SizedBox(width: 72, height: 72),
                  _buildKey(label: '0', onTap: () => _onDigit('0')),
                  _buildKey(icon: Icons.backspace_outlined, onTap: _onBackspace),
                ],
              ),
              const Spacer(),
              TextButton(
                onPressed: _onForgotPassword,
                child: Text(l10n.appLockForgotPassword),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
