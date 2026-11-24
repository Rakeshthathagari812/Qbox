import 'dart:convert';
import 'dart:typed_data';

import '../models/qbox_user.dart';
import '../onboarding_draft.dart';
import '../services/api_client.dart';

/// The logged-in user's own details, photos and PIN. Needs login.
abstract class ProfileApi {
  /// [details] as the server wants them for that role.
  Future<QboxUser> edit(QboxRole role, Map<String, dynamic> details);

  /// One more role for this account. [details] as for [edit].
  Future<QboxUser> addRole(QboxRole role, String pin, Map<String, dynamic> details);

  Future<QboxUser> setPhoto(QboxRole role, Uint8List jpeg);

  Future<QboxUser> removePhoto(QboxRole role);

  Future<Uint8List> photo(String ref);

  /// Returns this phone's new login token; other phones are logged out.
  Future<String> changePin(String oldPin, String newPin);

  Future<void> logOutAll();
}

class HttpProfileApi implements ProfileApi {
  HttpProfileApi(this._api);

  final ApiClient _api;

  static const _bad = ApiException('ERROR', 'Something went wrong. Please try again.');

  static String _path(QboxRole role) => switch (role) {
    QboxRole.business => 'shop',
    QboxRole.customer => 'customer',
    QboxRole.supplier => 'supplier',
  };

  @override
  Future<QboxUser> edit(QboxRole role, Map<String, dynamic> details) async =>
      _user(await _api.put('/api/me/${_path(role)}', details));

  @override
  Future<QboxUser> addRole(QboxRole role, String pin, Map<String, dynamic> details) async =>
      _user(await _api.post('/api/me/roles', {'role': roleCode(role), 'pin': pin, _path(role): details}));

  @override
  Future<QboxUser> setPhoto(QboxRole role, Uint8List jpeg) async =>
      _user(await _api.put('/api/me/photo/${roleCode(role)}', {'jpeg': base64Encode(jpeg)}));

  @override
  Future<QboxUser> removePhoto(QboxRole role) async => _user(await _api.delete('/api/me/photo/${roleCode(role)}'));

  @override
  Future<Uint8List> photo(String ref) async {
    final json = await _api.get('/api/photos/$ref');
    final jpeg = json is Map<String, dynamic> ? json['jpeg'] : null;
    if (jpeg is! String) throw _bad;
    try {
      return base64Decode(jpeg);
    } on FormatException {
      throw _bad;
    }
  }

  @override
  Future<String> changePin(String oldPin, String newPin) async {
    final json = await _api.post('/api/me/pin', {'oldPin': oldPin, 'newPin': newPin});
    final token = json is Map<String, dynamic> ? json['accessToken'] : null;
    if (token is! String) throw _bad;
    return token;
  }

  @override
  Future<void> logOutAll() => _api.post('/api/me/logout-all', {});

  static QboxUser _user(Object? json) => json is Map<String, dynamic> ? QboxUser.fromJson(json) : throw _bad;
}
