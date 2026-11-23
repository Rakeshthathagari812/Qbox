import '../translator/languages.dart';
import '../udhaar/udhaar_models.dart' show rupees;

/// How the shop takes payments.
class PaymentSettings {
  const PaymentSettings({
    this.upiId,
    this.upiName,
    this.razorpayConnected = false,
    this.razorpayKeyHint,
    this.automatic = false,
    this.testMode = false,
    this.usingTestAccount = false,
  });

  /// The shop's own UPI ID (payments to it are confirmed by hand).
  final String? upiId;
  final String? upiName;

  /// The shop's own Razorpay account is connected.
  final bool razorpayConnected;
  final String? razorpayKeyHint;

  /// Payments are confirmed by themselves ("₹250 received").
  final bool automatic;

  /// Pretend money only (Razorpay test keys).
  final bool testMode;

  /// Using QBOX's test account (development only).
  final bool usingTestAccount;

  bool get hasUpi => (upiId ?? '').isNotEmpty;

  /// Some way to take a payment is set up.
  bool get canCollect => automatic || hasUpi;

  static PaymentSettings? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    return PaymentSettings(
      upiId: json['upiId'] as String?,
      upiName: json['upiName'] as String?,
      razorpayConnected: json['razorpayConnected'] == true,
      razorpayKeyHint: json['razorpayKeyHint'] as String?,
      automatic: json['automatic'] == true,
      testMode: json['testMode'] == true,
      usingTestAccount: json['usingTestAccount'] == true,
    );
  }
}

enum PaymentSource {
  counter('COUNTER', 'UPI QR'),
  udhaar('UDHAAR', 'Udhaar paid in QBOX'),
  manual('MANUAL', 'UPI (confirmed by you)');

  const PaymentSource(this.code, this.label);

  final String code;
  final String label;

  static PaymentSource fromCode(Object? code) =>
      values.firstWhere((s) => s.code == code, orElse: () => PaymentSource.counter);
}

enum PaymentStatus {
  waiting('WAITING'),
  paid('PAID'),
  expired('EXPIRED'),
  cancelled('CANCELLED');

  const PaymentStatus(this.code);

  final String code;

  static PaymentStatus fromCode(Object? code) =>
      values.firstWhere((s) => s.code == code, orElse: () => PaymentStatus.waiting);
}

class Payment {
  const Payment({
    required this.id,
    required this.amountPaise,
    this.source = PaymentSource.counter,
    this.status = PaymentStatus.waiting,
    this.note,
    this.udhaarCustomerId,
    this.customerName,
    this.payerVpa,
    this.method,
    this.qrImageUrl,
    this.payUrl,
    this.testMode = false,
    this.expiresAt,
    this.paidAt,
    this.createdAt,
  });

  final int id;
  final int amountPaise;
  final PaymentSource source;
  final PaymentStatus status;
  final String? note;
  final int? udhaarCustomerId;
  final String? customerName;

  /// The UPI ID the money came from (e.g. ramesh@okaxis).
  final String? payerVpa;
  final String? method;

  /// A ready QR picture from Razorpay, or a payment page to draw as a QR.
  final String? qrImageUrl;
  final String? payUrl;
  final bool testMode;
  final DateTime? expiresAt;
  final DateTime? paidAt;
  final DateTime? createdAt;

  bool get isPaid => status == PaymentStatus.paid;

  /// Who paid, as well as QBOX knows: the udhaar customer, or their UPI ID.
  String? get payer => customerName ?? payerVpa;

  static Payment? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final id = json['id'];
    final amount = json['amountPaise'];
    if (id is! int || amount is! int) return null;
    return Payment(
      id: id,
      amountPaise: amount,
      source: PaymentSource.fromCode(json['source']),
      status: PaymentStatus.fromCode(json['status']),
      note: json['note'] as String?,
      udhaarCustomerId: json['udhaarCustomerId'] as int?,
      customerName: json['customerName'] as String?,
      payerVpa: json['payerVpa'] as String?,
      method: json['method'] as String?,
      qrImageUrl: json['qrImageUrl'] as String?,
      payUrl: json['payUrl'] as String?,
      testMode: json['testMode'] == true,
      expiresAt: _time(json['expiresAt']),
      paidAt: _time(json['paidAt']),
      createdAt: _time(json['createdAt']),
    );
  }
}

/// Everything paid to the shop on one day.
class PaymentsDay {
  const PaymentsDay({required this.totalPaise, required this.payments});

  final int totalPaise;
  final List<Payment> payments;

  static PaymentsDay? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final list = json['payments'];
    if (list is! List) return null;
    return PaymentsDay(
      totalPaise: json['totalPaise'] as int? ?? 0,
      payments: list.map(Payment.fromJson).whereType<Payment>().toList(),
    );
  }
}

/// What the app needs to open Razorpay's payment screen for an udhaar payment.
class UdhaarPayStart {
  const UdhaarPayStart({
    required this.payment,
    required this.keyId,
    required this.orderId,
    required this.shopName,
    required this.contact,
  });

  final Payment payment;
  final String keyId;
  final String orderId;
  final String shopName;
  final String contact;

  static UdhaarPayStart? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final payment = Payment.fromJson(json['payment']);
    final key = json['keyId'];
    final order = json['orderId'];
    if (payment == null || key is! String || order is! String) return null;
    return UdhaarPayStart(
      payment: payment,
      keyId: key,
      orderId: order,
      shopName: json['shopName'] as String? ?? 'Shop',
      contact: json['contact'] as String? ?? '',
    );
  }
}

/// A standard UPI payment link for the shop's own UPI ID, with the amount
/// filled in. Any UPI app (PhonePe, GPay, Paytm) reads it as a QR.
String upiLink({required String upiId, String? name, required int amountPaise, String? note}) {
  final params = <String, String>{
    'pa': upiId,
    if ((name ?? '').isNotEmpty) 'pn': name!,
    'am': (amountPaise / 100).toStringAsFixed(2),
    'cu': 'INR',
    if ((note ?? '').isNotEmpty) 'tn': note!,
  };
  final query = params.entries
      .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
      .join('&');
  return 'upi://pay?$query';
}

/// "₹250 received" said out loud in the shop's language (with the payer's
/// name when known).
String receivedWords(int paise, AppLanguage language, {String? from}) {
  final amount = rupees(paise).replaceAll('₹', '').replaceAll(',', '');
  final name = (from ?? '').trim();
  final hasName = name.isNotEmpty && !name.contains('@');
  return switch (language) {
    AppLanguage.telugu => hasName ? '$name నుండి $amount రూపాయలు వచ్చాయి' : '$amount రూపాయలు వచ్చాయి',
    AppLanguage.hindi => hasName ? '$name से $amount रुपये मिले' : '$amount रुपये मिले',
    AppLanguage.kannada => hasName ? '$name ಅವರಿಂದ $amount ರೂಪಾಯಿ ಬಂದಿದೆ' : '$amount ರೂಪಾಯಿ ಬಂದಿದೆ',
    AppLanguage.tamil => hasName ? '$name இடமிருந்து $amount ரூபாய் வந்துள்ளது' : '$amount ரூபாய் வந்துள்ளது',
    AppLanguage.english => hasName ? '$amount rupees received from $name' : '$amount rupees received',
  };
}

DateTime? _time(Object? v) => v is String ? DateTime.tryParse(v)?.toLocal() : null;
