import 'package:flutter/material.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('설정')),
      body: ListView(
        children: const [
          ListTile(title: Text('목표 칼로리 설정'), subtitle: Text('추후 구현')),
          ListTile(title: Text('단위 (g / oz)'), subtitle: Text('추후 구현')),
          ListTile(title: Text('제휴 쇼핑 추천 표시'), subtitle: Text('추후 구현')),
        ],
      ),
    );
  }
}
