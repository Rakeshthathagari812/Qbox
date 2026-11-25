import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qbox_app/onboarding_draft.dart';
import 'package:qbox_app/profile/notices.dart';
import 'package:qbox_app/services/api_client.dart';
import 'package:qbox_app/services/app_services.dart';
import 'package:qbox_app/stock/stock_models.dart';
import 'package:qbox_app/supplier_home_screen.dart';
import 'package:qbox_app/suppliers/order_screen.dart';
import 'package:qbox_app/suppliers/pay_supplier_screen.dart';
import 'package:qbox_app/suppliers/supplier_entry_screen.dart';
import 'package:qbox_app/suppliers/supplier_models.dart';
import 'package:qbox_app/suppliers/supplier_repository.dart';
import 'package:qbox_app/suppliers/supplier_screen.dart';
import 'package:qbox_app/suppliers/suppliers_screen.dart';
import 'package:qbox_app/supply/product_stock_screen.dart';
import 'package:qbox_app/supply/products_screen.dart';
import 'package:qbox_app/supply/supply_entry_screen.dart';
import 'package:qbox_app/supply/supply_models.dart';
import 'package:qbox_app/supply/supply_order_screen.dart';
import 'package:qbox_app/supply/supply_orders_screen.dart';
import 'package:qbox_app/supply/supply_payments_screen.dart';
import 'package:qbox_app/supply/supply_report_screen.dart';
import 'package:qbox_app/supply/supply_repository.dart';
import 'package:qbox_app/supply/supply_shop_screen.dart';
import 'package:qbox_app/supply/supply_shops_screen.dart';

import 'fake_auth_api.dart';
import 'udhaar_screen_test.dart' show pumpScreen, tapKey;

final now = DateTime(2026, 11, 24, 15);

SupplyShop shop(int id, {String name = 'Balaji', int opening = 0, bool connected = true}) => SupplyShop(
  linkId: id,
  name: name,
  category: 'Grocery',
  phone: '9876543210',
  openingPaise: opening * 100,
  balancePaise: opening * 100,
  connected: connected,
  connectedAt: DateTime(2026, 11, 1),
);

SupplyShop request(int id, int owes) => SupplyShop(linkId: id, name: 'Balaji', balancePaise: owes * 100, askedAt: now);

SupplyEntry entry(int id, int rupees, {bool payment = false, Confirm confirm = Confirm.waiting, DateTime? deleted}) =>
    SupplyEntry(
      id: id,
      kind: payment ? SupplierEntryKind.payment : SupplierEntryKind.purchase,
      amountPaise: rupees * 100,
      entryAt: DateTime(2026, 11, 20),
      confirm: confirm,
      deletedAt: deleted,
      deleteReason: deleted == null ? null : 'typed twice',
    );

SupplyOrder order(int id, {OrderStatus status = OrderStatus.sent, bool connected = true, int? total}) => SupplyOrder(
  id: id,
  linkId: 1,
  shopName: 'Balaji',
  shopPhone: '9876543210',
  status: status,
  note: 'by Friday',
  totalPaise: total,
  connected: connected,
  createdAt: DateTime(2026, 11, 23),
  lines: const [
    SupplyLine(id: 11, name: 'Rice', unit: StockUnit.kg, qtyMilli: 25000),
    SupplyLine(id: 12, name: 'Oil', unit: StockUnit.l, qtyMilli: 5000),
  ],
);

String textOf(WidgetTester tester, String key) => tester.widget<Text>(find.byKey(Key(key))).data!;

Finder at(String key) => find.byKey(Key(key));

Future<void> typeIn(WidgetTester tester, String key, String text) async {
  await tester.ensureVisible(at(key));
  await tester.enterText(at(key), text);
  await tester.pumpAndSettle();
}

Future<void> waitForMessage(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 4));
  await tester.pumpAndSettle();
}

void main() {
  late FakeSupplyApi api;

  setUp(() => api = FakeSupplyApi());

  group('reading and keeping', () {
    test('every copy survives saving', () {
      final home = SupplyHome(requests: [request(1, 50)], shops: [shop(2, opening: 10)], totalDuePaise: 1000);
      expect(SupplyHome.fromJson(home.toJson())!.toJson(), home.toJson());
      final detail = SupplyShopDetail(
        shop: shop(1),
        entries: [entry(1, 5, payment: true), entry(2, 6, deleted: now)],
        orders: [order(3, total: 500)],
      );
      expect(SupplyShopDetail.fromJson(detail.toJson())!.toJson(), detail.toJson());
      for (final bad in ['x', <String, dynamic>{}, null]) {
        expect(SupplyHome.fromJson(bad), isNull);
        expect(SupplyShopDetail.fromJson(bad), isNull);
        expect(SupplyOrder.fromJson(bad), isNull);
        expect(SupplyEntry.fromJson(bad), isNull);
        expect(SupplyLine.fromJson(bad), isNull);
      }
    });

    test('a payment counts only when confirmed', () {
      expect(entry(1, 5).counts, isTrue);
      expect(entry(1, 5, payment: true).counts, isFalse);
      expect(entry(1, 5, payment: true, confirm: Confirm.confirmed).counts, isTrue);
      expect(entry(1, 5, payment: true, confirm: Confirm.closed).counts, isFalse);
      expect(entry(1, 5, deleted: now).counts, isFalse);
    });

    test('log out forgets the copies', () async {
      final store = MemorySupplyStore();
      await SupplyRepository(api, store).home();
      expect(store.saved, isNotEmpty);
      await fakeServices(supplyStore: store).forgetUserData();
      expect(store.saved, isEmpty);
    });

    test('every bell kind for suppliers has words and a screen', () {
      const ledger = [
        'WANTS_TO_CONNECT', 'SHOP_LEFT', 'CONFIRM_PURCHASE', 'ENTRY_DELETED', 'SHOP_AGREED', 'SHOP_NOT_RIGHT',
      ];
      const orders = ['NEW_ORDER', 'ORDER_CANCELLED', 'ORDER_RECEIVED'];
      const mine = [
        'CONNECTED', 'NOT_CONNECTED', 'SUPPLIER_LEFT', 'ORDER_ACCEPTED', 'ORDER_REJECTED', 'ORDER_SENT',
        'MONEY_CONFIRMED', 'NOT_RIGHT', 'THEY_GAVE', 'THEY_GOT', 'THEY_DELETED',
      ];
      for (final kind in [...ledger, ...orders, ...mine]) {
        final n = Notice(id: 'a', kind: kind, name: 'Balaji', at: now, amountPaise: 25000);
        expect(n.title, contains('Balaji'), reason: kind);
        expect(
          n.screen.runtimeType,
          ledger.contains(kind)
              ? SupplyShopsScreen
              : orders.contains(kind)
              ? SupplyOrdersScreen
              : isNot(anyOf(SupplyShopsScreen, SupplyOrdersScreen)),
          reason: kind,
        );
      }
      final paid = Notice(id: 'a', kind: 'CONFIRM_PAYMENT', name: 'Balaji', at: now, amountPaise: 25000);
      expect((paid.title.contains('Balaji'), paid.screen.runtimeType), (true, SupplyPaymentsScreen));
      final low = Notice(id: 'a', kind: 'PRODUCT_LOW', name: 'Rice', at: now, note: '2500 KG');
      expect((low.title, low.detail, low.screen.runtimeType), ('Rice is running low', '2.5 kg left', ProductsScreen));
      expect(NoticeType.of(QboxRole.supplier), [NoticeType.order, NoticeType.ledger, NoticeType.stock]);
    });
  });

  group('shop ledger', () {
    Future<void> open(WidgetTester tester, {SupplyStore? store}) =>
        pumpScreen(tester, fakeServices(supply: api, supplyStore: store), SupplyShopsScreen(now: now));

    testWidgets('empty says how to start', (tester) async {
      await open(tester);
      expect(at('supply-empty'), findsOneWidget);
      expect(textOf(tester, 'supply-total'), '₹0');
    });

    testWidgets('a shop asks: check the amount, say yes', (tester) async {
      api.requests = [request(1, 500)];
      await open(tester);
      expect(find.text('They say they owe you ₹500 now.'), findsOneWidget);
      await tapKey(tester, 'request-yes-1');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(api.calls, isEmpty);
      await tapKey(tester, 'request-yes-1');
      await tapKey(tester, 'sure');
      expect(api.calls, ['accept shop 1 50000']);
      expect(at('request-1'), findsNothing);
      expect(textOf(tester, 'supply-total'), '₹500');
      expect(find.text('₹500 to get'), findsOneWidget);
    });

    testWidgets('the amount changed meanwhile: told, and nothing is agreed', (tester) async {
      api.requests = [request(1, 500)];
      api.nextError = const ApiException(
        'BALANCE_CHANGED',
        "The shop's account changed. Please check the amount again",
        status: 409,
      );
      await open(tester);
      await tapKey(tester, 'request-yes-1');
      await tapKey(tester, 'sure');
      expect(find.text("The shop's account changed. Please check the amount again"), findsOneWidget);
      expect(at('request-1'), findsOneWidget);
    });

    testWidgets('say no, with or without a reason', (tester) async {
      api.requests = [request(1, 500), request(2, 0)];
      await open(tester);
      expect(find.text('They say nothing is due now.'), findsOneWidget);
      await tapKey(tester, 'request-no-1');
      await tester.enterText(at('reason'), 'You owe 600');
      await tapKey(tester, 'reason-done');
      await waitForMessage(tester);
      await tapKey(tester, 'request-no-2');
      await tapKey(tester, 'reason-done');
      expect(api.calls, ['decline shop 1 You owe 600', 'decline shop 2 ']);
    });

    testWidgets('offline: the saved copy, and answering needs internet', (tester) async {
      final store = MemorySupplyStore();
      api.shops = [shop(1, opening: 300)];
      api.requests = [request(2, 10)];
      await SupplyRepository(api, store).home();
      api.offline = true;
      await open(tester, store: store);
      expect(find.text('Offline: showing the last saved copy.'), findsOneWidget);
      expect(find.text('₹300 to get'), findsOneWidget);
      await tapKey(tester, 'request-yes-2');
      await tapKey(tester, 'sure');
      expect(find.text('This needs internet. Please try again.'), findsOneWidget);
    });

    testWidgets('search, advance and disconnected shops', (tester) async {
      api.shops = [
        for (var i = 1; i <= 4; i++) shop(i, name: 'Shop $i', opening: i),
        shop(5, name: 'Old', opening: -20, connected: false),
      ];
      await open(tester);
      expect(find.text('₹20 advance'), findsOneWidget);
      expect(find.text('Disconnected'), findsOneWidget);
      await typeIn(tester, 'supply-search', 'shop 3');
      expect(at('shop-3'), findsOneWidget);
      expect(at('shop-1'), findsNothing);
      await typeIn(tester, 'supply-search', 'zzz');
      expect(find.text('No shops match.'), findsOneWidget);
    });
  });

  group('one shop', () {
    Future<FakeDeviceActions> open(WidgetTester tester) async {
      api.shops = [shop(1, opening: 100)];
      api.entries = {
        1: [
          entry(1, 400, payment: true),
          entry(2, 1000),
          entry(3, 70, deleted: DateTime(2026, 11, 21)),
          entry(4, 50, confirm: Confirm.confirmed),
        ],
      };
      final device = FakeDeviceActions();
      await pumpScreen(
        tester,
        fakeServices(supply: api, device: device),
        SupplyShopScreen(shop: api.shops.first, now: now),
      );
      return device;
    }

    testWidgets('a payment counts after confirming it', (tester) async {
      await open(tester);
      expect(textOf(tester, 'supply-balance'), '₹1,150');
      expect(textOf(tester, 'supply-opening'), startsWith('Opening balance ₹100, agreed'));
      expect(find.text('Not counted until you confirm'), findsOneWidget);
      expect(find.text('Deleted by the shop: typed twice'), findsOneWidget);
      expect(at('entry-yes-3'), findsNothing);
      expect(at('entry-yes-4'), findsNothing);
      await tapKey(tester, 'entry-yes-1');
      await tapKey(tester, 'sure');
      expect(api.calls, ['confirm 1']);
      expect(textOf(tester, 'supply-balance'), '₹750');
    });

    testWidgets('not received: why, then it can still be confirmed', (tester) async {
      await open(tester);
      await tapKey(tester, 'entry-no-1');
      await tapKey(tester, 'reason-done');
      expect(find.text('Write why'), findsOneWidget);
      await tester.enterText(at('reason'), 'Not in my bank');
      await tapKey(tester, 'reason-done');
      expect(find.text('You said: Not in my bank'), findsOneWidget);
      expect(at('entry-no-1'), findsNothing);
      await waitForMessage(tester);
      await tapKey(tester, 'entry-yes-1');
      await tapKey(tester, 'sure');
      expect(textOf(tester, 'supply-balance'), '₹750');
    });

    testWidgets('call and WhatsApp; disconnect stops answering', (tester) async {
      final device = await open(tester);
      await tapKey(tester, 'supply-call');
      await tapKey(tester, 'supply-whatsapp');
      expect(device.opened.map((u) => u.scheme), ['tel', 'whatsapp']);
      await tapKey(tester, 'supply-menu');
      await tester.tap(find.text('Disconnect'));
      await tester.pumpAndSettle();
      await tapKey(tester, 'sure');
      expect(api.calls, ['end shop 1']);
      expect(at('entry-yes-1'), findsNothing);
      expect(at('supply-menu'), findsNothing);
      expect(textOf(tester, 'supply-balance'), '₹1,150');
    });
  });

  group('the supplier writes', () {
    Future<void> open(WidgetTester tester) async {
      api.shops = [shop(1, opening: 1000)];
      api.sells = [const Product(id: 1, name: 'Rice', unit: StockUnit.kg, catalogCode: 'rice', pricePaise: 4800)];
      await pumpScreen(tester, fakeServices(supply: api), SupplyShopScreen(shop: api.shops.first, now: now));
    }

    testWidgets('goods given: from own products or typed; waits for the shop', (tester) async {
      await open(tester);
      await tapKey(tester, 'supply-give');
      await tapKey(tester, 'give-save');
      expect(textOf(tester, 'give-error'), 'Enter the amount');
      await tapKey(tester, 'line-add-product');
      await tapKey(tester, 'pick-product-1');
      await tapKey(tester, 'give-save');
      expect(textOf(tester, 'give-error'), 'Enter how much Rice');
      await typeIn(tester, 'line-qty-1', '10');
      await tapKey(tester, 'line-add');
      await typeIn(tester, 'line-name-2', 'Soap');
      await typeIn(tester, 'line-qty-2', '5');
      await tapKey(tester, 'give-use-total');
      api.nextError = const ApiException('NETWORK', 'x');
      await tapKey(tester, 'give-save');
      expect(textOf(tester, 'give-error'), 'This needs internet. Please try again.');
      await tapKey(tester, 'give-save');
      expect(api.calls.last, 'write 1 PURCHASE 48000 null Rice 10000,Soap 5000');
      expect(textOf(tester, 'supply-balance'), '₹1,000'); // not counted yet
      expect(find.text('Not counted until the shop says yes'), findsOneWidget);
      expect(find.textContaining('Written by you'), findsOneWidget);
      final id = api.entries[1]!.single.id;
      expect(at('entry-yes-$id'), findsNothing); // the shop answers it
      await waitForMessage(tester);
      await tapKey(tester, 'entry-delete-$id');
      await tester.enterText(at('reason'), 'wrong shop');
      await tapKey(tester, 'reason-done');
      expect(find.text('You deleted it: wrong shop'), findsOneWidget);
      expect(at('entry-delete-$id'), findsNothing);
    });

    testWidgets('got money: counts at once', (tester) async {
      await open(tester);
      await tapKey(tester, 'supply-got');
      expect(at('line-add'), findsNothing);
      await typeIn(tester, 'give-amount', '400');
      await tapKey(tester, 'give-method-UPI');
      await tapKey(tester, 'give-save');
      expect(api.calls.last, 'write 1 PAYMENT 40000 UPI ');
      expect(textOf(tester, 'supply-balance'), '₹600');
      expect(find.text('The shop has not checked yet'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await pumpScreen(tester, fakeServices(supply: api), SupplyPaymentsScreen(now: now));
      expect(find.text('Did these come?'), findsNothing);
      expect(find.text('Written by you'), findsOneWidget);
    });

    test('what counts', () {
      SupplyEntry e(bool payment, Confirm confirm) => SupplyEntry(
        id: 1,
        kind: payment ? SupplierEntryKind.payment : SupplierEntryKind.purchase,
        amountPaise: 1,
        entryAt: now,
        confirm: confirm,
        bySupplier: true,
      );
      expect([for (final c in Confirm.values) e(false, c).counts], [false, true, false, false]);
      expect([for (final c in Confirm.values) e(true, c).counts], [true, true, true, true]);
      SupplierEntry s(SupplierEntryKind kind, Confirm? c, {required bool theirs}) => SupplierEntry(
        id: 1, kind: kind, amountPaise: 1, entryAt: now, clientRef: 'r', confirm: c, bySupplier: theirs,
      );
      const p = SupplierEntryKind.payment;
      const g = SupplierEntryKind.purchase;
      expect([for (final c in Confirm.values) s(g, c, theirs: true).counts], [false, true, false, false]);
      expect([for (final c in Confirm.values) s(p, c, theirs: true).counts], [true, true, true, true]);
      expect([for (final c in Confirm.values) s(p, c, theirs: false).counts], [false, true, false, true]);
      expect([for (final c in Confirm.values) s(g, c, theirs: false).counts], [true, true, true, true]);
      expect(s(p, null, theirs: false).counts, isTrue);
      final kept = s(g, Confirm.waiting, theirs: true);
      expect(SupplierEntry.fromJson(kept.toJson())!.toJson(), kept.toJson());
      expect(SupplyEntry.fromJson(e(true, Confirm.waiting).toJson())!.bySupplier, isTrue);
    });
  });

  group('orders', () {
    Future<void> open(WidgetTester tester, SupplyOrder o) async {
      api.all = [o];
      await pumpScreen(tester, fakeServices(supply: api), SupplyOrderScreen(order: o, now: now));
    }

    testWidgets('accept with prices: the bill adds up by itself', (tester) async {
      await open(tester, order(1));
      expect(find.text('Note: by Friday'), findsOneWidget);
      await tapKey(tester, 'order-accept');
      expect(textOf(tester, 'order-problem'), 'Enter the bill total');
      await typeIn(tester, 'line-price-11', '48');
      await typeIn(tester, 'line-price-12', '150.50');
      expect(tester.widget<TextField>(at('order-total')).controller!.text, '1952.50');
      await tapKey(tester, 'line-have-12');
      expect(tester.widget<TextField>(at('order-total')).controller!.text, '1200');
      await typeIn(tester, 'order-total', '1180'); // a discount
      await tapKey(tester, 'order-accept');
      expect(api.calls, ['accept order 1 118000']);
      expect(textOf(tester, 'order-bill'), '₹1,180');
      expect(find.text('Not available'), findsOneWidget);
      expect(find.text('₹48/kg'), findsOneWidget);
    });

    testWidgets('nothing available, or reject with a reason', (tester) async {
      await open(tester, order(1));
      await tapKey(tester, 'line-have-11');
      await tapKey(tester, 'line-have-12');
      await tapKey(tester, 'order-accept');
      expect(textOf(tester, 'order-problem'), 'Nothing is available. Reject the order instead.');
      await tapKey(tester, 'order-reject');
      await tester.enterText(at('reason'), 'No stock');
      await tapKey(tester, 'reason-done');
      expect(api.calls, ['reject order 1 No stock']);
      expect(find.text('Rejected'), findsWidgets);
      expect(at('order-accept'), findsNothing);
    });

    testWidgets('change prices, then send', (tester) async {
      await open(tester, order(1, status: OrderStatus.accepted, total: 100000));
      await tapKey(tester, 'order-edit');
      await tapKey(tester, 'order-edit-cancel');
      expect(at('order-total'), findsNothing);
      await tapKey(tester, 'order-edit');
      await typeIn(tester, 'order-total', '900');
      await tapKey(tester, 'order-accept');
      expect(textOf(tester, 'order-bill'), '₹900');
      await waitForMessage(tester);
      await tapKey(tester, 'order-dispatch');
      await tapKey(tester, 'sure');
      expect(api.calls, ['accept order 1 90000', 'dispatch 1']);
      expect(at('order-edit'), findsNothing);
      expect(at('order-reject'), findsNothing);
    });

    testWidgets('the shop cancelled it meanwhile', (tester) async {
      await open(tester, order(1));
      api.all = [order(1, status: OrderStatus.cancelled)];
      api.nextError = const ApiException('ORDER_CLOSED', 'The shop cancelled this order', status: 409);
      await typeIn(tester, 'order-total', '100');
      await tapKey(tester, 'order-accept');
      expect(find.text('The shop cancelled this order'), findsOneWidget);
      expect(at('order-accept'), findsNothing);
    });

    testWidgets('no longer connected: only readable', (tester) async {
      await open(tester, order(1, connected: false));
      expect(at('order-disconnected'), findsOneWidget);
      expect(at('order-accept'), findsNothing);
      expect(at('order-reject'), findsNothing);
    });

    testWidgets('three lists, with counts', (tester) async {
      api.all = [
        order(1),
        order(2, status: OrderStatus.accepted, total: 5000),
        order(3, status: OrderStatus.dispatched),
        order(4, status: OrderStatus.received),
        order(5, connected: false),
      ];
      await pumpScreen(tester, fakeServices(supply: api), SupplyOrdersScreen(now: now));
      expect(find.text('New (1)'), findsOneWidget);
      expect(find.text('To give (2)'), findsOneWidget);
      expect(at('order-1'), findsOneWidget);
      await tapKey(tester, 'orders-doing');
      expect(at('order-2'), findsOneWidget);
      expect(at('order-3'), findsOneWidget);
      await tapKey(tester, 'orders-past');
      expect(at('order-4'), findsOneWidget);
      expect(at('order-5'), findsOneWidget);
    });
  });

  group("the shop's side", () {
    late FakeSupplierApi suppliers;
    late Supplier ravi;

    setUp(() {
      suppliers = FakeSupplierApi();
      ravi = suppliers.seed('Ravi Traders', mobile: '9848022338');
    });

    Future<void> open(WidgetTester tester) async =>
        pumpScreen(tester, fakeServices(suppliers: suppliers), SupplierScreen(supplier: ravi, now: now));

    testWidgets('connect with a code; a wrong one is refused', (tester) async {
      suppliers.onQbox.add('9848022338');
      await suppliers.addEntry(
        ravi.id,
        SupplierEntryDraft(kind: SupplierEntryKind.purchase, amountPaise: 50000, entryAt: now),
      );
      await open(tester);
      await tapKey(tester, 'supplier-connect');
      expect(textOf(tester, 'code-amount'), startsWith('The message tells them you owe ₹500 now.'));
      expect(textOf(tester, 'code-dev'), 'Test mode code: 482915');
      await tapKey(tester, 'code-confirm');
      expect(textOf(tester, 'code-error'), 'Enter the 6-digit code they received');
      await typeIn(tester, 'code', '000000');
      await tapKey(tester, 'code-confirm');
      expect(textOf(tester, 'code-error'), 'Wrong OTP. Please check and try again');
      await typeIn(tester, 'code', '482915');
      await tapKey(tester, 'code-confirm');
      expect(find.text('Connected with Ravi Traders'), findsOneWidget);
      expect(textOf(tester, 'supplier-link'), 'Connected in QBOX');
      expect(at('supplier-connect'), findsNothing);
      await waitForMessage(tester);
      await tapKey(tester, 'supplier-menu');
      await tapKey(tester, 'supplier-disconnect');
      await tapKey(tester, 'sure');
      expect(suppliers.links[ravi.id]!.status, LinkStatus.ended);
      expect(at('supplier-connect'), findsOneWidget);
    });

    testWidgets('not on QBOX yet: the number is verified', (tester) async {
      await open(tester);
      await tapKey(tester, 'supplier-connect');
      await typeIn(tester, 'code', '482915');
      await tapKey(tester, 'code-confirm');
      expect(
        textOf(tester, 'supplier-link'),
        'Number verified. You connect when they join QBOX as a supplier.',
      );
      expect(at('supplier-connect'), findsNothing);
    });

    testWidgets('code trouble: offline, too soon, resend', (tester) async {
      suppliers.codeError = const ApiException('OTP_TOO_SOON', 'Please wait 20 seconds', status: 429);
      await open(tester);
      await tapKey(tester, 'supplier-connect');
      expect(textOf(tester, 'code-error'), 'Please wait 20 seconds');
      expect(tester.widget<FilledButton>(at('code-confirm')).onPressed, isNull);
      await tapKey(tester, 'code-resend');
      expect(suppliers.codes, ['9848022338']);
      expect(tester.widget<TextButton>(at('code-resend')).onPressed, isNull); // wait
      await tester.pump(const Duration(seconds: 31));
      await tester.pumpAndSettle();
      suppliers.offline = true;
      await tapKey(tester, 'code-resend');
      expect(textOf(tester, 'code-error'), 'This needs internet. Please try again.');
    });

    testWidgets('no number; they said no', (tester) async {
      ravi = suppliers.seed('No number');
      await open(tester);
      await tapKey(tester, 'supplier-connect');
      expect(find.text("Add the supplier's mobile number first"), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      suppliers.links[ravi.id] = const SupplierLink(status: LinkStatus.declined, reason: 'You owe 600');
      await open(tester);
      expect(textOf(tester, 'supplier-link'), 'They did not connect: You owe 600');
    });

    testWidgets('adding a supplier connects with a code', (tester) async {
      suppliers.onQbox.add('9000000001');
      await pumpScreen(tester, fakeServices(suppliers: suppliers), SuppliersScreen(now: now));
      await tapKey(tester, 'suppliers-add');
      await typeIn(tester, 'supplier-name', 'New Traders');
      await tapKey(tester, 'supplier-save');
      expect(textOf(tester, 'supplier-error'), 'Enter their mobile number, or tap "Add without code"');
      await typeIn(tester, 'supplier-mobile', '9000000001');
      await tapKey(tester, 'supplier-save');
      expect(textOf(tester, 'code-amount'), startsWith('The message tells them you owe ₹0 now.'));
      await typeIn(tester, 'code', '482915');
      await tapKey(tester, 'code-confirm');
      final added = (await suppliers.suppliers()).suppliers.firstWhere((s) => s.name == 'New Traders');
      expect((added.connected, added.verified), (true, true));
    });

    testWidgets('going back from the code adds nothing; adding without a code', (tester) async {
      await pumpScreen(tester, fakeServices(suppliers: suppliers), SuppliersScreen(now: now));
      await tapKey(tester, 'suppliers-add');
      await typeIn(tester, 'supplier-name', 'Market seller');
      await typeIn(tester, 'supplier-mobile', '9000000001');
      await tapKey(tester, 'supplier-save');
      await tester.tap(at('udhaar-back').last);
      await tester.pumpAndSettle();
      expect(suppliers.known, hasLength(1));
      await tapKey(tester, 'supplier-skip');
      final added = (await suppliers.suppliers()).suppliers.firstWhere((s) => s.name == 'Market seller');
      expect((added.connected, added.verified), (false, false));
    });

    group('products', () {
      setUp(() {
        suppliers.links[ravi.id] = const SupplierLink(status: LinkStatus.on);
        ravi = Supplier(id: ravi.id, name: ravi.name, mobile: ravi.mobile, link: suppliers.links[ravi.id]);
        suppliers.sells[ravi.id] = [
          const SupplierProduct(id: 1, name: 'Rice', unit: StockUnit.kg, catalogCode: 'rice', pricePaise: 4800),
          const SupplierProduct(id: 2, name: 'Sugar', unit: StockUnit.kg, pricePaise: 4000),
          const SupplierProduct(id: 4, name: 'Salt', unit: StockUnit.bag),
          const SupplierProduct(id: 3, name: 'Dal', unit: StockUnit.kg, available: false),
        ];
      });

      testWidgets('open first, with prices; the total adds up; placed in QBOX, paid later', (tester) async {
        await open(tester);
        expect(at('product-1'), findsOneWidget); // no extra tap
        expect(find.text('₹48/kg'), findsOneWidget);
        expect(find.text('Price on the bill'), findsOneWidget);
        expect(find.text('Not available'), findsOneWidget);
        expect(at('product-add-3'), findsNothing);
        expect(at('cart-order'), findsNothing);
        await tapKey(tester, 'product-add-1');
        await tapKey(tester, 'product-more-1');
        expect(textOf(tester, 'cart-total'), '₹96');
        await typeIn(tester, 'product-qty-1', '25');
        await tapKey(tester, 'product-add-2');
        await typeIn(tester, 'product-qty-2', '1.5');
        expect(textOf(tester, 'cart-total'), '₹1,260');
        await typeIn(tester, 'product-qty-2', '1.2.3');
        expect(find.text('Check the quantities'), findsOneWidget);
        expect(tester.widget<FilledButton>(at('cart-order')).onPressed, isNull);
        await typeIn(tester, 'product-qty-2', '1.5');
        await tapKey(tester, 'product-add-4');
        expect(textOf(tester, 'cart-total'), 'From ₹1,260');
        await tapKey(tester, 'product-less-4');
        await tapKey(tester, 'cart-order');

        expect(find.text('Rice, 25 kg'), findsOneWidget);
        expect(textOf(tester, 'order-total'), '₹1,260');
        expect(at('order-pay-UPI'), findsNothing);
        expect(at('order-no-upi'), findsOneWidget);
        await tapKey(tester, 'line-add');
        await typeIn(tester, 'line-name-1', 'Biscuits');
        await typeIn(tester, 'line-qty-1', '2');
        await typeIn(tester, 'order-note', 'by Friday');
        await tapKey(tester, 'order-pay-by');
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();
        await tapKey(tester, 'order-send');
        final order = suppliers.orders[ravi.id]!.single;
        expect([for (final l in order.lines) (l.productId, l.name, l.qtyMilli)], [
          (1, 'Rice', 25000),
          (2, 'Sugar', 1500),
          (null, 'Biscuits', 2000),
        ]);
        expect((order.note, order.payPlan, order.payBy), ('by Friday', PayPlan.later, DateTime(2026, 12, 1)));
        expect(find.text('Order sent to Ravi Traders'), findsOneWidget);
        expect(find.text('Orders (1)'), findsOneWidget);
        expect(textOf(tester, 'order-plan-${order.id}'), 'Pay later, by 1 Dec');
        await tapKey(tester, 'tab-products');
        expect(at('cart-order'), findsNothing); // the cart is empty again
      });

      testWidgets('cash on delivery is filled in when the goods come', (tester) async {
        await open(tester);
        await tapKey(tester, 'product-add-1');
        await tapKey(tester, 'cart-order');
        await tapKey(tester, 'order-pay-CASH');
        expect(at('order-pay-by'), findsNothing);
        await tapKey(tester, 'order-send');
        final order = suppliers.orders[ravi.id]!.single;
        expect(order.payPlan, PayPlan.cash);
        await tapKey(tester, 'order-receive-${order.id}');
        expect(tester.widget<SwitchListTile>(at('entry-paid-now')).value, isTrue);
        expect(tester.widget<TextField>(at('entry-amount')).controller!.text, '48');
        await tapKey(tester, 'entry-save');
        expect(find.text('Goods received: stock updated'), findsOneWidget);
        expect((await suppliers.stock.stock()).items.single.name, 'Rice'); // joined the stock
        expect(textOf(tester, 'supplier-balance'), '₹48'); // until they confirm the cash
        expect(find.text('₹48 paid: waiting for them to confirm'), findsOneWidget);
      });

      testWidgets('search, offline, nothing yet, and typing something else', (tester) async {
        suppliers.sells[ravi.id] = [
          for (var i = 1; i <= 7; i++)
            SupplierProduct(id: i, name: 'Thing $i', unit: StockUnit.kg, catalogCode: i == 1 ? 'rice' : null),
        ];
        await open(tester);
        await typeIn(tester, 'products-search', 'బియ్యం'); // any language
        expect(at('product-1'), findsOneWidget);
        expect(at('product-2'), findsNothing);
        await typeIn(tester, 'products-search', 'zzz');
        expect(find.text('No products match.'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
        suppliers.offline = true;
        await open(tester);
        expect(find.text('Seeing products needs internet.'), findsOneWidget);
        suppliers.offline = false;
        suppliers.sells[ravi.id] = [];
        await tester.tap(find.text('Retry'));
        await tester.pumpAndSettle();
        expect(at('products-empty'), findsOneWidget);
        await tapKey(tester, 'supplier-order');
        expect(find.byType(OrderScreen), findsOneWidget);
        await typeIn(tester, 'line-name-1', 'Rice');
        await typeIn(tester, 'line-qty-1', '10');
        suppliers.nextError = const ApiException('NOT_AVAILABLE', 'Rice is not available now', status: 409);
        await tapKey(tester, 'order-send');
        expect(textOf(tester, 'order-error'), 'Rice is not available now');
        await tapKey(tester, 'order-send');
        expect(suppliers.orders[ravi.id], hasLength(1));
      });

      testWidgets('bought without an order: from their products', (tester) async {
        await open(tester);
        await tapKey(tester, 'supplier-menu');
        await tapKey(tester, 'supplier-purchase');
        await tapKey(tester, 'line-add-product');
        await tapKey(tester, 'pick-product-1');
        expect(tester.widget<TextField>(at('line-cost-1')).controller!.text, '48');
        await typeIn(tester, 'line-qty-1', '10');
        await tapKey(tester, 'entry-use-total');
        await tapKey(tester, 'entry-save');
        expect((await suppliers.stock.stock()).items.single.quantityMilli, 10000);
        expect(textOf(tester, 'supplier-balance'), '₹480');
      });

      group('paying', () {
        SupplierOrder accepted({int paying = 0, int paid = 0, OrderStatus status = OrderStatus.accepted}) => SupplierOrder(
          id: 7,
          status: status,
          shared: true,
          totalPaise: 48000,
          payPlan: PayPlan.upi,
          payingPaise: paying,
          paidPaise: paid,
          lines: const [EntryLine(lineId: 71, productId: 1, name: 'Rice', unit: StockUnit.kg, qtyMilli: 10000, costPaise: 4800)],
        );

        late FakeDeviceActions device;
        late MemorySupplierStore store;

        setUp(() {
          device = FakeDeviceActions();
          store = MemorySupplierStore();
          suppliers.upi[ravi.id] = 'ravi@okaxis';
          suppliers.orders[ravi.id] = [accepted()];
        });

        Future<void> openOrders(WidgetTester tester) async {
          await pumpScreen(
            tester,
            fakeServices(suppliers: suppliers, supplierStore: store, device: device),
            SupplierScreen(supplier: ravi, now: now),
          );
          await tapKey(tester, 'tab-orders');
        }

        testWidgets('UPI is offered, and only after they accept', (tester) async {
          suppliers.orders[ravi.id] = [];
          await openOrders(tester);
          expect(at('orders-empty'), findsOneWidget);
          await tapKey(tester, 'tab-products');
          await tapKey(tester, 'product-add-1');
          await tapKey(tester, 'cart-order');
          await tapKey(tester, 'order-pay-UPI');
          await tapKey(tester, 'order-send');
          final order = suppliers.orders[ravi.id]!.single;
          expect(textOf(tester, 'order-plan-${order.id}'), 'Pay by UPI, after they accept');
          expect(at('order-pay-${order.id}'), findsNothing);
        });

        testWidgets('by UPI: their own ID, the amount, then they confirm', (tester) async {
          await openOrders(tester);
          await tapKey(tester, 'order-pay-7');
          expect(find.text('Real money, straight to Ravi Traders (ravi@okaxis).'), findsOneWidget);
          expect(tester.widget<TextField>(at('pay-amount')).controller!.text, '480');
          await tapKey(tester, 'pay-upi');
          final link = device.opened.single;
          expect((link.scheme, link.queryParameters['pa'], link.queryParameters['am']), ('upi', 'ravi@okaxis', '480.00'));
          expect(store.asking, hasLength(1));
          await tapKey(tester, 'upi-yes');
          final e = suppliers.entries[ravi.id]!.single;
          expect((e.kind, e.amountPaise, e.method, e.orderId), (SupplierEntryKind.payment, 48000, PayMethod.upi, 7));
          expect(store.asking, isEmpty);
          expect(find.text('Saved. It counts after Ravi Traders confirms it.'), findsOneWidget);
          expect(find.text('₹480 paid: waiting for them to confirm'), findsOneWidget);
          expect(at('order-pay-7'), findsNothing);
          await waitForMessage(tester);
          await tapKey(tester, 'order-receive-7');
          expect(at('entry-paid-before'), findsOneWidget);
          expect(at('entry-paid-now'), findsNothing);
          await tapKey(tester, 'udhaar-back');
          await tapKey(tester, 'order-cancel-7');
          expect(find.textContaining('That stays as your advance'), findsOneWidget);
        });

        testWidgets('not paid, or no UPI app: nothing is written', (tester) async {
          await openOrders(tester);
          await tapKey(tester, 'order-pay-7');
          await typeIn(tester, 'pay-amount', '0.50');
          await tapKey(tester, 'pay-upi');
          expect(textOf(tester, 'pay-error'), 'Enter at least ₹1');
          await typeIn(tester, 'pay-amount', '480');
          await tapKey(tester, 'pay-upi');
          await tapKey(tester, 'upi-no');
          expect(textOf(tester, 'pay-error'), 'Not paid. Nothing was written.');
          device.failScheme = 'upi';
          await tapKey(tester, 'pay-upi');
          expect(textOf(tester, 'pay-error'), startsWith('No UPI app could open.'));
          expect(store.asking, isEmpty);
          expect(suppliers.entries[ravi.id], isEmpty);
        });

        testWidgets('the phone closed QBOX meanwhile: asked again', (tester) async {
          final draft = SupplierEntryDraft(
            kind: SupplierEntryKind.payment,
            amountPaise: 48000,
            entryAt: now,
            method: PayMethod.upi,
            orderId: 7,
          );
          store.asking = [PendingSupplierEntry(supplierId: ravi.id, draft: draft)];
          await openOrders(tester);
          expect(find.text('Did your UPI payment of ₹480 go through?'), findsOneWidget);
          suppliers.nextError = const ApiException('ORDER_NOT_FOUND', 'This order is not available', status: 404);
          await tapKey(tester, 'asking-yes');
          expect(store.asking, hasLength(1)); // refused: the money is not forgotten
          await waitForMessage(tester);
          await tapKey(tester, 'asking-yes');
          expect(suppliers.entries[ravi.id]!.single.orderId, 7);
          expect(at('supplier-asking'), findsNothing);
          store.asking = [PendingSupplierEntry(supplierId: ravi.id, draft: draft)];
          await tester.pumpWidget(const SizedBox());
          await openOrders(tester);
          await tapKey(tester, 'asking-no');
          expect(store.asking, isEmpty);
          expect(suppliers.entries[ravi.id], hasLength(1));
        });

        testWidgets('offline: "yes, I paid" waits on the phone', (tester) async {
          await openOrders(tester);
          await tapKey(tester, 'order-pay-7');
          await tapKey(tester, 'pay-upi');
          suppliers.offline = true;
          await tapKey(tester, 'upi-yes');
          expect(store.pending.single.draft.orderId, 7);
          expect(store.asking, isEmpty);
          expect(find.text('Saved on the phone. It will sync when internet is back.'), findsOneWidget);
        });

        testWidgets('an old balance, already paid in cash, in part', (tester) async {
          await suppliers.addEntry(
            ravi.id,
            SupplierEntryDraft(kind: SupplierEntryKind.purchase, amountPaise: 100000, entryAt: now),
          );
          suppliers.upi.remove(ravi.id);
          await open(tester);
          await tapKey(tester, 'supplier-pay');
          expect(textOf(tester, 'pay-for'), 'You owe ₹1,000. Pay all of it, or a part.');
          expect(tester.widget<TextField>(at('pay-amount')).controller!.text, '1000');
          expect(at('pay-no-upi'), findsOneWidget);
          expect(at('pay-upi'), findsNothing);
          await typeIn(tester, 'pay-amount', '');
          await tapKey(tester, 'pay-save');
          expect(textOf(tester, 'pay-error'), 'Enter the amount');
          await typeIn(tester, 'pay-amount', '400');
          await tapKey(tester, 'pay-save');
          final e = suppliers.entries[ravi.id]!.last;
          expect((e.amountPaise, e.method, e.orderId), (40000, PayMethod.cash, null));
          expect(textOf(tester, 'supplier-balance'), '₹1,000'); // until confirmed
        });

        testWidgets('UPI needs internet; the rest can be written', (tester) async {
          suppliers.offline = true;
          await pumpScreen(
            tester,
            fakeServices(suppliers: suppliers, supplierStore: store),
            PaySupplierScreen(supplier: ravi),
          );
          expect(find.text('Paying by UPI needs internet.'), findsOneWidget);
          suppliers.offline = false;
          await tester.tap(find.text('Retry'));
          await tester.pumpAndSettle();
          expect(at('pay-upi'), findsOneWidget);
        });

        test('drafts and orders survive saving', () {
          final draft = SupplierEntryDraft(
            kind: SupplierEntryKind.payment,
            amountPaise: 5,
            entryAt: now,
            orderId: 7,
            lines: const [EntryLine(name: 'Rice', unit: StockUnit.kg, qtyMilli: 5, catalogCode: 'rice')],
          );
          expect(SupplierEntryDraft.fromJson(draft.toStore())!.toStore(), draft.toStore());
          final o = accepted(paying: 5, paid: 10);
          expect(SupplierOrder.fromJson(o.toJson())!.toJson(), o.toJson());
          expect((o.leftPaise, o.paidSomething, accepted(paid: 60000).leftPaise), (47985, true, 0));
        });
      });

      testWidgets('a small phone with big text has room', (tester) async {
        suppliers.upi[ravi.id] = 'ravi@okaxis';
        suppliers.orders[ravi.id] = [
          const SupplierOrder(
            id: 7,
            status: OrderStatus.accepted,
            shared: true,
            totalPaise: 123456700,
            payPlan: PayPlan.cash,
            payingPaise: 100,
            lines: [EntryLine(lineId: 1, name: 'A product with a very long name', unit: StockUnit.dozen, qtyMilli: 1234567)],
          ),
        ];
        tester.platformDispatcher.textScaleFactorTestValue = 1.4;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final order = suppliers.orders[ravi.id]!.single;
        for (final screen in [
          SupplierScreen(supplier: ravi, now: now),
          OrderScreen(supplier: ravi, chosen: order.lines, now: now),
          PaySupplierScreen(supplier: ravi, order: order),
          SupplierEntryScreen(supplier: ravi, kind: SupplierEntryKind.purchase, order: order, now: now),
        ]) {
          await pumpScreen(tester, fakeServices(), const SizedBox());
          tester.view.physicalSize = const Size(1080, 1920);
          await tester.pumpWidget(
            ServicesScope(
              key: UniqueKey(),
              services: fakeServices(suppliers: suppliers),
              child: MaterialApp(home: screen),
            ),
          );
          await tester.pumpAndSettle();
          if (screen is SupplierScreen) {
            await tapKey(tester, 'product-add-1');
            await tapKey(tester, 'tab-orders');
          }
          if (screen is OrderScreen) await tapKey(tester, 'line-add');
          expect(tester.takeException(), isNull, reason: '$screen');
        }
      });
    });

    testWidgets('connected: payments wait, agreed entries cannot be deleted', (tester) async {
      suppliers.links[ravi.id] = const SupplierLink(status: LinkStatus.on);
      SupplierEntry e(int id, int rupees, SupplierEntryKind kind, Confirm confirm) => SupplierEntry(
        id: id,
        kind: kind,
        amountPaise: rupees * 100,
        entryAt: DateTime(2026, 11, 20),
        clientRef: 'ref-$id',
        confirm: confirm,
        disputeReason: confirm == Confirm.disputed ? 'Not in bank' : null,
      );
      suppliers.entries[ravi.id] = [
        e(1, 1000, SupplierEntryKind.purchase, Confirm.confirmed),
        e(2, 300, SupplierEntryKind.payment, Confirm.waiting),
        e(3, 200, SupplierEntryKind.payment, Confirm.disputed),
      ];
      await open(tester);
      await tapKey(tester, 'tab-history');
      expect(textOf(tester, 'supplier-balance'), '₹1,000');
      expect(find.text('Both agreed'), findsOneWidget);
      expect(find.text('Not counted until they confirm'), findsOneWidget);
      expect(find.text('They say not right: Not in bank'), findsOneWidget);
      await tester.ensureVisible(find.text('Goods bought').last);
      await tester.tap(find.text('Goods bought').last);
      await tester.pumpAndSettle();
      expect(at('delete-reason'), findsNothing);
      expect(find.textContaining('cannot be deleted'), findsOneWidget);
    });

    group('what they write', () {
      Future<void> openWith(WidgetTester tester, {bool payment = false}) async {
        suppliers.links[ravi.id] = const SupplierLink(status: LinkStatus.on);
        suppliers.entries[ravi.id] = [
          SupplierEntry(
            id: 1,
            kind: payment ? SupplierEntryKind.payment : SupplierEntryKind.purchase,
            amountPaise: 48000,
            entryAt: now,
            clientRef: 's-1',
            note: 'Bill 9',
            confirm: Confirm.waiting,
            bySupplier: true,
            lines: payment ? const [] : const [EntryLine(name: 'Rice', unit: StockUnit.kg, qtyMilli: 10000)],
          ),
        ];
        await open(tester);
      }

      testWidgets('goods: yes, and they join the stock', (tester) async {
        await openWith(tester);
        expect(find.text('Ravi Traders wrote: goods given, ₹480'), findsOneWidget);
        expect(textOf(tester, 'supplier-balance'), '₹0');
        await tapKey(tester, 'their-yes-1');
        expect(find.textContaining('the items go into your stock'), findsOneWidget);
        await tapKey(tester, 'sure');
        expect(textOf(tester, 'supplier-balance'), '₹480');
        expect((await suppliers.stock.stock()).items.single.quantityMilli, 10000);
        expect(at('their-1'), findsNothing);
      });

      testWidgets('not right: why; kept in the history; only they delete it', (tester) async {
        await openWith(tester);
        await tapKey(tester, 'their-no-1');
        await tester.enterText(at('reason'), 'Never came');
        await tapKey(tester, 'reason-done');
        expect(textOf(tester, 'supplier-balance'), '₹0');
        expect(at('their-1'), findsNothing);
        await waitForMessage(tester);
        await tapKey(tester, 'tab-history');
        expect(find.text('You said: Never came'), findsOneWidget);
        expect(find.text('Written by them'), findsOneWidget);
        await tester.tap(find.text('Goods bought').last);
        await tester.pumpAndSettle();
        expect(find.textContaining('only they can delete it'), findsOneWidget);
      });

      testWidgets('money they say they got counts already', (tester) async {
        await openWith(tester, payment: true);
        expect(textOf(tester, 'supplier-balance'), contains('480'));
        expect(find.text('Already taken off what you owe'), findsOneWidget);
        suppliers.offline = true;
        await tapKey(tester, 'their-yes-1');
        await tapKey(tester, 'sure');
        expect(find.text('This needs internet.'), findsOneWidget);
      });

      testWidgets('the list says there is something to check', (tester) async {
        await openWith(tester);
        await tester.pumpWidget(const SizedBox());
        await pumpScreen(tester, fakeServices(suppliers: suppliers), SuppliersScreen(now: now));
        expect(find.text('1 to check'), findsOneWidget);
      });
    });

    testWidgets('their bill is filled in when the goods come', (tester) async {
      suppliers.links[ravi.id] = const SupplierLink(status: LinkStatus.on);
      final rice = suppliers.stock.seed('Rice', StockUnit.kg);
      suppliers.orders[ravi.id] = [
        SupplierOrder(
          id: 7,
          status: OrderStatus.dispatched,
          shared: true,
          totalPaise: 118000,
          answerNote: 'coming Friday',
          lines: [
            EntryLine(lineId: 1, itemId: rice.id, name: 'Rice', unit: rice.unit, qtyMilli: 25000, costPaise: 4720),
            const EntryLine(lineId: 2, name: 'Oil', unit: StockUnit.l, qtyMilli: 5000, available: false),
          ],
        ),
      ];
      await pumpScreen(
        tester,
        fakeServices(suppliers: suppliers, stock: suppliers.stock),
        SupplierScreen(supplier: ravi, now: now),
      );
      await tapKey(tester, 'tab-orders');
      expect(find.text('On the way'), findsOneWidget);
      expect(find.text('Bill ₹1,180'), findsOneWidget);
      expect(find.text('Not available: Oil'), findsOneWidget);
      expect(at('order-cancel-7'), findsNothing);
      await tapKey(tester, 'order-receive-7');
      expect(tester.widget<TextField>(at('entry-amount')).controller!.text, '1180');
      expect(tester.widget<TextField>(at('line-cost-1')).controller!.text, '47.20');
      expect(at('line-qty-2'), findsNothing); // not available
    });

    test('a payment written offline waits for the supplier too', () async {
      suppliers.links[ravi.id] = const SupplierLink(status: LinkStatus.on);
      final repository = SupplierRepository(suppliers, MemorySupplierStore());
      await repository.freshBook();
      suppliers.offline = true;
      await repository.addEntry(
        ravi.id,
        SupplierEntryDraft(kind: SupplierEntryKind.payment, amountPaise: 5000, entryAt: now),
      );
      expect((await repository.savedBook())!.suppliers.single.balancePaise, 0);
    });
  });

  group("the supplier's payments", () {
    Future<void> open(WidgetTester tester, {SupplyStore? store}) async {
      api.shops = [shop(1, opening: 1000), shop(2, name: 'Old shop', connected: false)];
      api.entries = {
        1: [entry(1, 400, payment: true), entry(2, 300, payment: true, confirm: Confirm.confirmed), entry(3, 900)],
        2: [entry(4, 50, payment: true, confirm: Confirm.closed)],
      };
      await pumpScreen(tester, fakeServices(supply: api, supplyStore: store), SupplyPaymentsScreen(now: now));
    }

    testWidgets('confirm what came', (tester) async {
      await open(tester);
      expect(textOf(tester, 'pay-month'), '₹300');
      expect(textOf(tester, 'pay-to-get'), '₹1,600');
      expect(find.text('Did these come?'), findsOneWidget);
      expect(at('payment-3'), findsNothing); // goods, not money
      expect(at('payment-yes-2'), findsNothing);
      expect(at('payment-yes-4'), findsNothing);
      await tapKey(tester, 'payment-yes-1');
      await tapKey(tester, 'sure');
      expect(api.calls, ['confirm 1']);
      expect(textOf(tester, 'pay-to-get'), '₹1,200');
      expect(find.text('Did these come?'), findsNothing);
    });

    testWidgets('not received: why; it can still be confirmed', (tester) async {
      await open(tester);
      await tapKey(tester, 'payment-no-1');
      await tester.enterText(at('reason'), 'Not in my bank');
      await tapKey(tester, 'reason-done');
      expect(find.text('You said: Not in my bank'), findsOneWidget);
      expect(at('payment-yes-1'), findsOneWidget);
      expect(at('payment-no-1'), findsNothing);
    });

    testWidgets('their UPI ID: checked, saved, removed', (tester) async {
      await open(tester);
      await tapKey(tester, 'payments-upi-edit');
      await tester.enterText(at('upi-id'), 'ravi');
      await tapKey(tester, 'upi-save');
      expect(find.text('Like ravitraders@okaxis'), findsOneWidget);
      await tester.enterText(at('upi-id'), ' ravi@okaxis ');
      await tester.enterText(at('upi-name'), 'Ravi Traders');
      await tapKey(tester, 'upi-save');
      expect(textOf(tester, 'payments-upi'), 'ravi@okaxis');
      await waitForMessage(tester);
      await tapKey(tester, 'payments-upi-edit');
      await tester.enterText(at('upi-id'), '');
      await tapKey(tester, 'upi-save');
      expect(find.text('UPI ID removed'), findsOneWidget);
      expect(textOf(tester, 'payments-upi'), startsWith('Add it'));
    });

    testWidgets('offline: the saved copy', (tester) async {
      final store = MemorySupplyStore();
      await open(tester);
      final saved = await SupplyRepository(api, store).payments();
      expect(SupplyPayments.fromJson(saved.toJson())!.toJson(), saved.toJson());
      for (final bad in ['x', <String, dynamic>{}, null]) {
        expect(SupplyPayments.fromJson(bad), isNull);
        expect(SupplyPayment.fromJson(bad), isNull);
      }
      await tester.pumpWidget(const SizedBox());
      api.offline = true;
      await open(tester, store: store);
      expect(textOf(tester, 'pay-month'), '₹300');
      expect(at('supply-error'), findsOneWidget);
    });

    testWidgets('an order says how it is paid', (tester) async {
      final o = SupplyOrder.fromJson({
        ...order(1).toJson(),
        'payPlan': 'LATER',
        'payBy': '2026-12-05',
        'paidPaise': 1000,
        'payingPaise': 2000,
      })!;
      api.all = [o];
      await pumpScreen(tester, fakeServices(supply: api), SupplyOrderScreen(order: o, now: now));
      expect(textOf(tester, 'order-plan'), 'Payment: Pay later, by 5 Dec');
      expect(find.text('They paid ₹10'), findsOneWidget);
      expect(textOf(tester, 'order-paying'), startsWith('They say they paid ₹20.'));
      await tapKey(tester, 'order-reject');
      expect(find.textContaining('stays as their advance'), findsOneWidget);
    });
  });

  group("the supplier's products", () {
    Future<void> open(WidgetTester tester, {SupplyStore? store}) =>
        pumpScreen(tester, fakeServices(supply: api, supplyStore: store), const ProductsScreen());

    testWidgets('from the ready list, with prices', (tester) async {
      await open(tester);
      expect(at('my-products-empty'), findsOneWidget);
      await tapKey(tester, 'products-ready');
      expect(tester.widget<FilledButton>(at('ready-add')).onPressed, isNull);
      await tapKey(tester, 'ready-rice');
      await typeIn(tester, 'ready-price-rice', '48');
      await tapKey(tester, 'ready-maida');
      await tapKey(tester, 'ready-add');
      expect(api.calls, ['add Rice KG 4800, Maida KG null']);
      expect(find.text('₹48/kg'), findsOneWidget);
      await waitForMessage(tester);
      await tapKey(tester, 'products-ready');
      expect(tester.widget<Checkbox>(at('ready-rice')).onChanged, isNull);
    });

    testWidgets('own product: checks, suggestion, change, not available, remove', (tester) async {
      await open(tester);
      await tapKey(tester, 'products-add');
      await tapKey(tester, 'product-save');
      expect(textOf(tester, 'product-error'), 'Enter the product name');
      await typeIn(tester, 'product-name', 'biyy');
      await tapKey(tester, 'product-suggest-rice');
      await typeIn(tester, 'product-name', 'Sona rice');
      await typeIn(tester, 'product-price', '1.2.3');
      await tapKey(tester, 'product-save');
      expect(textOf(tester, 'product-error'), 'Check the price');
      await typeIn(tester, 'product-price', '52.50');
      await tapKey(tester, 'product-save');
      expect(api.sells.single.catalogCode, 'rice');
      expect(api.calls.last, 'add Sona rice KG 5250');
      final id = api.sells.single.id;
      await waitForMessage(tester);
      await tapKey(tester, 'my-product-on-$id');
      expect(api.calls.last, 'change $id Sona rice 5250 false');
      expect(find.text('₹52.50/kg, not available'), findsOneWidget);
      await waitForMessage(tester);
      await tapKey(tester, 'my-product-$id');
      await typeIn(tester, 'product-price', '');
      await tapKey(tester, 'product-save');
      expect(api.calls.last, 'change $id Sona rice null false');
      await waitForMessage(tester);
      await tapKey(tester, 'my-product-$id');
      await tapKey(tester, 'product-remove');
      await tapKey(tester, 'sure');
      expect(api.sells, isEmpty);
    });

    testWidgets('offline: the saved copy; changing needs internet', (tester) async {
      final store = MemorySupplyStore();
      api.sells = [const Product(id: 1, name: 'Rice', unit: StockUnit.kg)];
      await SupplyRepository(api, store).products();
      api.offline = true;
      await open(tester, store: store);
      expect(find.text('Rice'), findsOneWidget);
      await tapKey(tester, 'my-product-on-1');
      expect(find.text('This needs internet. Please try again.'), findsOneWidget);
    });

    testWidgets('a new order from products has its bill filled in', (tester) async {
      final o = SupplyOrder.fromJson({
        ...order(1).toJson(),
        'lines': [
          {'id': 11, 'name': 'Rice', 'unit': 'KG', 'qtyMilli': 25000, 'costPaise': 4800},
          {'id': 12, 'name': 'Oil', 'unit': 'L', 'qtyMilli': 5000, 'costPaise': 15000},
        ],
      })!;
      api.all = [o];
      await pumpScreen(tester, fakeServices(supply: api), SupplyOrderScreen(order: o, now: now));
      expect(tester.widget<TextField>(at('order-total')).controller!.text, '1950');
      await tapKey(tester, 'order-accept');
      expect(api.calls, ['accept order 1 195000']);
    });
  });

  group("the supplier's own stock", () {
    setUp(() => api.sells = [const Product(id: 1, name: 'Rice', unit: StockUnit.kg, pricePaise: 4800)]);

    testWidgets('start counting, in, out, correct, warn, stop', (tester) async {
      await pumpScreen(tester, fakeServices(supply: api), const ProductsScreen());
      expect(at('my-product-left-1'), findsNothing);
      await tapKey(tester, 'my-product-stock-1');
      expect(at('stock-why'), findsOneWidget);
      await tapKey(tester, 'stock-start');
      await tapKey(tester, 'move-save');
      expect(find.text('Enter how much'), findsOneWidget);
      await typeIn(tester, 'move-qty', '50');
      await tapKey(tester, 'move-save');
      expect(textOf(tester, 'stock-left'), '50 kg');
      await waitForMessage(tester);
      await tapKey(tester, 'stock-in');
      await typeIn(tester, 'move-qty', '0');
      await tapKey(tester, 'move-save');
      expect(find.text('Enter how much'), findsOneWidget);
      await typeIn(tester, 'move-qty', '25.5');
      await typeIn(tester, 'move-note', 'From the mill');
      await tapKey(tester, 'move-save');
      await waitForMessage(tester);
      await tapKey(tester, 'stock-out');
      await typeIn(tester, 'move-qty', '5.5');
      await tapKey(tester, 'move-save');
      expect(textOf(tester, 'stock-left'), '70 kg');
      expect(find.text('From the mill'), findsOneWidget);
      await waitForMessage(tester);
      await tapKey(tester, 'stock-count');
      await typeIn(tester, 'move-qty', '0');
      await tapKey(tester, 'move-save');
      expect(find.text('Shops see: not available'), findsOneWidget);
      expect(find.text('− 70 kg'), findsOneWidget);
      await waitForMessage(tester);
      await tapKey(tester, 'stock-in');
      await typeIn(tester, 'move-qty', '4');
      await tapKey(tester, 'move-save');
      await waitForMessage(tester);
      await tapKey(tester, 'stock-menu');
      await tapKey(tester, 'stock-warn');
      await typeIn(tester, 'warn-qty', '1.2.3');
      await tapKey(tester, 'warn-save');
      expect(find.text('Check the number'), findsOneWidget);
      await typeIn(tester, 'warn-qty', '5');
      await tapKey(tester, 'warn-save');
      expect(find.text('Warns at 5 kg'), findsOneWidget);
      expect(find.text('Running low'), findsOneWidget);
      await waitForMessage(tester);
      await tapKey(tester, 'udhaar-back');
      expect(textOf(tester, 'my-product-left-1'), 'You have 4 kg');
      await tapKey(tester, 'my-product-stock-1');
      await tapKey(tester, 'stock-menu');
      await tapKey(tester, 'stock-stop');
      await tapKey(tester, 'sure');
      expect(api.calls.last, 'counting 1 false 5000');
      expect(at('stock-start'), findsOneWidget);
    });

    testWidgets('needs internet', (tester) async {
      api.offline = true;
      await pumpScreen(tester, fakeServices(supply: api), ProductStockScreen(product: api.sells.single, now: now));
      expect(at('supply-error'), findsOneWidget);
      await tapKey(tester, 'stock-start');
      await typeIn(tester, 'move-qty', '5');
      await tapKey(tester, 'move-save');
      expect(find.text('This needs internet. Please try again.'), findsOneWidget);
    });

    testWidgets('answering an order shows what there is', (tester) async {
      final o = SupplyOrder.fromJson({
        ...order(1).toJson(),
        'lines': [
          {'id': 11, 'name': 'Rice', 'unit': 'KG', 'qtyMilli': 25000, 'haveMilli': 20000},
          {'id': 12, 'name': 'Oil', 'unit': 'L', 'qtyMilli': 5000},
        ],
      })!;
      api.all = [o];
      await pumpScreen(tester, fakeServices(supply: api), SupplyOrderScreen(order: o, now: now));
      expect(textOf(tester, 'line-left-11'), 'You have 20 kg');
      expect(at('line-left-12'), findsNothing);
    });

    test('copies survive saving; bad ones are refused', () {
      const p = Product(id: 1, name: 'Rice', unit: StockUnit.kg, counted: true, quantityMilli: 5, alertMilli: 9, low: true);
      expect(Product.fromJson(p.toJson())!.toJson(), p.toJson());
      for (final bad in ['x', <String, dynamic>{}, null]) {
        expect(ProductMove.fromJson(bad), isNull);
        expect(ProductStock.fromJson(bad), isNull);
        expect(SupplyReport.fromJson(bad), isNull);
        expect(ReportShop.fromJson(bad), isNull);
        expect(ReportProduct.fromJson(bad), isNull);
      }
      final s = ProductStock.fromJson({
        'product': p.toJson(),
        'moves': [
          {'id': 1, 'kind': 'OUT', 'qtyMilli': 500, 'note': 'To Balaji', 'moveAt': '2026-11-24T10:00:00Z'},
        ],
      })!;
      expect((s.moves.single.effect, s.moves.single.note), (-500, 'To Balaji'));
    });
  });

  group('reports', () {
    final full = SupplyReport.fromJson({
      'givenPaise': 145000,
      'receivedPaise': 20000,
      'waitingPaise': 7000,
      'toGetPaise': 912700,
      'orders': {'RECEIVED': 3, 'REJECTED': 1},
      'shops': [
        {'shopName': 'Balaji', 'givenPaise': 90000, 'receivedPaise': 0, 'toGetPaise': 90000, 'connected': true},
        {'shopName': 'Lakshmi', 'givenPaise': 55000, 'receivedPaise': 20000, 'toGetPaise': -500, 'connected': false},
      ],
      'products': [
        {'name': 'Rice', 'unit': 'KG', 'qtyMilli': 11500, 'amountPaise': 55500},
        {'name': 'Salt', 'unit': 'BAG', 'qtyMilli': 1000, 'amountPaise': null},
      ],
    })!;

    testWidgets('this month, by shop and product, shared on WhatsApp', (tester) async {
      api.reportAnswer = full;
      final device = FakeDeviceActions();
      await pumpScreen(tester, fakeServices(supply: api, device: device), SupplyReportScreen(now: now));
      expect(api.calls, ['report 2026-11-01 2026-11-24']);
      expect(find.text('1 Nov to 24 Nov'), findsOneWidget);
      expect(textOf(tester, 'report-given'), '₹1,450');
      expect(textOf(tester, 'report-received'), '₹200');
      expect(textOf(tester, 'report-to-get'), '₹9,127');
      expect(textOf(tester, 'report-waiting'), '₹70');
      expect(textOf(tester, 'report-orders'), '4 orders');
      expect(find.text('Rejected: 1, Received by the shop: 3'), findsOneWidget);
      expect(find.text('Lakshmi (disconnected)'), findsOneWidget);
      expect(find.text('Received ₹200, ₹5 advance'), findsOneWidget);
      expect(find.text('11.5 kg'), findsOneWidget);
      await tapKey(tester, 'report-share');
      final text = device.opened.single.queryParameters['text']!;
      expect(text, contains('Goods given: ₹1,450'));
      expect(text, contains('Balaji: given ₹900, received ₹0, to get ₹900'));
      device.failScheme = 'whatsapp';
      await tapKey(tester, 'report-share');
      expect(find.text('WhatsApp is not installed on this phone.'), findsOneWidget);
    });

    testWidgets('other periods; old numbers never stay', (tester) async {
      api.reportAnswer = full;
      await pumpScreen(tester, fakeServices(supply: api), SupplyReportScreen(now: now));
      await tapKey(tester, 'report-lastMonth');
      await tapKey(tester, 'report-threeMonths');
      await tapKey(tester, 'report-thisYear');
      expect(api.calls.skip(1), [
        'report 2026-10-01 2026-10-31',
        'report 2026-09-01 2026-11-24',
        'report 2026-01-01 2026-11-24',
      ]);
      api.offline = true;
      await tapKey(tester, 'report-thisMonth');
      expect(at('report-given'), findsNothing);
      expect(at('supply-error'), findsOneWidget);
      expect(tester.widget<IconButton>(at('report-share')).onPressed, isNull);
      expect(ReportPeriod.lastMonth.days(DateTime(2027, 1, 15)), (DateTime(2026, 12, 1), DateTime(2026, 12, 31)));
      expect(ReportPeriod.threeMonths.days(DateTime(2027, 1, 15)).$1, DateTime(2026, 11, 1));
    });

    testWidgets('nothing yet', (tester) async {
      await pumpScreen(tester, fakeServices(supply: api), SupplyReportScreen(now: now));
      expect(at('report-no-shops'), findsOneWidget);
      expect(at('report-no-products'), findsOneWidget);
      expect(textOf(tester, 'report-orders'), '0 orders');
      await tapKey(tester, 'report-custom');
      expect(find.byType(DateRangePickerDialog), findsOneWidget);
    });
  });

  testWidgets('supplier home: all 8 tiles open', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ServicesScope(
        services: fakeServices(supply: api),
        child: OnboardingScope(draft: OnboardingDraft(), child: const MaterialApp(home: SupplierHomeScreen())),
      ),
    );
    await tester.pumpAndSettle();
    for (final (tile, key) in [
      ('Orders', 'orders-empty-0'),
      ('Shop Ledger', 'supply-empty'),
      ('Payments', 'payments-empty'),
      ('Products', 'my-products-empty'),
      ('Reports', 'report-orders'),
    ]) {
      await tapKey(tester, 'tool-$tile');
      expect(at(key), findsOneWidget);
      await tapKey(tester, 'udhaar-back');
    }
    await tapKey(tester, 'tool-Calendar');
    expect(find.text('Supply Calendar'), findsOneWidget);
    for (final tile in ['Calculator', 'Translator']) {
      expect(find.byKey(Key('tool-$tile'), skipOffstage: false), findsOneWidget);
    }
  });

  testWidgets('a small phone with big text has room for everything', (tester) async {
    api.shops = [shop(1, name: 'A shop with a very long name', opening: 123456)];
    api.requests = [request(2, 98765)];
    api.entries = {1: [entry(1, 123456, payment: true)]};
    api.all = [order(1)];
    api.sells = [
      const Product(id: 1, name: 'A product with a very long name', unit: StockUnit.dozen, counted: true, quantityMilli: 1234567),
    ];
    api.reportAnswer = const SupplyReport(
      givenPaise: 123456789,
      receivedPaise: 123456789,
      toGetPaise: 123456789,
      shops: [ReportShop(name: 'A shop with a very long name', givenPaise: 123456789, toGetPaise: 123456789)],
      products: [ReportProduct(name: 'A very long product name', unit: StockUnit.dozen, qtyMilli: 1234567, amountPaise: 99999999)],
    );
    tester.platformDispatcher.textScaleFactorTestValue = 1.4;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    for (final screen in [
      SupplyShopsScreen(now: now),
      SupplyShopScreen(shop: api.shops.first, now: now),
      SupplyEntryScreen(shop: api.shops.first, kind: SupplierEntryKind.purchase),
      SupplyOrdersScreen(now: now),
      SupplyOrderScreen(order: api.all.first, now: now),
      SupplyPaymentsScreen(now: now),
      SupplyReportScreen(now: now),
      ProductsScreen(key: UniqueKey()),
      ProductStockScreen(product: api.sells.first, now: now),
    ]) {
      await pumpScreen(tester, fakeServices(supply: api), const SizedBox());
      tester.view.physicalSize = const Size(1080, 1920);
      await tester.pumpWidget(
        ServicesScope(
          key: UniqueKey(),
          services: fakeServices(supply: api),
          child: MaterialApp(home: screen),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '$screen');
    }
  });
}
