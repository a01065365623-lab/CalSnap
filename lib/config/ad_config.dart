import 'dart:io';

/// AdMob 광고 단위 ID 설정.
///
/// 아래 값은 전부 Google이 공식 제공하는 테스트 광고 ID다(항상 로드되고, 실제 수익은
/// 발생하지 않음). 개발/QA 중에는 이대로 써도 되지만, 실제 스토어 배포 전에는 반드시
/// AdMob 콘솔(https://admob.google.com)에서 발급받은 본인 계정의 실제 ID로 교체해야
/// 한다. 앱 ID는 android/app/src/main/AndroidManifest.xml, ios/Runner/Info.plist에도
/// 각각 등록돼 있으므로 세 곳 모두 같이 바꿔야 한다.
class AdConfig {
  AdConfig._();

  // ── 앱 ID (AndroidManifest.xml / Info.plist와 동일한 값이어야 함) ──
  // TODO: 실제 AdMob 앱 ID로 교체
  static const String _androidAppId = 'ca-app-pub-3940256099942544~3347511713'; // Google 테스트 앱 ID
  static const String _iosAppId = 'ca-app-pub-3940256099942544~1458002511'; // Google 테스트 앱 ID

  static String get appId => Platform.isIOS ? _iosAppId : _androidAppId;

  // ── 배너 광고 단위 ID ──
  // TODO: 실제 배너 광고 단위 ID로 교체
  static const String _androidBannerAdUnitId = 'ca-app-pub-3940256099942544/6300978111'; // Google 테스트 배너 ID
  static const String _iosBannerAdUnitId = 'ca-app-pub-3940256099942544/2934735716'; // Google 테스트 배너 ID

  static String get bannerAdUnitId => Platform.isIOS ? _iosBannerAdUnitId : _androidBannerAdUnitId;

  // ── 전면 광고 단위 ID ──
  // TODO: 실제 전면 광고 단위 ID로 교체
  static const String _androidInterstitialAdUnitId =
      'ca-app-pub-3940256099942544/1033173712'; // Google 테스트 전면 ID
  static const String _iosInterstitialAdUnitId =
      'ca-app-pub-3940256099942544/4411468910'; // Google 테스트 전면 ID

  static String get interstitialAdUnitId =>
      Platform.isIOS ? _iosInterstitialAdUnitId : _androidInterstitialAdUnitId;
}
