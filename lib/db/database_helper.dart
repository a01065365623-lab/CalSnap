import 'dart:convert';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/daily_log_entry.dart';
import '../models/food_db_item.dart';

/// assets/food_db_seed.json(19,495건, 약 8MB) 파싱은 CPU 바운드 작업이라 메인 isolate에서
/// 돌리면 첫 실행 시 UI가 잠깐 멈출 수 있다. compute()로 별도 isolate에서 실행하기 위해
/// 최상위 함수로 뺐다(compute 콜백은 top-level/static 함수여야 함).
List<Map<String, dynamic>> _parseFoodDbSeedJson(String raw) {
  final decoded = jsonDecode(raw) as List<dynamic>;
  return decoded.cast<Map<String, dynamic>>();
}

class DatabaseHelper {
  DatabaseHelper._internal();
  static final DatabaseHelper instance = DatabaseHelper._internal();

  /// assets/food_db_seed.json 내용이 바뀌면 이 값을 올려서 재시딩을 트리거한다.
  /// v2: 식약처 공식 데이터 19,495건으로 전체 교체. v3: seed 파일 갱신본으로 재교체.
  static const String _foodDbSeedVersion = '3';

  /// 배치 하나에 담을 최대 SQL 작업 수. 19,495건 전체를 배치 하나에 담으면 플랫폼
  /// 채널 페이로드가 지나치게 커지므로, 이 크기로 잘라 여러 배치로 나눠 commit한다.
  /// (트랜잭션 자체는 [_seedFoodDbIfNeeded]에서 db.transaction으로 하나로 묶어 원자성은 유지)
  static const int _seedBatchOpThreshold = 3000;

  Database? _db;

  Future<Database> get database async {
    _db ??= await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'calsnap.db');
    final db = await openDatabase(
      path,
      version: 6,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE daily_log (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            datetime TEXT NOT NULL,
            type TEXT NOT NULL,
            name TEXT NOT NULL,
            calories REAL NOT NULL,
            amount REAL,
            mode TEXT,
            carbsG REAL,
            proteinG REAL,
            fatG REAL,
            source TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE daily_summary (
            date TEXT PRIMARY KEY,
            total_intake REAL DEFAULT 0,
            total_burned REAL DEFAULT 0,
            net_calories REAL DEFAULT 0
          )
        ''');
        await db.execute('''
          CREATE TABLE weight_log (
            date TEXT PRIMARY KEY,
            weight_kg REAL NOT NULL,
            photo_path TEXT
          )
        ''');
        await _createFoodDbTables(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          // 기존 행은 세 컬럼 모두 NULL로 채워지고, log_entry_tile/일일 영양소 집계에서
          // null을 0으로 취급한다.
          await db.execute('ALTER TABLE daily_log ADD COLUMN carbsG REAL');
          await db.execute('ALTER TABLE daily_log ADD COLUMN proteinG REAL');
          await db.execute('ALTER TABLE daily_log ADD COLUMN fatG REAL');
        }
        if (oldVersion < 3) {
          // 온보딩/프로필 체중(user_profile_service)과는 별개로, 날짜별 체중 추이를
          // 기록하기 위한 테이블. 날짜당 하나만 유지한다(같은 날 재기록 시 덮어씀).
          await db.execute('''
            CREATE TABLE weight_log (
              date TEXT PRIMARY KEY,
              weight_kg REAL NOT NULL
            )
          ''');
        }
        if (oldVersion < 4) {
          // 빠른측정모드 "직접 입력" 경로 추가: 사진 기반(photo)인지 사진 없이
          // 직접 입력(manual)했는지 구분한다. 기존 행은 전부 NULL로 남고,
          // log_entry_tile은 null을 "구분 표시 없음(과거 기록)"으로 취급한다.
          await db.execute('ALTER TABLE daily_log ADD COLUMN source TEXT');
        }
        if (oldVersion < 5) {
          // "직접입력" 모드 자동완성용 로컬 한식 음식 DB(food_db) + 검색 인덱스
          // (food_search_terms LIKE 검색, food_search_fts FTS5 폴백) 추가.
          await _createFoodDbTables(db);
        }
        if (oldVersion < 6) {
          // 체중 기록에 사진(전/후 비교용)을 함께 저장할 수 있도록 컬럼 추가.
          // 기존 행은 전부 NULL.
          await db.execute('ALTER TABLE weight_log ADD COLUMN photo_path TEXT');
        }
      },
    );
    await _seedFoodDbIfNeeded(db);
    return db;
  }

  Future<void> _createFoodDbTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS food_db (
        id TEXT PRIMARY KEY,
        name_ko TEXT NOT NULL,
        name_en TEXT,
        country TEXT,
        category TEXT,
        serving_size_g REAL,
        calories REAL,
        carbs_g REAL,
        protein_g REAL,
        fat_g REAL,
        sodium_mg REAL,
        main_ingredients TEXT,
        image_url TEXT,
        ai_recognized_name TEXT,
        created_at TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS food_search_terms (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        food_id TEXT NOT NULL,
        term TEXT NOT NULL,
        FOREIGN KEY (food_id) REFERENCES food_db (id)
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_food_search_terms_term ON food_search_terms (term)',
    );
    await db.execute('''
      CREATE TABLE IF NOT EXISTS food_db_meta (
        key TEXT PRIMARY KEY,
        value TEXT
      )
    ''');
    // 일부 구형 기기의 시스템 SQLite에는 FTS5가 빠져 있을 수 있어, 실패해도 앱 구동
    // 자체는 막지 않는다(검색은 food_search_terms LIKE 매칭만으로도 동작).
    try {
      await db.execute(
        'CREATE VIRTUAL TABLE IF NOT EXISTS food_search_fts USING fts5(food_id UNINDEXED, term)',
      );
    } catch (_) {
      // FTS5 미지원 기기: fallback 검색만 비활성화되고 나머지는 정상 동작.
    }
  }

  /// assets/food_db_seed.json(19,495건)을 읽어 food_db/food_search_terms/food_search_fts를
  /// 채운다. food_db_meta.seed_version이 이미 [_foodDbSeedVersion]과 같으면 재실행하지 않는다.
  ///
  /// 건별 개별 트랜잭션은 19,495건 규모에서 매우 느려지므로, 전체를 db.transaction()
  /// 하나로 묶어 원자적으로 처리한다. 다만 배치 하나에 전체(약 12만 건의 INSERT)를 담으면
  /// 플랫폼 채널 페이로드가 지나치게 커져 오히려 느려지고 메모리를 많이 먹으므로,
  /// [_seedBatchOpThreshold]건마다 잘라 여러 배치로 나눠 commit한다(트랜잭션은 유지).
  Future<void> _seedFoodDbIfNeeded(Database db) async {
    final metaRows = await db.query(
      'food_db_meta',
      where: 'key = ?',
      whereArgs: ['seed_version'],
    );
    if (metaRows.isNotEmpty && metaRows.first['value'] == _foodDbSeedVersion) {
      return;
    }

    final stopwatch = Stopwatch()..start();

    final raw = await rootBundle.loadString('assets/food_db_seed.json');
    // JSON 디코딩(8MB, 19,495건)은 CPU 바운드라 메인 isolate를 막을 수 있어 별도
    // isolate(compute)에서 처리한다.
    final items = await compute(_parseFoodDbSeedJson, raw);

    // 일부 구형 기기는 시스템 SQLite에 FTS5가 없어 food_search_fts 테이블 생성 자체가
    // 실패할 수 있다(_createFoodDbTables 참고) — 그런 기기에서는 fts 관련 배치 명령을
    // 아예 큐에 넣지 않는다.
    final ftsExists = (await db.query(
      'sqlite_master',
      where: "type = 'table' AND name = 'food_search_fts'",
    ))
        .isNotEmpty;

    await db.transaction((txn) async {
      final clearBatch = txn.batch();
      clearBatch.delete('food_search_terms');
      clearBatch.delete('food_db');
      if (ftsExists) clearBatch.delete('food_search_fts');
      await clearBatch.commit(noResult: true);

      var batch = txn.batch();
      var opsInBatch = 0;

      Future<void> flushIfNeeded() async {
        if (opsInBatch < _seedBatchOpThreshold) return;
        await batch.commit(noResult: true);
        batch = txn.batch();
        opsInBatch = 0;
      }

      for (final map in items) {
        final food = FoodDbItem.fromSeedJson(map);
        batch.insert('food_db', food.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
        opsInBatch++;

        final terms = (map['search_terms'] as List<dynamic>? ?? [])
            .map((t) => t.toString())
            .toSet()
          ..add(food.nameKo)
          ..addAll(food.nameEn != null && food.nameEn!.isNotEmpty ? [food.nameEn!] : []);
        for (final term in terms) {
          batch.insert('food_search_terms', {'food_id': food.id, 'term': term});
          opsInBatch++;
          if (ftsExists) {
            batch.insert('food_search_fts', {'food_id': food.id, 'term': term});
            opsInBatch++;
          }
        }
        await flushIfNeeded();
      }
      if (opsInBatch > 0) {
        await batch.commit(noResult: true);
      }

      await txn.insert(
        'food_db_meta',
        {'key': 'seed_version', 'value': _foodDbSeedVersion},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });

    stopwatch.stop();
    // ignore: avoid_print
    print('시딩 완료: ${stopwatch.elapsedMilliseconds}ms (${items.length}건)');
  }

  /// 식사·운동·물, 요약, 체중 기록을 전부 삭제한다. 시크릿 모드 "비밀번호를 잊으셨나요?"
  /// 초기화 흐름과 설정 화면의 "전체 초기화" 버튼 전용 — 스키마는 그대로 두고 데이터만
  /// 비운다. weight_log.photo_path가 가리키던 실제 이미지 파일은 여기서 지우지 않으므로
  /// (파일 시스템은 DatabaseHelper의 책임이 아님), 호출부에서
  /// WeightPhotoService.deleteAllPhotos()를 함께 호출해야 한다.
  Future<void> resetAllData() async {
    final db = await database;
    await db.delete('daily_log');
    await db.delete('daily_summary');
    await db.delete('weight_log');
  }

  // ── daily_log ──────────────────────────────────────────

  Future<int> insertLog(DailyLogEntry entry) async {
    final db = await database;
    final id = await db.insert('daily_log', entry.toMap()..remove('id'));
    await _refreshDailySummary(_dateKey(entry.datetime));
    return id;
  }

  Future<List<DailyLogEntry>> getLogsForDate(DateTime date) async {
    final db = await database;
    final key = _dateKey(date);
    final rows = await db.query(
      'daily_log',
      where: "datetime LIKE ?",
      whereArgs: ['$key%'],
      orderBy: 'datetime ASC',
    );
    return rows.map((r) => DailyLogEntry.fromMap(r)).toList();
  }

  Future<void> deleteLog(int id, DateTime date) async {
    final db = await database;
    await db.delete('daily_log', where: 'id = ?', whereArgs: [id]);
    await _refreshDailySummary(_dateKey(date));
  }

  /// 해당 날짜의 로그를 전부 삭제한다("오늘 기록 전체 초기화" 등). 삭제 후
  /// daily_summary도 그 날짜 기준으로 다시 계산되어 0으로 갱신된다.
  Future<int> deleteLogsForDate(DateTime date) async {
    final db = await database;
    final key = _dateKey(date);
    final count = await db.delete('daily_log', where: 'datetime LIKE ?', whereArgs: ['$key%']);
    await _refreshDailySummary(key);
    return count;
  }

  /// 여러 건을 한 번에 삽입한다 (트랜잭션 배치 + 날짜별 요약 1회씩만 갱신).
  /// 대량 시드 데이터처럼 insertLog를 건마다 호출하기엔 비효율적인 경우에 사용.
  Future<void> insertLogsBulk(List<DailyLogEntry> entries) async {
    if (entries.isEmpty) return;
    final db = await database;
    final batch = db.batch();
    for (final entry in entries) {
      batch.insert('daily_log', entry.toMap()..remove('id'));
    }
    await batch.commit(noResult: true);

    final dateKeys = entries.map((e) => _dateKey(e.datetime)).toSet();
    for (final key in dateKeys) {
      await _refreshDailySummary(key);
    }
  }

  /// 여러 날짜에 걸친 원본 로그 목록을 조회한다 (daily_summary 집계가 아닌 개별 항목).
  Future<List<DailyLogEntry>> getLogsForRange(DateTime from, DateTime to) async {
    final db = await database;
    final rows = await db.query(
      'daily_log',
      where: 'substr(datetime, 1, 10) >= ? AND substr(datetime, 1, 10) <= ?',
      whereArgs: [_dateKey(from), _dateKey(to)],
      orderBy: 'datetime ASC',
    );
    return rows.map((r) => DailyLogEntry.fromMap(r)).toList();
  }

  /// name이 주어진 접두사로 시작하는 로그를 모두 삭제한다 (시드 데이터 정리용).
  Future<int> deleteLogsWhereNameStartsWith(String prefix) async {
    final db = await database;
    final rows = await db.query(
      'daily_log',
      columns: ['id', 'datetime'],
      where: 'name LIKE ?',
      whereArgs: ['$prefix%'],
    );
    if (rows.isEmpty) return 0;

    final ids = rows.map((r) => r['id'] as int).toList();
    await db.delete(
      'daily_log',
      where: 'id IN (${List.filled(ids.length, '?').join(',')})',
      whereArgs: ids,
    );

    final dateKeys = rows.map((r) => _dateKey(DateTime.parse(r['datetime'] as String))).toSet();
    for (final key in dateKeys) {
      await _refreshDailySummary(key);
    }
    return ids.length;
  }

  // ── daily_summary ──────────────────────────────────────

  Future<void> _refreshDailySummary(String dateKey) async {
    final db = await database;
    final rows = await db.query(
      'daily_log',
      where: "datetime LIKE ?",
      whereArgs: ['$dateKey%'],
    );

    double intake = 0;
    double burned = 0;
    for (final r in rows) {
      final cal = (r['calories'] as num).toDouble();
      if (cal >= 0) {
        intake += cal;
      } else {
        burned += cal.abs();
      }
    }

    await db.insert(
      'daily_summary',
      {
        'date': dateKey,
        'total_intake': intake,
        'total_burned': burned,
        'net_calories': intake - burned,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<DailySummary?> getSummary(DateTime date) async {
    final db = await database;
    final key = _dateKey(date);
    final rows = await db.query('daily_summary', where: 'date = ?', whereArgs: [key]);
    if (rows.isEmpty) return null;
    final r = rows.first;
    return DailySummary(
      date: r['date'] as String,
      totalIntake: (r['total_intake'] as num).toDouble(),
      totalBurned: (r['total_burned'] as num).toDouble(),
    );
  }

  Future<List<DailySummary>> getSummaryRange(DateTime from, DateTime to) async {
    final db = await database;
    final rows = await db.query(
      'daily_summary',
      where: 'date >= ? AND date <= ?',
      whereArgs: [_dateKey(from), _dateKey(to)],
      orderBy: 'date ASC',
    );
    return rows
        .map((r) => DailySummary(
              date: r['date'] as String,
              totalIntake: (r['total_intake'] as num).toDouble(),
              totalBurned: (r['total_burned'] as num).toDouble(),
            ))
        .toList();
  }

  /// 기간 내 운동(LogType.exercise) 기록만 날짜별로 집계한다(칼로리는 절댓값,
  /// 시간은 amount 합). 운동 기록이 없는 날짜는 결과에서 생략되므로, 통계 화면처럼
  /// 빈 날짜를 0으로 채워야 하는 호출부에서 직접 채워 넣어야 한다.
  Future<List<ExerciseSummary>> getExerciseSummaryRange(DateTime from, DateTime to) async {
    final db = await database;
    final rows = await db.rawQuery(
      '''
      SELECT substr(datetime, 1, 10) AS date,
             SUM(-calories) AS caloriesBurned,
             SUM(COALESCE(amount, 0)) AS minutes
      FROM daily_log
      WHERE type = ? AND substr(datetime, 1, 10) >= ? AND substr(datetime, 1, 10) <= ?
      GROUP BY date
      ORDER BY date ASC
      ''',
      [LogType.exercise.name, _dateKey(from), _dateKey(to)],
    );
    return rows
        .map((r) => ExerciseSummary(
              date: r['date'] as String,
              caloriesBurned: (r['caloriesBurned'] as num).toDouble(),
              minutes: (r['minutes'] as num).toDouble(),
            ))
        .toList();
  }

  /// 기간 내 음식(LogType.food) 기록의 탄단지(g)를 날짜별로 합산한다. 음식 기록이
  /// 없는 날짜는 결과에서 생략된다.
  Future<List<NutrientSummary>> getNutrientSummaryRange(DateTime from, DateTime to) async {
    final db = await database;
    final rows = await db.rawQuery(
      '''
      SELECT substr(datetime, 1, 10) AS date,
             SUM(COALESCE(carbsG, 0)) AS carbsG,
             SUM(COALESCE(proteinG, 0)) AS proteinG,
             SUM(COALESCE(fatG, 0)) AS fatG
      FROM daily_log
      WHERE type = ? AND substr(datetime, 1, 10) >= ? AND substr(datetime, 1, 10) <= ?
      GROUP BY date
      ORDER BY date ASC
      ''',
      [LogType.food.name, _dateKey(from), _dateKey(to)],
    );
    return rows
        .map((r) => NutrientSummary(
              date: r['date'] as String,
              carbsG: (r['carbsG'] as num).toDouble(),
              proteinG: (r['proteinG'] as num).toDouble(),
              fatG: (r['fatG'] as num).toDouble(),
            ))
        .toList();
  }

  /// [date]부터 과거로 거슬러 올라가며 하루도 빠짐없이 기록(daily_log)이 있는 연속
  /// 일수를 센다. 최대 [maxDays]일까지만 확인한다(스트릭 표시 목적상 그 이상은
  /// 의미가 크지 않고 쿼리 비용만 커진다). daily_summary가 아닌 daily_log를 직접
  /// 보는 이유: 하루의 기록을 전부 삭제해도 daily_summary 행 자체는 0으로 남아있어
  /// "기록한 날"로 잘못 셀 수 있기 때문이다.
  Future<int> getStreakDaysEndingOn(DateTime date, {int maxDays = 60}) async {
    final db = await database;
    final from = date.subtract(Duration(days: maxDays - 1));
    final rows = await db.rawQuery(
      '''
      SELECT DISTINCT substr(datetime, 1, 10) AS date
      FROM daily_log
      WHERE substr(datetime, 1, 10) >= ? AND substr(datetime, 1, 10) <= ?
      ''',
      [_dateKey(from), _dateKey(date)],
    );
    final loggedDates = rows.map((r) => r['date'] as String).toSet();

    int streak = 0;
    var cursor = date;
    while (loggedDates.contains(_dateKey(cursor))) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return streak;
  }

  // ── weight_log (온보딩/프로필 체중과 별개인 날짜별 체중 기록) ──────

  /// 해당 날짜의 체중을 기록/수정한다(같은 날짜면 덮어씀).
  Future<void> setWeightForDate(DateTime date, double weightKg) async {
    final db = await database;
    await db.insert(
      'weight_log',
      {'date': _dateKey(date), 'weight_kg': weightKg},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 해당 날짜의 체중 기록을 삭제한다(입력값을 비워 취소하는 용도).
  Future<void> deleteWeightForDate(DateTime date) async {
    final db = await database;
    await db.delete('weight_log', where: 'date = ?', whereArgs: [_dateKey(date)]);
  }

  Future<double?> getWeightForDate(DateTime date) async {
    final db = await database;
    final rows = await db.query('weight_log', where: 'date = ?', whereArgs: [_dateKey(date)]);
    if (rows.isEmpty) return null;
    return (rows.first['weight_kg'] as num).toDouble();
  }

  /// 캘린더 한 달치처럼, 구간 내 날짜별 체중을 한 번에 조회한다. 키는 'yyyy-MM-dd'.
  Future<Map<String, double>> getWeightsForRange(DateTime from, DateTime to) async {
    final db = await database;
    final rows = await db.query(
      'weight_log',
      where: 'date >= ? AND date <= ?',
      whereArgs: [_dateKey(from), _dateKey(to)],
    );
    return {for (final r in rows) r['date'] as String: (r['weight_kg'] as num).toDouble()};
  }

  /// 가장 최근에 기록된 체중 하나(날짜 무관). 최신 체중 기준 표시용.
  Future<double?> getLatestWeight() async {
    final db = await database;
    final rows = await db.query('weight_log', orderBy: 'date DESC', limit: 1);
    if (rows.isEmpty) return null;
    return (rows.first['weight_kg'] as num).toDouble();
  }

  /// [date] 이하(그날 포함)로 기록된 체중 중 가장 최근 값. 체중 기록 화면에서
  /// "선택한 날짜에 기록이 없으면 그 이전 가장 가까운 기록"을 보여줄 때 쓴다
  /// (그날 이후 미래 기록은 보지 않는다 — 과거 시점 화면에 미래 체중이 "최근"으로
  /// 뜨면 시간 순서상 혼란스럽다).
  Future<double?> getWeightOnOrBefore(DateTime date) async {
    final db = await database;
    final rows = await db.query(
      'weight_log',
      where: 'date <= ?',
      whereArgs: [_dateKey(date)],
      orderBy: 'date DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return (rows.first['weight_kg'] as num).toDouble();
  }

  /// [date]에 이미 체중이 기록되어 있어야 사진을 붙일 수 있다(weight_log는 date가
  /// PK이고 weight_kg가 NOT NULL이라 체중 없이 사진만 있는 행은 만들 수 없음). 그런
  /// 날짜에 호출하면 0행이 갱신되고 조용히 무시된다.
  Future<void> setWeightPhotoPath(DateTime date, String? photoPath) async {
    final db = await database;
    await db.update(
      'weight_log',
      {'photo_path': photoPath},
      where: 'date = ?',
      whereArgs: [_dateKey(date)],
    );
  }

  Future<String?> getWeightPhotoPath(DateTime date) async {
    final db = await database;
    final rows = await db.query('weight_log', where: 'date = ?', whereArgs: [_dateKey(date)]);
    if (rows.isEmpty) return null;
    return rows.first['photo_path'] as String?;
  }

  /// 구간 내 사진이 있는 날짜만 반환한다(체중 기록 캘린더의 카메라 아이콘 표시용).
  Future<Map<String, String>> getWeightPhotoPathsForRange(DateTime from, DateTime to) async {
    final db = await database;
    final rows = await db.query(
      'weight_log',
      columns: ['date', 'photo_path'],
      where: 'date >= ? AND date <= ? AND photo_path IS NOT NULL',
      whereArgs: [_dateKey(from), _dateKey(to)],
    );
    return {for (final r in rows) r['date'] as String: r['photo_path'] as String};
  }

  /// 사진이 있는 체중 기록 전체를 날짜순으로 반환한다(사진 비교 화면의 날짜 선택용).
  Future<List<WeightPhotoRecord>> getWeightPhotoRecords() async {
    final db = await database;
    final rows = await db.query(
      'weight_log',
      where: 'photo_path IS NOT NULL',
      orderBy: 'date ASC',
    );
    return rows
        .map((r) => WeightPhotoRecord(
              date: r['date'] as String,
              weightKg: (r['weight_kg'] as num).toDouble(),
              photoPath: r['photo_path'] as String,
            ))
        .toList();
  }

  String _dateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
