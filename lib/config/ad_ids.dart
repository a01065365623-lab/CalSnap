/// AdMob ID 모음. 광고 ID를 바꿀 때는 이 파일만 고치면 된다
/// (단, Android 앱 ID는 Gradle이 매니페스트에 넣어야 해서 android/app/build.gradle.kts의
/// manifestPlaceholders["admobAppId"]에도 같은 값을 넣어야 한다).
///
/// 어떤 ID를 쓸지는 lib/config/ad_config.dart가 빌드 모드로 고른다:
/// debug(kDebugMode) = Google 테스트 ID, 그 외(release/profile) = 실제 ID.
class AdIds {
  AdIds._();

  // ── 실제 ID (AdMob 콘솔 발급) ──
  static const String androidAppId = 'ca-app-pub-9075706979713157~1512052827';
  static const String androidBanner = 'ca-app-pub-9075706979713157/6744112487';
  static const String androidInterstitial = 'ca-app-pub-9075706979713157/4485614800';

  // iOS는 아직 실제 ID를 발급받지 않아 테스트 ID를 그대로 둔다.
  // TODO: iOS 출시 시 AdMob 콘솔에서 iOS 앱/광고 단위 ID를 발급받아 교체(Info.plist의
  // GADApplicationIdentifier도 함께).
  static const String iosAppId = testIosAppId;
  static const String iosBanner = testIosBanner;
  static const String iosInterstitial = testIosInterstitial;

  // ── Google 공식 테스트 ID (항상 로드되고 수익은 발생하지 않음) ──
  static const String testAndroidAppId = 'ca-app-pub-3940256099942544~3347511713';
  static const String testAndroidBanner = 'ca-app-pub-3940256099942544/6300978111';
  static const String testAndroidInterstitial = 'ca-app-pub-3940256099942544/1033173712';
  static const String testIosAppId = 'ca-app-pub-3940256099942544~1458002511';
  static const String testIosBanner = 'ca-app-pub-3940256099942544/2934735716';
  static const String testIosInterstitial = 'ca-app-pub-3940256099942544/4411468910';
}
