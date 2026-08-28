import '../db/database_helper.dart';
import '../models/food_db_item.dart';

/// "직접입력" 화면 자동완성용 로컬 한식 음식 DB 검색.
class FoodDbService {
  FoodDbService._internal();
  static final FoodDbService instance = FoodDbService._internal();

  /// 최종적으로 사용자에게 보여줄 결과 개수.
  static const int _maxResults = 15;

  /// SQL에서 미리 가져올 원본 후보 개수. "피자"처럼 흔한 검색어는 수천 건까지
  /// 매칭될 수 있어(식약처 DB 특성상 이름이 "{카테고리} {상품명}"으로 시작),
  /// 이후 사이즈/변형 그룹핑 + 상위 [_maxResults]개 자르기 전 단계에서 넉넉히 확보한다.
  static const int _rawCandidateLimit = 300;

  /// 이름 끝에 붙는 사이즈/변형 표기(괄호, 예: " (L)", " (R)", " (G)")를 제거하기 위한 패턴.
  /// 괄호 안 내용 길이를 짧게 제한해(4자 이하) 정말 부가적인 사이즈 코드만 걸러내고,
  /// "찌개 (돼지고기 400g)"처럼 긴 설명이 붙은 괄호는 건드리지 않는다.
  static final RegExp _sizeVariantSuffix = RegExp(r'\s*\([^()]{1,4}\)\s*$');

  /// [query]로 food_search_terms를 LIKE 검색해 우선 매칭하고, 결과가 없으면
  /// food_search_fts(FTS5)로 폴백 검색한다. 두 방식 모두 SQL 단계에서 이름이 검색어와
  /// 정확히 일치 > 검색어로 시작 > 그 외(포함) 순으로 정렬해 가져온 뒤, 이름 끝의
  /// 사이즈/변형 표기만 다른 항목들을 하나로 묶어 그룹당 대표 1건만 상위
  /// [_maxResults]개까지 반환한다.
  Future<List<FoodDbItem>> searchFood(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return [];

    final db = await DatabaseHelper.instance.database;
    final containsPattern = '%$trimmed%';
    final prefixPattern = '$trimmed%';

    var rows = await db.rawQuery(
      '''
      SELECT DISTINCT f.*
      FROM food_search_terms t
      JOIN food_db f ON f.id = t.food_id
      WHERE t.term LIKE ?1
      ORDER BY
        CASE
          WHEN f.name_ko = ?2 THEN 0
          WHEN f.name_ko LIKE ?3 THEN 1
          ELSE 2
        END,
        f.name_ko
      LIMIT ?4
      ''',
      [containsPattern, trimmed, prefixPattern, _rawCandidateLimit],
    );

    if (rows.isEmpty) {
      try {
        final matchQuery = _buildFtsPrefixQuery(trimmed);
        if (matchQuery.isEmpty) return [];
        rows = await db.rawQuery(
          '''
          SELECT DISTINCT f.*
          FROM food_search_fts s
          JOIN food_db f ON f.id = s.food_id
          WHERE food_search_fts MATCH ?1
          ORDER BY
            CASE
              WHEN f.name_ko = ?2 THEN 0
              WHEN f.name_ko LIKE ?3 THEN 1
              ELSE 2
            END,
            f.name_ko
          LIMIT ?4
          ''',
          [matchQuery, trimmed, prefixPattern, _rawCandidateLimit],
        );
      } catch (_) {
        // food_search_fts가 없는 기기(FTS5 미지원)에서는 LIKE 검색 결과 없음 = 최종 결과 없음.
        return [];
      }
    }
    if (rows.isEmpty) return [];

    final items = rows.map((r) => FoodDbItem.fromMap(r)).toList();
    final grouped = _dedupeSizeVariants(items);
    return grouped.take(_maxResults).toList();
  }

  /// 이름 끝의 사이즈/변형 표기만 다른 항목들을 "기본 이름" 기준으로 묶어, 그룹당
  /// 대표 1건만 남긴다. SQL에서 이미 관련도 순으로 정렬해 왔으므로, 그룹의 위치는
  /// 그 그룹에서 가장 먼저(=가장 관련도 높게) 등장한 항목의 순서를 그대로 따른다.
  List<FoodDbItem> _dedupeSizeVariants(List<FoodDbItem> items) {
    final groups = <String, List<FoodDbItem>>{};
    final order = <String>[];
    for (final item in items) {
      final base = _baseName(item.nameKo);
      if (!groups.containsKey(base)) order.add(base);
      groups.putIfAbsent(base, () => []).add(item);
    }
    return [for (final base in order) _pickRepresentative(groups[base]!)];
  }

  /// 그룹 내 대표 항목: 칼로리가 그룹 평균에 가장 가까운 항목(동률이면 먼저 나온 항목).
  FoodDbItem _pickRepresentative(List<FoodDbItem> group) {
    if (group.length == 1) return group.first;
    final avgCalories = group.map((e) => e.calories).reduce((a, b) => a + b) / group.length;
    var best = group.first;
    var bestDiff = (best.calories - avgCalories).abs();
    for (final item in group.skip(1)) {
      final diff = (item.calories - avgCalories).abs();
      if (diff < bestDiff) {
        best = item;
        bestDiff = diff;
      }
    }
    return best;
  }

  /// 끝에 붙은 사이즈/변형 괄호 표기를 반복 제거한 "기본 이름"(공백 정리 포함).
  String _baseName(String nameKo) {
    var base = nameKo.trim();
    var previous = '';
    while (previous != base) {
      previous = base;
      base = base.replaceFirst(_sizeVariantSuffix, '').trim();
    }
    return base;
  }

  /// 공백으로 나눈 각 토큰에 접두 매칭(`"토큰"*`)을 걸고 공백(암묵적 AND)으로 합친다.
  /// 토큰 내 따옴표는 이스케이프(`""`)해 FTS5 쿼리 문법을 깨지 않도록 한다.
  String _buildFtsPrefixQuery(String input) {
    final tokens = input.split(RegExp(r'\s+')).where((t) => t.isNotEmpty);
    return tokens.map((t) => '"${t.replaceAll('"', '""')}"*').join(' ');
  }
}
