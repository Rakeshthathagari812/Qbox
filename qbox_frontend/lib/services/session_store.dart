import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Keeps the login token on the phone so the user stays logged in
/// after closing the app.
abstract class SessionStore {
  Future<String?> readToken();

  Future<void> saveToken(String token);

  Future<void> clear();
}

/// Stores the token encrypted, with a key kept in the phone's secure
/// hardware (Android Keystore / iOS Keychain). Other apps, backups and
/// anyone browsing the phone's files cannot read it.
class SecureSessionStore implements SessionStore {
  static const _key = 'qbox_access_token';
  static const _storage = FlutterSecureStorage();

  @override
  Future<String?> readToken() async {
    try {
      return await _storage.read(key: _key);
    } catch (_) {
      // Unreadable (for example after the phone's lock settings changed):
      // treat it as logged out rather than crashing.
      await clear();
      return null;
    }
  }

  @override
  Future<void> saveToken(String token) => _storage.write(key: _key, value: token);

  @override
  Future<void> clear() async {
    try {
      await _storage.delete(key: _key);
    } catch (_) {
      // Nothing saved, or storage unavailable: either way nothing to clear.
    }
  }
}

/// Keeps the token in memory only. Used by tests.
class MemorySessionStore implements SessionStore {
  String? _token;

  @override
  Future<String?> readToken() async => _token;

  @override
  Future<void> saveToken(String token) async => _token = token;

  @override
  Future<void> clear() async => _token = null;
}
