# CalSnap Gemini Proxy

Gemini API 키를 서버에만 보관하고, 클라이언트(CalSnap Flutter 앱)는 이 프록시만 호출하도록 하는 백엔드.

## API

### `POST /recognize`

요청 헤더
```
Content-Type: application/json
X-API-Key: <PROXY_API_KEY와 동일한 값, PROXY_API_KEY 설정 시 필수>
```

요청 바디
```json
{
  "image": "<base64 인코딩된 이미지, data URI 접두사(data:image/jpeg;base64,...) 허용>",
  "hint": "<선택, 사용자가 미리 적어둔 음식명 힌트, 최대 100자>",
  "language": "<선택, 기기 언어 코드(예: ko, en, ja). foodName만 이 언어로 응답, 최대 10자>"
}
```

성공 응답 (200)
```json
{ "foodName": "김치찌개", "caloriesPer100g": 90, "estimatedWeightG": 400, "carbsG": 6, "proteinG": 8, "fatG": 4 }
```

내부적으로 gemini-2.0-flash에 이미지와 함께
"이 사진 속 음식의 정확한 이름, 100g당 예상 칼로리(kcal), 추정 총 중량(g),
100g당 예상 탄수화물(g)/단백질(g)/지방(g)을 JSON으로만 답해줘:
{foodName, caloriesPer100g, estimatedWeightG, carbsG, proteinG, fatG}" 프롬프트를 보내고,
응답 텍스트를 그대로 파싱해서 돌려준다. carbsG/proteinG/fatG는 100g 기준 값이다.

`language`를 함께 보내면 foodName만 그 언어로 답하도록 프롬프트에 지시가 추가된다(지원하지
않는/알 수 없는 언어 코드면 영어로 폴백). caloriesPer100g 등 숫자 필드는 언어와 무관하다.
`hint`가 함께 오면 "힌트는 참고용일 뿐, 최종 응답 언어는 language를 따른다"는 지시도 추가된다.
기존에 저장된 로그의 foodName은 인식 당시 언어로 고정되며, 이후 언어를 바꿔도 소급 변경되지 않는다.

실패 응답: `{"error": "..."}` + 400(잘못된 요청)/401(인증 실패)/502(Gemini 호출 실패 또는 응답 파싱 실패)

### `GET /health`

Railway 헬스체크용. `{"status": "ok"}` 반환.

## 로컬 실행

```bash
cd backend
python -m venv .venv && . .venv/Scripts/activate   # Windows Git Bash
pip install -r requirements.txt
cp .env.example .env   # 값 채우기
export $(cat .env | xargs)   # 또는 .env 로더 사용
python app.py
```

## Gemini API 키 준비

1. https://aistudio.google.com/apikey 접속 후 Google 계정으로 로그인.
2. "Create API key"로 키 발급 (무료 티어로 시작 가능).
3. 발급받은 키를 `GEMINI_API_KEY` 환경변수 값으로 사용.
   (키를 코드/커밋에 직접 넣지 말 것 — `.env`는 `.gitignore`에 포함되어 있음.)

## Railway 배포

1. Railway에서 이 `backend/` 디렉터리를 루트로 새 프로젝트 생성 (Root Directory: `backend`).
2. `requirements.txt` + `Procfile`을 자동 인식해 Nixpacks로 빌드됨.
3. Variables 탭에 `GEMINI_API_KEY`, `PROXY_API_KEY` 등록.
4. 배포 완료 후 발급된 URL을 Flutter 쪽 `GeminiFoodRecognitionService`의
   `proxyBaseUrl`(`lib/services/gemini_food_recognition_service.dart`)에
   `--dart-define=PROXY_BASE_URL=...`로 반영.
