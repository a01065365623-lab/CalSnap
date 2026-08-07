import 'package:flutter/material.dart';

import 'daily_log_screen.dart';
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

  final _screens = const [
    DailyLogScreen(),
    StatsScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_index],
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'home_fab',
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const QuickModeScreen()),
        ),
        icon: const Icon(Icons.camera_alt),
        label: const Text('찍기'),
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
