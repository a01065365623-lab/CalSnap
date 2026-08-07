"""AI Hub 한국 음식 이미지 데이터셋으로 참조 임베딩 DB(assets/food_embeddings.json)를 생성하는 오프라인 스크립트.

사전 준비
  1) aihub.or.kr 계정으로 "한국 음식 이미지" 데이터셋을 직접 다운로드해 로컬에 압축 해제.
     디렉토리 구조 예: <DATASET_ROOT>/<음식명>/*.jpg  (폴더 하나 = 음식 클래스 하나)
  2) 온디바이스(Dart, lib/services/food_recognition/feature_extractor.dart)와 같은
     전처리·모델 구조를 써야 두 벡터 공간이 일치한다: MobileNetV2, include_top=False,
     pooling='avg', 입력 224x224, [-1, 1] 정규화.
  3) pip install tensorflow pillow numpy

사용법
  python tools/build_embedding_db.py \
      --dataset-root /path/to/aihub_korean_food \
      --calories-csv tools/food_calories.csv \
      --output assets/food_embeddings.json \
      --samples-per-class 5

각 클래스(폴더)마다 최대 --samples-per-class 장을 임베딩한 뒤 평균 벡터를 대표값으로 저장한다.
--calories-csv는 "foodName,caloriesPer100g" 2열 CSV (식약처 식품영양성분DB 등에서 직접 준비).
"""
import argparse
import csv
import json
import sys
from pathlib import Path

import numpy as np
import tensorflow as tf
from PIL import Image


def load_calorie_map(csv_path: Path) -> dict[str, float]:
    mapping: dict[str, float] = {}
    with csv_path.open(encoding="utf-8-sig") as f:
        reader = csv.reader(f)
        next(reader, None)  # header
        for row in reader:
            if len(row) < 2:
                continue
            mapping[row[0].strip()] = float(row[1])
    return mapping


def build_model() -> tf.keras.Model:
    return tf.keras.applications.MobileNetV2(
        input_shape=(224, 224, 3),
        include_top=False,
        weights="imagenet",
        pooling="avg",
    )


def preprocess(image_path: Path) -> np.ndarray:
    image = Image.open(image_path).convert("RGB").resize((224, 224))
    arr = np.asarray(image, dtype=np.float32)
    return (arr / 127.5) - 1.0  # Dart 쪽과 동일한 [-1, 1] 정규화


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dataset-root", required=True, type=Path)
    parser.add_argument("--calories-csv", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--samples-per-class", type=int, default=5)
    args = parser.parse_args()

    calorie_map = load_calorie_map(args.calories_csv)
    model = build_model()

    class_dirs = sorted(p for p in args.dataset_root.iterdir() if p.is_dir())
    if not class_dirs:
        sys.exit(f"클래스 폴더를 찾을 수 없습니다: {args.dataset_root}")

    entries = []
    for class_dir in class_dirs:
        food_name = class_dir.name
        if food_name not in calorie_map:
            print(f"[skip] {food_name}: calories-csv에 칼로리 정보 없음", file=sys.stderr)
            continue

        image_paths = sorted(class_dir.glob("*.jpg"))[: args.samples_per_class]
        if not image_paths:
            print(f"[skip] {food_name}: 이미지 없음", file=sys.stderr)
            continue

        batch = np.stack([preprocess(p) for p in image_paths])
        vectors = model.predict(batch, verbose=0)
        mean_vector = vectors.mean(axis=0)

        entries.append({
            "foodName": food_name,
            "caloriesPer100g": calorie_map[food_name],
            "vector": [round(float(x), 6) for x in mean_vector],
        })
        print(f"[ok] {food_name}: {len(image_paths)}장 -> {mean_vector.shape[0]}차원 벡터")

    args.output.write_text(
        json.dumps(entries, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    print(f"완료: {len(entries)}종 -> {args.output}")


if __name__ == "__main__":
    main()

# --- MobileNetV2 -> TFLite 변환 ---
# 온디바이스(Dart) 특징 추출기와 벡터 공간을 맞추려면 반드시 위 build_model()과
# 동일한 구조를 변환해야 한다:
#
#   converter = tf.lite.TFLiteConverter.from_keras_model(build_model())
#   tflite_model = converter.convert()
#   Path("assets/models/mobilenet_v2_feature_extractor.tflite").write_bytes(tflite_model)
