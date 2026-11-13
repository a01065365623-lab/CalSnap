import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../db/database_helper.dart';
import '../models/daily_log_entry.dart';
import '../services/meal_log_service.dart';
import '../services/tts_service.dart';
import '../services/user_profile_service.dart';
import '../theme/app_colors.dart';
import '../utils/bmr_calculator.dart';
import '../utils/unit_converter.dart';
import '../utils/weight_forecast.dart';
import '../widgets/action_buttons.dart';
import '../widgets/banner_ad_widget.dart';
import '../widgets/daily_log_empty_state.dart';
import '../widgets/daily_summary_card.dart';
import '../widgets/food_detail_sheet.dart';
import '../widgets/log_entry_tile.dart';
import '../widgets/weekly_weight_forecast_card.dart';
import 'meal_calendar_screen.dart';
import 'quick_mode_screen.dart';
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
  // 주간 체중 변화 예상의 기준 칼로리. 저장된 목표 칼로리가 우선이고, 없으면 프로필로
  // 기초대사량 × 기본 활동계수를 계산한다. 둘 다 없으면 null(카드 숨김).
  double? _forecastTargetCalories;
  WeeklyWeightForecast? _weightForecast;
  // 저장된 "최근 먹은 음식"이 있을 때만 빈 화면에 그 바로가기를 보여준다.
  bool _hasMyFoods = false;

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

    double? forecastTarget = goalCalories;
    if (forecastTarget == null) {
      final profile = await UserProfileService.instance.getProfile();
      if (profile != null) {
        forecastTarget = calculateGoalCalories(
          gender: profile.gender,
          age: profile.age,
          heightCm: profile.heightCm,
          weightKg: profile.weightKg,
        );
      }
    }
    WeeklyWeightForecast? forecast;
    if (forecastTarget != null && forecastTarget > 0) {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final recent = await _db.getSummaryRange(
        today.subtract(const Duration(days: weightForecastWindowDays)),
        today.subtract(const Duration(days: 1)),
      );
      forecast = estimateWeeklyWeightChange(summaries: recent, targetCalories: forecastTarget, today: today);
    }

    final myFoods = await _db.getMyFoods(limit: 1);

    if (!mounted) return;
    setState(() {
      _entries = entries;
      _summary = summary;
      _unitSystem = unitSystem;
      _goalCalories = goalCalories;
      _waterGoalMl = waterGoalMl;
      _forecastTargetCalories = forecastTarget;
      _weightForecast = forecast;
      _hasMyFoods = myFoods.isNotEmpty;
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

  /// 빈 화면 바로가기. 빠른 측정 화면에서 저장하고 돌아오면 목록을 다시 읽는다.
  Future<void> _openQuickMode(QuickModeStartAction startAction) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => QuickModeScreen(startAction: startAction)),
    );
    if (mounted) _load();
  }

  Future<void> _openMealCalendar() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const MealCalendarScreen()));
    if (mounted) _load(); // 달력에서 지난 식사를 오늘로 다시 기록했을 수 있다.
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

    await MealLogService.instance.deleteLogsForDate(_selectedDate);
    _load();
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
            icon: const Icon(Icons.photo_library_outlined),
            tooltip: l10n.mealCalendarTitle,
            onPressed: _openMealCalendar,
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
          // 상단 카드들도 목록과 함께 스크롤된다. 예전처럼 카드를 고정하고 목록만
          // Expanded로 두면, 좁은 화면(320px)·큰 글꼴에서 카드만으로 높이를 다 써서
          // 세로 overflow가 났다.
          Expanded(
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Column(
                    children: [
                      DailySummaryCard(summary: _summary, goalCalories: _goalCalories),
                      _GoalChipsCard(goalCalories: _goalCalories, waterGoalMl: _waterGoalMl),
                      _WeightLogEntryCard(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const WeightLogScreen()),
                        ),
                      ),
                      // 앞으로의 예상치라 오늘 화면에서만 보여준다.
                      if (_isToday && _weightForecast != null && _forecastTargetCalories != null)
                        WeeklyWeightForecastCard(
                          forecast: _weightForecast!,
                          targetCalories: _forecastTargetCalories!,
                          unitSystem: _unitSystem,
                        ),
                      _NutrientsCard(entries: _entries),
                    ],
                  ),
                ),
                if (_entries.isEmpty && _isToday)
                  SliverToBoxAdapter(
                    child: DailyLogEmptyState(
                      onCamera: () => _openQuickMode(QuickModeStartAction.camera),
                      onManualEntry: () => _openQuickMode(QuickModeStartAction.manualEntry),
                      // 빠른 측정 화면 맨 위에 "최근 먹은 음식" 목록이 바로 보인다.
                      onRecentFoods: _hasMyFoods ? () => _openQuickMode(QuickModeStartAction.none) : null,
                    ),
                  )
                else if (_entries.isEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                      child: Text(l10n.dailyLogEmptyOtherDay, textAlign: TextAlign.center),
                    ),
                  )
                else
                  SliverList.builder(
                    itemCount: _entries.length,
                    itemBuilder: (context, i) {
                      final e = _entries[i];
                      return LogEntryTile(
                        entry: e,
                        unitSystem: _unitSystem,
                        onDelete: () async {
                          await MealLogService.instance.deleteLog(e.id!, _selectedDate);
                          _load();
                        },
                        // 관련 상품 보기는 음식 항목에만 의미가 있으므로, 운동·물
                        // 항목은 onTap을 null로 둬서 탭해도 아무 반응이 없게 한다.
                        onTap: e.type == LogType.food ? () => showFoodDetailSheet(context, e, _unitSystem) : null,
                      );
                    },
                  ),
                // 홈의 centerDocked FAB(운동/통계/찍기)과 이 화면의 물 FAB이 마지막
                // 항목을 가리지 않도록 아래 여백을 둔다.
                const SliverToBoxAdapter(child: SizedBox(height: 88)),
              ],
            ),
          ),
        ],
      ),
      // 홈 하단 버튼(운동/통계/찍기)과 같은 크기·모양·그림자의 정사각 버튼.
      floatingActionButton: _isToday
          ? ActionSquareButton(
              icon: Icons.water_drop,
              tooltip: l10n.dailyLogQuickAddWaterTooltip,
              background: AppColors.waterBlueStrong,
              foreground: AppColors.onAccent,
              onPressed: _openWaterQuickAddOptions,
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
