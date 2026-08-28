import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:fl_chart/fl_chart.dart';

import '../db/database_helper.dart';
import '../models/daily_log_entry.dart';
import '../theme/app_colors.dart';
import 'daily_log_screen.dart';
import 'weight_log_screen.dart';

enum _Period { week, month, year }

extension on _Period {
  int get days {
    switch (this) {
      case _Period.week:
        return 7;
      case _Period.month:
        return 30;
      case _Period.year:
        return 365;
    }
  }

  String label(AppLocalizations l10n) {
    switch (this) {
      case _Period.week:
        return l10n.statsPeriodWeek;
      case _Period.month:
        return l10n.statsPeriodMonth;
      case _Period.year:
        return l10n.statsPeriodYear;
    }
  }
}

enum _Category { calorie, weight, exercise, nutrition }

extension on _Category {
  String label(AppLocalizations l10n) {
    switch (this) {
      case _Category.calorie:
        return l10n.statsCategoryCalorie;
      case _Category.weight:
        return l10n.statsCategoryWeight;
      case _Category.exercise:
        return l10n.statsCategoryExercise;
      case _Category.nutrition:
        return l10n.statsCategoryNutrition;
    }
  }

  IconData get icon {
    switch (this) {
      case _Category.calorie:
        return Icons.local_fire_department;
      case _Category.weight:
        return Icons.monitor_weight_outlined;
      case _Category.exercise:
        return Icons.fitness_center;
      case _Category.nutrition:
        return Icons.pie_chart_outline;
    }
  }

  /// 칼로리=통계(그레이), 체중/운동량=틸, 영양소=음식(코랄) — 기존 카테고리 컬러 재사용.
  Color get color {
    switch (this) {
      case _Category.calorie:
        return AppColors.statsGray;
      case _Category.weight:
        return AppColors.weightTeal;
      case _Category.exercise:
        return AppColors.exerciseTeal;
      case _Category.nutrition:
        return AppColors.foodCoral;
    }
  }
}

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  _Period _period = _Period.week;
  List<DailySummary> _calorieData = [];
  Map<String, double> _weightMap = {};
  List<ExerciseSummary> _exerciseData = [];
  List<NutrientSummary> _nutrientData = [];
  bool _loading = true;
  // 통계 화면이 "안 열림"으로 보이는 가장 흔한 원인은 _load() 안에서 발생한 예외를
  // 잡지 않아 _loading이 영원히 true로 남는 것이었다. 예외를 잡아 화면에 보여주고
  // 재시도할 수 있게 한다.
  Object? _loadError;

  /// null이면 "오늘 기준 최근 N일". 값이 있으면 이 날짜부터 시작하는 구간을 본다.
  /// 연간 뷰는 구간 직접 선택을 지원하지 않는다(항상 최근 365일).
  DateTime? _rangeStart;
  late DateTime _rangeFrom;
  late DateTime _rangeTo;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _Category.values.length, vsync: this);
    _tabController.addListener(() => setState(() {})); // 탭 전환 시 하단 안내 문구 갱신
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    final now = DateTime.now();
    final from = (_period != _Period.year && _rangeStart != null)
        ? _rangeStart!
        : now.subtract(Duration(days: _period.days - 1));
    final to = from.add(Duration(days: _period.days - 1));

    try {
      final calorieFuture = DatabaseHelper.instance.getSummaryRange(from, to);
      final weightFuture = DatabaseHelper.instance.getWeightsForRange(from, to);
      final exerciseFuture = DatabaseHelper.instance.getExerciseSummaryRange(from, to);
      final nutrientFuture = DatabaseHelper.instance.getNutrientSummaryRange(from, to);

      final calorieData = await calorieFuture;
      final weightMap = await weightFuture;
      final exerciseData = await exerciseFuture;
      final nutrientData = await nutrientFuture;

      if (!mounted) return;
      setState(() {
        _calorieData = calorieData;
        _weightMap = weightMap;
        _exerciseData = exerciseData;
        _nutrientData = nutrientData;
        _rangeFrom = from;
        _rangeTo = to;
        _loading = false;
      });
    } catch (e, st) {
      // 예외를 그냥 흘려보내면 이 Future는 아무도 await하지 않으므로(initState에서
      // _load()를 fire-and-forget으로 호출) 조용히 사라지고 _loading만 영원히 true로
      // 남아 화면이 "안 열림/멈춤"처럼 보인다. 반드시 잡아서 에러 상태로 보여준다.
      debugPrint('[StatsScreen] _load() 실패: $e\n$st');
      if (!mounted) return;
      setState(() {
        _loadError = e;
        _loading = false;
      });
    }
  }

  void _changePeriod(_Period period) {
    if (period == _period) return;
    setState(() {
      _period = period;
      _rangeStart = null; // 기간을 바꾸면 직접 지정한 구간은 초기화
    });
    _load();
  }

  Future<void> _pickRangeStart() async {
    final now = DateTime.now();
    final lastPossibleStart = now.subtract(Duration(days: _period.days - 1));
    final picked = await showDatePicker(
      context: context,
      initialDate: _rangeStart ?? lastPossibleStart,
      firstDate: DateTime(2020),
      lastDate: lastPossibleStart.isBefore(DateTime(2020)) ? DateTime(2020) : lastPossibleStart,
    );
    if (picked == null) return;
    setState(() => _rangeStart = picked);
    _load();
  }

  void _resetToToday() {
    setState(() => _rangeStart = null);
    _load();
  }

  void _openDayDetail(DateTime date) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => DailyLogScreen(initialDate: date)));
  }

  Future<void> _openWeightEdit(DateTime date) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => WeightLogScreen(initialDate: date)),
    );
    _load(); // 체중을 수정/삭제했을 수 있으니 그래프를 갱신한다.
  }

  String _rangeHeaderText(AppLocalizations l10n) {
    final base = l10n.statsDateRange(_rangeFrom.month, _rangeFrom.day, _rangeTo.month, _rangeTo.day);
    if (_Category.values[_tabController.index] == _Category.calorie) {
      return '$base${l10n.statsCalorieRangeSuffix(_calorieData.length)}';
    }
    return base;
  }

  String _tapHintText(AppLocalizations l10n) {
    return _Category.values[_tabController.index] == _Category.weight
        ? l10n.statsTapHintWeight
        : l10n.statsTapHintDefault;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.bar_chart, color: AppColors.statsGray, size: 22),
            const SizedBox(width: 8),
            Text(l10n.statsAppBarTitle),
          ],
        ),
      ),
      body: Column(
        children: [
          TabBar(
            controller: _tabController,
            labelColor: AppColors.statsGray,
            unselectedLabelColor: Colors.grey.shade400,
            indicatorColor: AppColors.statsGray,
            tabs: _Category.values
                .map((c) => Tab(icon: Icon(c.icon, color: c.color), text: c.label(l10n)))
                .toList(),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SegmentedButton<_Period>(
                    segments: _Period.values
                        .map((p) => ButtonSegment(value: p, label: Text(p.label(l10n))))
                        .toList(),
                    selected: {_period},
                    onSelectionChanged: (selection) => _changePeriod(selection.first),
                  ),
                  if (_period != _Period.year) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        TextButton.icon(
                          onPressed: _pickRangeStart,
                          icon: const Icon(Icons.date_range, size: 18, color: AppColors.statsGray),
                          label: Text(_rangeStart != null
                              ? l10n.statsRangeChangeButton
                              : l10n.statsRangePickButton),
                        ),
                        if (_rangeStart != null)
                          TextButton(onPressed: _resetToToday, child: Text(l10n.statsResetToTodayButton)),
                      ],
                    ),
                  ],
                  const SizedBox(height: 8),
                  // _rangeFrom/_rangeTo는 _load()가 성공했을 때만 채워지는 late 필드라,
                  // 로딩 실패 시(_loadError != null)에도 !_loading만 보고 접근하면
                  // LateInitializationError로 또 다른 크래시가 난다.
                  if (!_loading && _loadError == null)
                    Text(
                      _rangeHeaderText(l10n),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  const SizedBox(height: 4),
                  Text(
                    _tapHintText(l10n),
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: _loading
                        ? const Center(child: CircularProgressIndicator())
                        : _loadError != null
                            ? _StatsLoadErrorView(error: _loadError!, onRetry: _load)
                            : TabBarView(
                            controller: _tabController,
                            children: [
                              _CalorieTab(
                                data: _calorieData,
                                from: _rangeFrom,
                                to: _rangeTo,
                                period: _period,
                                onTapDate: _openDayDetail,
                              ),
                              _WeightTab(
                                weights: _weightMap,
                                from: _rangeFrom,
                                to: _rangeTo,
                                period: _period,
                                onTapDate: _openWeightEdit,
                              ),
                              _ExerciseTab(
                                data: _exerciseData,
                                from: _rangeFrom,
                                to: _rangeTo,
                                period: _period,
                                onTapDate: _openDayDetail,
                              ),
                              _NutritionTab(
                                data: _nutrientData,
                                from: _rangeFrom,
                                to: _rangeTo,
                                period: _period,
                                onTapDate: _openDayDetail,
                              ),
                            ],
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 통계 데이터 로딩이 실패했을 때 무한 로딩 대신 보여주는 화면. 재시도 버튼 제공.
class _StatsLoadErrorView extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;

  const _StatsLoadErrorView({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, color: Colors.grey, size: 36),
          const SizedBox(height: 8),
          Text(l10n.statsLoadErrorMessage, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: Text(l10n.retryButton),
          ),
        ],
      ),
    );
  }
}

String _shortDate(String yyyyMMdd) {
  final parts = yyyyMMdd.split('-');
  return '${int.parse(parts[1])}/${int.parse(parts[2])}';
}

String _dateKeyOf(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// [from]~[to] 사이 모든 날짜를 하루 단위로 나열한다(기록 유무 무관).
List<DateTime> _dateRange(DateTime from, DateTime to) {
  final days = to.difference(from).inDays + 1;
  return [for (int i = 0; i < days; i++) DateTime(from.year, from.month, from.day + i)];
}

// ── 칼로리 탭 (기존 로직 그대로) ──────────────────────────────

class _CalorieTab extends StatelessWidget {
  final List<DailySummary> data;
  final DateTime from;
  final DateTime to;
  final _Period period;
  final void Function(DateTime date) onTapDate;

  const _CalorieTab({
    required this.data,
    required this.from,
    required this.to,
    required this.period,
    required this.onTapDate,
  });

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return Center(child: Text(AppLocalizations.of(context)!.statsInsufficientData));
    }
    if (period == _Period.year) {
      final dates = _dateRange(from, to);
      final byDate = {for (final s in data) s.date: s};
      return _YearLineChart(
        dates: dates,
        series: [
          _YearSeries(
            values: [for (final d in dates) byDate[_dateKeyOf(d)]?.netCalories],
            color: AppColors.statsGray,
          ),
        ],
        onTapDate: onTapDate,
      );
    }
    return _SummaryBarChart(data: data, period: period, onTapDate: onTapDate);
  }
}

/// 주간(7일)/월간(30일) 뷰: 날짜별 순칼로리 막대그래프. 막대를 탭하면 그날 상세로 이동.
class _SummaryBarChart extends StatelessWidget {
  final List<DailySummary> data;
  final _Period period;
  final void Function(DateTime date) onTapDate;

  const _SummaryBarChart({required this.data, required this.period, required this.onTapDate});

  @override
  Widget build(BuildContext context) {
    // 월간 뷰는 막대가 많아서 라벨을 5일 간격으로만 표시한다.
    final labelInterval = period == _Period.month ? 5 : 1;

    return BarChart(
      BarChartData(
        barTouchData: BarTouchData(
          touchCallback: (event, response) {
            if (event is! FlTapUpEvent) return;
            final index = response?.spot?.touchedBarGroupIndex;
            if (index == null || index < 0 || index >= data.length) return;
            onTapDate(DateTime.parse(data[index].date));
          },
        ),
        barGroups: [
          for (int i = 0; i < data.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: data[i].netCalories,
                  color: data[i].netCalories >= 0 ? Colors.deepOrange : Colors.teal,
                  width: period == _Period.month ? 4 : 12,
                ),
              ],
            ),
        ],
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i >= data.length || i % labelInterval != 0) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(_shortDate(data[i].date), style: const TextStyle(fontSize: 10)),
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        gridData: const FlGridData(show: true, drawVerticalLine: false),
      ),
    );
  }
}

/// [_YearLineChart]에 그릴 선 하나(값 배열 + 색상). 나눠진 세그먼트 계산은
/// [_YearLineChart]가 공통으로 처리한다.
class _YearSeries {
  final List<double?> values;
  final Color color;

  const _YearSeries({required this.values, required this.color});

  List<List<FlSpot>> _segments() {
    final segments = <List<FlSpot>>[];
    List<FlSpot>? current;
    for (int i = 0; i < values.length; i++) {
      final v = values[i];
      if (v == null) {
        current = null;
        continue;
      }
      if (current == null) {
        current = [];
        segments.add(current);
      }
      current.add(FlSpot(i.toDouble(), v));
    }
    return segments;
  }
}

/// 연간(365일) 뷰 공용 선그래프: 365개 포인트를 하나(또는 여러 개)의 이어진
/// 선으로 그리되, 기록이 없는 날짜에서는 구간을 나눠 선을 끊는다. x축은 라벨이
/// 겹치지 않도록 월이 바뀌는 날짜에만 표시한다. 포인트를 탭하면 그날 상세로 이동.
class _YearLineChart extends StatelessWidget {
  final List<DateTime> dates;
  final List<_YearSeries> series;
  final void Function(DateTime date) onTapDate;

  const _YearLineChart({
    required this.dates,
    required this.series,
    required this.onTapDate,
  });

  @override
  Widget build(BuildContext context) {
    final recorded = [for (final s in series) ...s.values.whereType<double>()];
    if (recorded.isEmpty) {
      // 호출부에서 이미 데이터 존재 여부를 확인하지만, 날짜 범위 확장 과정에서
      // 값이 하나도 안 남는 예외적인 경우를 대비한 방어 코드.
      return const SizedBox.shrink();
    }
    final minVal = recorded.reduce((a, b) => a < b ? a : b);
    final maxVal = recorded.reduce((a, b) => a > b ? a : b);
    final pad = ((maxVal - minVal) * 0.1).clamp(1.0, double.infinity);
    final minY = (minVal - pad).floorToDouble();
    final maxY = (maxVal + pad).ceilToDouble();

    return LineChart(
      LineChartData(
        minY: minY,
        maxY: maxY,
        lineTouchData: LineTouchData(
          touchCallback: (event, response) {
            if (event is! FlTapUpEvent) return;
            final spots = response?.lineBarSpots;
            if (spots == null || spots.isEmpty) return;
            final index = spots.first.x.toInt();
            if (index < 0 || index >= dates.length) return;
            onTapDate(dates[index]);
          },
        ),
        lineBarsData: [
          for (final s in series)
            for (final segment in s._segments())
              LineChartBarData(
                spots: segment,
                isCurved: true,
                color: s.color,
                barWidth: 2,
                dotData: const FlDotData(show: false),
                belowBarData: BarAreaData(show: false),
              ),
        ],
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i >= dates.length) return const SizedBox.shrink();
                // 365개를 다 라벨링하면 겹치므로 월이 바뀌는 날에만 표시한다.
                final isMonthMark = i == 0 || dates[i].day == 1;
                if (!isMonthMark) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('${dates[i].month}', style: const TextStyle(fontSize: 10)),
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        gridData: const FlGridData(show: true, drawVerticalLine: false),
      ),
    );
  }
}

// ── 체중 탭 ──────────────────────────────────────────────

class _WeightTab extends StatelessWidget {
  final Map<String, double> weights;
  final DateTime from;
  final DateTime to;
  final _Period period;
  final void Function(DateTime date) onTapDate;

  const _WeightTab({
    required this.weights,
    required this.from,
    required this.to,
    required this.period,
    required this.onTapDate,
  });

  @override
  Widget build(BuildContext context) {
    if (weights.isEmpty) {
      return Center(child: Text(AppLocalizations.of(context)!.statsNoWeightRecorded));
    }
    final dates = _dateRange(from, to);
    return period == _Period.year
        ? _YearLineChart(
            dates: dates,
            series: [
              _YearSeries(
                values: [for (final d in dates) weights[_dateKeyOf(d)]],
                color: AppColors.weightTeal,
              ),
            ],
            onTapDate: onTapDate,
          )
        : _WeightLineChart(dates: dates, weights: weights, period: period, onTapDate: onTapDate);
  }
}

/// 기록이 없는 날짜에서는 선을 잇지 않고 구간을 나눠, 값이 있는 날짜끼리만 자연스럽게 이어 그린다.
class _WeightLineChart extends StatelessWidget {
  final List<DateTime> dates;
  final Map<String, double> weights;
  final _Period period;
  final void Function(DateTime date) onTapDate;

  const _WeightLineChart({
    required this.dates,
    required this.weights,
    required this.period,
    required this.onTapDate,
  });

  @override
  Widget build(BuildContext context) {
    final values = [for (final d in dates) weights[_dateKeyOf(d)]];

    final segments = <List<FlSpot>>[];
    List<FlSpot>? current;
    for (int i = 0; i < values.length; i++) {
      final v = values[i];
      if (v == null) {
        current = null;
        continue;
      }
      if (current == null) {
        current = [];
        segments.add(current);
      }
      current.add(FlSpot(i.toDouble(), v));
    }

    final recorded = values.whereType<double>().toList();
    if (recorded.isEmpty) {
      // weights는 [from, to] 범위로 DB에서 가져온 것과 dates가 같은 범위여야 정상이지만,
      // 방어적으로 한 번 더 확인한다 — 비어있으면 reduce()가 StateError를 던져 통계
      // 화면 전체가 크래시하기 때문이다.
      return Center(child: Text(AppLocalizations.of(context)!.statsNoWeightRecorded));
    }
    final minY = (recorded.reduce((a, b) => a < b ? a : b) - 1).floorToDouble();
    final maxY = (recorded.reduce((a, b) => a > b ? a : b) + 1).ceilToDouble();
    final labelInterval = period == _Period.month ? 5 : 1;

    return LineChart(
      LineChartData(
        minY: minY,
        maxY: maxY,
        lineTouchData: LineTouchData(
          touchCallback: (event, response) {
            if (event is! FlTapUpEvent) return;
            final spots = response?.lineBarSpots;
            if (spots == null || spots.isEmpty) return;
            final index = spots.first.x.toInt();
            if (index < 0 || index >= dates.length) return;
            onTapDate(dates[index]);
          },
        ),
        lineBarsData: [
          for (final segment in segments)
            LineChartBarData(
              spots: segment,
              isCurved: true,
              color: AppColors.weightTeal,
              barWidth: 3,
              dotData: const FlDotData(show: true),
              belowBarData: BarAreaData(show: false),
            ),
        ],
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i >= dates.length || i % labelInterval != 0) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(_shortDate(_dateKeyOf(dates[i])), style: const TextStyle(fontSize: 10)),
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        gridData: const FlGridData(show: true, drawVerticalLine: false),
      ),
    );
  }
}

// ── 운동량 탭 ──────────────────────────────────────────────

enum _ExerciseMetric { calories, minutes }

class _ExerciseTab extends StatefulWidget {
  final List<ExerciseSummary> data;
  final DateTime from;
  final DateTime to;
  final _Period period;
  final void Function(DateTime date) onTapDate;

  const _ExerciseTab({
    required this.data,
    required this.from,
    required this.to,
    required this.period,
    required this.onTapDate,
  });

  @override
  State<_ExerciseTab> createState() => _ExerciseTabState();
}

class _ExerciseTabState extends State<_ExerciseTab> {
  _ExerciseMetric _metric = _ExerciseMetric.calories;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    if (widget.data.isEmpty) {
      return Center(child: Text(l10n.statsNoExerciseRecorded));
    }

    final dates = _dateRange(widget.from, widget.to);
    final byDate = {for (final e in widget.data) e.date: e};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SegmentedButton<_ExerciseMetric>(
          segments: [
            ButtonSegment(
                value: _ExerciseMetric.calories, label: Text(l10n.exerciseInputCustomCaloriesLabel)),
            ButtonSegment(value: _ExerciseMetric.minutes, label: Text(l10n.exerciseInputDurationLabel)),
          ],
          selected: {_metric},
          onSelectionChanged: (selection) => setState(() => _metric = selection.first),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: widget.period == _Period.year
              ? _YearLineChart(
                  dates: dates,
                  series: [
                    _YearSeries(
                      values: [
                        for (final d in dates)
                          byDate[_dateKeyOf(d)] == null
                              ? null
                              : (_metric == _ExerciseMetric.calories
                                  ? byDate[_dateKeyOf(d)]!.caloriesBurned
                                  : byDate[_dateKeyOf(d)]!.minutes),
                      ],
                      color: AppColors.exerciseTeal,
                    ),
                  ],
                  onTapDate: widget.onTapDate,
                )
              : _ExerciseBarChart(
                  dates: dates,
                  byDate: byDate,
                  period: widget.period,
                  metric: _metric,
                  onTapDate: widget.onTapDate,
                ),
        ),
      ],
    );
  }
}

class _ExerciseBarChart extends StatelessWidget {
  final List<DateTime> dates;
  final Map<String, ExerciseSummary> byDate;
  final _Period period;
  final _ExerciseMetric metric;
  final void Function(DateTime date) onTapDate;

  const _ExerciseBarChart({
    required this.dates,
    required this.byDate,
    required this.period,
    required this.metric,
    required this.onTapDate,
  });

  double _valueFor(DateTime d) {
    final e = byDate[_dateKeyOf(d)];
    if (e == null) return 0;
    return metric == _ExerciseMetric.calories ? e.caloriesBurned : e.minutes;
  }

  @override
  Widget build(BuildContext context) {
    final labelInterval = period == _Period.month ? 5 : 1;

    return BarChart(
      BarChartData(
        barTouchData: BarTouchData(
          touchCallback: (event, response) {
            if (event is! FlTapUpEvent) return;
            final index = response?.spot?.touchedBarGroupIndex;
            if (index == null || index < 0 || index >= dates.length) return;
            onTapDate(dates[index]);
          },
        ),
        barGroups: [
          for (int i = 0; i < dates.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: _valueFor(dates[i]),
                  color: AppColors.exerciseTeal,
                  width: period == _Period.month ? 4 : 12,
                ),
              ],
            ),
        ],
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i >= dates.length || i % labelInterval != 0) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(_shortDate(_dateKeyOf(dates[i])), style: const TextStyle(fontSize: 10)),
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        gridData: const FlGridData(show: true, drawVerticalLine: false),
      ),
    );
  }
}

// ── 영양소 탭 ──────────────────────────────────────────────

class _NutritionTab extends StatelessWidget {
  final List<NutrientSummary> data;
  final DateTime from;
  final DateTime to;
  final _Period period;
  final void Function(DateTime date) onTapDate;

  const _NutritionTab({
    required this.data,
    required this.from,
    required this.to,
    required this.period,
    required this.onTapDate,
  });

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return Center(child: Text(AppLocalizations.of(context)!.statsNoFoodRecorded));
    }

    final dates = _dateRange(from, to);
    final byDate = {for (final n in data) n.date: n};

    final totalCarbs = data.fold<double>(0, (sum, n) => sum + n.carbsG);
    final totalProtein = data.fold<double>(0, (sum, n) => sum + n.proteinG);
    final totalFat = data.fold<double>(0, (sum, n) => sum + n.fatG);
    // 탄수화물/단백질 4kcal/g, 지방 9kcal/g 기준 칼로리 비율.
    final carbsCal = totalCarbs * 4;
    final proteinCal = totalProtein * 4;
    final fatCal = totalFat * 9;
    final totalCal = carbsCal + proteinCal + fatCal;
    final carbsRatio = totalCal > 0 ? carbsCal / totalCal : 0.0;
    final proteinRatio = totalCal > 0 ? proteinCal / totalCal : 0.0;
    final fatRatio = totalCal > 0 ? fatCal / totalCal : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _MacroRatioSummary(
          carbsRatio: carbsRatio,
          proteinRatio: proteinRatio,
          fatRatio: fatRatio,
          days: data.length,
        ),
        const SizedBox(height: 16),
        Expanded(
          child: period == _Period.year
              ? _YearLineChart(
                  dates: dates,
                  series: [
                    _YearSeries(
                      values: [for (final d in dates) byDate[_dateKeyOf(d)]?.carbsG],
                      color: AppColors.foodCoral,
                    ),
                    _YearSeries(
                      values: [for (final d in dates) byDate[_dateKeyOf(d)]?.proteinG],
                      color: AppColors.exerciseTeal,
                    ),
                    _YearSeries(
                      values: [for (final d in dates) byDate[_dateKeyOf(d)]?.fatG],
                      color: AppColors.statsGray,
                    ),
                  ],
                  onTapDate: onTapDate,
                )
              : _NutritionStackedBarChart(dates: dates, byDate: byDate, period: period, onTapDate: onTapDate),
        ),
      ],
    );
  }
}

class _MacroRatioSummary extends StatelessWidget {
  final double carbsRatio;
  final double proteinRatio;
  final double fatRatio;
  final int days;

  const _MacroRatioSummary({
    required this.carbsRatio,
    required this.proteinRatio,
    required this.fatRatio,
    required this.days,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.statsMacroRatioTitle(days), style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            height: 12,
            child: Row(
              children: [
                if (carbsRatio > 0)
                  Expanded(
                    flex: (carbsRatio * 1000).round().clamp(1, 1000),
                    child: Container(color: AppColors.foodCoral),
                  ),
                if (proteinRatio > 0)
                  Expanded(
                    flex: (proteinRatio * 1000).round().clamp(1, 1000),
                    child: Container(color: AppColors.exerciseTeal),
                  ),
                if (fatRatio > 0)
                  Expanded(
                    flex: (fatRatio * 1000).round().clamp(1, 1000),
                    child: Container(color: AppColors.statsGray),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 16,
          children: [
            _MacroLegend(
              color: AppColors.foodCoral,
              label: '${l10n.macroCarbsLabel} ${(carbsRatio * 100).toStringAsFixed(0)}%',
            ),
            _MacroLegend(
              color: AppColors.exerciseTeal,
              label: '${l10n.macroProteinLabel} ${(proteinRatio * 100).toStringAsFixed(0)}%',
            ),
            _MacroLegend(
              color: AppColors.statsGray,
              label: '${l10n.macroFatLabel} ${(fatRatio * 100).toStringAsFixed(0)}%',
            ),
          ],
        ),
      ],
    );
  }
}

class _MacroLegend extends StatelessWidget {
  final Color color;
  final String label;

  const _MacroLegend({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}

class _NutritionStackedBarChart extends StatelessWidget {
  final List<DateTime> dates;
  final Map<String, NutrientSummary> byDate;
  final _Period period;
  final void Function(DateTime date) onTapDate;

  const _NutritionStackedBarChart({
    required this.dates,
    required this.byDate,
    required this.period,
    required this.onTapDate,
  });

  BarChartGroupData _stackedGroup(int index, DateTime date) {
    final n = byDate[_dateKeyOf(date)];
    final carbs = n?.carbsG ?? 0;
    final protein = n?.proteinG ?? 0;
    final fat = n?.fatG ?? 0;
    final total = carbs + protein + fat;

    return BarChartGroupData(
      x: index,
      barRods: [
        BarChartRodData(
          toY: total,
          width: period == _Period.month ? 4 : 12,
          rodStackItems: [
            BarChartRodStackItem(0, carbs, AppColors.foodCoral),
            BarChartRodStackItem(carbs, carbs + protein, AppColors.exerciseTeal),
            BarChartRodStackItem(carbs + protein, total, AppColors.statsGray),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final labelInterval = period == _Period.month ? 5 : 1;

    return BarChart(
      BarChartData(
        barTouchData: BarTouchData(
          touchCallback: (event, response) {
            if (event is! FlTapUpEvent) return;
            final index = response?.spot?.touchedBarGroupIndex;
            if (index == null || index < 0 || index >= dates.length) return;
            onTapDate(dates[index]);
          },
        ),
        barGroups: [for (int i = 0; i < dates.length; i++) _stackedGroup(i, dates[i])],
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i >= dates.length || i % labelInterval != 0) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(_shortDate(_dateKeyOf(dates[i])), style: const TextStyle(fontSize: 10)),
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        gridData: const FlGridData(show: true, drawVerticalLine: false),
      ),
    );
  }
}

