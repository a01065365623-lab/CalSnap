import 'dart:convert';

import 'package:calsnap/services/food_photo_service.dart';
import 'package:calsnap/services/food_recognition_service.dart';
import 'package:calsnap/utils/image_compress.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
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

List<int> sizeOf(Uint8List jpeg) {
  final d = img.decodeJpg(jpeg)!;
  return [d.width, d.height];
}

/// backend/app.py의 사진 캐시 키와 같은 방식: sha256(json(["photo", sha256(image), hint, language])).
String serverPhotoCacheKey(Uint8List uploadJpeg, String? hint, String language) {
  final imageHash = sha256.convert(uploadJpeg).toString();
  return sha256.convert(utf8.encode(jsonEncode(['photo', imageHash, hint, language]))).toString();
}

void main() {
  group('encodeFoodPhotoFromEncoded (한 번 디코딩 → 저장용·업로드용)', () {
    test('저장용은 긴 변 800px, 업로드용은 768px로 함께 만든다', () {
      final src = Uint8List.fromList(img.encodePng(twoTone(1600, 1200)));
      final out = encodeFoodPhotoFromEncoded(src);
      expect(out.ok, isTrue, reason: out.error);
      expect(sizeOf(out.storageJpeg!), [800, 600]);
      expect(sizeOf(out.uploadJpeg!), [768, 576]);
    });

    test('작은 사진은 키우지 않는다', () {
      final src = Uint8List.fromList(img.encodePng(twoTone(400, 300)));
      final out = encodeFoodPhotoFromEncoded(src);
      expect(sizeOf(out.storageJpeg!), [400, 300]);
      expect(sizeOf(out.uploadJpeg!), [400, 300]);
    });

    test('EXIF 회전(6 = 시계 방향 90°)을 두 결과 모두에 반영하고 회전 태그는 남기지 않는다', () {
      final src = withExifOrientation(Uint8List.fromList(img.encodeJpg(twoTone(400, 200), quality: 95)), 6);
      // 전제: 입력 JPEG에 APP1 Exif 블록이 실제로 들어 있다(회전 태그 6).
      expect(src.sublist(2, 4), [0xff, 0xe1]);

      final out = encodeFoodPhotoFromEncoded(src);
      expect(out.ok, isTrue, reason: out.error);
      for (final jpeg in [out.storageJpeg!, out.uploadJpeg!]) {
        final decoded = img.decodeJpg(jpeg)!;
        expect([decoded.width, decoded.height], [200, 400], reason: '가로 사진이 세로로 돌아가야 함');
        expect(decoded.exif.imageIfd.hasOrientation, isFalse, reason: '뷰어가 한 번 더 돌리지 않게');
        // 시계 방향 90°: 원본 왼쪽(빨강)이 위로 온다.
        expect(decoded.getPixel(100, 20).r, greaterThan(200));
        expect(decoded.getPixel(100, 380).b, greaterThan(200));
      }
    });

    test('HEIC처럼 image 패키지가 모르는 형식은 원인(헤더 포함)을 담아 실패한다', () {
      final out = encodeFoodPhotoFromEncoded(heicHeader);
      expect(out.ok, isFalse);
      expect(out.error, contains('지원하지 않는 형식'));
      expect(out.error, contains('66 74 79 70'), reason: "헤더('ftyp')가 로그에 남아야 원인 파악 가능");
    });

    test('픽셀 수가 한도를 넘는 큰 사진은 디코딩하지 않고 실패로 돌린다', () {
      final src = Uint8List.fromList(img.encodeJpg(twoTone(200, 100)));
      final out = encodeFoodPhotoFromEncoded(src, maxDecodePixels: 10000);
      expect(out.ok, isFalse);
      expect(out.error, contains('너무 큼'));
      expect(out.error, contains('200x100'));
    });

    test('같은 사진이면 업로드 바이트가 같아 서버 캐시 키(sha256)도 같다', () {
      final src = Uint8List.fromList(img.encodeJpg(twoTone(1600, 1200), quality: 92));
      final a = encodeFoodPhotoFromEncoded(src).uploadJpeg!;
      final b = encodeFoodPhotoFromEncoded(Uint8List.fromList(src)).uploadJpeg!;
      expect(a, b);
      expect(serverPhotoCacheKey(a, null, 'ko'), serverPhotoCacheKey(b, null, 'ko'));
    });
  });

  group('FoodPhotoService.prepareBytes', () {
    final service = FoodPhotoService.instance;
    final defaultPrimary = service.primaryEncoder;
    final defaultPlatform = service.platformEncoder;
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
      service.primaryEncoder = defaultPrimary;
      service.platformEncoder = defaultPlatform;
    });

    testWidgets('1차 디코딩이 실패하면 플랫폼 디코더로 한 번 디코딩해 두 규격을 만들고, 시간·크기를 남긴다',
        (tester) async {
      service.primaryEncoder = (_) async => const DualJpegOutcome.failure('테스트: HEIC라고 가정');
      final src = Uint8List.fromList(img.encodePng(twoTone(1600, 900)));

      final prepared = await capturingLogs(
        () => tester.runAsync(() => service.prepareBytes(src, sourceLabel: 'gallery.heic')),
      );

      expect(prepared, isNotNull, reason: logs.join('\n'));
      expect(prepared!.decoder, '플랫폼 디코더');
      expect(sizeOf(prepared.storageJpeg), [800, 450]);
      expect(sizeOf(prepared.uploadJpeg), [768, 432]);
      expect(logs.any((l) => l.contains('1차 디코딩 실패') && l.contains('테스트: HEIC라고 가정')), isTrue);
      final done = logs.singleWhere((l) => l.contains('사진 변환 완료'));
      expect(done, contains('플랫폼 디코더'));
      expect(done, matches(RegExp(r'\d+ms')));
      expect(done, contains('업로드 ${prepared.uploadJpeg.length}B'));
      expect(done, contains('저장 ${prepared.storageJpeg.length}B'));
    });

    testWidgets('플랫폼 디코더 경로도 같은 사진이면 같은 업로드 바이트(=같은 캐시 키)를 만든다', (tester) async {
      service.primaryEncoder = (_) async => const DualJpegOutcome.failure('HEIC');
      final src = Uint8List.fromList(img.encodePng(twoTone(1200, 1600)));

      final a = await capturingLogs(() => tester.runAsync(() => service.prepareBytes(src)));
      final b = await capturingLogs(() => tester.runAsync(() => service.prepareBytes(src)));

      expect(a!.uploadJpeg, b!.uploadJpeg);
      expect(serverPhotoCacheKey(a.uploadJpeg, '김밥', 'ko'), serverPhotoCacheKey(b.uploadJpeg, '김밥', 'ko'));
    });

    test('둘 다 실패하면 null(원본으로 폴백하지 않음)이고 각 실패 원인을 로그로 남긴다', () async {
      service.primaryEncoder = (_) async => const DualJpegOutcome.failure('원인 A');
      service.platformEncoder = (_) async => throw Exception('원인 B');

      final prepared = await capturingLogs(() => service.prepareBytes(heicHeader, sourceLabel: 'x.heic'));

      expect(prepared, isNull);
      expect(logs.any((l) => l.contains('원인 A')), isTrue);
      expect(logs.any((l) => l.contains('재시도도 실패') && l.contains('원인 B') && l.contains('사진을 읽을 수 없음')), isTrue);
    });

    test('1차 디코딩이 성공하면 플랫폼 디코더는 호출하지 않는다(디코딩 1회)', () async {
      var platformCalls = 0;
      service.platformEncoder = (_) async {
        platformCalls++;
        return const DualJpegOutcome.failure('호출되면 안 됨');
      };
      final src = Uint8List.fromList(img.encodeJpg(twoTone(100, 100)));

      final prepared = await capturingLogs(() => service.prepareBytes(src));

      expect(prepared, isNotNull);
      expect(prepared!.decoder, 'image 패키지');
      expect(platformCalls, 0);
    });
  });

  test('사진을 읽지 못하면 "사진을 읽을 수 없어요" 안내로 매핑된다', () {
    final l10n = lookupAppLocalizations(const Locale('ko'));
    const e = FoodRecognitionException(FoodRecognitionFailure.unreadablePhoto, 'decode failed');
    expect(friendlyRecognitionErrorMessage(l10n, e), l10n.recognitionErrorUnreadablePhoto);
    expect(l10n.recognitionErrorUnreadablePhoto, startsWith('사진을 읽을 수 없어요'));
  });
}
