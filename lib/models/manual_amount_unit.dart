import 'package:flutter_gen/gen_l10n/app_localizations.dart';

/// 직접 입력 화면에서 고를 수 있는 양의 단위.
enum ManualAmountUnit { gram, milliliter, serving, piece }

extension ManualAmountUnitX on ManualAmountUnit {
  String label(AppLocalizations l10n) {
    switch (this) {
      case ManualAmountUnit.gram:
        return l10n.manualEntryUnitGram;
      case ManualAmountUnit.milliliter:
        return l10n.manualEntryUnitMl;
      case ManualAmountUnit.serving:
        return l10n.manualEntryUnitServing;
      case ManualAmountUnit.piece:
        return l10n.manualEntryUnitPiece;
    }
  }

  /// 서버로 보내는 언어 독립적인 값(프롬프트에 그대로 삽입).
  String get apiValue {
    switch (this) {
      case ManualAmountUnit.gram:
        return 'g';
      case ManualAmountUnit.milliliter:
        return 'ml';
      case ManualAmountUnit.serving:
        return 'serving';
      case ManualAmountUnit.piece:
        return 'piece';
    }
  }
}

/// 음식 이름에 포함된 키워드로 흔히 쓰는 단위를 추천한다(간단한 로컬 매핑).
/// 일치하는 키워드가 없으면 [ManualAmountUnit.gram]을 기본값으로 쓴다.
const Map<String, ManualAmountUnit> _defaultUnitByFoodKeyword = {
  // 개(piece) 단위로 세는 음식
  '라면': ManualAmountUnit.piece,
  '계란': ManualAmountUnit.piece,
  '달걀': ManualAmountUnit.piece,
  '사과': ManualAmountUnit.piece,
  '바나나': ManualAmountUnit.piece,
  '빵': ManualAmountUnit.piece,
  '만두': ManualAmountUnit.piece,
  '토스트': ManualAmountUnit.piece,
  '삼각김밥': ManualAmountUnit.piece,
  // 인분(serving) 단위로 세는 음식
  '밥': ManualAmountUnit.serving,
  '국': ManualAmountUnit.serving,
  '찌개': ManualAmountUnit.serving,
  '탕': ManualAmountUnit.serving,
  '카레': ManualAmountUnit.serving,
  '면': ManualAmountUnit.serving,
  '볶음밥': ManualAmountUnit.serving,
  '비빔밥': ManualAmountUnit.serving,
  // ml 단위로 세는 음식/음료
  '물': ManualAmountUnit.milliliter,
  '우유': ManualAmountUnit.milliliter,
  '주스': ManualAmountUnit.milliliter,
  '커피': ManualAmountUnit.milliliter,
  '음료': ManualAmountUnit.milliliter,
  '두유': ManualAmountUnit.milliliter,
};

ManualAmountUnit suggestUnitForFoodName(String foodName) {
  final trimmed = foodName.trim();
  if (trimmed.isEmpty) return ManualAmountUnit.gram;
  for (final entry in _defaultUnitByFoodKeyword.entries) {
    if (trimmed.contains(entry.key)) return entry.value;
  }
  return ManualAmountUnit.gram;
}
