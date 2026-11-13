import 'package:flutter/material.dart';

/// 카테고리별 포인트 컬러(코랄·틸·그레이).
///
/// 앱 전체 배경/버튼 톤(메인 테마 시드 컬러)은 그대로 두고, 카테고리를 구분해
/// 보여주고 싶은 아이콘/포인트 요소에만 가볍게 얹어 쓰기 위한 상수 모음이다.
/// - 음식(빠른측정, 오늘의 로그 음식 항목) = 코랄
/// - 운동 = 틸, 체중 = 같은 틸 계열의 옅은 톤
/// - 통계/설정 = 그레이
class AppColors {
  AppColors._();

  // ── 화면 바탕·카드 ──────────────────────────────────────
  // 바탕은 흰색에 가까운 아주 옅은 웜톤, 카드는 순백 + 얇은 테두리 + 옅은 그림자로
  // 바탕과 분리한다(카드끼리 같은 색으로 붙어 보이지 않게).
  /// Material 테마 시드 컬러(기존 Colors.deepOrange와 같은 값).
  static const Color brandSeed = Color(0xFFFF5722);

  static const Color appBackground = Color(0xFFFFFBF9);
  static const Color cardSurface = Color(0xFFFFFFFF);
  static const Color cardBorder = Color(0xFFEEE6E2);
  static const Color cardShadow = Color(0x1F5A3A2E);
  // 배너 광고 위아래 구분선. 광고가 카드(콘텐츠)처럼 보이지 않게 영역만 가른다.
  static const Color adDivider = Color(0xFFE5DCD7);

  // ── 글자색 ─────────────────────────────────────────────
  // 흰 카드/바탕 위 보조 글자. Colors.grey(#9E9E9E)는 대비가 2.7:1이라 AA(4.5:1)를
  // 못 넘어서, 라벨처럼 작은 글자에는 이 색을 쓴다(흰색 대비 약 5.5:1).
  static const Color textMuted = Color(0xFF6B6966);

  static const Color foodCoral = Color(0xFFD85A30);
  static const Color foodCoralBg = Color(0xFFFBE7E0);
  // foodCoral은 흰 바탕 대비 3.9:1이라 아이콘·링·막대에만 쓰고, 작은 글자와 흰 글자를
  // 얹는 버튼 배경에는 같은 계열의 진한 코랄을 쓴다(흰색 대비 약 4.8:1).
  static const Color foodCoralStrong = Color(0xFFC24E26);

  static const Color exerciseTeal = Color(0xFF1D9E75);
  static const Color exerciseTealBg = Color(0xFFDFF3EC);
  // exerciseTeal은 흰 바탕 대비 3.4:1이라 아이콘·막대·큰 글자에만 쓰고, 작은 글자와
  // 흰 글자를 얹는 버튼 배경에는 같은 계열의 진한 틸을 쓴다(흰색 대비 약 5.0:1).
  static const Color exerciseTealStrong = Color(0xFF167E5E);

  static const Color weightTeal = Color(0xFF6FBFA3);
  static const Color weightTealBg = Color(0xFFE8F6F0);
  // weightTeal은 옅은 배경 위 아이콘으로 쓰기엔 대비가 낮아(약 2:1), 체중 카드 아이콘은
  // 같은 계열의 진한 톤을 쓴다(weightTealBg 대비 약 3.8:1).
  static const Color weightTealStrong = Color(0xFF2F8A6C);

  static const Color statsGray = Color(0xFF5F5E5A);
  static const Color statsGrayBg = Color(0xFFEBEAE7);

  // 목표 칼로리(오렌지)·권장 수분 섭취량(블루) 칩 전용. foodCoral(탄수화물)·
  // exerciseTeal(단백질/운동/수분과 다른 계열)과 겹치지 않는 색으로 골랐다.
  static const Color goalOrange = Color(0xFFEF6C00);
  static const Color goalOrangeBg = Color(0xFFFDE7D2);
  // 목표 칼로리 칩의 글자·아이콘(goalOrangeBg 대비 약 4.8:1).
  static const Color goalOrangeStrong = Color(0xFFA84B00);

  static const Color waterBlue = Color(0xFF2E86DE);
  static const Color waterBlueBg = Color(0xFFDDEBFC);
  // 권장 수분 칩의 글자·아이콘(waterBlueBg 대비 약 5.1:1).
  static const Color waterBlueText = Color(0xFF1A63AB);
  // 오늘의 로그 물 기록 아이콘(중립 블루그레이)과 그 배경.
  static const Color waterTileFg = Color(0xFF546E7A);
  static const Color waterTileBg = Color(0xFFECEFF1);
  // 물 빠른 추가 버튼 배경(흰 아이콘). waterBlue보다 한 단계 진해 흰색 대비 약 5.1:1.
  static const Color waterBlueStrong = Color(0xFF1F6FBF);

  // ── 하단 액션 버튼 ──────────────────────────────────────
  // 강조색은 운동(틸)·찍기(코랄)만 쓰고, 통계 같은 보조 버튼은 이 중립 톤으로 낮춘다.
  /// 강조색 버튼 위의 글자·아이콘.
  static const Color onAccent = Color(0xFFFFFFFF);
  static const Color neutralButtonBg = Color(0xFFF1EEEC);
  static const Color neutralButtonFg = statsGray;
  static const Color buttonShadow = Color(0x405A3A2E);

  // 목표 칼로리 초과 시 진행률 링의 주의색. 평소 링 색(foodCoral)보다 붉고 진해서
  // 초과 상태가 한눈에 구분된다(흰 배경 대비 4.5:1 이상).
  static const Color goalOverRed = Color(0xFFC62828);
  static const Color goalOverRedBg = Color(0xFFFADCDC);
}
