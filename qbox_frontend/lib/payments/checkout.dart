import 'dart:async';

import 'package:razorpay_flutter/razorpay_flutter.dart';

import 'payment_models.dart';

/// How Razorpay's payment screen ended.
sealed class CheckoutResult {
  const CheckoutResult();
}

/// Paid. The backend still checks [signature] before anything changes.
class CheckoutPaid extends CheckoutResult {
  const CheckoutPaid({required this.paymentId, required this.orderId, required this.signature});

  final String paymentId;
  final String orderId;
  final String signature;
}

class CheckoutCancelled extends CheckoutResult {
  const CheckoutCancelled();
}

class CheckoutFailed extends CheckoutResult {
  const CheckoutFailed(this.message);

  final String message;
}

/// Opens a payment screen for an udhaar payment. Tests use a pretend one.
abstract class Checkout {
  Future<CheckoutResult> pay(UdhaarPayStart start);
}

/// Razorpay's own payment screen (UPI apps, cards, net banking). Card and bank
/// details are typed into Razorpay's screen; QBOX never sees them.
class RazorpayCheckout implements Checkout {
  @override
  Future<CheckoutResult> pay(UdhaarPayStart start) {
    final razorpay = Razorpay();
    final done = Completer<CheckoutResult>();
    void finish(CheckoutResult result) {
      if (!done.isCompleted) done.complete(result);
      razorpay.clear();
    }

    razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, (PaymentSuccessResponse r) {
      final paymentId = r.paymentId;
      final orderId = r.orderId;
      final signature = r.signature;
      finish(paymentId == null || orderId == null || signature == null
          ? const CheckoutFailed('The payment could not be confirmed. If money was taken, it will show in a few minutes.')
          : CheckoutPaid(paymentId: paymentId, orderId: orderId, signature: signature));
    });
    razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, (PaymentFailureResponse r) {
      finish(r.code == Razorpay.PAYMENT_CANCELLED
          ? const CheckoutCancelled()
          : CheckoutFailed(r.code == Razorpay.NETWORK_ERROR
              ? 'No internet. Please try again.'
              : 'The payment did not go through. No money was taken. Please try again.'));
    });
    razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, (ExternalWalletResponse _) {
      finish(const CheckoutFailed('That wallet is not supported. Please pay with UPI.'));
    });

    try {
      razorpay.open({
        'key': start.keyId,
        'order_id': start.orderId,
        'amount': start.payment.amountPaise,
        'currency': 'INR',
        'name': start.shopName,
        'description': 'Udhaar payment',
        'prefill': {'contact': start.contact},
        'theme': {'color': '#651CE4'},
        'retry': {'enabled': true, 'max_count': 2},
      });
    } catch (_) {
      finish(const CheckoutFailed('The payment screen could not open. Please try again.'));
    }
    return done.future;
  }
}
