import 'package:flutter/material.dart';

import '../db/database_helper.dart';
import '../services/user_profile_service.dart';
import '../utils/bmr_calculator.dart';

/// 온보딩/프로필 체중(user_profile_service)과는 별개로, 날짜별 체중을 기록해
/// 다이어트 추이를 확인하기 위한 캘린더 화면.
class WeightLogScreen extends StatefulWidget {
  const WeightLogScreen({super.key});

  @override
  State<WeightLogScreen> createState() => _WeightLogScreenState();
}

class _WeightLogScreenState extends State<WeightLogScreen> {
  static const List<String> _weekdayLabels = ['일', '월', '화', '수', '목', '금', '토'];

  late DateTime _month; // 보고 있는 달의 1일
  Map<String, double> _weights = {};
  bool _loading = true;

  // 최신 체중 기준 BMI 표시용(키는 온보딩 프로필 값 사용, 보고 있는 달과는 무관).
  double? _latestWeightKg;
  double? _heightCm;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month, 1);
    _load();
    _loadBmiInputs();
  }

  Future<void> _loadBmiInputs() async {
    final profile = await UserProfileService.instance.getProfile();
    final latestWeight = await DatabaseHelper.instance.getLatestWeight();
    if (mounted) {
      setState(() {
        _heightCm = profile?.heightCm;
        _latestWeightKg = latestWeight;
      });
    }
  }

  /// 키(프로필)와 최신 체중 기록이 모두 있어야 계산 가능. 없으면 null(표시 안 함).
  String? get _bmiSummary {
    final height = _heightCm;
    final weight = _latestWeightKg;
    if (height == null || weight == null) return null;
    final bmi = calculateBmi(weightKg: weight, heightCm: height);
    return '최신 체중 ${weight.toStringAsFixed(1)}kg · BMI ${bmi.toStringAsFixed(1)} (${getBmiCategory(bmi)})';
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
    final key = _dateKey(date);
    final existing = _weights[key];
    final controller = TextEditingController(text: existing?.toStringAsFixed(1) ?? '');

    final result = await showDialog<_WeightDialogResult>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${date.month}월 ${date.day}일 체중'),
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
              child: const Text('삭제'),
            ),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')),
          TextButton(
            onPressed: () {
              final value = double.tryParse(controller.text.trim());
              if (value == null || value <= 0) return;
              Navigator.pop(context, _WeightDialogResult.saved(value));
            },
            child: const Text('저장'),
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
    final firstDayOffset = DateTime(_month.year, _month.month, 1).weekday % 7; // 일요일 시작 기준 빈칸 수
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final now = DateTime.now();

    return Scaffold(
      appBar: AppBar(title: const Text('체중 기록')),
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
                  '${_month.year}년 ${_month.month}월',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () => _changeMonth(1),
                ),
              ],
            ),
          ),
          if (_bmiSummary != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                _bmiSummary!,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ),
          Row(
            children: [
              for (final label in _weekdayLabels)
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
                            border: isToday ? Border.all(color: Colors.deepOrange, width: 1.5) : null,
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
                                  color: weight != null ? Colors.deepOrange : Colors.grey.shade400,
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
