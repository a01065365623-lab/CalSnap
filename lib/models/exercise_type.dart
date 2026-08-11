class ExerciseType {
  final String name;
  final double met;
  final String emoji;

  const ExerciseType({required this.name, required this.met, required this.emoji});
}

const List<ExerciseType> exerciseTypes = [
  ExerciseType(name: '걷기', met: 3.5, emoji: '🚶'),
  ExerciseType(name: '빠르게 걷기', met: 4.5, emoji: '🚶‍♂️'),
  ExerciseType(name: '조깅', met: 8.0, emoji: '🏃'),
  ExerciseType(name: '달리기', met: 11.0, emoji: '🏃‍♂️'),
  ExerciseType(name: '자전거', met: 7.5, emoji: '🚴'),
  ExerciseType(name: '근력운동', met: 6.0, emoji: '🏋️'),
  ExerciseType(name: '요가/스트레칭', met: 2.5, emoji: '🧘'),
  ExerciseType(name: '등산', met: 6.0, emoji: '⛰️'),
  ExerciseType(name: '수영', met: 8.0, emoji: '🏊'),
  ExerciseType(name: '계단 오르기', met: 8.8, emoji: '🪜'),
  ExerciseType(name: '기타운동', met: 0, emoji: '✏️'),
];

/// exerciseTypes 중 MET×시간 계산 대신 운동명/칼로리를 직접 입력받는 항목의 이름.
const String customExerciseName = '기타운동';

/// 기타운동 입력 화면에서 참고용으로 보여주는 빠른 선택 프리셋.
/// caloriesPer30Min은 30분 기준 대략적인 소모 칼로리 예시값이며,
/// 선택 시 사용자가 그대로 저장하거나 직접 수정할 수 있다.
class CustomExercisePreset {
  final String name;
  final double caloriesPer30Min;

  const CustomExercisePreset({required this.name, required this.caloriesPer30Min});
}

const List<CustomExercisePreset> customExercisePresets = [
  CustomExercisePreset(name: '낚시', caloriesPer30Min: 70),
  CustomExercisePreset(name: '배드민턴', caloriesPer30Min: 200),
  CustomExercisePreset(name: '골프', caloriesPer30Min: 130),
  CustomExercisePreset(name: '청소/집안일', caloriesPer30Min: 100),
  CustomExercisePreset(name: '등산(가벼운)', caloriesPer30Min: 150),
  CustomExercisePreset(name: '계단청소/육아활동', caloriesPer30Min: 120),
];

double calculateCaloriesBurned({
  required double met,
  required double weightKg,
  required int minutes,
}) {
  return met * weightKg * (minutes / 60);
}

const double defaultWeightKg = 65.0;
