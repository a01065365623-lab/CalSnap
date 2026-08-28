import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../models/food_db_item.dart';
import '../models/manual_amount_unit.dart';
import '../services/food_db_service.dart';
import '../services/food_recognition_service.dart';
import '../theme/app_colors.dart';

/// 빠른측정모드의 "직접 입력" 경로: 사진 없이 음식 이름과 양을 입력받아 AI로
/// 칼로리/영양소를 추정한다. 성공하면 [FoodRecognitionResult]를 pop으로 돌려주고,
/// 호출한 QuickModeScreen이 기존 "인식 결과 확인" 섹션을 그대로 재사용해 보여준다.
class ManualFoodEntryScreen extends StatefulWidget {
  final String initialFoodName;
  final FoodRecognitionService recognitionService;

  const ManualFoodEntryScreen({
    super.key,
    required this.initialFoodName,
    required this.recognitionService,
  });

  @override
  State<ManualFoodEntryScreen> createState() => _ManualFoodEntryScreenState();
}

class _ManualFoodEntryScreenState extends State<ManualFoodEntryScreen> {
  late final _foodNameController = TextEditingController(text: widget.initialFoodName);
  final _amountController = TextEditingController();

  ManualAmountUnit _unit = ManualAmountUnit.gram;
  bool _unitManuallySet = false;
  bool _loading = false;
  String? _errorMessage;
  String? _foodNameError;
  String? _amountError;

  // 로컬 음식 DB 자동완성. 선택된 항목이 있고 이름을 바꾸지 않았다면, 제출 시 AI
  // 호출 없이 DB 영양 정보로 바로 결과를 만든다(DB에 없으면 기존 AI 추정으로 폴백).
  List<FoodDbItem> _suggestions = [];
  FoodDbItem? _selectedDbItem;
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _unit = suggestUnitForFoodName(widget.initialFoodName);
    _foodNameController.addListener(_onFoodNameChanged);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _foodNameController.removeListener(_onFoodNameChanged);
    _foodNameController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  /// 사용자가 단위를 직접 고르기 전까지는, 음식 이름이 바뀔 때마다 추천 단위를 갱신한다.
  /// 아울러 이름 입력을 디바운스해 로컬 음식 DB 자동완성을 검색한다.
  void _onFoodNameChanged() {
    final text = _foodNameController.text;
    if (!_unitManuallySet) {
      final suggested = suggestUnitForFoodName(text);
      if (suggested != _unit) setState(() => _unit = suggested);
    }

    final trimmed = text.trim();
    if (_selectedDbItem != null && trimmed != _selectedDbItem!.nameKo) {
      setState(() => _selectedDbItem = null);
    }

    _searchDebounce?.cancel();
    if (trimmed.isEmpty || (_selectedDbItem != null && trimmed == _selectedDbItem!.nameKo)) {
      if (_suggestions.isNotEmpty) setState(() => _suggestions = []);
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 250), () => _searchDb(trimmed));
  }

  Future<void> _searchDb(String query) async {
    final results = await FoodDbService.instance.searchFood(query);
    if (!mounted || _foodNameController.text.trim() != query) return;
    setState(() => _suggestions = results);
  }

  /// 자동완성 항목 선택: 음식명/양(g)을 DB 값으로 채우고, 그램 단위로 고정한다
  /// (로컬 DB는 g 기준 값만 갖고 있어 단위 환산을 지원하지 않는다).
  void _selectSuggestion(FoodDbItem item) {
    setState(() {
      _foodNameController.text = item.nameKo;
      _foodNameController.selection = TextSelection.collapsed(offset: item.nameKo.length);
      _amountController.text = item.servingSizeG.toStringAsFixed(0);
      _unit = ManualAmountUnit.gram;
      _unitManuallySet = true;
      _selectedDbItem = item;
      _suggestions = [];
      _foodNameError = null;
      _amountError = null;
    });
    FocusScope.of(context).unfocus();
  }

  /// 검색 결과 항목 아래 표시 줄. name_en(영문 카테고리명)이 있으면 "Pizza · 240kcal ·
  /// 100g"처럼 맨 앞에 덧붙이고, 없는(순수 한식) 항목은 기존처럼 kcal/g만 보여준다.
  String _suggestionSubtitle(FoodDbItem item) {
    final kcalAndServing =
        '${item.calories.toStringAsFixed(0)}kcal · ${item.servingSizeG.toStringAsFixed(0)}g';
    final nameEn = item.nameEn?.trim();
    if (nameEn == null || nameEn.isEmpty) return kcalAndServing;
    final capitalized = nameEn[0].toUpperCase() + nameEn.substring(1);
    return '$capitalized · $kcalAndServing';
  }

  double? _parseAmount() => double.tryParse(_amountController.text.trim());

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context)!;
    final foodName = _foodNameController.text.trim();
    final amount = _parseAmount();

    setState(() {
      _foodNameError = foodName.isEmpty ? l10n.manualEntryFoodNameRequiredError : null;
      _amountError = (amount == null || amount <= 0) ? l10n.manualEntryAmountRequiredError : null;
    });
    if (_foodNameError != null || _amountError != null) return;

    // DB에서 고른 음식이고 이름을 그대로 유지했다면, AI 호출 없이 로컬 영양 정보로
    // 바로 결과를 만든다. 이름이 바뀌었거나 DB에 없는 음식이면 기존 AI 추정으로 폴백.
    final dbItem = _selectedDbItem;
    if (dbItem != null && foodName == dbItem.nameKo) {
      Navigator.pop(
        context,
        FoodRecognitionResult(
          foodName: foodName,
          caloriesPer100g: dbItem.caloriesPer100g,
          estimatedWeightG: amount!,
          confidence: 1.0,
          carbsG: dbItem.carbsPer100g,
          proteinG: dbItem.proteinPer100g,
          fatG: dbItem.fatPer100g,
        ),
      );
      return;
    }

    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final result = await widget.recognitionService.recognizeFromText(
        foodName: foodName,
        amount: amount!,
        unit: _unit.apiValue,
      );
      if (!mounted) return;
      Navigator.pop(context, result);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = friendlyRecognitionErrorMessage(l10n, e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.manualEntryAppBarTitle)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _foodNameController,
              decoration: InputDecoration(
                labelText: l10n.manualEntryFoodNameLabel,
                hintText: l10n.manualEntryFoodNameHint,
                errorText: _foodNameError,
              ),
            ),
            if (_suggestions.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(top: 4),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final item in _suggestions)
                      ListTile(
                        dense: true,
                        title: Text(item.nameKo),
                        subtitle: Text(_suggestionSubtitle(item)),
                        onTap: () => _selectSuggestion(item),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _amountController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: l10n.manualEntryAmountLabel,
                      errorText: _amountError,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                DropdownButton<ManualAmountUnit>(
                  value: _unit,
                  // 로컬 DB에서 고른 항목은 g 기준 값만 있어 단위 환산을 지원하지
                  // 않으므로, 선택되어 있는 동안은 단위를 그램으로 고정한다.
                  onChanged: _selectedDbItem != null
                      ? null
                      : (value) {
                          if (value == null) return;
                          setState(() {
                            _unit = value;
                            _unitManuallySet = true;
                          });
                        },
                  items: [
                    for (final unit in ManualAmountUnit.values)
                      DropdownMenuItem(value: unit, child: Text(unit.label(l10n))),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 24),
            if (_loading) const Center(child: CircularProgressIndicator()),
            if (!_loading && _errorMessage != null) ...[
              Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 8),
            ],
            if (!_loading)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _submit,
                  icon: const Icon(Icons.auto_awesome, color: AppColors.foodCoral),
                  label: Text(l10n.manualEntryEstimateButton),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
