import 'package:shared_preferences/shared_preferences.dart';
import '../domain/profile_repository.dart';

/// Uses the uncached API so a failed platform write cannot leave a newer
/// document in SharedPreferences' process-local cache.
final class PreferencesProfileStore
    implements ProfileDocumentStore, ProfileMigrationStore {
  static const key = 'hadoken_profiles_v1';
  static const backupKey = 'hadoken_profiles_pre_v3';
  final SharedPreferencesAsync _preferences;
  PreferencesProfileStore([SharedPreferencesAsync? preferences])
    : _preferences = preferences ?? SharedPreferencesAsync();

  @override
  Future<String?> read() => _preferences.getString(key);
  @override
  Future<void> write(String document) => _preferences.setString(key, document);
  @override
  Future<String?> readMigrationBackup() => _preferences.getString(backupKey);
  @override
  Future<void> writeMigrationBackup(String document) =>
      _preferences.setString(backupKey, document);
}
