# calsnap

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Release 빌드 — 반드시 `--dart-define-from-file=env.json`을 포함할 것

CalSnap의 음식 인식(Gemini 프록시) 서버는 `X-API-Key` 헤더로 앱을 인증한다. 이 값은
`GeminiFoodRecognitionService`에서 `String.fromEnvironment('PROXY_API_KEY')`로 컴파일
타임에 주입되는데, **`--dart-define`(또는 `--dart-define-from-file`) 없이 release를
빌드하면 이 값이 빈 문자열로 굳어버린다.** 이 상태의 앱은 겉보기엔 멀쩡히 실행되지만,
음식 인식 요청이 전부 서버에서 `401 Unauthorized`로 조용히 거부된다(2026-08-17: 실제로
이 실수로 release AAB를 한 번 잘못 빌드한 적이 있음 — 빌드/서명은 성공하고 앱도 잘
켜져서, 실기기에서 인식을 눌러보기 전까진 아무도 못 알아챌 뻔했다).

**그래서 release 빌드는 아래 스크립트로만 한다:**

```bash
# macOS/Linux/Git Bash
scripts/build_release.sh          # appbundle (기본, Play 스토어 업로드용)
scripts/build_release.sh apk      # apk (사이드로드/수동 테스트용)
```

```powershell
# Windows PowerShell
.\scripts\build_release.ps1          # appbundle (기본, Play 스토어 업로드용)
.\scripts\build_release.ps1 apk      # apk (사이드로드/수동 테스트용)
```

두 스크립트 모두 `env.json`이 있는지, `PROXY_API_KEY`가 비어있거나 예시값이 아닌지
먼저 확인하고 나서야 `flutter build ... --dart-define-from-file=env.json`을 실행한다
(`env.json`이 없다면 `env.json.example`을 복사해서 Railway 대시보드의 실제 값으로
채워넣을 것 — `env.json`은 `.gitignore`에 등록되어 있어 커밋되지 않는다).

이 스크립트 없이 `flutter build appbundle --release`를 직접 실행하고 싶다면, 최소한
아래 옵션은 빠뜨리지 말 것:

```
flutter build appbundle --release --dart-define-from-file=env.json
```

**추가 안전장치**: 스크립트를 우회해서 dart-define 없이 release를 빌드하더라도,
`GeminiFoodRecognitionService`가 release 모드에서 `apiKey`가 비어있으면 생성 시점에
바로 `StateError`를 던지도록 되어 있다. 즉 그런 잘못된 빌드를 설치해서 실행하면
음식 인식 화면을 여는 순간 바로 크래시하므로, 배포 전에 반드시 발견된다(사용자에게
조용히 401만 발생하는 것보다 훨씬 낫다).
