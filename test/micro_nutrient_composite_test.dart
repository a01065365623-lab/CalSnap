import 'dart:convert';
import 'dart:io';

import 'package:calsnap/models/daily_log_entry.dart';
import 'package:calsnap/models/micro_nutrient.dart';
import 'package:calsnap/services/micro_nutrient_db.dart';
import 'package:flutter_test/flutter_test.dart';

final foodsJson = jsonDecode(File('assets/nutrition/micro_nutrients.json').readAsStringSync());
final compositesJson = jsonDecode(File('assets/nutrition/composites.json').readAsStringSync()) as Map<String, Object?>;
final singlesOnly = MicroNutrientDb.fromJson(foodsJson);
final db = MicroNutrientDb.fromJson(foodsJson, composites: compositesJson);
final composites = (compositesJson['composites'] as List).cast<Map<String, Object?>>();

Map<String, Object?> food(String ko, Map<String, num?> per100g) => {
      'ko': ko,
      'en': ko,
      'aliases': <String>[],
      'per100g': {for (final n in MicroNutrient.values) n.jsonKey: per100g[n.jsonKey]},
    };

void main() {
  group('composites.json', () {
    test('20~30개, 재료는 모두 기존 DB 음식이고 g은 양수', () {
      expect(composites.length, inInclusiveRange(20, 30));
      final koNames = {for (final f in (foodsJson as Map)['foods'] as List) (f as Map)['ko']};
      for (final c in composites) {
        for (final i in (c['ingredients'] as List).cast<Map>()) {
          expect(koNames, contains(i['food']), reason: '${c['ko']}: ${i['food']}');
          expect(i['g'], isA<num>().having((g) => g > 0, 'g > 0', isTrue));
        }
      }
    });

    test('모든 복합 요리가 로드되고 approx로 취급된다', () {
      expect(db.size, singlesOnly.size + composites.length);
      for (final c in composites) {
        final m = db.lookup(c['ko'] as String)!;
        expect(m.food.nameKo, c['ko']);
        expect(m.partial, isFalse);
        expect(m.approx, isTrue, reason: '${c['ko']}');
      }
    });

    test('복합 요리 이름·별칭이 USDA 단일 음식과 정확히 겹치지 않는다(단일 음식 우선 규칙이 필요 없게)', () {
      for (final c in composites) {
        for (final name in [c['ko'], c['en'], ...(c['aliases'] as List)].cast<String>()) {
          final m = singlesOnly.lookup(name);
          expect(m == null || m.partial, isTrue, reason: '$name → ${m?.food.nameKo}');
        }
      }
    });

    test('USDA에 정확히 있는 비빔밥·볶음밥·햄샌드위치는 그대로 USDA 값', () {
      for (final name in ['비빔밥', '볶음밥', '햄샌드위치']) {
        final m = db.lookup(name)!;
        expect(m.food.nameKo, singlesOnly.lookup(name)!.food.nameKo, reason: name);
        expect(m.partial, isFalse, reason: name);
        expect(m.food.per100g, singlesOnly.lookup(name)!.food.per100g, reason: name);
      }
    });
  });

  group('재료 g 가중 평균', () {
    test('100g당 값 = Σ(재료 100g당 값 × g) ÷ 총 g', () {
      final d = MicroNutrientDb.fromJson(
        {
          'foods': [
            food('밥', {'iron_mg': 1, 'calcium_mg': 10, 'vitaminC_mg': 0}),
            food('시금치', {'iron_mg': 3, 'calcium_mg': 100, 'vitaminC_mg': 20}),
          ],
        },
        composites: {
          'composites': [
            {
              'ko': '시금치밥',
              'en': 'spinach rice',
              'aliases': [],
              'ingredients': [
                {'food': '밥', 'g': 150},
                {'food': '시금치', 'g': 50},
              ],
            },
          ],
        },
      );
      final dish = d.match('시금치밥')!;
      expect(dish.approx, isTrue);
      expect(dish.per100g[MicroNutrient.iron], closeTo((1 * 150 + 3 * 50) / 200, 1e-9));
      expect(dish.per100g[MicroNutrient.calcium], closeTo((10 * 150 + 100 * 50) / 200, 1e-9));
      expect(dish.per100g[MicroNutrient.vitaminC], closeTo(5, 1e-9));
      expect(dish.per100g[MicroNutrient.zinc], isNull, reason: '재료에 값이 없으면 null');
    });

    test('DB에 없는 재료·잘못된 g가 있으면 그 요리만 건너뛴다(예외 없음)', () {
      final d = MicroNutrientDb.fromJson(
        {
          'foods': [food('밥', {'iron_mg': 1})],
        },
        composites: {
          'composites': [
            {'ko': '없는재료밥', 'en': 'x', 'ingredients': [{'food': '밥', 'g': 100}, {'food': '고추장', 'g': 10}]},
            {'ko': '음수밥', 'en': 'y', 'ingredients': [{'food': '밥', 'g': -5}]},
            {'ko': '빈요리', 'en': 'z', 'ingredients': []},
            'garbage',
            {'ko': '밥두공기', 'en': 'two bowls', 'ingredients': [{'food': '밥', 'g': 400}]},
          ],
        },
      );
      expect(d.match('없는재료밥'), isNull);
      expect(d.match('음수밥'), isNull);
      expect(d.match('빈요리'), isNull);
      expect(d.match('밥두공기')?.per100g[MicroNutrient.iron], closeTo(1, 1e-9));
      expect(MicroNutrientDb.fromJson({'foods': []}, composites: 'oops').size, 0);
    });
  });

  group('부분 일치와 함께', () {
    test('복합 요리 이름이 더 길면 재료보다 우선', () {
      expect(db.lookup('돼지고기 김치볶음밥')!.food.nameKo, '김치볶음밥');
      expect(db.lookup('소고기 야채김밥')!.food.nameKo, '김밥');
      expect(db.lookup('바나나우유')!.food.nameKo, '바나나우유', reason: '바나나가 아니라 우유 음료');
      expect(db.lookup('매콤 제육덮밥 곱빼기')!.food.nameKo, '제육덮밥');
    });

    test('"닭가슴살 샐러드"는 닭가슴살 샐러드 복합 요리로', () {
      final m = db.lookup('닭가슴살 샐러드')!;
      expect(m.food.nameKo, '닭가슴살 샐러드');
      expect(m.partial, isFalse);
      expect(m.approx, isTrue);
      expect(db.lookup('닭가슴살 샐러드 도시락')!.food.nameKo, '닭가슴살 샐러드');
      expect(db.lookup('Grilled chicken salad')!.food.nameKo, '닭가슴살 샐러드');
    });

    test('국물 요리 가드는 그대로', () {
      expect(db.lookup('김치볶음밥 국'), isNull);
      expect(db.lookup('불고기 전골'), isNull);
    });
  });

  test('복합 요리로 합산한 기록은 approxCount에 들어간다', () {
    final s = summarizeMicroNutrients([
      DailyLogEntry(datetime: DateTime(2026, 11, 16, 12), type: LogType.food, name: '김밥', calories: 400, amount: 230),
      DailyLogEntry(datetime: DateTime(2026, 11, 16, 13), type: LogType.food, name: '쌀밥', calories: 300, amount: 210),
    ], db);
    expect(s.matchedCount, 2);
    expect(s.approxCount, 1);
  });
}
