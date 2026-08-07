# mobilenet_v2_feature_extractor.tflite

이 폴더에 온디바이스 특징 추출용 MobileNetV2 TFLite 모델을 넣어야 합니다.

- 파일명: `mobilenet_v2_feature_extractor.tflite`
- 요구 사항: 분류 헤드(top)를 제거하고 GlobalAveragePooling을 적용한
  "feature vector" 버전이어야 합니다 (예: 1280차원 임베딩 출력).
- `tools/build_embedding_db.py` 하단 주석의 변환 스니펫을 참고해
  동일한 구조(MobileNetV2, include_top=False, pooling=avg)로 변환하세요.
  참조 임베딩 DB(assets/food_embeddings.json)를 만들 때 쓴 것과
  반드시 같은 모델이어야 코사인 유사도 비교가 의미를 가집니다.
