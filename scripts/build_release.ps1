# CalSnap release 빌드 래퍼 (PowerShell).
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
#   .\scripts\build_release.ps1          # appbundle (기본값, Play 스토어 업로드용)
#   .\scripts\build_release.ps1 apk      # apk (사이드로드/수동 테스트용)
#   .\scripts\build_release.ps1 install  # apk 빌드 후 연결된 기기에 adb install -r
#
# install은 매번 android/key.properties의 고정 release keystore로 서명하므로, USB로
# 반복 사이드로드해도 서명이 항상 같아 기존 데이터가 유지된 채 업데이트된다(디버그
# 빌드로 설치하면 debug keystore와 서명이 달라 기존 release 앱 위에 덮어쓸 수 없어
# 매번 강제 삭제 후 재설치돼야 했음). 단, 기기에 Play 스토어에서 설치된 버전이 있다면
# 그건 Google Play 앱 서명 키로 재서명된 것이라 이 로컬 release 키와도 서명이 다르므로
# 최초 1회는 여전히 기존 앱 제거가 필요하다 — 그 이후부터는 이 install 경로로만
# 사이드로드하면 서명이 계속 고정된다.

param(
    [string]$Target = "appbundle"
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot

$envFile = "env.json"
if (-not (Test-Path $envFile)) {
    Write-Error "오류: $envFile 이 없습니다. env.json.example을 $envFile 로 복사한 뒤, Railway 대시보드의 실제 PROXY_API_KEY/PROXY_BASE_URL 값으로 채워주세요."
    exit 1
}

$envJson = Get-Content $envFile -Raw | ConvertFrom-Json
$apiKey = $envJson.PROXY_API_KEY

if ([string]::IsNullOrWhiteSpace($apiKey) -or $apiKey -eq "your-secret-key") {
    Write-Error "오류: $envFile 의 PROXY_API_KEY 값이 비어 있거나 예시값(your-secret-key)입니다. Railway 대시보드 > Variables 탭의 실제 PROXY_API_KEY 값으로 채워주세요."
    exit 1
}

$buildTarget = if ($Target -eq "install") { "apk" } else { $Target }

$maskedKey = $apiKey.Substring(0, [Math]::Min(4, $apiKey.Length)) + "****"
Write-Host "release 빌드 시작 — target=$buildTarget, env=$envFile (PROXY_API_KEY=$maskedKey)"
flutter build $buildTarget --release --dart-define-from-file=$envFile

if ($Target -eq "install") {
    $apkPath = "build\app\outputs\flutter-apk\app-release.apk"
    if (-not (Test-Path $apkPath)) {
        Write-Error "오류: $apkPath 를 찾을 수 없습니다."
        exit 1
    }
    $adb = (Get-Command adb -ErrorAction SilentlyContinue).Source
    if (-not $adb) { $adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" }
    Write-Host "연결된 기기에 설치 중 (release keystore 고정 서명 — 기존 데이터 유지)..."
    & $adb install -r $apkPath
}
