import 'dart:io';

import 'package:flutter/foundation.dart' show compute;
import 'package:uuid/uuid.dart';

import '../utils/image_compress.dart';
import 'local_photo_store.dart';

/// 식사 기록 사진을 기기 로컬(documents/food_photos)에 저장/삭제한다. 원본 카메라
/// 사진(수 MB)을 그대로 두면 1년치 기록에 저장 공간이 크게 늘어나므로, 긴 변
/// [maxDimension]px · JPEG [jpegQuality]%로 줄여 저장한다. 서버로는 올리지 않는다.
///
/// "내 음식 목록"(my_foods) 썸네일은 식사 기록 사진과 별도 파일(my_food_*.jpg)로
/// 복사해 둔다 — 기록을 지워도 목록 썸네일이 깨지지 않게 하기 위해서다.
class FoodPhotoService extends LocalPhotoStore {
  FoodPhotoService._internal() : super('food_photos');
  static final FoodPhotoService instance = FoodPhotoService._internal();

  static const int maxDimension = 800;
  static const int jpegQuality = 75;

  static const _uuid = Uuid();

  /// [source]를 축소·재인코딩해 새 파일(meal_<uuid>.jpg)로 저장하고 경로를 반환한다.
  /// 디코딩에 실패하면(지원 안 하는 포맷 등) 사진 없이 저장되도록 null을 반환한다.
  Future<String?> saveMealPhoto(File source) async {
    try {
      final bytes = await source.readAsBytes();
      final compressed = await compute(
        compressJpegInIsolate,
        ImageCompressRequest(bytes, maxDimension: maxDimension, quality: jpegQuality),
      );
      if (compressed == null) return null;
      final dir = await photoDir();
      final path = '${dir.path}/meal_${_uuid.v4()}.jpg';
      await File(path).writeAsBytes(compressed, flush: true);
      return path;
    } catch (_) {
      // 사진 저장 실패가 식사 기록 저장 자체를 막아서는 안 된다.
      return null;
    }
  }

  /// 이미 저장된(축소된) 사진 파일을 [prefix]_<uuid>.jpg로 복사한다. 원본이 없으면 null.
  Future<String?> copyPhoto(String? sourcePath, {required String prefix}) async {
    if (sourcePath == null) return null;
    try {
      final src = File(sourcePath);
      if (!await src.exists()) return null;
      final dir = await photoDir();
      final path = '${dir.path}/${prefix}_${_uuid.v4()}.jpg';
      await src.copy(path);
      return path;
    } catch (_) {
      return null;
    }
  }
}
