import 'package:flutter/material.dart';

import '../db/database_helper.dart';
import '../models/daily_log_entry.dart';
import '../widgets/log_entry_tile.dart';

class DailyLogScreen extends StatefulWidget {
  const DailyLogScreen({super.key});

  @override
  State<DailyLogScreen> createState() => _DailyLogScreenState();
}

class _DailyLogScreenState extends State<DailyLogScreen> {
  final _db = DatabaseHelper.instance;
  final _today = DateTime.now();

  List<DailyLogEntry> _entries = [];
  DailySummary? _summary;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final entries = await _db.getLogsForDate(_today);
    final summary = await _db.getSummary(_today);
    setState(() {
      _entries = entries;
      _summary = summary;
    });
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
      appBar: AppBar(title: const Text('오늘의 로그')),
      body: Column(
        children: [
          _SummaryCard(summary: _summary),
          Expanded(
            child: _entries.isEmpty
                ? const Center(child: Text('아직 기록이 없어요. 사진을 찍어보세요!'))
                : ListView.builder(
                    itemCount: _entries.length,
                    itemBuilder: (context, i) {
                      final e = _entries[i];
                      return LogEntryTile(
                        entry: e,
                        onDelete: () async {
                          await _db.deleteLog(e.id!, _today);
                          _load();
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'daily_log_fab',
        onPressed: _quickAddWater,
        tooltip: '물 250ml 빠르게 추가',
        child: const Icon(Icons.water_drop),
      ),
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
