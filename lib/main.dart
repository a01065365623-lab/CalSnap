import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import 'db/database_helper.dart';
import 'screens/app_lock_screen.dart';
import 'screens/home_screen.dart';
import 'screens/onboarding_screen.dart';
import 'services/ad_service.dart';
import 'services/app_lock_service.dart';
import 'services/user_profile_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 첫 프레임을 늦추지 않도록 초기화는 백그라운드에서 진행한다. 실패해도
  // AdService 내부에서 조용히 무시하므로 앱 실행에 영향 없음.
  unawaited(AdService.instance.initialize());
  final onboardingComplete = await UserProfileService.instance.isOnboardingComplete();
  // 온보딩 전이면 잠글 데이터 자체가 없으므로 시크릿 모드 여부와 무관하게 온보딩으로 보낸다.
  final locked = onboardingComplete && await AppLockService.instance.isEnabled();
  runApp(CalSnapApp(onboardingComplete: onboardingComplete, locked: locked));
}

class CalSnapApp extends StatelessWidget {
  final bool onboardingComplete;
  final bool locked;

  const CalSnapApp({super.key, required this.onboardingComplete, required this.locked});

  /// 앱 전체 텍스트를 이 비율만큼 키운다(약 15~20% 확대 요청 중 중간값). 코드 곳곳이
  /// ThemeData.textTheme이 아니라 TextStyle(fontSize: ...)를 직접 지정하고 있어서,
  /// textTheme만 키워서는 대부분의 화면에 반영되지 않는다. 대신 MediaQuery의
  /// textScaler를 곱해주면 테마 참조 여부와 무관하게 모든 Text에 일괄 적용되고,
  /// 상대적 크기 비율(작은 라벨 vs 큰 강조 숫자)도 그대로 유지된다.
  static const double _textScaleFactor = 1.18;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CalSnap',
      debugShowCheckedModeBanner: false,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      // 기기 locale이 14개 지원 언어 중 하나와 일치하면 그 언어를, 없으면 앱의 기본
      // 언어인 한국어로 폴백한다(wedi_app은 gen-l10n이 알파벳순으로 생성한
      // supportedLocales 목록의 첫 항목인 'ar'로 암묵적으로 폴백되는데, 이는 의도된
      // 설계가 아니라 우연에 가까워 보여 CalSnap에서는 명시적으로 한국어를 기본값으로 뒀다).
      localeResolutionCallback: (locale, supportedLocales) {
        if (locale != null) {
          for (final supported in supportedLocales) {
            if (supported.languageCode == locale.languageCode) return supported;
          }
        }
        return const Locale('ko');
      },
      theme: ThemeData(
        colorSchemeSeed: Colors.deepOrange,
        useMaterial3: true,
        fontFamily: 'Pretendard',
        // 스낵바가 body/bottomNavigationBar를 밀어 올리지 않고 그 위에 오버레이되게 한다.
        // fixed(기본값)였다면 스낵바가 뜰 때만 하단 배너 광고가 가려짐/드러남이 달라져
        // 평소 상태와 레이아웃이 달라 보이는 문제가 있었다.
        snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
      ),
      builder: (context, child) {
        final mediaQuery = MediaQuery.of(context);
        // 기기 접근성 글자 크기 설정(mediaQuery.textScaler)에 앱 자체 확대 비율을
        // 곱한다 — 곱셈이라 사용자가 시스템 글자 크기를 더 키워둔 경우에도 그 설정을
        // 무시하지 않고 함께 반영된다.
        final currentScale = mediaQuery.textScaler.scale(1.0);
        return MediaQuery(
          data: mediaQuery.copyWith(
            textScaler: TextScaler.linear(currentScale * _textScaleFactor),
          ),
          child: child!,
        );
      },
      home: _AppStartupGate(
        child: !onboardingComplete
            ? const OnboardingScreen()
            : locked
                ? const AppLockScreen()
                : const HomeScreen(),
      ),
    );
  }
}

/// 첫 프레임은 즉시 그리되(로딩 인디케이터), 음식 DB 시딩(최초 실행/버전업 시 최대 수 초
/// 소요될 수 있음)이 끝날 때까지는 온보딩/잠금/홈 화면을 보여주지 않는다. 시딩이 이미
/// 끝난 이후(=대부분의 실행)에는 database getter가 즉시 반환되어 사실상 순간적으로 지나간다.
class _AppStartupGate extends StatefulWidget {
  final Widget child;

  const _AppStartupGate({required this.child});

  @override
  State<_AppStartupGate> createState() => _AppStartupGateState();
}

class _AppStartupGateState extends State<_AppStartupGate> {
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await DatabaseHelper.instance.database;
    if (mounted) setState(() => _ready = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return widget.child;
  }
}
