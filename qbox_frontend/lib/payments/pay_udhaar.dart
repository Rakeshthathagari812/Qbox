import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/api_client.dart';
import '../services/app_services.dart';
import '../udhaar/udhaar_models.dart';
import '../udhaar/udhaar_widgets.dart';
import 'checkout.dart';
import 'payment_models.dart';

/// A customer pays udhaar to one shop: choose the amount, pay on Razorpay's
/// own payment screen, then the backend checks the payment before the book
/// changes. Returns the message to show (null if the customer backed out).
/// [onWorking] is told when QBOX starts and stops waiting on the network.
Future<String?> payUdhaar(
  BuildContext context,
  AppServices app,
  MyBook book, {
  void Function(bool working)? onWorking,
}) async {
  final amount = await showDialog<int>(
    context: context,
    builder: (_) => _AmountDialog(book: book),
  );
  if (amount == null) return null;
  onWorking?.call(true);
  try {
    return await _pay(app, book, amount);
  } finally {
    onWorking?.call(false);
  }
}

Future<String> _pay(AppServices app, MyBook book, int amount) async {
  final UdhaarPayStart start;
  try {
    start = await app.payments.startUdhaarPayment(book.bookId, amount, newClientRef());
  } on ApiException catch (e) {
    return e.isNetwork ? 'Paying needs internet. Please try again.' : e.message;
  }

  final result = await app.checkout.pay(start);
  switch (result) {
    case CheckoutCancelled():
      return 'Payment cancelled. No money was taken.';
    case CheckoutFailed(:final message):
      return message;
    case CheckoutPaid(:final paymentId, :final orderId, :final signature):
      try {
        final payment = await app.payments.verify(
          start.payment.id,
          razorpayPaymentId: paymentId,
          razorpayOrderId: orderId,
          razorpaySignature: signature,
        );
        return payment.isPaid
            ? 'Paid ${rupees(payment.amountPaise)} to ${book.shopName}'
            : 'Payment is being checked. It will show here in a few minutes.';
      } on ApiException catch (e) {
        return e.isNetwork
            ? 'Paid. It will show here once the internet is back.'
            : e.message;
      }
  }
}

class _AmountDialog extends StatefulWidget {
  const _AmountDialog({required this.book});

  final MyBook book;

  @override
  State<_AmountDialog> createState() => _AmountDialogState();
}

class _AmountDialogState extends State<_AmountDialog> {
  late final _amount = TextEditingController(text: paiseToText(widget.book.balancePaise));
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  void _submit() {
    final paise = parsePaise(_amount.text);
    final due = widget.book.balancePaise;
    if (paise == null || paise < 100) {
      setState(() => _error = 'Enter at least ₹1');
    } else if (paise > due) {
      setState(() => _error = 'You owe ${rupees(due)}. Pay up to that amount');
    } else {
      Navigator.of(context).pop(paise);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Pay ${widget.book.shopName}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('You owe ${rupees(widget.book.balancePaise)}', style: udText(13, color: udBody)),
          TextField(
            key: const Key('pay-amount'),
            controller: _amount,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
            style: udText(28, weight: FontWeight.w800),
            decoration: InputDecoration(prefixText: '₹ ', errorText: _error),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 8),
          Text('Pay with any UPI app, card or net banking on Razorpay\'s secure screen.',
              style: udText(12, color: udBody)),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          key: const Key('pay-confirm'),
          onPressed: _submit,
          style: FilledButton.styleFrom(backgroundColor: udPaid),
          child: const Text('Pay'),
        ),
      ],
    );
  }
}
