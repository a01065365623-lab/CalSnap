import 'dart:io';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// 기기 로컬에 저장된 음식 사진의 정사각 썸네일. 경로가 없거나 파일이 사라졌으면
/// 음식 아이콘 자리표시로 대신한다. 썸네일 크기에 맞춰 디코딩(cacheWidth)해 800px
/// 원본을 목록마다 통째로 메모리에 올리지 않게 한다.
class FoodPhotoThumbnail extends StatelessWidget {
  final String? path;
  final double size;
  final double radius;

  const FoodPhotoThumbnail({super.key, required this.path, this.size = 40, this.radius = 8});

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.foodCoralBg,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Icon(Icons.restaurant, color: AppColors.foodCoral, size: size * 0.5),
    );
    final p = path;
    if (p == null || p.isEmpty) return placeholder;

    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 2.0;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Image.file(
        File(p),
        width: size,
        height: size,
        fit: BoxFit.cover,
        cacheWidth: (size * dpr).round(),
        errorBuilder: (_, __, ___) => placeholder,
      ),
    );
  }
}
