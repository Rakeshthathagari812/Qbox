import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/qbox_user.dart';
import '../onboarding_draft.dart';

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

/// An error to show the user. [message] is already written for shopkeepers.
class ApiException implements Exception {
  const ApiException(this.code, this.message, {this.status = 0});

  final String code;
  final String message;
  final int status;

  bool get isUnauthorized => status == 401;

  @override
  String toString() => 'ApiException($code, $message)';
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
  HttpAuthApi({required this.baseUrl, http.Client? client})
      : _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;

  static const _timeout = Duration(seconds: 15);

  @override
  Future<OtpSent> sendOtp(String mobile, OtpPurpose purpose) async {
    final json = await _post('/api/auth/otp/send', {
      'mobile': mobile,
      'purpose': purpose.code,
    });
    return OtpSent(
      resendInSeconds: (json['resendInSeconds'] as num?)?.toInt() ?? 30,
      devOtp: json['devOtp'] as String?,
    );
  }

  @override
  Future<String> verifyOtp(String mobile, OtpPurpose purpose, String otp) async {
    final json = await _post('/api/auth/otp/verify', {
      'mobile': mobile,
      'purpose': purpose.code,
      'otp': otp,
    });
    return json['verificationToken'] as String;
  }

  @override
  Future<AuthResult> register(Map<String, dynamic> body) async {
    return _authResult(await _post('/api/auth/register', body));
  }

  @override
  Future<AuthResult> login(String mobile, String pin) async {
    return _authResult(
      await _post('/api/auth/login', {'mobile': mobile, 'pin': pin}),
    );
  }

  @override
  Future<void> resetPin(String verificationToken, String newPin) async {
    await _post('/api/auth/pin/reset', {
      'verificationToken': verificationToken,
      'newPin': newPin,
    });
  }

  @override
  Future<QboxUser> me(String accessToken) async {
    final json = await _send(
      () => _client.get(
        Uri.parse('$baseUrl/api/me'),
        headers: {'Authorization': 'Bearer $accessToken'},
      ),
    );
    return QboxUser.fromJson(json);
  }

  AuthResult _authResult(Map<String, dynamic> json) {
    return AuthResult(
      accessToken: json['accessToken'] as String,
      user: QboxUser.fromJson(json['user'] as Map<String, dynamic>),
    );
  }

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body) {
    return _send(
      () => _client.post(
        Uri.parse('$baseUrl$path'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      ),
    );
  }

  Future<Map<String, dynamic>> _send(
    Future<http.Response> Function() request,
  ) async {
    final http.Response response;
    try {
      response = await request().timeout(_timeout);
    } on TimeoutException {
      throw const ApiException(
        'NETWORK',
        'The QBOX server is taking too long. Please try again.',
      );
    } catch (_) {
      throw const ApiException(
        'NETWORK',
        'Cannot reach the QBOX server. Check your internet connection.',
      );
    }

    final decoded = response.body.isEmpty ? null : _decode(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return decoded is Map<String, dynamic> ? decoded : const {};
    }
    if (decoded is Map<String, dynamic> && decoded['message'] is String) {
      throw ApiException(
        decoded['code'] as String? ?? 'ERROR',
        decoded['message'] as String,
        status: response.statusCode,
      );
    }
    throw ApiException(
      'ERROR',
      'Something went wrong. Please try again.',
      status: response.statusCode,
    );
  }

  static Object? _decode(String body) {
    try {
      return jsonDecode(body);
    } on FormatException {
      return null;
    }
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
