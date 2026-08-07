# CalSnap 아키텍처 & 화면설계

## 1. 모드 구조
1. **빠른모드 (Quick)** — 사진 1장 → AI 카테고리 추정 → 슬라이더로 양 보정 → 저장
2. **정밀모드 (Precision)** — 2장(위/측면) + 기준객체 → 더 정확한 부피 추정 (1차 출시 제외, 추후 업데이트)
3. **데일리로그 (Daily Log)** — 음식/운동/물을 하나의 타임라인에 통합, 하루 마감 시 순칼로리(섭취-소모) 표시

1차 출시(한국 단일 시장) 범위: **빠른모드 + 데일리로그모드만 포함.** 정밀모드는 스텁만 만들어두고 추후 활성화.

## 2. 화면 흐름
```
HomeScreen (BottomNavigationBar)
 ├─ QuickModeScreen      : 카메라/갤러리 → AI 인식 → 보정 슬라이더 → 저장
 ├─ DailyLogScreen        : 오늘 타임라인 (음식/운동/물), 하루 요약 카드
 ├─ StatsScreen           : 주간/월간/연간 그래프 (fl_chart)
 └─ SettingsScreen        : 목표 칼로리 설정, 단위, 제휴 쇼핑 링크 설정
```

## 3. DB 스키마 (SQLite, sqflite)

```sql
-- 통합 로그: 음식/운동/물 전부 하나의 타임라인
CREATE TABLE daily_log (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  datetime TEXT NOT NULL,       -- ISO8601
  type TEXT NOT NULL,           -- 'food' | 'exercise' | 'water'
  name TEXT NOT NULL,
  calories REAL NOT NULL,       -- food: +, exercise: -, water: 0
  amount REAL,                  -- g, 분, ml 등
  mode TEXT                     -- 'quick' | 'precision' (food only)
);

-- 하루 단위 집계 (자정 배치 or on-write 갱신)
CREATE TABLE daily_summary (
  date TEXT PRIMARY KEY,        -- yyyy-MM-dd
  total_intake REAL DEFAULT 0,
  total_burned REAL DEFAULT 0,
  net_calories REAL DEFAULT 0
);
```

사진 원본은 저장하지 않음(용량 절약, 1년치 텍스트 로그만 유지) — 사용자 결정 사항.

## 4. 폴더 구조
```
lib/
 ├─ main.dart
 ├─ models/
 │   └─ daily_log_entry.dart
 ├─ db/
 │   └─ database_helper.dart
 ├─ services/
 │   ├─ food_recognition_service.dart   # AI 사진 인식 (추후 API 연동)
 │   ├─ nutrition_api_service.dart      # 식약처 식품영양성분DB 연동
 │   └─ affiliate_service.dart          # 쿠팡/스마트스토어/아마존 딥링크 (웨디 코드 재사용)
 ├─ screens/
 │   ├─ home_screen.dart
 │   ├─ quick_mode_screen.dart
 │   ├─ precision_mode_screen.dart      # 1차 출시 제외, 스텁만
 │   ├─ daily_log_screen.dart
 │   ├─ stats_screen.dart
 │   └─ settings_screen.dart
 └─ widgets/
     ├─ log_entry_tile.dart
     └─ shop_button.dart                # 웨디 _ShopBtn/confirmLink 패턴 이식
```

## 5. 다음 작업 우선순위 (한국 1차 출시 기준)
1. `nutrition_api_service.dart` — 식약처 식품영양성분DB 실제 연동
2. `food_recognition_service.dart` — AI 인식 API 선정 및 연동 (Google Cloud Vision / Clarifai / 자체 모델)
3. QuickModeScreen 실제 카메라 캡처 + 보정 UI 완성
4. DailyLogScreen 타임라인 UI + daily_summary 자동 집계 로직
5. affiliate_service — 웨디의 confirmLink 바텀시트 방식 그대로 이식
