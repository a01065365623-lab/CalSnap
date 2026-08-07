import 'dart:io';

import 'feature_extractor.dart';
import 'food_embedding_database.dart';

/// TFLite MobileNetV2 특징 추출 + 참조 임베딩 DB 코사인 유사도 매칭을 묶은 온디바이스 1차 인식기.
class OnDeviceFoodMatcher {
  final FeatureExtractor _extractor;
  final FoodEmbeddingDatabase _database;

  OnDeviceFoodMatcher({
    FeatureExtractor? extractor,
    FoodEmbeddingDatabase? database,
  })  : _extractor = extractor ?? FeatureExtractor(),
        _database = database ?? FoodEmbeddingDatabase();

  bool _ready = false;

  Future<void> load() async {
    if (_ready) return;
    await _extractor.load();
    await _database.load();
    _ready = true;
  }

  Future<FoodMatch?> match(File imageFile) async {
    if (!_ready) {
      await load();
    }
    final vector = await _extractor.extract(imageFile);
    return _database.findBestMatch(vector);
  }

  void dispose() {
    _extractor.close();
    _ready = false;
  }
}
