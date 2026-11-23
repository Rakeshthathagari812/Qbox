import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qbox_app/services/device_actions.dart';
import 'package:qbox_app/stock/stock_models.dart';
import 'package:qbox_app/suppliers/order_screen.dart';
import 'package:qbox_app/suppliers/supplier_models.dart';
import 'package:qbox_app/suppliers/supplier_repository.dart';
import 'package:qbox_app/suppliers/supplier_screen.dart';
import 'package:qbox_app/suppliers/suppliers_screen.dart';
import 'package:qbox_app/translator/languages.dart';

import 'fake_auth_api.dart';
import 'udhaar_screen_test.dart' show pumpScreen, tapKey;

final now = DateTime(2026, 11, 23, 15);

Future<void> typeIn(WidgetTester tester, String key, String text) async {
  await tester.enterText(find.byKey(Key(key)), text);
  await tester.pumpAndSettle();
}

String textOf(WidgetTester tester, String key) => tester.widget<Text>(find.byKey(Key(key))).data!;

void main() {
  group('helpers', () {
    test('WhatsApp order: English with names in the shop language', () {
      final text = orderMessage(
        shopName: 'Lakshmi Stores',
        lines: const [
          EntryLine(itemId: 1, name: 'Rice', unit: StockUnit.kg, qtyMilli: 25000),
          EntryLine(itemId: 2, name: 'Lux soap', unit: StockUnit.piece, qtyMilli: 12000),
        ],
        catalogCodes: const {1: 'rice', 2: null},
        language: AppLanguage.telugu,
        note: 'deliver by Friday',
      );
      expect(text,
          'Order from Lakshmi Stores:\n1. Rice (బియ్యం) - 25 kg\n2. Lux soap - 12 pcs\nNote: deliver by Friday\nPlease confirm. Thank you.');
    });

    test('suggested order brings stock to twice the alert level, in whole units', () {
      expect(suggestedOrder(const StockItem(id: 1, name: 'Rice', unit: StockUnit.kg, quantityMilli: 3000, alertMilli: 10000)), 17000);
      expect(suggestedOrder(const StockItem(id: 1, name: 'Oil', unit: StockUnit.l, quantityMilli: 4500, alertMilli: 5000)), 6000);
      expect(suggestedOrder(const StockItem(id: 1, name: 'X', unit: StockUnit.piece)), 1000);
    });

    test('pay-by reminders only for money still due on a date', () {
      final dues = dueReminders(SupplierBook([
        Supplier(id: 1, name: 'Ravi Traders', balancePaise: 700000, nextDue: DateTime(2026, 11, 30)),
        Supplier(id: 2, name: 'Paid up', nextDue: DateTime(2026, 11, 30)),
        const Supplier(id: 3, name: 'No date', balancePaise: 100),
      ]));
      expect(dues.map((d) => d.title), ['Pay Ravi Traders today']);
      expect(dues.single.body, 'You owe ₹7,000. Due today, Mon, 30 November 2026.');
    });
  });

  group('screens', () {
    testWidgets('list: what is owed, overdue, reminders set', (tester) async {
      final api = FakeSupplierApi();
      final ravi = api.seed('Ravi Traders', supplies: 'Rice, dal');
      api.seed('Sri Oils');
      await api.addEntry(ravi.id, SupplierEntryDraft(kind: SupplierEntryKind.purchase, amountPaise: 1200000, entryAt: now));
      api.dueDates[ravi.id] = DateTime(2026, 11, 20);
      final reminders = FakeReminders();
      await pumpScreen(tester, fakeServices(suppliers: api, reminders: reminders), SuppliersScreen(now: now));
      expect(textOf(tester, 'suppliers-total'), '₹12,000');
      expect(find.byKey(const Key('suppliers-overdue')), findsOneWidget);
      expect(find.text('Overdue'), findsOneWidget);
      expect(reminders.dues, ['2026-11-20: Pay Ravi Traders today']);
      await typeIn(tester, 'suppliers-search', 'dal');
      expect(find.text('Sri Oils'), findsNothing);
    });

    testWidgets('add a supplier from contacts', (tester) async {
      final api = FakeSupplierApi();
      final device = FakeDeviceActions()..nextContact = const PickedContact(name: 'Ravi Traders', phone: '+91 98480-22338');
      await pumpScreen(tester, fakeServices(suppliers: api, device: device), SuppliersScreen(now: now));
      expect(find.byKey(const Key('suppliers-empty')), findsOneWidget);
      await tapKey(tester, 'suppliers-add');
      await tapKey(tester, 'supplier-contact');
      await typeIn(tester, 'supplier-supplies', 'Rice, dal');
      await tapKey(tester, 'supplier-save');
      final saved = api.known.values.single;
      expect(saved.name, 'Ravi Traders');
      expect(saved.mobile, '9848022338');
      expect(find.text('Ravi Traders'), findsWidgets); // their page opened
    });

    testWidgets('purchase with items: stock goes up, balance up; then a payment', (tester) async {
      final stock = FakeStockApi();
      final rice = stock.seed('Rice', StockUnit.kg, qty: 5000);
      final api = FakeSupplierApi(stock: stock);
      final ravi = api.seed('Ravi Traders');
      final services = fakeServices(suppliers: api, stock: stock);
      await pumpScreen(tester, services, SupplierScreen(supplier: ravi, now: now));

      await tapKey(tester, 'supplier-purchase');
      await tapKey(tester, 'line-add');
      await tapKey(tester, 'pick-${rice.id}');
      await typeIn(tester, 'line-qty-${rice.id}', '25');
      await typeIn(tester, 'line-cost-${rice.id}', '48');
      await tapKey(tester, 'entry-use-total');
      expect(tester.widget<TextField>(find.byKey(const Key('entry-amount'))).controller!.text, '1200');
      await tapKey(tester, 'entry-save');
      expect(textOf(tester, 'supplier-balance'), '₹1,200');
      expect(find.text('Rice 25 kg'), findsOneWidget);
      expect((await stock.item(rice.id)).item.quantityMilli, 30000);

      await tapKey(tester, 'supplier-payment');
      await typeIn(tester, 'entry-amount', '500');
      await tapKey(tester, 'entry-method-UPI');
      await tapKey(tester, 'entry-save');
      expect(textOf(tester, 'supplier-balance'), '₹700');
      expect(api.entries[ravi.id]!.last.method, PayMethod.upi);
    });

    testWidgets('purchase paid now adds nothing to what is owed', (tester) async {
      final api = FakeSupplierApi();
      final ravi = api.seed('Ravi Traders');
      await pumpScreen(tester, fakeServices(suppliers: api), SupplierScreen(supplier: ravi, now: now));
      await tapKey(tester, 'supplier-purchase');
      await typeIn(tester, 'entry-amount', '800');
      await tapKey(tester, 'entry-paid-now');
      expect(find.byKey(const Key('entry-due')), findsNothing);
      await tapKey(tester, 'entry-save');
      expect(textOf(tester, 'supplier-balance'), '₹0');
      expect(api.entries[ravi.id]!.map((e) => e.kind), [SupplierEntryKind.purchase, SupplierEntryKind.payment]);
    });

    testWidgets('order from low stock, sent on WhatsApp, then goods received', (tester) async {
      final stock = FakeStockApi();
      final rice = stock.seed('Rice', StockUnit.kg, qty: 3000, alert: 10000, code: 'rice');
      stock.seed('Salt', StockUnit.packet, qty: 50000, alert: 5000);
      final api = FakeSupplierApi(stock: stock);
      final ravi = api.seed('Ravi Traders', mobile: '9848022338');
      final device = FakeDeviceActions();
      await pumpScreen(tester, fakeServices(suppliers: api, stock: stock, device: device), SupplierScreen(supplier: ravi, now: now));

      await tapKey(tester, 'supplier-order');
      // Only the low item is filled in, with the suggested amount.
      expect(tester.widget<TextField>(find.byKey(Key('line-qty-${rice.id}'))).controller!.text, '17');
      expect(find.text('Salt'), findsNothing);
      await tapKey(tester, 'order-send');
      final link = device.opened.single;
      expect(link.scheme, 'whatsapp');
      expect(link.queryParameters['phone'], '919848022338');
      expect(link.queryParameters['text'], contains('1. Rice - 17 kg'));
      expect(find.text('Waiting for goods'), findsOneWidget);

      final order = api.orders[ravi.id]!.single;
      await tapKey(tester, 'order-receive-${order.id}');
      await typeIn(tester, 'line-qty-${rice.id}', '15');
      await typeIn(tester, 'entry-amount', '720');
      await tapKey(tester, 'entry-save');
      expect(find.text('Goods received: stock updated'), findsOneWidget);
      expect(find.text('Waiting for goods'), findsNothing);
      expect((await stock.item(rice.id)).item.quantityMilli, 18000);
      expect(textOf(tester, 'supplier-balance'), '₹720');
    });

    testWidgets('delete an entry with a reason (kept, crossed out)', (tester) async {
      final api = FakeSupplierApi();
      final ravi = api.seed('Ravi Traders');
      await api.addEntry(ravi.id, SupplierEntryDraft(kind: SupplierEntryKind.purchase, amountPaise: 50000, entryAt: now, note: 'Bill 12'));
      await pumpScreen(tester, fakeServices(suppliers: api), SupplierScreen(supplier: ravi, now: now));
      await tapKey(tester, 'supplier-purchase'); // open and close the form: nothing saved
      await tester.tap(find.byKey(const Key('udhaar-back')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bill 12'));
      await tester.pumpAndSettle();
      await typeIn(tester, 'delete-reason', 'wrong supplier');
      await tapKey(tester, 'delete-yes');
      expect(find.text('Deleted: wrong supplier'), findsOneWidget);
      expect(textOf(tester, 'supplier-balance'), '₹0');
    });

    testWidgets('offline payment kept on the phone, then synced once', (tester) async {
      final api = FakeSupplierApi();
      final ravi = api.seed('Ravi Traders');
      await api.addEntry(ravi.id, SupplierEntryDraft(kind: SupplierEntryKind.purchase, amountPaise: 100000, entryAt: now));
      final store = MemorySupplierStore();
      final services = fakeServices(suppliers: api, supplierStore: store);
      await services.suppliers.freshSupplier(ravi.id);
      api.offline = true;
      await pumpScreen(tester, services, SupplierScreen(supplier: ravi, now: now));
      await tapKey(tester, 'supplier-payment');
      await typeIn(tester, 'entry-amount', '400');
      await tapKey(tester, 'entry-save');
      expect(find.text('Saved on the phone. It will sync when internet is back.'), findsOneWidget);
      expect(textOf(tester, 'supplier-balance'), '₹600');
      expect(find.text('⏳ Waiting for internet to sync'), findsOneWidget);

      api.offline = false;
      await pumpScreen(tester, services, SuppliersScreen(now: now));
      expect(find.text('1 offline entry is now saved'), findsOneWidget);
      expect(store.pending, isEmpty);
      expect(api.entries[ravi.id]!.length, 2);
    });
  });
}
