import 'package:flutter/material.dart';

import 'daily_log_screen.dart';
import 'exercise_input_screen.dart';
import 'quick_mode_screen.dart';
import 'settings_screen.dart';
import 'stats_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;
  int _dailyLogRefreshTick = 0;

  Future<void> _pushAndRefreshDailyLog(Widget screen) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
    if (mounted) setState(() => _dailyLogRefreshTick++);
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      DailyLogScreen(key: ValueKey(_dailyLogRefreshTick)),
      const StatsScreen(),
      const SettingsScreen(),
    ];
    return Scaffold(
      body: screens[_index],
      floatingActionButton: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.extended(
            heroTag: 'exercise_fab',
            onPressed: () => _pushAndRefreshDailyLog(const ExerciseInputScreen()),
            icon: const Icon(Icons.fitness_center),
            label: const Text('운동'),
          ),
          const SizedBox(width: 12),
          FloatingActionButton.extended(
            heroTag: 'home_fab',
            onPressed: () => _pushAndRefreshDailyLog(const QuickModeScreen()),
            icon: const Icon(Icons.camera_alt),
            label: const Text('찍기'),
          ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: BottomAppBar(
        shape: const CircularNotchedRectangle(),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            IconButton(
              icon: Icon(Icons.list_alt, color: _index == 0 ? Colors.deepOrange : Colors.grey),
              onPressed: () => setState(() => _index = 0),
            ),
            IconButton(
              icon: Icon(Icons.bar_chart, color: _index == 1 ? Colors.deepOrange : Colors.grey),
              onPressed: () => setState(() => _index = 1),
            ),
            IconButton(
              icon: Icon(Icons.settings, color: _index == 2 ? Colors.deepOrange : Colors.grey),
              onPressed: () => setState(() => _index = 2),
            ),
          ],
        ),
      ),
    );
  }
}
