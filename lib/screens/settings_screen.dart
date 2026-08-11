import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../db/database_helper.dart';
import '../dev/seed_data.dart';
import '../services/user_profile_service.dart';
import '../utils/unit_converter.dart';
import 'onboarding_screen.dart';
import 'profile_edit_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _busy = false;
  double? _goalCalories;
  String? _userId;
  UnitSystem _unitSystem = UnitSystem.metric;

  @override
  void initState() {
    super.initState();
    _loadProfileSummary();
  }

  Future<void> _loadProfileSummary() async {
    final goalCalories = await UserProfileService.instance.getGoalCalories();
    final userId = await UserProfileService.instance.getUserId();
    final unitSystem = await UserProfileService.instance.getUnitSystem();
    if (mounted) {
      setState(() {
        _goalCalories = goalCalories;
        _userId = userId;
        _unitSystem = unitSystem;
      });
    }
  }

  String get _unitSystemLabel =>
      _unitSystem == UnitSystem.metric ? '미터법 (g / kg)' : '야드파운드법 (oz / lb)';

  Future<void> _pickUnitSystem() async {
    final selected = await showDialog<UnitSystem>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('단위 선택'),
        children: [
          for (final unit in UnitSystem.values)
            RadioListTile<UnitSystem>(
              title: Text(unit == UnitSystem.metric ? '미터법 (g / kg)' : '야드파운드법 (oz / lb)'),
              value: unit,
              groupValue: _unitSystem,
              onChanged: (value) => Navigator.pop(context, value),
            ),
        ],
      ),
    );
    if (selected == null || selected == _unitSystem) return;
    await UserProfileService.instance.setUnitSystem(selected);
    if (mounted) setState(() => _unitSystem = selected);
  }

  Future<void> _openProfileEditor() async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const ProfileEditScreen()),
    );
    if (changed == true) _loadProfileSummary();
  }

  Future<void> _editUserId() async {
    final controller = TextEditingController(text: _userId ?? '');
    final newId = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('임시 사용자 ID 변경'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('저장'),
          ),
        ],
      ),
    );
    if (newId == null || newId.isEmpty) return;
    await UserProfileService.instance.setUserId(newId);
    _loadProfileSummary();
  }

  Future<void> _resetProfile() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('프로필 초기화'),
        content: const Text(
          '성별·나이·키·체중·목표 칼로리 등 프로필 정보를 모두 지우고 온보딩을 처음부터 다시 진행합니다. '
          '식사·운동 기록은 그대로 유지됩니다. 계속할까요?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('초기화')),
        ],
      ),
    );
    if (confirmed != true) return;

    await UserProfileService.instance.resetProfile();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const OnboardingScreen()),
      (route) => false,
    );
  }

  Future<void> _run(Future<String> Function() action) async {
    setState(() => _busy = true);
    try {
      final message = await action();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('실패: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String> _seed() async {
    final sw = Stopwatch()..start();
    final count = await seedOneYearOfLogs();
    sw.stop();
    return '시드 $count건 삽입 완료 (${sw.elapsedMilliseconds}ms)';
  }

  Future<String> _clear() async {
    final sw = Stopwatch()..start();
    final count = await clearSeedData();
    sw.stop();
    return '시드 $count건 삭제 완료 (${sw.elapsedMilliseconds}ms)';
  }

  Future<String> _queryRange() async {
    final sw = Stopwatch()..start();
    final now = DateTime.now();
    final entries = await DatabaseHelper.instance.getLogsForRange(
      now.subtract(const Duration(days: 364)),
      now,
    );
    sw.stop();
    return '최근 365일 조회: ${entries.length}건 (${sw.elapsedMilliseconds}ms)';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('설정')),
      body: ListView(
        children: [
          ListTile(
            title: const Text('목표 칼로리 설정'),
            subtitle: Text(
              _goalCalories != null
                  ? '${_goalCalories!.toStringAsFixed(0)} kcal/일 · 성별·나이·키·체중 기준'
                  : '정보를 입력해주세요',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: _openProfileEditor,
          ),
          ListTile(
            title: const Text('프로필 초기화 (온보딩 다시하기)'),
            subtitle: const Text('성별·나이·키·체중·목표 칼로리를 지우고 온보딩부터 다시 시작'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _resetProfile,
          ),
          ListTile(
            title: const Text('임시 사용자 ID'),
            subtitle: Text(_userId ?? '-'),
            trailing: const Icon(Icons.edit),
            onTap: _editUserId,
          ),
          ListTile(
            title: const Text('단위 (g / oz)'),
            subtitle: Text(_unitSystemLabel),
            trailing: const Icon(Icons.chevron_right),
            onTap: _pickUnitSystem,
          ),
          const ListTile(title: Text('제휴 쇼핑 추천 표시'), subtitle: Text('추후 구현')),
          if (kDebugMode) ...[
            const Divider(),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text('디버그 도구', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
            ),
            ListTile(
              leading: const Icon(Icons.dataset),
              title: const Text('1년치 테스트 데이터 생성'),
              subtitle: const Text('과거 365일, 하루 2~4건 더미 로그 삽입'),
              enabled: !_busy,
              onTap: () => _run(_seed),
            ),
            ListTile(
              leading: const Icon(Icons.search),
              title: const Text('365일 범위 조회 테스트'),
              subtitle: const Text('getLogsForRange 동작/성능 확인'),
              enabled: !_busy,
              onTap: () => _run(_queryRange),
            ),
            ListTile(
              leading: const Icon(Icons.delete_sweep),
              title: const Text('테스트 데이터 삭제'),
              subtitle: const Text('시드로 생성한 항목만 제거 (실제 기록은 유지)'),
              enabled: !_busy,
              onTap: () => _run(_clear),
            ),
            if (_busy) const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
          ],
        ],
      ),
    );
  }
}
