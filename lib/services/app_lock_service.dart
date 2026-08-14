import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 시크릿 모드(앱 잠금)에 쓰는 2자리 숫자 비밀번호 저장/검증.
///
/// 2자리(00~99, 경우의 수 100개)라 애초에 완전한 보안은 불가능하지만, 그래도
/// SharedPreferences에 평문으로 남기지는 않도록 기기별 랜덤 salt + SHA-256 해시로
/// 저장한다.
class AppLockService {
  AppLockService._internal();
  static final AppLockService instance = AppLockService._internal();

  static const _keyEnabled = 'secret_mode_enabled';
  static const _keyHash = 'secret_mode_hash';
  static const _keySalt = 'secret_mode_salt';

  Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyEnabled) ?? false;
  }

  String _generateSalt() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return base64UrlEncode(bytes);
  }

  String _hash(String pin, String salt) => sha256.convert(utf8.encode('$salt:$pin')).toString();

  /// [pin]이 "00"~"99" 형태의 2자리 숫자 문자열인지 확인한다.
  bool isValidPin(String pin) => RegExp(r'^\d{2}$').hasMatch(pin);

  /// 비밀번호를 (재)설정하고 시크릿 모드를 켠다.
  Future<void> setPassword(String pin) async {
    assert(isValidPin(pin));
    final prefs = await SharedPreferences.getInstance();
    final salt = _generateSalt();
    await prefs.setString(_keySalt, salt);
    await prefs.setString(_keyHash, _hash(pin, salt));
    await prefs.setBool(_keyEnabled, true);
  }

  /// 입력한 비밀번호가 저장된 값과 일치하는지 확인한다. 비밀번호가 설정돼 있지
  /// 않으면(정상적으로는 발생하지 않아야 함) 항상 false.
  Future<bool> verifyPassword(String pin) async {
    final prefs = await SharedPreferences.getInstance();
    final salt = prefs.getString(_keySalt);
    final storedHash = prefs.getString(_keyHash);
    if (salt == null || storedHash == null) return false;
    return _hash(pin, salt) == storedHash;
  }

  /// 시크릿 모드를 끄고 저장된 비밀번호(해시/salt)를 모두 지운다. 비밀번호 확인은
  /// 호출부(설정 화면의 끄기 흐름, 잠금 화면의 "비밀번호를 잊으셨나요?" 초기화 흐름)
  /// 에서 먼저 수행한다.
  Future<void> disable() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyEnabled);
    await prefs.remove(_keyHash);
    await prefs.remove(_keySalt);
  }
}
