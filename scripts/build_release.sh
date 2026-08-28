#!/usr/bin/env bash
# CalSnap release 빌드 래퍼.
#
# release 빌드는 반드시 --dart-define-from-file=env.json으로 PROXY_API_KEY를 함께
# 넘겨야 한다. 빠뜨리면 GeminiFoodRecognitionService.apiKey가 빈 문자열로 컴파일되고,
# 앱은 정상적으로 실행되지만 음식 인식 요청이 전부 서버에서 401로 "조용히" 거부된다
# (2026-08-17: 실제로 이 실수로 release AAB를 한 번 잘못 빌드한 적이 있음). 이 스크립트는
# 그 실수를 build 단계에서 막는다. GeminiFoodRecognitionService 생성자에도 같은 상황을
# release 실행 시 즉시 크래시시키는 런타임 안전장치가 있지만, 그건 최후의 방어선이고
# 이 스크립트가 1차 방어선이다.
#
# 사용법:
#   scripts/build_release.sh          # appbundle (기본값, Play 스토어 업로드용)
#   scripts/build_release.sh apk      # apk (사이드로드/수동 테스트용)
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

target="${1:-appbundle}"
env_file="env.json"

if [[ ! -f "$env_file" ]]; then
  echo "오류: $env_file 이 없습니다." >&2
  echo "      env.json.example을 $env_file 로 복사한 뒤, Railway 대시보드의 실제" >&2
  echo "      PROXY_API_KEY/PROXY_BASE_URL 값으로 채워주세요." >&2
  exit 1
fi

api_key=$(grep -o '"PROXY_API_KEY"[[:space:]]*:[[:space:]]*"[^"]*"' "$env_file" \
  | sed -E 's/.*:[[:space:]]*"([^"]*)"/\1/')

if [[ -z "$api_key" || "$api_key" == "your-secret-key" ]]; then
  echo "오류: $env_file 의 PROXY_API_KEY 값이 비어 있거나 예시값(your-secret-key)입니다." >&2
  echo "      Railway 대시보드 > Variables 탭의 실제 PROXY_API_KEY 값으로 채워주세요." >&2
  exit 1
fi

echo "release 빌드 시작 — target=$target, env=$env_file (PROXY_API_KEY=${api_key:0:4}****)"
flutter build "$target" --release --dart-define-from-file="$env_file"
