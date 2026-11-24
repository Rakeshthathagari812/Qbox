import '../udhaar/udhaar_models.dart' show parsePaise;

/// What a scanned QR is. Nothing in a QR is trusted until the customer has
/// seen who is paid; a shop's QBOX QR is looked up on the server.
sealed class ScannedQr {
  const ScannedQr();
}

/// A shop's QBOX QR. Only its code is used; everything else comes from the server.
class ShopQr extends ScannedQr {
  const ShopQr(this.code);

  final String code;
}

/// Any other UPI QR (a PhonePe / GPay / Paytm sticker, or a counter QR with an amount).
class UpiQr extends ScannedQr {
  const UpiQr({required this.uri, required this.upiId, this.name, this.amountPaise, this.signed = false});

  final Uri uri;
  final String upiId;

  /// The name written in the QR (nobody has checked it).
  final String? name;
  final int? amountPaise;

  /// Signed by the bank: any change would make UPI apps refuse it.
  final bool signed;

  /// What to open in the UPI app. The amount is added only when the QR has none
  /// and is not signed.
  Uri linkFor(int? paise) {
    if (paise == null || amountPaise != null || signed) return uri;
    final rest = {
      for (final e in uri.queryParameters.entries)
        if (!const {'am', 'cu'}.contains(e.key.toLowerCase())) e.key: e.value,
      'am': '${paise ~/ 100}.${(paise % 100).toString().padLeft(2, '0')}',
      'cu': 'INR',
    };
    final query = rest.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&');
    return Uri.parse('upi://pay?$query');
  }
}

/// A Razorpay payment page (the counter QR while Razorpay's UPI QR is off).
class PageQr extends ScannedQr {
  const PageQr(this.uri);

  final Uri uri;
}

/// Not something QBOX can pay.
class UnknownQr extends ScannedQr {
  const UnknownQr();
}

final _code = RegExp(r'^[a-z2-7]{16}$');
final _upiId = RegExp(r'^[A-Za-z0-9._-]{2,256}@[A-Za-z0-9.]{2,64}$');

ScannedQr readQr(String text) {
  try {
    final uri = Uri.parse(text.trim());
    final params = {for (final e in uri.queryParameters.entries) e.key.toLowerCase(): e.value.trim()};
    if (uri.scheme == 'qbox' || uri.scheme == 'upi') {
      final code = params['qbox'];
      if (uri.host.toLowerCase() != 'pay') return const UnknownQr();
      if (code != null && _code.hasMatch(code)) return ShopQr(code);
    }
    if (uri.scheme == 'upi') return _upi(uri, params);
    // Only Razorpay's own short links, so a QR cannot open some other website.
    if (uri.scheme == 'https' && uri.host == 'rzp.io' && uri.userInfo.isEmpty && uri.path.length > 1) {
      return PageQr(uri);
    }
  } catch (_) {
    // Not readable as a link.
  }
  return const UnknownQr();
}

ScannedQr _upi(Uri uri, Map<String, String> params) {
  final id = params['pa'] ?? '';
  final currency = params['cu'] ?? 'INR';
  if (!_upiId.hasMatch(id) || currency.toUpperCase() != 'INR') return const UnknownQr();
  final name = params['pn'] ?? '';
  return UpiQr(
    uri: uri,
    upiId: id,
    name: name.isEmpty ? null : name,
    amountPaise: parsePaise(params['am'] ?? ''),
    signed: (params['sign'] ?? '').isNotEmpty,
  );
}
