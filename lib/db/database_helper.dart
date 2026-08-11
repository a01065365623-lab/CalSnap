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
      version: 2,
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
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          // 기존 행은 세 컬럼 모두 NULL로 채워지고, log_entry_tile/일일 영양소 집계에서
          // null을 0으로 취급한다.
          await db.execute('ALTER TABLE daily_log ADD COLUMN carbsG REAL');
          await db.execute('ALTER TABLE daily_log ADD COLUMN proteinG REAL');
          await db.execute('ALTER TABLE daily_log ADD COLUMN fatG REAL');
        }
      },
    );
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

  String _dateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
