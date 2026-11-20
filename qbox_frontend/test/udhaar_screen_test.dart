import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qbox_app/services/app_services.dart';
import 'package:qbox_app/services/device_actions.dart';
import 'package:qbox_app/udhaar/my_udhaar_screen.dart';
import 'package:qbox_app/udhaar/udhaar_models.dart';
import 'package:qbox_app/udhaar/udhaar_screen.dart';
import 'package:qbox_app/udhaar/udhaar_store.dart';

import 'fake_auth_api.dart';

final now = DateTime(2026, 11, 19, 15);

UdhaarEntry credit(int rupeesAmount, DateTime at, {int id = 100, String ref = 'seed-1'}) => UdhaarEntry(
  id: id,
  kind: EntryKind.credit,
  amountPaise: rupeesAmount * 100,
  entryAt: at,
  clientRef: ref,
);

Future<void> pumpScreen(WidgetTester tester, AppServices services, Widget screen) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ServicesScope(services: services, child: MaterialApp(home: screen)),
  );
  await tester.pumpAndSettle();
}

Future<void> openBook(WidgetTester tester, AppServices services) =>
    pumpScreen(tester, services, UdhaarScreen(now: now));

Future<void> tapKey(WidgetTester tester, String key) async {
  final finder = find.byKey(Key(key));
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> type(WidgetTester tester, String key, String text) async {
  await tester.enterText(find.byKey(Key(key)), text);
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pumpAndSettle();
}

String balanceText(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('customer-balance'))).data!;

void main() {
  testWidgets('book: total, customers by amount, overdue filter, search', (tester) async {
    final api = FakeUdhaarApi();
    final ramesh = api.seed('Ramesh', '9876543210', history: [credit(500, DateTime(2026, 9, 1))]);
    api.seed('Suresh', '9123456780', history: [credit(200, now, ref: 'seed-2')]);
    await openBook(tester, fakeServices(udhaar: api));

    expect(tester.widget<Text>(find.byKey(const Key('udhaar-total'))).data, '₹700');
    expect(find.text('with 2 customers'), findsOneWidget);
    expect(find.text('No payment 79 days'), findsOneWidget);

    await tapKey(tester, 'udhaar-overdue-chip');
    expect(find.byKey(Key('udhaar-customer-${ramesh.id}')), findsOneWidget);
    expect(find.text('Suresh'), findsNothing);
    await tapKey(tester, 'udhaar-show-all');

    await type(tester, 'udhaar-search', 'sur');
    expect(find.text('Suresh'), findsOneWidget);
    expect(find.text('Ramesh'), findsNothing);
    await type(tester, 'udhaar-search', '98765');
    expect(find.text('Ramesh'), findsOneWidget);
  });

  testWidgets('add customer: contact picker, SMS code, then their page', (tester) async {
    final api = FakeUdhaarApi();
    final device = FakeDeviceActions()
      ..nextContact = const PickedContact(name: 'Kiran Kumar', phone: '+91 98765-43210');
    await openBook(tester, fakeServices(udhaar: api, device: device));
    expect(find.byKey(const Key('udhaar-empty')), findsOneWidget);

    await tapKey(tester, 'udhaar-add-customer');
    await tapKey(tester, 'add-pick-contact');
    expect(find.text('Kiran Kumar'), findsOneWidget);
    expect(find.text('9876543210'), findsOneWidget);

    await tapKey(tester, 'add-send-code');
    expect(api.invitesSentTo, ['9876543210']);
    expect(find.text('Test mode code: 123456'), findsOneWidget);

    await type(tester, 'add-otp', '000000');
    await tapKey(tester, 'add-confirm');
    expect(find.text('Wrong OTP. Please check and try again'), findsOneWidget);

    await type(tester, 'add-otp', '123456');
    await tapKey(tester, 'add-confirm');
    // Now on the new customer's page.
    expect(find.byKey(const Key('customer-empty')), findsOneWidget);
    expect(find.text('Kiran Kumar'), findsWidgets);
    expect(api.customers.values.single.mobile, '9876543210');
  });

  testWidgets('add customer: checks name and number first', (tester) async {
    final api = FakeUdhaarApi();
    await openBook(tester, fakeServices(udhaar: api));
    await tapKey(tester, 'udhaar-add-customer');
    await tapKey(tester, 'add-send-code');
    expect(find.text('Enter customer name'), findsOneWidget);
    await type(tester, 'add-name', 'Ravi');
    await type(tester, 'add-mobile', '12345');
    await tapKey(tester, 'add-send-code');
    expect(find.text('Enter a 10-digit mobile number'), findsOneWidget);
    expect(api.invitesSentTo, isEmpty);
  });

  testWidgets('customer page: udhaar then payment, balance updates', (tester) async {
    final api = FakeUdhaarApi();
    final c = api.seed('Ramesh', '9876543210');
    await openBook(tester, fakeServices(udhaar: api));
    await tapKey(tester, 'udhaar-customer-${c.id}');
    expect(balanceText(tester), '₹0');

    await tapKey(tester, 'customer-credit');
    await type(tester, 'entry-amount', '250');
    expect(find.text('New balance: ₹250 due'), findsOneWidget);
    await type(tester, 'entry-note', 'rice 5 kg');
    await tapKey(tester, 'entry-save');
    expect(balanceText(tester), '₹250');
    expect(find.text('rice 5 kg'), findsOneWidget);

    await tapKey(tester, 'customer-payment');
    await type(tester, 'entry-amount', '100');
    await tapKey(tester, 'entry-save');
    expect(balanceText(tester), '₹150');
    expect(api.entries[c.id]!.map((e) => e.kind), [EntryKind.credit, EntryKind.payment]);
  });

  testWidgets('an empty amount is not saved', (tester) async {
    final api = FakeUdhaarApi();
    final c = api.seed('Ramesh', '9876543210');
    await openBook(tester, fakeServices(udhaar: api));
    await tapKey(tester, 'udhaar-customer-${c.id}');
    await tapKey(tester, 'customer-credit');
    await tapKey(tester, 'entry-save');
    expect(find.text('Enter the amount'), findsOneWidget);
    expect(api.entries[c.id], isEmpty);
  });

  testWidgets('crossing the credit limit asks first', (tester) async {
    final api = FakeUdhaarApi();
    final c = api.seed('Ramesh', '9876543210', limitPaise: 20000);
    await openBook(tester, fakeServices(udhaar: api));
    await tapKey(tester, 'udhaar-customer-${c.id}');
    expect(find.text('Limit ₹200 · ₹200 left'), findsOneWidget);

    await tapKey(tester, 'customer-credit');
    await type(tester, 'entry-amount', '300');
    await tapKey(tester, 'entry-save');
    expect(find.text('Credit limit crossed'), findsOneWidget);
    await tapKey(tester, 'limit-save-anyway');
    expect(balanceText(tester), '₹300');
    expect(find.text('Over the ₹200 limit by ₹100'), findsOneWidget);
  });

  testWidgets('offline: saved on the phone, synced later, never doubled', (tester) async {
    final api = FakeUdhaarApi();
    final c = api.seed('Ramesh', '9876543210');
    final store = MemoryUdhaarStore();
    await openBook(tester, fakeServices(udhaar: api, udhaarStore: store));

    api.offline = true;
    await tapKey(tester, 'udhaar-customer-${c.id}');
    expect(find.byKey(const Key('customer-offline')), findsOneWidget);
    await tapKey(tester, 'customer-credit');
    await type(tester, 'entry-amount', '120');
    await tapKey(tester, 'entry-save');
    expect(find.textContaining('Saved on the phone'), findsOneWidget);
    expect(find.text('⏳ Waiting for internet to sync'), findsOneWidget);
    expect(balanceText(tester), '₹120');

    await tapKey(tester, 'udhaar-back');
    expect(find.text('1 entry waiting to sync'), findsOneWidget);
    expect(find.byKey(const Key('udhaar-offline')), findsOneWidget);

    api.offline = false;
    await tapKey(tester, 'udhaar-waiting');
    final syncNow = find.text('Sync now');
    await tester.tap(syncNow);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('udhaar-waiting')), findsNothing);
    expect(api.entries[c.id]!.single.amountPaise, 12000);
    expect(store.pending, isEmpty);
    expect(tester.widget<Text>(find.byKey(const Key('udhaar-total'))).data, '₹120');
  });

  testWidgets('delete an entry: kept crossed out with the reason', (tester) async {
    final api = FakeUdhaarApi();
    final c = api.seed('Ramesh', '9876543210', history: [credit(500, now)]);
    await openBook(tester, fakeServices(udhaar: api));
    await tapKey(tester, 'udhaar-customer-${c.id}');
    expect(balanceText(tester), '₹500');

    await tapKey(tester, 'entry-seed-1');
    expect(find.text('Delete this entry?'), findsOneWidget);
    await tester.tap(find.text('Wrong amount'));
    await tester.pumpAndSettle();
    await tapKey(tester, 'delete-confirm');
    expect(find.text('Deleted: Wrong amount'), findsOneWidget);
    expect(balanceText(tester), '₹0');
    expect(api.entries[c.id]!.single.deleted, isTrue);
  });

  testWidgets('WhatsApp reminder opens a chat with the balance typed in', (tester) async {
    final api = FakeUdhaarApi();
    final device = FakeDeviceActions();
    final c = api.seed('Ramesh', '9876543210', history: [credit(500, now)]);
    await openBook(tester, fakeServices(udhaar: api, device: device));
    await tapKey(tester, 'udhaar-customer-${c.id}');

    await tapKey(tester, 'customer-whatsapp');
    // Straight into the WhatsApp app (no web lookup).
    final link = device.opened.single;
    expect(link.scheme, 'whatsapp');
    expect(link.queryParameters['phone'], '919876543210');
    expect(link.queryParameters['text'], contains('Ramesh'));
    expect(link.queryParameters['text'], contains('₹500'));

    // If the app link cannot open, the web link is used instead.
    device
      ..opened.clear()
      ..failScheme = 'whatsapp';
    await tapKey(tester, 'customer-whatsapp');
    expect(device.opened.map((u) => u.scheme), ['whatsapp', 'https']);
    expect(device.opened.last.host, 'wa.me');
    device.failScheme = null;

    await tapKey(tester, 'customer-call');
    expect(device.opened.last.toString(), 'tel:+919876543210');
  });

  testWidgets('voice: "Ramesh 250 udhaar" fills the form to check, then saves', (tester) async {
    final api = FakeUdhaarApi();
    final c = api.seed('Ramesh', '9876543210');
    final voice = FakeVoiceInput()..nextWords = 'Ramesh 250 udhaar';
    await openBook(tester, fakeServices(udhaar: api, voice: voice));

    await tapKey(tester, 'udhaar-speak');
    expect(find.byKey(const Key('entry-voice-note')), findsOneWidget);
    expect(find.text('250'), findsOneWidget);
    expect(find.text('Udhaar given'), findsWidgets);
    await tapKey(tester, 'entry-save');
    expect(api.entries[c.id]!.single.amountPaise, 25000);
    expect(tester.widget<Text>(find.byKey(const Key('udhaar-total'))).data, '₹250');
  });

  testWidgets('voice: two customers with that name -> asks which one', (tester) async {
    final api = FakeUdhaarApi();
    api.seed('Ramesh Kumar', '9000000001');
    final rao = api.seed('Ramesh Rao', '9000000002');
    final voice = FakeVoiceInput()..nextWords = 'Ramesh paid 100';
    await openBook(tester, fakeServices(udhaar: api, voice: voice));

    await tapKey(tester, 'udhaar-speak');
    expect(find.text('Which customer?'), findsOneWidget);
    await tapKey(tester, 'voice-pick-${rao.id}');
    expect(find.text('Payment received'), findsOneWidget);
    await tapKey(tester, 'entry-save');
    expect(api.entries[rao.id]!.single.kind, EntryKind.payment);
  });

  testWidgets('voice: unknown name -> offers to add them', (tester) async {
    final voice = FakeVoiceInput()..nextWords = 'Mahesh 400 udhaar';
    await openBook(tester, fakeServices(voice: voice));
    await tapKey(tester, 'udhaar-speak');
    expect(find.textContaining('"Mahesh" is not in your udhaar book'), findsOneWidget);
    await tapKey(tester, 'voice-add-new');
    expect(find.text('Add customer'), findsWidgets);
    expect(find.text('Mahesh'), findsOneWidget); // name already filled in
  });

  testWidgets('My Udhaar: the customer sees each shop and their history', (tester) async {
    final api = FakeUdhaarApi();
    api.books.addAll(const [
      MyBook(bookId: 1, shopName: 'Sri Balaji Stores', shopPhone: '9876500000', balancePaise: 35000),
      MyBook(bookId: 2, shopName: 'Lakshmi Kirana', balancePaise: 12000),
    ]);
    api.bookEntries[1] = [credit(350, now)];
    final device = FakeDeviceActions();
    await pumpScreen(tester, fakeServices(udhaar: api, device: device), MyUdhaarScreen(now: now));

    expect(tester.widget<Text>(find.byKey(const Key('myudhaar-total'))).data, '₹470');
    expect(find.text('at 2 shops'), findsOneWidget);

    await tapKey(tester, 'mybook-1');
    expect(find.text('You took udhaar'), findsOneWidget);
    await tapKey(tester, 'mybook-call');
    expect(device.opened.single.toString(), 'tel:+919876500000');
  });

  testWidgets('"Not me" only sends a report: nothing hidden, can be taken back', (tester) async {
    final api = FakeUdhaarApi();
    api.books.add(MyBook(
      bookId: 1,
      shopName: 'Sri Balaji Stores',
      balancePaise: 35000,
      verifiedAt: DateTime(2026, 11, 19, 10),
    ));
    api.bookEntries[1] = [credit(350, now)];
    await pumpScreen(tester, fakeServices(udhaar: api), MyUdhaarScreen(now: now));
    await tapKey(tester, 'mybook-1');

    await tapKey(tester, 'mybook-not-me');
    // Reminded that the number was checked with a code at the shop.
    expect(find.textContaining('checked with a code at Sri Balaji Stores on Thu, 19 November 2026'),
        findsOneWidget);
    await tapKey(tester, 'not-me-confirm');

    expect(api.books.single.dispute, Dispute.reported);
    expect(find.byKey(const Key('mybook-reported')), findsOneWidget);
    expect(find.text('You took udhaar'), findsOneWidget); // still visible
    expect(find.byKey(const Key('mybook-not-me')), findsNothing);

    await tester.tap(find.text('Take back'));
    await tester.pumpAndSettle();
    expect(api.books.single.dispute, Dispute.none);
    expect(find.byKey(const Key('mybook-not-me')), findsOneWidget);

    // Back on the list the shop is still there.
    await tapKey(tester, 'udhaar-back');
    expect(find.text('Sri Balaji Stores'), findsOneWidget);
  });

  testWidgets('after the shop confirms, the customer sees it and cannot report again', (tester) async {
    final api = FakeUdhaarApi();
    api.books.add(const MyBook(
      bookId: 1,
      shopName: 'Sri Balaji Stores',
      balancePaise: 35000,
      dispute: Dispute.confirmed,
    ));
    await pumpScreen(tester, fakeServices(udhaar: api), MyUdhaarScreen(now: now));
    await tapKey(tester, 'mybook-1');
    expect(find.byKey(const Key('mybook-confirmed')), findsOneWidget);
    expect(find.byKey(const Key('mybook-not-me')), findsNothing);
  });

  testWidgets('shop: sees the report and confirms the number', (tester) async {
    final api = FakeUdhaarApi();
    final c = api.seed('Ramesh', '9876543210', history: [credit(500, now)]);
    api.report(c.id);
    await openBook(tester, fakeServices(udhaar: api));

    expect(find.text('1 customer says this is not their number. Please check.'), findsOneWidget);
    expect(find.text('Says not their number'), findsOneWidget);

    await tapKey(tester, 'udhaar-customer-${c.id}');
    expect(find.byKey(const Key('customer-dispute')), findsOneWidget);
    await tapKey(tester, 'dispute-confirm');
    await tapKey(tester, 'dispute-sure');
    expect(api.customers[c.id]!.dispute, Dispute.confirmed);
    expect(find.byKey(const Key('customer-dispute')), findsNothing);
    expect(balanceText(tester), '₹500'); // balance never changes

    await tapKey(tester, 'udhaar-back');
    expect(find.byKey(const Key('udhaar-disputes')), findsNothing);
  });

  testWidgets('shop: wrong number -> unlink, then move the history to the right number', (tester) async {
    final api = FakeUdhaarApi();
    final c = api.seed('Ramesh', '9876543210', history: [credit(500, now)]);
    api.report(c.id);
    await openBook(tester, fakeServices(udhaar: api));
    await tapKey(tester, 'udhaar-customer-${c.id}');

    await tapKey(tester, 'dispute-unlink');
    await tapKey(tester, 'dispute-sure');
    expect(api.customers[c.id]!.dispute, Dispute.unlinked);
    expect(find.byKey(const Key('customer-unlinked')), findsOneWidget);

    await tester.tap(find.text('Right number'));
    await tester.pumpAndSettle();
    expect(find.text('Old number: +91 9876543210'), findsOneWidget);
    await type(tester, 'add-mobile', '9123456780');
    await tapKey(tester, 'add-send-code');
    expect(api.invitesSentTo, ['9123456780']);
    await type(tester, 'add-otp', '123456');
    await tapKey(tester, 'add-confirm');

    expect(api.customers[c.id]!.mobile, '9123456780');
    expect(api.customers[c.id]!.dispute, Dispute.none);
    expect(find.byKey(const Key('customer-unlinked')), findsNothing);
    expect(balanceText(tester), '₹500'); // same history, new number
  });

  test('log out forgets the udhaar book and unsent entries', () async {
    final store = MemoryUdhaarStore()
      ..book = const UdhaarBook([UdhaarCustomer(id: 1, name: 'R', mobile: '9000000001')])
      ..pending = [
        PendingEntry(
          customerId: 1,
          draft: EntryDraft(kind: EntryKind.credit, amountPaise: 100, entryAt: now),
        ),
      ];
    await fakeServices(udhaarStore: store).forgetUserData();
    expect(store.book, isNull);
    expect(store.pending, isEmpty);
  });
}
