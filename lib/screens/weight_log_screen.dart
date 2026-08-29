import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../db/database_helper.dart';
import '../services/user_profile_service.dart';
import '../services/weight_photo_service.dart';
import '../theme/app_colors.dart';
import '../utils/bmr_calculator.dart';
import 'weight_photo_compare_screen.dart';

String _bmiCategoryLabel(AppLocalizations l10n, BmiCategory category) {
  switch (category) {
    case BmiCategory.underweight:
      return l10n.bmiCategoryUnderweight;
    case BmiCategory.normal:
      return l10n.bmiCategoryNormal;
    case BmiCategory.overweight:
      return l10n.bmiCategoryOverweight;
    case BmiCategory.obese:
      return l10n.bmiCategoryObese;
  }
}

/// 온보딩/프로필 체중(user_profile_service)과는 별개로, 날짜별 체중을 기록해
/// 다이어트 추이를 확인하기 위한 캘린더 화면.
class WeightLogScreen extends StatefulWidget {
  /// 지정하면 그 날짜가 속한 달을 열고, 곧바로 그 날짜의 체중 입력 다이얼로그를 띄운다.
  /// 통계 화면의 체중 추이 그래프에서 특정 지점을 탭했을 때 바로 수정할 수 있도록 한다.
  final DateTime? initialDate;

  const WeightLogScreen({super.key, this.initialDate});

  @override
  State<WeightLogScreen> createState() => _WeightLogScreenState();
}

class _WeightLogScreenState extends State<WeightLogScreen> {
  late DateTime _month; // 보고 있는 달의 1일
  Map<String, double> _weights = {};
  Map<String, String> _photoPaths = {};
  bool _loading = true;

  // 최신 체중/BMI/BMR 요약 표시용(키·성별·나이는 온보딩 프로필 값 사용, 보고 있는 달과는 무관).
  // "최근 체중"은 항상 전체 기록 중 최신값이 아니라, _referenceDate 기준으로 그날
  // 기록이 있으면 그 값을, 없으면 그 이전 가장 가까운 기록을 보여준다. 화면을 처음
  // 열 때는 오늘(또는 initialDate)이 기준이고, 캘린더에서 날짜를 눌러 체중을
  // 입력/수정/삭제할 때마다 그 날짜로 기준이 바뀌면서 요약도 함께 갱신된다.
  late DateTime _referenceDate;
  double? _latestWeightKg;
  UserProfile? _profile;

  @override
  void initState() {
    super.initState();
    final initialDate = widget.initialDate;
    final base = initialDate ?? DateTime.now();
    _month = DateTime(base.year, base.month, 1);
    _referenceDate = base;
    _load();
    _loadBmiInputs();
    if (initialDate != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _editWeight(initialDate);
      });
    }
  }

  Future<void> _loadBmiInputs() async {
    final profile = await UserProfileService.instance.getProfile();
    final onDate = await DatabaseHelper.instance.getWeightForDate(_referenceDate);
    final latestWeight = onDate ?? await DatabaseHelper.instance.getWeightOnOrBefore(_referenceDate);
    if (mounted) {
      setState(() {
        _profile = profile;
        _latestWeightKg = latestWeight;
      });
    }
  }

  /// 체중/키가 없으면 해당 항목만 생략하고 나머지를 표시한다(체중 자체가 없으면 전체 숨김).
  String? _bmiSummary(AppLocalizations l10n) {
    final weight = _latestWeightKg;
    if (weight == null) return null;

    final parts = <String>[l10n.weightLogRecentWeight(weight.toStringAsFixed(1))];

    final profile = _profile;
    if (profile != null) {
      final bmi = calculateBmi(weightKg: weight, heightCm: profile.heightCm);
      parts.add(l10n.weightLogBmiSummary(bmi.toStringAsFixed(1), _bmiCategoryLabel(l10n, getBmiCategory(bmi))));

      final bmr = calculateBmr(
        gender: profile.gender,
        age: profile.age,
        heightCm: profile.heightCm,
        weightKg: weight,
      );
      parts.add(l10n.weightLogBmrSummary(NumberFormat('#,##0').format(bmr)));
    }

    return parts.join(' · ');
  }

  String _dateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _load() async {
    setState(() => _loading = true);
    final from = _month;
    final to = DateTime(_month.year, _month.month + 1, 0); // 이번 달 마지막 날
    final weights = await DatabaseHelper.instance.getWeightsForRange(from, to);
    final photoPaths = await DatabaseHelper.instance.getWeightPhotoPathsForRange(from, to);
    if (mounted) {
      setState(() {
        _weights = weights;
        _photoPaths = photoPaths;
        _loading = false;
      });
    }
  }

  void _changeMonth(int delta) {
    setState(() => _month = DateTime(_month.year, _month.month + delta, 1));
    _load();
  }

  Future<void> _editWeight(DateTime date) async {
    final l10n = AppLocalizations.of(context)!;
    final key = _dateKey(date);
    final existing = _weights[key];
    final existingPhotoPath = _photoPaths[key];
    final controller = TextEditingController(text: existing?.toStringAsFixed(1) ?? '');
    final picker = ImagePicker();

    // 사진 선택/제거는 다이얼로그 안에서만 미리보기로 반영하고, 실제 파일 저장·삭제와
    // DB 반영은 저장 버튼을 눌러 다이얼로그가 닫힌 뒤에 한 번에 처리한다.
    XFile? pickedPhoto;
    var photoCleared = false;

    final result = await showDialog<_WeightDialogResult>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final hasPhoto = pickedPhoto != null || (existingPhotoPath != null && !photoCleared);

          Future<void> pick(ImageSource source) async {
            final picked = await picker.pickImage(source: source);
            if (picked != null) {
              setDialogState(() {
                pickedPhoto = picked;
                photoCleared = false;
              });
            }
          }

          return AlertDialog(
            title: Text(l10n.weightLogEditDialogTitle(date.month, date.day)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: controller,
                    autofocus: true,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      suffixText: 'kg',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (hasPhoto)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(
                        File(pickedPhoto?.path ?? existingPhotoPath!),
                        height: 120,
                        fit: BoxFit.cover,
                      ),
                    ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TextButton.icon(
                        icon: const Icon(Icons.camera_alt_outlined, size: 18),
                        label: Text(l10n.weightLogPhotoAddButton),
                        onPressed: () => pick(ImageSource.camera),
                      ),
                      TextButton.icon(
                        icon: const Icon(Icons.photo_library_outlined, size: 18),
                        label: Text(l10n.weightLogPhotoGalleryButton),
                        onPressed: () => pick(ImageSource.gallery),
                      ),
                      if (hasPhoto)
                        IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          tooltip: l10n.weightLogPhotoRemoveButton,
                          onPressed: () => setDialogState(() {
                            pickedPhoto = null;
                            photoCleared = true;
                          }),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              if (existing != null)
                TextButton(
                  onPressed: () => Navigator.pop(context, const _WeightDialogResult.deleted()),
                  child: Text(l10n.deleteButton),
                ),
              TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancelButton)),
              TextButton(
                onPressed: () {
                  final value = double.tryParse(controller.text.trim());
                  if (value == null || value <= 0) return;
                  Navigator.pop(context, _WeightDialogResult.saved(value));
                },
                child: Text(l10n.saveButton),
              ),
            ],
          );
        },
      ),
    );
    if (result == null) return;

    if (result.isDelete) {
      if (existingPhotoPath != null) {
        await WeightPhotoService.instance.deletePhoto(existingPhotoPath);
      }
      await DatabaseHelper.instance.deleteWeightForDate(date);
    } else if (result.value != null) {
      await DatabaseHelper.instance.setWeightForDate(date, result.value!);
      if (pickedPhoto != null) {
        final savedPath = await WeightPhotoService.instance.savePhoto(pickedPhoto!, date);
        await DatabaseHelper.instance.setWeightPhotoPath(date, savedPath);
      } else if (photoCleared && existingPhotoPath != null) {
        await WeightPhotoService.instance.deletePhoto(existingPhotoPath);
        await DatabaseHelper.instance.setWeightPhotoPath(date, null);
      }
    }
    _referenceDate = date; // 방금 입력/수정/삭제한 날짜 기준으로 상단 요약을 다시 계산한다.
    _load();
    _loadBmiInputs();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final weekdayLabels = [
      l10n.weekdaySun,
      l10n.weekdayMon,
      l10n.weekdayTue,
      l10n.weekdayWed,
      l10n.weekdayThu,
      l10n.weekdayFri,
      l10n.weekdaySat,
    ];
    final firstDayOffset = DateTime(_month.year, _month.month, 1).weekday % 7; // 일요일 시작 기준 빈칸 수
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final now = DateTime.now();

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.monitor_weight_outlined, color: AppColors.weightTeal, size: 22),
            const SizedBox(width: 8),
            Text(l10n.weightLogAppBarTitle),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.compare),
            tooltip: l10n.weightLogComparePhotosTooltip,
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const WeightPhotoCompareScreen()),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () => _changeMonth(-1),
                ),
                Text(
                  l10n.weightLogMonthHeader(_month.year, _month.month),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () => _changeMonth(1),
                ),
              ],
            ),
          ),
          if (_bmiSummary(l10n) != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 아래 캘린더의 날짜/체중 텍스트(13/12px)보다 눈에 띄게 크고, 체중
                  // 카테고리 컬러(틸)를 써서 이 화면에서 가장 중요한 정보임을 드러낸다.
                  Text(
                    _bmiSummary(l10n)!,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: AppColors.weightTeal,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    l10n.weightLogBmiBmrLegend,
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final label in weekdayLabels)
                Expanded(
                  child: Center(
                    child: Text(label, style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                  ),
                ),
            ],
          ),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : GridView.builder(
                    // 아래쪽은 그리드 셀(터치 영역)이 화면 맨 끝까지 채워지므로, 고정 8
                    // 대신 시스템 제스처 내비게이션 바 높이를 더해 마지막 줄이 그 바에
                    // 가려 눌리지 않도록 한다.
                    padding: EdgeInsets.fromLTRB(8, 8, 8, 8 + MediaQuery.of(context).padding.bottom),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 7,
                      childAspectRatio: 0.8,
                    ),
                    itemCount: firstDayOffset + daysInMonth,
                    itemBuilder: (context, index) {
                      if (index < firstDayOffset) return const SizedBox.shrink();

                      final day = index - firstDayOffset + 1;
                      final date = DateTime(_month.year, _month.month, day);
                      final key = _dateKey(date);
                      final weight = _weights[key];
                      final isToday =
                          date.year == now.year && date.month == now.month && date.day == now.day;

                      return InkWell(
                        onTap: () => _editWeight(date),
                        child: Container(
                          margin: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: isToday ? Border.all(color: AppColors.weightTeal, width: 1.5) : null,
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                '$day',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                weight != null ? weight.toStringAsFixed(1) : '-',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: weight != null ? AppColors.weightTeal : Colors.grey.shade400,
                                  fontWeight: weight != null ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
                              if (_photoPaths.containsKey(key))
                                const Padding(
                                  padding: EdgeInsets.only(top: 1),
                                  child: Icon(Icons.photo_camera, size: 10, color: AppColors.weightTeal),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _WeightDialogResult {
  final double? value;
  final bool isDelete;
  const _WeightDialogResult.saved(this.value) : isDelete = false;
  const _WeightDialogResult.deleted()
      : value = null,
        isDelete = true;
}
