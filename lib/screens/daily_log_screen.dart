import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../db/database_helper.dart';
import '../models/daily_log_entry.dart';
import '../services/tts_service.dart';
import '../services/user_profile_service.dart';
import '../theme/app_colors.dart';
import '../utils/unit_converter.dart';
import '../widgets/log_entry_tile.dart';
import '../widgets/related_products_button.dart';
import 'weight_log_screen.dart';

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

  String _title(AppLocalizations l10n) => _isToday
      ? l10n.dailyLogTodayTitle
      : l10n.dailyLogDateTitle(_selectedDate.month, _selectedDate.day);

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
    final l10n = AppLocalizations.of(context)!;
    await _db.insertLog(DailyLogEntry(
      datetime: DateTime.now(),
      type: LogType.water,
      name: l10n.dailyLogWaterEntryName,
      calories: 0,
      amount: 250,
    ));
    unawaited(TtsService.instance.speak(TtsCategory.waterLog));
    _load();
  }

  Future<void> _deleteAllForDate() async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.dailyLogDeleteAllDialogTitle),
        content: Text(l10n.dailyLogDeleteAllDialogContent),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.cancelButton)),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text(l10n.deleteButton)),
        ],
      ),
    );
    if (confirmed != true) return;

    await _db.deleteLogsForDate(_selectedDate);
    _load();
  }

  /// 음식 항목을 탭했을 때 상세 정보 + "관련 상품 보기" 버튼을 보여준다.
  /// 운동/물 항목에는 이 상세 시트를 연결하지 않는다(build()에서 onTap을 null로 둠).
  void _showFoodDetail(BuildContext context, DailyLogEntry entry) {
    final l10n = AppLocalizations.of(context)!;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(entry.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(
              '${entry.calories.toStringAsFixed(0)} kcal',
              style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
            ),
            if (entry.carbsG != null || entry.proteinG != null || entry.fatG != null) ...[
              const SizedBox(height: 4),
              Text(
                l10n.nutrientsSummary(
                  (entry.carbsG ?? 0).toStringAsFixed(0),
                  (entry.proteinG ?? 0).toStringAsFixed(0),
                  (entry.fatG ?? 0).toStringAsFixed(0),
                ),
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              ),
            ],
            const SizedBox(height: 16),
            RelatedProductsButton(queryBuilder: () => entry.name),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(_title(l10n)),
        actions: [
          if (!_isToday)
            IconButton(
              icon: const Icon(Icons.today),
              tooltip: l10n.dailyLogBackToTodayTooltip,
              onPressed: _goToToday,
            ),
          IconButton(
            icon: const Icon(Icons.calendar_month),
            tooltip: l10n.dailyLogPickDateTooltip,
            onPressed: _pickDate,
          ),
          if (_entries.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              tooltip: l10n.dailyLogDeleteAllTooltip,
              onPressed: _deleteAllForDate,
            ),
        ],
      ),
      body: Column(
        children: [
          _SummaryCard(summary: _summary),
          _WeightLogEntryCard(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const WeightLogScreen()),
            ),
          ),
          _NutrientsCard(entries: _entries),
          Expanded(
            child: _entries.isEmpty
                ? Center(
                    child: Text(_isToday ? l10n.dailyLogEmptyToday : l10n.dailyLogEmptyOtherDay),
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
                        // 관련 상품 보기는 음식 항목에만 의미가 있으므로, 운동·물
                        // 항목은 onTap을 null로 둬서 탭해도 아무 반응이 없게 한다.
                        onTap: e.type == LogType.food ? () => _showFoodDetail(context, e) : null,
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
              tooltip: l10n.dailyLogQuickAddWaterTooltip,
              child: const Icon(Icons.water_drop),
            )
          : null,
      // 배너는 이 화면 자신의 Scaffold가 아니라 HomeScreen(바깥쪽 Scaffold)의
      // bottomNavigationBar에서 렌더링한다 — 그래야 HomeScreen의 운동/찍기 FAB도
      // 배너 높이를 인식해서 겹치지 않게 위로 올라간다. 자세한 이유는
      // home_screen.dart의 관련 주석 참고.
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final DailySummary? summary;
  const _SummaryCard({required this.summary});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
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
            _StatColumn(label: l10n.dailyLogIntakeLabel, value: intake),
            _StatColumn(label: l10n.dailyLogBurnedLabel, value: burned),
            _StatColumn(label: l10n.netCaloriesLabel, value: net, highlight: true),
          ],
        ),
      ),
    );
  }
}

/// 체중 기록 캘린더(WeightLogScreen)로 이동하는 진입점 카드.
class _WeightLogEntryCard extends StatelessWidget {
  final VoidCallback onTap;
  const _WeightLogEntryCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: ListTile(
        leading: const CircleAvatar(
          backgroundColor: AppColors.weightTealBg,
          foregroundColor: AppColors.weightTeal,
          child: Icon(Icons.monitor_weight_outlined, color: AppColors.weightTeal),
        ),
        title: Text(l10n.weightLogAppBarTitle),
        subtitle: Text(l10n.weightLogCardSubtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
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
    final l10n = AppLocalizations.of(context)!;
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
          l10n.nutrientsSummary(
            carbs.toStringAsFixed(0),
            protein.toStringAsFixed(0),
            fat.toStringAsFixed(0),
          ),
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
