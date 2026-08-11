import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../utils/bmr_calculator.dart';
import '../utils/unit_converter.dart';

class UserProfile {
  final Gender gender;
  final int age;
  final double heightCm;
  final double weightKg;

  const UserProfile({
    required this.gender,
    required this.age,
    required this.heightCm,
    required this.weightKg,
  });
}

/// 회원가입 없이 로컬(SharedPreferences)에만 저장되는 최소 프로필.
/// 온보딩 완료 여부, 임시 사용자 ID(UUID), 성별/나이/키/체중, 계산된 목표 칼로리를 보관한다.
class UserProfileService {
  UserProfileService._internal();
  static final UserProfileService instance = UserProfileService._internal();

  static const _keyOnboardingComplete = 'onboarding_complete';
  static const _keyUserId = 'user_id';
  static const _keyGender = 'profile_gender';
  static const _keyAge = 'profile_age';
  static const _keyHeightCm = 'profile_height_cm';
  static const _keyWeightKg = 'profile_weight_kg';
  static const _keyGoalCalories = 'profile_goal_calories';
  static const _keyUnitSystem = 'unit_system';

  Future<bool> isOnboardingComplete() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyOnboardingComplete) ?? false;
  }

  /// 온보딩 마지막 단계에서 호출: 프로필 저장 + 임시 사용자 ID 발급 + 완료 플래그 설정.
  Future<void> completeOnboarding(UserProfile profile) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyUserId, const Uuid().v4());
    await saveProfile(profile);
    await prefs.setBool(_keyOnboardingComplete, true);
  }

  /// 성별/나이/키/체중을 저장한다.
  /// [goalCaloriesOverride]를 주면 그 값을 목표 칼로리로 그대로 저장하고(사용자가 직접 수정한 값),
  /// 생략하면 BMR 공식으로 계산한 값을 저장한다.
  Future<void> saveProfile(UserProfile profile, {double? goalCaloriesOverride}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyGender, profile.gender.name);
    await prefs.setInt(_keyAge, profile.age);
    await prefs.setDouble(_keyHeightCm, profile.heightCm);
    await prefs.setDouble(_keyWeightKg, profile.weightKg);
    await prefs.setDouble(
      _keyGoalCalories,
      goalCaloriesOverride ??
          calculateGoalCalories(
            gender: profile.gender,
            age: profile.age,
            heightCm: profile.heightCm,
            weightKg: profile.weightKg,
          ),
    );
  }

  Future<UserProfile?> getProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final genderStr = prefs.getString(_keyGender);
    final age = prefs.getInt(_keyAge);
    final height = prefs.getDouble(_keyHeightCm);
    final weight = prefs.getDouble(_keyWeightKg);
    if (genderStr == null || age == null || height == null || weight == null) return null;
    return UserProfile(
      gender: Gender.values.byName(genderStr),
      age: age,
      heightCm: height,
      weightKg: weight,
    );
  }

  Future<double?> getGoalCalories() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_keyGoalCalories);
  }

  Future<String?> getUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyUserId);
  }

  Future<void> setUserId(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyUserId, id);
  }

  /// 온보딩을 처음부터 다시 하도록 프로필 관련 데이터를 초기화한다. 임시 사용자 ID는
  /// 유지한다(completeOnboarding이 다음 온보딩 완료 시 어차피 새 ID를 발급하며,
  /// 단위 설정처럼 프로필과 무관한 값들도 그대로 둔다).
  Future<void> resetProfile() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyOnboardingComplete);
    await prefs.remove(_keyGender);
    await prefs.remove(_keyAge);
    await prefs.remove(_keyHeightCm);
    await prefs.remove(_keyWeightKg);
    await prefs.remove(_keyGoalCalories);
  }

  /// 화면 표시 단위(g/kg 미터법 vs oz/lb 야드파운드법). 저장은 항상 metric 기준으로
  /// 이루어지며, 이 설정은 화면에 보여줄 때 변환 여부만 결정한다. 기본값은 metric.
  Future<UnitSystem> getUnitSystem() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_keyUnitSystem);
    if (value == null) return UnitSystem.metric;
    return UnitSystem.values.byName(value);
  }

  Future<void> setUnitSystem(UnitSystem unit) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyUnitSystem, unit.name);
  }

  /// 저장된 체중이 있으면 그 값을, 없으면 [fallback]을 반환한다.
  /// (운동 화면 등에서 defaultWeightKg 하드코딩 대신 실제 체중을 쓰기 위함)
  Future<double> getWeightKgOrDefault(double fallback) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_keyWeightKg) ?? fallback;
  }
}
