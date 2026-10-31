import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import 'local_photo_store.dart';

/// 체중 기록에 첨부하는 사진(전/후 비교용)을 기기 로컬(documents/weight_photos)에
/// 저장/삭제한다. DB(weight_log.photo_path)에는 이 서비스가 반환한 경로 문자열만 저장된다.
class WeightPhotoService extends LocalPhotoStore {
  WeightPhotoService._internal() : super('weight_photos');
  static final WeightPhotoService instance = WeightPhotoService._internal();

  /// [date] 기준 파일명으로 저장한다(같은 날짜에 다시 촬영하면 덮어씀). 반환값을
  /// DatabaseHelper.setWeightPhotoPath에 그대로 넘기면 된다.
  Future<String> savePhoto(XFile picked, DateTime date) async {
    final dir = await photoDir();
    final fileName = 'weight_${DateFormat('yyyyMMdd').format(date)}.jpg';
    final savedPath = '${dir.path}/$fileName';
    await File(picked.path).copy(savedPath);
    return savedPath;
  }
}
