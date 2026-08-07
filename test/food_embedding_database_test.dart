import 'package:calsnap/services/food_recognition/food_embedding_database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('findBestMatch returns the closest vector by cosine similarity', () {
    final db = FoodEmbeddingDatabase();
    db.loadFromJsonString('''
    [
      {"foodName": "김치찌개", "caloriesPer100g": 90, "vector": [1, 0, 0]},
      {"foodName": "된장찌개", "caloriesPer100g": 80, "vector": [0, 1, 0]}
    ]
    ''');

    final match = db.findBestMatch([0.9, 0.1, 0]);

    expect(match, isNotNull);
    expect(match!.food.foodName, '김치찌개');
    expect(match.similarity, closeTo(0.994, 0.01));
  });

  test('returns null when database is empty', () {
    final db = FoodEmbeddingDatabase();
    expect(db.findBestMatch([1, 0]), isNull);
  });

  test('throws when query vector dimension differs from stored vectors', () {
    final db = FoodEmbeddingDatabase();
    db.loadFromJsonString(
      '[{"foodName": "테스트", "caloriesPer100g": 100, "vector": [1, 2, 3]}]',
    );
    expect(() => db.findBestMatch([1, 2]), throwsArgumentError);
  });
}
