import 'package:shared_preferences/shared_preferences.dart';

import 'food_recognition_service.dart';

/// 이날 몇 번째 사진 인식부터 무료 한도 안내를 보여줄지. 첫 번째 결과에서는 결과만
/// 보여주고, 두 번째 결과가 나왔을 때 "하루 N회 무료" 안내를 한 줄로 덧붙인다.
const int photoQuotaNoticeFromUse = 2;

/// 빠른 측정 결과 아래의 "사진 인식은 하루 N회 무료" 안내 노출 여부를 판단·기록한다.
/// 팝업이 아니라 한 줄 안내이고, 하루에 한 번만 보인다 — 한 번 보여준 날(또는 사용자가
/// 닫은 날)의 날짜를 SharedPreferences에 남겨 두고 그날은 다시 띄우지 않는다.
class PhotoQuotaNoticeService {
  PhotoQuotaNoticeService._();
  static final PhotoQuotaNoticeService instance = PhotoQuotaNoticeService._();

  static const keyLastShownDate = 'photo_quota_notice_last_shown_date';

  /// 방금 받은 사진 인식 결과의 사용량으로 안내를 보여줄지 정하고, 보여준다면 오늘
  /// 날짜를 기록한다(다음 결과부터는 오늘 안 보이게). 보여줄 때 한도(N)를, 아니면 null.
  Future<int?> takeNoticeLimitForToday(RecognitionUsage? usage, {DateTime? now}) async {
    final prefs = await SharedPreferences.getInstance();
    final today = dateKey(now ?? DateTime.now());
    final limit = photoQuotaNoticeLimit(
      usage: usage,
      lastShownDate: prefs.getString(keyLastShownDate),
      today: today,
    );
    if (limit != null) await prefs.setString(keyLastShownDate, today);
    return limit;
  }

  /// 사용자가 안내를 닫았을 때. 오늘은 다시 보이지 않게 날짜를 기록한다.
  Future<void> dismissForToday({DateTime? now}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(keyLastShownDate, dateKey(now ?? DateTime.now()));
  }
}

/// 안내를 보여줘야 하면 서버가 내려준 사진 한도(N), 아니면 null.
/// - 서버가 한도를 두지 않으면(무제한·사용량 없음) 안내할 게 없다.
/// - 오늘 사진 인식이 [photoQuotaNoticeFromUse]회 이상이어야 한다.
/// - 오늘 이미 보여줬거나 닫았으면 다시 보여주지 않는다.
int? photoQuotaNoticeLimit({
  required RecognitionUsage? usage,
  required String? lastShownDate,
  required String today,
}) {
  final photo = usage?.photo;
  if (photo == null || !photo.isLimited) return null;
  if (photo.used < photoQuotaNoticeFromUse) return null;
  if (lastShownDate == today) return null;
  return photo.limit;
}

String dateKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
