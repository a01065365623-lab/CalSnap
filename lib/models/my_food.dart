/// "내 음식 목록"(my_foods) 한 건. 식사를 저장할 때마다 음식명 기준으로 저장/갱신되며,
/// 빠른측정 화면의 "최근 먹은 음식"에서 탭하면 AI 인식(Gemini) 없이 이 값을 양 비율로
/// 환산해 바로 기록한다.
///
/// calories/carbsG/proteinG/fatG는 [baseAmountG]만큼 먹었을 때의 절대값이다(가장 최근에
/// 저장한 1회분 기준). [baseAmountG]가 없으면(중량 정보 없는 기록) 1회분 단위로만 환산한다.
class MyFood {
  final int? id;
  final String name;
  final double? baseAmountG;
  final double calories;
  final double carbsG;
  final double proteinG;
  final double fatG;
  final String? photoPath;
  final int useCount;
  final DateTime lastUsedAt;

  const MyFood({
    this.id,
    required this.name,
    this.baseAmountG,
    required this.calories,
    this.carbsG = 0,
    this.proteinG = 0,
    this.fatG = 0,
    this.photoPath,
    this.useCount = 0,
    required this.lastUsedAt,
  });

  factory MyFood.fromMap(Map<String, dynamic> map) {
    return MyFood(
      id: map['id'] as int?,
      name: map['name'] as String,
      baseAmountG: (map['base_amount_g'] as num?)?.toDouble(),
      calories: (map['calories'] as num).toDouble(),
      carbsG: (map['carbs_g'] as num?)?.toDouble() ?? 0,
      proteinG: (map['protein_g'] as num?)?.toDouble() ?? 0,
      fatG: (map['fat_g'] as num?)?.toDouble() ?? 0,
      photoPath: map['photo_path'] as String?,
      useCount: (map['use_count'] as num?)?.toInt() ?? 0,
      lastUsedAt: DateTime.parse(map['last_used_at'] as String),
    );
  }
}
