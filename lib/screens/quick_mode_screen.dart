import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:image_picker/image_picker.dart';

import '../db/database_helper.dart';
import '../models/daily_log_entry.dart';
import '../services/food_recognition_service.dart';
import '../services/gemini_food_recognition_service.dart';
import '../services/tts_service.dart';
import '../services/user_profile_service.dart';
import '../theme/app_colors.dart';
import '../utils/unit_converter.dart';
import '../widgets/related_products_button.dart';

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
    final picked = await _picker.pickImage(source: source, imageQuality: 80);
    if (picked == null) return;

    final image = File(picked.path);
    setState(() {
      _image = image;
      _result = null;
      _errorMessage = null;
    });
    await _recognize(image);
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
      final message = _friendlyErrorMessage(l10n, e);
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

  String _friendlyErrorMessage(AppLocalizations l10n, Object error) {
    if (error is FoodRecognitionException) {
      switch (error.failure) {
        case FoodRecognitionFailure.unauthorized:
          return l10n.recognitionErrorUnauthorized;
        case FoodRecognitionFailure.timeout:
          return l10n.recognitionErrorTimeout;
        case FoodRecognitionFailure.network:
          return l10n.recognitionErrorNetwork;
        case FoodRecognitionFailure.server:
        case FoodRecognitionFailure.unknown:
          return l10n.recognitionErrorGeneric;
      }
    }
    return l10n.recognitionErrorGeneric;
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
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  onPressed: () => _pickImage(ImageSource.camera),
                  icon: const Icon(Icons.camera_alt, color: AppColors.foodCoral),
                  label: Text(l10n.quickModeCameraButton),
                ),
                ElevatedButton.icon(
                  onPressed: () => _pickImage(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library, color: AppColors.foodCoral),
                  label: Text(l10n.quickModeGalleryButton),
                ),
              ],
            ),
            const SizedBox(height: 24),
            if (_loading) const CircularProgressIndicator(),
            if (!_loading && _errorMessage != null) ...[
              Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
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
