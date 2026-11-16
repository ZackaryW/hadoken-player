import 'package:shared_preferences/shared_preferences.dart';
import '../domain/skill_assignments.dart';

final class PreferencesSkillStore implements SkillAssignmentStore {
  static const key = 'hadoken_skills_v1';
  final SharedPreferencesAsync preferences;
  PreferencesSkillStore([SharedPreferencesAsync? preferences])
    : preferences = preferences ?? SharedPreferencesAsync();
  @override
  Future<String?> read() => preferences.getString(key);
  @override
  Future<void> write(String document) => preferences.setString(key, document);
}
