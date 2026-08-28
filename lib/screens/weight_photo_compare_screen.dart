import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:intl/intl.dart';

import '../db/database_helper.dart';
import '../models/daily_log_entry.dart';
import '../theme/app_colors.dart';

/// 사진이 첨부된 체중 기록 중 두 날짜를 골라 나란히 비교해서 보여준다.
class WeightPhotoCompareScreen extends StatefulWidget {
  const WeightPhotoCompareScreen({super.key});

  @override
  State<WeightPhotoCompareScreen> createState() => _WeightPhotoCompareScreenState();
}

class _WeightPhotoCompareScreenState extends State<WeightPhotoCompareScreen> {
  bool _loading = true;
  List<WeightPhotoRecord> _records = [];
  WeightPhotoRecord? _before;
  WeightPhotoRecord? _after;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final records = await DatabaseHelper.instance.getWeightPhotoRecords();
    if (!mounted) return;
    setState(() {
      _records = records;
      // 처음 열었을 때는 가장 오래된 사진을 '이전', 가장 최근 사진을 '이후'로 기본
      // 선택해 바로 비교가 되도록 한다.
      if (records.isNotEmpty) {
        _before = records.first;
        _after = records.last;
      }
      _loading = false;
    });
  }

  String _formatDate(String dateKey) => DateFormat('yyyy.MM.dd').format(DateTime.parse(dateKey));

  Widget _photoColumn(
    AppLocalizations l10n,
    String label,
    WeightPhotoRecord? record,
    ValueChanged<WeightPhotoRecord?> onChanged,
  ) {
    return Expanded(
      child: Column(
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          DropdownButton<WeightPhotoRecord>(
            isExpanded: true,
            value: record,
            hint: Text(l10n.weightPhotoComparePickDateHint),
            items: _records
                .map((r) => DropdownMenuItem(
                      value: r,
                      child: Text(
                        '${_formatDate(r.date)} · ${r.weightKg.toStringAsFixed(1)}kg',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ))
                .toList(),
            onChanged: onChanged,
          ),
          const SizedBox(height: 8),
          AspectRatio(
            aspectRatio: 3 / 4,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(8),
              ),
              clipBehavior: Clip.antiAlias,
              child: record != null
                  ? Image.file(File(record.photoPath), fit: BoxFit.cover)
                  : Center(
                      child: Text(
                        l10n.weightPhotoCompareNoPhotoPlaceholder,
                        style: TextStyle(color: Colors.grey.shade500),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.compare, color: AppColors.weightTeal, size: 22),
            const SizedBox(width: 8),
            Text(l10n.weightPhotoCompareAppBarTitle),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _records.length < 2
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      l10n.weightPhotoCompareEmptyMessage,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _photoColumn(
                        l10n,
                        l10n.weightPhotoComparePickBeforeLabel,
                        _before,
                        (value) => setState(() => _before = value),
                      ),
                      const SizedBox(width: 12),
                      _photoColumn(
                        l10n,
                        l10n.weightPhotoComparePickAfterLabel,
                        _after,
                        (value) => setState(() => _after = value),
                      ),
                    ],
                  ),
                ),
    );
  }
}
