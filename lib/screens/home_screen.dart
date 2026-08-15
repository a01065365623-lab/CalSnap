import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../db/database_helper.dart';
import '../models/daily_log_entry.dart';
import '../services/ad_service.dart';
import '../services/tts_service.dart';
import '../services/user_profile_service.dart';
import '../theme/app_colors.dart';
import '../widgets/banner_ad_widget.dart';
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
      // centerDocked는 FAB을 bottomNavigationBar 슬롯의 "맨 위 가장자리"에 절반씩
      // 걸치도록(straddle) 배치한다. BottomAppBar 혼자였다면 CircularNotchedRectangle이
      // 그 부분을 실제로 오려내(notch) 겹침이 없었겠지만, 배너 광고는 notch 대상이
      // 아니라서 FAB 하단 절반이 배너 위에 그대로 겹쳐 그려졌다 — 이게 "운동" FAB이
      // 배너를 가리던 근본 원인이다. endFloat은 straddle 없이 bottomNavigationBar
      // 슬롯 전체(배너 실제 높이 + 하단바 높이, ad.size.height 기준으로 동적 측정된 값)
      // 위에 여백을 두고 완전히 위로 뜨므로 배너 크기가 기기별로 달라져도 항상 안전하다.
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      // 배너는 "오늘의 로그" 탭(_index == 0)에서만 보여준다. bottomNavigationBar
      // 전체를 이 Column의 실제 높이로 Scaffold가 인식해서 body 영역을 자동으로
      // 줄여주므로, 배너의 실제 높이(BannerAdWidget이 ad.size.height로 동적 측정)를
      // 수동으로 계산할 필요가 없다.
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_index == 0) const BannerAdWidget(),
          BottomAppBar(
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
        ],
      ),
    );
  }
}
