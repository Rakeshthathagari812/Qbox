import '../models/qbox_user.dart';
import '../onboarding_draft.dart';
import 'api_client.dart';

export 'api_client.dart' show ApiException;

enum OtpPurpose {
  signup('SIGNUP'),
  resetPin('RESET_PIN');

  const OtpPurpose(this.code);
  final String code;
}

class OtpSent {
  const OtpSent({required this.resendInSeconds, this.devOtp});

  final int resendInSeconds;

  /// Only filled while the backend is in test mode (no SMS provider yet).
  final String? devOtp;
}

class AuthResult {
  const AuthResult({required this.accessToken, required this.user});

  final String accessToken;
  final QboxUser user;
}

/// Everything the app asks the backend about accounts.
abstract class AuthApi {
  Future<OtpSent> sendOtp(String mobile, OtpPurpose purpose);

  /// Returns a verification token for [register] or [resetPin].
  Future<String> verifyOtp(String mobile, OtpPurpose purpose, String otp);

  Future<AuthResult> register(Map<String, dynamic> body);

  Future<AuthResult> login(String mobile, String pin);

  Future<void> resetPin(String verificationToken, String newPin);

  Future<QboxUser> me(String accessToken);
}

/// Talks to the FastAPI backend over REST.
class HttpAuthApi implements AuthApi {
  HttpAuthApi(this._api);

  final ApiClient _api;

  @override
  Future<OtpSent> sendOtp(String mobile, OtpPurpose purpose) async {
    final json = await _map(
      _api.post('/api/auth/otp/send', {
        'mobile': mobile,
        'purpose': purpose.code,
      }, auth: false),
    );
    return OtpSent(
      resendInSeconds: (json['resendInSeconds'] as num?)?.toInt() ?? 30,
      devOtp: json['devOtp'] as String?,
    );
  }

  @override
  Future<String> verifyOtp(
    String mobile,
    OtpPurpose purpose,
    String otp,
  ) async {
    final json = await _map(
      _api.post('/api/auth/otp/verify', {
        'mobile': mobile,
        'purpose': purpose.code,
        'otp': otp,
      }, auth: false),
    );
    return json['verificationToken'] as String;
  }

  @override
  Future<AuthResult> register(Map<String, dynamic> body) async {
    return _authResult(
      await _map(_api.post('/api/auth/register', body, auth: false)),
    );
  }

  @override
  Future<AuthResult> login(String mobile, String pin) async {
    return _authResult(
      await _map(
        _api.post('/api/auth/login', {
          'mobile': mobile,
          'pin': pin,
        }, auth: false),
      ),
    );
  }

  @override
  Future<void> resetPin(String verificationToken, String newPin) async {
    await _api.post('/api/auth/pin/reset', {
      'verificationToken': verificationToken,
      'newPin': newPin,
    }, auth: false);
  }

  @override
  Future<QboxUser> me(String accessToken) async {
    return QboxUser.fromJson(
      await _map(_api.getWithToken('/api/me', accessToken)),
    );
  }

  AuthResult _authResult(Map<String, dynamic> json) {
    return AuthResult(
      accessToken: json['accessToken'] as String,
      user: QboxUser.fromJson(json['user'] as Map<String, dynamic>),
    );
  }

  static Future<Map<String, dynamic>> _map(Future<Object?> reply) async {
    final json = await reply;
    return json is Map<String, dynamic> ? json : const {};
  }
}

/// Builds the POST /api/auth/register body from what the user typed.
Map<String, dynamic> registrationBody(OnboardingDraft draft, String pin) {
  final roles = draft.orderedRoles();
  final shop = draft.shop;
  final customer = draft.customer;
  final supplier = draft.supplier;
  return {
    'verificationToken': draft.verificationToken,
    'pin': pin,
    'roles': [for (final role in roles) roleCode(role)],
    if (roles.contains(QboxRole.business))
      'shop': {
        'shopName': shop.shopName.trim(),
        'businessType': shop.businessType,
        'businessTypeDetail': shop.businessTypeDetail.trim(),
        'shopCategory': shop.shopCategory,
        'shopCategoryDetail': shop.shopCategoryDetail.trim(),
        'address': shop.address.trim(),
        'contactNumber': shop.contactNumber,
      },
    if (roles.contains(QboxRole.customer))
      'customer': {
        'fullName': customer.fullName.trim(),
        'mobileNumber': customer.mobileNumber,
        'email': customer.email.trim(),
        'address': customer.address.trim(),
        'aadhaarLinkRequested': customer.aadhaarLinkRequested,
      },
    if (roles.contains(QboxRole.supplier))
      'supplier': {
        'supplierName': supplier.supplierName.trim(),
        'businessType': supplier.businessType,
        'businessTypeDetail': supplier.businessTypeDetail.trim(),
        'productsSupplied': supplier.productsSupplied.trim(),
        'contactNumber': supplier.contactNumber,
        'address': supplier.address.trim(),
      },
  };
}
