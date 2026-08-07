import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart' show rootBundle;

/// 참조 음식 1종의 특징벡터 항목.
class FoodEmbedding {
  final String foodName;
  final double caloriesPer100g;
  final List<double> vector;

  const FoodEmbedding({
    required this.foodName,
    required this.caloriesPer100g,
    required this.vector,
  });

  factory FoodEmbedding.fromJson(Map<String, dynamic> json) {
    return FoodEmbedding(
      foodName: json['foodName'] as String,
      caloriesPer100g: (json['caloriesPer100g'] as num).toDouble(),
      vector: (json['vector'] as List)
          .map((e) => (e as num).toDouble())
          .toList(),
    );
  }
}

class FoodMatch {
  final FoodEmbedding food;
  final double similarity; // 코사인 유사도, -1.0 ~ 1.0

  const FoodMatch({required this.food, required this.similarity});
}

/// assets/food_embeddings.json 에 저장된 참조 음식 특징벡터 DB.
/// 오프라인 생성 스크립트: tools/build_embedding_db.py 참고.
class FoodEmbeddingDatabase {
  static const String assetPath = 'assets/food_embeddings.json';

  List<FoodEmbedding> _entries = const [];

  bool get isLoaded => _entries.isNotEmpty;

  Future<void> load() async {
    final raw = await rootBundle.loadString(assetPath);
    loadFromJsonString(raw);
  }

  /// asset 번들 없이도 테스트할 수 있도록 JSON 문자열을 직접 주입하는 경로.
  void loadFromJsonString(String raw) {
    final list = jsonDecode(raw) as List;
    _entries = list
        .map((e) => FoodEmbedding.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  FoodMatch? findBestMatch(List<double> queryVector) {
    if (_entries.isEmpty) return null;

    FoodEmbedding? best;
    var bestScore = -1.0;
    for (final entry in _entries) {
      final score = _cosineSimilarity(queryVector, entry.vector);
      if (score > bestScore) {
        bestScore = score;
        best = entry;
      }
    }
    if (best == null) return null;
    return FoodMatch(food: best, similarity: bestScore);
  }

  double _cosineSimilarity(List<double> a, List<double> b) {
    if (a.length != b.length) {
      throw ArgumentError('벡터 차원이 다릅니다: ${a.length} vs ${b.length}');
    }
    var dot = 0.0, normA = 0.0, normB = 0.0;
    for (var i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }
    if (normA == 0 || normB == 0) return 0;
    return dot / (sqrt(normA) * sqrt(normB));
  }
}
