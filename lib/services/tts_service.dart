import 'dart:convert';
import 'dart:math';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_tts/flutter_tts.dart';

import '../db/database_helper.dart';
import '../utils/goal_status.dart';
import 'user_profile_service.dart';

/// 상황별 격려 멘트 카테고리. assets/calsnap_phrases.json의 "category" 값과 1:1로 대응한다.
enum TtsCategory {
  appOpen,
  mealSave,
  exerciseSave,
  waterLog,
  goalMet,
  goalOver,
  exerciseReminder,
  streak,
}

extension on TtsCategory {
  String get key {
    switch (this) {
      case TtsCategory.appOpen:
        return 'app_open';
      case TtsCategory.mealSave:
        return 'meal_save';
      case TtsCategory.exerciseSave:
        return 'exercise_save';
      case TtsCategory.waterLog:
        return 'water_log';
      case TtsCategory.goalMet:
        return 'goal_met';
      case TtsCategory.goalOver:
        return 'goal_over';
      case TtsCategory.exerciseReminder:
        return 'exercise_reminder';
      case TtsCategory.streak:
        return 'streak';
    }
  }
}

/// wedi_app(assets/wedi_phrases.json)이 지원하는 14개 언어와 동일한 목록 · 순서.
/// {"category": "...", "ko": "...", "en": "...", ...} 형식의 언어 컬럼 키로 쓰인다.
const List<String> _supportedLangKeys = [
  'ko', 'en', 'ja', 'zh', 'de', 'fr', 'es', 'hi', 'pt', 'it', 'ru', 'tr', 'vi', 'ar',
];

/// langKey → flutter_tts에 넘길 전체 로케일 태그. wedi_app 설정 화면의 언어 선택
/// 목록(ko-KR, en-US, ja-JP ...)과 동일한 매핑을 그대로 따른다.
const Map<String, String> _langKeyToTtsLocale = {
  'ko': 'ko-KR',
  'en': 'en-US',
  'ja': 'ja-JP',
  'zh': 'zh-CN',
  'de': 'de-DE',
  'fr': 'fr-FR',
  'es': 'es-ES',
  'hi': 'hi-IN',
  'pt': 'pt-BR',
  'it': 'it-IT',
  'ru': 'ru-RU',
  'tr': 'tr-TR',
  'vi': 'vi-VN',
  'ar': 'ar-SA',
};

/// 상황별 격려 멘트를 실시간 TTS로 읽어주는 서비스.
///
/// wedi_app(assets/wedi_phrases.json)과 동일한 파이프라인을 그대로 따른다: 음성 파일을
/// 미리 생성해 assets에 넣는 방식이 아니라, 멘트 텍스트만 assets/calsnap_phrases.json에
/// 두고 rootBundle.loadString으로 읽어 캐싱한 뒤, 카테고리별로 Random().nextInt로 하나를
/// 골라 기기의 TTS 엔진(flutter_tts)으로 그때그때 읽는다.
///
/// wedi_app은 TTS 언어를 사용자가 설정 화면에서 직접 고르지만(기본값 ko-KR), CalSnap에는
/// 별도의 언어 선택 UI가 없으므로 기기 locale(PlatformDispatcher.instance.locale)을 그대로
/// 사용해 14개 언어 중 하나로 매핑한다. 지원하지 않는 언어는 en으로 폴백한다.
class TtsService {
  TtsService._internal();
  static final TtsService instance = TtsService._internal();

  static const String _assetPath = 'assets/calsnap_phrases.json';

  final FlutterTts _tts = FlutterTts();
  final Random _random = Random();
  bool _awaitCompletionConfigured = false;

  /// flutter_tts는 기본적으로 speak() 호출 즉시(재생 시작만 확인하고) Future를
  /// 완료시켜서, 호출부가 "실제로 다 읽었는지"는 알 수 없다. 앱 오픈 시 TTS와
  /// 전면광고 소리가 겹치는 문제(HomeScreen에서 TTS가 끝난 뒤 광고를 띄우려면
  /// 진짜 완료 시점이 필요함)를 풀려면 이 설정이 꼭 필요해서, 첫 speak() 호출 전에
  /// 한 번만 켠다.
  Future<void> _ensureAwaitCompletionConfigured() async {
    if (_awaitCompletionConfigured) return;
    _awaitCompletionConfigured = true;
    try {
      await _tts.awaitSpeakCompletion(true);
    } catch (_) {
      // 일부 기기/엔진은 미지원일 수 있음 — 그런 경우 그냥 기존처럼 즉시 반환된다.
    }
  }

  /// 카테고리 → 그 카테고리에 속한 멘트들(각 멘트는 언어 코드 → 텍스트 맵).
  Map<String, List<Map<String, String>>>? _cache;

  /// assets/calsnap_phrases.json 형식:
  /// [{"category": "app_open", "ko": "...", "en": "...", ...}, ...]
  Future<Map<String, List<Map<String, String>>>> _loadPhrases() async {
    final cached = _cache;
    if (cached != null) return cached;

    final raw = await rootBundle.loadString(_assetPath);
    final list = jsonDecode(raw) as List<dynamic>;
    final byCategory = <String, List<Map<String, String>>>{};
    for (final e in list) {
      final m = e as Map<String, dynamic>;
      final category = m['category'] as String?;
      if (category == null) continue;

      final texts = <String, String>{};
      for (final lang in _supportedLangKeys) {
        final text = (m[lang] as String?)?.trim();
        if (text != null && text.isNotEmpty) texts[lang] = text;
      }
      if (texts.isEmpty) continue;

      byCategory.putIfAbsent(category, () => []).add(texts);
    }
    _cache = byCategory;
    return byCategory;
  }

  /// 기기 locale의 언어 코드를 calsnap_phrases.json의 언어 컬럼 키로 변환한다.
  /// 지원하지 않는 언어는 en으로 폴백한다(wedi_app의 _ttsLangToKey와 동일한 방식).
  String _resolveLangKey() {
    final code = PlatformDispatcher.instance.locale.languageCode.toLowerCase();
    return _supportedLangKeys.contains(code) ? code : 'en';
  }

  /// ar-SA 등 국가 코드 포함 로케일이 기기에 없으면 기본 언어 코드로, 그래도 없으면
  /// en-US로 재시도한다(wedi_app의 _setTtsLanguageWithFallback과 동일한 방식).
  Future<void> _setTtsLanguageWithFallback(String langKey) async {
    final locale = _langKeyToTtsLocale[langKey] ?? 'en-US';
    try {
      if (await _tts.isLanguageAvailable(locale) == true) {
        await _tts.setLanguage(locale);
        return;
      }
      final baseLang = locale.split('-').first;
      if (baseLang != locale && await _tts.isLanguageAvailable(baseLang) == true) {
        await _tts.setLanguage(baseLang);
        return;
      }
    } catch (_) {
      // isLanguageAvailable 자체가 실패하는 기기도 있으므로 무시하고 en-US로 폴백.
    }
    await _tts.setLanguage('en-US');
  }

  /// [category]에 속한 멘트 중 하나를 무작위로 골라, 기기 locale에 맞는 언어로 읽어준다.
  /// 설정에서 음성 안내를 꺼두었거나, 해당 카테고리에 멘트가 없거나, TTS 엔진 오류가 나도
  /// 조용히 무시한다(음성 안내는 부가 기능이므로 앱의 나머지 흐름을 절대 막지 않는다).
  Future<void> speak(TtsCategory category) async {
    if (!await UserProfileService.instance.getTtsEnabled()) return;

    Map<String, List<Map<String, String>>> phrases;
    try {
      phrases = await _loadPhrases();
    } catch (_) {
      return;
    }

    final pool = phrases[category.key];
    if (pool == null || pool.isEmpty) return;
    final picked = pool[_random.nextInt(pool.length)];

    final langKey = _resolveLangKey();
    final text = picked[langKey] ?? picked['en'] ?? picked.values.first;

    try {
      await _tts.stop();
      await _ensureAwaitCompletionConfigured();
      await _setTtsLanguageWithFallback(langKey);
      await _tts.speak(text);
    } catch (_) {
      // 기기에 해당 언어 음성이 없는 등 TTS 엔진 오류는 무시.
    }
  }

  /// 저장 직후 호출한다: 오늘 순칼로리가 목표 칼로리 대비 goal_met/goal_over에 해당하면
  /// 그 멘트를, 아니면 [fallback](meal_save 또는 exercise_save)을 재생한다.
  Future<void> speakAfterSave(TtsCategory fallback) async {
    if (!await UserProfileService.instance.getTtsEnabled()) return;

    final today = DateTime.now();
    final summary = await DatabaseHelper.instance.getSummary(today);
    final goalCalories = await UserProfileService.instance.getGoalCalories();

    final status = evaluateGoalStatus(
      netCalories: summary?.netCalories ?? 0,
      goalCalories: goalCalories,
      hasIntake: (summary?.totalIntake ?? 0) > 0,
    );

    switch (status) {
      case GoalStatus.met:
        await speak(TtsCategory.goalMet);
      case GoalStatus.over:
        await speak(TtsCategory.goalOver);
      case GoalStatus.unknown:
        await speak(fallback);
    }
  }
}
