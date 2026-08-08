"""Cloud Vision 프록시 백엔드.

CalSnap Flutter 앱의 HybridFoodRecognitionService가 온디바이스 매칭에 실패했을 때
호출하는 폴백 서버. Google Cloud Vision API 키를 서버에만 보관해 클라이언트
바이너리에 키가 노출되지 않도록 한다.

환경변수
  GOOGLE_APPLICATION_CREDENTIALS_JSON : GCP 서비스 계정 키 JSON 전체 내용
                                         (Railway 등 파일 마운트가 어려운 환경을 위해 문자열로 받음)
  PROXY_API_KEY                       : 클라이언트가 X-API-Key 헤더로 보내야 하는 공유 시크릿.
                                         미설정 시 인증 없이 열려있으니 배포 전 반드시 설정할 것.
"""
import base64
import binascii
import json
import os

from flask import Flask, jsonify, request
from google.cloud import vision
from google.oauth2 import service_account

app = Flask(__name__)

_MAX_IMAGE_BYTES = 8 * 1024 * 1024  # 8MB
_PROXY_API_KEY = os.environ.get("PROXY_API_KEY")


def _init_vision_client() -> vision.ImageAnnotatorClient:
    creds_json = os.environ.get("GOOGLE_APPLICATION_CREDENTIALS_JSON")
    if not creds_json:
        raise RuntimeError(
            "GOOGLE_APPLICATION_CREDENTIALS_JSON 환경변수가 설정되지 않았습니다."
        )
    info = json.loads(creds_json)
    credentials = service_account.Credentials.from_service_account_info(info)
    return vision.ImageAnnotatorClient(credentials=credentials)


_vision_client = _init_vision_client()


@app.get("/health")
def health():
    return jsonify(status="ok")


@app.post("/recognize")
def recognize():
    if _PROXY_API_KEY and request.headers.get("X-API-Key") != _PROXY_API_KEY:
        return jsonify(error="unauthorized"), 401

    payload = request.get_json(silent=True)
    if not payload or "image" not in payload:
        return jsonify(error="'image' 필드(base64 문자열)가 필요합니다."), 400

    raw_b64 = payload["image"]
    if isinstance(raw_b64, str) and raw_b64.strip().startswith("data:") and "," in raw_b64:
        raw_b64 = raw_b64.split(",", 1)[1]  # data:image/jpeg;base64,... 형태 허용

    try:
        image_bytes = base64.b64decode(raw_b64, validate=True)
    except (binascii.Error, ValueError, TypeError):
        return jsonify(error="base64 디코딩 실패"), 400

    if not image_bytes:
        return jsonify(error="빈 이미지입니다."), 400
    if len(image_bytes) > _MAX_IMAGE_BYTES:
        return jsonify(error="이미지가 너무 큽니다 (최대 8MB)."), 400

    image = vision.Image(content=image_bytes)
    try:
        response = _vision_client.label_detection(image=image)
    except Exception as exc:  # Vision SDK의 다양한 예외를 502로 통일해 전달
        return jsonify(error=f"Cloud Vision 호출 실패: {exc}"), 502

    if response.error.message:
        return jsonify(error=f"Cloud Vision 오류: {response.error.message}"), 502

    labels = [
        {"description": ann.description, "score": round(ann.score, 4)}
        for ann in response.label_annotations
    ]

    return jsonify(labels=labels)


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", 8080)))
