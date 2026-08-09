"""Gemini 프록시 백엔드.

CalSnap Flutter 앱의 HybridFoodRecognitionService가 온디바이스 매칭에 실패했을 때
호출하는 폴백 서버. Gemini API 키를 서버에만 보관해 클라이언트 바이너리에
키가 노출되지 않도록 한다.

환경변수
  GEMINI_API_KEY : Google AI Studio(https://aistudio.google.com/apikey)에서 발급받은
                    Gemini API 키 (무료 티어 가능).
  PROXY_API_KEY  : 클라이언트가 X-API-Key 헤더로 보내야 하는 공유 시크릿.
                    미설정 시 인증 없이 열려있으니 배포 전 반드시 설정할 것.
"""
import base64
import binascii
import json
import os

import google.generativeai as genai
from flask import Flask, jsonify, request

app = Flask(__name__)

_MAX_IMAGE_BYTES = 8 * 1024 * 1024  # 8MB
_PROXY_API_KEY = os.environ.get("PROXY_API_KEY")

_PROMPT = (
    "이 사진 속 음식의 정확한 이름과 100g당 예상 칼로리(kcal)를 JSON으로만 답해줘: "
    "{foodName, caloriesPer100g}"
)


def _init_model() -> genai.GenerativeModel:
    api_key = os.environ.get("GEMINI_API_KEY")
    if not api_key:
        raise RuntimeError("GEMINI_API_KEY 환경변수가 설정되지 않았습니다.")
    genai.configure(api_key=api_key)
    return genai.GenerativeModel("gemini-1.5-flash")


_model = _init_model()


def _parse_food_json(text: str) -> dict | None:
    cleaned = text.strip()
    if cleaned.startswith("```"):
        # ```json { ... } ``` 형태의 코드펜스로 감싸서 오는 경우 제거
        cleaned = cleaned.strip("`").strip()
        if cleaned.lower().startswith("json"):
            cleaned = cleaned[4:].strip()

    try:
        data = json.loads(cleaned)
    except (json.JSONDecodeError, TypeError):
        return None

    if not isinstance(data, dict) or "foodName" not in data or "caloriesPer100g" not in data:
        return None

    return {"foodName": data["foodName"], "caloriesPer100g": data["caloriesPer100g"]}


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

    try:
        response = _model.generate_content(
            [_PROMPT, {"mime_type": "image/jpeg", "data": image_bytes}]
        )
    except Exception as exc:  # Gemini SDK의 다양한 예외를 502로 통일해 전달
        return jsonify(error=f"Gemini 호출 실패: {exc}"), 502

    parsed = _parse_food_json(response.text or "")
    if parsed is None:
        return jsonify(error=f"Gemini 응답 파싱 실패: {response.text!r}"), 502

    return jsonify(parsed)


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", 8080)))
