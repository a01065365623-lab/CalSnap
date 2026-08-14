/// 지역/언어별 쇼핑 제휴 링크 설정.
///
/// wedi_app에서 검증된 3사(쿠팡파트너스/네이버/아마존 어소시에이트) 딥링크 패턴을
/// 그대로 이식했다. 실제 서비스 배포 전 아래 값을 전부 CalSnap 전용 계정의 실제
/// 제휴 ID로 교체해야 한다(wedi_app 것을 그대로 쓰면 수익이 wedi_app 계정으로
/// 잡히거나, 심하면 각 플랫폼 제휴 정책 위반이 될 수 있다).
class AffiliateConfig {
  AffiliateConfig._();

  /// 쿠팡파트너스 채널 ID. 현재는 검색 결과 URL(coupang.com/np/search)만 쓰고
  /// 있어 필수는 아니지만, 추후 파트너스 API로 정식 딥링크를 발급받을 경우 필요하다.
  /// TODO: 실제 쿠팡파트너스 채널 ID로 교체
  static const String coupangChannelId = 'YOUR_COUPANG_CHANNEL_ID';

  /// 아마존 어소시에이트 추적 태그(스토어 ID). wedi_app은 'wediapp-20'을 썼으나
  /// (요청 주신 'wedia'는 실제 코드에서 확인되지 않음 — 참고로 알려드립니다),
  /// CalSnap은 반드시 별도로 발급받은 본인 계정 태그를 써야 한다.
  /// TODO: 실제 아마존 어소시에이트 태그로 교체 (예: yourtag-20)
  static const String amazonAssociateTag = 'YOUR_AMAZON_TAG-20';
}
