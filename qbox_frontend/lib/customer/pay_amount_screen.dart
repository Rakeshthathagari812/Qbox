import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../payments/checkout.dart';
import '../payments/payment_models.dart';
import '../services/api_client.dart';
import '../services/app_services.dart';
import '../udhaar/my_udhaar_screen.dart';
import '../udhaar/udhaar_models.dart';
import '../profile/photos.dart';
import '../udhaar/udhaar_widgets.dart';

/// Pay one shop: check its name, type the amount, then pay on Razorpay's screen
/// (confirmed by itself) or in a UPI app (the shop confirms).
class PayAmountScreen extends StatefulWidget {
  const PayAmountScreen({required this.shop, super.key});

  final PayShop shop;

  @override
  State<PayAmountScreen> createState() => _PayAmountScreenState();
}

class _PayAmountScreenState extends State<PayAmountScreen> {
  final _amount = TextEditingController();
  final _note = TextEditingController();
  AppServices? _services;
  String? _amountError;
  String? _message;
  bool _busy = false;

  /// What was paid (or said to be paid); shown instead of the form.
  ({String title, String text, bool waiting})? _done;

  /// The same payment retried (e.g. after losing internet) keeps its id, so the
  /// server makes it only once.
  String _request = '';
  String _clientRef = newClientRef();

  AppServices get _app => _services!;
  PayShop get _shop => widget.shop;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _services ??= ServicesScope.of(context);
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pay({required bool upi}) async {
    final paise = parsePaise(_amount.text);
    if (paise == null || paise < 100) {
      setState(() => _amountError = 'Enter at least ₹1');
      return;
    }
    if (paise > 100000000) {
      setState(() => _amountError = 'Enter up to ₹10,00,000');
      return;
    }
    FocusScope.of(context).unfocus();
    final request = '$upi $paise ${_note.text.trim()}';
    if (request != _request) {
      _request = request;
      _clientRef = newClientRef();
    }
    setState(() {
      _amountError = null;
      _message = null;
      _busy = true;
    });
    try {
      final start = await _app.payments.startShopPayment(_shop, paise, _clientRef, upi: upi, note: _note.text.trim());
      if (!mounted) return;
      upi ? await _payByUpi(start) : await _payOnline(start);
      _request = ''; // the next payment is a new one
    } on ApiException catch (e) {
      if (mounted) setState(() => _message = e.isNetwork ? 'Paying needs internet. Please try again.' : e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _payOnline(ShopPayStart start) async {
    final result = await _app.checkout.pay(
      UdhaarPayStart(
        payment: start.payment,
        keyId: start.keyId ?? '',
        orderId: start.orderId ?? '',
        shopName: start.shopName,
        contact: start.contact,
        description: 'Payment to shop',
      ),
    );
    if (!mounted) return;
    switch (result) {
      case CheckoutCancelled():
        setState(() => _message = 'Payment cancelled. No money was taken.');
      case CheckoutFailed(:final message):
        setState(() => _message = message);
      case CheckoutPaid(:final paymentId, :final orderId, :final signature):
        var paid = false;
        var text = 'Your payment is being checked. It will show in Transaction History. Please do not pay again.';
        try {
          final payment = await _app.payments.verify(
            start.payment.id,
            razorpayPaymentId: paymentId,
            razorpayOrderId: orderId,
            razorpaySignature: signature,
          );
          paid = payment.isPaid;
        } on ApiException catch (e) {
          if (!e.isNetwork) text = e.message;
        }
        if (!mounted) return;
        setState(
          () => _done = paid
              ? (title: 'Paid ${rupees(start.payment.amountPaise)}', text: 'to ${start.shopName}', waiting: false)
              : (title: 'Checking payment', text: text, waiting: true),
        );
    }
  }

  Future<void> _payByUpi(ShopPayStart start) async {
    final id = start.payment.id;
    final upiId = start.upiId ?? '';
    final link = upiLink(
      upiId: upiId,
      name: start.upiName ?? start.shopName,
      amountPaise: start.payment.amountPaise,
      note: start.payment.note,
    );
    if (!await _app.device.openLink(Uri.parse(link))) {
      await _quietly(() => _app.payments.dropUpi(id));
      if (mounted) setState(() => _message = 'No UPI app could open. You can pay $upiId from any UPI app.');
      return;
    }
    if (!mounted) return;
    setState(() => _busy = false); // waiting for the customer, not the network
    final paid = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Did the payment go through?'),
        content: Text('${rupees(start.payment.amountPaise)} to ${start.shopName} in your UPI app.'),
        actions: [
          TextButton(
            key: const Key('upi-no'),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('No'),
          ),
          FilledButton(
            key: const Key('upi-yes'),
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: udPaid),
            child: const Text('Yes, I paid'),
          ),
        ],
      ),
    );
    if (paid == null || !mounted) return; // asked again on the Pay to Shop screen
    setState(() => _busy = true);
    final sent = await _quietly(() => paid ? _app.payments.claimUpi(id) : _app.payments.dropUpi(id));
    if (!mounted) return;
    if (!paid) {
      setState(() => _message = 'Not paid. Nothing was recorded.');
    } else {
      setState(
        () => _done = (
          title: 'Waiting for ${start.shopName}',
          text: sent
              ? 'The shop will check its bank and confirm ${rupees(start.payment.amountPaise)}.'
              : 'No internet now. Open Pay to Shop later and answer "Yes, I paid".',
          waiting: true,
        ),
      );
    }
  }

  /// False when it could not be sent (the question is asked again later).
  Future<bool> _quietly(Future<Object?> Function() send) async {
    try {
      await send();
      return true;
    } on ApiException {
      return false;
    }
  }

  Future<void> _payUdhaar() => Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => MyBookScreen(
        book: MyBook(bookId: _shop.bookId!, shopName: _shop.shopName, balancePaise: _shop.duePaise),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final done = _done;
    return Scaffold(
      backgroundColor: udBackground,
      body: SafeArea(
        child: Column(
          children: [
            UdHeader(title: 'Pay to Shop', subtitle: _shop.shopName, busy: _busy),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: done == null ? _form() : _result(done),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _result(({String title, String text, bool waiting}) done) => [
    const SizedBox(height: 48),
    Icon(
      done.waiting ? Icons.hourglass_top_rounded : Icons.check_circle_rounded,
      size: 88,
      color: done.waiting ? udWarn : udPaid,
    ),
    const SizedBox(height: 16),
    Text(
      done.title,
      key: const Key('pay-done'),
      textAlign: TextAlign.center,
      style: udText(24, weight: FontWeight.w800),
    ),
    const SizedBox(height: 8),
    Text(done.text, textAlign: TextAlign.center, style: udText(14, color: udBody)),
    const SizedBox(height: 32),
    _button('pay-close', 'Done', udPurple, () => Navigator.of(context).pop()),
  ];

  List<Widget> _form() {
    final due = _shop.duePaise;
    return [
      UdCard(
        child: Row(
          children: [
            QboxPhoto(photo: _shop.shopPhoto, icon: Icons.storefront_rounded, size: 52),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Paying', style: udText(12, color: udBody)),
                  Text(
                    _shop.shopName,
                    key: const Key('pay-shop-name'),
                    style: udText(20, weight: FontWeight.w800),
                  ),
                  if ((_shop.shopCategory ?? '').isNotEmpty)
                    Text(_shop.shopCategory!, style: udText(12, color: udBody)),
                ],
              ),
            ),
          ],
        ),
      ),
      if (due > 0 && _shop.bookId != null)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: UdCard(
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'You owe ${rupees(due)} udhaar here. This payment does not reduce it.',
                    key: const Key('pay-due'),
                    style: udText(13),
                  ),
                ),
                TextButton(
                  key: const Key('pay-udhaar-instead'),
                  onPressed: _busy ? null : _payUdhaar,
                  child: const Text('Pay udhaar'),
                ),
              ],
            ),
          ),
        ),
      const SizedBox(height: 12),
      UdCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Amount', style: udText(13, color: udBody)),
            TextField(
              key: const Key('payshop-amount'),
              controller: _amount,
              enabled: !_busy,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
              style: udText(30, weight: FontWeight.w800),
              decoration: InputDecoration(prefixText: '₹ ', errorText: _amountError),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('payshop-note'),
              controller: _note,
              enabled: !_busy,
              maxLength: 100,
              style: udText(14),
              decoration: const InputDecoration(hintText: 'For what? (optional)'),
            ),
          ],
        ),
      ),
      if (_message != null)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(
            _message!,
            key: const Key('pay-message'),
            textAlign: TextAlign.center,
            style: udText(13, weight: FontWeight.w600, color: udDue),
          ),
        ),
      const SizedBox(height: 16),
      if (_shop.online) ...[
        _button('pay-online', _shop.testMode ? 'Pay (test money)' : 'Pay', udPaid, () => _pay(upi: false)),
        _hint(
          _shop.testMode
              ? 'Test mode: pretend money, nothing is taken from your bank.'
              : "UPI, card or net banking on Razorpay's secure screen.",
        ),
      ],
      if (_shop.upi) ...[
        _button('pay-upi', 'Pay with UPI app', udPurple, () => _pay(upi: true)),
        _hint("Real money goes straight to the shop's UPI ID. The shop confirms it by hand."),
      ],
      if (!_shop.online && !_shop.upi)
        Text(
          '${_shop.shopName} does not take payments in QBOX yet. Please pay at the shop.',
          key: const Key('pay-none'),
          textAlign: TextAlign.center,
          style: udText(14, color: udBody),
        )
      else
        _hint('The shop will see your name.'),
    ];
  }

  Widget _button(String key, String label, Color color, VoidCallback onPressed) => SizedBox(
    width: double.infinity,
    height: 54,
    child: FilledButton(
      key: Key(key),
      onPressed: _busy ? null : onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: color,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: udText(17, weight: FontWeight.w700),
      ),
      child: Text(label),
    ),
  );

  Widget _hint(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 6, 8, 14),
    child: Text(text, textAlign: TextAlign.center, style: udText(12, color: udBody)),
  );
}
