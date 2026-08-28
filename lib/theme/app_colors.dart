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

  static const Color foodCoral = Color(0xFFD85A30);
  static const Color foodCoralBg = Color(0xFFFBE7E0);

  static const Color exerciseTeal = Color(0xFF1D9E75);
  static const Color exerciseTealBg = Color(0xFFDFF3EC);

  static const Color weightTeal = Color(0xFF6FBFA3);
  static const Color weightTealBg = Color(0xFFE8F6F0);

  static const Color statsGray = Color(0xFF5F5E5A);
  static const Color statsGrayBg = Color(0xFFEBEAE7);

  // 목표 칼로리(오렌지)·권장 수분 섭취량(블루) 칩 전용. foodCoral(탄수화물)·
  // exerciseTeal(단백질/운동/수분과 다른 계열)과 겹치지 않는 색으로 골랐다.
  static const Color goalOrange = Color(0xFFEF6C00);
  static const Color goalOrangeBg = Color(0xFFFDE7D2);

  static const Color waterBlue = Color(0xFF2E86DE);
  static const Color waterBlueBg = Color(0xFFDDEBFC);
}
