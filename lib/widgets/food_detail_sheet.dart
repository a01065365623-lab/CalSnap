import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../models/daily_log_entry.dart';
import '../utils/unit_converter.dart';
import 'related_products_button.dart';

/// 음식 기록 상세 시트: (사진이 있으면) 큰 사진과 중량·칼로리·탄단지, "관련 상품 보기"
/// 버튼. 오늘의 로그와 식사 사진 달력에서 같은 모양으로 쓴다.
Future<void> showFoodDetailSheet(BuildContext context, DailyLogEntry entry, UnitSystem unitSystem) {
  final l10n = AppLocalizations.of(context)!;
  final photoPath = entry.photoPath;
  final amount = entry.amount;
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (photoPath != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(
                  File(photoPath),
                  width: double.infinity,
                  height: MediaQuery.of(ctx).size.height * 0.4,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
              const SizedBox(height: 12),
            ],
            Text(entry.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(
              amount != null
                  ? '${formatWeight(amount, unitSystem)} · ${entry.calories.toStringAsFixed(0)} kcal'
                  : '${entry.calories.toStringAsFixed(0)} kcal',
              style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
            ),
            if (entry.carbsG != null || entry.proteinG != null || entry.fatG != null) ...[
              const SizedBox(height: 4),
              Text(
                l10n.nutrientsSummary(
                  (entry.carbsG ?? 0).toStringAsFixed(0),
                  (entry.proteinG ?? 0).toStringAsFixed(0),
                  (entry.fatG ?? 0).toStringAsFixed(0),
                ),
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              ),
            ],
            const SizedBox(height: 16),
            RelatedProductsButton(queryBuilder: () => entry.name),
          ],
        ),
      ),
    ),
  );
}
