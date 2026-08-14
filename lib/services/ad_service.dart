import 'dart:async';

import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/ad_config.dart';

/// AdMob 초기화 + 전면 광고 노출 빈도 제한.
///
/// 전면 광고 규칙:
/// - 온보딩 직후 첫 실행(콜드 스타트 1회차)에는 노출하지 않는다.
/// - 그 이후 콜드 스타트부터는 마지막 노출로부터 [_minInterval] 이상 지났을 때만 노출한다.
/// - 광고 로드/노출에 실패해도 예외를 던지지 않고 조용히 넘어간다(앱 흐름에 영향 없음).
class AdService {
  AdService._internal();
  static final AdService instance = AdService._internal();

  static const _keyLastShownAt = 'interstitial_last_shown_at_millis';
  static const _keyColdStartCount = 'ad_cold_start_count';
  static const Duration _minInterval = Duration(minutes: 3);

  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    try {
      await MobileAds.instance.initialize();
      _initialized = true;
    } catch (_) {
      // 초기화 실패해도(예: 네트워크 없음) 앱 실행 자체를 막지 않는다.
    }
  }

  Future<InterstitialAd?> _loadInterstitial() async {
    final completer = Completer<InterstitialAd?>();
    try {
      await InterstitialAd.load(
        adUnitId: AdConfig.interstitialAdUnitId,
        request: const AdRequest(),
        adLoadCallback: InterstitialAdLoadCallback(
          onAdLoaded: (ad) {
            if (!completer.isCompleted) completer.complete(ad);
          },
          onAdFailedToLoad: (error) {
            if (!completer.isCompleted) completer.complete(null);
          },
        ),
      );
    } catch (_) {
      if (!completer.isCompleted) completer.complete(null);
    }
    return completer.future;
  }

  /// 홈 화면에 처음 진입했을 때(콜드 스타트) 호출한다. 빈도 제한을 통과하면 전면
  /// 광고를 로드해서 보여준다. 시크릿 모드 잠금 화면에서는 호출하지 않으므로,
  /// 잠금이 걸려 있으면 잠금 해제 후 홈 화면에 도달했을 때만 이 로직을 탄다.
  Future<void> maybeShowInterstitialOnColdStart() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final coldStartCount = (prefs.getInt(_keyColdStartCount) ?? 0) + 1;
      await prefs.setInt(_keyColdStartCount, coldStartCount);

      // 온보딩 직후 첫 실행(=이 기기에서 홈 화면 첫 진입)에는 노출하지 않는다.
      if (coldStartCount <= 1) return;

      final lastShownMillis = prefs.getInt(_keyLastShownAt);
      if (lastShownMillis != null) {
        final elapsed = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(lastShownMillis));
        if (elapsed < _minInterval) return;
      }

      await initialize();
      final ad = await _loadInterstitial();
      if (ad == null) return;

      final shown = Completer<void>();
      ad.fullScreenContentCallback = FullScreenContentCallback(
        onAdDismissedFullScreenContent: (ad) {
          ad.dispose();
          if (!shown.isCompleted) shown.complete();
        },
        onAdFailedToShowFullScreenContent: (ad, error) {
          ad.dispose();
          if (!shown.isCompleted) shown.complete();
        },
      );
      await ad.show();
      await prefs.setInt(_keyLastShownAt, DateTime.now().millisecondsSinceEpoch);
      await shown.future;
    } catch (_) {
      // 광고 실패는 앱 흐름과 무관하게 조용히 무시한다.
    }
  }
}
