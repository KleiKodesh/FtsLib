import 'package:shared_preferences/shared_preferences.dart';

/// Persists user settings using SharedPreferences.
/// Mirrors the C# SettingsService.
class SettingsService {
  static const _keyDbPath = 'IndexedDbPath';

  final SharedPreferences _prefs;

  SettingsService(this._prefs);

  String get indexedDbPath => _prefs.getString(_keyDbPath) ?? '';

  Future<void> setIndexedDbPath(String path) =>
      _prefs.setString(_keyDbPath, path);
}
