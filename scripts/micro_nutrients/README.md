# 비타민·미네랄 데이터 (`assets/nutrition/micro_nutrients.json`)

오늘의 로그 "비타민·미네랄" 카드가 쓰는 100g당 영양소 값이다. 값은 손으로 적지 않고,
`build_micro_nutrients.py`가 USDA 원본 CSV에서 그대로 가져온다.

## 출처

| dataset | 이름 | 내려받기 |
|---|---|---|
| `fndds` | USDA FoodData Central — FNDDS(Survey Foods), release 2024-10-31 | https://fdc.nal.usda.gov/download-datasets (`FoodData_Central_survey_food_csv_2024-10-31.zip`) |
| `sr_legacy` | USDA FoodData Central — SR Legacy, release 2018-04 | https://fdc.nal.usda.gov/download-datasets (`FoodData_Central_sr_legacy_food_csv_2018-04.zip`) |

USDA FoodData Central 자료는 퍼블릭 도메인(CC0)이다.

식약처 식품영양성분 DB는 아직 들어 있지 않다. 공공데이터포털의 통합 자료집(15047698)은
`various.foodsafetykorea.go.kr/nutrient/`로 연결만 되어 있어 스크립트로 받을 수 없었다(사이트에서
직접 내려받거나 공공데이터포털 API 키가 필요). 받으면 `foods.tsv`에 `mfds` dataset을 추가해 합치면 된다.

## 다시 만들기

```bash
python scripts/micro_nutrients/build_micro_nutrients.py \
  <압축 푼 FoodData_Central_survey_food_csv_2024-10-31 폴더> \
  <압축 푼 FoodData_Central_sr_legacy_food_csv_2018-04 폴더>
```

- `foods.tsv`: 음식명(한/영/별칭) ↔ USDA 항목(`fdc_id` + description) 1:1 대응표. description이
  원본과 다르면 빌드가 멈춘다.
- 원본에 값이 없는 영양소는 `null`로 둔다(앱에서는 그 영양소만 합산하지 않는다).

## 대응 원칙

- USDA에 같은 음식이 있을 때만 넣었다. 비슷하지만 다른 음식(예: 명란 ≠ caviar, 순대 ≠ blood sausage,
  어묵 ≠ fish cake/patty, 된장 ≠ miso, 깐풍기 ≠ General Tso chicken)은 넣지 않았다.
- 같은 음식은 없지만 가장 가까운 USDA 항목으로 대신한 15개는 `foods.tsv` 마지막 열과 JSON에
  `approx: true`로 표시한다. 이런 음식이 합산에 들어가면 카드에 "일부는 비슷한 음식 값으로 계산했어요"가 붙는다.
  라면(ramen soup), 돈까스(coated pork chop), 탕수육(sweet and sour pork), 김(dried seaweed),
  단무지(pickled radishes), 볶음면(lo mein), 군만두·찐만두(wonton/pot sticker), 족발(pig's feet),
  밀크티(bubble tea), 단호박(pumpkin), 애호박(green summer squash), 대파(green onions),
  볶음밥(fried rice, NFS), 치킨(coated fried chicken breast).
- 김치찌개·된장찌개·김밥·잡채·불고기·삼계탕·냉면·짜장면처럼 USDA에 없는 한식은 비워 두었다
  (매칭되지 않으면 앱에서 "영양 정보 없음"으로 센다).

## 원본에 값이 없는 항목 (null)

| 음식 | USDA 항목 | 없는 영양소 |
|---|---|---|
| 삼겹살 | SR 167812 Pork, fresh, belly, raw | 비타민 D |
| 명태 | SR 173726 Fish, pollock, Alaska, cooked | 비타민 D, B12, A, C |
| 팽이버섯 | SR 169382 Mushrooms, enoki, raw | 비타민 A |
| 대추 | SR 168151 Jujube, raw | 비타민 D |
| 방어 | SR 174248 Fish, yellowtail, mixed species, cooked, dry heat | 비타민 D |
| 농어 | SR 173694 Fish, sea bass, mixed species, cooked, dry heat | 비타민 D |
