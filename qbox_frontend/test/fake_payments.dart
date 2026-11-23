import 'package:qbox_app/payments/checkout.dart';
import 'package:qbox_app/payments/payment_models.dart';
import 'package:qbox_app/payments/payments_api.dart';
import 'package:qbox_app/services/api_client.dart';

/// A pretend payments backend. [markPaid] plays "the customer paid".
class FakePaymentsApi implements PaymentsApi {
  PaymentSettings current = const PaymentSettings();
  final Map<int, Payment> payments = {};
  final List<String> calls = [];
  ApiException? nextError;

  /// The backend's answer for "verify": paid unless set to false.
  bool verifyPays = true;
  int _next = 1;

  /// Pretend the customer paid payment [id].
  void markPaid(int id, {String? vpa = 'ramesh@okaxis'}) {
    final p = payments[id]!;
    payments[id] = _copy(p, status: PaymentStatus.paid, payerVpa: vpa, paidAt: DateTime.now());
  }

  Payment _copy(Payment p, {PaymentStatus? status, String? payerVpa, DateTime? paidAt}) => Payment(
    id: p.id,
    amountPaise: p.amountPaise,
    source: p.source,
    status: status ?? p.status,
    note: p.note,
    udhaarCustomerId: p.udhaarCustomerId,
    customerName: p.customerName,
    payerVpa: payerVpa ?? p.payerVpa,
    qrImageUrl: p.qrImageUrl,
    payUrl: p.payUrl,
    testMode: p.testMode,
    expiresAt: p.expiresAt,
    paidAt: paidAt ?? p.paidAt,
    createdAt: p.createdAt,
  );

  void _check(String call) {
    calls.add(call);
    final error = nextError;
    if (error != null) {
      nextError = null;
      throw error;
    }
  }

  Payment _add(int amountPaise, PaymentSource source, PaymentStatus status,
      {String? note, int? customerId, String? customerName}) {
    final id = _next++;
    final p = Payment(
      id: id,
      amountPaise: amountPaise,
      source: source,
      status: status,
      note: note,
      udhaarCustomerId: customerId,
      customerName: customerName,
      payUrl: source == PaymentSource.counter ? 'https://rzp.io/i/test$id' : null,
      testMode: current.testMode,
      paidAt: status == PaymentStatus.paid ? DateTime.now() : null,
      createdAt: DateTime.now(),
    );
    payments[id] = p;
    return p;
  }

  @override
  Future<PaymentSettings> settings() async {
    _check('settings');
    return current;
  }

  @override
  Future<PaymentSettings> saveUpi(String upiId, String upiName) async {
    _check('saveUpi $upiId');
    return current = PaymentSettings(
      upiId: upiId.isEmpty ? null : upiId,
      upiName: upiId.isEmpty || upiName.isEmpty ? null : upiName,
      razorpayConnected: current.razorpayConnected,
      razorpayKeyHint: current.razorpayKeyHint,
      automatic: current.automatic,
      testMode: current.testMode,
    );
  }

  @override
  Future<PaymentSettings> connectRazorpay(String keyId, String keySecret) async {
    _check('connect $keyId');
    return current = PaymentSettings(
      upiId: current.upiId,
      upiName: current.upiName,
      razorpayConnected: true,
      razorpayKeyHint: 'rzp_test_••••${keyId.substring(keyId.length - 4)}',
      automatic: true,
      testMode: keyId.startsWith('rzp_test_'),
    );
  }

  @override
  Future<PaymentSettings> disconnectRazorpay() async {
    _check('disconnect');
    return current = PaymentSettings(upiId: current.upiId, upiName: current.upiName);
  }

  @override
  Future<Payment> collect({required int amountPaise, required String clientRef, String? note, int? udhaarCustomerId}) async {
    _check('collect $amountPaise');
    return _add(amountPaise, PaymentSource.counter, PaymentStatus.waiting,
        note: note, customerId: udhaarCustomerId);
  }

  @override
  Future<Payment> recordManual({required int amountPaise, required String clientRef, String? note, int? udhaarCustomerId}) async {
    _check('manual $amountPaise');
    return _add(amountPaise, PaymentSource.manual, PaymentStatus.paid, note: note, customerId: udhaarCustomerId);
  }

  @override
  Future<Payment> payment(int id) async {
    _check('payment $id');
    return payments[id]!;
  }

  @override
  Future<Payment> cancel(int id) async {
    _check('cancel $id');
    final p = payments[id]!;
    if (p.status == PaymentStatus.waiting) payments[id] = _copy(p, status: PaymentStatus.cancelled);
    return payments[id]!;
  }

  @override
  Future<PaymentsDay> today() async {
    _check('today');
    final paid = payments.values.where((p) => p.isPaid).toList().reversed.toList();
    return PaymentsDay(totalPaise: paid.fold(0, (s, p) => s + p.amountPaise), payments: paid);
  }

  @override
  Future<UdhaarPayStart> startUdhaarPayment(int bookId, int amountPaise, String clientRef) async {
    _check('udhaar $bookId $amountPaise');
    final p = _add(amountPaise, PaymentSource.udhaar, PaymentStatus.waiting, customerId: bookId);
    return UdhaarPayStart(payment: p, keyId: 'rzp_test_KEY', orderId: 'order_$bookId', shopName: 'Lakshmi Stores', contact: '9988776655');
  }

  @override
  Future<Payment> verify(int paymentId, {required String razorpayPaymentId, required String razorpayOrderId, required String razorpaySignature}) async {
    _check('verify $paymentId $razorpayPaymentId');
    if (verifyPays) markPaid(paymentId);
    return payments[paymentId]!;
  }
}

/// Pretend Razorpay payment screen: answers with [result].
class FakeCheckout implements Checkout {
  CheckoutResult result = const CheckoutPaid(paymentId: 'pay_1', orderId: 'order_1', signature: 'sig');
  final List<UdhaarPayStart> opened = [];

  @override
  Future<CheckoutResult> pay(UdhaarPayStart start) async {
    opened.add(start);
    return result;
  }
}
