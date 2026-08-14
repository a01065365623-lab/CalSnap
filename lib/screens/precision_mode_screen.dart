import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

/// 1차 출시(한국 단일 시장)에서는 제외. 추후 업데이트로 활성화 예정.
/// 계획: 위/측면 2장 촬영 + 기준객체(수저, 카드 등) 병행으로 부피 추정 정확도 향상.
class PrecisionModeScreen extends StatelessWidget {
  const PrecisionModeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.precisionModeAppBarTitle)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            l10n.precisionModeComingSoon,
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
