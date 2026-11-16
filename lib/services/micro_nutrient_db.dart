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

  /// USDA에 같은 음식이 없어 가장 가까운 항목(예: 라면 → ramen soup)의 값을 쓴 경우.
  final bool approx;

  const MicroNutrientFood({
    required this.nameKo,
    required this.nameEn,
    required this.per100g,
    this.approx = false,
  });
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

/// 부분 일치에 쓰는 DB 음식명의 최소 길이(정규화 후 글자 수). 1글자(밥·파·무·배·김 등)는
/// 다른 이름 속에 너무 쉽게 들어 있어 부분 일치에서는 쓰지 않는다(정확히 같을 때만 매칭).
const int microNutrientPartialMinLength = 2;

/// 국물 요리로 끝나는 이름은 부분 일치하지 않는다. "감자탕"→감자, "김치찌개"→김치처럼
/// 재료 하나의 100g당 값을 국물까지 포함한 무게에 곱하면 크게 부풀려지기 때문이다.
const List<String> _brothDishSuffixes = ['찌개', '전골', '국밥', '탕', '국', '수프', '스프', 'soup', 'stew', 'broth'];

/// [MicroNutrientDb.lookup] 결과. [partial]이면 이름 일부만 맞춘 것이라 비슷한 음식 값으로 본다.
class MicroNutrientMatch {
  final MicroNutrientFood food;
  final bool partial;

  const MicroNutrientMatch(this.food, {this.partial = false});

  /// 합산 시 "비슷한 음식 값" 안내 대상인지.
  bool get approx => partial || food.approx;
}

/// assets/nutrition/micro_nutrients.json을 읽어 음식명(한/영/별칭) → 영양소 값 색인을 만든다.
/// 매칭 순서: ① 정규화한 이름이 정확히 같음 → ② 괄호 내용을 뺀 이름이 같음 → ③ 부분 일치
/// (이름 안에 들어 있는 DB 음식명 중 가장 긴 것, 길이가 같으면 앞에 나온 것). ③은 approx로
/// 취급한다. 데이터 파일이 없거나 깨져 있어도 예외를 던지지 않고 빈 DB가 되어, 화면에는
/// "정보 없음"만 보인다.
class MicroNutrientDb {
  final Map<String, MicroNutrientFood> _index;

  /// 부분 일치 후보 키(길이 내림차순).
  final List<String> _partialKeys;

  MicroNutrientDb._(this._index)
      : _partialKeys = _index.keys.where((k) => k.length >= microNutrientPartialMinLength).toList()
          ..sort((a, b) => b.length.compareTo(a.length));

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
        approx: raw['approx'] == true,
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
  MicroNutrientFood? match(String foodName) => lookup(foodName)?.food;

  /// [match]와 같지만 부분 일치 여부까지 알려준다.
  MicroNutrientMatch? lookup(String foodName) {
    final normalized = normalizeFoodName(foodName);
    final exact = _index[normalized];
    if (exact != null) return MicroNutrientMatch(exact);
    final withoutBrackets = normalizeFoodNameWithoutBrackets(foodName);
    if (withoutBrackets.isEmpty) return null;
    final bracketless = _index[withoutBrackets];
    if (bracketless != null) return MicroNutrientMatch(bracketless);
    final partial = _longestContainedKey(withoutBrackets);
    return partial == null ? null : MicroNutrientMatch(_index[partial]!, partial: true);
  }

  String? _longestContainedKey(String name) {
    if (_brothDishSuffixes.any(name.endsWith)) return null;
    String? best;
    var bestPos = 0;
    for (final key in _partialKeys) {
      if (best != null && key.length < best.length) break;
      if (key.length >= name.length) continue; // 같은 길이면 이미 정확 일치에서 걸렀다.
      final pos = name.indexOf(key);
      if (pos < 0) continue;
      if (best == null || pos < bestPos) {
        best = key;
        bestPos = pos;
      }
    }
    return best;
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

  /// 합산에 들어간 기록 중 비슷한 음식 값으로 계산한 수([MicroNutrientMatch.approx]:
  /// approx 표시된 음식이거나 이름 일부만 맞춘 경우).
  final int approxCount;

  const MicroNutrientSummary({
    required this.totals,
    required this.foodEntryCount,
    required this.unmatchedCount,
    this.approxCount = 0,
  });

  int get matchedCount => foodEntryCount - unmatchedCount;
  bool get hasData => matchedCount > 0;
}

/// 음식 기록마다 (100g당 값 × 먹은 양 g ÷ 100)을 더한다. 운동·물 기록은 보지 않는다.
/// 매칭된 음식이라도 원본에 값이 없는(null) 영양소는 그 음식만 합산에서 빠진다.
MicroNutrientSummary summarizeMicroNutrients(Iterable<DailyLogEntry> entries, MicroNutrientDb db) {
  final totals = <MicroNutrient, double>{};
  var foodCount = 0;
  var unmatched = 0;
  var approx = 0;
  for (final e in entries) {
    if (e.type != LogType.food) continue;
    foodCount++;
    final grams = e.amount;
    final match = db.lookup(e.name);
    if (match == null || grams == null || grams <= 0 || !grams.isFinite) {
      unmatched++;
      continue;
    }
    final food = match.food;
    if (match.approx) approx++;
    for (final n in MicroNutrient.values) {
      final per100 = food.per100g[n];
      if (per100 == null) continue;
      totals[n] = (totals[n] ?? 0) + per100 * grams / 100;
    }
  }
  return MicroNutrientSummary(
    totals: totals,
    foodEntryCount: foodCount,
    unmatchedCount: unmatched,
    approxCount: approx,
  );
}
