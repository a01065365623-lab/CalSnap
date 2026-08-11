import 'package:flutter/material.dart';

import '../db/database_helper.dart';
import '../models/daily_log_entry.dart';
import '../models/exercise_type.dart';
import '../services/user_profile_service.dart';

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

  bool get _isCustom => _selected.name == customExerciseName;

  double? get _customCalories => double.tryParse(_customCaloriesController.text.trim());

  String? get _customCaloriesError {
    if (_customCaloriesController.text.trim().isEmpty) return null;
    final value = _customCalories;
    if (value == null) return '숫자를 입력해주세요';
    if (value <= 0) return '0보다 커야 해요';
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
    final name = _isCustom ? _customNameController.text.trim() : '${_selected.emoji} ${_selected.name}';
    await DatabaseHelper.instance.insertLog(DailyLogEntry(
      datetime: DateTime.now(),
      type: LogType.exercise,
      name: name,
      calories: -_caloriesBurned,
      amount: _isCustom ? null : _minutes,
    ));
    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('저장했어요')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('운동 기록')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('운동 종류', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: exerciseTypes.map((e) {
                final selected = e.name == _selected.name;
                return ChoiceChip(
                  label: Text('${e.emoji} ${e.name}'),
                  selected: selected,
                  onSelected: (_) => setState(() => _selected = e),
                );
              }).toList(),
            ),
            const SizedBox(height: 24),
            if (_isCustom) ...[
              const Text('운동명', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              TextField(
                controller: _customNameController,
                decoration: const InputDecoration(
                  hintText: '예: 낚시, 배드민턴',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 16),
              const Text('소모 칼로리', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              TextField(
                controller: _customCaloriesController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  hintText: '예: 300',
                  suffixText: 'kcal',
                  border: const OutlineInputBorder(),
                  isDense: true,
                  errorText: _customCaloriesError,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '30분 기준 예시예요, 활동 강도에 따라 조절하세요',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: customExercisePresets.map((p) {
                  return ActionChip(
                    label: Text('${p.name} · ${p.caloriesPer30Min.toStringAsFixed(0)}kcal'),
                    labelStyle: const TextStyle(fontSize: 12),
                    visualDensity: VisualDensity.compact,
                    onPressed: () {
                      _customNameController.text = p.name;
                      _customCaloriesController.text = p.caloriesPer30Min.toStringAsFixed(0);
                    },
                  );
                }).toList(),
              ),
            ] else ...[
              const Text('운동 시간', style: TextStyle(fontWeight: FontWeight.bold)),
              Text(
                '${_minutes.round()}분',
                style: const TextStyle(fontSize: 18),
              ),
              Slider(
                value: _minutes,
                min: 10,
                max: 180,
                divisions: 17,
                label: '${_minutes.round()}분',
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
                              ? '운동명을 입력해주세요'
                              : _customNameController.text.trim())
                          : '${_selected.emoji} ${_selected.name} · ${_minutes.round()}분',
                      style: const TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '예상 소모 ${_caloriesBurned.toStringAsFixed(0)} kcal',
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
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
                child: const Text('저장'),
              ),
            ),
            TextButton(onPressed: _reset, child: const Text('초기화')),
          ],
        ),
      ),
    );
  }
}
