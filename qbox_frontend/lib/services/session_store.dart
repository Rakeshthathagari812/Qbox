import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/qbox_user.dart';

/// Keeps the login token, and a copy of the account details, on the phone,
/// so the user stays logged in after closing the app and can open it offline.
abstract class SessionStore {
  Future<String?> readToken();

  Future<void> saveToken(String token);

  /// The account details from the last time the server was reached.
  Future<QboxUser?> readUser();

  Future<void> saveUser(QboxUser user);

  /// Forgets the token and the account details (log out).
  Future<void> clear();
}

/// Stores everything encrypted, with a key kept in the phone's secure
/// hardware (Android Keystore / iOS Keychain). Other apps, backups and
/// anyone browsing the phone's files cannot read it.
class SecureSessionStore implements SessionStore {
  static const _tokenKey = 'qbox_access_token';
  static const _userKey = 'qbox_user';
  static const _storage = FlutterSecureStorage();

  @override
  Future<String?> readToken() => _read(_tokenKey);

  @override
  Future<void> saveToken(String token) =>
      _storage.write(key: _tokenKey, value: token);

  @override
  Future<QboxUser?> readUser() async {
    final text = await _read(_userKey);
    if (text == null) return null;
    try {
      return QboxUser.fromJson(jsonDecode(text) as Map<String, dynamic>);
    } catch (_) {
      return null; // damaged copy: the app simply needs the server once
    }
  }

  @override
  Future<void> saveUser(QboxUser user) =>
      _storage.write(key: _userKey, value: jsonEncode(user.toJson()));

  @override
  Future<void> clear() async {
    for (final key in [_tokenKey, _userKey]) {
      try {
        await _storage.delete(key: key);
      } catch (_) {
        // Nothing saved, or storage unavailable: either way nothing to clear.
      }
    }
  }

  Future<String?> _read(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (_) {
      // Unreadable (for example after the phone's lock settings changed):
      // treat it as logged out rather than crashing.
      await clear();
      return null;
    }
  }
}

/// Keeps everything in memory only. Used by tests.
class MemorySessionStore implements SessionStore {
  String? _token;
  QboxUser? _user;

  @override
  Future<String?> readToken() async => _token;

  @override
  Future<void> saveToken(String token) async => _token = token;

  @override
  Future<QboxUser?> readUser() async => _user;

  @override
  Future<void> saveUser(QboxUser user) async => _user = user;

  @override
  Future<void> clear() async {
    _token = null;
    _user = null;
  }
}
