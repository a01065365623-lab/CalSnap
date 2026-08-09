import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../db/database_helper.dart';
import '../models/daily_log_entry.dart';
import '../services/food_recognition_service.dart';
import '../services/gemini_food_recognition_service.dart';

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

  File? _image;
  FoodRecognitionResult? _result;
  double _portionMultiplier = 1.0; // 보정 슬라이더 (0.5x ~ 2.0x)
  bool _loading = false;

  @override
  void dispose() {
    _foodNameController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    final picked = await _picker.pickImage(source: source, imageQuality: 80);
    if (picked == null) return;

    setState(() {
      _image = File(picked.path);
      _loading = true;
      _result = null;
    });

    final result = await _recognitionService.recognize(_image!);
    setState(() {
      _result = result;
      _foodNameController.text = result.foodName;
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
      calories: _result!.estimatedCalories * _portionMultiplier,
      mode: LogMode.quick,
    ));
    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('저장했어요')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('빠른 측정')),
      body: Padding(
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
                child: const Center(child: Text('사진을 찍거나 선택해주세요')),
              ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  onPressed: () => _pickImage(ImageSource.camera),
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('촬영'),
                ),
                ElevatedButton.icon(
                  onPressed: () => _pickImage(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library),
                  label: const Text('갤러리'),
                ),
              ],
            ),
            const SizedBox(height: 24),
            if (_loading) const CircularProgressIndicator(),
            if (_result != null) ...[
              TextField(
                controller: _foodNameController,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                decoration: const InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  suffixIcon: Icon(Icons.edit, size: 18),
                ),
              ),
              Text('추정 정확도 ${(_result!.confidence * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(color: Colors.grey)),
              const SizedBox(height: 12),
              Text('양 보정: ${(_portionMultiplier * 100).toStringAsFixed(0)}%'),
              Slider(
                value: _portionMultiplier,
                min: 0.5,
                max: 2.0,
                divisions: 15,
                label: '${(_portionMultiplier * 100).toStringAsFixed(0)}%',
                onChanged: (v) => setState(() => _portionMultiplier = v),
              ),
              Text(
                '${(_result!.estimatedCalories * _portionMultiplier).toStringAsFixed(0)} kcal',
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: _save, child: const Text('저장')),
            ],
          ],
        ),
      ),
    );
  }
}
