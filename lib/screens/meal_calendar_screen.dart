import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:intl/intl.dart';

import '../db/database_helper.dart';
import '../models/daily_log_entry.dart';
import '../services/user_profile_service.dart';
import '../theme/app_colors.dart';
import '../utils/unit_converter.dart';
import '../widgets/food_detail_sheet.dart';
import '../widgets/food_photo_thumbnail.dart';

/// 하루치 음식 기록(운동·물 제외)을 달력 칸 하나에 그리기 위한 묶음.
class MealCalendarDay {
  final List<DailyLogEntry> meals; // 시간순
  const MealCalendarDay(this.meals);

  List<DailyLogEntry> get photoMeals => meals.where((e) => e.photoPath != null).toList();
  String? get firstPhotoPath => photoMeals.isEmpty ? null : photoMeals.first.photoPath;
  int get photoCount => photoMeals.length;
  double get totalCalories => meals.fold(0, (sum, e) => sum + e.calories);
}

String mealCalendarDateKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// 기간 로그를 날짜(yyyy-MM-dd)별 음식 기록으로 묶는다. 음식 기록이 없는 날은 빠진다.
Map<String, MealCalendarDay> groupMealsByDay(List<DailyLogEntry> logs) {
  final byDay = <String, List<DailyLogEntry>>{};
  for (final e in logs) {
    if (e.type != LogType.food) continue;
    byDay.putIfAbsent(mealCalendarDateKey(e.datetime), () => []).add(e);
  }
  return {
    for (final entry in byDay.entries)
      entry.key: MealCalendarDay(entry.value..sort((a, b) => a.datetime.compareTo(b.datetime))),
  };
}

/// 월별 식사 사진 달력. 체중 기록 캘린더(WeightLogScreen)와 같은 그리드 구조를 쓰고,
/// 사진이 있는 날은 그날 첫 식사 사진 썸네일(여러 장이면 개수 배지)을, 사진 없이 직접
/// 입력만 한 날은 칼로리 점과 숫자만 보여준다. 날짜를 탭하면 그날 식사 목록 시트가 뜬다.
class MealCalendarScreen extends StatefulWidget {
  const MealCalendarScreen({super.key});

  @override
  State<MealCalendarScreen> createState() => _MealCalendarScreenState();
}

class _MealCalendarScreenState extends State<MealCalendarScreen> {
  late DateTime _month; // 보고 있는 달의 1일
  Map<String, MealCalendarDay> _days = {};
  UnitSystem _unitSystem = UnitSystem.metric;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month, 1);
    _load();
    UserProfileService.instance.getUnitSystem().then((u) {
      if (mounted) setState(() => _unitSystem = u);
    });
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final from = _month;
    final to = DateTime(_month.year, _month.month + 1, 0); // 이번 달 마지막 날
    final logs = await DatabaseHelper.instance.getLogsForRange(from, to);
    if (mounted) {
      setState(() {
        _days = groupMealsByDay(logs);
        _loading = false;
      });
    }
  }

  void _changeMonth(int delta) {
    setState(() => _month = DateTime(_month.year, _month.month + delta, 1));
    _load();
  }

  Future<void> _openDay(DateTime date, MealCalendarDay day) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _MealDaySheet(date: date, day: day, unitSystem: _unitSystem),
    );
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
            const Icon(Icons.photo_library_outlined, color: AppColors.foodCoral, size: 22),
            const SizedBox(width: 8),
            Flexible(child: Text(l10n.mealCalendarTitle, overflow: TextOverflow.ellipsis)),
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
                    // 체중 캘린더와 같이, 마지막 줄이 제스처 내비게이션 바에 가리지 않게 한다.
                    padding: EdgeInsets.fromLTRB(8, 8, 8, 8 + MediaQuery.of(context).padding.bottom),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 7,
                      childAspectRatio: 0.8,
                    ),
                    itemCount: firstDayOffset + daysInMonth,
                    itemBuilder: (context, index) {
                      if (index < firstDayOffset) return const SizedBox.shrink();

                      final day = index - firstDayOffset + 1;
                      final date = DateTime(_month.year, _month.month, day);
                      final meals = _days[mealCalendarDateKey(date)];
                      final isToday =
                          date.year == now.year && date.month == now.month && date.day == now.day;
                      return MealCalendarDayCell(
                        day: day,
                        meals: meals,
                        isToday: isToday,
                        onTap: meals == null ? null : () => _openDay(date, meals),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// 달력 한 칸: 날짜 숫자 아래에 첫 식사 사진(여러 장이면 개수 배지) 또는 칼로리 점+숫자.
class MealCalendarDayCell extends StatelessWidget {
  final int day;
  final MealCalendarDay? meals;
  final bool isToday;
  final VoidCallback? onTap;

  const MealCalendarDayCell({
    super.key,
    required this.day,
    required this.meals,
    this.isToday = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final meals = this.meals;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: isToday ? Border.all(color: AppColors.foodCoral, width: 1.5) : null,
        ),
        child: Column(
          children: [
            const SizedBox(height: 2),
            Text(
              '$day',
              style: TextStyle(fontSize: 12, fontWeight: isToday ? FontWeight.bold : FontWeight.normal),
            ),
            Expanded(
              child: meals == null
                  ? const SizedBox.shrink()
                  : meals.firstPhotoPath != null
                      ? _PhotoThumb(path: meals.firstPhotoPath!, count: meals.photoCount)
                      : _CalorieMark(calories: meals.totalCalories),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhotoThumb extends StatelessWidget {
  final String path;
  final int count;
  const _PhotoThumb({required this.path, required this.count});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 정수 크기로 맞춰 칸마다 같은 cacheWidth가 나오게 한다 — 그래야 디코딩된 축소
        // 이미지가 ImageCache에서 재사용되어 달을 넘기거나 스크롤할 때 다시 디코딩하지 않는다.
        final size = (math.min(constraints.maxWidth, constraints.maxHeight) - 4).floorToDouble();
        if (size <= 0) return const SizedBox.shrink();
        return Center(
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              FoodPhotoThumbnail(path: path, size: size, radius: 6),
              if (count > 1)
                Positioned(
                  right: -3,
                  top: -3,
                  child: Container(
                    key: const ValueKey('meal-photo-count'),
                    constraints: const BoxConstraints(minWidth: 15, minHeight: 15),
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      color: AppColors.foodCoral,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white, width: 1),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '$count',
                      style: const TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _CalorieMark extends StatelessWidget {
  final double calories;
  const _CalorieMark({required this.calories});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: const BoxDecoration(color: AppColors.foodCoral, shape: BoxShape.circle),
        ),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            calories.toStringAsFixed(0),
            style: const TextStyle(fontSize: 10, color: AppColors.foodCoral, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

/// 날짜를 탭하면 뜨는 그날 식사 목록. 항목을 탭하면 큰 사진과 영양 정보 시트를 연다.
class _MealDaySheet extends StatelessWidget {
  final DateTime date;
  final MealCalendarDay day;
  final UnitSystem unitSystem;

  const _MealDaySheet({required this.date, required this.day, required this.unitSystem});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.mealCalendarDayTitle(date.month, date.day),
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    l10n.mealCalendarDayTotal(day.totalCalories.toStringAsFixed(0)),
                    style: const TextStyle(fontSize: 13, color: AppColors.foodCoral, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: day.meals.length,
                itemBuilder: (context, i) {
                  final meal = day.meals[i];
                  return ListTile(
                    leading: FoodPhotoThumbnail(path: meal.photoPath, size: 48),
                    title: Text(meal.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                      '${DateFormat('HH:mm').format(meal.datetime)} · ${meal.calories.toStringAsFixed(0)} kcal',
                    ),
                    onTap: () => showFoodDetailSheet(context, meal, unitSystem),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
