import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qbox_app/customer/pay_amount_screen.dart';
import 'package:qbox_app/customer/pay_number_screen.dart';
import 'package:qbox_app/customer/pay_shop_screen.dart';
import 'package:qbox_app/customer/scan_camera.dart';
import 'package:qbox_app/customer/scanned_qr.dart';
import 'package:qbox_app/customer/transaction_models.dart';
import 'package:qbox_app/customer/transactions_screen.dart';
import 'package:qbox_app/payments/checkout.dart';
import 'package:qbox_app/payments/payment_models.dart';
import 'package:qbox_app/payments/payments_screen.dart';
import 'package:qbox_app/payments/shop_qr_screen.dart';
import 'package:qbox_app/services/api_client.dart';
import 'package:qbox_app/services/app_services.dart';
import 'package:qbox_app/services/device_actions.dart';
import 'package:qbox_app/udhaar/my_udhaar_screen.dart';
import 'package:qbox_app/udhaar/udhaar_models.dart';

import 'fake_auth_api.dart';
import 'udhaar_screen_test.dart' show pumpScreen, tapKey;

const online = PayShop(ref: 'book:3', shopName: 'Lakshmi Stores', shopCategory: 'Grocery', online: true, testMode: true);
const upi = PayShop(ref: 'mobile:9876543210', shopName: 'Balaji', upi: true);
const network = ApiException('NETWORK', 'Cannot reach the QBOX server.');

Future<void> typeIn(WidgetTester tester, String key, String text) async {
  await tester.enterText(find.byKey(Key(key)), text);
  await tester.pumpAndSettle();
}

/// Pretend camera: tap it and it "sees" [text] many times, like a real one.
class FakeCamera implements QrCamera {
  FakeCamera([this.text = '', this.picture]);

  String text;

  /// What "Upload QR" finds (null = chose nothing, empty = no QR).
  String? picture;

  @override
  final torch = ValueNotifier(false);

  @override
  Widget view(void Function(String text) onText) => Align(
    child: TextButton(
      key: const Key('fake-camera'),
      onPressed: () => [text, text, text].forEach(onText),
      child: const Text('camera'),
    ),
  );

  @override
  Future<void> toggleTorch() async => torch.value = !torch.value;

  @override
  Future<String?> readPicture() async => picture;

  @override
  void dispose() {}
}

String textOf(WidgetTester tester, String key) => tester.widget<Text>(find.byKey(Key(key))).data!;

void main() {
  test('from the backend', () {
    final shops = PayShops.fromJson({
      'shops': [
        {'ref': 'book:1', 'shopName': 'A', 'duePaise': 500, 'online': true, 'upi': false},
        {'broken': true},
      ],
      'unfinished': [
        {'shopName': 'B', 'payment': {'id': 4, 'amountPaise': 100}},
      ],
    })!;
    expect(shops.shops.single.duePaise, 500);
    expect(shops.unfinished.single.payment.id, 4);
    final day = PaymentsDay.fromJson({
      'totalPaise': 0,
      'payments': <Object>[],
      'toConfirm': [
        {'id': 9, 'amountPaise': 100, 'source': 'DIRECT', 'claimedAt': '2026-11-24T10:00:00Z'},
      ],
    })!;
    expect(day.toConfirm.single.source, PaymentSource.direct);
    expect(PaymentsDay.fromJson({'totalPaise': 0, 'payments': <Object>[]})!.toConfirm, isEmpty);
  });

  group('choosing the shop', () {
    testWidgets('a listed shop opens with its name', (tester) async {
      final api = FakePaymentsApi()..shops = [online];
      await pumpScreen(tester, fakeServices(payments: api), const PayNumberScreen());
      await tapKey(tester, 'payshop-book:3');
      expect(textOf(tester, 'pay-shop-name'), 'Lakshmi Stores');
    });

    testWidgets('by number, checked before asking the server', (tester) async {
      final api = FakePaymentsApi()..byNumber['9876543210'] = upi;
      await pumpScreen(tester, fakeServices(payments: api), const PayNumberScreen());
      await typeIn(tester, 'payshop-mobile', '12345');
      await tapKey(tester, 'payshop-find');
      expect(find.text('Enter a 10-digit mobile number'), findsOneWidget);
      expect(api.calls.where((c) => c.startsWith('find')), isEmpty);

      await typeIn(tester, 'payshop-mobile', '9000000000');
      await tapKey(tester, 'payshop-find');
      expect(find.text('No QBOX shop uses this number'), findsOneWidget);

      await typeIn(tester, 'payshop-mobile', '+91 98765 43210');
      await tapKey(tester, 'payshop-find');
      expect(textOf(tester, 'pay-shop-name'), 'Balaji');
    });

    testWidgets('a number from contacts', (tester) async {
      final device = FakeDeviceActions()..nextContact = const PickedContact(name: 'Balaji', phone: '+91 98765-43210');
      await pumpScreen(tester, fakeServices(payments: FakePaymentsApi(), device: device), const PayNumberScreen());
      await tapKey(tester, 'payshop-contact');
      expect(tester.widget<TextField>(find.byKey(const Key('payshop-mobile'))).controller!.text, '9876543210');
    });

    testWidgets('offline says so', (tester) async {
      await pumpScreen(tester, fakeServices(payments: FakePaymentsApi()..nextError = network), PayShopScreen(camera: FakeCamera()));
      expect(find.byKey(const Key('payshop-error')), findsOneWidget);
    });

    testWidgets('a UPI question left open is asked again', (tester) async {
      final api = FakePaymentsApi();
      await api.startShopPayment(upi, 15000, 'ref-00001', upi: true);
      await api.startShopPayment(upi, 2000, 'ref-00002', upi: true);
      await pumpScreen(tester, fakeServices(payments: api), PayShopScreen(camera: FakeCamera()));
      expect(find.text('Did you pay ₹150 to Lakshmi Stores by UPI?'), findsOneWidget);
      await tapKey(tester, 'payshop-yes-1');
      await tapKey(tester, 'payshop-no-2');
      expect(api.calls, containsAll(['claim 1', 'drop 2']));
      expect(find.byKey(const Key('payshop-unfinished-1')), findsNothing);
      expect(find.byKey(const Key('payshop-unfinished-2')), findsNothing);
    });
  });

  group('reading a QR', () {
    const code = 'abcdefghij234567';

    test('a shop QBOX QR: only its code is used, never the UPI ID beside it', () {
      for (final text in ['qbox://pay?qbox=$code', 'upi://pay?pa=thief@okaxis&pn=X&cu=INR&qbox=$code']) {
        expect((readQr(text) as ShopQr).code, code);
      }
    });

    test('other UPI QRs', () {
      final sticker = readQr('upi://pay?pa=lakshmi%40okaxis&pn=Lakshmi%20Stores&mc=5411') as UpiQr;
      expect((sticker.upiId, sticker.name, sticker.amountPaise), ('lakshmi@okaxis', 'Lakshmi Stores', null));
      final link = sticker.linkFor(9950);
      expect(link.queryParameters, {
        'pa': 'lakshmi@okaxis', 'pn': 'Lakshmi Stores', 'mc': '5411', 'am': '99.50', 'cu': 'INR',
      });

      final fixed = readQr('upi://pay?pa=a.b@ybl&am=250.50&tr=T1') as UpiQr;
      expect(fixed.amountPaise, 25050);
      expect(fixed.linkFor(100), fixed.uri); // the amount in the QR cannot be changed

      final signed = readQr('upi://pay?pa=shop@ybl&sign=MEUCIQ') as UpiQr;
      expect(signed.linkFor(100), signed.uri); // never altered
    });

    test('Razorpay page, and nothing else on the web', () {
      expect(readQr('https://rzp.io/i/abc'), isA<PageQr>());
      for (final bad in [
        'https://rzp.io.evil.com/i/abc', 'https://evil.com/rzp.io', 'http://rzp.io/i/abc',
        'https://a@rzp.io/i/abc', 'https://rzp.io/', 'https://google.com', 'hello', '', '%%%',
        'upi://pay?pn=NoId', 'upi://pay?pa=bad id@x', 'upi://pay?pa=a.b@ybl&cu=USD', 'upi://mandate?pa=a.b@ybl',
        'qbox://pay?qbox=SHORT', 'tel:9876543210', 'javascript:alert(1)',
      ]) {
        expect(readQr(bad), isA<UnknownQr>(), reason: bad);
      }
    });
  });

  group('scan QR', () {
    Future<void> scan(WidgetTester tester, String text, {FakePaymentsApi? api, FakeDeviceActions? device}) async {
      await pumpScreen(
        tester,
        fakeServices(payments: api ?? FakePaymentsApi(), device: device),
        PayShopScreen(camera: FakeCamera(text)),
      );
      await tapKey(tester, 'fake-camera');
    }

    testWidgets('opens on the camera, with Upload QR, Torch and Number below', (tester) async {
      final camera = FakeCamera();
      await pumpScreen(tester, fakeServices(), PayShopScreen(camera: camera));
      expect(find.byKey(const Key('fake-camera')), findsOneWidget);
      for (final label in ['Scan any QR', 'Upload QR', 'Torch', 'Number']) {
        expect(find.text(label), findsOneWidget);
      }
      await tapKey(tester, 'payshop-torch');
      expect(camera.torch.value, isTrue);
      await tapKey(tester, 'payshop-number');
      expect(find.byKey(const Key('payshop-mobile')), findsOneWidget);
      // The camera is off while another screen is open, and on again after.
      expect(find.byKey(const Key('fake-camera'), skipOffstage: false), findsNothing);
      await tapKey(tester, 'udhaar-back');
      expect(find.byKey(const Key('fake-camera')), findsOneWidget);
    });

    testWidgets('upload a picture of a QR', (tester) async {
      final api = FakePaymentsApi()..byCode['abcdefghij234567'] = online;
      final camera = FakeCamera('', '');
      await pumpScreen(tester, fakeServices(payments: api), PayShopScreen(camera: camera));
      await tapKey(tester, 'payshop-upload');
      expect(find.text('No QR was found in that picture.'), findsOneWidget);
      camera.picture = null; // chose nothing
      await tapKey(tester, 'payshop-upload');
      expect(find.byKey(const Key('fake-camera')), findsOneWidget);
      camera.picture = 'qbox://pay?qbox=abcdefghij234567';
      await tapKey(tester, 'payshop-upload');
      expect(textOf(tester, 'pay-shop-name'), 'Lakshmi Stores');
    });

    testWidgets('coming back does not reopen the QR still in front of the camera', (tester) async {
      final api = FakePaymentsApi()..byCode['abcdefghij234567'] = online;
      await scan(tester, 'qbox://pay?qbox=abcdefghij234567', api: api);
      await tapKey(tester, 'udhaar-back');
      await tapKey(tester, 'fake-camera');
      expect(api.calls.where((c) => c.startsWith('scan')), hasLength(1));
      expect(find.text('Scan any QR'), findsOneWidget);
    });

    testWidgets('fits a small phone', (tester) async {
      tester.view.physicalSize = const Size(640, 1136);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final api = FakePaymentsApi();
      await api.startShopPayment(upi, 15000, 'ref-00001', upi: true);
      await tester.pumpWidget(
        ServicesScope(
          services: fakeServices(payments: api),
          child: MaterialApp(home: PayShopScreen(camera: FakeCamera())),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Number'), findsOneWidget);
    });

    testWidgets('a shop QBOX QR opens that shop, asked once', (tester) async {
      final api = FakePaymentsApi()..byCode['abcdefghij234567'] = online;
      await scan(tester, 'qbox://pay?qbox=abcdefghij234567', api: api);
      expect(textOf(tester, 'pay-shop-name'), 'Lakshmi Stores');
      expect(api.calls.where((c) => c.startsWith('scan')), hasLength(1));
      await tapKey(tester, 'udhaar-back');
      expect(find.text('Scan any QR'), findsOneWidget); // only one screen was left
    });

    testWidgets('an old QBOX QR says so', (tester) async {
      await scan(tester, 'qbox://pay?qbox=abcdefghij234567');
      expect(find.textContaining('not in use'), findsOneWidget);
    });

    testWidgets('a UPI sticker: name, warning, amount, then the UPI app', (tester) async {
      final api = FakePaymentsApi();
      final device = FakeDeviceActions();
      await scan(tester, 'upi://pay?pa=tea@ybl&pn=Tea%20Stall', api: api, device: device);
      expect(textOf(tester, 'scanned-name'), 'Tea Stall');
      expect(textOf(tester, 'scanned-upi'), 'tea@ybl');
      expect(find.textContaining('QBOX has not checked'), findsOneWidget);
      await tapKey(tester, 'scanned-pay');
      expect(find.text('Enter at least ₹1'), findsOneWidget);
      await typeIn(tester, 'scanned-amount', '20');
      await tapKey(tester, 'scanned-pay');
      expect(device.opened.single.queryParameters['am'], '20.00');
      await tapKey(tester, 'scan-yes');
      expect(textOf(tester, 'scanned-message'), 'Added to your history.');
      expect(find.text('Done'), findsOneWidget); // not "Pay" again
      expect(api.calls.where((c) => c.startsWith('shop ')), isEmpty);
    });

    testWidgets('a counter QR: the amount is fixed', (tester) async {
      final device = FakeDeviceActions();
      await scan(tester, 'upi://pay?pa=tea@ybl&am=45.00', device: device);
      expect(textOf(tester, 'scanned-fixed'), '₹45');
      expect(find.byKey(const Key('scanned-amount')), findsNothing);
      await tapKey(tester, 'scanned-pay');
      expect(device.opened.single.toString(), 'upi://pay?pa=tea@ybl&am=45.00');
    });

    testWidgets('a Razorpay page opens only after asking', (tester) async {
      final device = FakeDeviceActions();
      await scan(tester, 'https://rzp.io/i/abc', device: device);
      expect(device.opened, isEmpty);
      await tapKey(tester, 'page-open');
      expect(device.opened.single.host, 'rzp.io');
      await tapKey(tester, 'scan-yes');
      expect(find.text('Enter the amount you paid'), findsOneWidget);
      await tapKey(tester, 'scan-no');
      expect(find.text('Not paid. Nothing was added.'), findsOneWidget);
    });

    testWidgets('some other QR is refused', (tester) async {
      final device = FakeDeviceActions();
      await scan(tester, 'https://evil.example/pay', device: device);
      expect(find.text('This is not a payment QR.'), findsOneWidget);
      expect(device.opened, isEmpty);
    });
  });

  group('the shop QR', () {
    testWidgets('from the payments screen', (tester) async {
      await pumpScreen(tester, fakeServices(), const PaymentsScreen(checkEvery: Duration(hours: 1)));
      await tapKey(tester, 'payments-qr');
      expect(find.byKey(const Key('shopqr')), findsOneWidget);
      expect(find.textContaining('Add your UPI ID'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('offline says so', (tester) async {
      await pumpScreen(tester, fakeServices(payments: FakePaymentsApi()..nextError = network), const ShopQrScreen());
      expect(find.byKey(const Key('shopqr-error')), findsOneWidget);
    });
  });

  group('paying online', () {
    testWidgets('Razorpay, then the backend checks it', (tester) async {
      final api = FakePaymentsApi();
      final checkout = FakeCheckout();
      await pumpScreen(tester, fakeServices(payments: api, checkout: checkout), const PayAmountScreen(shop: online));
      expect(find.text('Pay (test money)'), findsOneWidget);
      expect(find.byKey(const Key('pay-upi')), findsNothing);
      await typeIn(tester, 'payshop-amount', '150');
      await tapKey(tester, 'pay-online');
      expect(api.calls, ['shop book:3 15000 ONLINE', 'verify 1 pay_1']);
      expect(checkout.opened.single.description, 'Payment to shop');
      expect(textOf(tester, 'pay-done'), 'Paid ₹150');
    });

    testWidgets('amount checks happen before anything is sent', (tester) async {
      final api = FakePaymentsApi();
      await pumpScreen(tester, fakeServices(payments: api), const PayAmountScreen(shop: online));
      for (final bad in ['', '0.5', '0']) {
        await typeIn(tester, 'payshop-amount', bad);
        await tapKey(tester, 'pay-online');
        expect(find.text('Enter at least ₹1'), findsOneWidget);
      }
      await typeIn(tester, 'payshop-amount', '1000001');
      await tapKey(tester, 'pay-online');
      expect(find.text('Enter up to ₹10,00,000'), findsOneWidget);
      expect(api.calls, isEmpty);
    });

    testWidgets('cancelled: nothing paid, and the next try is a new payment', (tester) async {
      final api = FakePaymentsApi();
      final checkout = FakeCheckout()..result = const CheckoutCancelled();
      await pumpScreen(tester, fakeServices(payments: api, checkout: checkout), const PayAmountScreen(shop: online));
      await typeIn(tester, 'payshop-amount', '150');
      await tapKey(tester, 'pay-online');
      expect(textOf(tester, 'pay-message'), 'Payment cancelled. No money was taken.');
      await tapKey(tester, 'pay-online');
      expect(api.clientRefs.toSet(), hasLength(2));
    });

    testWidgets('no internet while starting: the retry is the same payment', (tester) async {
      final api = FakePaymentsApi()..nextError = network;
      await pumpScreen(tester, fakeServices(payments: api), const PayAmountScreen(shop: online));
      await typeIn(tester, 'payshop-amount', '150');
      await tapKey(tester, 'pay-online');
      expect(textOf(tester, 'pay-message'), 'Paying needs internet. Please try again.');
      await tapKey(tester, 'pay-online');
      expect(api.clientRefs, hasLength(2));
      expect(api.clientRefs.toSet(), hasLength(1));
    });

    testWidgets('paid but not confirmed yet: asks not to pay again', (tester) async {
      final api = FakePaymentsApi()..verifyPays = false;
      await pumpScreen(tester, fakeServices(payments: api), const PayAmountScreen(shop: online));
      await typeIn(tester, 'payshop-amount', '150');
      await tapKey(tester, 'pay-online');
      expect(textOf(tester, 'pay-done'), 'Checking payment');
      expect(find.textContaining('Please do not pay again'), findsOneWidget);
    });

    testWidgets('udhaar due is shown, with its own way to pay', (tester) async {
      const owing = PayShop(ref: 'book:3', shopName: 'Lakshmi Stores', bookId: 3, duePaise: 50000, online: true);
      final udhaar = FakeUdhaarApi()..books.add(const MyBook(bookId: 3, shopName: 'Lakshmi Stores', balancePaise: 50000));
      await pumpScreen(tester, fakeServices(udhaar: udhaar), const PayAmountScreen(shop: owing));
      expect(textOf(tester, 'pay-due'), contains('You owe ₹500 udhaar here'));
      await tapKey(tester, 'pay-udhaar-instead');
      expect(find.byType(MyBookScreen), findsOneWidget);
    });
  });

  group('paying by UPI', () {
    testWidgets('opens the UPI app; "Yes, I paid" waits for the shop', (tester) async {
      final api = FakePaymentsApi();
      final device = FakeDeviceActions();
      await pumpScreen(tester, fakeServices(payments: api, device: device), const PayAmountScreen(shop: upi));
      expect(find.textContaining('Real money'), findsOneWidget);
      await typeIn(tester, 'payshop-amount', '99.50');
      await tapKey(tester, 'pay-upi');
      final link = device.opened.single;
      expect(link.scheme, 'upi');
      expect(link.queryParameters['pa'], 'lakshmi@okaxis');
      expect(link.queryParameters['am'], '99.50');
      await tapKey(tester, 'upi-yes');
      expect(api.calls, ['shop mobile:9876543210 9950 UPI', 'claim 1']);
      expect(textOf(tester, 'pay-done'), 'Waiting for Balaji');
    });

    testWidgets('"No" records nothing', (tester) async {
      final api = FakePaymentsApi();
      await pumpScreen(tester, fakeServices(payments: api), const PayAmountScreen(shop: upi));
      await typeIn(tester, 'payshop-amount', '20');
      await tapKey(tester, 'pay-upi');
      await tapKey(tester, 'upi-no');
      expect(api.calls.last, 'drop 1');
      expect(textOf(tester, 'pay-message'), 'Not paid. Nothing was recorded.');
    });

    testWidgets('no UPI app on the phone', (tester) async {
      final api = FakePaymentsApi();
      final device = FakeDeviceActions()..failScheme = 'upi';
      await pumpScreen(tester, fakeServices(payments: api, device: device), const PayAmountScreen(shop: upi));
      await typeIn(tester, 'payshop-amount', '20');
      await tapKey(tester, 'pay-upi');
      expect(api.calls.last, 'drop 1');
      expect(textOf(tester, 'pay-message'), contains('lakshmi@okaxis'));
    });

    testWidgets('a shop that takes no payments in QBOX', (tester) async {
      await pumpScreen(tester, fakeServices(), const PayAmountScreen(shop: PayShop(ref: 'book:1', shopName: 'Old Shop')));
      expect(find.byKey(const Key('pay-none')), findsOneWidget);
      expect(find.byKey(const Key('pay-online')), findsNothing);
    });
  });

  group('the shop confirms', () {
    Future<FakePaymentsApi> open(WidgetTester tester) async {
      final api = FakePaymentsApi();
      await api.startShopPayment(upi, 15000, 'ref-00001', upi: true);
      await api.claimUpi(1);
      await pumpScreen(tester, fakeServices(payments: api), const PaymentsScreen(checkEvery: Duration(hours: 1)));
      return api;
    }

    testWidgets('received: added to today', (tester) async {
      final api = await open(tester);
      expect(find.text('Ravi says they paid ₹150 by UPI'), findsOneWidget);
      expect(textOf(tester, 'payments-total'), '₹0');
      await tapKey(tester, 'confirm-yes-1');
      await tapKey(tester, 'confirm-upi-sure');
      expect(api.calls, contains('answer 1 true'));
      expect(textOf(tester, 'payments-total'), '₹150');
      expect(find.byKey(const Key('confirm-1')), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('not received: not counted', (tester) async {
      final api = await open(tester);
      await tapKey(tester, 'confirm-no-1');
      await tapKey(tester, 'confirm-upi-sure');
      expect(api.calls, contains('answer 1 false'));
      expect(textOf(tester, 'payments-total'), '₹0');
      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets('history: waiting and not-confirmed UPI payments are not counted', (tester) async {
    Transaction pay(String id, TransactionStatus status) => Transaction(
      id: id,
      kind: EntryKind.payment,
      amountPaise: 15000,
      at: DateTime(2026, 11, 20),
      shopKey: 'A',
      shopName: 'Balaji',
      status: status,
    );
    final api = FakeTransactionsApi()
      ..all = [for (final s in TransactionStatus.values) pay('payment-${s.code}', s)];
    await pumpScreen(tester, fakeServices(transactions: api), TransactionsScreen(now: DateTime(2026, 11, 24)));
    expect(textOf(tester, 'transactions-paid'), '₹150');
    expect(find.text('Waiting for the shop to confirm'), findsOneWidget);
    expect(find.text('Not confirmed by the shop'), findsOneWidget);
    final copy = Transaction.fromJson(api.all[1].toJson())!;
    expect(copy.status, TransactionStatus.waiting);
  });
}
