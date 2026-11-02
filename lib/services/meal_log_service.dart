import 'dart:typed_data';

import '../db/database_helper.dart';
import '../models/daily_log_entry.dart';
import '../models/my_food.dart';
import 'food_photo_service.dart';
import 'weight_photo_service.dart';

/// 식사 기록 저장/삭제를 DB(daily_log, my_foods)와 기기 로컬 사진 파일(food_photos)에
/// 함께 반영한다. DatabaseHelper는 파일 시스템을 건드리지 않으므로, 사진이 붙을 수 있는
/// 기록의 저장·삭제·초기화는 반드시 이 서비스를 거쳐야 사진 파일이 고아로 남지 않는다.
class MealLogService {
  MealLogService._internal();
  static final MealLogService instance = MealLogService._internal();

  final _db = DatabaseHelper.instance;
  final _photos = FoodPhotoService.instance;

  /// 빠른측정(사진/직접입력) 결과를 식사 기록으로 저장하고 내 음식 목록을 갱신한다.
  /// [photoJpeg]는 FoodPhotoService.prepare가 이미 800px/JPEG 75%로 만들어 둔 저장용
  /// 바이트다(다시 디코딩하지 않음). 서버에는 올리지 않고 기기에만 저장한다.
  Future<void> saveMeal({
    required String name,
    required double calories,
    double? amountG,
    required double carbsG,
    required double proteinG,
    required double fatG,
    required LogSource source,
    Uint8List? photoJpeg,
  }) async {
    final now = DateTime.now();
    final photoPath = photoJpeg != null ? await _photos.writeMealPhoto(photoJpeg) : null;
    await _db.insertLog(DailyLogEntry(
      datetime: now,
      type: LogType.food,
      name: name,
      calories: calories,
      amount: amountG,
      mode: LogMode.quick,
      carbsG: carbsG,
      proteinG: proteinG,
      fatG: fatG,
      source: source,
      photoPath: photoPath,
    ));
    // 목록 썸네일은 기록 사진과 별도 파일로 복사해 둔다(기록을 지워도 목록이 깨지지 않게).
    final thumbPath = await _photos.copyPhoto(photoPath, prefix: 'my_food');
    await _upsertMyFood(
      name: name,
      amountG: amountG,
      calories: calories,
      carbsG: carbsG,
      proteinG: proteinG,
      fatG: fatG,
      thumbPath: thumbPath,
      usedAt: now,
    );
  }

  /// 내 음식 목록 항목을 [multiplier]배 양으로 바로 기록한다. AI 인식(Gemini)을 호출하지
  /// 않으므로 서버 일일 한도에도 포함되지 않는다. 기록에는 목록 썸네일을 복사해 붙인다.
  Future<void> saveFromMyFood(MyFood food, double multiplier) async {
    final now = DateTime.now();
    final amountG = food.baseAmountG != null ? food.baseAmountG! * multiplier : null;
    final calories = food.calories * multiplier;
    final carbs = food.carbsG * multiplier;
    final protein = food.proteinG * multiplier;
    final fat = food.fatG * multiplier;
    final photoPath = await _photos.copyPhoto(food.photoPath, prefix: 'meal');
    await _db.insertLog(DailyLogEntry(
      datetime: now,
      type: LogType.food,
      name: food.name,
      calories: calories,
      amount: amountG,
      mode: LogMode.quick,
      carbsG: carbs,
      proteinG: protein,
      fatG: fat,
      source: LogSource.myFood,
      photoPath: photoPath,
    ));
    await _upsertMyFood(
      name: food.name,
      amountG: amountG,
      calories: calories,
      carbsG: carbs,
      proteinG: protein,
      fatG: fat,
      thumbPath: null, // 기존 썸네일 유지
      usedAt: now,
    );
  }

  /// 지난 식사 기록 한 건을 지금 시각의 새 기록으로 다시 남긴다(식사 사진 달력의 "오늘로
  /// 다시 기록"). 내 음식 목록 재기록과 마찬가지로 AI 인식(Gemini)을 호출하지 않아 서버
  /// 일일 한도에 포함되지 않고, 출처는 LogSource.myFood로 남긴다.
  Future<void> relogToToday(DailyLogEntry meal) => _relogAll([meal]);

  /// [date]의 음식 기록 전체를 오늘로 복사하고 복사한 개수를 반환한다. 운동·물 기록은
  /// 식단이 아니므로 제외한다. 저장 방식은 [relogToToday]와 같다.
  Future<int> copyDayToToday(DateTime date) async {
    final meals = (await _db.getLogsForDate(date)).where((e) => e.type == LogType.food).toList();
    await _relogAll(meals);
    return meals.length;
  }

  Future<void> _relogAll(List<DailyLogEntry> meals) async {
    if (meals.isEmpty) return;
    final now = DateTime.now();
    final copies = <DailyLogEntry>[];
    for (var i = 0; i < meals.length; i++) {
      // 사진은 새 파일로 복사해 둔다(원래 기록을 지워도 새 기록의 사진이 깨지지 않게).
      final photoPath = await _photos.copyPhoto(meals[i].photoPath, prefix: 'meal');
      // 같은 시각으로 넣으면 목록 순서가 섞일 수 있어, 원래 순서대로 1ms씩 벌린다.
      copies.add(relogEntry(meals[i], now.add(Duration(milliseconds: i)), photoPath));
    }
    await _db.insertLogsBulk(copies);
    for (final c in copies) {
      await _upsertMyFood(
        name: c.name,
        amountG: c.amount,
        calories: c.calories,
        carbsG: c.carbsG ?? 0,
        proteinG: c.proteinG ?? 0,
        fatG: c.fatG ?? 0,
        thumbPath: null, // 기존 썸네일 유지
        usedAt: now,
      );
    }
  }

  Future<void> _upsertMyFood({
    required String name,
    double? amountG,
    required double calories,
    required double carbsG,
    required double proteinG,
    required double fatG,
    String? thumbPath,
    required DateTime usedAt,
  }) async {
    final replaced = await _db.upsertMyFood(
      name: name,
      baseAmountG: amountG,
      calories: calories,
      carbsG: carbsG,
      proteinG: proteinG,
      fatG: fatG,
      photoPath: thumbPath,
      usedAt: usedAt,
    );
    await _photos.deletePhoto(replaced);
  }

  /// 기록 한 건과 그 사진 파일을 함께 삭제한다.
  Future<void> deleteLog(int id, DateTime date) async {
    final photoPath = await _db.deleteLog(id, date);
    await _photos.deletePhoto(photoPath);
  }

  /// 해당 날짜의 기록 전체와 그 사진 파일들을 함께 삭제한다.
  Future<void> deleteLogsForDate(DateTime date) async {
    final photoPaths = await _db.deleteLogsForDate(date);
    await _photos.deletePhotos(photoPaths);
  }

  /// 모든 기록(식사·운동·물·체중·내 음식 목록)과 기기에 저장된 사진(식사·체중)을 전부
  /// 삭제한다. "전체 초기화"와 시크릿 모드 PIN 분실 초기화에서 사용.
  Future<void> resetAllData() async {
    await _db.resetAllData();
    await _photos.deleteAllPhotos();
    await WeightPhotoService.instance.deleteAllPhotos();
  }
}

/// [meal]과 같은 음식·양·영양 정보로 [at] 시각에 다시 기록할 항목을 만든다. id는 새로
/// 매기고, 출처는 AI 인식 없이 다시 기록했다는 뜻의 LogSource.myFood로 바꾼다.
DailyLogEntry relogEntry(DailyLogEntry meal, DateTime at, String? photoPath) => DailyLogEntry(
      datetime: at,
      type: LogType.food,
      name: meal.name,
      calories: meal.calories,
      amount: meal.amount,
      mode: meal.mode ?? LogMode.quick,
      carbsG: meal.carbsG,
      proteinG: meal.proteinG,
      fatG: meal.fatG,
      source: LogSource.myFood,
      photoPath: photoPath,
    );
