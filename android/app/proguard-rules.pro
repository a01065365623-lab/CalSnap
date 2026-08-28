# CalSnap release용 커스텀 ProGuard/R8 규칙.
# tflite_flutter 제거(2026-08-17, 실제로 호출되지 않는 온디바이스 매칭 경로였음)로
# 이전에 필요했던 GpuDelegateFactory -dontwarn 규칙은 삭제했다. 현재는 규칙 없음 —
# 새 의존성 추가로 R8이 missing-class 경고를 내면 여기에 추가할 것.
