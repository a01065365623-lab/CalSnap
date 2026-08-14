import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../db/database_helper.dart';
import '../models/daily_log_entry.dart';
import '../models/exercise_type.dart';
import '../services/tts_service.dart';
import '../services/user_profile_service.dart';
import '../theme/app_colors.dart';

String _exerciseTypeLabel(AppLocalizations l10n, String id) {
  switch (id) {
    case 'walk':
      return l10n.exerciseTypeWalk;
    case 'briskWalk':
      return l10n.exerciseTypeBriskWalk;
    case 'jog':
      return l10n.exerciseTypeJog;
    case 'run':
      return l10n.exerciseTypeRun;
    case 'cycle':
      return l10n.exerciseTypeCycle;
    case 'strength':
      return l10n.exerciseTypeStrength;
    case 'yoga':
      return l10n.exerciseTypeYoga;
    case 'hike':
      return l10n.exerciseTypeHike;
    case 'swim':
      return l10n.exerciseTypeSwim;
    case 'stairs':
      return l10n.exerciseTypeStairs;
    case 'other':
      return l10n.exerciseTypeOther;
    default:
      return id;
  }
}

String _presetLabel(AppLocalizations l10n, String id) {
  switch (id) {
    case 'fishing':
      return l10n.presetFishing;
    case 'badminton':
      return l10n.presetBadminton;
    case 'golf':
      return l10n.presetGolf;
    case 'housework':
      return l10n.presetHousework;
    case 'lightHike':
      return l10n.presetLightHike;
    case 'stairsChildcare':
      return l10n.presetStairsChildcare;
    default:
      return id;
  }
}

class ExerciseInputScreen extends StatefulWidget {
  const ExerciseInputScreen({super.key});

  @override
  State<ExerciseInputScreen> createState() => _ExerciseInputScreenState();
}

class _ExerciseInputScreenState extends State<ExerciseInputScreen> {
  ExerciseType _selected = exerciseTypes.first;
  double _minutes = 30;
  double _weightKg = defaultWeightKg;

  final _customNameController = TextEditingController();
  final _customCaloriesController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _customNameController.addListener(() => setState(() {}));
    _customCaloriesController.addListener(() => setState(() {}));
    _loadWeight();
  }

  Future<void> _loadWeight() async {
    final weight = await UserProfileService.instance.getWeightKgOrDefault(defaultWeightKg);
    if (mounted) setState(() => _weightKg = weight);
  }

  @override
  void dispose() {
    _customNameController.dispose();
    _customCaloriesController.dispose();
    super.dispose();
  }

  bool get _isCustom => _selected.id == customExerciseId;

  double? get _customCalories => double.tryParse(_customCaloriesController.text.trim());

  String? _customCaloriesError(AppLocalizations l10n) {
    if (_customCaloriesController.text.trim().isEmpty) return null;
    final value = _customCalories;
    if (value == null) return l10n.exerciseInputCustomCaloriesErrorNaN;
    if (value <= 0) return l10n.exerciseInputCustomCaloriesErrorNonPositive;
    return null;
  }

  bool get _canSave {
    if (!_isCustom) return true;
    final calories = _customCalories;
    return _customNameController.text.trim().isNotEmpty && calories != null && calories > 0;
  }

  double get _caloriesBurned {
    if (_isCustom) return _customCalories ?? 0;
    return calculateCaloriesBurned(
      met: _selected.met,
      weightKg: _weightKg,
      minutes: _minutes.round(),
    );
  }

  /// 운동 종류/시간/기타운동 입력을 전부 초기 상태로 되돌린다.
  void _reset() {
    setState(() {
      _selected = exerciseTypes.first;
      _minutes = 30;
      _customNameController.clear();
      _customCaloriesController.clear();
    });
  }

  Future<void> _save() async {
    if (!_canSave) return;
    final l10n = AppLocalizations.of(context)!;
    final name = _isCustom
        ? _customNameController.text.trim()
        : '${_selected.emoji} ${_exerciseTypeLabel(l10n, _selected.id)}';
    await DatabaseHelper.instance.insertLog(DailyLogEntry(
      datetime: DateTime.now(),
      type: LogType.exercise,
      name: name,
      calories: -_caloriesBurned,
      amount: _isCustom ? null : _minutes,
    ));
    unawaited(TtsService.instance.speakAfterSave(TtsCategory.exerciseSave));
    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.savedSnackbarMessage)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.fitness_center, color: AppColors.exerciseTeal, size: 22),
            const SizedBox(width: 8),
            Text(l10n.exerciseInputAppBarTitle),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.exerciseInputTypeLabel, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: exerciseTypes.map((e) {
                final selected = e.id == _selected.id;
                return ChoiceChip(
                  label: Text('${e.emoji} ${_exerciseTypeLabel(l10n, e.id)}'),
                  selected: selected,
                  selectedColor: AppColors.exerciseTealBg,
                  checkmarkColor: AppColors.exerciseTeal,
                  onSelected: (_) => setState(() => _selected = e),
                );
              }).toList(),
            ),
            const SizedBox(height: 24),
            if (_isCustom) ...[
              Text(l10n.exerciseInputCustomNameLabel, style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              TextField(
                controller: _customNameController,
                decoration: InputDecoration(
                  hintText: l10n.exerciseInputCustomNameHint,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 16),
              Text(l10n.exerciseInputCustomCaloriesLabel, style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              TextField(
                controller: _customCaloriesController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  hintText: l10n.exerciseInputCustomCaloriesHint,
                  suffixText: 'kcal',
                  border: const OutlineInputBorder(),
                  isDense: true,
                  errorText: _customCaloriesError(l10n),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                l10n.exerciseInputPresetHint,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: customExercisePresets.map((p) {
                  final label = _presetLabel(l10n, p.id);
                  return ActionChip(
                    label: Text('$label · ${p.caloriesPer30Min.toStringAsFixed(0)}kcal'),
                    labelStyle: const TextStyle(fontSize: 12),
                    visualDensity: VisualDensity.compact,
                    onPressed: () {
                      _customNameController.text = label;
                      _customCaloriesController.text = p.caloriesPer30Min.toStringAsFixed(0);
                    },
                  );
                }).toList(),
              ),
            ] else ...[
              Text(l10n.exerciseInputDurationLabel, style: const TextStyle(fontWeight: FontWeight.bold)),
              Text(
                '${_minutes.round()}${l10n.minutesSuffix}',
                style: const TextStyle(fontSize: 18),
              ),
              Slider(
                value: _minutes,
                min: 10,
                max: 180,
                divisions: 17,
                label: '${_minutes.round()}${l10n.minutesSuffix}',
                onChanged: (v) => setState(() => _minutes = v),
              ),
            ],
            const SizedBox(height: 24),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Text(
                      _isCustom
                          ? (_customNameController.text.trim().isEmpty
                              ? l10n.exerciseInputCustomNamePlaceholder
                              : _customNameController.text.trim())
                          : '${_selected.emoji} ${_exerciseTypeLabel(l10n, _selected.id)} · '
                              '${_minutes.round()}${l10n.minutesSuffix}',
                      style: const TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l10n.exerciseInputEstimatedBurn(_caloriesBurned.toStringAsFixed(0)),
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppColors.exerciseTeal,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _canSave ? _save : null,
                child: Text(l10n.saveButton),
              ),
            ),
            TextButton(onPressed: _reset, child: Text(l10n.resetButton)),
          ],
        ),
      ),
    );
  }
}
