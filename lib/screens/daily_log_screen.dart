import 'package:flutter/material.dart';

import '../db/database_helper.dart';
import '../models/daily_log_entry.dart';
import '../services/user_profile_service.dart';
import '../utils/unit_converter.dart';
import '../widgets/log_entry_tile.dart';

class DailyLogScreen extends StatefulWidget {
  /// 조회할 날짜. 생략하면 오늘. 통계 화면 등에서 특정 날짜의 상세 내역을
  /// 보여줄 때도 이 화면을 그대로 재사용한다 (조회/삭제 흐름 동일).
  final DateTime? initialDate;

  const DailyLogScreen({super.key, this.initialDate});

  @override
  State<DailyLogScreen> createState() => _DailyLogScreenState();
}

class _DailyLogScreenState extends State<DailyLogScreen> {
  final _db = DatabaseHelper.instance;
  late DateTime _selectedDate;

  List<DailyLogEntry> _entries = [];
  DailySummary? _summary;
  UnitSystem _unitSystem = UnitSystem.metric;

  bool get _isToday {
    final now = DateTime.now();
    return _selectedDate.year == now.year && _selectedDate.month == now.month && _selectedDate.day == now.day;
  }

  String get _title => _isToday ? '오늘의 로그' : '${_selectedDate.month}월 ${_selectedDate.day}일 로그';

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.initialDate ?? DateTime.now();
    _load();
  }

  Future<void> _load() async {
    final entries = await _db.getLogsForDate(_selectedDate);
    final summary = await _db.getSummary(_selectedDate);
    final unitSystem = await UserProfileService.instance.getUnitSystem();
    setState(() {
      _entries = entries;
      _summary = summary;
      _unitSystem = unitSystem;
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked == null) return;
    setState(() => _selectedDate = picked);
    _load();
  }

  void _goToToday() {
    setState(() => _selectedDate = DateTime.now());
    _load();
  }

  Future<void> _quickAddWater() async {
    await _db.insertLog(DailyLogEntry(
      datetime: DateTime.now(),
      type: LogType.water,
      name: '물',
      calories: 0,
      amount: 250,
    ));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_title),
        actions: [
          if (!_isToday)
            IconButton(
              icon: const Icon(Icons.today),
              tooltip: '오늘로 돌아가기',
              onPressed: _goToToday,
            ),
          IconButton(
            icon: const Icon(Icons.calendar_month),
            tooltip: '날짜 선택',
            onPressed: _pickDate,
          ),
        ],
      ),
      body: Column(
        children: [
          _SummaryCard(summary: _summary),
          _NutrientsCard(entries: _entries),
          Expanded(
            child: _entries.isEmpty
                ? Center(
                    child: Text(_isToday ? '아직 기록이 없어요. 사진을 찍어보세요!' : '이 날짜에는 기록이 없어요.'),
                  )
                : ListView.builder(
                    itemCount: _entries.length,
                    itemBuilder: (context, i) {
                      final e = _entries[i];
                      return LogEntryTile(
                        entry: e,
                        unitSystem: _unitSystem,
                        onDelete: () async {
                          await _db.deleteLog(e.id!, _selectedDate);
                          _load();
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: _isToday
          ? FloatingActionButton(
              heroTag: 'daily_log_fab',
              onPressed: _quickAddWater,
              tooltip: '물 250ml 빠르게 추가',
              child: const Icon(Icons.water_drop),
            )
          : null,
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final DailySummary? summary;
  const _SummaryCard({required this.summary});

  @override
  Widget build(BuildContext context) {
    final intake = summary?.totalIntake ?? 0;
    final burned = summary?.totalBurned ?? 0;
    final net = summary?.netCalories ?? 0;

    return Card(
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _StatColumn(label: '섭취', value: intake),
            _StatColumn(label: '소모', value: burned),
            _StatColumn(label: '순칼로리', value: net, highlight: true),
          ],
        ),
      ),
    );
  }
}

/// 그날 음식 기록들의 탄수화물/단백질/지방 합계를 보여준다. 각 항목의 값은 이미
/// 실제 섭취량 기준으로 환산되어 저장돼 있으므로(calories와 동일한 방식) 그대로 더하면 된다.
/// 운동/물 기록은 영양소와 무관하므로 집계에서 제외하고, 값이 없는(null) 과거 기록은 0으로 취급한다.
class _NutrientsCard extends StatelessWidget {
  final List<DailyLogEntry> entries;
  const _NutrientsCard({required this.entries});

  @override
  Widget build(BuildContext context) {
    double carbs = 0, protein = 0, fat = 0;
    for (final e in entries) {
      if (e.type != LogType.food) continue;
      carbs += e.carbsG ?? 0;
      protein += e.proteinG ?? 0;
      fat += e.fatG ?? 0;
    }

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Text(
          '탄수화물 ${carbs.toStringAsFixed(0)}g · '
          '단백질 ${protein.toStringAsFixed(0)}g · '
          '지방 ${fat.toStringAsFixed(0)}g',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
      ),
    );
  }
}

class _StatColumn extends StatelessWidget {
  final String label;
  final double value;
  final bool highlight;
  const _StatColumn({required this.label, required this.value, this.highlight = false});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: Colors.grey)),
        Text(
          value.toStringAsFixed(0),
          style: TextStyle(
            fontSize: 20,
            fontWeight: highlight ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ],
    );
  }
}
