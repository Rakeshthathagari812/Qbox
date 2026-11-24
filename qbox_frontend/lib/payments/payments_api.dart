import '../services/api_client.dart';
import 'payment_models.dart';

/// Everything the app asks the backend about payments. Needs login.
abstract class PaymentsApi {
  // Shop side
  Future<PaymentSettings> settings();

  /// Saves the shop's own UPI ID (empty removes it).
  Future<PaymentSettings> saveUpi(String upiId, String upiName);

  /// Connects the shop's own Razorpay account (checked with Razorpay first).
  Future<PaymentSettings> connectRazorpay(String keyId, String keySecret);

  Future<PaymentSettings> disconnectRazorpay();

  /// A one-time QR for this amount; Razorpay confirms the payment by itself.
  Future<Payment> collect({
    required int amountPaise,
    required String clientRef,
    String? note,
    int? udhaarCustomerId,
  });

  /// Records money paid to the shop's own UPI ID (confirmed by the shop).
  Future<Payment> recordManual({
    required int amountPaise,
    required String clientRef,
    String? note,
    int? udhaarCustomerId,
  });

  /// One payment (the backend checks Razorpay while it is waiting).
  Future<Payment> payment(int id);

  Future<Payment> cancel(int id);

  /// Everything paid today.
  Future<PaymentsDay> today();

  // Customer side
  Future<UdhaarPayStart> startUdhaarPayment(int bookId, int amountPaise, String clientRef);

  /// Shops the customer can pay: linked, and paid before.
  Future<PayShops> payShops();

  /// The shop with this QBOX login number (limited per hour).
  Future<PayShop> findShop(String mobile);

  /// The shop whose QBOX QR was scanned.
  Future<PayShop> scanShop(String code);

  /// Shop side: its own QR.
  Future<ShopQrCode> shopQr();

  /// [upi] = the shop's own UPI ID; otherwise Razorpay's payment screen.
  Future<ShopPayStart> startShopPayment(PayShop shop, int amountPaise, String clientRef, {required bool upi, String? note});

  /// "I paid by UPI" (the shop confirms) / "I did not pay".
  Future<Payment> claimUpi(int paymentId);
  Future<Payment> dropUpi(int paymentId);

  // Shop side: did the customer's UPI money come?
  Future<Payment> answerUpi(int paymentId, {required bool received});

  /// What Razorpay's payment screen returned, checked by the backend.
  Future<Payment> verify(int paymentId, {
    required String razorpayPaymentId,
    required String razorpayOrderId,
    required String razorpaySignature,
  });
}

class HttpPaymentsApi implements PaymentsApi {
  HttpPaymentsApi(this._api);

  final ApiClient _api;

  static const _base = '/api/payments';

  /// Making a QR or order waits for Razorpay too.
  static const _slow = Duration(seconds: 30);

  @override
  Future<PaymentSettings> settings() async =>
      _read(await _api.get('$_base/settings'), PaymentSettings.fromJson);

  @override
  Future<PaymentSettings> saveUpi(String upiId, String upiName) async => _read(
    await _api.put('$_base/settings/upi', {'upiId': upiId, 'upiName': upiName}),
    PaymentSettings.fromJson,
  );

  @override
  Future<PaymentSettings> connectRazorpay(String keyId, String keySecret) async => _read(
    await _api.post('$_base/settings/razorpay', {'keyId': keyId, 'keySecret': keySecret}, timeout: _slow),
    PaymentSettings.fromJson,
  );

  @override
  Future<PaymentSettings> disconnectRazorpay() async =>
      _read(await _api.delete('$_base/settings/razorpay'), PaymentSettings.fromJson);

  @override
  Future<Payment> collect({
    required int amountPaise,
    required String clientRef,
    String? note,
    int? udhaarCustomerId,
  }) async => _read(
    await _api.post('$_base/collect', {
      'amountPaise': amountPaise,
      'clientRef': clientRef,
      'note': note,
      'udhaarCustomerId': udhaarCustomerId,
    }, timeout: _slow),
    Payment.fromJson,
  );

  @override
  Future<Payment> recordManual({
    required int amountPaise,
    required String clientRef,
    String? note,
    int? udhaarCustomerId,
  }) async => _read(
    await _api.post('$_base/manual', {
      'amountPaise': amountPaise,
      'clientRef': clientRef,
      'note': note,
      'udhaarCustomerId': udhaarCustomerId,
    }),
    Payment.fromJson,
  );

  @override
  Future<Payment> payment(int id) async =>
      _read(await _api.get('$_base/$id', timeout: _slow), Payment.fromJson);

  @override
  Future<Payment> cancel(int id) async =>
      _read(await _api.post('$_base/$id/cancel', {}, timeout: _slow), Payment.fromJson);

  @override
  Future<PaymentsDay> today() async =>
      _read(await _api.get(_base, timeout: _slow), PaymentsDay.fromJson);

  @override
  Future<UdhaarPayStart> startUdhaarPayment(int bookId, int amountPaise, String clientRef) async => _read(
    await _api.post('$_base/udhaar/$bookId', {'amountPaise': amountPaise, 'clientRef': clientRef}, timeout: _slow),
    UdhaarPayStart.fromJson,
  );

  @override
  Future<PayShops> payShops() async => _read(await _api.get('$_base/shops'), PayShops.fromJson);

  @override
  Future<PayShop> findShop(String mobile) async =>
      _read(await _api.post('$_base/shops/find', {'mobile': mobile}), PayShop.fromJson);

  @override
  Future<PayShop> scanShop(String code) async =>
      _read(await _api.post('$_base/shops/scan', {'code': code}), PayShop.fromJson);

  @override
  Future<ShopQrCode> shopQr() async => _read(await _api.get('$_base/settings/qr'), ShopQrCode.fromJson);

  @override
  Future<ShopPayStart> startShopPayment(PayShop shop, int amountPaise, String clientRef,
      {required bool upi, String? note}) async => _read(
    await _api.post('$_base/shop', {
      'ref': shop.ref,
      'amountPaise': amountPaise,
      'method': upi ? 'UPI' : 'ONLINE',
      'note': note,
      'clientRef': clientRef,
    }, timeout: _slow),
    ShopPayStart.fromJson,
  );

  @override
  Future<Payment> claimUpi(int paymentId) async =>
      _read(await _api.post('$_base/$paymentId/claim', {}), Payment.fromJson);

  @override
  Future<Payment> dropUpi(int paymentId) async =>
      _read(await _api.post('$_base/$paymentId/drop', {}), Payment.fromJson);

  @override
  Future<Payment> answerUpi(int paymentId, {required bool received}) async =>
      _read(await _api.post('$_base/$paymentId/${received ? 'confirm' : 'not-received'}', {}), Payment.fromJson);

  @override
  Future<Payment> verify(int paymentId, {
    required String razorpayPaymentId,
    required String razorpayOrderId,
    required String razorpaySignature,
  }) async => _read(
    await _api.post('$_base/$paymentId/verify', {
      'razorpayPaymentId': razorpayPaymentId,
      'razorpayOrderId': razorpayOrderId,
      'razorpaySignature': razorpaySignature,
    }, timeout: _slow),
    Payment.fromJson,
  );

  static T _read<T>(Object? json, T? Function(Object?) read) {
    final value = read(json);
    if (value == null) {
      throw const ApiException('ERROR', 'Something went wrong. Please try again.');
    }
    return value;
  }
}
