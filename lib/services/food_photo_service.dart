import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show compute, debugPrint, visibleForTesting;
import 'package:uuid/uuid.dart';

import '../utils/image_compress.dart';
import 'local_photo_store.dart';

/// 순수 Dart 경로 시그니처(테스트에서 실패 상황을 흉내 내기 위해 교체 가능).
typedef PrimaryPhotoEncoder = Future<DualJpegOutcome> Function(Uint8List originalBytes);

/// 플랫폼 디코더 경로 시그니처(테스트에서 교체 가능).
typedef PlatformPhotoEncoder = Future<DualJpegOutcome> Function(Uint8List originalBytes);

/// 사진 한 장을 한 번 디코딩해 만든 결과. 인식 업로드에는 [uploadJpeg], 식사 저장에는
/// [storageJpeg]를 쓴다. 재시도 때도 같은 객체를 다시 쓰면 서버 캐시 키(업로드 바이트의
/// sha256)가 그대로 유지된다.
class PreparedFoodPhoto {
  final Uint8List storageJpeg;
  final Uint8List uploadJpeg;
  final int originalBytes;

  /// 'image 패키지' 또는 '플랫폼 디코더'.
  final String decoder;
  final Duration elapsed;

  const PreparedFoodPhoto({
    required this.storageJpeg,
    required this.uploadJpeg,
    required this.originalBytes,
    required this.decoder,
    required this.elapsed,
  });
}

/// 식사 사진을 준비(디코딩·축소)하고 기기 로컬(documents/food_photos)에 저장/삭제한다.
/// 서버로는 업로드용 축소본만 인식 요청에 실어 보내고, 저장본은 이 기기에만 둔다.
///
/// 카메라 촬영본은 JPEG이지만 갤러리에서 고른 사진은 기기 설정에 따라 HEIC/HEIF일 수
/// 있다(삼성 등은 기본 촬영 형식이 HEIC). image 패키지는 HEIC를 못 읽으므로, 1차로
/// 순수 Dart로 디코딩하고 실패하면 플랫폼 디코더(dart:ui — Android는 HEIF 지원)로 축소
/// 디코딩한다. 어느 쪽이든 디코딩은 한 번이고, 그 결과에서 저장용(800px/75%)과
/// 업로드용(768px/80%) JPEG를 함께 만든다([FoodPhotoSpec]). 각 단계의 실패 원인과
/// 변환 시간·크기는 debugPrint로 남긴다.
///
/// "내 음식 목록"(my_foods) 썸네일은 식사 기록 사진과 별도 파일(my_food_*.jpg)로
/// 복사해 둔다 — 기록을 지워도 목록 썸네일이 깨지지 않게 하기 위해서다.
class FoodPhotoService extends LocalPhotoStore {
  FoodPhotoService._internal() : super('food_photos');
  static final FoodPhotoService instance = FoodPhotoService._internal();

  static const _uuid = Uuid();
  static const _tag = '[FoodPhotoService]';

  @visibleForTesting
  PrimaryPhotoEncoder primaryEncoder = (bytes) => compute(_encodeFromEncodedInIsolate, bytes);

  @visibleForTesting
  PlatformPhotoEncoder platformEncoder = _encodeWithPlatformDecoder;

  /// [source]를 읽어 한 번 디코딩하고 저장용·업로드용 JPEG를 만든다. 순수 Dart와 플랫폼
  /// 디코더가 모두 실패하면 원인을 로그로 남기고 null을 반환한다 — 이때 호출부는 원본을
  /// 그대로 올리지 말고 "사진을 읽을 수 없어요"를 안내해야 한다.
  Future<PreparedFoodPhoto?> prepare(File source) async {
    final Uint8List bytes;
    try {
      bytes = await source.readAsBytes();
    } catch (e) {
      debugPrint('$_tag 원본 사진을 읽지 못함 (${source.path}): $e');
      return null;
    }
    return prepareBytes(bytes, sourceLabel: source.path);
  }

  @visibleForTesting
  Future<PreparedFoodPhoto?> prepareBytes(Uint8List bytes, {String sourceLabel = ''}) async {
    final stopwatch = Stopwatch()..start();

    var decoder = 'image 패키지';
    var outcome = await _guard(() => primaryEncoder(bytes));
    if (!outcome.ok) {
      debugPrint('$_tag 1차 디코딩 실패 ($sourceLabel, ${bytes.length}B): ${outcome.error} → 플랫폼 디코더로 재시도');
      decoder = '플랫폼 디코더';
      outcome = await _guard(() => platformEncoder(bytes));
      if (!outcome.ok) {
        stopwatch.stop();
        debugPrint(
          '$_tag 플랫폼 디코더 재시도도 실패 ($sourceLabel, ${stopwatch.elapsedMilliseconds}ms): '
          '${outcome.error} → 사진을 읽을 수 없음',
        );
        return null;
      }
    }
    stopwatch.stop();

    final prepared = PreparedFoodPhoto(
      storageJpeg: outcome.storageJpeg!,
      uploadJpeg: outcome.uploadJpeg!,
      originalBytes: bytes.length,
      decoder: decoder,
      elapsed: stopwatch.elapsed,
    );
    debugPrint(
      '$_tag 사진 변환 완료 ($decoder, ${prepared.elapsed.inMilliseconds}ms): 원본 ${bytes.length}B → '
      '업로드 ${prepared.uploadJpeg.length}B(${FoodPhotoSpec.uploadMaxDimension}px/${FoodPhotoSpec.uploadQuality}%), '
      '저장 ${prepared.storageJpeg.length}B(${FoodPhotoSpec.storageMaxDimension}px/${FoodPhotoSpec.storageQuality}%)',
    );
    return prepared;
  }

  static Future<DualJpegOutcome> _guard(Future<DualJpegOutcome> Function() run) async {
    try {
      return await run();
    } catch (e) {
      return DualJpegOutcome.failure('예외: $e');
    }
  }

  static DualJpegOutcome _encodeFromEncodedInIsolate(Uint8List bytes) => encodeFoodPhotoFromEncoded(bytes);

  /// dart:ui 이미지 코덱으로 디코딩한다. Android에서는 시스템 디코더가 HEIC/HEIF를
  /// 처리하고 EXIF 회전도 반영한다. 큰 사진은 디코딩 단계에서부터 긴 변을 저장용 크기
  /// 근처로 줄여 메모리 사용을 억제한다(한 변만 지정해 비율 유지).
  static Future<DualJpegOutcome> _encodeWithPlatformDecoder(Uint8List bytes) async {
    const maxDim = FoodPhotoSpec.storageMaxDimension;
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final codec = await ui.instantiateImageCodecWithSize(
      buffer,
      getTargetSize: (w, h) {
        if (w <= maxDim && h <= maxDim) return const ui.TargetImageSize();
        return w >= h ? const ui.TargetImageSize(width: maxDim) : const ui.TargetImageSize(height: maxDim);
      },
    );
    try {
      final frame = await codec.getNextFrame();
      final image = frame.image;
      try {
        final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        if (data == null) return const DualJpegOutcome.failure('플랫폼 디코더가 픽셀 데이터를 주지 않음');
        return compute(
          encodeFoodPhotoFromRgba,
          RgbaEncodeRequest(
            data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
            width: image.width,
            height: image.height,
          ),
        );
      } finally {
        image.dispose();
      }
    } finally {
      codec.dispose();
    }
  }

  /// 준비해 둔 저장용 JPEG([PreparedFoodPhoto.storageJpeg])를 새 파일(meal_<uuid>.jpg)로
  /// 쓰고 경로를 반환한다. 다시 디코딩하지 않는다. 쓰기에 실패하면 로그를 남기고 null
  /// (사진 저장 실패가 식사 기록 저장 자체를 막지는 않는다).
  Future<String?> writeMealPhoto(Uint8List storageJpeg) async {
    try {
      final dir = await photoDir();
      final path = '${dir.path}/meal_${_uuid.v4()}.jpg';
      await File(path).writeAsBytes(storageJpeg, flush: true);
      return path;
    } catch (e) {
      debugPrint('$_tag 사진 파일 저장 실패: $e');
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
    } catch (e) {
      debugPrint('$_tag 사진 복사 실패 ($sourcePath): $e');
      return null;
    }
  }
}
