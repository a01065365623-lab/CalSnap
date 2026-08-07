# CalSnap Vision Proxy

Cloud Vision API 키를 서버에만 보관하고, 클라이언트(CalSnap Flutter 앱)는 이 프록시만 호출하도록 하는 백엔드.

## API

### `POST /recognize`

요청 헤더
```
Content-Type: application/json
X-API-Key: <PROXY_API_KEY와 동일한 값, PROXY_API_KEY 설정 시 필수>
```

요청 바디
```json
{ "image": "<base64 인코딩된 이미지, data URI 접두사(data:image/jpeg;base64,...) 허용>" }
```

성공 응답 (200)
```json
{
  "labels": [
    { "description": "Kimchi stew", "score": 0.9123 },
    { "description": "Food", "score": 0.8765 }
  ]
}
```

실패 응답: `{"error": "..."}` + 400(잘못된 요청)/401(인증 실패)/502(Cloud Vision 호출 실패)

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

## GCP 서비스 계정 준비

1. GCP 콘솔에서 프로젝트 생성 후 **Cloud Vision API** 활성화.
2. IAM > 서비스 계정 생성, "Cloud Vision API 사용자" 역할 부여.
3. 키(JSON) 발급 후, 파일 내용 전체를 `GOOGLE_APPLICATION_CREDENTIALS_JSON` 환경변수 값으로 사용.
   (파일 자체를 커밋하지 말 것 — `backend/*.json`은 `.gitignore`에 포함되어 있음.)

## Railway 배포

1. Railway에서 이 `backend/` 디렉터리를 루트로 새 프로젝트 생성 (Root Directory: `backend`).
2. `requirements.txt` + `Procfile`을 자동 인식해 Nixpacks로 빌드됨.
3. Variables 탭에 `GOOGLE_APPLICATION_CREDENTIALS_JSON`, `PROXY_API_KEY` 등록.
4. 배포 완료 후 발급된 URL을 Flutter 쪽 `CloudVisionFoodRecognitionService`의
   `proxyBaseUrl`(`lib/services/cloud_vision_food_recognition_service.dart`)에 반영.
   현재 그 파일은 `/vision/food` 멀티파트 계약으로 되어 있어 이 `/recognize`
   base64 JSON 계약과 다르므로, 클라이언트 쪽도 맞춰서 수정이 필요함.
