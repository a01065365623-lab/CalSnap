// 이미 배포된 0.1.2+11(versionCode 11)의 DB(스키마 v6)를 그대로 만든 뒤, 현재 코드
// (DatabaseHelper, 스키마 v7)로 열었을 때 기존 기록이 보존되고 새 스키마(daily_log.
// photo_path, my_foods)가 추가되는지 확인한다. 실제 기기 대신 PC용 SQLite(sqflite_common_ffi)를 쓴다.
//
// v6 DDL은 커밋 662a1cf(0.1.2+11)의 database_helper.dart onCreate를 그대로 옮겼다.

import 'package:calsnap/db/database_helper.dart';
import 'package:calsnap/models/daily_log_entry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> createV6Database(String path) async {
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
      // 0.1.2+11의 _createFoodDbTables와 같은 음식 DB 테이블. 시딩은 이미 끝난 상태(seed v3)로
      // 둔다 — 업그레이드가 사용자 기록과 무관한 음식 DB 재시딩을 일으키지 않는지도 함께 본다.
      await db.execute('''
        CREATE TABLE food_db (
          id TEXT PRIMARY KEY, name_ko TEXT NOT NULL, name_en TEXT, country TEXT, category TEXT,
          serving_size_g REAL, calories REAL, carbs_g REAL, protein_g REAL, fat_g REAL, sodium_mg REAL,
          main_ingredients TEXT, image_url TEXT, ai_recognized_name TEXT, created_at TEXT
        )
      ''');
      await db.execute('''
        CREATE TABLE food_search_terms (
          id INTEGER PRIMARY KEY AUTOINCREMENT, food_id TEXT NOT NULL, term TEXT NOT NULL,
          FOREIGN KEY (food_id) REFERENCES food_db (id)
        )
      ''');
      await db.execute('CREATE TABLE food_db_meta (key TEXT PRIMARY KEY, value TEXT)');
    },
  );

  // 실제 사용자가 남겼을 법한 기록: 사진 식사, 직접입력 식사, 운동, 물, 체중(사진 포함), 요약.
  await db.insert('daily_log', {
    'datetime': '2026-10-30T08:10:00.000',
    'type': 'food',
    'name': '김밥',
    'calories': 480.0,
    'amount': 250.0,
    'mode': 'quick',
    'carbsG': 70.0,
    'proteinG': 15.0,
    'fatG': 12.0,
    'source': 'photo',
  });
  await db.insert('daily_log', {
    'datetime': '2026-10-30T12:30:00.000',
    'type': 'food',
    'name': '라면',
    'calories': 500.0,
    'amount': 120.0,
    'mode': 'quick',
    'carbsG': 80.0,
    'proteinG': 10.0,
    'fatG': 16.0,
    'source': 'manual',
  });
  await db.insert('daily_log', {
    'datetime': '2026-10-30T19:00:00.000',
    'type': 'exercise',
    'name': '걷기',
    'calories': -150.0,
    'amount': 40.0,
  });
  await db.insert('daily_log', {
    'datetime': '2026-10-30T20:00:00.000',
    'type': 'water',
    'name': '물',
    'calories': 0.0,
    'amount': 250.0,
  });
  await db.insert('daily_summary', {
    'date': '2026-10-30',
    'total_intake': 980.0,
    'total_burned': 150.0,
    'net_calories': 830.0,
  });
  await db.insert('weight_log', {
    'date': '2026-10-30',
    'weight_kg': 61.4,
    'photo_path': '/data/user/0/com.kbraingames.calsnap/app_flutter/weight_photos/weight_20261030.jpg',
  });
  await db.insert('weight_log', {'date': '2026-10-31', 'weight_kg': 61.1});
  await db.insert('food_db', {'id': 'K001', 'name_ko': '비빔밥', 'calories': 150.0});
  await db.insert('food_search_terms', {'food_id': 'K001', 'term': '비빔밥'});
  await db.insert('food_db_meta', {'key': 'seed_version', 'value': '3'});
  await db.close();
}

Future<List<String>> columnsOf(Database db, String table) async =>
    (await db.rawQuery('PRAGMA table_info($table)')).map((r) => r['name'] as String).toList();

void main() {
  late String dbPath;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    dbPath = join(await getDatabasesPath(), 'calsnap.db');
    await deleteDatabase(dbPath);
    await createV6Database(dbPath);
  });

  tearDownAll(() async {
    await (await DatabaseHelper.instance.database).close();
    await deleteDatabase(dbPath);
  });

  test('0.1.2+11(DB v6) → 현재(DB v7): 기존 기록은 그대로, photo_path와 my_foods는 추가', () async {
    final helper = DatabaseHelper.instance;
    final db = await helper.database; // 여기서 onUpgrade(6 → 7)가 실행된다.

    expect(await db.getVersion(), 7);

    // 새 스키마
    expect(await columnsOf(db, 'daily_log'), contains('photo_path'));
    expect(
      await columnsOf(db, 'my_foods'),
      containsAll(['name', 'name_key', 'base_amount_g', 'calories', 'carbs_g', 'protein_g', 'fat_g',
          'photo_path', 'use_count', 'last_used_at']),
    );
    expect(await db.query('my_foods'), isEmpty, reason: '업그레이드만으로 내 음식 목록이 생기지는 않는다');

    // 식사·운동·물 기록 보존(값과 순서 그대로, 새 photo_path는 NULL)
    final logs = await helper.getLogsForDate(DateTime(2026, 10, 30));
    expect(logs.map((e) => e.name), ['김밥', '라면', '걷기', '물']);
    final gimbap = logs[0];
    expect(gimbap.type, LogType.food);
    expect(gimbap.calories, 480);
    expect(gimbap.amount, 250);
    expect([gimbap.carbsG, gimbap.proteinG, gimbap.fatG], [70, 15, 12]);
    expect(gimbap.source, LogSource.photo);
    expect(gimbap.photoPath, isNull, reason: '예전 기록은 사진을 복구할 수 없으므로 NULL로 남는다');
    expect(logs[1].source, LogSource.manual);
    expect(logs[2].type, LogType.exercise);
    expect(logs[2].calories, -150);
    expect(logs[2].amount, 40);
    expect(logs[3].type, LogType.water);
    expect(logs[3].amount, 250);

    // 일일 요약 보존
    final summary = await helper.getSummary(DateTime(2026, 10, 30));
    expect(summary!.totalIntake, 980);
    expect(summary.totalBurned, 150);

    // 체중 기록(사진 경로 포함) 보존
    expect(await helper.getWeightForDate(DateTime(2026, 10, 30)), 61.4);
    expect(await helper.getWeightForDate(DateTime(2026, 10, 31)), 61.1);
    expect(
      await helper.getWeightPhotoPath(DateTime(2026, 10, 30)),
      endsWith('weight_photos/weight_20261030.jpg'),
    );

    // 음식 DB는 재시딩되지 않음(시드 v3 유지, 기존 행 그대로)
    expect((await db.query('food_db')).map((r) => r['id']), ['K001']);
    expect((await db.query('food_db_meta')).single['value'], '3');
  });

  test('업그레이드된 DB에서 새 기능(사진 경로 저장, 내 음식 목록)이 바로 동작한다', () async {
    final helper = DatabaseHelper.instance;

    await helper.insertLog(DailyLogEntry(
      datetime: DateTime(2026, 11, 2, 12),
      type: LogType.food,
      name: '김밥',
      calories: 480,
      amount: 250,
      mode: LogMode.quick,
      carbsG: 70,
      proteinG: 15,
      fatG: 12,
      source: LogSource.photo,
      photoPath: '/x/food_photos/meal_1.jpg',
    ));
    final today = await helper.getLogsForDate(DateTime(2026, 11, 2));
    expect(today.single.photoPath, '/x/food_photos/meal_1.jpg');

    await helper.upsertMyFood(name: '김밥', baseAmountG: 250, calories: 480, carbsG: 70, proteinG: 15, fatG: 12);
    await helper.upsertMyFood(name: ' 김밥 ', baseAmountG: 200, calories: 384, carbsG: 56, proteinG: 12, fatG: 9.6);
    final foods = await helper.getMyFoods();
    expect(foods, hasLength(1), reason: '이름 앞뒤 공백 차이는 같은 음식');
    expect(foods.single.useCount, 2);
    expect(foods.single.baseAmountG, 200);

    // 기존(v6 시절) 기록은 여전히 그대로
    expect((await helper.getLogsForDate(DateTime(2026, 10, 30))).length, 4);
  });
}
