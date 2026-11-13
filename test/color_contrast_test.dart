// AppColors 조합의 WCAG 2.x 대비 검사(라이트 테마).
// - 일반 글자: 4.5:1 이상 (AA)
// - 아이콘·진행 막대·버튼 경계 같은 비텍스트 요소: 3:1 이상 (AA, 1.4.11)

import 'dart:math' as math;

import 'package:calsnap/theme/app_colors.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

double _channel(double c) => c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

double relativeLuminance(Color c) => 0.2126 * _channel(c.r) + 0.7152 * _channel(c.g) + 0.0722 * _channel(c.b);

double contrastRatio(Color a, Color b) {
  final la = relativeLuminance(a);
  final lb = relativeLuminance(b);
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

const _white = Color(0xFFFFFFFF);

void main() {
  test('대비 계산 자체 검증: 검정/흰색 21:1, 같은 색 1:1', () {
    expect(contrastRatio(const Color(0xFF000000), _white), closeTo(21, 0.01));
    expect(contrastRatio(_white, _white), 1);
  });

  // [이름, 글자색, 바탕색]
  final textPairs = <(String, Color, Color)>[
    ('보조 글자 / 카드', AppColors.textMuted, AppColors.cardSurface),
    ('보조 글자 / 바탕', AppColors.textMuted, AppColors.appBackground),
    ('섭취 숫자(진한 코랄) / 카드', AppColors.foodCoralStrong, AppColors.cardSurface),
    ('소모 숫자(진한 틸) / 카드', AppColors.exerciseTealStrong, AppColors.cardSurface),
    ('목표 초과(빨강) / 카드', AppColors.goalOverRed, AppColors.cardSurface),
    ('흰 글자 / 진한 코랄 버튼', _white, AppColors.foodCoralStrong),
    ('진한 코랄 글자 / 바탕', AppColors.foodCoralStrong, AppColors.appBackground),
    ('흰 글자 / 진한 틸 버튼', _white, AppColors.exerciseTealStrong),
    ('사진 한도 안내 / 회색 바탕', AppColors.statsGray, AppColors.statsGrayBg),
  ];
  for (final (name, fg, bg) in textPairs) {
    test('글자 4.5:1 이상 — $name', () {
      expect(contrastRatio(fg, bg), greaterThanOrEqualTo(4.5));
    });
  }

  final nonTextPairs = <(String, Color, Color)>[
    ('소모 아이콘(틸) / 카드', AppColors.exerciseTeal, AppColors.cardSurface),
    ('목표 링(코랄) / 카드', AppColors.foodCoral, AppColors.cardSurface),
  ];
  for (final (name, fg, bg) in nonTextPairs) {
    test('비텍스트 3:1 이상 — $name', () {
      expect(contrastRatio(fg, bg), greaterThanOrEqualTo(3));
    });
  }
}
