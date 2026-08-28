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
    unawaited(_playAppOpenTtsThenMaybeShowAd());
  }

  /// TTS 앱 오픈 멘트와 전면광고가 동시에 트리거되면 소리가 겹쳐서, TTS가 (실제로)
  /// 다 재생된 뒤 최소 2초를 더 기다렸다가 광고를 띄우도록 순서를 강제한다.
  /// TtsService가 awaitSpeakCompletion(true)를 켜두므로 _playAppOpenTts()의 await는
  /// 재생 시작이 아니라 재생 "완료" 시점에 끝난다.
  Future<void> _playAppOpenTtsThenMaybeShowAd() async {
    final spoke = await _playAppOpenTts();
    if (spoke) {
      await Future.delayed(const Duration(seconds: 2));
    }
    if (!mounted) return;
    // 시크릿 모드가 켜져 있으면 잠금 화면을 통과해야만 HomeScreen에 도달하므로,
    // 여기서 호출하는 것만으로 "잠금 화면에서는 광고 노출 안 함" 조건이 자연히 지켜진다.
    unawaited(AdService.instance.maybeShowInterstitialOnColdStart());
  }

  /// 앱 첫 진입 시 상황에 맞는 멘트 하나를 고른다. 여러 조건이 동시에 맞아도 음성이
  /// 겹쳐 재생되지 않도록 우선순위를 둔다: 저녁인데 운동을 안 했으면 그 리마인더가
  /// 가장 실용적이라 최우선, 그다음 스트릭 축하, 둘 다 아니면 기본 인사.
  /// 실제로 멘트를 재생했으면 true(전면광고 전 딜레이가 필요하다는 뜻).
  Future<bool> _playAppOpenTts() async {
    if (!await UserProfileService.instance.getTtsEnabled()) return false;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    if (now.hour >= 18) {
      final logs = await DatabaseHelper.instance.getLogsForDate(today);
      final hasExercise = logs.any((e) => e.type == LogType.exercise);
      if (!hasExercise) {
        await TtsService.instance.speak(TtsCategory.exerciseReminder);
        return true;
      }
    }

    // "오늘"은 아직 진행 중이라 스트릭에 포함하지 않고, 어제까지 연속 기록만 본다.
    final streak = await DatabaseHelper.instance
        .getStreakDaysEndingOn(today.subtract(const Duration(days: 1)));
    if (streak >= 3) {
      await TtsService.instance.speak(TtsCategory.streak);
      return true;
    }

    await TtsService.instance.speak(TtsCategory.appOpen);
    return true;
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
      // 운동/통계/찍기 3개를 다 정상 크기로 두니 하단 영역이 너무 커져서, 다른 탭(오늘의
      // 로그 하단, 설정의 "테스트 데이터 삭제" 등) 요소를 가리고 터치까지 막았다.
      // FloatingActionButtonThemeData로 크기·아이콘을 기존의 약 2/3 수준으로 줄였다가
      // (Transform.scale 같은 시각적 축소가 아니라 실제 레이아웃 크기 자체를 줄이는
      // 방식이라, 눌림 영역도 같이 줄어들어 뒤에 가려졌던 요소가 다시 눌린다),
      // 그게 너무 작아서 그 축소된 크기 기준으로 가로만 약 1/3, 세로는 약 1/4만 다시
      // 키운 비대칭 크기로 재조정했다(위치는 그대로 centerDocked 유지).
      floatingActionButton: Theme(
        data: Theme.of(context).copyWith(
          floatingActionButtonTheme: Theme.of(context).floatingActionButtonTheme.copyWith(
                iconSize: 16,
                // 통계 FAB(원형): 2/3로 줄인 38x38 기준 가로 +1/3(≈51), 세로 +1/4(≈48).
                sizeConstraints: const BoxConstraints.tightFor(width: 51, height: 48),
                // extended FAB(운동/찍기): 2/3로 줄인 높이 32 기준 세로 +1/4 = 40.
                extendedSizeConstraints: const BoxConstraints(minHeight: 40, maxHeight: 40),
                extendedIconLabelSpacing: 8,
                // extended FAB은 폭을 직접 지정하는 필드가 없어 좌우 padding으로 가로폭을
                // 넓힌다(2/3로 줄였던 10 → 더 키움).
                extendedPadding: const EdgeInsets.symmetric(horizontal: 14),
                extendedTextStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
        ),
        child: Row(
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
            const SizedBox(width: 8),
            // 하단 탭의 통계 화면과는 별개로, 운동/찍기 FAB 사이에 빠른 진입 경로를 하나
            // 더 둔다. 3개짜리 extended FAB을 나란히 두면 라벨이 긴 언어(독일어 등)에서
            // 가로로 넘칠 위험이 있어 이 버튼만 아이콘 전용(원형)으로 좁게 뒀다.
            FloatingActionButton(
              heroTag: 'stats_fab',
              backgroundColor: AppColors.statsGray,
              foregroundColor: Colors.white,
              tooltip: l10n.statsAppBarTitle,
              onPressed: () =>
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const StatsScreen())),
              child: const Icon(Icons.bar_chart),
            ),
            const SizedBox(width: 8),
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
