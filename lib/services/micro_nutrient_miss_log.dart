import 'package:flutter/foundation.dart';

import '../models/daily_log_entry.dart';
import 'micro_nutrient_db.dart';

/// 비타민·미네랄 데이터에 매칭되지 않은 음식명을 세는 개발 확인용 카운터.
///
/// - 서버로 보내지 않는다. 디스크에도 쓰지 않고 앱이 떠 있는 동안 메모리에만 둔다
///   (SharedPreferences·앱 파일은 Android 자동 백업으로 기기 밖에 복사될 수 있어서).
/// - 같은 기록(id)은 화면을 다시 그려도 한 번만 센다.
/// - 디버그 빌드에서만 debugPrint로 상위 항목을 남긴다. 사전·별칭을 늘릴 때 참고용이다.
class MicroNutrientMissLog {
  MicroNutrientMissLog._();
  static final MicroNutrientMissLog instance = MicroNutrientMissLog._();

  /// 기억해 둘 이름 수 상한(넘으면 적게 나온 것부터 버린다).
  static const int maxNames = 200;

  /// 중복 집계 방지용으로 기억할 기록 id 수 상한.
  static const int maxSeenIds = 2000;

  final Map<String, int> _counts = {};
  final Set<int> _seenIds = {};

  /// 이름별 매칭 실패 횟수(많은 순).
  List<MapEntry<String, int>> get topMisses =>
      _counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

  int countOf(String name) => _counts[name.trim()] ?? 0;

  /// [summary]의 이름 매칭 실패 기록을 센다. 새로 센 기록 수를 돌려준다.
  int record(MicroNutrientSummary summary) {
    var added = 0;
    for (final e in summary.nameMissEntries) {
      final id = e.id;
      if (id == null || !_seenIds.add(id)) continue;
      final name = e.name.trim();
      if (name.isEmpty) continue;
      _counts[name] = (_counts[name] ?? 0) + 1;
      added++;
    }
    if (_seenIds.length > maxSeenIds) {
      _seenIds.removeAll(_seenIds.take(_seenIds.length - maxSeenIds).toList());
    }
    if (_counts.length > maxNames) {
      final keep = topMisses.take(maxNames).map((e) => e.key).toSet();
      _counts.removeWhere((name, _) => !keep.contains(name));
    }
    if (added > 0 && kDebugMode) {
      final top = topMisses.take(10).map((e) => '${e.key}×${e.value}').join(', ');
      debugPrint('[micro-nutrient] 매칭 실패 +$added (누적 ${_counts.length}종): $top');
    }
    return added;
  }

  @visibleForTesting
  void clear() {
    _counts.clear();
    _seenIds.clear();
  }
}

/// 테스트용: 기록 목록으로 바로 집계한다.
@visibleForTesting
int recordMissesFromEntries(Iterable<DailyLogEntry> entries, MicroNutrientDb db) =>
    MicroNutrientMissLog.instance.record(summarizeMicroNutrients(entries, db));
