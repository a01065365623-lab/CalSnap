import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:intl/intl.dart';

import '../db/database_helper.dart';
import '../dev/seed_data.dart';
import '../services/app_lock_service.dart';
import '../services/user_profile_service.dart';
import '../theme/app_colors.dart';
import '../utils/bmr_calculator.dart';
import '../utils/unit_converter.dart';
import 'onboarding_screen.dart';
import 'profile_edit_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

String _bmiCategoryLabel(AppLocalizations l10n, BmiCategory category) {
  switch (category) {
    case BmiCategory.underweight:
      return l10n.bmiCategoryUnderweight;
    case BmiCategory.normal:
      return l10n.bmiCategoryNormal;
    case BmiCategory.overweight:
      return l10n.bmiCategoryOverweight;
    case BmiCategory.obese:
      return l10n.bmiCategoryObese;
  }
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _busy = false;
  double? _goalCalories;
  String? _userId;
  UnitSystem _unitSystem = UnitSystem.metric;
  UserProfile? _profile;
  bool _ttsEnabled = true;
  bool _secretModeEnabled = false;

  @override
  void initState() {
    super.initState();
    _loadProfileSummary();
  }

  Future<void> _loadProfileSummary() async {
    final goalCalories = await UserProfileService.instance.getGoalCalories();
    final userId = await UserProfileService.instance.getUserId();
    final unitSystem = await UserProfileService.instance.getUnitSystem();
    final profile = await UserProfileService.instance.getProfile();
    final ttsEnabled = await UserProfileService.instance.getTtsEnabled();
    final secretModeEnabled = await AppLockService.instance.isEnabled();
    if (mounted) {
      setState(() {
        _goalCalories = goalCalories;
        _userId = userId;
        _unitSystem = unitSystem;
        _profile = profile;
        _ttsEnabled = ttsEnabled;
        _secretModeEnabled = secretModeEnabled;
      });
    }
  }

  Future<void> _setTtsEnabled(bool enabled) async {
    await UserProfileService.instance.setTtsEnabled(enabled);
    if (mounted) setState(() => _ttsEnabled = enabled);
  }

  Future<void> _onSecretModeToggle(bool enable) async {
    final success = enable ? await _showSetPasswordDialog() : await _showDisablePasswordDialog();
    if (success && mounted) setState(() => _secretModeEnabled = enable);
  }

  /// 시크릿 모드를 켤 때: 새 비밀번호 2자리를 입력받고 확인란과 일치하는지 검증한 뒤 저장한다.
  Future<bool> _showSetPasswordDialog() async {
    final l10n = AppLocalizations.of(context)!;
    final newController = TextEditingController();
    final confirmController = TextEditingController();
    String? errorText;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(l10n.secretModeSetTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: newController,
                keyboardType: TextInputType.number,
                obscureText: true,
                maxLength: 2,
                decoration: InputDecoration(
                  labelText: l10n.secretModeSetLabel,
                  hintText: l10n.secretModeHint2Digits,
                  counterText: '',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: confirmController,
                keyboardType: TextInputType.number,
                obscureText: true,
                maxLength: 2,
                decoration: InputDecoration(
                  labelText: l10n.secretModeConfirmLabel,
                  counterText: '',
                ),
              ),
              if (errorText != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(errorText!, style: const TextStyle(color: Colors.red, fontSize: 12)),
                ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.cancelButton)),
            TextButton(
              onPressed: () {
                final pin = newController.text.trim();
                if (!AppLockService.instance.isValidPin(pin)) {
                  setDialogState(() => errorText = l10n.secretModeInvalidError);
                  return;
                }
                if (pin != confirmController.text.trim()) {
                  setDialogState(() => errorText = l10n.secretModeMismatchError);
                  return;
                }
                Navigator.pop(context, true);
              },
              child: Text(l10n.saveButton),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return false;
    await AppLockService.instance.setPassword(newController.text.trim());
    return true;
  }

  /// 시크릿 모드를 끌 때: 현재 비밀번호를 확인한 뒤에만 해제한다.
  Future<bool> _showDisablePasswordDialog() async {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController();
    String? errorText;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(l10n.secretModeDisableTitle),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            obscureText: true,
            maxLength: 2,
            autofocus: true,
            decoration: InputDecoration(
              labelText: l10n.secretModeDisableLabel,
              hintText: l10n.secretModeHint2Digits,
              counterText: '',
              errorText: errorText,
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.cancelButton)),
            TextButton(
              onPressed: () async {
                final correct = await AppLockService.instance.verifyPassword(controller.text.trim());
                if (!correct) {
                  setDialogState(() => errorText = l10n.secretModeDisableWrongError);
                  return;
                }
                if (context.mounted) Navigator.pop(context, true);
              },
              child: Text(l10n.confirmButton),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return false;
    await AppLockService.instance.disable();
    return true;
  }

  /// 온보딩 전이거나 키/체중이 없으면 null(표시 안 함).
  String? _bmiBmrText(AppLocalizations l10n) {
    final profile = _profile;
    if (profile == null) return null;
    final bmi = calculateBmi(weightKg: profile.weightKg, heightCm: profile.heightCm);
    final bmr = calculateBmr(
      gender: profile.gender,
      age: profile.age,
      heightCm: profile.heightCm,
      weightKg: profile.weightKg,
    );
    final bmrText = NumberFormat('#,##0').format(bmr);
    return l10n.settingsBmiBmrSummary(
      bmi.toStringAsFixed(1),
      _bmiCategoryLabel(l10n, getBmiCategory(bmi)),
      bmrText,
    );
  }

  String _unitSystemLabel(AppLocalizations l10n) =>
      _unitSystem == UnitSystem.metric ? l10n.unitSystemMetricLabel : l10n.unitSystemImperialLabel;

  Future<void> _pickUnitSystem() async {
    final l10n = AppLocalizations.of(context)!;
    final selected = await showDialog<UnitSystem>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(l10n.settingsUnitPickerTitle),
        children: [
          for (final unit in UnitSystem.values)
            RadioListTile<UnitSystem>(
              title: Text(unit == UnitSystem.metric ? l10n.unitSystemMetricLabel : l10n.unitSystemImperialLabel),
              value: unit,
              groupValue: _unitSystem,
              onChanged: (value) => Navigator.pop(context, value),
            ),
        ],
      ),
    );
    if (selected == null || selected == _unitSystem) return;
    await UserProfileService.instance.setUnitSystem(selected);
    if (mounted) setState(() => _unitSystem = selected);
  }

  Future<void> _openProfileEditor() async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const ProfileEditScreen()),
    );
    if (changed == true) _loadProfileSummary();
  }

  Future<void> _editUserId() async {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController(text: _userId ?? '');
    final newId = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.settingsEditUserIdTitle),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancelButton)),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text(l10n.saveButton),
          ),
        ],
      ),
    );
    if (newId == null || newId.isEmpty) return;
    await UserProfileService.instance.setUserId(newId);
    _loadProfileSummary();
  }

  Future<void> _resetProfile() async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.settingsResetProfileDialogTitle),
        content: Text(l10n.settingsResetProfileDialogContent),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.cancelButton)),
          TextButton(
              onPressed: () => Navigator.pop(context, true), child: Text(l10n.settingsResetProfileConfirmButton)),
        ],
      ),
    );
    if (confirmed != true) return;

    await UserProfileService.instance.resetProfile();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const OnboardingScreen()),
      (route) => false,
    );
  }

  Future<void> _run(Future<String> Function() action) async {
    setState(() => _busy = true);
    try {
      final message = await action();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.settingsActionFailed('$e'))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String> _seed() async {
    final sw = Stopwatch()..start();
    final count = await seedOneYearOfLogs();
    sw.stop();
    return '시드 $count건 삽입 완료 (${sw.elapsedMilliseconds}ms)';
  }

  Future<String> _clear() async {
    final sw = Stopwatch()..start();
    final count = await clearSeedData();
    sw.stop();
    return '시드 $count건 삭제 완료 (${sw.elapsedMilliseconds}ms)';
  }

  Future<String> _queryRange() async {
    final sw = Stopwatch()..start();
    final now = DateTime.now();
    final entries = await DatabaseHelper.instance.getLogsForRange(
      now.subtract(const Duration(days: 364)),
      now,
    );
    sw.stop();
    return '최근 365일 조회: ${entries.length}건 (${sw.elapsedMilliseconds}ms)';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.settings, color: AppColors.statsGray, size: 22),
            const SizedBox(width: 8),
            Text(l10n.settingsAppBarTitle),
          ],
        ),
      ),
      body: ListView(
        children: [
          ListTile(
            title: Text(l10n.settingsGoalCaloriesTile),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _goalCalories != null
                      ? l10n.settingsGoalCaloriesSubtitle(_goalCalories!.toStringAsFixed(0))
                      : l10n.settingsGoalCaloriesEmpty,
                ),
                if (_bmiBmrText(l10n) != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      _bmiBmrText(l10n)!,
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                  ),
              ],
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: _openProfileEditor,
          ),
          ListTile(
            leading: const Icon(Icons.restart_alt, color: AppColors.statsGray),
            title: Text(l10n.settingsResetProfileTile),
            subtitle: Text(l10n.settingsResetProfileSubtitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: _resetProfile,
          ),
          ListTile(
            title: Text(l10n.settingsUserIdTile),
            subtitle: Text(_userId ?? '-'),
            trailing: const Icon(Icons.edit),
            onTap: _editUserId,
          ),
          ListTile(
            title: Text(l10n.settingsUnitTile),
            subtitle: Text(_unitSystemLabel(l10n)),
            trailing: const Icon(Icons.chevron_right),
            onTap: _pickUnitSystem,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.record_voice_over_outlined, color: AppColors.statsGray),
            title: Text(l10n.settingsVoiceGuideTile),
            subtitle: Text(l10n.settingsVoiceGuideSubtitle),
            value: _ttsEnabled,
            onChanged: _setTtsEnabled,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.lock_outline, color: AppColors.statsGray),
            title: Text(l10n.settingsSecretModeTile),
            subtitle: Text(l10n.settingsSecretModeSubtitle),
            value: _secretModeEnabled,
            onChanged: _onSecretModeToggle,
          ),
          ListTile(title: Text(l10n.settingsAffiliateTile), subtitle: Text(l10n.settingsAffiliateSubtitle)),
          if (kDebugMode) ...[
            const Divider(),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text('디버그 도구', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
            ),
            ListTile(
              leading: const Icon(Icons.dataset, color: AppColors.statsGray),
              title: const Text('1년치 테스트 데이터 생성'),
              subtitle: const Text('과거 365일, 하루 2~4건 더미 로그 삽입'),
              enabled: !_busy,
              onTap: () => _run(_seed),
            ),
            ListTile(
              leading: const Icon(Icons.search, color: AppColors.statsGray),
              title: const Text('365일 범위 조회 테스트'),
              subtitle: const Text('getLogsForRange 동작/성능 확인'),
              enabled: !_busy,
              onTap: () => _run(_queryRange),
            ),
            ListTile(
              leading: const Icon(Icons.delete_sweep, color: AppColors.statsGray),
              title: const Text('테스트 데이터 삭제'),
              subtitle: const Text('시드로 생성한 항목만 제거 (실제 기록은 유지)'),
              enabled: !_busy,
              onTap: () => _run(_clear),
            ),
            if (_busy) const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
          ],
        ],
      ),
    );
  }
}
