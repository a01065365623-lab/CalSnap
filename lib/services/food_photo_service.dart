import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show compute, debugPrint, visibleForTesting;
import 'package:uuid/uuid.dart';

import '../utils/image_compress.dart';
import 'local_photo_store.dart';

/// 순수 Dart 압축기 시그니처(테스트에서 실패 상황을 흉내 내기 위해 교체 가능).
typedef PrimaryCompressor = Future<CompressOutcome> Function(ImageCompressRequest req);

/// 플랫폼 디코더 경로 시그니처(테스트에서 교체 가능).
typedef PlatformCompressor = Future<CompressOutcome> Function(Uint8List bytes);

/// 식사 기록 사진을 기기 로컬(documents/food_photos)에 저장/삭제한다. 원본 카메라
/// 사진(수 MB)을 그대로 두면 1년치 기록에 저장 공간이 크게 늘어나므로, 긴 변
/// [maxDimension]px · JPEG [jpegQuality]%로 줄여 저장한다. 서버로는 올리지 않는다.
///
/// 카메라 촬영본은 JPEG이지만 갤러리에서 고른 사진은 기기 설정에 따라 HEIC/HEIF일 수
/// 있다(삼성 등은 기본 촬영 형식이 HEIC). image 패키지는 HEIC를 못 읽으므로, 1차로
/// 순수 Dart 압축을 시도하고 실패하면 플랫폼 디코더(dart:ui — Android는 HEIF 지원)로
/// 축소 디코딩해 JPEG로 다시 인코딩한다. 각 단계의 실패 원인은 debugPrint로 남긴다.
///
/// "내 음식 목록"(my_foods) 썸네일은 식사 기록 사진과 별도 파일(my_food_*.jpg)로
/// 복사해 둔다 — 기록을 지워도 목록 썸네일이 깨지지 않게 하기 위해서다.
class FoodPhotoService extends LocalPhotoStore {
  FoodPhotoService._internal() : super('food_photos');
  static final FoodPhotoService instance = FoodPhotoService._internal();

  static const int maxDimension = 800;
  static const int jpegQuality = 75;

  static const _uuid = Uuid();
  static const _tag = '[FoodPhotoService]';

  @visibleForTesting
  PrimaryCompressor primaryCompressor = (req) => compute(compressJpegInIsolate, req);

  @visibleForTesting
  PlatformCompressor platformCompressor = _compressWithPlatformDecoder;

  /// [source]를 축소·재인코딩해 새 파일(meal_<uuid>.jpg)로 저장하고 경로를 반환한다.
  /// 순수 Dart 압축과 플랫폼 디코더 재시도가 모두 실패하면 원인을 로그로 남기고 null을
  /// 반환한다(사진 저장 실패가 식사 기록 저장 자체를 막지는 않는다).
  Future<String?> saveMealPhoto(File source) async {
    final Uint8List bytes;
    try {
      bytes = await source.readAsBytes();
    } catch (e) {
      debugPrint('$_tag 원본 사진을 읽지 못함 (${source.path}): $e');
      return null;
    }

    final compressed = await compressForStorage(bytes, sourceLabel: source.path);
    if (compressed == null) return null;

    try {
      final dir = await photoDir();
      final path = '${dir.path}/meal_${_uuid.v4()}.jpg';
      await File(path).writeAsBytes(compressed, flush: true);
      return path;
    } catch (e) {
      debugPrint('$_tag 압축한 사진을 저장하지 못함: $e');
      return null;
    }
  }

  /// 저장용 JPEG 바이트를 만든다: 순수 Dart → 실패 시 플랫폼 디코더로 재시도.
  @visibleForTesting
  Future<Uint8List?> compressForStorage(Uint8List bytes, {String sourceLabel = ''}) async {
    final first = await _guard(
      () => primaryCompressor(ImageCompressRequest(bytes, maxDimension: maxDimension, quality: jpegQuality)),
    );
    if (first.ok) return first.bytes;
    debugPrint('$_tag 1차 압축 실패 ($sourceLabel, ${bytes.length}B): ${first.error} → 플랫폼 디코더로 재시도');

    final second = await _guard(() => platformCompressor(bytes));
    if (second.ok) {
      debugPrint('$_tag 플랫폼 디코더로 변환 성공 (${bytes.length}B → ${second.bytes!.length}B)');
      return second.bytes;
    }
    debugPrint('$_tag 플랫폼 디코더 재시도도 실패 ($sourceLabel): ${second.error} → 사진 없이 저장');
    return null;
  }

  static Future<CompressOutcome> _guard(Future<CompressOutcome> Function() run) async {
    try {
      return await run();
    } catch (e) {
      return CompressOutcome.failure('예외: $e');
    }
  }

  /// dart:ui 이미지 코덱으로 디코딩한다. Android에서는 시스템 디코더가 HEIC/HEIF를
  /// 처리하고 EXIF 회전도 반영한다. 큰 사진은 디코딩 단계에서부터 긴 변을
  /// [maxDimension] 근처로 줄여 메모리 사용을 억제한다(한 변만 지정해 비율 유지).
  static Future<CompressOutcome> _compressWithPlatformDecoder(Uint8List bytes) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final codec = await ui.instantiateImageCodecWithSize(
      buffer,
      getTargetSize: (w, h) {
        if (w <= maxDimension && h <= maxDimension) return const ui.TargetImageSize();
        return w >= h
            ? const ui.TargetImageSize(width: maxDimension)
            : const ui.TargetImageSize(height: maxDimension);
      },
    );
    try {
      final frame = await codec.getNextFrame();
      final image = frame.image;
      try {
        final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        if (data == null) return const CompressOutcome.failure('플랫폼 디코더가 픽셀 데이터를 주지 않음');
        return compute(
          encodeRgbaToJpegInIsolate,
          RgbaEncodeRequest(
            data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
            width: image.width,
            height: image.height,
            maxDimension: maxDimension,
            quality: jpegQuality,
          ),
        );
      } finally {
        image.dispose();
      }
    } finally {
      codec.dispose();
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
