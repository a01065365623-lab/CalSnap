import 'dart:convert';
import 'package:http/http.dart' as http;

/// 식약처 식품영양성분DB(공공데이터포털) 연동 서비스.
/// API 키 발급 후 baseUrl/apiKey 채워서 사용.
/// https://various.foodsafetykorea.go.kr/nutrient/ 참고
class NutritionInfo {
  final String foodName;
  final double caloriesPer100g;
  final double? carbs;
  final double? protein;
  final double? fat;

  const NutritionInfo({
    required this.foodName,
    required this.caloriesPer100g,
    this.carbs,
    this.protein,
    this.fat,
  });

  factory NutritionInfo.fromJson(Map<String, dynamic> json) {
    return NutritionInfo(
      foodName: json['foodName'] as String? ?? '',
      caloriesPer100g: double.tryParse(json['calories']?.toString() ?? '') ?? 0,
      carbs: double.tryParse(json['carbs']?.toString() ?? ''),
      protein: double.tryParse(json['protein']?.toString() ?? ''),
      fat: double.tryParse(json['fat']?.toString() ?? ''),
    );
  }
}

class NutritionApiService {
  // TODO: 식약처 공공데이터포털에서 발급받은 API 키로 교체
  static const String _apiKey = 'YOUR_API_KEY_HERE';
  static const String _baseUrl = 'https://openapi.foodsafetykorea.go.kr/api';

  Future<List<NutritionInfo>> searchFood(String query) async {
    final url = Uri.parse('$_baseUrl/$_apiKey/I2790/json/1/20/DESC_KOR=$query');
    final res = await http.get(url);

    if (res.statusCode != 200) {
      throw Exception('식약처 API 호출 실패: ${res.statusCode}');
    }

    final data = jsonDecode(res.body);
    final rows = (data['I2790']?['row'] as List?) ?? [];

    return rows
        .map((r) => NutritionInfo(
              foodName: r['DESC_KOR'] ?? '',
              caloriesPer100g: double.tryParse(r['NUTR_CONT1']?.toString() ?? '') ?? 0,
              carbs: double.tryParse(r['NUTR_CONT2']?.toString() ?? ''),
              protein: double.tryParse(r['NUTR_CONT3']?.toString() ?? ''),
              fat: double.tryParse(r['NUTR_CONT4']?.toString() ?? ''),
            ))
        .toList();
  }
}
