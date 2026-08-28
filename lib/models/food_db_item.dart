/// 로컬 한식 음식 DB(food_db 테이블) 한 건. "직접입력" 화면 자동완성에 쓰인다.
class FoodDbItem {
  final String id;
  final String nameKo;
  final String? nameEn;
  final String? country;
  final String? category;
  final double servingSizeG;
  final double calories; // servingSizeG 기준 총량(100g당 값 아님)
  final double carbsG;
  final double proteinG;
  final double fatG;
  final double? sodiumMg;
  final String? mainIngredients;
  final String? imageUrl;
  final String? aiRecognizedName;
  final String? createdAt;

  const FoodDbItem({
    required this.id,
    required this.nameKo,
    this.nameEn,
    this.country,
    this.category,
    required this.servingSizeG,
    required this.calories,
    required this.carbsG,
    required this.proteinG,
    required this.fatG,
    this.sodiumMg,
    this.mainIngredients,
    this.imageUrl,
    this.aiRecognizedName,
    this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name_ko': nameKo,
      'name_en': nameEn,
      'country': country,
      'category': category,
      'serving_size_g': servingSizeG,
      'calories': calories,
      'carbs_g': carbsG,
      'protein_g': proteinG,
      'fat_g': fatG,
      'sodium_mg': sodiumMg,
      'main_ingredients': mainIngredients,
      'image_url': imageUrl,
      'ai_recognized_name': aiRecognizedName,
      'created_at': createdAt,
    };
  }

  factory FoodDbItem.fromMap(Map<String, dynamic> map) {
    return FoodDbItem(
      id: map['id'] as String,
      nameKo: map['name_ko'] as String,
      nameEn: map['name_en'] as String?,
      country: map['country'] as String?,
      category: map['category'] as String?,
      servingSizeG: (map['serving_size_g'] as num).toDouble(),
      calories: (map['calories'] as num).toDouble(),
      carbsG: (map['carbs_g'] as num).toDouble(),
      proteinG: (map['protein_g'] as num).toDouble(),
      fatG: (map['fat_g'] as num).toDouble(),
      sodiumMg: (map['sodium_mg'] as num?)?.toDouble(),
      mainIngredients: map['main_ingredients'] as String?,
      imageUrl: map['image_url'] as String?,
      aiRecognizedName: map['ai_recognized_name'] as String?,
      createdAt: map['created_at'] as String?,
    );
  }

  factory FoodDbItem.fromSeedJson(Map<String, dynamic> json) {
    return FoodDbItem(
      id: json['id'] as String,
      nameKo: json['name_ko'] as String,
      nameEn: json['name_en'] as String?,
      country: json['country'] as String?,
      category: json['category'] as String?,
      servingSizeG: (json['serving_size_g'] as num).toDouble(),
      calories: (json['calories'] as num).toDouble(),
      carbsG: (json['carbs_g'] as num).toDouble(),
      proteinG: (json['protein_g'] as num).toDouble(),
      fatG: (json['fat_g'] as num).toDouble(),
      sodiumMg: (json['sodium_mg'] as num?)?.toDouble(),
      mainIngredients: json['main_ingredients'] as String?,
      imageUrl: json['image_url'] as String?,
      aiRecognizedName: json['ai_recognized_name'] as String?,
      createdAt: json['created_at'] as String?,
    );
  }

  /// 100g당 칼로리로 환산(FoodRecognitionResult와 동일한 스케일링 방식을 쓰기 위함).
  double get caloriesPer100g => servingSizeG > 0 ? calories / servingSizeG * 100 : 0;
  double get carbsPer100g => servingSizeG > 0 ? carbsG / servingSizeG * 100 : 0;
  double get proteinPer100g => servingSizeG > 0 ? proteinG / servingSizeG * 100 : 0;
  double get fatPer100g => servingSizeG > 0 ? fatG / servingSizeG * 100 : 0;
}
