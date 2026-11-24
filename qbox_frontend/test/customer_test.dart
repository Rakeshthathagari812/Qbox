import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qbox_app/customer/transaction_models.dart';
import 'package:qbox_app/customer/transactions_repository.dart';
import 'package:qbox_app/customer/transactions_screen.dart';
import 'package:qbox_app/customer_home_screen.dart';
import 'package:qbox_app/onboarding_draft.dart';
import 'package:qbox_app/services/app_services.dart';
import 'package:qbox_app/udhaar/my_udhaar_screen.dart';
import 'package:qbox_app/udhaar/udhaar_models.dart';
import 'package:qbox_app/udhaar/udhaar_widgets.dart';

import 'fake_auth_api.dart';
import 'udhaar_screen_test.dart' show pumpScreen, tapKey;

final now = DateTime(2026, 11, 24, 15);

Transaction line(
  String id,
  EntryKind kind,
  int rupeesAmount,
  DateTime at, {
  String shop = 'Balaji',
  bool online = false,
  bool testMode = false,
  bool deleted = false,
}) => Transaction(
  id: id,
  kind: kind,
  amountPaise: rupeesAmount * 100,
  at: at,
  shopKey: 'QBM-$shop',
  shopName: shop,
  online: online,
  testMode: testMode,
  deletedAt: deleted ? at : null,
  deleteReason: deleted ? 'by mistake' : null,
);

String textOf(WidgetTester tester, String key) => tester.widget<Text>(find.byKey(Key(key))).data!;

void main() {
  group('history rules', () {
    final items = [
      line('a', EntryKind.credit, 500, now),
      line('b', EntryKind.credit, 70, now, deleted: true),
      line('c', EntryKind.payment, 200, now),
      line('d', EntryKind.payment, 100, now, online: true, deleted: true),
      line('e', EntryKind.payment, 40, now, deleted: true),
    ];

    test('deleted lines are not counted, but money paid online always is', () {
      expect(totalTaken(items), 50000);
      expect(totalPaid(items), 30000);
    });

    test('a month survives saving and reading back', () {
      final history = MonthHistory(month: '2026-11', months: const ['2026-11'], items: items);
      final copy = MonthHistory.fromJson(history.toJson())!;
      expect(copy.toJson(), history.toJson());
      expect(MonthHistory.fromJson('x'), isNull);
      expect(Transaction.fromJson(<String, dynamic>{'id': 'x'}), isNull);
    });

    test('month words', () {
      expect(monthKey(DateTime(2026, 3, 9)), '2026-03');
      expect(monthLabel('2026-03'), 'March 2026');
      expect(monthLabel('bad'), 'bad');
    });
  });

  group('transaction history', () {
    late FakeTransactionsApi api;

    setUp(() {
      api = FakeTransactionsApi()
        ..all = [
          line('1', EntryKind.credit, 500, DateTime(2026, 11, 20)),
          line('2', EntryKind.payment, 200, DateTime(2026, 11, 22), online: true, testMode: true),
          line('3', EntryKind.credit, 90, DateTime(2026, 11, 21), shop: 'Lakshmi'),
          line('4', EntryKind.credit, 1200, DateTime(2026, 8, 3), shop: 'Lakshmi'),
        ];
    });

    Future<void> open(WidgetTester tester, {TransactionsStore? store}) => pumpScreen(
      tester,
      fakeServices(transactions: api, transactionsStore: store),
      TransactionsScreen(now: now),
    );

    testWidgets('this month: totals, newest first, online badge', (tester) async {
      await open(tester);
      expect(textOf(tester, 'transactions-month'), 'November 2026');
      expect(textOf(tester, 'transactions-taken'), '₹590');
      expect(textOf(tester, 'transactions-paid'), '₹200');
      expect(find.text('Online (test money)'), findsOneWidget);
      final newest = tester.getTopLeft(find.byKey(const Key('transaction-2'))).dy;
      expect(newest, lessThan(tester.getTopLeft(find.byKey(const Key('transaction-3'))).dy));
    });

    IconData arrowIn(WidgetTester tester, String key) => tester
        .widget<Icon>(find.descendant(of: find.byKey(Key(key)), matching: find.byType(Icon)).first)
        .icon!;

    testWidgets('the arrow goes out when paid, in when udhaar was taken', (tester) async {
      await open(tester);
      expect(arrowIn(tester, 'transaction-2'), Icons.north_east_rounded);
      expect(arrowIn(tester, 'transaction-1'), Icons.south_west_rounded);
    });

    testWidgets('a book line: the arrow is the reader\'s, customer or shop', (tester) async {
      UdhaarEntry entry(EntryKind kind) =>
          UdhaarEntry(id: 1, kind: kind, amountPaise: 100, entryAt: now, clientRef: kind.name);
      await pumpScreen(
        tester,
        fakeServices(),
        Scaffold(
          body: Column(
            children: [
              for (final mine in [true, false])
                for (final kind in EntryKind.values)
                  EntryTile(
                    key: Key('$mine-${kind.name}'),
                    entry: entry(kind),
                    balanceAfter: 0,
                    now: now,
                    forCustomer: mine,
                  ),
            ],
          ),
        ),
      );
      expect(arrowIn(tester, 'true-payment'), Icons.north_east_rounded);
      expect(arrowIn(tester, 'true-credit'), Icons.south_west_rounded);
      expect(arrowIn(tester, 'false-payment'), Icons.south_west_rounded);
      expect(arrowIn(tester, 'false-credit'), Icons.north_east_rounded);
    });

    testWidgets('the filter is only All, Shops and Others, not each shop', (tester) async {
      await open(tester);
      expect(find.byType(ChoiceChip), findsNWidgets(3));
      for (final label in ['All', 'Shops', 'Others']) {
        expect(find.widgetWithText(ChoiceChip, label), findsOneWidget);
      }
      await tapKey(tester, 'transactions-shop-shops');
      expect(textOf(tester, 'transactions-taken'), '₹590');
      await tapKey(tester, 'transactions-shop-others');
      expect(textOf(tester, 'transactions-taken'), '₹0');
      expect(find.text('Nothing to others in November 2026.'), findsOneWidget);
      await tapKey(tester, 'transactions-shop-all');
      expect(find.byKey(const Key('transaction-1')), findsOneWidget);
    });

    testWidgets('arrows skip months with nothing, and come back', (tester) async {
      await open(tester);
      await tapKey(tester, 'transactions-older');
      expect(textOf(tester, 'transactions-month'), 'August 2026');
      expect(textOf(tester, 'transactions-taken'), '₹1,200');
      await tapKey(tester, 'transactions-newer');
      expect(textOf(tester, 'transactions-month'), 'November 2026');
      expect(api.asked, ['2026-11', '2026-08', '2026-11']);
    });

    testWidgets('empty month', (tester) async {
      api.all = [];
      await open(tester);
      expect(find.byKey(const Key('transactions-empty')), findsOneWidget);
    });

    testWidgets('offline: the saved copy, or a clear message', (tester) async {
      final store = MemoryTransactionsStore();
      await store.save(await api.month('2026-11'));
      api.offline = true;
      await open(tester, store: store);
      expect(textOf(tester, 'transactions-taken'), '₹590');
      expect(find.text('Offline: showing the last saved copy.'), findsOneWidget);
      await tapKey(tester, 'transactions-older');
      expect(find.text('Offline: this month is not saved on this phone.'), findsOneWidget);
      expect(find.byKey(const Key('transactions-empty')), findsNothing);
      await tapKey(tester, 'transactions-newer');
      expect(textOf(tester, 'transactions-month'), 'November 2026');
    });

    testWidgets('a line the shop deleted is shown, not counted', (tester) async {
      api.all = [line('9', EntryKind.credit, 300, DateTime(2026, 11, 2), deleted: true)];
      await open(tester);
      expect(textOf(tester, 'transactions-taken'), '₹0');
      expect(find.text('Deleted by the shop: by mistake'), findsOneWidget);
    });

    test('log out forgets the saved months', () async {
      final store = MemoryTransactionsStore();
      await store.save(await api.month('2026-11'));
      await fakeServices(transactionsStore: store).forgetUserData();
      expect(store.saved, isEmpty);
    });
  });

  group('my udhaar (with the shop details)', () {
    MyBook shop(int id, String name, {int balance = 0}) => MyBook(
      bookId: id,
      shopName: name,
      shopPhone: '9876500000',
      shopCategory: 'Grocery & Daily Needs',
      shopAddress: 'Main Road, Warangal',
      balancePaise: balance,
    );

    testWidgets('details, call, WhatsApp, and opening the entries', (tester) async {
      final udhaar = FakeUdhaarApi()..books.add(shop(1, 'Sri Balaji Stores', balance: 35000));
      final device = FakeDeviceActions();
      await pumpScreen(tester, fakeServices(udhaar: udhaar, device: device), MyUdhaarScreen(now: now));
      expect(find.text('Sri Balaji Stores'), findsOneWidget);
      expect(find.text('Grocery & Daily Needs'), findsOneWidget);
      expect(find.text('Main Road, Warangal'), findsOneWidget);
      expect(find.text('₹350 due'), findsOneWidget);
      expect(find.byKey(const Key('myudhaar-search')), findsNothing);

      await tapKey(tester, 'myudhaar-call-1');
      await tapKey(tester, 'myudhaar-message-1');
      await tapKey(tester, 'myudhaar-whatsapp-1');
      expect(device.opened.map((u) => u.scheme), ['tel', 'sms', 'whatsapp']);

      await tapKey(tester, 'mybook-1');
      expect(find.byKey(const Key('mybook-balance')), findsOneWidget);
    });

    testWidgets('no shops, then a shop with no phone after pulling down', (tester) async {
      final udhaar = FakeUdhaarApi();
      await pumpScreen(tester, fakeServices(udhaar: udhaar), const MyUdhaarScreen());
      expect(find.byKey(const Key('myudhaar-empty')), findsOneWidget);
      udhaar.books.add(const MyBook(bookId: 2, shopName: 'Lakshmi'));
      await tester.fling(find.byType(ListView).first, const Offset(0, 400), 1000);
      await tester.pumpAndSettle();
      expect(find.text('Lakshmi'), findsOneWidget);
      expect(find.byKey(const Key('myudhaar-call-2')), findsNothing);
    });

    testWidgets('search appears with many shops', (tester) async {
      final udhaar = FakeUdhaarApi();
      for (var i = 1; i <= 5; i++) {
        udhaar.books.add(shop(i, 'Shop $i'));
      }
      await pumpScreen(tester, fakeServices(udhaar: udhaar), const MyUdhaarScreen());
      await tester.enterText(find.byKey(const Key('myudhaar-search')), 'shop 3');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('mybook-3')), findsOneWidget);
      expect(find.byKey(const Key('mybook-1')), findsNothing);
      await tester.enterText(find.byKey(const Key('myudhaar-search')), 'xyz');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('myudhaar-no-match')), findsOneWidget);
    });

    testWidgets('offline with nothing saved says so', (tester) async {
      await pumpScreen(tester, fakeServices(udhaar: FakeUdhaarApi()..offline = true), const MyUdhaarScreen());
      expect(find.byKey(const Key('myudhaar-offline')), findsOneWidget);
      expect(find.byKey(const Key('myudhaar-empty')), findsNothing);
    });
  });

  testWidgets('customer home: My Udhaar and history open; My Shops and My QR are gone', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ServicesScope(
        services: fakeServices(),
        child: OnboardingScope(draft: OnboardingDraft(), child: const MaterialApp(home: CustomerHomeScreen())),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('tool-My QR')), findsNothing);
    expect(find.byKey(const Key('tool-My Shops')), findsNothing);
    await tapKey(tester, 'tool-My Udhaar');
    expect(find.byKey(const Key('myudhaar-empty')), findsOneWidget);
    await tapKey(tester, 'udhaar-back');
    await tapKey(tester, 'tool-Transaction History');
    expect(find.byKey(const Key('transactions-month')), findsOneWidget);
    await tapKey(tester, 'udhaar-back');
    await tapKey(tester, 'tool-Checklist & Notes');
    expect(find.byKey(const Key('lists-empty')), findsOneWidget);
  });
}
