/// [id]는 화면에 보여주는 이름이 아니라, 로케일과 무관하게 고정된 식별자다(비교/저장용).
/// 실제 표시 라벨은 화면에서 id를 기준으로 AppLocalizations에서 조회한다.
class ExerciseType {
  final String id;
  final double met;
  final String emoji;

  const ExerciseType({required this.id, required this.met, required this.emoji});
}

const List<ExerciseType> exerciseTypes = [
  ExerciseType(id: 'walk', met: 3.5, emoji: '🚶'),
  ExerciseType(id: 'briskWalk', met: 4.5, emoji: '🚶‍♂️'),
  ExerciseType(id: 'jog', met: 8.0, emoji: '🏃'),
  ExerciseType(id: 'run', met: 11.0, emoji: '🏃‍♂️'),
  ExerciseType(id: 'cycle', met: 7.5, emoji: '🚴'),
  ExerciseType(id: 'strength', met: 6.0, emoji: '🏋️'),
  ExerciseType(id: 'yoga', met: 2.5, emoji: '🧘'),
  ExerciseType(id: 'hike', met: 6.0, emoji: '⛰️'),
  ExerciseType(id: 'swim', met: 8.0, emoji: '🏊'),
  ExerciseType(id: 'stairs', met: 8.8, emoji: '🪜'),
  ExerciseType(id: 'other', met: 0, emoji: '✏️'),
];

/// exerciseTypes 중 MET×시간 계산 대신 운동명/칼로리를 직접 입력받는 항목의 id.
const String customExerciseId = 'other';

/// 기타운동 입력 화면에서 참고용으로 보여주는 빠른 선택 프리셋.
/// caloriesPer30Min은 30분 기준 대략적인 소모 칼로리 예시값이며,
/// 선택 시 사용자가 그대로 저장하거나 직접 수정할 수 있다.
class CustomExercisePreset {
  final String id;
  final double caloriesPer30Min;

  const CustomExercisePreset({required this.id, required this.caloriesPer30Min});
}

const List<CustomExercisePreset> customExercisePresets = [
  CustomExercisePreset(id: 'fishing', caloriesPer30Min: 70),
  CustomExercisePreset(id: 'badminton', caloriesPer30Min: 200),
  CustomExercisePreset(id: 'golf', caloriesPer30Min: 130),
  CustomExercisePreset(id: 'housework', caloriesPer30Min: 100),
  CustomExercisePreset(id: 'lightHike', caloriesPer30Min: 150),
  CustomExercisePreset(id: 'stairsChildcare', caloriesPer30Min: 120),
];

double calculateCaloriesBurned({
  required double met,
  required double weightKg,
  required int minutes,
}) {
  return met * weightKg * (minutes / 60);
}

const double defaultWeightKg = 65.0;
