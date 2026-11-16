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
    ('흰 글자 / 진한 코랄 버튼', AppColors.onAccent, AppColors.foodCoralStrong),
    ('진한 코랄 글자 / 바탕', AppColors.foodCoralStrong, AppColors.appBackground),
    ('흰 글자 / 진한 틸 버튼', AppColors.onAccent, AppColors.exerciseTealStrong),
    ('사진 한도 안내 / 회색 바탕', AppColors.statsGray, AppColors.statsGrayBg),
    ('지방 라벨 / 카드', AppColors.statsGray, AppColors.cardSurface),
    ('목표 칼로리 칩', AppColors.goalOrangeStrong, AppColors.goalOrangeBg),
    ('권장 수분 칩', AppColors.waterBlueText, AppColors.waterBlueBg),
    ('링 퍼센트(진한 코랄) / 카드', AppColors.foodCoralStrong, AppColors.cardSurface),
    ('흰 아이콘 / 물 버튼', AppColors.onAccent, AppColors.waterBlueStrong),
    ('통계 아이콘 / 중립 버튼', AppColors.neutralButtonFg, AppColors.neutralButtonBg),
  ];
  for (final (name, fg, bg) in textPairs) {
    test('글자 4.5:1 이상 — $name', () {
      expect(contrastRatio(fg, bg), greaterThanOrEqualTo(4.5));
    });
  }

  final nonTextPairs = <(String, Color, Color)>[
    ('소모 아이콘(틸) / 카드', AppColors.exerciseTeal, AppColors.cardSurface),
    ('목표 링(코랄) / 카드', AppColors.foodCoral, AppColors.cardSurface),
    ('탄수화물 막대 / 카드', AppColors.foodCoral, AppColors.cardSurface),
    ('단백질 막대 / 카드', AppColors.exerciseTeal, AppColors.cardSurface),
    ('지방 막대 / 카드', AppColors.statsGray, AppColors.cardSurface),
    ('체중 아이콘 / 옅은 틸', AppColors.weightTealStrong, AppColors.weightTealBg),
    ('음식 아이콘 / 옅은 코랄', AppColors.foodCoral, AppColors.foodCoralBg),
    ('운동 아이콘 / 옅은 틸', AppColors.exerciseTealStrong, AppColors.exerciseTealBg),
    ('물 아이콘 / 옅은 회청', AppColors.waterTileFg, AppColors.waterTileBg),
    ('빈 화면 버튼 테두리 / 카드', AppColors.foodCoral, AppColors.appBackground),
    ('비타민 막대 / 카드', AppColors.goalOrange, AppColors.cardSurface),
    ('미네랄 막대 / 카드', AppColors.waterBlue, AppColors.cardSurface),
    ('비타민·미네랄 카드 아이콘 / 카드', AppColors.weightTealStrong, AppColors.cardSurface),
  ];
  for (final (name, fg, bg) in nonTextPairs) {
    test('비텍스트 3:1 이상 — $name', () {
      expect(contrastRatio(fg, bg), greaterThanOrEqualTo(3));
    });
  }
}
