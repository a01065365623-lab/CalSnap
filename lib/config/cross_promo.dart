import 'package:flutter_gen/gen_l10n/app_localizations.dart';

/// K-Brain Games Lab 다른 앱 소개(크로스 프로모션) 목록. 설정 화면의 "K-Brain Games Lab
/// 다른 앱" 섹션에 카드로만 노출한다 — 팝업·전면광고로 띄우지 않고, 광고 옆에도 두지 않는다.
///
/// 앱을 추가하려면:
///   1. 아이콘(192px PNG 권장)을 assets/promo/에 넣는다(pubspec.yaml에 폴더가 등록돼 있음).
///   2. 한 줄 소개 문구 키를 14개 언어 ARB(lib/l10n/app_*.arb)에 추가한다.
///   3. 아래 [crossPromoApps]에 항목을 하나 추가한다. 아직 출시 전이면 `enabled: false`로
///      두면 목록에서 숨겨지고, 출시 후 `true`로 바꾸면 노출된다.
class CrossPromoApp {
  /// Google Play 패키지명(applicationId).
  final String packageName;

  /// 앱 이름. 브랜드명이라 번역하지 않는다.
  final String name;

  /// assets/promo/ 아래 아이콘 경로.
  final String iconAsset;

  /// 현재 언어의 한 줄 소개.
  final String Function(AppLocalizations l10n) tagline;

  /// false면 설정 화면 목록에서 숨긴다(출시 전 앱).
  final bool enabled;

  const CrossPromoApp({
    required this.packageName,
    required this.name,
    required this.iconAsset,
    required this.tagline,
    required this.enabled,
  });

  /// Play 스토어 앱으로 바로 여는 링크.
  Uri get marketUri => Uri.parse('market://details?id=$packageName');

  /// Play 스토어 앱이 없거나 market:// 실행에 실패했을 때의 웹 링크.
  Uri get webUri => Uri.parse('https://play.google.com/store/apps/details?id=$packageName');
}

/// 이 앱(CalSnap)의 패키지명. 같은 목록 파일을 다른 앱에 복사해 써도 자기 자신은
/// 소개하지 않도록 [visibleCrossPromoApps]에서 걸러낸다.
const String currentAppPackageName = 'com.kbraingames.calsnap';

String _wediTagline(AppLocalizations l10n) => l10n.crossPromoWediTagline;

const List<CrossPromoApp> crossPromoApps = [
  CrossPromoApp(
    packageName: 'com.wedi.app',
    name: 'Wedi',
    iconAsset: 'assets/promo/wedi.png',
    tagline: _wediTagline,
    enabled: true,
  ),
];

/// 설정 화면에 실제로 보여줄 목록(현재 앱·비활성 앱 제외).
List<CrossPromoApp> get visibleCrossPromoApps =>
    crossPromoApps.where((a) => a.enabled && a.packageName != currentAppPackageName).toList();
