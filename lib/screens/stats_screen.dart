import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

import '../db/database_helper.dart';
import '../models/daily_log_entry.dart';

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  List<DailySummary> _weekData = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final now = DateTime.now();
    final weekAgo = now.subtract(const Duration(days: 6));
    final data = await DatabaseHelper.instance.getSummaryRange(weekAgo, now);
    setState(() => _weekData = data);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('통계')),
      body: _weekData.isEmpty
          ? const Center(child: Text('아직 데이터가 부족해요'))
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('최근 7일 순칼로리', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 220,
                    child: LineChart(
                      LineChartData(
                        lineBarsData: [
                          LineChartBarData(
                            spots: [
                              for (int i = 0; i < _weekData.length; i++)
                                FlSpot(i.toDouble(), _weekData[i].netCalories),
                            ],
                            isCurved: true,
                            dotData: const FlDotData(show: true),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
