import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/daily_log_entry.dart';

class DatabaseHelper {
  DatabaseHelper._internal();
  static final DatabaseHelper instance = DatabaseHelper._internal();

  Database? _db;

  Future<Database> get database async {
    _db ??= await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'calsnap.db');
    return openDatabase(
      path,
      version: 3,
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
            fatG REAL
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
            weight_kg REAL NOT NULL
          )
        ''');
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
      },
    );
  }

  /// 식사·운동·물, 요약, 체중 기록을 전부 삭제한다. 시크릿 모드 "비밀번호를 잊으셨나요?"
  /// 초기화 흐름 전용 — 스키마는 그대로 두고 데이터만 비운다.
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

  String _dateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
