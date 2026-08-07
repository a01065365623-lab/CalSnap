import 'package:flutter/material.dart';

import 'screens/home_screen.dart';

void main() {
  runApp(const CalSnapApp());
}

class CalSnapApp extends StatelessWidget {
  const CalSnapApp({super.key});

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
      home: const HomeScreen(),
    );
  }
}
