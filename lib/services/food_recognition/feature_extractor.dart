import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

/// MobileNetV2(TFLite, headless feature-vector 버전)로 이미지를 고정 길이
/// 특징벡터로 변환한다.
///
/// 모델 파일은 assets/models/mobilenet_v2_feature_extractor.tflite 에 위치해야 하며,
/// tools/build_embedding_db.py 로 참조 DB를 만들 때 사용한 것과 동일한 구조
/// (MobileNetV2, include_top=False, pooling=avg)여야 두 벡터 공간이 일치한다.
class FeatureExtractor {
  static const String modelAsset =
      'assets/models/mobilenet_v2_feature_extractor.tflite';
  static const int inputSize = 224;

  Interpreter? _interpreter;
  int _outputSize = 0;

  bool get isLoaded => _interpreter != null;

  Future<void> load() async {
    if (_interpreter != null) return;
    final interpreter = await Interpreter.fromAsset(modelAsset);
    _outputSize = interpreter.getOutputTensor(0).shape.last;
    _interpreter = interpreter;
  }

  /// 이미지를 [-1, 1] 범위로 정규화한 224x224 RGB 텐서로 변환 후 추론한다.
  Future<List<double>> extract(File imageFile) async {
    final interpreter = _interpreter;
    if (interpreter == null) {
      throw StateError('FeatureExtractor.load()를 먼저 호출해야 합니다.');
    }

    final decoded = img.decodeImage(await imageFile.readAsBytes());
    if (decoded == null) {
      throw ArgumentError('이미지를 디코딩할 수 없습니다: ${imageFile.path}');
    }
    final resized = img.copyResize(decoded, width: inputSize, height: inputSize);

    final input = [
      List.generate(
        inputSize,
        (y) => List.generate(inputSize, (x) {
          final pixel = resized.getPixel(x, y);
          return [
            (pixel.r / 127.5) - 1.0,
            (pixel.g / 127.5) - 1.0,
            (pixel.b / 127.5) - 1.0,
          ];
        }),
      ),
    ];

    final output = [List.filled(_outputSize, 0.0)];
    interpreter.run(input, output);
    return List<double>.from(output[0]);
  }

  void close() {
    _interpreter?.close();
    _interpreter = null;
  }
}
