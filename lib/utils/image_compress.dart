import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// 가로/세로 중 긴 쪽이 [maxDimension]을 넘으면 비율을 유지한 채 줄이고, JPEG 품질
/// [quality]로 재인코딩한다. 디코딩에 실패하면(지원 안 하는 포맷 등) null을 반환해
/// 호출부가 원본을 그대로 쓸지 결정하게 한다.
///
/// CPU 바운드 작업이라 UI 스레드에서 무거운 사진을 처리할 때는 compute()로 감싸
/// 호출한다([ImageCompressRequest]/[compressJpegInIsolate] 참고).
Uint8List? compressJpeg(Uint8List originalBytes, {required int maxDimension, required int quality}) {
  final decoded = img.decodeImage(originalBytes);
  if (decoded == null) return null;

  final longestSide = decoded.width > decoded.height ? decoded.width : decoded.height;
  final resized = longestSide > maxDimension
      ? img.copyResize(
          decoded,
          width: decoded.width >= decoded.height ? maxDimension : null,
          height: decoded.height > decoded.width ? maxDimension : null,
        )
      : decoded;

  return Uint8List.fromList(img.encodeJpg(resized, quality: quality));
}

/// compute()에 넘기기 위한 인자 묶음(compute 콜백은 인자를 하나만 받는다).
class ImageCompressRequest {
  final Uint8List bytes;
  final int maxDimension;
  final int quality;

  const ImageCompressRequest(this.bytes, {required this.maxDimension, required this.quality});
}

/// compute() 진입점(최상위 함수여야 함).
Uint8List? compressJpegInIsolate(ImageCompressRequest req) =>
    compressJpeg(req.bytes, maxDimension: req.maxDimension, quality: req.quality);
