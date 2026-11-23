import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qbox_app/payments/checkout.dart';
import 'package:qbox_app/payments/collect_screen.dart';
import 'package:qbox_app/payments/payment_models.dart';
import 'package:qbox_app/payments/payment_settings_screen.dart';
import 'package:qbox_app/payments/payments_screen.dart';
import 'package:qbox_app/services/api_client.dart';
import 'package:qbox_app/services/settings_store.dart';
import 'package:qbox_app/translator/languages.dart';
import 'package:qbox_app/translator/voice_language.dart';
import 'package:qbox_app/udhaar/my_udhaar_screen.dart';
import 'package:qbox_app/udhaar/udhaar_models.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'fake_auth_api.dart';
import 'udhaar_screen_test.dart' show credit, pumpScreen, tapKey;

const automatic = PaymentSettings(automatic: true, testMode: true, usingTestAccount: true);
const upiOnly = PaymentSettings(upiId: 'lakshmi@okaxis', upiName: 'Lakshmi Stores');

Future<void> typeIn(WidgetTester tester, String key, String text) async {
  await tester.enterText(find.byKey(Key(key)), text);
  await tester.pumpAndSettle();
}

/// Taps, then moves time on a little. Used while "Waiting for payment…" spins
/// (a spinner never settles).
Future<void> tapWaiting(WidgetTester tester, String key) async {
  final finder = find.byKey(Key(key));
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await settleFor(tester);
}

Future<void> settleFor(WidgetTester tester, [Duration time = const Duration(milliseconds: 600)]) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(time ~/ 6);
  }
}

/// Removes the screen so its timers stop before the test ends.
Future<void> closeScreen(WidgetTester tester) => tester.pumpWidget(const SizedBox());

void main() {
  group('helpers', () {
    test('UPI link with the amount filled in', () {
      expect(
        upiLink(upiId: 'lakshmi@okaxis', name: 'Lakshmi Stores', amountPaise: 25050, note: 'rice'),
        'upi://pay?pa=lakshmi%40okaxis&pn=Lakshmi%20Stores&am=250.50&cu=INR&tn=rice',
      );
      expect(upiLink(upiId: 'a@ybl', amountPaise: 100), 'upi://pay?pa=a%40ybl&am=1.00&cu=INR');
    });

    test('"received" said in the shop language, with the name when known', () {
      expect(receivedWords(25000, AppLanguage.english), '250 rupees received');
      expect(receivedWords(75000, AppLanguage.english, from: 'Ramesh'), '750 rupees received from Ramesh');
      expect(receivedWords(25000, AppLanguage.telugu), '250 రూపాయలు వచ్చాయి');
      expect(receivedWords(150000, AppLanguage.hindi, from: 'Ramesh'), 'Ramesh से 1500 रुपये मिले');
      // A UPI ID is not read out as a name.
      expect(receivedWords(25000, AppLanguage.english, from: 'ramesh@okaxis'), '250 rupees received');
    });

    test('payment from the backend', () {
      final p = Payment.fromJson({
        'id': 7, 'amountPaise': 25000, 'source': 'UDHAAR', 'status': 'PAID',
        'customerName': 'Ramesh', 'payerVpa': 'r@ybl', 'testMode': true,
        'paidAt': '2026-11-22T10:00:00Z',
      })!;
      expect(p.isPaid, isTrue);
      expect(p.source, PaymentSource.udhaar);
      expect(p.payer, 'Ramesh');
      expect(Payment.fromJson({'id': 'x'}), isNull);
    });
  });

  group('collect', () {
    testWidgets('automatic: amount, QR, then "₹250 received" out loud', (tester) async {
      final api = FakePaymentsApi()..current = automatic;
      final speaker = FakeSpeaker();
      await pumpScreen(tester, fakeServices(payments: api, speaker: speaker), const CollectScreen());
      expect(find.byKey(const Key('collect-test-mode')), findsOneWidget);

      await typeIn(tester, 'collect-amount', '250');
      await tapWaiting(tester, 'collect-show-qr');
      expect(api.calls, contains('collect 25000'));
      expect(find.byType(QrImageView), findsOneWidget);
      expect(find.byKey(const Key('collect-waiting')), findsOneWidget);
      expect(find.byKey(const Key('collect-open-page')), findsOneWidget); // test mode helper

      await settleFor(tester, const Duration(seconds: 3));
      expect(api.calls, contains('payment 1'));
      expect(find.byKey(const Key('collect-waiting')), findsOneWidget); // not paid yet

      api.markPaid(1);
      await settleFor(tester, const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(find.text('₹250 received'), findsOneWidget);
      expect(find.text('from ramesh@okaxis'), findsOneWidget);
      expect(speaker.said, ['250 rupees received']);

      await tapKey(tester, 'collect-next');
      expect(find.byKey(const Key('collect-amount')), findsOneWidget);
      await closeScreen(tester);
    });

    testWidgets('own UPI ID only: UPI QR, shop confirms by hand', (tester) async {
      final api = FakePaymentsApi()..current = upiOnly;
      final speaker = FakeSpeaker();
      await pumpScreen(tester, fakeServices(payments: api, speaker: speaker), const CollectScreen());
      await typeIn(tester, 'collect-amount', '120');
      await tapKey(tester, 'collect-show-qr');
      expect(api.calls.where((c) => c.startsWith('collect')), isEmpty);
      final qr = tester.widget<QrImageView>(find.byType(QrImageView));
      expect(qr, isNotNull);
      expect(find.textContaining('lakshmi@okaxis'), findsOneWidget);

      await tapKey(tester, 'collect-received');
      await tapKey(tester, 'collect-received-yes');
      expect(api.calls, contains('manual 12000'));
      expect(find.text('₹120 received'), findsOneWidget);
      expect(speaker.said, ['120 rupees received']);
      await closeScreen(tester);
    });

    testWidgets('nothing set up: asks to set up payments', (tester) async {
      await pumpScreen(tester, fakeServices(payments: FakePaymentsApi()), const CollectScreen());
      expect(find.byKey(const Key('collect-setup')), findsOneWidget);
      await tapKey(tester, 'collect-setup');
      expect(find.byType(PaymentSettingsScreen), findsOneWidget);
      await closeScreen(tester);
    });

    testWidgets('cancel a QR, and amount checks', (tester) async {
      final api = FakePaymentsApi()..current = automatic;
      await pumpScreen(tester, fakeServices(payments: api), const CollectScreen());
      await tapKey(tester, 'collect-show-qr');
      expect(find.text('Enter an amount of at least ₹1'), findsOneWidget);

      await typeIn(tester, 'collect-amount', '99');
      await tapWaiting(tester, 'collect-show-qr');
      await tapWaiting(tester, 'collect-cancel');
      await tester.pumpAndSettle();
      expect(api.calls, contains('cancel 1'));
      expect(find.text('QR cancelled.'), findsOneWidget);
      await tapKey(tester, 'collect-again');
      expect(find.byKey(const Key('collect-amount')), findsOneWidget);
      await closeScreen(tester);
    });

    testWidgets('amount by voice in Telugu', (tester) async {
      final settings = MemorySettingsStore();
      await saveVoiceLanguage(settings, AppLanguage.telugu);
      final voice = FakeVoiceInput()..nextWords = 'రెండు వందల యాభై';
      final api = FakePaymentsApi()..current = automatic;
      await pumpScreen(tester, fakeServices(payments: api, voice: voice, settings: settings), const CollectScreen());
      await tapKey(tester, 'collect-speak');
      expect(voice.lastLocale, 'te_IN');
      expect(tester.widget<TextField>(find.byKey(const Key('collect-amount'))).controller!.text, '250');
      await closeScreen(tester);
    });

    testWidgets('for an udhaar customer', (tester) async {
      final udhaar = FakeUdhaarApi();
      final ramesh = udhaar.seed('Ramesh', '9876543210', history: [credit(400, DateTime(2026, 11, 1))]);
      final api = FakePaymentsApi()..current = automatic;
      final services = fakeServices(payments: api, udhaar: udhaar);
      await services.udhaar.freshBook();
      await pumpScreen(tester, services, const CollectScreen());
      await tapKey(tester, 'collect-customer');
      await tapKey(tester, 'collect-customer-${ramesh.id}');
      expect(find.text('Udhaar of Ramesh'), findsOneWidget);
      // The amount due is filled in.
      expect(tester.widget<TextField>(find.byKey(const Key('collect-amount'))).controller!.text, '400');
      await tapWaiting(tester, 'collect-show-qr');
      expect(api.payments[1]!.udhaarCustomerId, ramesh.id);
      await closeScreen(tester);
    });
  });

  group('payments list', () {
    testWidgets('today\'s total, and new payments are said out loud', (tester) async {
      final api = FakePaymentsApi()..current = automatic;
      final first = await api.collect(amountPaise: 25000, clientRef: 'ref-00001');
      api.markPaid(first.id);
      final speaker = FakeSpeaker();
      await pumpScreen(tester, fakeServices(payments: api, speaker: speaker),
          const PaymentsScreen(checkEvery: Duration(seconds: 5)));
      expect(tester.widget<Text>(find.byKey(const Key('payments-total'))).data, '₹250');
      expect(speaker.said, isEmpty); // what was there before is not announced

      final udhaar = await api.startUdhaarPayment(3, 75000, 'ref-00002');
      api.payments[udhaar.payment.id] = Payment(
        id: udhaar.payment.id, amountPaise: 75000, source: PaymentSource.udhaar,
        status: PaymentStatus.paid, customerName: 'Ramesh', paidAt: DateTime.now(),
      );
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(const Key('payments-total'))).data, '₹1,000');
      expect(speaker.said, ['750 rupees received from Ramesh']);
      final paidAt = api.payments[udhaar.payment.id]!.paidAt!;
      expect(find.text('Udhaar paid in QBOX · ${whenLabel(paidAt, DateTime.now())}'), findsOneWidget);
      await closeScreen(tester);
    });

    testWidgets('empty day, and set-up reminder', (tester) async {
      await pumpScreen(tester, fakeServices(payments: FakePaymentsApi()), const PaymentsScreen());
      expect(find.byKey(const Key('payments-empty')), findsOneWidget);
      expect(find.byKey(const Key('payments-setup')), findsOneWidget);
      await closeScreen(tester);
    });
  });

  group('settings', () {
    testWidgets('save UPI ID, connect and disconnect Razorpay', (tester) async {
      final api = FakePaymentsApi();
      await pumpScreen(tester, fakeServices(payments: api), const PaymentSettingsScreen());
      expect(tester.widget<Text>(find.byKey(const Key('settings-razorpay-status'))).data, 'Not connected');

      await typeIn(tester, 'settings-upi', 'lakshmi@okaxis');
      await tapKey(tester, 'settings-upi-save');
      expect(api.calls, contains('saveUpi lakshmi@okaxis'));
      expect(find.text('UPI ID saved'), findsOneWidget);

      await typeIn(tester, 'settings-key-id', 'rzp_test_ABCD1234');
      await typeIn(tester, 'settings-key-secret', 'secretsecretsecret');
      await tapKey(tester, 'settings-connect');
      expect(api.calls, contains('connect rzp_test_ABCD1234'));
      expect(tester.widget<Text>(find.byKey(const Key('settings-razorpay-status'))).data,
          'Connected: rzp_test_••••1234 (test mode)');

      await tapKey(tester, 'settings-disconnect');
      await tapKey(tester, 'settings-disconnect-yes');
      expect(api.calls, contains('disconnect'));
      expect(tester.widget<Text>(find.byKey(const Key('settings-razorpay-status'))).data, 'Not connected');
    });

    testWidgets('wrong keys: the backend message is shown', (tester) async {
      final api = FakePaymentsApi();
      await pumpScreen(tester, fakeServices(payments: api), const PaymentSettingsScreen());
      await typeIn(tester, 'settings-key-id', 'rzp_test_ABCD1234');
      await typeIn(tester, 'settings-key-secret', 'wrongwrongwrong');
      api.nextError = const ApiException('RAZORPAY_KEYS_WRONG', 'Razorpay did not accept these keys', status: 400);
      await tapKey(tester, 'settings-connect');
      expect(find.text('Razorpay did not accept these keys'), findsOneWidget);
    });
  });

  group('customer pays udhaar', () {
    MyBook book({int owes = 50000}) => MyBook(bookId: 3, shopName: 'Lakshmi Stores', balancePaise: owes);

    Future<FakeUdhaarApi> openMyBook(WidgetTester tester, FakePaymentsApi api, FakeCheckout checkout,
        {int owes = 50000}) async {
      final udhaar = FakeUdhaarApi()..books.add(book(owes: owes));
      await pumpScreen(tester, fakeServices(payments: api, checkout: checkout, udhaar: udhaar),
          MyBookScreen(book: book(owes: owes)));
      return udhaar;
    }

    testWidgets('pays on Razorpay\'s screen, then the backend checks it', (tester) async {
      final api = FakePaymentsApi();
      final checkout = FakeCheckout();
      await openMyBook(tester, api, checkout);
      await tapKey(tester, 'mybook-pay');
      expect(tester.widget<TextField>(find.byKey(const Key('pay-amount'))).controller!.text, '500');
      await typeIn(tester, 'pay-amount', '300');
      await tapKey(tester, 'pay-confirm');
      expect(api.calls, contains('udhaar 3 30000'));
      expect(checkout.opened.single.keyId, 'rzp_test_KEY');
      expect(api.calls, contains('verify 1 pay_1'));
      expect(find.text('Paid ₹300 to Lakshmi Stores'), findsOneWidget);
    });

    testWidgets('more than owed is refused before paying', (tester) async {
      final api = FakePaymentsApi();
      await openMyBook(tester, api, FakeCheckout(), owes: 20000);
      await tapKey(tester, 'mybook-pay');
      await typeIn(tester, 'pay-amount', '250');
      await tapKey(tester, 'pay-confirm');
      expect(find.text('You owe ₹200. Pay up to that amount'), findsOneWidget);
      expect(api.calls.where((c) => c.startsWith('udhaar')), isEmpty);
    });

    testWidgets('cancelled or failed payment changes nothing', (tester) async {
      final api = FakePaymentsApi();
      final checkout = FakeCheckout()..result = const CheckoutCancelled();
      await openMyBook(tester, api, checkout);
      await tapKey(tester, 'mybook-pay');
      await tapKey(tester, 'pay-confirm');
      expect(find.text('Payment cancelled. No money was taken.'), findsOneWidget);
      expect(api.calls.where((c) => c.startsWith('verify')), isEmpty);
    });

    testWidgets('shop without online payments: its message is shown', (tester) async {
      final api = FakePaymentsApi()
        ..nextError = const ApiException('SHOP_NO_ONLINE',
            'Lakshmi Stores does not take online payments in QBOX yet. Please pay at the shop', status: 409);
      final checkout = FakeCheckout();
      await openMyBook(tester, api, checkout);
      await tapKey(tester, 'mybook-pay');
      await tapKey(tester, 'pay-confirm');
      expect(find.textContaining('does not take online payments'), findsOneWidget);
      expect(checkout.opened, isEmpty);
    });

    testWidgets('nothing owed: no Pay button', (tester) async {
      await openMyBook(tester, FakePaymentsApi(), FakeCheckout(), owes: 0);
      expect(find.byKey(const Key('mybook-pay')), findsNothing);
    });
  });
}
