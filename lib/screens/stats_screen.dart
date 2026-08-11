import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

import '../db/database_helper.dart';
import '../models/daily_log_entry.dart';
import 'daily_log_screen.dart';

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

  String get label {
    switch (this) {
      case _Period.week:
        return '주간';
      case _Period.month:
        return '월간';
      case _Period.year:
        return '연간';
    }
  }
}

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  _Period _period = _Period.week;
  List<DailySummary> _data = [];
  bool _loading = true;

  /// null이면 "오늘 기준 최근 N일". 값이 있으면 이 날짜부터 시작하는 구간을 본다.
  /// 연간 뷰는 구간 직접 선택을 지원하지 않는다(항상 최근 365일).
  DateTime? _rangeStart;
  late DateTime _rangeFrom;
  late DateTime _rangeTo;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final now = DateTime.now();
    final from = (_period != _Period.year && _rangeStart != null)
        ? _rangeStart!
        : now.subtract(Duration(days: _period.days - 1));
    final to = from.add(Duration(days: _period.days - 1));
    final data = await DatabaseHelper.instance.getSummaryRange(from, to);
    setState(() {
      _data = data;
      _rangeFrom = from;
      _rangeTo = to;
      _loading = false;
    });
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('통계')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SegmentedButton<_Period>(
              segments: _Period.values
                  .map((p) => ButtonSegment(value: p, label: Text(p.label)))
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
                    icon: const Icon(Icons.date_range, size: 18),
                    label: Text(_rangeStart != null ? '기간 변경' : '기간 직접 선택'),
                  ),
                  if (_rangeStart != null)
                    TextButton(onPressed: _resetToToday, child: const Text('오늘 기준으로')),
                ],
              ),
            ],
            const SizedBox(height: 8),
            if (!_loading)
              Text(
                '${_rangeFrom.month}월 ${_rangeFrom.day}일 ~ ${_rangeTo.month}월 ${_rangeTo.day}일 순칼로리 · 기록 ${_data.length}일',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            const SizedBox(height: 4),
            Text(
              '날짜를 탭하면 그날의 상세 기록을 볼 수 있어요',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _data.isEmpty
                      ? const Center(child: Text('아직 데이터가 부족해요'))
                      : _period == _Period.year
                          ? _SummaryList(data: _data, onTapDate: _openDayDetail)
                          : _SummaryBarChart(data: _data, period: _period, onTapDate: _openDayDetail),
            ),
          ],
        ),
      ),
    );
  }
}

String _shortDate(String yyyyMMdd) {
  final parts = yyyyMMdd.split('-');
  return '${int.parse(parts[1])}/${int.parse(parts[2])}';
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

const List<String> _weekdayNames = ['월', '화', '수', '목', '금', '토', '일'];

/// 연간(365일) 뷰: 막대 365개나 선 하나로는 눈이 아프니 날짜별 텍스트 리스트로 보여준다.
/// 각 행을 탭하면 그날 상세로 이동.
class _SummaryList extends StatelessWidget {
  final List<DailySummary> data;
  final void Function(DateTime date) onTapDate;

  const _SummaryList({required this.data, required this.onTapDate});

  @override
  Widget build(BuildContext context) {
    final reversed = data.reversed.toList(); // 최신 날짜가 위로
    return ListView.separated(
      itemCount: reversed.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final s = reversed[i];
        final date = DateTime.parse(s.date);
        final weekday = _weekdayNames[date.weekday - 1];
        return ListTile(
          dense: true,
          title: Text('${date.month}월 ${date.day}일 ($weekday)'),
          subtitle: Text('섭취 ${s.totalIntake.toStringAsFixed(0)} · 소모 ${s.totalBurned.toStringAsFixed(0)}'),
          trailing: Text(
            '${s.netCalories >= 0 ? '+' : ''}${s.netCalories.toStringAsFixed(0)} kcal',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: s.netCalories >= 0 ? Colors.deepOrange : Colors.teal,
            ),
          ),
          onTap: () => onTapDate(date),
        );
      },
    );
  }
}
