import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// 순수 Dart(image 패키지)로 한 번에 디코딩할 최대 픽셀 수. 이보다 큰 사진(예: 50MP)을
/// 통째로 RGBA로 풀면 수백 MB를 잡아 메모리 부족으로 앱이 죽을 수 있으므로, 이 경우엔
/// 디코딩하지 않고 실패로 돌려 호출부가 축소 디코딩이 가능한 플랫폼 디코더로 다시
/// 시도하게 한다(FoodPhotoService 참고).
const int maxPureDartDecodePixels = 24 * 1000 * 1000;

/// 음식 사진 한 장에서 만드는 두 가지 JPEG 규격.
///  - 기기 저장용(documents/food_photos): 긴 변 800px, 품질 75%
///  - 인식 업로드용(서버 → Gemini): 긴 변 768px, 품질 80%. 서버는 리사이즈하지 않고
///    받은 바이트를 그대로 Gemini에 넘기며, 캐시 키도 이 바이트의 sha256이다.
class FoodPhotoSpec {
  static const int storageMaxDimension = 800;
  static const int storageQuality = 75;
  static const int uploadMaxDimension = 768;
  static const int uploadQuality = 80;
}

/// 한 번의 디코딩으로 만든 저장용·업로드용 JPEG. 실패하면 [error]에 원인. isolate 간에
/// 그대로 주고받을 수 있도록 단순 필드만 둔다.
class DualJpegOutcome {
  final Uint8List? storageJpeg;
  final Uint8List? uploadJpeg;
  final String? error;

  const DualJpegOutcome.success(Uint8List this.storageJpeg, Uint8List this.uploadJpeg) : error = null;
  const DualJpegOutcome.failure(String this.error)
      : storageJpeg = null,
        uploadJpeg = null;

  bool get ok => storageJpeg != null && uploadJpeg != null;
}

/// 원본 사진 바이트(JPEG/PNG/WebP 등)를 image 패키지로 **한 번만** 디코딩해 저장용·
/// 업로드용 JPEG를 함께 만든다. EXIF 회전은 픽셀에 반영하고, 결과 JPEG에는 EXIF를
/// 남기지 않는다(회전 태그 중복 적용 방지 + 원본의 GPS 위치 등 제거).
///
/// image 패키지가 못 읽는 형식(HEIC/HEIF 등)이거나 너무 큰 사진이면 예외 대신 원인을
/// 담은 실패 결과를 돌려준다. 같은 입력이면 항상 같은 바이트가 나온다(결정적 인코딩).
DualJpegOutcome encodeFoodPhotoFromEncoded(Uint8List originalBytes, {int maxDecodePixels = maxPureDartDecodePixels}) {
  try {
    final decoder = img.findDecoderForData(originalBytes);
    if (decoder == null) {
      return DualJpegOutcome.failure('image 패키지가 지원하지 않는 형식 (헤더 ${_headerHex(originalBytes)})');
    }
    final info = decoder.startDecode(originalBytes);
    if (info != null && info.width * info.height > maxDecodePixels) {
      return DualJpegOutcome.failure(
        '사진이 너무 큼 (${info.width}x${info.height}, ${decoder.runtimeType}) — 메모리 보호를 위해 건너뜀',
      );
    }
    final decoded = decoder.decode(originalBytes);
    if (decoded == null) {
      return DualJpegOutcome.failure('${decoder.runtimeType} 디코딩 실패');
    }
    return _encodeDual(decoded);
  } catch (e) {
    return DualJpegOutcome.failure('압축 중 예외: $e');
  }
}

/// 플랫폼 디코더(dart:ui)가 이미 풀어 둔 RGBA 픽셀로 저장용·업로드용 JPEG를 만드는 요청.
class RgbaEncodeRequest {
  final Uint8List rgba;
  final int width;
  final int height;

  const RgbaEncodeRequest(this.rgba, {required this.width, required this.height});
}

/// RGBA → 저장용·업로드용 JPEG. 플랫폼 디코더가 EXIF 회전을 이미 반영해 픽셀을 돌려주므로
/// 여기서는 회전하지 않는다.
DualJpegOutcome encodeFoodPhotoFromRgba(RgbaEncodeRequest req) {
  try {
    final image = img.Image.fromBytes(
      width: req.width,
      height: req.height,
      bytes: req.rgba.buffer,
      bytesOffset: req.rgba.offsetInBytes,
      numChannels: 4,
      order: img.ChannelOrder.rgba,
    );
    return _encodeDual(image);
  } catch (e) {
    return DualJpegOutcome.failure('RGBA → JPEG 인코딩 중 예외: $e');
  }
}

/// 디코딩 결과 하나로 두 규격을 만든다: 원본 → 저장용(800) → 그 결과를 다시 업로드용(768)
/// 으로 줄인다. 원본 크기에서 두 번 리사이즈하지 않아 가볍다.
DualJpegOutcome _encodeDual(img.Image decoded) {
  final storage = _fitAndOrient(decoded, FoodPhotoSpec.storageMaxDimension);
  final upload = _fitAndOrient(storage, FoodPhotoSpec.uploadMaxDimension);
  return DualJpegOutcome.success(
    Uint8List.fromList(img.encodeJpg(storage, quality: FoodPhotoSpec.storageQuality)),
    Uint8List.fromList(img.encodeJpg(upload, quality: FoodPhotoSpec.uploadQuality)),
  );
}

/// 긴 변이 [maxDimension]을 넘으면 비율을 유지해 줄이고, 남아 있는 EXIF 회전을 픽셀에
/// 반영한 뒤 EXIF를 비운 이미지를 돌려준다.
img.Image _fitAndOrient(img.Image source, int maxDimension) {
  final orientation = source.exif.imageIfd.hasOrientation ? source.exif.imageIfd.orientation : null;

  final longestSide = math.max(source.width, source.height);
  var out = longestSide > maxDimension
      ? img.copyResize(
          source,
          width: source.width >= source.height ? maxDimension : null,
          height: source.height > source.width ? maxDimension : null,
        )
      : img.Image.from(source);

  // JPEG는 image 패키지 디코더가 이미 EXIF 회전을 반영하고 태그를 지워 준다. 다른
  // 형식(TIFF/WebP 등)에 회전 태그가 남아 있는 경우를 위한 방어로, 축소한 뒤에 돌린다
  // (원본 크기에서 돌리는 것보다 훨씬 가볍다).
  if (orientation != null && orientation != 1) {
    out.exif = img.ExifData()..imageIfd.orientation = orientation;
    out = img.bakeOrientation(out);
  }
  out.exif = img.ExifData();
  return out;
}

String _headerHex(Uint8List bytes) =>
    bytes.take(12).map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
