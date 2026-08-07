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
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE daily_log (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            datetime TEXT NOT NULL,
            type TEXT NOT NULL,
            name TEXT NOT NULL,
            calories REAL NOT NULL,
            amount REAL,
            mode TEXT
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
