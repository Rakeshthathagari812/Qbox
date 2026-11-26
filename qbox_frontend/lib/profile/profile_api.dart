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

  /// What is still open, before deleting the account.
  Future<DeleteCheck> deleteCheck();

  /// Cannot be undone.
  Future<void> deleteAccount(String pin);

  /// How to reach QBOX. No login needed.
  Future<SupportContact> support();

  /// Which versions of the app may still be used. No login needed.
  Future<AppVersions> versions();
}

class DeleteCheck {
  const DeleteCheck({this.youOwePaise = 0, this.owedToYouPaise = 0, this.paymentsOpen = false});

  final int youOwePaise;
  final int owedToYouPaise;

  /// A payment to this shop is not finished: it must be answered first.
  final bool paymentsOpen;
}

class SupportContact {
  const SupportContact({this.name, this.phone, this.email});

  final String? name;
  final String? phone;
  final String? email;

  bool get isEmpty => name == null && phone == null && email == null;
}

class AppVersions {
  const AppVersions({this.minBuild = 0, this.updateUrl});

  /// Older builds must update. 0 = any.
  final int minBuild;
  final String? updateUrl;
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

  @override
  Future<DeleteCheck> deleteCheck() async {
    final json = await _api.get('/api/me/delete-check');
    if (json is! Map<String, dynamic>) throw _bad;
    return DeleteCheck(
      youOwePaise: json['youOwePaise'] as int? ?? 0,
      owedToYouPaise: json['owedToYouPaise'] as int? ?? 0,
      paymentsOpen: json['paymentsOpen'] == true,
    );
  }

  @override
  Future<void> deleteAccount(String pin) => _api.post('/api/me/delete', {'pin': pin});

  @override
  Future<SupportContact> support() async {
    final json = await _api.get('/api/info');
    if (json is! Map<String, dynamic>) throw _bad;
    return SupportContact(
      name: json['supportName'] as String?,
      phone: json['supportPhone'] as String?,
      email: json['supportEmail'] as String?,
    );
  }

  @override
  Future<AppVersions> versions() async {
    final json = await _api.get('/api/info', auth: false, timeout: const Duration(seconds: 6));
    if (json is! Map<String, dynamic>) throw _bad;
    return AppVersions(minBuild: json['minBuild'] as int? ?? 0, updateUrl: json['updateUrl'] as String?);
  }

  static QboxUser _user(Object? json) => json is Map<String, dynamic> ? QboxUser.fromJson(json) : throw _bad;
}
