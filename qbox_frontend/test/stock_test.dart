import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qbox_app/services/settings_store.dart';
import 'package:qbox_app/stock/item_screen.dart';
import 'package:qbox_app/stock/stock_models.dart';
import 'package:qbox_app/stock/stock_repository.dart';
import 'package:qbox_app/stock/stock_screen.dart';
import 'package:qbox_app/stock/stock_store.dart';
import 'package:qbox_app/stock/voice_stock.dart';
import 'package:qbox_app/translator/languages.dart';
import 'package:qbox_app/translator/voice_language.dart';

import 'fake_auth_api.dart';
import 'udhaar_screen_test.dart' show pumpScreen, tapKey;

final now = DateTime(2026, 11, 23, 15);

Future<void> typeIn(WidgetTester tester, String key, String text) async {
  await tester.enterText(find.byKey(Key(key)), text);
  await tester.pumpAndSettle();
}

String textOf(WidgetTester tester, String key) => tester.widget<Text>(find.byKey(Key(key))).data!;

void main() {
  group('quantities', () {
    test('shown and typed in thousandths of the unit', () {
      expect(formatQty(1500, StockUnit.kg), '1.5 kg');
      expect(formatQty(3000, StockUnit.piece), '3 pcs');
      expect(formatQty(1250, StockUnit.l), '1.25 L');
      expect(formatQty(-500, StockUnit.kg), '-0.5 kg');
      expect(parseQty('1.5'), 1500);
      expect(parseQty('12'), 12000);
      expect(parseQty('0.125'), 125);
      expect(parseQty('1.2345'), isNull);
      expect(parseQty('abc'), isNull);
    });

    test('units convert within their kind only', () {
      expect(StockUnit.kg.convert(500000, StockUnit.g), 500); // 500 g = 0.5 kg
      expect(StockUnit.g.convert(2000, StockUnit.kg), 2000000);
      expect(StockUnit.l.convert(250000, StockUnit.ml), 250);
      expect(StockUnit.piece.convert(2000, StockUnit.dozen), 24000);
      expect(StockUnit.kg.convert(1000, StockUnit.packet), isNull);
    });

    test('value and low stock', () {
      const item = StockItem(id: 1, name: 'Rice', unit: StockUnit.kg, quantityMilli: 4500, costPaise: 4800, alertMilli: 5000);
      expect(item.valuePaise, 21600);
      expect(item.isLow, isTrue);
      expect(item.copyWith(quantityMilli: 6000).isLow, isFalse);
    });
  });

  group('voice', () {
    const rice = StockItem(id: 1, name: 'Rice', unit: StockUnit.kg, catalogCode: 'rice', quantityMilli: 40000);
    const sugar = StockItem(id: 2, name: 'Sugar', unit: StockUnit.kg, catalogCode: 'sugar', quantityMilli: 10000);
    const oil = StockItem(id: 3, name: 'Sunflower oil', unit: StockUnit.l, catalogCode: 'sunflower_oil');
    const custom = StockItem(id: 4, name: 'Sona masoori', unit: StockUnit.kg);
    const items = [rice, sugar, oil, custom];

    test('English', () {
      final s = parseSpokenStock('rice 10 kg came', AppLanguage.english, items)!;
      expect(s.matches, [rice]);
      expect(s.kind, MoveKind.stockIn);
      expect(s.qtyFor(rice), 10000);

      final sold = parseSpokenStock('sold 500 grams sugar', AppLanguage.english, items)!;
      expect(sold.matches, [sugar]);
      expect(sold.kind, MoveKind.out);
      expect(sold.qtyFor(sugar), 500); // 0.5 kg

      final words = parseSpokenStock('two litres sunflower oil sold', AppLanguage.english, items)!;
      expect(words.matches, [oil]);
      expect(words.qtyFor(oil), 2000);
    });

    test('Telugu, Hindi, Kannada and Tamil names and numbers', () {
      final te = parseSpokenStock('బియ్యం పది కిలోలు వచ్చాయి', AppLanguage.telugu, items)!;
      expect(te.matches, [rice]);
      expect(te.kind, MoveKind.stockIn);
      expect(te.qtyFor(rice), 10000);

      final hi = parseSpokenStock('चीनी 2 किलो बिकी', AppLanguage.hindi, items)!;
      expect(hi.matches, [sugar]);
      expect(hi.kind, MoveKind.out);
      expect(hi.qtyFor(sugar), 2000);

      final kn = parseSpokenStock('ಅಕ್ಕಿ 5 ಕಿಲೋ ಬಂತು', AppLanguage.kannada, items)!;
      expect(kn.matches, [rice]);
      expect(kn.kind, MoveKind.stockIn);

      final ta = parseSpokenStock('அரிசி 3 கிலோ விற்றேன்', AppLanguage.tamil, items)!;
      expect(ta.matches, [rice]);
      expect(ta.kind, MoveKind.out);
      expect(ta.qtyFor(rice), 3000);
    });

    test('own item names said in Telugu letters', () {
      final s = parseSpokenStock('సోనా మసూరి 25 కిలోలు వచ్చాయి', AppLanguage.telugu, items)!;
      expect(s.matches, [custom]);
      expect(s.qtyFor(custom), 25000);
    });

    test('a ready-list item not in stock yet, and unclear sentences', () {
      final s = parseSpokenStock('onion 5 kg came', AppLanguage.english, items)!;
      expect(s.matches, isEmpty);
      expect(s.newItem?.code, 'onion');

      final noKind = parseSpokenStock('rice 4 kg', AppLanguage.english, items)!;
      expect(noKind.kind, isNull);

      final two = parseSpokenStock('rice 2 kg sold', AppLanguage.english,
          [rice, const StockItem(id: 9, name: 'Basmati', unit: StockUnit.kg, catalogCode: 'rice')])!;
      expect(two.matches.length, 2);

      expect(parseSpokenStock('hello there', AppLanguage.english, items), isNull);
    });
  });

  group('offline', () {
    test('a move is kept on the phone, counted, and sent once later', () async {
      final api = FakeStockApi();
      final rice = api.seed('Rice', StockUnit.kg, qty: 10000);
      final repo = StockRepository(api, MemoryStockStore());
      await repo.freshBook();

      api.offline = true;
      final outcome = await repo.addMove(rice.id, MoveDraft(kind: MoveKind.out, qtyMilli: 2000, moveAt: now));
      expect(outcome, MoveSaved.savedOffline);
      expect((await repo.savedBook())!.items.single.quantityMilli, 8000);
      expect(await repo.pendingCount(), 1);

      api.offline = false;
      final report = await repo.sendPending();
      expect(report.sent, 1);
      await repo.sendPending();
      expect(api.moves[rice.id]!.length, 2); // opening + the sale, once
      expect((await repo.freshBook()).items.single.quantityMilli, 8000);
    });
  });

  group('screens', () {
    testWidgets('list: value, low filter, search in any language, home badge count', (tester) async {
      final api = FakeStockApi();
      api.seed('Rice', StockUnit.kg, qty: 40000, cost: 4800, code: 'rice');
      api.seed('Sugar', StockUnit.kg, qty: 3000, alert: 5000, cost: 4000, code: 'sugar');
      final services = fakeServices(stock: api);
      await pumpScreen(tester, services, StockScreen(now: now));

      expect(textOf(tester, 'stock-value'), '₹2,040');
      expect(find.text('1 running low'), findsOneWidget);
      expect(services.stock.lowCount.value, 1);
      await tapKey(tester, 'stock-low-chip');
      expect(find.text('Rice'), findsNothing);
      expect(find.text('Sugar'), findsOneWidget);
      await tapKey(tester, 'stock-low-chip');

      await typeIn(tester, 'stock-search', 'చక్కెర');
      expect(find.text('Sugar'), findsOneWidget);
      expect(find.text('Rice'), findsNothing);
    });

    testWidgets('quick start: tick common items with quantities', (tester) async {
      final api = FakeStockApi();
      await pumpScreen(tester, fakeServices(stock: api), StockScreen(now: now));
      expect(find.byKey(const Key('stock-empty')), findsOneWidget);

      await tapKey(tester, 'stock-quick-start-empty');
      await tapKey(tester, 'quick-rice');
      await typeIn(tester, 'quick-qty-rice', '25');
      await typeIn(tester, 'quick-search', 'चीनी');
      await tapKey(tester, 'quick-sugar');
      await tapKey(tester, 'quick-add');

      expect(find.text('2 items added'), findsOneWidget);
      expect(find.text('25 kg'), findsOneWidget);
      expect(find.text('0 kg'), findsOneWidget);
      expect(api.items.values.map((i) => i.catalogCode), containsAll(['rice', 'sugar']));
    });

    testWidgets('own items show in "Your items" and can be added back after removing', (tester) async {
      final api = FakeStockApi();
      api.seed('Rice', StockUnit.kg, code: 'rice'); // a plain ready-list item: not in "Your items"
      final lux = api.seed('Lux soap', StockUnit.piece, qty: 5000);
      final sona = api.seed('Sona masoori', StockUnit.kg, code: 'rice');
      await api.archiveItem(sona.id);
      await pumpScreen(tester, fakeServices(stock: api), StockScreen(now: now));

      await tapKey(tester, 'stock-quick-start');
      expect(find.text('Your items'), findsOneWidget);
      expect(find.byKey(const Key('quick-own-rice')), findsNothing);
      // Lux soap is in stock: shown, but cannot be ticked again.
      expect(tester.widget<Checkbox>(find.byKey(const Key('quick-own-lux soap'))).onChanged, isNull);
      await tapKey(tester, 'quick-own-sona masoori');
      await typeIn(tester, 'quick-qty-own-sona masoori', '20');
      await tapKey(tester, 'quick-add');
      expect(find.text('1 item added'), findsOneWidget);
      final back = api.items.values.firstWhere((i) => i.name == 'Sona masoori');
      expect(back.catalogCode, 'rice'); // still heard as "బియ్యం" by voice
      expect(find.text('20 kg'), findsOneWidget);

      // Removed items are also suggested while typing a new item's name.
      await api.archiveItem(lux.id);
      await tester.drag(find.byType(ListView).first, const Offset(0, 300));
      await tester.pumpAndSettle();
      await tapKey(tester, 'stock-add');
      await typeIn(tester, 'item-name', 'lux');
      await tapKey(tester, 'item-past-lux soap');
      await tapKey(tester, 'item-save');
      expect(api.items.values.firstWhere((i) => i.name == 'Lux soap').unit, StockUnit.piece);
    });

    testWidgets('item: sold, then "running low" notification once', (tester) async {
      final api = FakeStockApi();
      final sugar = api.seed('Sugar', StockUnit.kg, qty: 6000, alert: 5000);
      final reminders = FakeReminders();
      final services = fakeServices(stock: api, reminders: reminders);
      await services.stock.freshBook();
      await pumpScreen(tester, services, ItemScreen(item: sugar, now: now));
      expect(textOf(tester, 'item-qty'), '6 kg');

      await tapKey(tester, 'item-out');
      await typeIn(tester, 'move-qty', '1.5');
      await tapKey(tester, 'move-save');
      expect(textOf(tester, 'item-qty'), '4.5 kg');
      expect(find.text('Saved: Sugar −1.5 kg'), findsOneWidget);
      expect(reminders.shown, ['Running low: Sugar: Only 4.5 kg left. Order more soon.']);

      // Already low: no second notification for the next sale.
      await tapKey(tester, 'item-out');
      await typeIn(tester, 'move-qty', '1');
      await tapKey(tester, 'move-save');
      expect(reminders.shown.length, 1);
    });

    testWidgets('correct the count needs a reason', (tester) async {
      final api = FakeStockApi();
      final rice = api.seed('Rice', StockUnit.kg, qty: 10000);
      await pumpScreen(tester, fakeServices(stock: api), ItemScreen(item: rice, now: now));
      await tapKey(tester, 'item-adjust');
      await typeIn(tester, 'move-qty', '9.5');
      expect(find.text('Change: −0.5 kg'), findsOneWidget);
      await tapKey(tester, 'move-save');
      expect(find.byKey(const Key('move-error')), findsOneWidget);
      await typeIn(tester, 'move-note', 'spilled');
      await tapKey(tester, 'move-save');
      expect(textOf(tester, 'item-qty'), '9.5 kg');
      expect(api.moves[rice.id]!.last.qtyMilli, -500);
    });

    testWidgets('voice in Telugu opens the sheet filled in', (tester) async {
      final api = FakeStockApi();
      final rice = api.seed('Rice', StockUnit.kg, qty: 20000, code: 'rice');
      final settings = MemorySettingsStore();
      await saveVoiceLanguage(settings, AppLanguage.telugu);
      final voice = FakeVoiceInput()..nextWords = 'బియ్యం 10 కిలోలు వచ్చాయి';
      await pumpScreen(tester, fakeServices(stock: api, voice: voice, settings: settings), StockScreen(now: now));
      await tapKey(tester, 'stock-speak');
      expect(voice.lastLocale, 'te_IN');
      expect(tester.widget<TextField>(find.byKey(const Key('move-qty'))).controller!.text, '10');
      await tapKey(tester, 'move-save');
      expect(find.text('Saved: Rice +10 kg'), findsOneWidget);
      expect(api.moves[rice.id]!.last.kind, MoveKind.stockIn);
      expect(find.text('30 kg'), findsOneWidget);
    });

    testWidgets('add an item with a ready-list suggestion; same name refused', (tester) async {
      final api = FakeStockApi();
      api.seed('Sugar', StockUnit.kg);
      await pumpScreen(tester, fakeServices(stock: api), StockScreen(now: now));
      await tapKey(tester, 'stock-add');
      await typeIn(tester, 'item-name', 'oni');
      await tapKey(tester, 'item-suggest-onion');
      await typeIn(tester, 'item-opening', '12');
      await typeIn(tester, 'item-alert', '3');
      await tapKey(tester, 'item-save');
      expect(find.text('Onion added to your stock'), findsOneWidget);
      final onion = api.items.values.firstWhere((i) => i.name == 'Onion');
      expect(onion.catalogCode, 'onion');
      expect(onion.alertMilli, 3000);

      await tapKey(tester, 'stock-add');
      await typeIn(tester, 'item-name', 'sugar');
      await tapKey(tester, 'item-save');
      expect(find.text('sugar is already in your stock'), findsOneWidget);
    });

    testWidgets('offline: entry kept on the phone, then synced', (tester) async {
      final api = FakeStockApi();
      final rice = api.seed('Rice', StockUnit.kg, qty: 10000);
      final store = MemoryStockStore();
      final services = fakeServices(stock: api, stockStore: store);
      await services.stock.freshBook();
      api.offline = true;
      await pumpScreen(tester, services, ItemScreen(item: rice, now: now));
      await tapKey(tester, 'item-in');
      await typeIn(tester, 'move-qty', '5');
      await tapKey(tester, 'move-save');
      expect(find.textContaining('Saved on the phone'), findsOneWidget);
      expect(textOf(tester, 'item-qty'), '15 kg');
      expect(find.text('⏳ Waiting for internet to sync'), findsOneWidget);

      api.offline = false;
      await pumpScreen(tester, services, StockScreen(now: now));
      expect(find.text('1 offline entry is now saved'), findsOneWidget);
      expect(store.pending, isEmpty);
    });
  });
}
