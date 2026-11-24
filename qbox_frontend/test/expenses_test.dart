import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qbox_app/customer/expenses_screen.dart';
import 'package:qbox_app/customer/pay_shop_screen.dart';
import 'package:qbox_app/customer/record_form_screen.dart';
import 'package:qbox_app/customer/scanned_qr.dart';
import 'package:qbox_app/customer/scanned_upi_screen.dart';
import 'package:qbox_app/customer/transaction_models.dart';
import 'package:qbox_app/customer/transactions_repository.dart';
import 'package:qbox_app/customer/transactions_screen.dart';
import 'package:qbox_app/services/api_client.dart';
import 'package:qbox_app/services/app_services.dart';
import 'package:qbox_app/udhaar/udhaar_models.dart';

import 'fake_auth_api.dart';
import 'pay_shop_test.dart' show FakeCamera;
import 'udhaar_screen_test.dart' show pumpScreen, tapKey;

final now = DateTime(2026, 11, 24, 15);

Transaction pay(
  String id,
  int rupeesAmount, {
  DateTime? at,
  String shop = 'Balaji',
  ExpenseCategory? category = ExpenseCategory.groceries,
  bool own = false,
  bool hidden = false,
  bool notSame = false,
  EntryKind kind = EntryKind.payment,
}) => Transaction(
  id: id,
  kind: kind,
  amountPaise: rupeesAmount * 100,
  at: at ?? DateTime(2026, 11, 20, 10),
  shopKey: own ? Transaction.ownKey : 'QBM-$shop',
  shopName: shop,
  category: kind == EntryKind.credit ? null : category,
  own: own,
  hidden: hidden,
  notSame: notSame,
);

RecordDraft draft({String title = 'Tea', int rupeesAmount = 20, DateTime? at}) => RecordDraft(
  title: title,
  amountPaise: rupeesAmount * 100,
  category: ExpenseCategory.food,
  at: at ?? DateTime(2026, 11, 20, 10),
);

String textOf(WidgetTester tester, String key) => tester.widget<Text>(find.byKey(Key(key))).data!;

Future<void> typeIn(WidgetTester tester, String key, String text) async {
  await tester.enterText(find.byKey(Key(key)), text);
  await tester.pumpAndSettle();
}

Future<void> save(WidgetTester tester) async {
  await tapKey(tester, 'record-save');
  await tapKey(tester, 'record-sure');
}

void main() {
  group('rules', () {
    test('udhaar counts once, when paid; left out is not counted', () {
      final items = [
        pay('entry-1', 500, kind: EntryKind.credit),
        pay('entry-2', 300),
        pay('payment-3', 100, hidden: true),
        pay('own-4', 50, own: true, category: ExpenseCategory.food),
      ];
      expect(totalPaid(items), 45000);
      expect(totalSpent(items), 35000);
      expect(totalOwn(items), 5000);
      expect(spentByCategory(items), [(ExpenseCategory.groceries, 30000), (ExpenseCategory.food, 5000)]);
    });

    test('possible duplicates: same amount and day, each used once', () {
      final items = [
        pay('entry-1', 100),
        pay('own-1', 100, own: true),
        pay('own-2', 100, own: true),
        pay('own-3', 100, own: true, at: DateTime(2026, 11, 21)),
        pay('entry-9', 70),
        pay('own-4', 70, own: true, notSame: true),
        pay('entry-5', 60, kind: EntryKind.credit),
        pay('own-5', 60, own: true),
      ];
      final same = possibleDuplicates(items);
      expect(same.keys, ['own-1']);
      expect(same['own-1']!.id, 'entry-1');
    });

    test('one said to be the same is not counted, and uses up the other one', () {
      final same = Transaction.fromJson({...pay('own-1', 100, own: true).toJson(), 'same': true})!;
      final items = [pay('entry-1', 100), same, pay('own-2', 100, own: true)];
      expect(totalPaid(items), 20000);
      expect(possibleDuplicates(items), isEmpty);
    });

    test('drafts and questions survive saving', () {
      final d = draft();
      expect(RecordDraft.fromJson(d.toJson())!.toJson(), d.toJson());
      final q = ScanQuestion(title: 'Tea', at: now, upiId: 'tea@ybl', amountPaise: 2000);
      expect(ScanQuestion.fromJson(q.toJson())!.toJson(), q.toJson());
      expect(RecordDraft.fromJson('x'), isNull);
      expect(ScanQuestion.fromJson(const <String, dynamic>{}), isNull);
    });
  });

  group('offline records', () {
    late FakeTransactionsApi api;
    late MemoryTransactionsStore store;
    late TransactionsRepository repository;

    setUp(() {
      api = FakeTransactionsApi();
      store = MemoryTransactionsStore();
      repository = TransactionsRepository(api, store);
    });

    test('kept on the phone, shown, then sent once', () async {
      api.offline = true;
      expect(await repository.addRecord(draft()), isFalse);
      final saved = (await repository.saved('2026-11'))!;
      expect(saved.items.single.pending, isTrue);
      expect(saved.months, ['2026-11']);
      expect(await repository.saved('2026-10'), isNull);

      api.offline = false;
      final fresh = await repository.fresh('2026-11');
      expect(fresh.items.single.id, 'own-1');
      expect(store.pending, isEmpty);
      await repository.fresh('2026-11');
      expect(api.all, hasLength(1));
    });

    test('a record the server says is wrong is dropped; server trouble keeps it', () async {
      store.pending = [draft(title: 'A'), draft(title: 'B')];
      api.nextError = const ApiException('INVALID_INPUT', 'bad', status: 400);
      expect(await repository.sendPending(), ['A: bad']);
      expect(api.all.single.shopName, 'B');

      store.pending = [draft(title: 'C')];
      for (final status in [500, 401, 429]) {
        api.nextError = ApiException('X', 'x', status: status);
        expect(await repository.sendPending(), isEmpty);
        expect(store.pending, hasLength(1), reason: '$status');
      }
    });

    test('answering a question twice adds the payment once', () async {
      final q = ScanQuestion(title: 'Tea', at: now, amountPaise: 2000);
      await repository.ask(q);
      await repository.answer(q, amountPaise: 2000);
      await repository.answer(q, amountPaise: 2000);
      expect(api.all, hasLength(1));
      expect(await repository.questions(), isEmpty);
    });

    test('log out forgets everything', () async {
      store.pending = [draft()];
      store.questions = [ScanQuestion(title: 'Tea', at: now)];
      await fakeServices(transactionsStore: store).forgetUserData();
      expect(store.pending, isEmpty);
      expect(store.questions, isEmpty);
    });
  });

  group('adding a payment', () {
    testWidgets('from Expenses: checks, then shown as added by you', (tester) async {
      final api = FakeTransactionsApi();
      await pumpScreen(tester, fakeServices(transactions: api), ExpensesScreen(now: now));
      await tapKey(tester, 'record-add');
      await tapKey(tester, 'record-save');
      expect(find.text('Enter at least ₹1'), findsOneWidget);
      expect(find.text('Enter a name, like Tea stall'), findsOneWidget);
      expect(api.calls, isEmpty);

      await typeIn(tester, 'record-amount', '20');
      await typeIn(tester, 'record-title', 'Tea stall');
      await tapKey(tester, 'category-FOOD');
      await save(tester);
      expect(api.calls, ['add Tea stall 2000']);
      expect(api.all.single.category, ExpenseCategory.food);
      expect(find.text('Added by you'), findsOneWidget);
      expect(textOf(tester, 'expenses-total'), '₹20');
      await pumpScreen(tester, fakeServices(transactions: api), const SizedBox());
      await pumpScreen(tester, fakeServices(transactions: api), TransactionsScreen(now: now));
      expect(textOf(tester, 'transactions-own'), '₹20 of this was added by you.');
    });

    testWidgets('offline: saved on the phone', (tester) async {
      final api = FakeTransactionsApi()..offline = true;
      await pumpScreen(tester, fakeServices(transactions: api), ExpensesScreen(now: now));
      await tapKey(tester, 'record-add');
      await typeIn(tester, 'record-amount', '20');
      await typeIn(tester, 'record-title', 'Bus');
      await save(tester);
      expect(find.text('Waiting for internet'), findsOneWidget);
    });

    testWidgets('nothing in the history can be added, changed or deleted', (tester) async {
      final api = FakeTransactionsApi();
      await api.addRecord(draft());
      api.all.add(pay('entry-1', 300));
      await pumpScreen(tester, fakeServices(transactions: api), TransactionsScreen(now: now));
      for (final id in ['own-1', 'entry-1']) {
        await tapKey(tester, 'transaction-$id');
        expect(find.byType(BottomSheet), findsNothing);
        expect(find.byType(AlertDialog), findsNothing);
      }
      expect(find.byKey(const Key('record-add')), findsNothing);
      expect(find.byIcon(Icons.delete_outline_rounded), findsNothing);
      expect(find.byIcon(Icons.edit_outlined), findsNothing);
    });

    testWidgets('it is checked once more before saving', (tester) async {
      final api = FakeTransactionsApi();
      await pumpScreen(tester, fakeServices(transactions: api), ExpensesScreen(now: now));
      await tapKey(tester, 'record-add');
      await typeIn(tester, 'record-amount', '20');
      await typeIn(tester, 'record-title', 'Bus');
      await tapKey(tester, 'record-save');
      expect(find.text('₹20 to Bus?'), findsOneWidget);
      await tester.tap(find.text('Go back'));
      await tester.pumpAndSettle();
      expect(api.calls, isEmpty);
      await typeIn(tester, 'record-amount', '25');
      await save(tester);
      expect(api.calls, ['add Bus 2500']);
    });

    testWidgets('the form keeps what was typed when the server refuses', (tester) async {
      final api = FakeTransactionsApi()..nextError = const ApiException('X', 'Too many', status: 400);
      await pumpScreen(tester, fakeServices(transactions: api), RecordFormScreen(now: now));
      await typeIn(tester, 'record-amount', '20');
      await typeIn(tester, 'record-title', 'Bus');
      await save(tester);
      expect(find.text('Too many'), findsOneWidget);
      expect(find.text('Bus'), findsOneWidget);
    });
  });

  group('history', () {
    testWidgets('filter: all, shops, others', (tester) async {
      final api = FakeTransactionsApi()
        ..all = [pay('entry-1', 300), pay('own-1', 50, own: true, shop: 'Tea')];
      await pumpScreen(tester, fakeServices(transactions: api), TransactionsScreen(now: now));
      expect(textOf(tester, 'transactions-paid'), '₹350');
      await tapKey(tester, 'transactions-shop-others');
      expect(textOf(tester, 'transactions-paid'), '₹50');
      await tapKey(tester, 'transactions-shop-shops');
      expect(textOf(tester, 'transactions-paid'), '₹300');
      expect(find.byKey(const Key('transactions-own')), findsNothing);
      await tapKey(tester, 'transactions-shop-all');
      expect(textOf(tester, 'transactions-paid'), '₹350');
    });

    testWidgets('maybe the same payment: kept, counted once, and can be counted again', (tester) async {
      final api = FakeTransactionsApi();
      await api.addRecord(draft(rupeesAmount: 100));
      api.all.add(pay('entry-1', 100));
      await pumpScreen(tester, fakeServices(transactions: api), TransactionsScreen(now: now));
      expect(textOf(tester, 'same-own-1'), 'Is this the same payment as ₹100 to Balaji?');
      await tapKey(tester, 'same-yes-own-1');
      expect(api.calls.last, 'same 1');
      expect(textOf(tester, 'transactions-paid'), '₹100');
      expect(find.byKey(const Key('transaction-own-1')), findsOneWidget);
      expect(find.text('Same as another payment: not counted'), findsOneWidget);
      await tapKey(tester, 'count-own-1');
      expect(textOf(tester, 'transactions-paid'), '₹200');
    });

    testWidgets('maybe the same payment: keep both, not asked again', (tester) async {
      final api = FakeTransactionsApi();
      await api.addRecord(draft(rupeesAmount: 100));
      api.all.add(pay('entry-1', 100));
      await pumpScreen(tester, fakeServices(transactions: api), TransactionsScreen(now: now));
      await tapKey(tester, 'same-no-own-1');
      expect(api.calls.last, 'different 1');
      expect(find.byKey(const Key('same-own-1')), findsNothing);
      expect(textOf(tester, 'transactions-paid'), '₹200');
    });
  });

  group('expenses', () {
    late FakeTransactionsApi api;

    setUp(() {
      api = FakeTransactionsApi()
        ..all = [
          pay('entry-1', 900, kind: EntryKind.credit),
          pay('entry-2', 300),
          pay('payment-3', 100, shop: 'Medical', category: ExpenseCategory.health),
          pay('own-4', 50, own: true, shop: 'Tea', category: ExpenseCategory.food),
        ];
    });

    Future<void> open(WidgetTester tester) =>
        pumpScreen(tester, fakeServices(transactions: api), ExpensesScreen(now: now));

    testWidgets('total and categories; udhaar taken is not counted', (tester) async {
      await open(tester);
      expect(textOf(tester, 'expenses-total'), '₹450');
      expect(find.byKey(const Key('transaction-entry-1')), findsNothing);
      await tapKey(tester, 'expenses-HEALTH');
      expect(find.byKey(const Key('transaction-payment-3')), findsOneWidget);
      expect(find.byKey(const Key('transaction-entry-2')), findsNothing);
      await tapKey(tester, 'expenses-all');
      expect(find.byKey(const Key('transaction-entry-2')), findsOneWidget);
    });

    testWidgets('another category for an automatic one', (tester) async {
      await open(tester);
      await tapKey(tester, 'transaction-payment-3');
      await tapKey(tester, 'category-BILLS');
      expect(api.calls, ['mark payment-3 BILLS false']);
      expect(find.byKey(const Key('expenses-BILLS')), findsOneWidget);
    });

    testWidgets('leave one out, then count it again', (tester) async {
      await open(tester);
      await tapKey(tester, 'transaction-entry-2');
      await tapKey(tester, 'expense-hide');
      expect(textOf(tester, 'expenses-total'), '₹150');
      await tapKey(tester, 'expenses-hidden');
      await tapKey(tester, 'transaction-entry-2');
      await tapKey(tester, 'expense-hide');
      expect(textOf(tester, 'expenses-total'), '₹450');
    });

    testWidgets('one they added: category and leaving out, nothing else', (tester) async {
      await open(tester);
      await tapKey(tester, 'transaction-own-4');
      expect(find.text('Remove'), findsNothing);
      await tapKey(tester, 'category-BILLS');
      expect(api.calls, ['mark own-4 BILLS false']);
      await tapKey(tester, 'transaction-own-4');
      await tapKey(tester, 'expense-hide');
      expect(textOf(tester, 'expenses-total'), '₹400');
    });

    testWidgets('budget: set, over it, remove', (tester) async {
      await open(tester);
      await tapKey(tester, 'expenses-set-budget');
      await tapKey(tester, 'budget-save');
      expect(find.text('Enter at least ₹1'), findsOneWidget);
      await typeIn(tester, 'budget-amount', '1000');
      await tapKey(tester, 'budget-save');
      expect(textOf(tester, 'expenses-budget'), '₹550 left of ₹1,000');

      await tapKey(tester, 'expenses-set-budget');
      await typeIn(tester, 'budget-amount', '400');
      await tapKey(tester, 'budget-save');
      expect(textOf(tester, 'expenses-budget'), '₹50 over your budget of ₹400');

      await tapKey(tester, 'expenses-set-budget');
      await tapKey(tester, 'budget-remove');
      expect(find.byKey(const Key('expenses-budget')), findsNothing);
    });

    testWidgets('a possible double is asked here too', (tester) async {
      api.all = [pay('entry-2', 100)];
      await api.addRecord(draft(rupeesAmount: 100));
      await open(tester);
      expect(textOf(tester, 'expenses-total'), '₹200');
      await tapKey(tester, 'same-yes-own-1');
      expect(textOf(tester, 'expenses-total'), '₹100');
    });

    testWidgets('empty month, and adding from here', (tester) async {
      api.all = [];
      await open(tester);
      expect(find.byKey(const Key('expenses-empty')), findsOneWidget);
      await tapKey(tester, 'record-add');
      await typeIn(tester, 'record-amount', '80');
      await typeIn(tester, 'record-title', 'Auto');
      await tapKey(tester, 'category-TRAVEL');
      await save(tester);
      expect(textOf(tester, 'expenses-total'), '₹80');
      expect(find.byKey(const Key('expenses-TRAVEL')), findsOneWidget);
    });

    testWidgets('fits a small phone', (tester) async {
      api.budget = 100;
      tester.view.physicalSize = const Size(640, 1136);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      for (final screen in [ExpensesScreen(now: now), TransactionsScreen(now: now), RecordFormScreen(now: now)]) {
        await tester.pumpWidget(
          ServicesScope(
            key: UniqueKey(),
            services: fakeServices(transactions: api),
            child: MaterialApp(home: screen),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$screen');
      }
    });
  });

  group('scanned QR', () {
    final qr = readQr('upi://pay?pa=tea@ybl&pn=Tea%20Stall') as UpiQr;

    testWidgets('"Yes" adds it, with the UPI ID', (tester) async {
      final api = FakeTransactionsApi();
      final services = fakeServices(transactions: api);
      await pumpScreen(tester, services, ScannedUpiScreen(qr: qr));
      await typeIn(tester, 'scanned-amount', '20');
      await tapKey(tester, 'scanned-pay');
      await tapKey(tester, 'scan-yes');
      final added = api.all.single;
      expect((added.shopName, added.amountPaise, added.scanned, added.upiId), ('Tea Stall', 2000, true, 'tea@ybl'));
    });

    testWidgets('"No", or no UPI app, adds nothing and is not asked again', (tester) async {
      final api = FakeTransactionsApi();
      final store = MemoryTransactionsStore();
      final device = FakeDeviceActions();
      await pumpScreen(
        tester,
        fakeServices(transactions: api, transactionsStore: store, device: device),
        ScannedUpiScreen(qr: qr),
      );
      await typeIn(tester, 'scanned-amount', '20');
      device.failScheme = 'upi';
      await tapKey(tester, 'scanned-pay');
      expect(textOf(tester, 'scanned-message'), 'No UPI app could open.');
      expect(store.questions, isEmpty);
      device.failScheme = null;
      await tapKey(tester, 'scanned-pay');
      expect(store.questions, hasLength(1)); // kept while the UPI app is open
      await tapKey(tester, 'scan-no');
      expect(api.all, isEmpty);
      expect(store.questions, isEmpty);
    });

    testWidgets('QBOX was closed: asked again in Pay to Shop', (tester) async {
      final api = FakeTransactionsApi();
      final store = MemoryTransactionsStore()
        ..questions = [
          ScanQuestion(title: 'Tea Stall', at: now, amountPaise: 2000),
          ScanQuestion(title: 'Bus', at: now),
        ];
      await pumpScreen(
        tester,
        fakeServices(transactions: api, transactionsStore: store),
        PayShopScreen(camera: FakeCamera()),
      );
      expect(find.text('Did you pay ₹20 to Tea Stall?'), findsOneWidget);
      await tapKey(tester, 'payshop-yes-scan');
      expect(api.all.single.amountPaise, 2000);
      expect(find.text('Did your payment to Bus go through?'), findsOneWidget);
      await tapKey(tester, 'payshop-yes-scan');
      await typeIn(tester, 'scan-amount', '45');
      await tapKey(tester, 'scan-yes');
      expect(api.all.last.amountPaise, 4500);
      expect(store.questions, isEmpty);
    });
  });
}
