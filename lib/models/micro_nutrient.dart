/// 오늘의 로그 "비타민·미네랄" 카드의 8개 항목. [jsonKey]는
/// assets/nutrition/micro_nutrients.json의 per100g 키, [unit]은 화면 표시 단위다.
enum MicroNutrient {
  vitaminD('vitaminD_ug', 'µg'),
  vitaminB12('vitaminB12_ug', 'µg'),
  vitaminA('vitaminA_ugRAE', 'µg RAE'),
  vitaminC('vitaminC_mg', 'mg'),
  iron('iron_mg', 'mg'),
  calcium('calcium_mg', 'mg'),
  zinc('zinc_mg', 'mg'),
  potassium('potassium_mg', 'mg');

  const MicroNutrient(this.jsonKey, this.unit);

  final String jsonKey;
  final String unit;
}

/// 성인 1일 기준량. 식약처 「식품등의 표시기준」 1일 영양성분 기준치(성인, 표시용)를 따른다.
/// 성별·나이·임신 여부에 따라 실제 권장 섭취량은 다르므로, 화면의 %는 이 기준치 대비
/// 참고값일 뿐이다.
const Map<MicroNutrient, double> microNutrientDailyReference = {
  MicroNutrient.vitaminD: 10, // µg
  MicroNutrient.vitaminB12: 2.4, // µg
  MicroNutrient.vitaminA: 700, // µg RAE
  MicroNutrient.vitaminC: 100, // mg
  MicroNutrient.iron: 12, // mg
  MicroNutrient.calcium: 700, // mg
  MicroNutrient.zinc: 8.5, // mg
  MicroNutrient.potassium: 3500, // mg
};
