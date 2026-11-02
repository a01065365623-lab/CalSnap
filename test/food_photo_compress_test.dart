import 'package:calsnap/services/food_photo_service.dart';
import 'package:calsnap/utils/image_compress.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// 왼쪽 절반 빨강, 오른쪽 절반 파랑인 [w]x[h] 이미지. 회전 방향을 픽셀로 확인하는 데 쓴다.
img.Image twoTone(int w, int h) {
  final image = img.Image(width: w, height: h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      image.setPixelRgb(x, y, x < w ~/ 2 ? 255 : 0, 0, x < w ~/ 2 ? 0 : 255);
    }
  }
  return image;
}

/// 카메라가 쓰는 방식 그대로 EXIF(APP1, IFD0 Orientation 태그 0x0112)를 JPEG의 SOI
/// 바로 뒤에 끼워 넣는다. image 패키지 인코더는 회전 태그를 써주지 않아서 직접 만든다.
Uint8List withExifOrientation(Uint8List jpeg, int orientation) {
  final tiff = <int>[
    0x4d, 0x4d, 0x00, 0x2a, 0x00, 0x00, 0x00, 0x08, // big-endian TIFF, IFD0 at 8
    0x00, 0x01, // entry count
    0x01, 0x12, 0x00, 0x03, 0x00, 0x00, 0x00, 0x01, 0x00, orientation, 0x00, 0x00, // Orientation SHORT
    0x00, 0x00, 0x00, 0x00, // next IFD
  ];
  final payload = [...'Exif'.codeUnits, 0, 0, ...tiff];
  final len = payload.length + 2;
  return Uint8List.fromList([
    0xff, 0xd8, // SOI
    0xff, 0xe1, len >> 8, len & 0xff, ...payload,
    ...jpeg.sublist(2),
  ]);
}

/// HEIC 파일의 앞부분(ISO BMFF 'ftyp' 박스, 브랜드 heic). image 패키지는 이 형식을 모른다.
final heicHeader = Uint8List.fromList([
  0x00, 0x00, 0x00, 0x18, 0x66, 0x74, 0x79, 0x70, 0x68, 0x65, 0x69, 0x63, //
  0x00, 0x00, 0x00, 0x00, 0x6d, 0x69, 0x66, 0x31, 0x68, 0x65, 0x69, 0x63,
]);

void main() {
  group('compressJpegDetailed', () {
    test('긴 변을 800px로 줄이고 JPEG로 저장한다', () {
      final src = Uint8List.fromList(img.encodePng(twoTone(1600, 1200)));
      final out = compressJpegDetailed(src, maxDimension: 800, quality: 75);
      expect(out.ok, isTrue, reason: out.error);
      final decoded = img.decodeJpg(out.bytes!)!;
      expect([decoded.width, decoded.height], [800, 600]);
    });

    test('EXIF 회전(6 = 시계 방향 90°)을 픽셀에 반영하고 회전 태그는 남기지 않는다', () {
      final src = withExifOrientation(Uint8List.fromList(img.encodeJpg(twoTone(400, 200), quality: 95)), 6);
      // 전제: 입력 JPEG에 APP1 Exif 블록이 실제로 들어 있다(회전 태그 6).
      expect(src.sublist(2, 4), [0xff, 0xe1]);

      final out = compressJpegDetailed(src, maxDimension: 800, quality: 90);
      expect(out.ok, isTrue, reason: out.error);
      final decoded = img.decodeJpg(out.bytes!)!;
      expect([decoded.width, decoded.height], [200, 400], reason: '가로 사진이 세로로 돌아가야 함');
      expect(decoded.exif.imageIfd.hasOrientation, isFalse, reason: '뷰어가 한 번 더 돌리지 않게');
      // 시계 방향 90°: 원본 왼쪽(빨강)이 위로 온다.
      final top = decoded.getPixel(100, 20);
      final bottom = decoded.getPixel(100, 380);
      expect(top.r, greaterThan(200));
      expect(bottom.b, greaterThan(200));
    });

    test('HEIC처럼 image 패키지가 모르는 형식은 원인을 담아 실패한다', () {
      final out = compressJpegDetailed(heicHeader, maxDimension: 800, quality: 75);
      expect(out.ok, isFalse);
      expect(out.error, contains('지원하지 않는 형식'));
      expect(out.error, contains('66 74 79 70'), reason: "헤더('ftyp')가 로그에 남아야 원인 파악 가능");
    });

    test('픽셀 수가 한도를 넘는 큰 사진은 디코딩하지 않고 실패로 돌린다', () {
      final src = Uint8List.fromList(img.encodeJpg(twoTone(200, 100)));
      final out = compressJpegDetailed(src, maxDimension: 800, quality: 75, maxDecodePixels: 10000);
      expect(out.ok, isFalse);
      expect(out.error, contains('너무 큼'));
      expect(out.error, contains('200x100'));
    });
  });

  group('FoodPhotoService.compressForStorage', () {
    final service = FoodPhotoService.instance;
    final defaultPrimary = service.primaryCompressor;
    final defaultPlatform = service.platformCompressor;
    final logs = <String>[];

    /// [body] 동안만 debugPrint를 가로채 [logs]에 모은다(위젯 테스트는 본문이 끝나기 전에
    /// 원래 debugPrint로 되돌려야 해서 tearDown 대신 이 방식을 쓴다).
    Future<T> capturingLogs<T>(Future<T> Function() body) async {
      final original = debugPrint;
      logs.clear();
      debugPrint = (String? message, {int? wrapWidth}) => logs.add(message ?? '');
      try {
        return await body();
      } finally {
        debugPrint = original;
      }
    }

    tearDown(() {
      service.primaryCompressor = defaultPrimary;
      service.platformCompressor = defaultPlatform;
    });

    testWidgets('1차 압축이 실패하면 플랫폼 디코더로 다시 시도해 800px JPEG를 만든다', (tester) async {
      service.primaryCompressor = (_) async => const CompressOutcome.failure('테스트: HEIC라고 가정');
      final src = Uint8List.fromList(img.encodePng(twoTone(1600, 900)));

      final out = await capturingLogs(
        () => tester.runAsync(() => service.compressForStorage(src, sourceLabel: 'gallery.heic')),
      );

      expect(out, isNotNull, reason: logs.join('\n'));
      final decoded = img.decodeJpg(out!)!;
      expect([decoded.width, decoded.height], [800, 450]);
      expect(logs.any((l) => l.contains('1차 압축 실패') && l.contains('테스트: HEIC라고 가정')), isTrue);
      expect(logs.any((l) => l.contains('플랫폼 디코더로 변환 성공')), isTrue);
    });

    test('둘 다 실패하면 null을 돌려주고 각 실패 원인을 로그로 남긴다', () async {
      service.primaryCompressor = (_) async => const CompressOutcome.failure('원인 A');
      service.platformCompressor = (_) async => throw Exception('원인 B');

      final out = await capturingLogs(() => service.compressForStorage(heicHeader, sourceLabel: 'x.heic'));

      expect(out, isNull);
      expect(logs.any((l) => l.contains('원인 A')), isTrue);
      expect(logs.any((l) => l.contains('재시도도 실패') && l.contains('원인 B')), isTrue);
    });

    test('1차 압축이 성공하면 플랫폼 디코더는 호출하지 않는다', () async {
      var platformCalls = 0;
      service.platformCompressor = (_) async {
        platformCalls++;
        return const CompressOutcome.failure('호출되면 안 됨');
      };
      final src = Uint8List.fromList(img.encodeJpg(twoTone(100, 100)));

      final out = await capturingLogs(() => service.compressForStorage(src));

      expect(out, isNotNull);
      expect(platformCalls, 0);
    });
  });
}
