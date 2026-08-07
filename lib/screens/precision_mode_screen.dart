import 'package:flutter/material.dart';

/// 1차 출시(한국 단일 시장)에서는 제외. 추후 업데이트로 활성화 예정.
/// 계획: 위/측면 2장 촬영 + 기준객체(수저, 카드 등) 병행으로 부피 추정 정확도 향상.
class PrecisionModeScreen extends StatelessWidget {
  const PrecisionModeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('정밀 측정')),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            '정밀 측정 모드는 준비 중입니다.\n곧 업데이트로 만나보실 수 있어요.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
