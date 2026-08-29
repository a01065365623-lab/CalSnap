import 'dart:io';

import 'package:in_app_update/in_app_update.dart';
import 'package:url_launcher/url_launcher.dart';

/// Google Play 인앱 업데이트. lexfall(js/app_update.js)의 정책을 그대로 따른다:
/// Flexible 업데이트를 우선하고, 불가능한 상황(즉시 업데이트만 허용된 높은 우선순위
/// 업데이트)에는 기록 흐름을 강제로 막지 않도록 즉시(immediate) 업데이트 대신
/// 스토어 페이지로만 안내한다. Play Core는 Android 전용이라 다른 플랫폼에서는 아무
/// 동작도 하지 않는다.
class AppUpdateService {
  AppUpdateService._();
  static final AppUpdateService instance = AppUpdateService._();

  static const _packageName = 'com.kbraingames.calsnap';

  bool get _supported => Platform.isAndroid;

  Future<AppUpdateInfo?> checkForUpdate() async {
    if (!_supported) return null;
    try {
      return await InAppUpdate.checkForUpdate();
    } catch (_) {
      return null;
    }
  }

  /// installStatus가 downloaded로 바뀌면(Flexible 업데이트 다운로드 완료) 이벤트가 온다.
  Stream<InstallStatus> get installStatusStream =>
      _supported ? InAppUpdate.installUpdateListener : const Stream.empty();

  Future<bool> startFlexibleUpdate() async {
    if (!_supported) return false;
    try {
      final result = await InAppUpdate.startFlexibleUpdate();
      return result == AppUpdateResult.success;
    } catch (_) {
      return false;
    }
  }

  Future<void> completeFlexibleUpdate() async {
    if (!_supported) return;
    try {
      await InAppUpdate.completeFlexibleUpdate();
    } catch (_) {
      // 성공 시 앱이 재시작되므로 여기 도달하는 건 실패한 경우뿐이다. 실패해도
      // 다음 실행/복귀 시 checkForUpdate()가 다시 재시작 안내를 띄운다.
    }
  }

  /// Flexible 업데이트가 불가능할 때(즉시 업데이트만 허용) 대신 안내하는 경로.
  Future<void> openStoreListing() async {
    final marketUri = Uri.parse('market://details?id=$_packageName');
    if (await canLaunchUrl(marketUri)) {
      await launchUrl(marketUri);
      return;
    }
    await launchUrl(
      Uri.parse('https://play.google.com/store/apps/details?id=$_packageName'),
      mode: LaunchMode.externalApplication,
    );
  }
}
