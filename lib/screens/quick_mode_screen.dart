import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:image_picker/image_picker.dart';

import '../config/feature_flags.dart';
import '../db/database_helper.dart';
import '../models/daily_log_entry.dart';
import '../services/food_recognition_service.dart';
import '../services/gemini_food_recognition_service.dart';
import '../services/tts_service.dart';
import '../services/user_profile_service.dart';
import '../theme/app_colors.dart';
import '../utils/unit_converter.dart';
import '../widgets/related_products_button.dart';
import 'manual_food_entry_screen.dart';

class QuickModeScreen extends StatefulWidget {
  const QuickModeScreen({super.key});

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
  FoodRecognitionResult? _result;
  double _portionMultiplier = 1.0; // 보정 슬라이더 (0.5x ~ 2.0x)
  bool _loading = false;
  String? _errorMessage;
  UnitSystem _unitSystem = UnitSystem.metric;
  // 사진 없이 "직접 입력" 경로로 얻은 결과인지 구분해서 저장 시 source에 반영한다.
  bool _isManualEntry = false;

  @override
  void initState() {
    super.initState();
    _loadUnitSystem();
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
    // 리사이즈/압축은 GeminiFoodRecognitionService가 업로드 직전에 한 번만 수행한다
    // (여기서 imageQuality까지 지정하면 원본 미리보기 화질만 낮아지고 이중 압축이 됨).
    final picked = await _picker.pickImage(source: source);
    if (picked == null) return;

    final image = File(picked.path);
    setState(() {
      _image = image;
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
    });

    final hint = _hintController.text.trim();
    try {
      final result = await _recognitionService.recognize(
        image,
        hint: hint.isEmpty ? null : hint,
      );
      if (!mounted) return;
      setState(() {
        _result = result;
        _foodNameController.text = result.foodName;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context)!;
      final message = friendlyRecognitionErrorMessage(l10n, e);
      setState(() {
        _loading = false;
        _errorMessage = message;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          action: SnackBarAction(label: l10n.retryButton, onPressed: () => _recognize(image)),
        ),
      );
    }
  }

  /// 인식 결과를 취소하고 촬영/갤러리 버튼만 있는 초기 상태로 되돌린다.
  void _reset() {
    setState(() {
      _image = null;
      _result = null;
      _errorMessage = null;
      _foodNameController.clear();
      _portionMultiplier = 1.0;
      _loading = false;
      _isManualEntry = false;
    });
  }

  Future<void> _save() async {
    if (_result == null) return;
    final foodName = _foodNameController.text.trim().isEmpty
        ? _result!.foodName
        : _foodNameController.text.trim();
    await DatabaseHelper.instance.insertLog(DailyLogEntry(
      datetime: DateTime.now(),
      type: LogType.food,
      name: foodName,
      calories: _totalCalories,
      mode: LogMode.quick,
      carbsG: _totalCarbs,
      proteinG: _totalProtein,
      fatG: _totalFat,
      source: _isManualEntry ? LogSource.manual : LogSource.photo,
    ));
    unawaited(TtsService.instance.speakAfterSave(TtsCategory.mealSave));
    if (mounted) {
      final l10n = AppLocalizations.of(context)!;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.savedSnackbarMessage)),
      );
    }
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
            const SizedBox(height: 24),
            if (_loading) const CircularProgressIndicator(),
            if (!_loading && _errorMessage != null) ...[
              Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
              if (kShowPrivateTestQuotaNotice) ...[
                const SizedBox(height: 4),
                Text(
                  l10n.quickModePrivateTestQuotaNotice,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ],
              const SizedBox(height: 8),
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
              ElevatedButton(onPressed: _save, child: Text(l10n.saveButton)),
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
