import 'package:shared_preferences/shared_preferences.dart';

/// Small app settings kept on the phone (chosen languages and such).
/// Not personal data, so they stay after log out.
abstract class SettingsStore {
  Future<String?> read(String key);

  Future<void> write(String key, String value);
}

class PrefsSettingsStore implements SettingsStore {
  static const _prefix = 'qbox_setting_';

  @override
  Future<String?> read(String key) async {
    try {
      return (await SharedPreferences.getInstance()).getString('$_prefix$key');
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(String key, String value) async {
    try {
      await (await SharedPreferences.getInstance()).setString('$_prefix$key', value);
    } catch (_) {}
  }
}

/// In memory only. Used by tests.
class MemorySettingsStore implements SettingsStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}
