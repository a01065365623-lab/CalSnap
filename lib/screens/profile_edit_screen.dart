import 'package:flutter/material.dart';

import '../services/user_profile_service.dart';
import '../utils/bmr_calculator.dart';
import '../utils/unit_converter.dart';
import '../widgets/labeled_number_field.dart';

/// 설정 화면에서 진입: 온보딩 때 입력한 성별/나이/키/체중을 다시 수정하고,
/// 목표 칼로리도 공식 계산값에 얽매이지 않고 직접 원하는 값으로 저장할 수 있다.
class ProfileEditScreen extends StatefulWidget {
  const ProfileEditScreen({super.key});

  @override
  State<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends State<ProfileEditScreen> {
  Gender? _gender;
  final _ageController = TextEditingController();
  final _heightController = TextEditingController();
  final _weightController = TextEditingController();
  final _goalCaloriesController = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  UnitSystem _unitSystem = UnitSystem.metric;

  // 사용자가 목표 칼로리 필드를 직접 수정했는지 여부. true가 되면 나이/키/체중/성별이
  // 바뀌어도 자동 계산값으로 덮어쓰지 않는다(사용자가 입력한 값을 존중).
  bool _goalCaloriesManuallyEdited = false;
  // _goalCaloriesController.text를 코드에서 프로그래밍적으로 설정하는 동안
  // 그 변경을 "사용자가 직접 수정함"으로 오인하지 않기 위한 가드.
  bool _isSyncingGoalCalories = false;

  @override
  void initState() {
    super.initState();
    for (final c in [_ageController, _heightController, _weightController]) {
      c.addListener(_onBasicFieldChanged);
    }
    _goalCaloriesController.addListener(_onGoalCaloriesFieldChanged);
    _loadCurrent();
  }

  void _onBasicFieldChanged() {
    setState(() {
      if (!_goalCaloriesManuallyEdited) _syncGoalCaloriesToAutoCalculated();
    });
  }

  void _onGoalCaloriesFieldChanged() {
    if (_isSyncingGoalCalories) return;
    _goalCaloriesManuallyEdited = true;
    setState(() {});
  }

  /// 현재 성별/나이/키/체중 기준 공식 계산값으로 목표 칼로리 필드를 갱신한다.
  void _syncGoalCaloriesToAutoCalculated() {
    final value = _autoCalculatedGoalCalories;
    if (value == null) return;
    _isSyncingGoalCalories = true;
    _goalCaloriesController.text = value.toStringAsFixed(0);
    _isSyncingGoalCalories = false;
  }

  Future<void> _loadCurrent() async {
    final profile = await UserProfileService.instance.getProfile();
    final storedGoalCalories = await UserProfileService.instance.getGoalCalories();
    _unitSystem = await UserProfileService.instance.getUnitSystem();

    if (profile != null) {
      _gender = profile.gender;
      _ageController.text = profile.age.toString();
      _heightController.text = profile.heightCm.toStringAsFixed(0);
      final displayWeight =
          _unitSystem == UnitSystem.imperial ? kgToLb(profile.weightKg) : profile.weightKg;
      _weightController.text = displayWeight.toStringAsFixed(1);
    }

    // 저장된 목표 칼로리가 공식 계산값과 다르면 사용자가 직접 수정했던 값으로 보고
    // 이후 입력값이 바뀌어도 자동으로 덮어쓰지 않는다.
    final autoCalculated = _autoCalculatedGoalCalories;
    if (storedGoalCalories != null &&
        autoCalculated != null &&
        (storedGoalCalories - autoCalculated).abs() > 0.5) {
      _goalCaloriesManuallyEdited = true;
    }

    // 저장된 목표 칼로리(직접 수정한 값 포함)가 있으면 그걸, 없으면 공식 계산값으로 채운다.
    final initialGoalCalories = storedGoalCalories ?? autoCalculated;
    if (initialGoalCalories != null) {
      _isSyncingGoalCalories = true;
      _goalCaloriesController.text = initialGoalCalories.toStringAsFixed(0);
      _isSyncingGoalCalories = false;
    }

    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _ageController.dispose();
    _heightController.dispose();
    _weightController.dispose();
    _goalCaloriesController.dispose();
    super.dispose();
  }

  int? get _age => int.tryParse(_ageController.text.trim());
  double? get _height => double.tryParse(_heightController.text.trim());
  double? get _goalCalories => double.tryParse(_goalCaloriesController.text.trim());

  /// 체중 입력 필드는 현재 표시 단위(kg 또는 lb) 기준 값을 담고 있으므로
  /// 저장/계산에 쓸 때는 항상 kg로 변환한다.
  double? get _weightKg {
    final raw = double.tryParse(_weightController.text.trim());
    if (raw == null) return null;
    return _unitSystem == UnitSystem.imperial ? lbToKg(raw) : raw;
  }

  bool get _isValid =>
      _gender != null &&
      (_age ?? 0) > 0 &&
      (_height ?? 0) > 0 &&
      (_weightKg ?? 0) > 0 &&
      (_goalCalories ?? 0) > 0;

  /// 성별/나이/키/체중 기준 BMR 공식 계산값(참고용). 목표 칼로리 필드는 이 값과
  /// 별개로 사용자가 직접 수정해 저장할 수 있다.
  double? get _autoCalculatedGoalCalories {
    final gender = _gender;
    final age = _age;
    final height = _height;
    final weight = _weightKg;
    if (gender == null || age == null || height == null || weight == null) return null;
    if (age <= 0 || height <= 0 || weight <= 0) return null;
    return calculateGoalCalories(gender: gender, age: age, heightCm: height, weightKg: weight);
  }

  void _applyAutoCalculated() {
    final value = _autoCalculatedGoalCalories;
    if (value == null) return;
    setState(() {
      _goalCaloriesManuallyEdited = false;
      _isSyncingGoalCalories = true;
      _goalCaloriesController.text = value.toStringAsFixed(0);
      _isSyncingGoalCalories = false;
    });
  }

  Future<void> _save() async {
    if (!_isValid || _saving) return;
    setState(() => _saving = true);
    await UserProfileService.instance.saveProfile(
      UserProfile(gender: _gender!, age: _age!, heightCm: _height!, weightKg: _weightKg!),
      goalCaloriesOverride: _goalCalories!,
    );
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final autoCalculated = _autoCalculatedGoalCalories;

    return Scaffold(
      appBar: AppBar(title: const Text('내 정보 수정')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('성별', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    children: [
                      ChoiceChip(
                        label: const Text('남'),
                        selected: _gender == Gender.male,
                        onSelected: (_) => setState(() {
                          _gender = Gender.male;
                          if (!_goalCaloriesManuallyEdited) _syncGoalCaloriesToAutoCalculated();
                        }),
                      ),
                      ChoiceChip(
                        label: const Text('여'),
                        selected: _gender == Gender.female,
                        onSelected: (_) => setState(() {
                          _gender = Gender.female;
                          if (!_goalCaloriesManuallyEdited) _syncGoalCaloriesToAutoCalculated();
                        }),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  LabeledNumberField(label: '나이', suffix: '세', controller: _ageController),
                  const SizedBox(height: 16),
                  LabeledNumberField(label: '키', suffix: 'cm', controller: _heightController, allowDecimal: true),
                  const SizedBox(height: 16),
                  LabeledNumberField(
                    label: '체중',
                    suffix: _unitSystem == UnitSystem.imperial ? 'lb' : 'kg',
                    controller: _weightController,
                    allowDecimal: true,
                  ),
                  const SizedBox(height: 24),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: LabeledNumberField(
                          label: '목표 칼로리 (직접 수정 가능)',
                          suffix: 'kcal',
                          controller: _goalCaloriesController,
                        ),
                      ),
                      if (autoCalculated != null)
                        Padding(
                          padding: const EdgeInsets.only(left: 8, bottom: 2),
                          child: TextButton(
                            onPressed: _applyAutoCalculated,
                            child: const Text('자동 계산값 적용'),
                          ),
                        ),
                    ],
                  ),
                  if (autoCalculated != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      '공식 계산값: ${autoCalculated.toStringAsFixed(0)} kcal/일 (성별·나이·키·체중 기준)',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                  ],
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isValid ? _save : null,
                      child: _saving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('저장'),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
