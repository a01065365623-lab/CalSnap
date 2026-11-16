import 'dart:convert';
import 'dart:io';

import 'package:calsnap/models/daily_log_entry.dart';
import 'package:calsnap/models/micro_nutrient.dart';
import 'package:calsnap/services/micro_nutrient_db.dart';
import 'package:flutter_test/flutter_test.dart';

final db = MicroNutrientDb.fromJson(jsonDecode(File('assets/nutrition/micro_nutrients.json').readAsStringSync()));

DailyLogEntry meal(String name, double grams) => DailyLogEntry(
      datetime: DateTime(2026, 11, 16, 12),
      type: LogType.food,
      name: name,
      calories: 300,
      amount: grams,
    );

void main() {
  group('부분 일치', () {
    test('이름 안에 DB 음식명이 들어 있으면 매칭하고 approx로 본다', () {
      final m = db.lookup('야채 비빔밥')!;
      expect(m.food.nameKo, '비빔밥');
      expect(m.partial, isTrue);
      expect(m.approx, isTrue);

      final en = db.lookup('Grilled chicken breast with herbs')!;
      expect(en.food.nameKo, '닭가슴살');
      expect(en.partial, isTrue);
    });

    test('정확히 같으면 부분 일치가 아니다', () {
      final m = db.lookup('비빔밥')!;
      expect(m.partial, isFalse);
      expect(m.approx, isFalse);
      expect(db.lookup('닭가슴살 (100g)')!.partial, isFalse, reason: '괄호 내용만 다른 건 정확 일치');
    });

    test('가장 긴 일치어 우선', () {
      expect(db.lookup('삶은계란 샐러드')!.food.nameKo, '삶은 계란', reason: '"계란"보다 "삶은계란"이 길다');
      expect(db.lookup('그릭요거트 볼')!.food.nameKo, '그릭요거트', reason: '"요거트"보다 길다');
      expect(db.lookup('딸기우유 한 팩')!.food.nameKo, '딸기우유', reason: '"우유"보다 길다');
    });

    test('길이가 같으면 이름 앞쪽에 나온 것', () {
      expect(db.lookup('Eggplant parmesan')!.food.nameKo, '가지', reason: 'eggplant·parmesan 둘 다 8자');
    });

    test('1글자 음식명은 부분 일치에 쓰지 않는다', () {
      for (final name in ['파전', '무생채', '김말이', '밤양갱', '배숙']) {
        expect(db.lookup(name), isNull, reason: name);
      }
      expect(db.lookup('배추전')!.food.nameKo, '배추', reason: '2글자 "배추"는 쓴다');
    });

    test('국물 요리는 재료 하나로 부분 일치하지 않는다', () {
      for (final name in ['감자탕', '김치찌개', '된장국', '돼지고기 김치찌개', '부대찌개', '순두부찌개', '소고기 국밥', 'Potato stew', 'Tofu soup']) {
        expect(db.lookup(name), isNull, reason: name);
      }
      expect(db.lookup('미역국')!.partial, isFalse, reason: '정확히 있는 국은 그대로');
    });

    test('오매칭 방지: "닭가슴살 샐러드"는 닭가슴살로(시저샐러드·소고기 등 엉뚱한 음식 아님)', () {
      final m = db.lookup('닭가슴살 샐러드')!;
      expect(m.food.nameKo, '닭가슴살');
      expect(m.approx, isTrue);
      expect(db.lookup('chicken breast salad')!.food.nameKo, '닭가슴살');
    });

    test('다른 언어·관련 없는 이름은 여전히 매칭 실패', () {
      for (final name in ['Pechuga de pollo', '鶏むね肉', 'صدر دجاج', 'Куриная грудка', '🍗', 'x' * 5000]) {
        expect(db.lookup(name), isNull, reason: name);
      }
    });
  });

  test('부분 일치로 합산된 기록은 approxCount에 들어간다', () {
    final s = summarizeMicroNutrients([meal('비빔밥', 400), meal('야채 비빔밥', 400), meal('감자탕', 500)], db);
    expect(s.matchedCount, 2);
    expect(s.unmatchedCount, 1);
    expect(s.approxCount, 1);
    final perGram = db.match('비빔밥')!.per100g[MicroNutrient.iron]! / 100;
    expect(s.totals[MicroNutrient.iron], closeTo(perGram * 800, 1e-9));
  });
}
