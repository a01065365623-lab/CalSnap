import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:image_picker/image_picker.dart';

import '../db/database_helper.dart';
import '../models/daily_log_entry.dart';
import '../models/my_food.dart';
import '../services/food_photo_service.dart';
import '../services/food_recognition_service.dart';
import '../services/gemini_food_recognition_service.dart';
import '../services/meal_log_service.dart';
import '../services/tts_service.dart';
import '../services/user_profile_service.dart';
import '../theme/app_colors.dart';
import '../utils/unit_converter.dart';
import '../widgets/food_photo_thumbnail.dart';
import '../widgets/related_products_button.dart';
import 'manual_food_entry_screen.dart';

/// 빠른 측정 화면을 열자마자 바로 실행할 동작. 오늘의 로그 빈 화면의 바로가기
/// 버튼(카메라/직접 입력)이 한 번 더 탭하지 않아도 되도록 쓴다.
enum QuickModeStartAction { none, camera, manualEntry }

class QuickModeScreen extends StatefulWidget {
  final QuickModeStartAction startAction;

  const QuickModeScreen({super.key, this.startAction = QuickModeStartAction.none});

  @override
  State<QuickModeScreen> createState() => _QuickModeScreenState();
}

class _QuickModeScreenState extends State<QuickModeScreen> {
  final _picker = ImagePicker();
  // proxyBaseUrl / apiKey는 GeminiFoodRecognitionService 기본값(--dart-define 주입) 사용.
  final FoodRecognitionService _recognitionService = GeminiFoodRecognitionService();
  final _foodNameController = TextEditingController();
  final _hintController = TextEditingController();

  File? _image;
  // _image를 한 번 디코딩해 만든 업로드용·저장용 JPEG. 재시도와 저장에 그대로 다시 써서
  // 두 번 디코딩하지 않고, 재전송 시 서버 캐시 키(업로드 바이트 sha256)도 유지한다.
  PreparedFoodPhoto? _prepared;
  FoodRecognitionResult? _result;
  double _portionMultiplier = 1.0; // 보정 슬라이더 (0.5x ~ 2.0x)
  bool _loading = false;
  String? _errorMessage;
  UnitSystem _unitSystem = UnitSystem.metric;
  // 사진 없이 "직접 입력" 경로로 얻은 결과인지 구분해서 저장 시 source에 반영한다.
  bool _isManualEntry = false;
  // 서버가 사진 인식 일일 한도 초과(daily_limit_exceeded)를 알려온 상태. 재시도해도
  // 소용없으므로 재시도 버튼 대신 아직 쓸 수 있는 "직접 입력"을 안내한다.
  bool _photoLimitReached = false;
  bool _saving = false;

  // "최근 먹은 음식"(my_foods). 탭하면 Gemini 호출 없이 양만 조정해 바로 기록한다.
  List<MyFood> _myFoods = [];
  bool _myFoodsByFrequency = false;

  @override
  void initState() {
    super.initState();
    _loadUnitSystem();
    _loadMyFoods();
    _recognitionService.refreshUsage();
    if (widget.startAction != QuickModeStartAction.none) {
      // 라우트 전환이 끝나기 전에 카메라/다음 화면을 띄우지 않도록 첫 프레임 뒤에 실행한다.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        switch (widget.startAction) {
          case QuickModeStartAction.camera:
            _pickImage(ImageSource.camera);
          case QuickModeStartAction.manualEntry:
            _openManualEntry();
          case QuickModeStartAction.none:
            break;
        }
      });
    }
  }

  Future<void> _loadMyFoods() async {
    final foods = await DatabaseHelper.instance.getMyFoods(byFrequency: _myFoodsByFrequency);
    if (mounted) setState(() => _myFoods = foods);
  }

  void _toggleMyFoodsSort(bool byFrequency) {
    if (byFrequency == _myFoodsByFrequency) return;
    setState(() => _myFoodsByFrequency = byFrequency);
    _loadMyFoods();
  }

  /// 최근 먹은 음식 탭: 양 슬라이더 시트를 띄우고, 저장하면 AI 인식 없이 바로 기록한다
  /// (서버를 거치지 않으므로 일일 사진/직접입력 한도에도 포함되지 않는다).
  Future<void> _openMyFood(MyFood food) async {
    final multiplier = await showModalBottomSheet<double>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _MyFoodQuickSaveSheet(food: food, unitSystem: _unitSystem),
    );
    if (multiplier == null || !mounted || _saving) return;
    setState(() => _saving = true);
    try {
      await MealLogService.instance.saveFromMyFood(food, multiplier);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
    _afterSaved();
  }

  void _afterSaved() {
    unawaited(TtsService.instance.speakAfterSave(TtsCategory.mealSave));
    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.savedSnackbarMessage)),
    );
  }

  Future<void> _loadUnitSystem() async {
    final unitSystem = await UserProfileService.instance.getUnitSystem();
    if (mounted) setState(() => _unitSystem = unitSystem);
  }

  @override
  void dispose() {
    _foodNameController.dispose();
    _hintController.dispose();
    super.dispose();
  }

  double get _totalCalories {
    final result = _result;
    if (result == null) return 0;
    return result.caloriesPer100g *
        (result.estimatedWeightG * _portionMultiplier) /
        100;
  }

  double get _totalCarbs => _scaledNutrient((r) => r.carbsG);
  double get _totalProtein => _scaledNutrient((r) => r.proteinG);
  double get _totalFat => _scaledNutrient((r) => r.fatG);

  /// 100g당 영양소 값을, 보정된 추정 중량 기준 절대량으로 환산한다(calories와 동일한 방식).
  double _scaledNutrient(double Function(FoodRecognitionResult) per100g) {
    final result = _result;
    if (result == null) return 0;
    return per100g(result) * (result.estimatedWeightG * _portionMultiplier) / 100;
  }

  Future<void> _pickImage(ImageSource source) async {
    // 리사이즈/압축은 _recognize에서 FoodPhotoService.prepare가 한 번만 수행한다
    // (여기서 imageQuality까지 지정하면 원본 미리보기 화질만 낮아지고 이중 압축이 됨).
    final picked = await _picker.pickImage(source: source);
    if (picked == null) return;

    final image = File(picked.path);
    setState(() {
      _image = image;
      _prepared = null;
      _result = null;
      _errorMessage = null;
      _isManualEntry = false;
    });
    await _recognize(image);
  }

  /// "직접 입력" 버튼: 상단 힌트 필드에 입력해둔 음식 이름을 그대로 넘겨서 새 입력
  /// 화면을 열고, 텍스트 기반 AI 추정 결과를 받아오면 기존 인식 결과 확인 섹션을
  /// 그대로 재사용해 보여준다(사진 기반 결과와 동일한 흐름).
  Future<void> _openManualEntry() async {
    final result = await Navigator.push<FoodRecognitionResult>(
      context,
      MaterialPageRoute(
        builder: (_) => ManualFoodEntryScreen(
          initialFoodName: _hintController.text.trim(),
          recognitionService: _recognitionService,
        ),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _image = null;
      _prepared = null;
      _errorMessage = null;
      _result = result;
      _foodNameController.text = result.foodName;
      _portionMultiplier = 1.0;
      _isManualEntry = true;
    });
  }

  Future<void> _recognize(File image) async {
    setState(() {
      _loading = true;
      _errorMessage = null;
      _photoLimitReached = false;
    });

    final hint = _hintController.text.trim();
    try {
      // 사진 변환은 처음 한 번만. 재시도 때는 같은 바이트를 다시 보낸다.
      final prepared = _prepared ?? await FoodPhotoService.instance.prepare(image);
      // 변환 중에 다른 사진을 고르거나 초기화했다면 이 결과는 버린다.
      if (!mounted || !identical(_image, image)) return;
      if (prepared == null) {
        // 원본을 그대로 올리지 않는다(서버 요청 전이라 일일 한도도 차감되지 않음).
        throw const FoodRecognitionException(
          FoodRecognitionFailure.unreadablePhoto,
          '사진 디코딩 실패(image 패키지·플랫폼 디코더 모두)',
        );
      }
      _prepared = prepared;
      final result = await _recognitionService.recognize(
        prepared.uploadJpeg,
        hint: hint.isEmpty ? null : hint,
      );
      if (!mounted || !identical(_image, image)) return;
      setState(() {
        _result = result;
        _foodNameController.text = result.foodName;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || !identical(_image, image)) return;
      final l10n = AppLocalizations.of(context)!;
      final limitReached = e is FoodRecognitionException &&
          e.failure == FoodRecognitionFailure.dailyLimitExceeded;
      final message = limitReached
          ? l10n.recognitionErrorPhotoDailyLimitExceeded
          : friendlyRecognitionErrorMessage(l10n, e);
      setState(() {
        _loading = false;
        _errorMessage = message;
        _photoLimitReached = limitReached;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          action: limitReached
              ? null
              : SnackBarAction(label: l10n.retryButton, onPressed: () => _recognize(image)),
        ),
      );
    }
  }

  /// 인식 결과를 취소하고 촬영/갤러리 버튼만 있는 초기 상태로 되돌린다.
  void _reset() {
    setState(() {
      _image = null;
      _prepared = null;
      _result = null;
      _errorMessage = null;
      _foodNameController.clear();
      _portionMultiplier = 1.0;
      _loading = false;
      _isManualEntry = false;
      _photoLimitReached = false;
    });
  }

  Future<void> _save() async {
    final result = _result;
    if (result == null || _saving) return;
    final foodName = _foodNameController.text.trim().isEmpty
        ? result.foodName
        : _foodNameController.text.trim();
    // 사진 축소·저장에 잠깐 걸리므로 중복 탭으로 같은 기록이 두 번 저장되지 않게 막는다.
    setState(() => _saving = true);
    try {
      await MealLogService.instance.saveMeal(
        name: foodName,
        calories: _totalCalories,
        amountG: result.estimatedWeightG > 0 ? result.estimatedWeightG * _portionMultiplier : null,
        carbsG: _totalCarbs,
        proteinG: _totalProtein,
        fatG: _totalFat,
        source: _isManualEntry ? LogSource.manual : LogSource.photo,
        // 사진은 이미 만들어 둔 저장용 축소본(800px)을 이 기기(documents/food_photos)에만 저장한다.
        photoJpeg: _isManualEntry ? null : _prepared?.storageJpeg,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
    _afterSaved();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.restaurant, color: AppColors.foodCoral, size: 22),
            const SizedBox(width: 8),
            Text(l10n.quickModeAppBarTitle),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            if (_myFoods.isNotEmpty && _result == null && !_loading) ...[
              _RecentFoodsStrip(
                foods: _myFoods,
                byFrequency: _myFoodsByFrequency,
                onSortChanged: _toggleMyFoodsSort,
                onTap: _openMyFood,
              ),
              const SizedBox(height: 16),
            ],
            if (_image != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(_image!, height: 220, fit: BoxFit.cover),
              )
            else
              Container(
                height: 220,
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(child: Text(l10n.quickModePlaceholder)),
              ),
            const SizedBox(height: 16),
            Text(
              l10n.quickModeGuidance,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _hintController,
              textAlign: TextAlign.center,
              decoration: InputDecoration(
                isDense: true,
                hintText: l10n.quickModeHintFieldPlaceholder,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _QuickModeActionButton(
                    icon: Icons.camera_alt,
                    label: l10n.quickModeCameraButton,
                    onPressed: () => _pickImage(ImageSource.camera),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _QuickModeActionButton(
                    icon: Icons.photo_library,
                    label: l10n.quickModeGalleryButton,
                    onPressed: () => _pickImage(ImageSource.gallery),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _QuickModeActionButton(
                    icon: Icons.edit_note,
                    label: l10n.quickModeManualEntryButton,
                    onPressed: _openManualEntry,
                  ),
                ),
              ],
            ),
            ValueListenableBuilder<RecognitionUsage?>(
              valueListenable: _recognitionService.usage,
              builder: (context, usage, _) {
                final photo = usage?.photo;
                if (photo == null || !photo.isLimited) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    l10n.quickModePhotoQuotaRemaining(photo.remaining!, photo.limit),
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                  ),
                );
              },
            ),
            const SizedBox(height: 4),
            Text(
              l10n.quickModeLaunchFreeNotice,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11, color: AppColors.foodCoral),
            ),
            const SizedBox(height: 24),
            if (_loading) const CircularProgressIndicator(),
            if (!_loading && _errorMessage != null) ...[
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.red),
              ),
              const SizedBox(height: 8),
              if (_photoLimitReached) ...[
                Text(
                  l10n.quickModeManualEntryStillAvailable,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _openManualEntry,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.foodCoral,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    icon: const Icon(Icons.edit_note),
                    label: Text(l10n.quickModeManualEntryButton),
                  ),
                ),
              ] else
                ElevatedButton.icon(
                  onPressed: _image == null ? null : () => _recognize(_image!),
                  icon: const Icon(Icons.refresh),
                  label: Text(l10n.retryButton),
                ),
            ],
            if (_result != null) ...[
              TextField(
                controller: _foodNameController,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                decoration: const InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  suffixIcon: Icon(Icons.edit, size: 18, color: AppColors.foodCoral),
                ),
              ),
              Text(l10n.quickModeConfidence((_result!.confidence * 100).toStringAsFixed(0)),
                  style: const TextStyle(color: Colors.grey)),
              const SizedBox(height: 12),
              Text(l10n.quickModePortionAdjust((_portionMultiplier * 100).toStringAsFixed(0))),
              Slider(
                value: _portionMultiplier,
                min: 0.5,
                max: 2.0,
                divisions: 15,
                label: '${(_portionMultiplier * 100).toStringAsFixed(0)}%',
                onChanged: (v) => setState(() => _portionMultiplier = v),
              ),
              Text(
                l10n.quickModeEstimatedSummary(
                  formatWeight(_result!.estimatedWeightG * _portionMultiplier, _unitSystem),
                  _totalCalories.toStringAsFixed(0),
                ),
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                l10n.nutrientsSummary(
                  _totalCarbs.toStringAsFixed(0),
                  _totalProtein.toStringAsFixed(0),
                  _totalFat.toStringAsFixed(0),
                ),
                style: const TextStyle(fontSize: 13, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: _saving ? null : _save, child: Text(l10n.saveButton)),
              const SizedBox(height: 8),
              RelatedProductsButton(
                queryBuilder: () => _foodNameController.text.trim().isEmpty
                    ? _result!.foodName
                    : _foodNameController.text.trim(),
              ),
              TextButton(onPressed: _reset, child: Text(l10n.quickModeRetakeResetButton)),
            ],
          ],
        ),
      ),
    );
  }
}

/// 촬영/갤러리/직접입력 3버튼 공용 스타일. 버튼이 2개에서 3개로 늘어나도 각 버튼의
/// 터치 영역이 좁아지지 않도록 아이콘/폰트/패딩을 조금씩 줄이고, Expanded로 균등
/// 배분해 폭 대신 세로 여백(패딩)으로 터치 영역을 확보한다.
class _QuickModeActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  const _QuickModeActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: AppColors.foodCoral, size: 20),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(fontSize: 12),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// 빠른측정 화면 상단 "최근 먹은 음식" 가로 목록(썸네일 + 이름). 최근순/자주 먹은 순 전환.
class _RecentFoodsStrip extends StatelessWidget {
  final List<MyFood> foods;
  final bool byFrequency;
  final ValueChanged<bool> onSortChanged;
  final ValueChanged<MyFood> onTap;

  const _RecentFoodsStrip({
    required this.foods,
    required this.byFrequency,
    required this.onSortChanged,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    Widget sortChip(String label, bool value) => ChoiceChip(
          label: Text(label, style: const TextStyle(fontSize: 11)),
          selected: byFrequency == value,
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          onSelected: (_) => onSortChanged(value),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.quickModeRecentFoodsTitle,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ),
            sortChip(l10n.myFoodsSortRecent, false),
            const SizedBox(width: 4),
            sortChip(l10n.myFoodsSortFrequent, true),
          ],
        ),
        Text(
          l10n.quickModeRecentFoodsHint,
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 96,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: foods.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, i) {
              final food = foods[i];
              return InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => onTap(food),
                child: SizedBox(
                  width: 68,
                  child: Column(
                    children: [
                      FoodPhotoThumbnail(path: food.photoPath, size: 60),
                      const SizedBox(height: 4),
                      Text(
                        food.name,
                        style: const TextStyle(fontSize: 11),
                        maxLines: 2,
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// 내 음식 목록 항목을 탭했을 때 뜨는 시트: 양 슬라이더(0.5x~2.0x)로 조정 후 저장.
/// 저장 버튼을 누르면 선택한 배율을 반환한다(실제 저장은 호출부에서).
class _MyFoodQuickSaveSheet extends StatefulWidget {
  final MyFood food;
  final UnitSystem unitSystem;

  const _MyFoodQuickSaveSheet({required this.food, required this.unitSystem});

  @override
  State<_MyFoodQuickSaveSheet> createState() => _MyFoodQuickSaveSheetState();
}

class _MyFoodQuickSaveSheetState extends State<_MyFoodQuickSaveSheet> {
  double _multiplier = 1.0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final food = widget.food;
    final calories = (food.calories * _multiplier).toStringAsFixed(0);
    final base = food.baseAmountG;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                FoodPhotoThumbnail(path: food.photoPath, size: 64),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(food.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 2),
                      Text(
                        l10n.myFoodUseCount(food.useCount),
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(l10n.quickModePortionAdjust((_multiplier * 100).toStringAsFixed(0))),
            Slider(
              value: _multiplier,
              min: 0.5,
              max: 2.0,
              divisions: 15,
              label: '${(_multiplier * 100).toStringAsFixed(0)}%',
              onChanged: (v) => setState(() => _multiplier = v),
            ),
            Text(
              base != null
                  ? l10n.myFoodAmountSummary(formatWeight(base * _multiplier, widget.unitSystem), calories)
                  : '$calories kcal',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              l10n.nutrientsSummary(
                (food.carbsG * _multiplier).toStringAsFixed(0),
                (food.proteinG * _multiplier).toStringAsFixed(0),
                (food.fatG * _multiplier).toStringAsFixed(0),
              ),
              style: const TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context, _multiplier),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.foodCoral,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: Text(l10n.saveButton),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
