import 'package:shared_preferences/shared_preferences.dart';
import '../domain/profile_repository.dart';

/// Uses the uncached API so a failed platform write cannot leave a newer
/// document in SharedPreferences' process-local cache.
final class PreferencesProfileStore implements ProfileDocumentStore {
  static const key = 'hadoken_profiles_v1';
  final SharedPreferencesAsync _preferences;
  PreferencesProfileStore([SharedPreferencesAsync? preferences])
    : _preferences = preferences ?? SharedPreferencesAsync();

  @override
  Future<String?> read() => _preferences.getString(key);
  @override
  Future<void> write(String document) => _preferences.setString(key, document);
}
