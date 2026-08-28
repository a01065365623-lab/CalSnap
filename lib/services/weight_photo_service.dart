import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

/// 체중 기록에 첨부하는 사진(전/후 비교용)을 기기 로컬에 저장/삭제한다.
/// DB(weight_log.photo_path)에는 이 서비스가 반환한 경로 문자열만 저장되고,
/// 실제 파일 저장/삭제는 이 서비스가 전담한다.
class WeightPhotoService {
  WeightPhotoService._internal();
  static final WeightPhotoService instance = WeightPhotoService._internal();

  Future<Directory> _photoDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${appDir.path}/weight_photos');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// [date] 기준 파일명으로 저장한다(같은 날짜에 다시 촬영하면 덮어씀). 반환값을
  /// DatabaseHelper.setWeightPhotoPath에 그대로 넘기면 된다.
  Future<String> savePhoto(XFile picked, DateTime date) async {
    final dir = await _photoDir();
    final fileName = 'weight_${DateFormat('yyyyMMdd').format(date)}.jpg';
    final savedPath = '${dir.path}/$fileName';
    await File(picked.path).copy(savedPath);
    return savedPath;
  }

  /// 사진 한 장을 삭제한다(사진 변경/삭제, 체중 기록 자체 삭제 시 사용).
  Future<void> deletePhoto(String path) async {
    final file = File(path);
    if (await file.exists()) await file.delete();
  }

  /// weight_photos 디렉터리 전체를 삭제한다("전체 초기화" 등 모든 기록 삭제 시 사용).
  Future<void> deleteAllPhotos() async {
    final dir = await _photoDir();
    if (await dir.exists()) await dir.delete(recursive: true);
  }
}
