import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../config/ad_config.dart';
import '../theme/app_colors.dart';

/// 표준 배너(320x50) 광고. 로딩 중이거나 로드에 실패하면 자리를 차지하지 않도록
/// 크기가 0인 위젯을 보여줘서, 광고 실패가 레이아웃이나 앱 흐름에 영향을 주지 않게 한다.
class BannerAdWidget extends StatefulWidget {
  const BannerAdWidget({super.key});

  @override
  State<BannerAdWidget> createState() => _BannerAdWidgetState();
}

class _BannerAdWidgetState extends State<BannerAdWidget> {
  BannerAd? _bannerAd;

  @override
  void initState() {
    super.initState();
    _loadBanner();
  }

  void _loadBanner() {
    final ad = BannerAd(
      size: AdSize.banner,
      adUnitId: AdConfig.bannerAdUnitId,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (mounted) setState(() => _bannerAd = ad as BannerAd);
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
        },
      ),
    );
    ad.load();
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ad = _bannerAd;
    if (ad == null) return const SizedBox.shrink();
    return AdSlotFrame(
      child: SizedBox(
        width: ad.size.width.toDouble(),
        height: ad.size.height.toDouble(),
        child: AdWidget(ad: ad),
      ),
    );
  }
}

/// 광고 영역 틀. 위아래에 얇은 구분선을 긋고 아래 콘텐츠와 간격을 둬서, 광고가 카드
/// 목록의 일부처럼 보이지 않게 한다. 광고가 없으면(로딩 중·실패) 이 틀도 그리지 않는다.
class AdSlotFrame extends StatelessWidget {
  final Widget child;
  const AdSlotFrame({super.key, required this.child});

  static const double innerPadding = 6;
  static const double bottomGap = 8;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: bottomGap),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Divider(height: 1, thickness: 1, color: AppColors.adDivider),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: innerPadding),
            child: Center(child: child),
          ),
          const Divider(height: 1, thickness: 1, color: AppColors.adDivider),
        ],
      ),
    );
  }
}
