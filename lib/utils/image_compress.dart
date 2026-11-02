import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// 순수 Dart(image 패키지)로 한 번에 디코딩할 최대 픽셀 수. 이보다 큰 사진(예: 50MP)을
/// 통째로 RGBA로 풀면 수백 MB를 잡아 메모리 부족으로 앱이 죽을 수 있으므로, 이 경우엔
/// 디코딩하지 않고 실패로 돌려 호출부가 축소 디코딩이 가능한 플랫폼 디코더로 다시
/// 시도하게 한다(FoodPhotoService 참고).
const int maxPureDartDecodePixels = 24 * 1000 * 1000;

/// 압축 결과. 성공하면 [bytes], 실패하면 원인 설명([error]). isolate 간에 그대로
/// 주고받을 수 있도록 단순 필드만 둔다.
class CompressOutcome {
  final Uint8List? bytes;
  final String? error;

  const CompressOutcome.success(Uint8List this.bytes) : error = null;
  const CompressOutcome.failure(String this.error) : bytes = null;

  bool get ok => bytes != null;
}

/// 가로/세로 중 긴 쪽이 [maxDimension]을 넘으면 비율을 유지한 채 줄이고, EXIF 회전
/// 정보를 실제 픽셀에 반영한 뒤 JPEG 품질 [quality]로 재인코딩한다. 결과 JPEG에는
/// EXIF를 남기지 않는다(회전 태그 중복 적용 방지 + 원본의 GPS 위치 등 제거).
///
/// image 패키지가 못 읽는 형식(HEIC/HEIF 등)이거나 너무 큰 사진이면 예외 대신
/// 원인을 담은 실패 결과를 돌려준다.
CompressOutcome compressJpegDetailed(
  Uint8List originalBytes, {
  required int maxDimension,
  required int quality,
  int maxDecodePixels = maxPureDartDecodePixels,
}) {
  try {
    final decoder = img.findDecoderForData(originalBytes);
    if (decoder == null) {
      return CompressOutcome.failure('image 패키지가 지원하지 않는 형식 (헤더 ${_headerHex(originalBytes)})');
    }
    final info = decoder.startDecode(originalBytes);
    if (info != null && info.width * info.height > maxDecodePixels) {
      return CompressOutcome.failure(
        '사진이 너무 큼 (${info.width}x${info.height}, ${decoder.runtimeType}) — 메모리 보호를 위해 건너뜀',
      );
    }
    final decoded = decoder.decode(originalBytes);
    if (decoded == null) {
      return CompressOutcome.failure('${decoder.runtimeType} 디코딩 실패');
    }
    return CompressOutcome.success(_resizeOrientEncode(decoded, maxDimension: maxDimension, quality: quality));
  } catch (e) {
    return CompressOutcome.failure('압축 중 예외: $e');
  }
}

/// [compressJpegDetailed]의 간단 버전. 실패하면 null(원인은 버림).
Uint8List? compressJpeg(Uint8List originalBytes, {required int maxDimension, required int quality}) =>
    compressJpegDetailed(originalBytes, maxDimension: maxDimension, quality: quality).bytes;

Uint8List _resizeOrientEncode(img.Image decoded, {required int maxDimension, required int quality}) {
  final orientation = decoded.exif.imageIfd.hasOrientation ? decoded.exif.imageIfd.orientation : null;

  final longestSide = math.max(decoded.width, decoded.height);
  var out = longestSide > maxDimension
      ? img.copyResize(
          decoded,
          width: decoded.width >= decoded.height ? maxDimension : null,
          height: decoded.height > decoded.width ? maxDimension : null,
        )
      : decoded;

  // JPEG는 image 패키지 디코더가 이미 EXIF 회전을 반영하고 태그를 지워 준다. 다른
  // 형식(TIFF/WebP 등)에 회전 태그가 남아 있는 경우를 위한 방어로, 축소한 뒤에 돌린다
  // (원본 크기에서 돌리는 것보다 훨씬 가볍다).
  if (orientation != null && orientation != 1) {
    out.exif = img.ExifData()..imageIfd.orientation = orientation;
    out = img.bakeOrientation(out);
  }
  out.exif = img.ExifData();
  return Uint8List.fromList(img.encodeJpg(out, quality: quality));
}

String _headerHex(Uint8List bytes) =>
    bytes.take(12).map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');

/// compute()에 넘기기 위한 인자 묶음(compute 콜백은 인자를 하나만 받는다).
class ImageCompressRequest {
  final Uint8List bytes;
  final int maxDimension;
  final int quality;

  const ImageCompressRequest(this.bytes, {required this.maxDimension, required this.quality});
}

/// compute() 진입점(최상위 함수여야 함).
CompressOutcome compressJpegInIsolate(ImageCompressRequest req) =>
    compressJpegDetailed(req.bytes, maxDimension: req.maxDimension, quality: req.quality);

/// 플랫폼 디코더(dart:ui)가 이미 풀어 둔 RGBA 픽셀을 JPEG로 인코딩하는 요청.
class RgbaEncodeRequest {
  final Uint8List rgba;
  final int width;
  final int height;
  final int maxDimension;
  final int quality;

  const RgbaEncodeRequest(
    this.rgba, {
    required this.width,
    required this.height,
    required this.maxDimension,
    required this.quality,
  });
}

/// compute() 진입점: RGBA → (필요하면 축소) → JPEG. 플랫폼 디코더가 EXIF 회전을 이미
/// 반영해 픽셀을 돌려주므로 여기서는 회전하지 않는다.
CompressOutcome encodeRgbaToJpegInIsolate(RgbaEncodeRequest req) {
  try {
    final image = img.Image.fromBytes(
      width: req.width,
      height: req.height,
      bytes: req.rgba.buffer,
      bytesOffset: req.rgba.offsetInBytes,
      numChannels: 4,
      order: img.ChannelOrder.rgba,
    );
    return CompressOutcome.success(_resizeOrientEncode(image, maxDimension: req.maxDimension, quality: req.quality));
  } catch (e) {
    return CompressOutcome.failure('RGBA → JPEG 인코딩 중 예외: $e');
  }
}
