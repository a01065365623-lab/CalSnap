"""Gemini 프록시 백엔드.

CalSnap Flutter 앱(GeminiFoodRecognitionService)이 사진 기반/텍스트 기반 음식 인식을
위해 호출하는 서버. Gemini API 키를 서버에만 보관해 클라이언트 바이너리에 키가
노출되지 않도록 한다.

환경변수
  GEMINI_API_KEY : Google AI Studio(https://aistudio.google.com/apikey)에서 발급받은
                    Gemini API 키 (무료 티어 가능).
  GEMINI_MODEL   : 사용할 Gemini 모델 ID(기본 gemini-3.8-flash). 'gemini-flash-latest' 같은
                    별칭은 새 모델이 나오면 예고 없이 바뀌어 응답 형식·품질이 흔들릴 수 있어서,
                    기본값은 정식(stable) 버전명으로 고정한다.
  PROXY_API_KEY  : 클라이언트가 X-API-Key 헤더로 보내야 하는 공유 시크릿.
                    미설정 시 인증 없이 열려있으니 배포 전 반드시 설정할 것.
  DATABASE_URL   : 일일 사용 횟수 카운터를 저장할 PostgreSQL 접속 URL(Railway Postgres
                    플러그인을 붙이면 자동 주입). 미설정/접속 실패 시 메모리 카운터로
                    대체되며, 그 경우 서버 재시작 시 카운트가 초기화된다.
  DAILY_LIMIT_PHOTO : 기기(X-User-Id)당 하루 사진 인식(/recognize) 허용 횟수(기본 3).
  DAILY_LIMIT_TEXT  : 기기당 하루 직접 입력 추정(/recognize-text) 허용 횟수(기본 20).
  DAILY_LIMIT_PHOTO_PREMIUM : 구독자용 하루 사진 인식 횟수(기본 30). 구독 기능 연결 전이라
                    아직 사용하지 않는다.
  CACHE_MAX_ENTRIES : 동일 요청 응답 캐시 최대 항목 수(기본 5000).
  한도는 0 이하로 설정하면 제한하지 않는다. 날짜 경계는 한국시간(KST) 자정.
"""
import base64
import binascii
import collections
import datetime
import hashlib
import json
import logging
import os
import threading
import time

import google.generativeai as genai
from google.api_core.exceptions import GoogleAPICallError, ResourceExhausted
from flask import Flask, jsonify, request

app = Flask(__name__)

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
logger = logging.getLogger("calsnap-proxy")

_MAX_IMAGE_BYTES = 8 * 1024 * 1024  # 8MB
_PROXY_API_KEY = os.environ.get("PROXY_API_KEY")
_DAILY_LIMITS = {
    "photo": int(os.environ.get("DAILY_LIMIT_PHOTO", "3")),
    "text": int(os.environ.get("DAILY_LIMIT_TEXT", "20")),
}
# 구독자용 사진 한도. 구독 기능을 붙일 때 구독 여부에 따라 _DAILY_LIMITS["photo"] 대신 쓴다.
_DAILY_LIMIT_PHOTO_PREMIUM = int(os.environ.get("DAILY_LIMIT_PHOTO_PREMIUM", "30"))
_CACHE_MAX_ENTRIES = int(os.environ.get("CACHE_MAX_ENTRIES", "5000"))
_KST = datetime.timezone(datetime.timedelta(hours=9))
_GEMINI_MODEL = os.environ.get("GEMINI_MODEL", "").strip() or "gemini-3.8-flash"

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
    logger.info("Gemini 모델: %s", _GEMINI_MODEL)
    return genai.GenerativeModel(_GEMINI_MODEL)


_model = _init_model()


class _GeminiCallError(Exception):
    """Gemini 호출 실패를 엔드포인트 핸들러까지 (HTTP 상태 코드, 사용자용 메시지)로
    들고 올라간다. rate limit(429)과 그 외 API 오류를 구분해 응답 상태 코드와
    로그 모두에 반영하기 위함 — 이전에는 둘 다 502로 뭉개져서 로그만 봐서는
    "Gemini가 느려서 실패"인지 "쿼터를 다 써서 실패"인지 구분할 수 없었다."""

    def __init__(self, status_code: int, message: str):
        super().__init__(message)
        self.status_code = status_code
        self.message = message


def _call_gemini(content, *, endpoint: str):
    """Gemini 호출 + 결과 로깅을 한 곳에 모은다. outcome(success/rate_limited/
    api_error/unexpected_error)과 소요시간을 남겨서, 나중에 로그만으로 실패 원인별
    비율(특히 429 비율)을 집계할 수 있게 한다. 캐시 히트(cache_hit)·일일 한도 초과
    (daily_limit_exceeded)·파싱 실패(parse_failed)는 _recognize_with_limits가 같은 형식으로
    남긴다."""
    start = time.monotonic()
    try:
        response = _model.generate_content(content)
    except ResourceExhausted as exc:
        elapsed_ms = (time.monotonic() - start) * 1000
        logger.warning(
            "gemini_call endpoint=%s outcome=rate_limited elapsed_ms=%.0f error=%s",
            endpoint, elapsed_ms, exc,
        )
        raise _GeminiCallError(429, "Gemini 요청 한도(rate limit)에 도달했습니다. 잠시 후 다시 시도해주세요.") from exc
    except GoogleAPICallError as exc:
        elapsed_ms = (time.monotonic() - start) * 1000
        logger.error(
            "gemini_call endpoint=%s outcome=api_error status=%s elapsed_ms=%.0f error=%s",
            endpoint, getattr(exc, "code", None), elapsed_ms, exc,
        )
        raise _GeminiCallError(502, f"Gemini 호출 실패: {exc}") from exc
    except Exception as exc:
        elapsed_ms = (time.monotonic() - start) * 1000
        logger.error(
            "gemini_call endpoint=%s outcome=unexpected_error elapsed_ms=%.0f error=%s",
            endpoint, elapsed_ms, exc,
        )
        raise _GeminiCallError(502, f"Gemini 호출 실패: {exc}") from exc

    elapsed_ms = (time.monotonic() - start) * 1000
    logger.info("gemini_call endpoint=%s outcome=success elapsed_ms=%.0f", endpoint, elapsed_ms)
    return response


def _today_kst() -> datetime.date:
    return datetime.datetime.now(_KST).date()


class _MemoryUsageStore:
    """DATABASE_URL이 없을 때(로컬 개발 등) 쓰는 대체 카운터. 프로세스 메모리에만 있어
    재시작 시 초기화되고, gunicorn 워커가 여러 개면 워커마다 따로 센다."""

    def __init__(self):
        self._lock = threading.Lock()
        self._counts: dict[tuple[str, datetime.date, str], int] = {}

    def try_acquire(self, client_key: str, day: datetime.date, kind: str, limit: int) -> bool:
        with self._lock:
            # 지난 날짜 카운트는 버린다(메모리가 무한히 늘지 않게).
            self._counts = {k: v for k, v in self._counts.items() if k[1] >= day}
            key = (client_key, day, kind)
            used = self._counts.get(key, 0)
            if used >= limit:
                return False
            self._counts[key] = used + 1
            return True

    def refund(self, client_key: str, day: datetime.date, kind: str) -> None:
        with self._lock:
            key = (client_key, day, kind)
            if self._counts.get(key, 0) > 0:
                self._counts[key] -= 1

    def get_counts(self, client_key: str, day: datetime.date) -> dict[str, int]:
        with self._lock:
            return {k[2]: v for k, v in self._counts.items() if k[0] == client_key and k[1] == day}


class _PostgresUsageStore:
    """일일 사용 횟수를 PostgreSQL에 저장해 서버 재시작/재배포에도 유지한다.
    차감은 INSERT ... ON CONFLICT 한 문장으로 처리해 동시 요청에도 한도를 넘지 않는다."""

    def __init__(self, database_url: str):
        from psycopg_pool import ConnectionPool

        self._pool = ConnectionPool(
            database_url, min_size=1, max_size=4, open=True, timeout=5,
            kwargs={"autocommit": True},
        )
        try:
            self._create_table()
        except Exception:
            # 풀을 닫지 않으면 백그라운드 워커가 접속을 계속 재시도한다.
            self._pool.close()
            raise

    def _create_table(self) -> None:
        with self._pool.connection() as conn:
            conn.execute(
                """
                CREATE TABLE IF NOT EXISTS daily_usage (
                    client_key TEXT NOT NULL,
                    usage_date DATE NOT NULL,
                    kind TEXT NOT NULL,
                    count INTEGER NOT NULL DEFAULT 0,
                    PRIMARY KEY (client_key, usage_date, kind)
                )
                """
            )
            # 한도 판정에는 당일 행만 필요하므로 오래된 행은 기동 시 정리한다.
            conn.execute("DELETE FROM daily_usage WHERE usage_date < CURRENT_DATE - 7")

    def try_acquire(self, client_key: str, day: datetime.date, kind: str, limit: int) -> bool:
        with self._pool.connection() as conn:
            row = conn.execute(
                """
                INSERT INTO daily_usage (client_key, usage_date, kind, count)
                VALUES (%s, %s, %s, 1)
                ON CONFLICT (client_key, usage_date, kind)
                DO UPDATE SET count = daily_usage.count + 1
                WHERE daily_usage.count < %s
                RETURNING count
                """,
                (client_key, day, kind, limit),
            ).fetchone()
        return row is not None

    def refund(self, client_key: str, day: datetime.date, kind: str) -> None:
        with self._pool.connection() as conn:
            conn.execute(
                "UPDATE daily_usage SET count = count - 1 "
                "WHERE client_key = %s AND usage_date = %s AND kind = %s AND count > 0",
                (client_key, day, kind),
            )

    def get_counts(self, client_key: str, day: datetime.date) -> dict[str, int]:
        with self._pool.connection() as conn:
            rows = conn.execute(
                "SELECT kind, count FROM daily_usage WHERE client_key = %s AND usage_date = %s",
                (client_key, day),
            ).fetchall()
        return {kind: count for kind, count in rows}


def _init_usage_store():
    database_url = os.environ.get("DATABASE_URL")
    if not database_url:
        logger.warning("DATABASE_URL 미설정 — 일일 사용 횟수를 메모리에만 저장합니다(재시작 시 초기화).")
        return _MemoryUsageStore()
    try:
        return _PostgresUsageStore(database_url)
    except Exception as exc:
        # DB가 아직 준비 안 됐다고 서버 전체가 못 뜨면 인식 기능이 통째로 죽으므로,
        # 메모리 카운터로라도 계속 서비스한다.
        logger.error("PostgreSQL 연결 실패 — 메모리 카운터로 대체합니다: %s", exc)
        return _MemoryUsageStore()


_usage_store = _init_usage_store()


class _ResponseCache:
    """같은 사진(바이트 해시)이나 같은 음식명+양 조합 요청은 Gemini를 다시 부르지 않고
    이전 결과로 바로 응답한다. 캐시 히트는 일일 횟수에 포함하지 않는다.
    결과 JSON만 메모리에 두고(사진 원본은 보관하지 않음), 오래 안 쓰인 항목부터 밀어낸다."""

    def __init__(self, max_entries: int):
        self.max_entries = max_entries
        self._lock = threading.Lock()
        self._data: collections.OrderedDict[str, dict] = collections.OrderedDict()

    def get(self, key: str) -> dict | None:
        with self._lock:
            value = self._data.get(key)
            if value is not None:
                self._data.move_to_end(key)
            return value

    def put(self, key: str, value: dict) -> None:
        if self.max_entries <= 0:
            return
        with self._lock:
            self._data[key] = value
            self._data.move_to_end(key)
            while len(self._data) > self.max_entries:
                self._data.popitem(last=False)


_response_cache = _ResponseCache(_CACHE_MAX_ENTRIES)


def _cache_key(*parts) -> str:
    return hashlib.sha256(json.dumps(parts, ensure_ascii=False).encode("utf-8")).hexdigest()


def _client_key() -> str:
    """일일 제한 집계 키. 앱이 보내는 X-User-Id(온보딩 때 생성된 임의 UUID)를 쓰고,
    헤더가 없는 구버전 앱은 클라이언트 IP로 대신 센다. 원문 대신 해시만 보관/로깅한다."""
    user_id = (request.headers.get("X-User-Id") or "").strip()[:64]
    if user_id:
        raw = f"uid:{user_id}"
    else:
        forwarded = request.headers.get("X-Forwarded-For", "")
        ip = forwarded.split(",")[0].strip() if forwarded else (request.remote_addr or "unknown")
        raw = f"ip:{ip}"
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()[:16]


def _usage_summary(client_key: str) -> dict:
    """앱의 "오늘 남은 사진 인식 2/3" 표시용. limit이 0 이하(무제한)면 remaining은 null."""
    try:
        counts = _usage_store.get_counts(client_key, _today_kst())
    except Exception as exc:
        logger.error("usage_store get_counts 실패: %s", exc)
        counts = {}
    summary = {}
    for kind, limit in _DAILY_LIMITS.items():
        used = counts.get(kind, 0)
        summary[kind] = {
            "used": used,
            "limit": limit,
            "remaining": max(limit - used, 0) if limit > 0 else None,
        }
    return summary


def _daily_limit_exceeded_response(endpoint: str, kind: str, client_key: str):
    logger.warning(
        "gemini_call endpoint=%s outcome=daily_limit_exceeded kind=%s client=%s limit=%d",
        endpoint, kind, client_key, _DAILY_LIMITS[kind],
    )
    # 429는 "Gemini 쿼터 소진(잠시 후 재시도 가능)"에 이미 쓰고 있어서, "오늘은 더 못 씀"을
    # 앱이 구분할 수 있도록 별도 상태 코드(403)와 code 필드를 쓴다.
    return (
        jsonify(
            error="오늘 사용 횟수를 모두 사용했어요. 내일 다시 이용해 주세요.",
            code="daily_limit_exceeded",
            usage=_usage_summary(client_key),
        ),
        403,
    )


def _recognize_with_limits(content, *, endpoint: str, kind: str, cache_key: str):
    """캐시 확인 → 일일 한도 차감 → Gemini 호출 → 파싱 → 캐시 저장까지 공통 처리하고
    Flask 응답 (body, status)을 돌려준다. Gemini 오류 시에는 사용자 탓이 아니므로
    차감을 되돌린다."""
    client_key = _client_key()

    cached = _response_cache.get(cache_key)
    if cached is not None:
        logger.info("gemini_call endpoint=%s outcome=cache_hit", endpoint)
        return jsonify({**cached, "usage": _usage_summary(client_key)}), 200

    limit = _DAILY_LIMITS[kind]
    day = _today_kst()
    acquired = False
    if limit > 0:
        try:
            if not _usage_store.try_acquire(client_key, day, kind, limit):
                return _daily_limit_exceeded_response(endpoint, kind, client_key)
            acquired = True
        except Exception as exc:
            # 카운터 저장소 장애로 인식 기능 전체를 막지는 않는다(로그로만 남김).
            logger.error("usage_store try_acquire 실패 — 제한 없이 진행: %s", exc)

    try:
        response = _call_gemini(content, endpoint=endpoint)
    except _GeminiCallError as exc:
        if acquired:
            try:
                _usage_store.refund(client_key, day, kind)
            except Exception as refund_exc:
                logger.error("usage_store refund 실패: %s", refund_exc)
        return jsonify(error=exc.message), exc.status_code

    parsed = _parse_food_json(response.text or "")
    if parsed is None:
        logger.error("gemini_call endpoint=%s outcome=parse_failed raw=%r", endpoint, response.text)
        return jsonify(error=f"Gemini 응답 파싱 실패: {response.text!r}"), 502

    _response_cache.put(cache_key, parsed)
    return jsonify({**parsed, "usage": _usage_summary(client_key)}), 200


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


@app.get("/usage")
def usage():
    """앱 화면의 "오늘 남은 횟수" 표시용. 차감 없이 오늘(KST) 사용량만 돌려준다."""
    if _PROXY_API_KEY and request.headers.get("X-API-Key") != _PROXY_API_KEY:
        return jsonify(error="unauthorized"), 401
    return jsonify(usage=_usage_summary(_client_key()))


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

    return _recognize_with_limits(
        [_build_prompt(hint, language), {"mime_type": "image/jpeg", "data": image_bytes}],
        endpoint="recognize",
        kind="photo",
        cache_key=_cache_key("photo", hashlib.sha256(image_bytes).hexdigest(), hint, language),
    )


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

    return _recognize_with_limits(
        _build_text_prompt(food_name, amount, unit, language),
        endpoint="recognize-text",
        kind="text",
        # 대소문자/공백 차이만 있는 같은 음식명+양 조합은 같은 요청으로 본다.
        cache_key=_cache_key("text", " ".join(food_name.lower().split()), float(amount), unit, language),
    )


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", 8080)))
