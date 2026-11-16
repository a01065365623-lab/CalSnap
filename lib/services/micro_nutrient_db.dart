import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/daily_log_entry.dart';
import '../models/micro_nutrient.dart';

/// 비타민·미네랄 DB의 음식 한 건(100g당 값). 원본(USDA)에 값이 없는 영양소는 null이다.
class MicroNutrientFood {
  final String nameKo;
  final String nameEn;
  final Map<MicroNutrient, double?> per100g;

  const MicroNutrientFood({required this.nameKo, required this.nameEn, required this.per100g});
}

/// 음식명 비교용 정규화: 소문자로 바꾸고 공백·괄호 문자·흔한 구분 기호를 없앤다.
/// 예) "삶은 계란", "삶은계란", "Hard-Boiled Egg" → "삶은계란", "hardboiledegg".
String normalizeFoodName(String name) {
  return name.toLowerCase().replaceAll(RegExp(r'[\s()\[\]{}（）［］【】<>·・,._\-/~!?:;"' "'" r']'), '');
}

/// 괄호 안의 내용까지 없앤 정규화. "닭가슴살(100g)", "Banana (ripe)"처럼 꾸밈말이 붙은
/// 이름을 두 번째 시도로 맞춰 보는 데 쓴다.
String normalizeFoodNameWithoutBrackets(String name) {
  return normalizeFoodName(name.replaceAll(RegExp(r'[(\[{（［【][^)\]}）］】]*[)\]}）］】]'), ''));
}

/// assets/nutrition/micro_nutrients.json을 읽어 음식명(한/영/별칭) → 영양소 값 색인을 만든다.
/// 음식명은 정규화한 문자열이 정확히 같을 때만 매칭한다(부분 일치는 엉뚱한 음식에 붙을
/// 위험이 커서 하지 않는다). 데이터 파일이 없거나 깨져 있어도 예외를 던지지 않고 빈 DB가
/// 되어, 화면에는 "정보 없음"만 보인다.
class MicroNutrientDb {
  final Map<String, MicroNutrientFood> _index;

  MicroNutrientDb._(this._index);

  static final MicroNutrientDb empty = MicroNutrientDb._(const {});

  int get size => _index.values.toSet().length;

  factory MicroNutrientDb.fromJson(Object? json) {
    final index = <String, MicroNutrientFood>{};
    final foods = json is Map ? json['foods'] : null;
    if (foods is! List) return MicroNutrientDb._(index);
    for (final raw in foods) {
      if (raw is! Map) continue;
      final ko = raw['ko'];
      final en = raw['en'];
      final per100g = raw['per100g'];
      if (ko is! String || en is! String || per100g is! Map) continue;
      final food = MicroNutrientFood(
        nameKo: ko,
        nameEn: en,
        per100g: {
          for (final n in MicroNutrient.values)
            n: per100g[n.jsonKey] is num ? (per100g[n.jsonKey] as num).toDouble() : null,
        },
      );
      final aliases = raw['aliases'] is List ? (raw['aliases'] as List).whereType<String>() : const <String>[];
      for (final name in [ko, en, ...aliases]) {
        final key = normalizeFoodName(name);
        if (key.isNotEmpty) index.putIfAbsent(key, () => food);
      }
    }
    return MicroNutrientDb._(index);
  }

  /// 기록된 음식명으로 찾는다. 못 찾으면 null(예외 없음).
  MicroNutrientFood? match(String foodName) {
    final exact = _index[normalizeFoodName(foodName)];
    if (exact != null) return exact;
    final key = normalizeFoodNameWithoutBrackets(foodName);
    return key.isEmpty ? null : _index[key];
  }

  static Future<MicroNutrientDb>? _loading;

  /// 앱 번들의 데이터를 한 번만 읽어 캐시한다. 읽기·파싱에 실패하면 빈 DB.
  static Future<MicroNutrientDb> load({AssetBundle? bundle}) {
    return _loading ??= () async {
      try {
        final raw = await (bundle ?? rootBundle).loadString('assets/nutrition/micro_nutrients.json');
        return MicroNutrientDb.fromJson(jsonDecode(raw));
      } catch (e) {
        debugPrint('micro_nutrients.json load failed: $e');
        return empty;
      }
    }();
  }

  @visibleForTesting
  static void resetCacheForTest() => _loading = null;
}

/// 하루치 비타민·미네랄 합산 결과.
class MicroNutrientSummary {
  /// 영양소별 합계. 매칭된 음식이 하나도 없으면 비어 있다(= "정보 없음").
  final Map<MicroNutrient, double> totals;

  /// 그날 음식 기록 수.
  final int foodEntryCount;

  /// 영양 정보를 못 붙인 음식 기록 수(음식명이 매칭되지 않았거나, 먹은 양(g)이 없는 기록).
  final int unmatchedCount;

  const MicroNutrientSummary({required this.totals, required this.foodEntryCount, required this.unmatchedCount});

  int get matchedCount => foodEntryCount - unmatchedCount;
  bool get hasData => matchedCount > 0;
}

/// 음식 기록마다 (100g당 값 × 먹은 양 g ÷ 100)을 더한다. 운동·물 기록은 보지 않는다.
/// 매칭된 음식이라도 원본에 값이 없는(null) 영양소는 그 음식만 합산에서 빠진다.
MicroNutrientSummary summarizeMicroNutrients(Iterable<DailyLogEntry> entries, MicroNutrientDb db) {
  final totals = <MicroNutrient, double>{};
  var foodCount = 0;
  var unmatched = 0;
  for (final e in entries) {
    if (e.type != LogType.food) continue;
    foodCount++;
    final grams = e.amount;
    final food = db.match(e.name);
    if (food == null || grams == null || grams <= 0 || !grams.isFinite) {
      unmatched++;
      continue;
    }
    for (final n in MicroNutrient.values) {
      final per100 = food.per100g[n];
      if (per100 == null) continue;
      totals[n] = (totals[n] ?? 0) + per100 * grams / 100;
    }
  }
  return MicroNutrientSummary(totals: totals, foodEntryCount: foodCount, unmatchedCount: unmatched);
}
