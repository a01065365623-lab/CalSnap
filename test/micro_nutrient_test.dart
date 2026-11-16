import 'dart:convert';
import 'dart:io';

import 'package:calsnap/models/daily_log_entry.dart';
import 'package:calsnap/models/micro_nutrient.dart';
import 'package:calsnap/services/micro_nutrient_db.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> food(String ko, String en, List<String> aliases, Map<String, num?> per100g,
        {Object? approx = false}) =>
    {
      'ko': ko,
      'approx': approx,
      'en': en,
      'aliases': aliases,
      'per100g': {
        for (final n in MicroNutrient.values) n.jsonKey: per100g[n.jsonKey],
      },
    };

final sampleDb = MicroNutrientDb.fromJson({
  'foods': [
    food('삶은 계란', 'hard-boiled egg', ['삶은달걀', 'boiled egg'], {
      'vitaminD_ug': 2.2,
      'vitaminB12_ug': 1.1,
      'calcium_mg': 50,
      'iron_mg': 1.2,
    }),
    food('닭가슴살', 'chicken breast', ['chicken breast'], {'zinc_mg': 1.0, 'potassium_mg': 250}),
    food('명태', 'pollock', ['동태'], {'vitaminD_ug': null, 'calcium_mg': 20}),
    food('라면', 'ramen', ['ramyeon'], {'iron_mg': 0.5, 'calcium_mg': 10}, approx: true),
  ],
});

DailyLogEntry entry(String name, double? grams, {LogType type = LogType.food}) => DailyLogEntry(
      datetime: DateTime(2026, 11, 16, 12),
      type: type,
      name: name,
      calories: type == LogType.exercise ? -100 : 100,
      amount: grams,
    );

void main() {
  group('normalizeFoodName', () {
    test('공백·괄호·대소문자·하이픈 제거', () {
      expect(normalizeFoodName(' 삶은  계란 '), '삶은계란');
      expect(normalizeFoodName('Hard-Boiled Egg'), 'hardboiledegg');
      expect(normalizeFoodName('닭가슴살(구이)'), '닭가슴살구이');
      expect(normalizeFoodName('［김치］'), '김치');
    });

    test('괄호 내용까지 지우는 2차 정규화', () {
      expect(normalizeFoodNameWithoutBrackets('닭가슴살 (100g)'), '닭가슴살');
      expect(normalizeFoodNameWithoutBrackets('Banana (ripe)'), 'banana');
      expect(normalizeFoodNameWithoutBrackets('김치（배추）'), '김치');
    });
  });

  group('MicroNutrientDb.match', () {
    test('한글명·영문명·별칭, 띄어쓰기·대소문자 무관', () {
      expect(sampleDb.match('삶은계란')?.nameKo, '삶은 계란');
      expect(sampleDb.match('Hard Boiled Egg')?.nameKo, '삶은 계란');
      expect(sampleDb.match('BOILED EGG')?.nameKo, '삶은 계란');
      expect(sampleDb.match('삶은 달걀')?.nameKo, '삶은 계란');
      expect(sampleDb.match('동태')?.nameKo, '명태');
    });

    test('괄호 꾸밈말은 2차로 맞춘다', () {
      expect(sampleDb.match('닭가슴살(100g)')?.nameKo, '닭가슴살');
      expect(sampleDb.match('Chicken breast (grilled)')?.nameKo, '닭가슴살');
    });

    test('부분 일치는 하지 않는다', () {
      expect(sampleDb.match('닭가슴살 샐러드'), isNull);
      expect(sampleDb.match('계란'), isNull);
    });

    test('다른 언어·빈 문자열·이상한 입력은 예외 없이 null', () {
      for (final name in ['', '   ', '()', 'Pechuga de pollo', '鶏むね肉', 'صدر دجاج', 'Куриная грудка', '🍗🍗', 'x' * 5000]) {
        expect(sampleDb.match(name), isNull, reason: name);
      }
    });
  });

  group('MicroNutrientDb.fromJson', () {
    test('깨진 데이터는 빈 DB(예외 없음)', () {
      expect(MicroNutrientDb.fromJson(null).size, 0);
      expect(MicroNutrientDb.fromJson('oops').size, 0);
      expect(MicroNutrientDb.fromJson({'foods': 'x'}).size, 0);
      final partial = MicroNutrientDb.fromJson({
        'foods': [
          {'ko': 1},
          'nope',
          food('사과', 'apple', [], {'vitaminC_mg': 4}),
        ],
      });
      expect(partial.size, 1);
      expect(partial.match('apple')?.per100g[MicroNutrient.vitaminC], 4);
    });
  });

  group('approx(비슷한 음식 값)', () {
    test('JSON의 approx=true만 비슷한 음식으로 읽고, 다른 값은 false', () {
      expect(sampleDb.match('라면')?.approx, isTrue);
      expect(sampleDb.match('삶은 계란')?.approx, isFalse);
      final odd = MicroNutrientDb.fromJson({
        'foods': [food('사과', 'apple', [], {}, approx: 'true'), food('배', 'pear', [], {}, approx: null)],
      });
      expect(odd.match('apple')?.approx, isFalse);
      expect(odd.match('pear')?.approx, isFalse);
    });

    test('합산에 들어간 approx 기록만 센다(미매칭·양 없음은 제외)', () {
      final s = summarizeMicroNutrients([
        entry('라면', 500),
        entry('ramyeon', 250),
        entry('라면', null),
        entry('삶은 계란', 50),
        entry('김치찌개', 300),
      ], sampleDb);
      expect(s.approxCount, 2);
      expect(s.matchedCount, 3);
      expect(s.totals[MicroNutrient.iron], closeTo(0.5 * 7.5 + 1.2 * 0.5, 1e-9));
    });

    test('approx 음식이 없으면 0', () {
      expect(summarizeMicroNutrients([entry('삶은 계란', 100)], sampleDb).approxCount, 0);
    });
  });

  group('summarizeMicroNutrients', () {
    test('(100g당 값 × 먹은 g ÷ 100)을 더한다', () {
      final s = summarizeMicroNutrients([
        entry('삶은 계란', 150),
        entry('닭가슴살', 200),
        entry('삶은달걀', 50),
      ], sampleDb);
      expect(s.foodEntryCount, 3);
      expect(s.unmatchedCount, 0);
      expect(s.totals[MicroNutrient.vitaminD], closeTo(2.2 * 2, 1e-9)); // 150g + 50g
      expect(s.totals[MicroNutrient.calcium], closeTo(100, 1e-9));
      expect(s.totals[MicroNutrient.zinc], closeTo(2.0, 1e-9));
      expect(s.totals[MicroNutrient.potassium], closeTo(500, 1e-9));
      expect(s.totals.containsKey(MicroNutrient.vitaminC), isFalse, reason: '어느 음식에도 값이 없음');
    });

    test('매칭 안 됨·먹은 양 없음은 합산에서 빼고 개수만 센다', () {
      final s = summarizeMicroNutrients([
        entry('김치찌개', 300),
        entry('Pechuga de pollo', 120),
        entry('닭가슴살', null),
        entry('닭가슴살', 0),
        entry('닭가슴살', 100),
      ], sampleDb);
      expect(s.foodEntryCount, 5);
      expect(s.unmatchedCount, 4);
      expect(s.matchedCount, 1);
      expect(s.totals[MicroNutrient.potassium], closeTo(250, 1e-9));
    });

    test('원본 값이 null인 영양소는 그 음식만 건너뛴다', () {
      final s = summarizeMicroNutrients([entry('명태', 100), entry('삶은 계란', 100)], sampleDb);
      expect(s.totals[MicroNutrient.vitaminD], closeTo(2.2, 1e-9));
      expect(s.totals[MicroNutrient.calcium], closeTo(70, 1e-9));
    });

    test('운동·물은 무시, 음식이 없으면 정보 없음', () {
      final s = summarizeMicroNutrients([
        entry('달리기', 30, type: LogType.exercise),
        entry('물', 250, type: LogType.water),
      ], sampleDb);
      expect(s.foodEntryCount, 0);
      expect(s.hasData, isFalse);
      expect(summarizeMicroNutrients([], sampleDb).hasData, isFalse);
    });

    test('모두 매칭 실패면 hasData=false', () {
      final s = summarizeMicroNutrients([entry('김치찌개', 300)], sampleDb);
      expect(s.hasData, isFalse);
      expect(s.unmatchedCount, 1);
    });
  });

  group('번들 데이터(assets/nutrition/micro_nutrients.json)', () {
    final json = jsonDecode(File('assets/nutrition/micro_nutrients.json').readAsStringSync()) as Map<String, Object?>;
    final db = MicroNutrientDb.fromJson(json);
    final foods = (json['foods'] as List).cast<Map<String, Object?>>();

    test('300개 이상, 모든 항목에 USDA 출처와 8개 키', () {
      expect(foods.length, greaterThanOrEqualTo(300));
      expect(db.size, foods.length);
      for (final f in foods) {
        expect(f['fdcId'], isA<int>());
        expect(['fndds', 'sr_legacy'], contains(f['source']));
        final per100g = f['per100g'] as Map;
        for (final n in MicroNutrient.values) {
          expect(per100g.containsKey(n.jsonKey), isTrue, reason: '${f['ko']} ${n.jsonKey}');
          final v = per100g[n.jsonKey];
          expect(v == null || (v is num && v >= 0), isTrue, reason: '${f['ko']} ${n.jsonKey}=$v');
        }
      }
    });

    test('각 음식의 한글명·영문명은 자기 자신으로 매칭된다(별칭 충돌 없음)', () {
      for (final f in foods) {
        expect(db.match(f['ko'] as String)?.nameKo, f['ko']);
        expect(db.match(f['en'] as String)?.nameKo, f['ko']);
      }
    });

    test('비슷한 음식으로 대신한 15개만 approx=true', () {
      const expected = {
        '라면', '돈까스', '탕수육', '김', '단무지', '볶음면', '군만두', '찐만두', //
        '족발', '밀크티', '단호박', '애호박', '대파', '볶음밥', '치킨',
      };
      for (final f in foods) {
        expect(f['approx'], isA<bool>(), reason: '${f['ko']}');
      }
      expect(foods.where((f) => f['approx'] == true).map((f) => f['ko']).toSet(), expected);
      for (final name in expected) {
        expect(db.match(name)?.approx, isTrue, reason: name);
      }
      expect(db.match('쌀밥')?.approx, isFalse);
    });

    test('흔한 음식 매칭', () {
      for (final name in ['밥', '김치', '계란', '우유', '닭가슴살', '두부', '시금치', '사과', '바나나', '라면', 'kimchi', 'Banana']) {
        expect(db.match(name), isNotNull, reason: name);
      }
    });
  });
}
