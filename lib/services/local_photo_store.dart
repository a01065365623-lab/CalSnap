import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// 앱 전용 documents 디렉터리 아래 하위 폴더 하나([dirName])에 사진 파일을 저장/삭제하는
/// 공통 로직. 체중 사진(weight_photos)과 음식 사진(food_photos)이 함께 쓴다.
/// DB에는 이 클래스가 반환한 경로 문자열만 저장되고, 실제 파일 관리는 여기서 전담한다.
/// 사진은 서버로 올리지 않으며 이 기기에만 남는다.
abstract class LocalPhotoStore {
  LocalPhotoStore(this.dirName);

  final String dirName;

  Future<Directory> photoDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${appDir.path}/$dirName');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// 사진 한 장을 삭제한다. 경로가 null/빈 문자열이거나 파일이 이미 없으면 무시한다.
  Future<void> deletePhoto(String? path) async {
    if (path == null || path.isEmpty) return;
    final file = File(path);
    if (await file.exists()) await file.delete();
  }

  Future<void> deletePhotos(Iterable<String?> paths) async {
    for (final p in paths) {
      await deletePhoto(p);
    }
  }

  /// 디렉터리 전체를 삭제한다("전체 초기화" 등 모든 기록 삭제 시 사용).
  Future<void> deleteAllPhotos() async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${appDir.path}/$dirName');
    if (await dir.exists()) await dir.delete(recursive: true);
  }
}
