"""Gemini 프록시 백엔드.

CalSnap Flutter 앱(GeminiFoodRecognitionService)이 사진 기반/텍스트 기반 음식 인식을
위해 호출하는 서버. Gemini API 키를 서버에만 보관해 클라이언트 바이너리에 키가
노출되지 않도록 한다.

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
    "이 사진 속 음식의 정확한 이름, 100g당 예상 칼로리(kcal), 추정 총 중량(g), "
    "100g당 예상 탄수화물(g)/단백질(g)/지방(g)을 JSON으로만 답해줘: "
    "{foodName, caloriesPer100g, estimatedWeightG, carbsG, proteinG, fatG}. "
    "사진에 여러 음식이 있으면 각각의 이름·칼로리·중량·탄단지를 모두 파악해서 "
    "칼로리·중량·탄수화물·단백질·지방을 각각 합산한 뒤, 대표 이름(예: '목살 스테이크 정식')과 "
    "합산 칼로리(caloriesPer100g), 합산 중량(estimatedWeightG), "
    "합산 탄수화물(carbsG)/단백질(proteinG)/지방(fatG)을 이 JSON 형식으로 답해줘. "
    "리조또와 아란치니처럼 조리법이 다른 유사 음식을 헷갈리지 않도록, "
    "재료·조리 형태·모양을 꼼꼼히 살펴 최대한 구체적인 이름으로 답해줘."
)


_TEXT_PROMPT = (
    "사용자가 사진 없이 음식 이름과 양을 직접 입력했어. 이 정보만으로 100g당 예상 "
    "칼로리(kcal), 입력된 양을 그램(g)으로 환산한 추정 총 중량, 100g당 예상 "
    "탄수화물(g)/단백질(g)/지방(g)을 JSON으로만 답해줘: "
    "{foodName, caloriesPer100g, estimatedWeightG, carbsG, proteinG, fatG}. "
    "foodName은 사용자가 입력한 이름을 더 명확하게 다듬어서(오탈자 교정 등) 반환해줘. "
    "estimatedWeightG는 사용자가 입력한 '양+단위'를 그 음식의 일반적인 밀도/구성을 "
    "고려해 그램(g) 단위로 환산한 값이어야 해(예: 단위가 'piece'면 그 음식 1개의 "
    "평균 중량 x 개수, 'serving'이면 일반적인 1인분 중량 x 인분 수, 'ml'이면 그 "
    "음식의 비중을 고려해 g으로 환산, 'g'이면 입력값을 그대로 사용)."
)


def _build_text_prompt(food_name: str, amount: float, unit: str, language: str | None) -> str:
    unit_label = {"g": "그램(g)", "ml": "밀리리터(ml)", "serving": "인분", "piece": "개"}.get(
        unit, unit
    )
    prompt = (
        f"{_TEXT_PROMPT} 사용자 입력 — 음식 이름: '{food_name}', 양: {amount}{unit_label}."
    )
    if language:
        prompt += (
            f" 응답 중 foodName 값은 반드시 언어 코드 '{language}'에 해당하는 언어로 답해줘. "
            "이 언어 코드를 모르거나 지원하지 않는다면 영어로 답해줘. "
            "caloriesPer100g, estimatedWeightG, carbsG, proteinG, fatG는 언어와 무관하게 "
            "숫자만 그대로 반환하고, 단위나 설명 문구는 붙이지 마."
        )
    return prompt


def _build_prompt(hint: str | None, language: str | None) -> str:
    prompt = _PROMPT

    if language:
        prompt += (
            f" 응답 중 foodName 값은 반드시 언어 코드 '{language}'에 해당하는 언어로 답해줘. "
            "이 언어 코드를 모르거나 지원하지 않는다면 영어로 답해줘. "
            "caloriesPer100g, estimatedWeightG, carbsG, proteinG, fatG는 언어와 무관하게 "
            "숫자만 그대로 반환하고, 단위나 설명 문구는 붙이지 마."
        )

    if hint:
        prompt += (
            f" 사용자가 제공한 음식명 힌트: {hint}. 이 정보를 참고해서 정확한 이름과 "
            "칼로리를 답해줘. 사진과 힌트가 명백히 다르면 사진을 우선해줘."
        )
        if language:
            prompt += (
                " 힌트가 어떤 언어로 적혀 있든 그건 참고용일 뿐이고, foodName의 최종 응답 "
                f"언어는 위에서 지정한 '{language}'를 그대로 따라야 해(힌트 언어로 답하지 마)."
            )

    return prompt


def _init_model() -> genai.GenerativeModel:
    api_key = os.environ.get("GEMINI_API_KEY")
    if not api_key:
        raise RuntimeError("GEMINI_API_KEY 환경변수가 설정되지 않았습니다.")
    genai.configure(api_key=api_key)
    return genai.GenerativeModel("gemini-flash-latest")


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

    required_keys = ("foodName", "caloriesPer100g", "estimatedWeightG")
    if not isinstance(data, dict) or not all(key in data for key in required_keys):
        return None

    return {
        "foodName": data["foodName"],
        "caloriesPer100g": data["caloriesPer100g"],
        "estimatedWeightG": data["estimatedWeightG"],
        # 탄단지는 구형 프롬프트 응답과의 호환을 위해 없으면 0으로 채운다.
        "carbsG": data.get("carbsG", 0),
        "proteinG": data.get("proteinG", 0),
        "fatG": data.get("fatG", 0),
    }


@app.get("/health")
def health():
    return jsonify(status="ok")


@app.get("/models")
def list_models():
    """디버그용: 이 GEMINI_API_KEY로 실제 사용 가능한 모델 목록을 조회한다."""
    if _PROXY_API_KEY and request.headers.get("X-API-Key") != _PROXY_API_KEY:
        return jsonify(error="unauthorized"), 401

    try:
        models = [
            {
                "name": m.name,
                "supported_generation_methods": list(m.supported_generation_methods),
            }
            for m in genai.list_models()
        ]
    except Exception as exc:
        return jsonify(error=f"모델 목록 조회 실패: {exc}"), 502

    return jsonify(models=models)


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

    hint = payload.get("hint")
    if not isinstance(hint, str):
        hint = None
    else:
        hint = hint.strip()[:100] or None

    language = payload.get("language")
    if not isinstance(language, str):
        language = None
    else:
        # 언어 코드는 짧다(예: "ko", "zh-Hant") — 프롬프트에 그대로 삽입되므로 길이를
        # 넉넉히 제한해 이상한 입력이 프롬프트를 부풀리는 걸 막는다.
        language = language.strip()[:10] or None

    try:
        response = _model.generate_content(
            [_build_prompt(hint, language), {"mime_type": "image/jpeg", "data": image_bytes}]
        )
    except Exception as exc:  # Gemini SDK의 다양한 예외를 502로 통일해 전달
        return jsonify(error=f"Gemini 호출 실패: {exc}"), 502

    parsed = _parse_food_json(response.text or "")
    if parsed is None:
        return jsonify(error=f"Gemini 응답 파싱 실패: {response.text!r}"), 502

    return jsonify(parsed)


@app.post("/recognize-text")
def recognize_text():
    """빠른측정모드 "직접 입력" 경로: 사진 없이 음식 이름+양만으로 추정한다."""
    if _PROXY_API_KEY and request.headers.get("X-API-Key") != _PROXY_API_KEY:
        return jsonify(error="unauthorized"), 401

    payload = request.get_json(silent=True)
    if not payload:
        return jsonify(error="요청 본문이 필요합니다."), 400

    food_name = payload.get("foodName")
    if not isinstance(food_name, str) or not food_name.strip():
        return jsonify(error="'foodName' 필드(문자열)가 필요합니다."), 400
    food_name = food_name.strip()[:100]

    amount = payload.get("amount")
    if not isinstance(amount, (int, float)) or amount <= 0:
        return jsonify(error="'amount' 필드(0보다 큰 숫자)가 필요합니다."), 400

    unit = payload.get("unit")
    if unit not in ("g", "ml", "serving", "piece"):
        return jsonify(error="'unit' 필드는 g/ml/serving/piece 중 하나여야 합니다."), 400

    language = payload.get("language")
    if not isinstance(language, str):
        language = None
    else:
        language = language.strip()[:10] or None

    try:
        response = _model.generate_content(
            _build_text_prompt(food_name, amount, unit, language)
        )
    except Exception as exc:  # Gemini SDK의 다양한 예외를 502로 통일해 전달
        return jsonify(error=f"Gemini 호출 실패: {exc}"), 502

    parsed = _parse_food_json(response.text or "")
    if parsed is None:
        return jsonify(error=f"Gemini 응답 파싱 실패: {response.text!r}"), 502

    return jsonify(parsed)


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", 8080)))
