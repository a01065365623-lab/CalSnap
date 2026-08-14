import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

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
      ),
      home: !onboardingComplete
          ? const OnboardingScreen()
          : locked
              ? const AppLockScreen()
              : const HomeScreen(),
    );
  }
}
