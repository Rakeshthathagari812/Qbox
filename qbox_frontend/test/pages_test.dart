import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qbox_app/calculator/voice_services.dart';
import 'package:qbox_app/customer/checklist_notes_screen.dart';
import 'package:qbox_app/customer/page_models.dart';
import 'package:qbox_app/customer/pages_repository.dart';
import 'package:qbox_app/services/api_client.dart';
import 'package:qbox_app/services/app_services.dart';

import 'fake_auth_api.dart';
import 'udhaar_screen_test.dart' show pumpScreen, tapKey, type;

final now = DateTime(2026, 11, 24, 15);

PageItem item(String text, {String qty = '', bool done = false}) =>
    PageItem(ref: 'item-${text.toLowerCase()}', text: text, qty: qty, done: done);

QboxPage list(String ref, String title, List<PageItem> items, {bool pinned = false}) =>
    QboxPage(ref: ref, isList: true, title: title, items: items, pinned: pinned, updatedAt: now);

QboxPage note(String ref, String text, {String title = ''}) =>
    QboxPage(ref: ref, isList: false, title: title, text: text, updatedAt: now);

List<String> read(String words) => [for (final i in readItems(words)) i.qty.isEmpty ? i.text : '${i.text} | ${i.qty}'];

void main() {
  group('reading items', () {
    test('quantity before or after, or none', () {
      expect(read('rice 2 kg'), ['Rice | 2 kg']);
      expect(read('2kg rice'), ['Rice | 2 kg']);
      expect(read('half kg of sugar'), ['Sugar | half kg']);
      expect(read('milk - 1.5 litres'), ['Milk | 1.5 litres']);
      expect(read('Rice, 2 kg'), ['Rice | 2 kg']);
      expect(read('eggs 1 dozen'), ['Eggs | 1 dozen']);
      expect(read('బియ్యం 2 kg'), ['బియ్యం | 2 kg']);
      expect(read('ఉల్లిపాయలు'), ['ఉల్లిపాయలు']);
    });

    test('names with numbers, "and", or words like units stay whole', () {
      expect(read('7 up'), ['7 up']);
      expect(read('bread and butter'), ['Bread and butter']);
      expect(read('garam masala'), ['Garam masala']);
      expect(read('2 kg'), ['2 kg']);
      expect(read('ginger'), ['Ginger']);
      expect(read('5 glasses'), ['5 glasses']);
    });

    test('many at once, and a list pasted from WhatsApp', () {
      expect(read('milk, rice 2 kg, , onions'), ['Milk', 'Rice | 2 kg', 'Onions']);
      expect(read('*Groceries*\n• Rice - 2 kg\n✓ Milk\n3. Dal\n\n- Salt'), ['Rice | 2 kg', 'Milk', 'Dal', 'Salt']);
      expect(read('  \n , '), isEmpty);
    });

    test('too long is cut as the server counts it', () {
      expect(readItems('అ' * 200).single.text.runes.length, maxItemChars);
      expect(cutTo('కి' * 60, 80).runes.length, 80);
    });

    test('adding one that is there: not twice; needed again if ticked', () {
      final already = <String>[];
      final items = addItems([item('Rice'), item('Milk', done: true)], readItems('rice, milk 2 l, dal'), already: already);
      expect([for (final i in items) '${i.text} ${i.qty} ${i.done}'], ['Rice  false', 'Milk 2 l false', 'Dal  false']);
      expect(already, ['Rice']);
    });

    test('the message', () {
      expect(
        shareText(list('a', 'Groceries', [item('Milk', done: true), item('Rice', qty: '2 kg')])),
        '*Groceries*\n• Rice - 2 kg\n✓ Milk',
      );
      expect(shareText(note('b', 'Call the bank', title: 'Today')), '*Today*\nCall the bank');
    });
  });

  group('two phones', () {
    final base = list('a', 'Groceries', [item('Rice'), item('Milk'), item('Dal')]);

    test('ticks, new items and removals from both are kept', () {
      final mine = base.copyWith(items: [item('Rice', done: true), item('Milk'), item('Salt')]); // Dal removed
      final theirs = base.copyWith(title: 'Home', items: [item('Milk', qty: '2 l'), item('Dal'), item('Tea')]); // Rice removed
      final joined = joinPages(base, mine, theirs);
      expect(joined.title, 'Home');
      expect([for (final i in joined.items) '${i.text}${i.qty}'], ['Milk2 l', 'Tea', 'Rice', 'Salt']);
      expect(joined.items.firstWhere((i) => i.text == 'Rice').done, isTrue); // changed here, so it stays
    });

    test('a note changed on both keeps both texts', () {
      expect(joinText('a', 'a', 'b'), 'b');
      expect(joinText('a', 'c', 'a'), 'c');
      expect(joinText('a', 'a one', 'a two'), 'a two\n\na one');
    });
  });

  group('saving', () {
    late FakePagesApi api;
    late MemoryPagesStore store;
    late PagesRepository repo;

    setUp(() {
      api = FakePagesApi();
      store = MemoryPagesStore();
      repo = PagesRepository(api, store, now: () => now);
    });

    Future<void> settle() async {
      for (var i = 0; i < 30; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    test('kept on the phone, and sent', () async {
      await repo.open();
      repo.put(list('a', 'Groceries', [item('Rice')]));
      await settle();
      expect(api.pages['a']!.version, 1);
      expect(repo.waiting, isFalse);
      final again = PagesRepository(FakePagesApi()..offline = true, store);
      await again.open();
      expect(again.pages.single.items.single.text, 'Rice');
      expect(again.offline, isTrue);
    });

    test('offline changes are sent later, also after a restart', () async {
      api.offline = true;
      await repo.open();
      repo.put(list('a', 'Groceries', [item('Rice')]));
      repo.update('a', (p) => p.copyWith(items: [...p.items, item('Dal')]));
      await settle();
      expect((repo.waiting, repo.offline), (true, true));
      api.offline = false;
      final again = PagesRepository(api, store);
      await again.open();
      expect(api.pages['a']!.items.length, 2);
      expect((again.waiting, again.offline), (false, false));
    });

    test('an answer that got lost does not undo what came after', () async {
      await repo.open();
      repo.put(list('a', 'Groceries', [item('Rice'), item('Dal')]));
      await settle();
      api.loseAnswer = true;
      repo.update('a', (p) => p.copyWith(items: [...p.items, item('Salt')]));
      await settle();
      expect((api.pages['a']!.version, repo.waiting), (2, true));
      // Restarted, then Salt is removed again: it must not come back.
      final again = PagesRepository(api, store);
      await again.open();
      again.update('a', (p) => p.copyWith(items: p.items.sublist(0, 2)));
      await settle();
      expect([for (final i in api.pages['a']!.items) i.text], ['Rice', 'Dal']);
      expect(again.waiting, isFalse);
    });

    test('a lost answer, and then Salt removed before the next try', () async {
      await repo.open();
      repo.put(list('a', 'Groceries', [item('Rice')]));
      await settle();
      api.loseAnswer = true;
      repo.update('a', (p) => p.copyWith(items: [...p.items, item('Salt')]));
      await settle();
      repo.update('a', (p) => p.copyWith(items: [item('Rice', done: true)]));
      await settle();
      expect([for (final i in api.pages['a']!.items) '${i.text} ${i.done}'], ['Rice true']);
    });

    test('changed on another phone: both are kept', () async {
      await repo.open();
      repo.put(list('a', 'Groceries', [item('Rice')]));
      await settle();
      api.keep(api.pages['a']!.copyWith(items: [item('Rice'), item('Tea')]), 2);
      repo.update('a', (p) => p.copyWith(items: [item('Rice', done: true)]));
      await settle();
      expect([for (final i in repo.pages.single.items) '${i.text} ${i.done}'], ['Rice true', 'Tea false']);
      expect(api.pages['a']!.version, 3);
      expect(repo.waiting, isFalse);
    });

    test('changes while a save is on its way go next', () async {
      await repo.open();
      api.hold = Completer<void>();
      repo.put(list('a', 'Groceries', [item('Rice')]));
      await settle();
      repo.update('a', (p) => p.copyWith(items: [...p.items, item('Dal')]));
      api.hold!.complete();
      await settle();
      expect(api.pages['a']!.items.length, 2);
      expect(repo.waiting, isFalse);
    });

    test('deleted while its first save is on its way', () async {
      await repo.open();
      api.hold = Completer<void>();
      repo.put(list('a', 'Groceries', const []));
      await settle();
      repo.remove('a');
      api.hold!.complete();
      await settle();
      expect(api.pages, isEmpty);
      expect(repo.pages, isEmpty);
      expect(repo.waiting, isFalse);
      expect(store.saved, isEmpty);
    });

    test('deleted elsewhere: gone here; but kept if it was changed here', () async {
      api.keep(note('a', 'one'), 1);
      api.keep(note('b', 'two'), 1);
      await repo.open();
      api.offline = true;
      repo.update('b', (p) => p.copyWith(text: 'two changed'));
      await settle();
      api
        ..offline = false
        ..pages.clear()
        ..deleted.addAll(['a', 'b']);
      await repo.refresh();
      expect([for (final p in repo.pages) p.text], ['two changed']);
      expect(repo.pages.single.ref, isNot('b'));
      expect(api.pages.values.single.text, 'two changed');
    });

    test('delete and undo', () async {
      api.keep(note('a', 'one'), 1);
      await repo.open();
      final page = repo.pages.single;
      repo.remove('a');
      expect(repo.pages, isEmpty);
      repo.restore(page);
      await settle();
      expect(api.deleted, {'a'});
      expect(api.pages.values.single.text, 'one');
      expect(repo.waiting, isFalse);
    });

    test('refused by the server: kept here, the others still go', () async {
      await repo.open();
      api.refuse = const ApiException('TOO_MANY_PAGES', 'You have too many lists and notes', status: 400);
      repo.put(note('a', 'one'));
      await settle();
      expect(repo.problem, 'one: You have too many lists and notes');
      expect((repo.pages.length, repo.waiting), (1, true));
      api.refuse = null;
      await repo.refresh();
      expect((repo.problem, repo.waiting), (null, false));
    });

    test('log out forgets everything, even with a save on its way', () async {
      await repo.open();
      api.hold = Completer<void>();
      repo.put(note('a', 'one'));
      await settle();
      await repo.clear();
      api.hold!.complete();
      await settle();
      expect(repo.pages, isEmpty);
      expect(store.saved, isEmpty);
      // The next user starts clean.
      api.pages.clear();
      await repo.open();
      expect(repo.pages, isEmpty);
    });

    test('damaged copies are ignored', () {
      expect(LocalPage.fromJson('x'), isNull);
      expect(QboxPage.fromJson(<String, dynamic>{'ref': 'a', 'kind': 'OTHER', 'updatedAt': '2026-11-24'}), isNull);
      expect(PageItem.fromJson(<String, dynamic>{'ref': 1}), isNull);
    });
  });

  group('screens', () {
    late FakePagesApi api;

    setUp(() => api = FakePagesApi());

    Future<void> open(WidgetTester tester, {VoiceInput? voice, FakeDeviceActions? device, PagesStore? store}) =>
        pumpScreen(
          tester,
          fakeServices(pages: api, pagesStore: store, voice: voice, device: device),
          ChecklistNotesScreen(now: now),
        );

    Future<void> enter(WidgetTester tester, String words) async {
      await tester.enterText(find.byKey(const Key('item-input')), words);
      await tapKey(tester, 'item-add');
    }

    Future<void> choose(WidgetTester tester, String menu, String choice) async {
      await tapKey(tester, menu);
      await tester.tap(find.text(choice));
      await tester.pumpAndSettle();
    }

    testWidgets('a new list: type, tick, use again', (tester) async {
      await open(tester);
      expect(find.byKey(const Key('lists-empty')), findsOneWidget);
      await tapKey(tester, 'pages-new');
      await tapKey(tester, 'list-name-save');
      expect(find.text('Enter a name, like Groceries'), findsOneWidget);
      await tapKey(tester, 'list-idea-Groceries');
      await enter(tester, 'rice 2 kg, milk');
      await type(tester, 'item-input', 'onions'); // Done on the keyboard adds too
      expect(find.text('0 of 3 done'), findsOneWidget);
      expect(find.text('2 kg'), findsOneWidget);
      await tester.tap(find.text('Milk'));
      await tester.pumpAndSettle();
      expect(find.text('1 of 3 done'), findsOneWidget);
      expect(find.text('Done (1)'), findsOneWidget);
      expect(tester.getTopLeft(find.text('Milk')).dy, greaterThan(tester.getTopLeft(find.text('Onions')).dy));
      await enter(tester, 'rice');
      expect(find.text('Rice is already here'), findsOneWidget);
      expect(api.pages.values.single.items.length, 3);
      await choose(tester, 'list-menu', 'Use again (untick all)');
      expect(find.text('0 of 3 done'), findsOneWidget);
      await tapKey(tester, 'udhaar-back');
      expect(find.text('Rice, Milk, Onions'), findsOneWidget);
    });

    testWidgets('by voice: check the words, then add', (tester) async {
      api.keep(list('a', 'Groceries', const []), 1);
      final voice = FakeVoiceInput()..nextWords = 'sugar 1 kg';
      await open(tester, voice: voice);
      await tapKey(tester, 'page-a');
      await tapKey(tester, 'pages-mic');
      expect(api.pages['a']!.items, isEmpty);
      expect(tester.widget<TextField>(find.byKey(const Key('item-input'))).controller!.text, 'sugar 1 kg');
      voice.nextWords = 'salt';
      await tapKey(tester, 'pages-mic');
      await tapKey(tester, 'item-add');
      expect([for (final i in api.pages['a']!.items) '${i.text} ${i.qty}'], ['Sugar 1 kg', 'Salt ']);
      voice.nextWords = '';
      await tapKey(tester, 'pages-mic');
      expect(find.text('Did not hear anything. Tap the mic and try again.'), findsOneWidget);
      voice.nextError = const VoiceException('The microphone is busy.');
      await tapKey(tester, 'pages-mic');
      expect(find.text('The microphone is busy.'), findsOneWidget);
    });

    testWidgets('speak in Telugu', (tester) async {
      api.keep(list('a', 'Groceries', const []), 1);
      final voice = FakeVoiceInput()..nextWords = 'బియ్యం';
      await open(tester, voice: voice);
      await tapKey(tester, 'page-a');
      await tapKey(tester, 'pages-voice-lang');
      await tapKey(tester, 'voice-lang-te');
      await tapKey(tester, 'pages-mic');
      await tapKey(tester, 'item-add');
      expect(voice.lastLocale, 'te_IN');
      expect(find.text('బియ్యం'), findsOneWidget);
    });

    testWidgets('change, remove and undo an item; remove ticked', (tester) async {
      api.keep(list('a', 'Groceries', [item('Rice'), item('Milk', done: true), item('Dal')]), 1);
      await open(tester);
      await tapKey(tester, 'page-a');
      await tapKey(tester, 'item-edit-item-rice');
      await tester.enterText(find.byKey(const Key('item-text')), '  ');
      await tapKey(tester, 'item-save');
      expect(find.text('Enter the item'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('item-text')), 'Brown rice');
      await tester.enterText(find.byKey(const Key('item-qty')), '5 kg');
      await tapKey(tester, 'item-save');
      expect(find.text('Brown rice'), findsOneWidget);
      await tapKey(tester, 'item-edit-item-rice');
      await tapKey(tester, 'item-remove');
      expect(find.text('Brown rice'), findsNothing);
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect([for (final i in api.pages['a']!.items) i.text], ['Brown rice', 'Milk', 'Dal']);
      await choose(tester, 'list-menu', 'Remove ticked items');
      expect([for (final i in api.pages['a']!.items) i.text], ['Brown rice', 'Dal']);
    });

    testWidgets('rename, pin, send on WhatsApp, delete and undo a list', (tester) async {
      api.keep(list('a', 'Groceries', [item('Rice', qty: '2 kg')]), 1);
      final device = FakeDeviceActions();
      await open(tester, device: device);
      await tapKey(tester, 'page-a');
      await choose(tester, 'list-menu', 'Rename');
      await type(tester, 'list-name', 'Home');
      await choose(tester, 'list-menu', 'Pin to top');
      await tapKey(tester, 'list-whatsapp');
      expect(device.opened.single.toString(), startsWith('whatsapp://send?text='));
      expect(device.opened.single.queryParameters['text'], '*Home*\n• Rice - 2 kg');
      expect((api.pages['a']!.title, api.pages['a']!.pinned), ('Home', true));
      await choose(tester, 'list-menu', 'Delete list');
      await tapKey(tester, 'page-delete-sure');
      expect(find.byKey(const Key('lists-empty')), findsOneWidget);
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(find.text('Home'), findsOneWidget);
      expect(api.pages.values.single.items.single.text, 'Rice');
    });

    testWidgets('a note saves by itself, by typing and by voice', (tester) async {
      final voice = FakeVoiceInput()..nextWords = 'call the bank';
      await open(tester, voice: voice);
      await tapKey(tester, 'tab-notes');
      expect(find.byKey(const Key('notes-empty')), findsOneWidget);
      await tapKey(tester, 'pages-new');
      await tester.enterText(find.byKey(const Key('note-text')), 'Gas: 12345');
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(api.pages.values.single.text, 'Gas: 12345');
      await tapKey(tester, 'pages-mic');
      await tester.enterText(find.byKey(const Key('note-title')), 'Home ');
      await tapKey(tester, 'udhaar-back');
      expect(api.pages.values.single.text, 'Gas: 12345 call the bank');
      expect(api.pages.values.single.title, 'Home');
      expect(find.text('Home'), findsOneWidget);
    });

    testWidgets('an empty new note is not kept; emptying one deletes it, with undo', (tester) async {
      api.keep(note('a', 'Gas: 12345'), 1);
      await open(tester);
      await tapKey(tester, 'tab-notes');
      await tapKey(tester, 'pages-new');
      await tapKey(tester, 'udhaar-back');
      expect(api.pages.length, 1);
      await tapKey(tester, 'page-a');
      await tester.enterText(find.byKey(const Key('note-text')), '');
      await tapKey(tester, 'udhaar-back');
      expect(api.pages, isEmpty);
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(find.text('Gas: 12345'), findsOneWidget);
    });

    testWidgets('a note changed on another phone while it is open', (tester) async {
      api.keep(note('a', 'one'), 1);
      await open(tester);
      final pages = ServicesScope.of(tester.element(find.byType(ChecklistNotesScreen))).pages;
      await tapKey(tester, 'tab-notes');
      await tapKey(tester, 'page-a');
      api.keep(note('a', 'one two'), 2);
      await pages.refresh();
      await tester.pumpAndSettle();
      final text = tester.widget<TextField>(find.byKey(const Key('note-text'))).controller!;
      expect(text.text, 'one two');
      await tester.enterText(find.byKey(const Key('note-text')), 'one two mine');
      api.keep(note('a', 'one two theirs'), 3);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(text.text, 'one two theirs\n\none two mine');
      expect(api.pages['a']!.text, text.text);
    });

    testWidgets('delete a note from its menu', (tester) async {
      api.keep(note('a', 'one'), 1);
      await open(tester);
      await tapKey(tester, 'tab-notes');
      await tapKey(tester, 'page-a');
      await choose(tester, 'note-menu', 'Delete note');
      await tapKey(tester, 'page-delete-sure');
      expect(find.byKey(const Key('notes-empty')), findsOneWidget);
      expect(find.text('Undo'), findsOneWidget);
    });

    testWidgets('a list deleted on another phone while it is open', (tester) async {
      api.keep(list('a', 'Groceries', const []), 1);
      await open(tester);
      final pages = ServicesScope.of(tester.element(find.byType(ChecklistNotesScreen))).pages;
      await tapKey(tester, 'page-a');
      api.pages.clear();
      await pages.refresh();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('list-gone')), findsOneWidget);
    });

    testWidgets('offline: works, says so, and sends on retry', (tester) async {
      api.offline = true;
      await open(tester);
      expect(find.text('Offline: showing the copy on this phone.'), findsOneWidget);
      await tapKey(tester, 'pages-new');
      await tapKey(tester, 'list-idea-Medicines');
      await enter(tester, 'cough syrup');
      expect(find.text('Offline: saved on this phone. It will be sent when there is internet.'), findsOneWidget);
      api.offline = false;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('pages-banner')), findsNothing);
      expect(api.pages.values.single.items.single.text, 'Cough syrup');
    });

    testWidgets('search looks inside lists and notes; pinned first', (tester) async {
      for (var i = 1; i <= 4; i++) {
        api.keep(list('l$i', 'List $i', [item(i == 2 ? 'Turmeric' : 'Rice')], pinned: i == 3), 1);
      }
      api.keep(note('n', 'turmeric is good'), 1);
      await open(tester);
      expect(
        tester.getTopLeft(find.byKey(const Key('page-l3'))).dy,
        lessThan(tester.getTopLeft(find.byKey(const Key('page-l1'))).dy),
      );
      await tester.enterText(find.byKey(const Key('pages-search')), 'TURM');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('page-l2')), findsOneWidget);
      expect(find.byKey(const Key('page-l1')), findsNothing);
      await tapKey(tester, 'tab-notes');
      expect(find.byKey(const Key('page-n')), findsOneWidget);
      await tester.enterText(find.byKey(const Key('pages-search')), 'zzz');
      await tester.pumpAndSettle();
      expect(find.text('Nothing found.'), findsOneWidget);
    });

    testWidgets('a full list says so', (tester) async {
      api.keep(list('a', 'Big', [for (var i = 0; i < 200; i++) item('Thing $i')]), 1);
      await open(tester);
      await tapKey(tester, 'page-a');
      await enter(tester, 'one more');
      expect(find.text('A list can have up to 200 items.'), findsOneWidget);
      expect(api.pages['a']!.items.length, 200);
    });

    testWidgets('a small phone with big text has room for everything', (tester) async {
      api.keep(list('a', 'A very long name for a list of things', [item('Something with a long name', qty: '10 packets')]), 1);
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpScreen(tester, fakeServices(pages: api), ChecklistNotesScreen(now: now));
      tester.view.physicalSize = const Size(960, 1600);
      await tester.pumpAndSettle();
      await tapKey(tester, 'page-a');
      expect(tester.takeException(), isNull);
      await tapKey(tester, 'udhaar-back');
      await tapKey(tester, 'tab-notes');
      await tapKey(tester, 'pages-new');
      expect(tester.takeException(), isNull);
    });
  });
}
