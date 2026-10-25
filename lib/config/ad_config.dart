import 'dart:io';

import 'package:flutter/foundation.dart' show kDebugMode;

import 'ad_ids.dart';

/// AdMob 광고 단위 ID 선택.
///
/// debug 빌드(kDebugMode)는 Google 공식 테스트 ID, release 빌드는 실제 ID를 쓴다 —
/// 개발 중 실제 광고를 노출/클릭하면 AdMob 계정이 무효 트래픽으로 정지될 수 있기
/// 때문이다. ID 값 자체는 lib/config/ad_ids.dart에 모여 있다. Android 앱 ID는
/// android/app/build.gradle.kts의 manifestPlaceholders(admobAppId)로 같은 기준(debug만
/// 테스트 ID)으로 분기되고, iOS 앱 ID는 ios/Runner/Info.plist에 등록돼 있다.
class AdConfig {
  AdConfig._();

  // ── 앱 ID (build.gradle.kts의 admobAppId / Info.plist와 동일한 값이어야 함) ──
  static String get appId => Platform.isIOS
      ? (kDebugMode ? AdIds.testIosAppId : AdIds.iosAppId)
      : (kDebugMode ? AdIds.testAndroidAppId : AdIds.androidAppId);

  // ── 배너 광고 단위 ID ──
  static String get bannerAdUnitId => Platform.isIOS
      ? (kDebugMode ? AdIds.testIosBanner : AdIds.iosBanner)
      : (kDebugMode ? AdIds.testAndroidBanner : AdIds.androidBanner);

  // ── 전면 광고 단위 ID ──
  static String get interstitialAdUnitId => Platform.isIOS
      ? (kDebugMode ? AdIds.testIosInterstitial : AdIds.iosInterstitial)
      : (kDebugMode ? AdIds.testAndroidInterstitial : AdIds.androidInterstitial);
}
