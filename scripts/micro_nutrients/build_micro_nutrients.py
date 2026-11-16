"""assets/nutrition/micro_nutrients.json 생성기.

foods.tsv(음식명 ↔ USDA FoodData Central 항목 대응표)를 읽고, USDA가 공개한 원본 CSV에서
8개 영양소의 100g당 값을 그대로 가져온다. 값을 손으로 적거나 보정하지 않는다 — 원본에
값이 없으면 null로 두고 missing 목록에 남긴다.

원본 데이터(공개, 퍼블릭 도메인 — https://fdc.nal.usda.gov/download-datasets):
  - FNDDS(Survey Foods) 2024-10-31: FoodData_Central_survey_food_csv_2024-10-31.zip
  - SR Legacy 2018-04:              FoodData_Central_sr_legacy_food_csv_2018-04.zip

사용법:
  python scripts/micro_nutrients/build_micro_nutrients.py <fndds_csv_dir> <sr_legacy_csv_dir>
"""
import csv
import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
TSV = ROOT / "scripts/micro_nutrients/foods.tsv"
OUT = ROOT / "assets/nutrition/micro_nutrients.json"

# JSON 키 ← (USDA nutrient.id, nutrient_nbr). 단위는 USDA 원본 그대로(µg/mg).
# SR Legacy의 food_nutrient.csv는 nutrient.id를, FNDDS는 nutrient_nbr를 nutrient_id 열에 쓴다.
NUTRIENT_CODES = {
    "vitaminD_ug": ("1114", "328"),    # Vitamin D (D2 + D3), µg
    "vitaminB12_ug": ("1178", "418"),  # Vitamin B-12, µg
    "vitaminA_ugRAE": ("1106", "320"), # Vitamin A, RAE, µg
    "vitaminC_mg": ("1162", "401"),    # Vitamin C, total ascorbic acid, mg
    "iron_mg": ("1089", "303"),        # Iron, Fe, mg
    "calcium_mg": ("1087", "301"),     # Calcium, Ca, mg
    "zinc_mg": ("1095", "309"),        # Zinc, Zn, mg
    "potassium_mg": ("1092", "306"),   # Potassium, K, mg
}
CODE_KEY = {
    "sr_legacy": {ids[0]: key for key, ids in NUTRIENT_CODES.items()},
    "fndds": {ids[1]: key for key, ids in NUTRIENT_CODES.items()},
}
NUTRIENTS = list(NUTRIENT_CODES)

SOURCES = {
    "fndds": {
        "name": "USDA FoodData Central — FNDDS (Survey Foods), release 2024-10-31",
        "url": "https://fdc.nal.usda.gov/download-datasets",
    },
    "sr_legacy": {
        "name": "USDA FoodData Central — SR Legacy, release 2018-04",
        "url": "https://fdc.nal.usda.gov/download-datasets",
    },
}


def load_dataset(dataset: str, csv_dir: pathlib.Path, wanted_ids: set[str]):
    descriptions = {}
    with open(csv_dir / "food.csv", encoding="utf-8") as f:
        for r in csv.DictReader(f):
            if r["fdc_id"] in wanted_ids:
                descriptions[r["fdc_id"]] = r["description"]
    values: dict[str, dict[str, float]] = {i: {} for i in wanted_ids}
    with open(csv_dir / "food_nutrient.csv", encoding="utf-8") as f:
        for r in csv.DictReader(f):
            fid = r["fdc_id"]
            key = CODE_KEY[dataset].get(r["nutrient_id"])
            if key and fid in values and r["amount"] != "":
                values[fid][key] = float(r["amount"])
    return descriptions, values


def main():
    dirs = {"fndds": pathlib.Path(sys.argv[1]), "sr_legacy": pathlib.Path(sys.argv[2])}
    rows = []
    for line in TSV.read_text(encoding="utf-8").splitlines():
        if not line.strip() or line.startswith("#"):
            continue
        ko, en, aliases, dataset, fdc_id, desc = line.split("\t")
        rows.append((ko, en, [a for a in aliases.split(";") if a], dataset, fdc_id, desc))

    loaded = {}
    for ds, d in dirs.items():
        ids = {r[4] for r in rows if r[3] == ds}
        loaded[ds] = load_dataset(ds, d, ids)

    foods, missing = [], []
    for ko, en, aliases, ds, fdc_id, desc in rows:
        descriptions, values = loaded[ds]
        if descriptions.get(fdc_id) != desc:
            raise SystemExit(f"대응표 불일치: {ko} fdc_id={fdc_id} 원본='{descriptions.get(fdc_id)}' 대응표='{desc}'")
        per100g = {key: values[fdc_id].get(key) for key in NUTRIENTS}
        for key, v in per100g.items():
            if v is None:
                missing.append(f"{ko} ({ds} {fdc_id} '{desc}'): {key}")
        foods.append({
            "ko": ko,
            "en": en,
            "aliases": aliases,
            "source": ds,
            "fdcId": int(fdc_id),
            "usdaDescription": desc,
            "per100g": per100g,
        })

    OUT.parent.mkdir(parents=True, exist_ok=True)
    data = {
        "version": 1,
        "note": "100g당 값. USDA FoodData Central 원본 값 그대로이며, 원본에 없는 값은 null이다.",
        "sources": SOURCES,
        "units": {k: k.split("_", 1)[1] for k in NUTRIENTS},
        "foods": foods,
    }
    OUT.write_text(json.dumps(data, ensure_ascii=False, indent=1) + "\n", encoding="utf-8", newline="\n")
    print(f"{len(foods)} foods → {OUT.relative_to(ROOT)}")
    print(f"missing values: {len(missing)}")
    for m in missing:
        print("  -", m)


if __name__ == "__main__":
    main()
