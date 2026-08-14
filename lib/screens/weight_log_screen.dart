import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:intl/intl.dart';

import '../db/database_helper.dart';
import '../services/user_profile_service.dart';
import '../theme/app_colors.dart';
import '../utils/bmr_calculator.dart';

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

/// 온보딩/프로필 체중(user_profile_service)과는 별개로, 날짜별 체중을 기록해
/// 다이어트 추이를 확인하기 위한 캘린더 화면.
class WeightLogScreen extends StatefulWidget {
  /// 지정하면 그 날짜가 속한 달을 열고, 곧바로 그 날짜의 체중 입력 다이얼로그를 띄운다.
  /// 통계 화면의 체중 추이 그래프에서 특정 지점을 탭했을 때 바로 수정할 수 있도록 한다.
  final DateTime? initialDate;

  const WeightLogScreen({super.key, this.initialDate});

  @override
  State<WeightLogScreen> createState() => _WeightLogScreenState();
}

class _WeightLogScreenState extends State<WeightLogScreen> {
  late DateTime _month; // 보고 있는 달의 1일
  Map<String, double> _weights = {};
  bool _loading = true;

  // 최신 체중/BMI/BMR 요약 표시용(키·성별·나이는 온보딩 프로필 값 사용, 보고 있는 달과는 무관).
  double? _latestWeightKg;
  UserProfile? _profile;

  @override
  void initState() {
    super.initState();
    final initialDate = widget.initialDate;
    final base = initialDate ?? DateTime.now();
    _month = DateTime(base.year, base.month, 1);
    _load();
    _loadBmiInputs();
    if (initialDate != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _editWeight(initialDate);
      });
    }
  }

  Future<void> _loadBmiInputs() async {
    final profile = await UserProfileService.instance.getProfile();
    final latestWeight = await DatabaseHelper.instance.getLatestWeight();
    if (mounted) {
      setState(() {
        _profile = profile;
        _latestWeightKg = latestWeight;
      });
    }
  }

  /// 체중/키가 없으면 해당 항목만 생략하고 나머지를 표시한다(체중 자체가 없으면 전체 숨김).
  String? _bmiSummary(AppLocalizations l10n) {
    final weight = _latestWeightKg;
    if (weight == null) return null;

    final parts = <String>[l10n.weightLogRecentWeight(weight.toStringAsFixed(1))];

    final profile = _profile;
    if (profile != null) {
      final bmi = calculateBmi(weightKg: weight, heightCm: profile.heightCm);
      parts.add(l10n.weightLogBmiSummary(bmi.toStringAsFixed(1), _bmiCategoryLabel(l10n, getBmiCategory(bmi))));

      final bmr = calculateBmr(
        gender: profile.gender,
        age: profile.age,
        heightCm: profile.heightCm,
        weightKg: weight,
      );
      parts.add(l10n.weightLogBmrSummary(NumberFormat('#,##0').format(bmr)));
    }

    return parts.join(' · ');
  }

  String _dateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _load() async {
    setState(() => _loading = true);
    final from = _month;
    final to = DateTime(_month.year, _month.month + 1, 0); // 이번 달 마지막 날
    final weights = await DatabaseHelper.instance.getWeightsForRange(from, to);
    if (mounted) {
      setState(() {
        _weights = weights;
        _loading = false;
      });
    }
  }

  void _changeMonth(int delta) {
    setState(() => _month = DateTime(_month.year, _month.month + delta, 1));
    _load();
  }

  Future<void> _editWeight(DateTime date) async {
    final l10n = AppLocalizations.of(context)!;
    final key = _dateKey(date);
    final existing = _weights[key];
    final controller = TextEditingController(text: existing?.toStringAsFixed(1) ?? '');

    final result = await showDialog<_WeightDialogResult>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.weightLogEditDialogTitle(date.month, date.day)),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            suffixText: 'kg',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        actions: [
          if (existing != null)
            TextButton(
              onPressed: () => Navigator.pop(context, const _WeightDialogResult.deleted()),
              child: Text(l10n.deleteButton),
            ),
          TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancelButton)),
          TextButton(
            onPressed: () {
              final value = double.tryParse(controller.text.trim());
              if (value == null || value <= 0) return;
              Navigator.pop(context, _WeightDialogResult.saved(value));
            },
            child: Text(l10n.saveButton),
          ),
        ],
      ),
    );
    if (result == null) return;

    if (result.isDelete) {
      await DatabaseHelper.instance.deleteWeightForDate(date);
    } else if (result.value != null) {
      await DatabaseHelper.instance.setWeightForDate(date, result.value!);
    }
    _load();
    _loadBmiInputs();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final weekdayLabels = [
      l10n.weekdaySun,
      l10n.weekdayMon,
      l10n.weekdayTue,
      l10n.weekdayWed,
      l10n.weekdayThu,
      l10n.weekdayFri,
      l10n.weekdaySat,
    ];
    final firstDayOffset = DateTime(_month.year, _month.month, 1).weekday % 7; // 일요일 시작 기준 빈칸 수
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final now = DateTime.now();

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.monitor_weight_outlined, color: AppColors.weightTeal, size: 22),
            const SizedBox(width: 8),
            Text(l10n.weightLogAppBarTitle),
          ],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () => _changeMonth(-1),
                ),
                Text(
                  l10n.weightLogMonthHeader(_month.year, _month.month),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () => _changeMonth(1),
                ),
              ],
            ),
          ),
          if (_bmiSummary(l10n) != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                _bmiSummary(l10n)!,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ),
          Row(
            children: [
              for (final label in weekdayLabels)
                Expanded(
                  child: Center(
                    child: Text(label, style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                  ),
                ),
            ],
          ),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : GridView.builder(
                    padding: const EdgeInsets.all(8),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 7,
                      childAspectRatio: 0.8,
                    ),
                    itemCount: firstDayOffset + daysInMonth,
                    itemBuilder: (context, index) {
                      if (index < firstDayOffset) return const SizedBox.shrink();

                      final day = index - firstDayOffset + 1;
                      final date = DateTime(_month.year, _month.month, day);
                      final key = _dateKey(date);
                      final weight = _weights[key];
                      final isToday =
                          date.year == now.year && date.month == now.month && date.day == now.day;

                      return InkWell(
                        onTap: () => _editWeight(date),
                        child: Container(
                          margin: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: isToday ? Border.all(color: AppColors.weightTeal, width: 1.5) : null,
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                '$day',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                weight != null ? weight.toStringAsFixed(1) : '-',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: weight != null ? AppColors.weightTeal : Colors.grey.shade400,
                                  fontWeight: weight != null ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _WeightDialogResult {
  final double? value;
  final bool isDelete;
  const _WeightDialogResult.saved(this.value) : isDelete = false;
  const _WeightDialogResult.deleted()
      : value = null,
        isDelete = true;
}
