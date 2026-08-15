import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../db/database_helper.dart';
import '../models/daily_log_entry.dart';
import '../services/ad_service.dart';
import '../services/tts_service.dart';
import '../services/user_profile_service.dart';
import '../theme/app_colors.dart';
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

  @override
  void initState() {
    super.initState();
    _playAppOpenTts();
    // 시크릿 모드가 켜져 있으면 잠금 화면을 통과해야만 HomeScreen에 도달하므로,
    // 여기서 호출하는 것만으로 "잠금 화면에서는 광고 노출 안 함" 조건이 자연히 지켜진다.
    unawaited(AdService.instance.maybeShowInterstitialOnColdStart());
  }

  /// 앱 첫 진입 시 상황에 맞는 멘트 하나를 고른다. 여러 조건이 동시에 맞아도 음성이
  /// 겹쳐 재생되지 않도록 우선순위를 둔다: 저녁인데 운동을 안 했으면 그 리마인더가
  /// 가장 실용적이라 최우선, 그다음 스트릭 축하, 둘 다 아니면 기본 인사.
  Future<void> _playAppOpenTts() async {
    if (!await UserProfileService.instance.getTtsEnabled()) return;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    if (now.hour >= 18) {
      final logs = await DatabaseHelper.instance.getLogsForDate(today);
      final hasExercise = logs.any((e) => e.type == LogType.exercise);
      if (!hasExercise) {
        await TtsService.instance.speak(TtsCategory.exerciseReminder);
        return;
      }
    }

    // "오늘"은 아직 진행 중이라 스트릭에 포함하지 않고, 어제까지 연속 기록만 본다.
    final streak = await DatabaseHelper.instance
        .getStreakDaysEndingOn(today.subtract(const Duration(days: 1)));
    if (streak >= 3) {
      await TtsService.instance.speak(TtsCategory.streak);
      return;
    }

    await TtsService.instance.speak(TtsCategory.appOpen);
  }

  Future<void> _pushAndRefreshDailyLog(Widget screen) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
    if (mounted) setState(() => _dailyLogRefreshTick++);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
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
            backgroundColor: AppColors.exerciseTeal,
            foregroundColor: Colors.white,
            onPressed: () => _pushAndRefreshDailyLog(const ExerciseInputScreen()),
            icon: const Icon(Icons.fitness_center),
            label: Text(l10n.homeExerciseFabLabel),
          ),
          const SizedBox(width: 12),
          FloatingActionButton.extended(
            heroTag: 'home_fab',
            backgroundColor: AppColors.foodCoral,
            foregroundColor: Colors.white,
            onPressed: () => _pushAndRefreshDailyLog(const QuickModeScreen()),
            icon: const Icon(Icons.camera_alt),
            label: Text(l10n.homeCameraFabLabel),
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
              icon: Icon(Icons.bar_chart, color: _index == 1 ? AppColors.statsGray : Colors.grey),
              onPressed: () => setState(() => _index = 1),
            ),
            IconButton(
              icon: Icon(Icons.settings, color: _index == 2 ? AppColors.statsGray : Colors.grey),
              onPressed: () => setState(() => _index = 2),
            ),
          ],
        ),
      ),
    );
  }
}
