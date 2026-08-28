import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../db/database_helper.dart';
import '../models/daily_log_entry.dart';
import '../services/tts_service.dart';
import '../services/user_profile_service.dart';
import '../theme/app_colors.dart';
import '../utils/unit_converter.dart';
import '../widgets/banner_ad_widget.dart';
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
  double? _goalCalories;
  double? _waterGoalMl;

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
    // 목표 칼로리/권장 수분 섭취량은 온보딩·설정 화면에서 이미 저장해 둔 값을 그대로
    // 읽기만 한다(여기서 새로 계산하지 않음).
    final goalCalories = await UserProfileService.instance.getGoalCalories();
    final waterGoalMl = await UserProfileService.instance.getDailyWaterGoalMl();
    setState(() {
      _entries = entries;
      _summary = summary;
      _unitSystem = unitSystem;
      _goalCalories = goalCalories;
      _waterGoalMl = waterGoalMl;
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

  /// 물방울 FAB를 탭하면 뜨는 선택 다이얼로그. "250ml 바로 추가"는 즉시, "직접
  /// 입력"은 같은 다이얼로그 안에서 숫자 입력 화면으로 전환된다(별도 다이얼로그를
  /// 닫고 새로 여는 방식이 아니다 — showDialog를 연달아 호출하면 첫 다이얼로그
  /// 라우트의 InheritedElement가 언마운트되는 도중 두 번째 다이얼로그가 끼어들어
  /// "_dependents.isEmpty" assertion이 나서, 하나의 다이얼로그 내부 상태 전환으로
  /// 바꿔 그 문제 자체를 없앴다).
  Future<void> _openWaterQuickAddOptions() async {
    final amount = await showDialog<double>(
      context: context,
      builder: (context) => const _WaterQuickAddDialog(),
    );
    if (amount == null) return;
    await _insertWaterLog(amount);
  }

  Future<void> _insertWaterLog(double amountMl) async {
    final l10n = AppLocalizations.of(context)!;
    await _db.insertLog(DailyLogEntry(
      datetime: DateTime.now(),
      type: LogType.water,
      name: l10n.dailyLogWaterEntryName,
      calories: 0,
      amount: amountMl,
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
          // FAB(운동/찍기)와 물리적으로 겹칠 일이 없는 상단에 고정 배치한다. 예전에
          // bottomNavigationBar 쪽에 뒀을 때는 FAB 도킹 위치 계산과 얽혀서 광고가
          // 가려지는 문제가 반복됐다 — 자세한 배경은 git log 참고.
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: BannerAdWidget(),
          ),
          _SummaryCard(summary: _summary),
          _GoalChipsCard(goalCalories: _goalCalories, waterGoalMl: _waterGoalMl),
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
              onPressed: _openWaterQuickAddOptions,
              tooltip: l10n.dailyLogQuickAddWaterTooltip,
              child: const Icon(Icons.water_drop),
            )
          : null,
    );
  }
}

/// 물방울 FAB 다이얼로그. 처음엔 "250ml 바로 추가"/"직접 입력" 선택지를 보여주고,
/// "직접 입력"을 누르면 같은 다이얼로그(같은 Route) 안에서 숫자 입력 화면으로
/// setState 전환한다 — 다이얼로그를 닫고 새로 여는 방식이 아니라서, 두 개의
/// showDialog를 연달아 호출할 때 생기는 InheritedElement 언마운트 타이밍 문제가
/// 애초에 발생하지 않는다. 최종적으로 Navigator.pop(context, amountMl) 한 번으로
/// 닫히며, 취소 시 null을 반환한다.
class _WaterQuickAddDialog extends StatefulWidget {
  const _WaterQuickAddDialog();

  @override
  State<_WaterQuickAddDialog> createState() => _WaterQuickAddDialogState();
}

class _WaterQuickAddDialogState extends State<_WaterQuickAddDialog> {
  bool _showAmountInput = false;
  final _controller = TextEditingController(text: '250');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    if (!_showAmountInput) {
      return SimpleDialog(
        title: Text(l10n.dailyLogWaterAmountDialogTitle),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 250.0),
            child: Text(l10n.dailyLogWaterQuickAdd250Button),
          ),
          SimpleDialogOption(
            onPressed: () => setState(() => _showAmountInput = true),
            child: Text(l10n.quickModeManualEntryButton),
          ),
        ],
      );
    }

    return AlertDialog(
      title: Text(l10n.dailyLogWaterAmountDialogTitle),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: false),
        decoration: const InputDecoration(suffixText: 'ml'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancelButton),
        ),
        TextButton(
          onPressed: () {
            final value = double.tryParse(_controller.text.trim());
            Navigator.pop(context, (value != null && value > 0) ? value : null);
          },
          child: Text(l10n.dailyLogWaterAmountDialogAddButton),
        ),
      ],
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

/// 그날 음식 기록들의 탄수화물/단백질/지방 합계를 칩 3개로 보여준다. 각 항목의 값은 이미
/// 실제 섭취량 기준으로 환산되어 저장돼 있으므로(calories와 동일한 방식) 그대로 더하면 된다.
/// 운동/물 기록은 영양소와 무관하므로 집계에서 제외하고, 값이 없는(null) 과거 기록은 0으로 취급한다.
/// 색상은 통계 화면의 매크로 비율 차트(stats_screen.dart)와 동일하게 맞췄다.
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.spaceEvenly,
          children: [
            _StatChip(
              icon: Icons.grain,
              label: '${l10n.macroCarbsLabel} ${carbs.toStringAsFixed(0)}g',
              color: AppColors.foodCoral,
              backgroundColor: AppColors.foodCoralBg,
            ),
            _StatChip(
              icon: Icons.set_meal,
              label: '${l10n.macroProteinLabel} ${protein.toStringAsFixed(0)}g',
              color: AppColors.exerciseTeal,
              backgroundColor: AppColors.exerciseTealBg,
            ),
            _StatChip(
              icon: Icons.opacity,
              label: '${l10n.macroFatLabel} ${fat.toStringAsFixed(0)}g',
              color: AppColors.statsGray,
              backgroundColor: AppColors.statsGrayBg,
            ),
          ],
        ),
      ),
    );
  }
}

/// "체중 기록" 진입 카드 바로 위에, 설정에 이미 저장된 목표 칼로리/권장 수분
/// 섭취량을 탄단지 칩(_NutrientsCard)과 동일한 스타일로 보여준다. 여기서는 저장된
/// 값을 읽기만 하고 새로 계산하지 않는다 — 계산은 온보딩/프로필 수정 화면
/// (user_profile_service.dart)의 몫이다. 아직 값이 없으면(온보딩 전 등) 그 칩만 숨긴다.
class _GoalChipsCard extends StatelessWidget {
  final double? goalCalories;
  final double? waterGoalMl;
  const _GoalChipsCard({required this.goalCalories, required this.waterGoalMl});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final chips = [
      if (goalCalories != null)
        _StatChip(
          icon: Icons.local_fire_department,
          label: '${l10n.dailyLogGoalCaloriesChipLabel} ${goalCalories!.toStringAsFixed(0)}kcal',
          color: AppColors.goalOrange,
          backgroundColor: AppColors.goalOrangeBg,
        ),
      if (waterGoalMl != null)
        _StatChip(
          icon: Icons.water_drop,
          label: '${l10n.dailyLogWaterGoalChipLabel} ${waterGoalMl!.toStringAsFixed(0)}ml',
          color: AppColors.waterBlue,
          backgroundColor: AppColors.waterBlueBg,
        ),
    ];
    if (chips.isEmpty) return const SizedBox.shrink();

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.spaceEvenly,
          children: chips,
        ),
      ),
    );
  }
}

/// 오늘의 로그 상단 칩(탄단지/목표 칼로리/권장 수분)에 공통으로 쓰는 필(pill) 스타일
/// 위젯. 색상만 카테고리별로 다르고 모양·패딩·폰트 크기는 항상 동일하다.
class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final Color backgroundColor;

  const _StatChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color)),
        ],
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
