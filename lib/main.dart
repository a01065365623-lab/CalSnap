import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'screens/onboarding_screen.dart';
import 'services/user_profile_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final onboardingComplete = await UserProfileService.instance.isOnboardingComplete();
  runApp(CalSnapApp(onboardingComplete: onboardingComplete));
}

class CalSnapApp extends StatelessWidget {
  final bool onboardingComplete;

  const CalSnapApp({super.key, required this.onboardingComplete});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CalSnap',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.deepOrange,
        useMaterial3: true,
        fontFamily: 'Pretendard',
      ),
      home: onboardingComplete ? const HomeScreen() : const OnboardingScreen(),
    );
  }
}
