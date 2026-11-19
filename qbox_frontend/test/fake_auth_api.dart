import 'package:qbox_app/models/qbox_user.dart';
import 'package:qbox_app/onboarding_draft.dart';
import 'package:qbox_app/services/app_services.dart';
import 'package:qbox_app/services/auth_api.dart';
import 'package:qbox_app/services/session_store.dart';

/// A pretend backend for widget tests. It follows the same rules as the
/// FastAPI one: the OTP is always 123456, a mobile can register once,
/// and login needs the right PIN.
class FakeAuthApi implements AuthApi {
  FakeAuthApi() {
    _accounts[demoMobile] = _Account(
      pin: demoPin,
      user: const QboxUser(
        id: 1,
        mobile: demoMobile,
        roles: {QboxRole.business, QboxRole.customer, QboxRole.supplier},
        shop: ShopProfile(qboxId: 'QBM10001', shopName: 'Sri Rama Kirana'),
        customer: CustomerProfile(qboxId: 'QBC10001', fullName: 'Ramu'),
        supplier: SupplierProfile(
          qboxId: 'QBS10001',
          supplierName: 'Sri Venkateswara Suppliers',
        ),
      ),
    );
  }

  static const demoMobile = '9123456789';
  static const demoPin = '1234';
  static const otp = '123456';

  final Map<String, _Account> _accounts = {};
  Map<String, dynamic>? lastRegistration;

  /// When true, [me] fails as if the server could not be reached.
  bool offline = false;

  @override
  Future<OtpSent> sendOtp(String mobile, OtpPurpose purpose) async {
    final registered = _accounts.containsKey(mobile);
    if (purpose == OtpPurpose.signup && registered) {
      throw const ApiException(
        'MOBILE_REGISTERED',
        'This mobile number is already registered. Please log in',
        status: 409,
      );
    }
    if (purpose == OtpPurpose.resetPin && !registered) {
      throw const ApiException(
        'MOBILE_NOT_FOUND',
        'No QBOX account found for this mobile number',
        status: 404,
      );
    }
    return const OtpSent(resendInSeconds: 30, devOtp: otp);
  }

  @override
  Future<String> verifyOtp(String mobile, OtpPurpose purpose, String code) async {
    if (code != otp) {
      throw const ApiException(
        'OTP_WRONG',
        'Wrong OTP. Please check and try again',
        status: 400,
      );
    }
    return 'verify:${purpose.code}:$mobile';
  }

  @override
  Future<AuthResult> register(Map<String, dynamic> body) async {
    lastRegistration = body;
    final mobile = _mobileFrom(body['verificationToken'] as String, OtpPurpose.signup);
    final id = _accounts.length + 1;
    final roles = {
      for (final code in body['roles'] as List<dynamic>) roleFromCode(code as String)!,
    };
    final shop = body['shop'] as Map<String, dynamic>?;
    final customer = body['customer'] as Map<String, dynamic>?;
    final supplier = body['supplier'] as Map<String, dynamic>?;
    final user = QboxUser(
      id: id,
      mobile: mobile,
      roles: roles,
      shop: shop == null
          ? null
          : ShopProfile(qboxId: 'QBM${10000 + id}', shopName: shop['shopName'] as String),
      customer: customer == null
          ? null
          : CustomerProfile(
              qboxId: 'QBC${10000 + id}',
              fullName: customer['fullName'] as String,
            ),
      supplier: supplier == null
          ? null
          : SupplierProfile(
              qboxId: 'QBS${10000 + id}',
              supplierName: supplier['supplierName'] as String,
            ),
    );
    _accounts[mobile] = _Account(pin: body['pin'] as String, user: user);
    return AuthResult(accessToken: 'access:$mobile', user: user);
  }

  @override
  Future<AuthResult> login(String mobile, String pin) async {
    final account = _accounts[mobile];
    if (account == null || account.pin != pin) {
      throw const ApiException(
        'LOGIN_FAILED',
        'Mobile number or PIN does not match',
        status: 401,
      );
    }
    return AuthResult(accessToken: 'access:$mobile', user: account.user);
  }

  @override
  Future<void> resetPin(String verificationToken, String newPin) async {
    final mobile = _mobileFrom(verificationToken, OtpPurpose.resetPin);
    final account = _accounts[mobile]!;
    _accounts[mobile] = _Account(pin: newPin, user: account.user);
  }

  @override
  Future<QboxUser> me(String accessToken) async {
    if (offline) {
      throw const ApiException(
        'NETWORK',
        'Cannot reach the QBOX server. Check your internet connection.',
      );
    }
    final account = _accounts[accessToken.replaceFirst('access:', '')];
    if (account == null) {
      throw const ApiException('TOKEN_INVALID', 'Please log in', status: 401);
    }
    return account.user;
  }

  String _mobileFrom(String token, OtpPurpose purpose) {
    final prefix = 'verify:${purpose.code}:';
    if (!token.startsWith(prefix)) {
      throw const ApiException(
        'TOKEN_INVALID',
        'Please verify your mobile again',
        status: 401,
      );
    }
    return token.substring(prefix.length);
  }
}

class _Account {
  const _Account({required this.pin, required this.user});

  final String pin;
  final QboxUser user;
}

AppServices fakeServices({FakeAuthApi? api, SessionStore? session}) {
  return AppServices(
    auth: api ?? FakeAuthApi(),
    session: session ?? MemorySessionStore(),
  );
}
