import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../services/user_profile_service.dart';
import '../utils/bmr_calculator.dart';
import '../utils/unit_converter.dart';
import '../widgets/labeled_number_field.dart';
import 'home_screen.dart';

/// 회원가입 없이, 목표 칼로리 계산에 필요한 최소 정보(성별/나이/키/체중)만 받는 온보딩.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  Gender? _gender;
  final _ageController = TextEditingController();
  final _heightController = TextEditingController();
  final _weightController = TextEditingController();
  bool _saving = false;
  UnitSystem _unitSystem = UnitSystem.metric;

  @override
  void initState() {
    super.initState();
    for (final c in [_ageController, _heightController, _weightController]) {
      c.addListener(() => setState(() {}));
    }
    _loadUnitSystem();
  }

  Future<void> _loadUnitSystem() async {
    final unitSystem = await UserProfileService.instance.getUnitSystem();
    if (mounted) setState(() => _unitSystem = unitSystem);
  }

  @override
  void dispose() {
    _ageController.dispose();
    _heightController.dispose();
    _weightController.dispose();
    super.dispose();
  }

  int? get _age => int.tryParse(_ageController.text.trim());
  double? get _height => double.tryParse(_heightController.text.trim());

  /// 체중 입력 필드는 현재 표시 단위(kg 또는 lb) 기준 값을 담고 있으므로
  /// 저장/계산에 쓸 때는 항상 kg로 변환한다.
  double? get _weightKg {
    final raw = double.tryParse(_weightController.text.trim());
    if (raw == null) return null;
    return _unitSystem == UnitSystem.imperial ? lbToKg(raw) : raw;
  }

  bool get _canStart => _gender != null && (_age ?? 0) > 0 && (_height ?? 0) > 0 && (_weightKg ?? 0) > 0;

  Future<void> _start() async {
    if (!_canStart || _saving) return;
    setState(() => _saving = true);
    await UserProfileService.instance.completeOnboarding(UserProfile(
      gender: _gender!,
      age: _age!,
      heightCm: _height!,
      weightKg: _weightKg!,
    ));
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.onboardingAppBarTitle)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.onboardingIntro,
                style: const TextStyle(fontSize: 14, color: Colors.grey),
              ),
              const SizedBox(height: 24),
              Text(l10n.genderLabel, style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                children: [
                  ChoiceChip(
                    label: Text(l10n.genderMale),
                    selected: _gender == Gender.male,
                    onSelected: (_) => setState(() => _gender = Gender.male),
                  ),
                  ChoiceChip(
                    label: Text(l10n.genderFemale),
                    selected: _gender == Gender.female,
                    onSelected: (_) => setState(() => _gender = Gender.female),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              LabeledNumberField(label: l10n.ageLabel, suffix: l10n.ageSuffix, controller: _ageController),
              const SizedBox(height: 16),
              LabeledNumberField(
                  label: l10n.heightLabel, suffix: 'cm', controller: _heightController, allowDecimal: true),
              const SizedBox(height: 16),
              LabeledNumberField(
                label: l10n.weightLabel,
                suffix: _unitSystem == UnitSystem.imperial ? 'lb' : 'kg',
                controller: _weightController,
                allowDecimal: true,
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _canStart ? _start : null,
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : Text(l10n.onboardingStartButton),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
