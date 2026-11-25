import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qbox_app/ask/ask_brain.dart';
import 'package:qbox_app/ask/ask_screen.dart';
import 'package:qbox_app/ask/ask_words.dart';
import 'package:qbox_app/calculator/voice_services.dart';
import 'package:qbox_app/calendar/calendar_models.dart';
import 'package:qbox_app/customer/page_models.dart';
import 'package:qbox_app/customer/transaction_models.dart';
import 'package:qbox_app/onboarding_draft.dart';
import 'package:qbox_app/services/app_services.dart';
import 'package:qbox_app/services/settings_store.dart';
import 'package:qbox_app/stock/stock_models.dart';
import 'package:qbox_app/stock/stock_store.dart';
import 'package:qbox_app/suppliers/supplier_models.dart';
import 'package:qbox_app/supply/supply_models.dart';
import 'package:qbox_app/translator/languages.dart';
import 'package:qbox_app/translator/voice_language.dart';
import 'package:qbox_app/udhaar/customer_screen.dart';
import 'package:qbox_app/udhaar/entry_form_screen.dart';
import 'package:qbox_app/udhaar/udhaar_models.dart';

import 'fake_auth_api.dart';
import 'udhaar_screen_test.dart' show pumpScreen, tapKey;

final now = DateTime(2026, 11, 25, 10);

Finder at(String key) => find.byKey(Key(key));

String textOf(WidgetTester tester, String key) => tester.widget<Text>(at(key)).data!;

UdhaarEntry line(int rupees, {EntryKind kind = EntryKind.credit, DateTime? on, String ref = 'a'}) => UdhaarEntry(
  id: ref.hashCode,
  kind: kind,
  amountPaise: rupees * 100,
  entryAt: on ?? DateTime(2026, 11, 20),
  clientRef: ref,
);

void main() {
  late FakeUdhaarApi udhaar;
  late FakeStockApi stock;
  late FakeSupplierApi suppliers;
  late FakePaymentsApi payments;
  late FakeTransactionsApi transactions;
  late FakeCalendarApi calendar;
  late FakeSupplyApi supply;
  late FakeTranslator translator;
  late MemoryStockStore stockStore;

  setUp(() {
    udhaar = FakeUdhaarApi();
    stock = FakeStockApi();
    suppliers = FakeSupplierApi(stock: stock);
    payments = FakePaymentsApi();
    transactions = FakeTransactionsApi();
    calendar = FakeCalendarApi();
    supply = FakeSupplyApi();
    translator = FakeTranslator();
    stockStore = MemoryStockStore();
  });

  AppServices services({FakeVoiceInput? voice, FakeSpeaker? speaker, SettingsStore? settings}) => fakeServices(
    udhaar: udhaar,
    stock: stock,
    stockStore: stockStore,
    suppliers: suppliers,
    payments: payments,
    transactions: transactions,
    calendar: calendar,
    supply: supply,
    translator: translator,
    voice: voice,
    speaker: speaker,
    settings: settings,
  );

  Future<AskAnswer> ask(
    QboxRole role,
    String words, {
    AppLanguage language = AppLanguage.english,
    String? english,
  }) => AskBrain(services(), role, now: now).ask(words, language, english: () async => english);

  Future<String> shop(String words, {AppLanguage language = AppLanguage.english, String? english}) async =>
      (await ask(QboxRole.business, words, language: language, english: english)).text;

  group('words', () {
    test('every answer is written in all five languages, with the same blanks', () {
      for (final MapEntry(key: key, value: texts) in allAnswers) {
        expect(texts, hasLength(5), reason: key);
        Set<String> blanks(String t) => {for (final m in RegExp(r'\{[abc]\}').allMatches(t)) m[0]!};
        for (final t in texts) {
          expect(t.trim(), isNotEmpty, reason: key);
          expect(blanks(t), blanks(texts.first), reason: '$key: $t');
        }
      }
    });

    test('every example is understood, in every language, without translating', () async {
      for (final role in QboxRole.values) {
        for (final language in AppLanguage.values) {
          final examples = askExamples(role, language);
          expect(examples, hasLength(5));
          for (final e in examples) {
            final answer = await AskBrain(services(), role, now: now).ask(
              e,
              language,
              english: () async => fail('translated: $e'),
            );
            expect(answer.understood, isTrue, reason: '$role $language: $e');
          }
        }
      }
    });

    // Other ways of asking (empty records, so the answer shows what was understood).
    test('asked in other words', () async {
      const e = AppLanguage.english, t = AppLanguage.telugu, h = AppLanguage.hindi;
      const k = AppLanguage.kannada, m = AppLanguage.tamil;
      const b = QboxRole.business, c = QboxRole.customer, s = QboxRole.supplier;
      for (final (role, lang, want, questions) in <(QboxRole, AppLanguage, String, List<String>)>[
        (b, e, 'owedNone', ['who has to give me more money', 'who has not paid', 'show pending udhaar', 'tell me the customers with pending amount', 'whose balance is highest']),
        (b, e, 'lowNone', ['which items are finishing', 'what should I buy', 'out of stock items', 'is any item short', 'things to reorder']),
        (b, e, 'paidToday', ["today's collection", 'how much did I earn today', 'sales today', 'how much cash did we get today', 'did anyone pay today']),
        (b, e, 'oweSuppliers', ['supplier dues', 'how much should I pay to suppliers', 'what is the amount I have to give suppliers']),
        (b, e, 'lateNone', ['who is not paying for long time']),
        (b, e, 'ordersNone', ['have my orders arrived']),
        (b, e, 'tomorrowNone', ['what meetings are there tomorrow']),
        (b, t, 'owedNone', ['ఎవరు నాకు డబ్బులు ఇవ్వాలి', 'నాకు ఎంత రావాలి', 'ఎక్కువ బాకీ ఉన్న కస్టమర్ ఎవరు']),
        (b, t, 'lowNone', ['ఏ సరుకు అయిపోయింది', 'ఏం కొనాలి']),
        (b, t, 'paidToday', ['ఈరోజు ఎంత వసూలు అయింది', 'ఈ రోజు అమ్మకాలు ఎంత', 'ఈరోజు ఎంత సంపాదించాను']),
        (b, t, 'oweSuppliers', ['సప్లయర్ బాకీ ఎంత', 'సప్లయర్లకు ఎంత చెల్లించాలి']),
        (b, t, 'tomorrowNone', ['రేపు ఏ పండుగ']),
        (b, h, 'owedNone', ['किसने पैसे नहीं दिए', 'मुझे कितना लेना है', 'उधार किस किस का है']),
        (b, h, 'lowNone', ['कौन सा माल खत्म हो गया', 'क्या खरीदना है']),
        (b, h, 'paidToday', ['आज की कमाई कितनी है', 'आज कितनी बिक्री हुई']),
        (b, h, 'oweSuppliers', ['सप्लायर का बाकी', 'थोक वाले को कितना देना है']),
        (b, k, 'owedNone', ['ಯಾರು ಹಣ ಕೊಡಬೇಕು', 'ಯಾರು ಸಾಲ ತೀರಿಸಿಲ್ಲ']),
        (b, k, 'lowNone', ['ಯಾವ ವಸ್ತು ಖಾಲಿಯಾಗಿದೆ']),
        (b, k, 'paidToday', ['ಇಂದಿನ ವಸೂಲಿ ಎಷ್ಟು', 'ಇಂದು ಎಷ್ಟು ಮಾರಾಟ ಆಯಿತು']),
        (b, m, 'owedNone', ['யார் பணம் தர வேண்டும்', 'யார் கடன் கட்டவில்லை']),
        (b, m, 'lowNone', ['எந்த பொருள் தீர்ந்து விட்டது']),
        (b, m, 'paidToday', ['இன்றைய வசூல் எவ்வளவு', 'இன்று விற்பனை எவ்வளவு']),
        (c, e, 'youOweNone', ['where do I have to pay', 'am I in debt anywhere']),
        (c, e, 'spent', ['my expenses', 'how much money did I waste this month']),
        (c, e, 'lastPaidNone', ['what did I pay this month', 'show what I paid']),
        (c, e, 'todayNone', ['any meeting today']),
        (c, e, 'tomorrowNone', ['is there a holiday tomorrow']),
        (c, e, 'listsNone', ['what to buy from list', 'show my shopping list']),
        (c, t, 'youOweNone', ['నేను ఎవరికి ఎంత ఇవ్వాలి', 'నేను ఎంత అప్పు ఉన్నాను']),
        (c, t, 'spent', ['ఈ నెల ఖర్చు ఎంత', 'డబ్బులు ఎంత ఖర్చయ్యాయి']),
        (c, t, 'lastPaidNone', ['నేను చెల్లించిన డబ్బులు']),
        (c, t, 'todayNone', ['ఈరోజు ఏమైనా రిమైండర్లు ఉన్నాయా']),
        (c, h, 'youOweNone', ['मुझे किसको कितना देना है', 'मेरी उधारी कितनी है']),
        (c, h, 'spent', ['मेरा खर्च बताओ', 'मैंने कितने पैसे खर्च किए']),
        (c, h, 'todayNone', ['आज कोई रिमाइंडर है क्या']),
        (c, k, 'youOweNone', ['ನಾನು ಎಷ್ಟು ಸಾಲ ಕೊಡಬೇಕು']),
        (c, k, 'spent', ['ಈ ತಿಂಗಳ ಖರ್ಚು ಎಷ್ಟು']),
        (c, m, 'youOweNone', ['நான் எவ்வளவு கடன் தர வேண்டும்']),
        (c, m, 'spent', ['என் செலவு எவ்வளவு', 'இந்த மாத செலவு என்ன']),
        (s, e, 'toGet', ['which shop has to give money', 'who needs to pay me']),
        (s, e, 'ordersNone', ['orders to send', 'what orders came today']),
        (s, e, 'received', ['how much did I receive']),
        (s, e, 'lowNone', ['what stock is finished', 'which product is out of stock']),
        (s, e, 'given', ['how is my business this month']),
        (s, e, 'requestsNone', ['does any shop want to connect']),
        (s, t, 'toGet', ['ఏ షాపు డబ్బులు ఇవ్వాలి', 'షాపుల నుండి ఎంత రావాలి']),
        (s, t, 'ordersNone', ['ఆర్డర్లు వచ్చాయా', 'కొత్త ఆర్డర్ ఏమైనా వచ్చిందా']),
        (s, t, 'received', ['ఎంత డబ్బు వచ్చింది']),
        (s, h, 'toGet', ['किस दुकान से पैसे लेने हैं', 'दुकानों पर कितना उधार है']),
        (s, h, 'ordersNone', ['कोई ऑर्डर आया क्या']),
        (s, h, 'received', ['कितना पैसा मिला']),
        (s, k, 'toGet', ['ಅಂಗಡಿಯವರು ಎಷ್ಟು ಕೊಡಬೇಕು']),
        (s, k, 'ordersNone', ['ಆರ್ಡರ್ ಬಂದಿದೆಯಾ']),
        (s, m, 'toGet', ['எந்த கடை பணம் தர வேண்டும்']),
        (s, m, 'ordersNone', ['ஆர்டர் வந்ததா']),
        (s, m, 'received', ['எவ்வளவு பணம் வந்தது']),
      ]) {
        for (final q in questions) {
          expect((await ask(role, q, language: lang)).text, askSays(want, lang, a: '₹0', b: '₹0'), reason: q);
        }
      }
    });

    test('every example gets its own answer, in every language', () async {
      const zero = '₹0';
      for (final l in AppLanguage.values) {
        Future<List<String>> answers(QboxRole role) async => [
          for (final e in askExamples(role, l)) (await ask(role, e, language: l)).text,
        ];
        expect(await answers(QboxRole.business), [
          askSays('owedNone', l),
          askSays('lowNone', l),
          askSays('paidToday', l, a: zero),
          askSays('oweSuppliers', l, a: zero),
          askSays('owedNone', l),
        ], reason: l.englishName);
        expect(await answers(QboxRole.customer), [
          askSays('youOweNone', l),
          askSays('spent', l, a: zero),
          askSays('spent', l, a: zero), // no budget set
          askSays('tomorrowNone', l),
          askSays('listsNone', l),
        ], reason: l.englishName);
        expect(await answers(QboxRole.supplier), [
          askSays('ordersNone', l),
          askSays('toGet', l, a: zero),
          askSays('lowNone', l),
          l == AppLanguage.english ? askSays('confirmNone', l) : askSays('received', l, a: zero),
          askSays('given', l, a: zero),
        ], reason: l.englishName);
      }
    });
  });

  group('shop', () {
    setUp(() {
      udhaar.seed('Ramesh Kumar', '9876543210', history: [line(500, on: DateTime(2026, 8, 1))]);
      udhaar.seed('Suresh', '9123456780', history: [line(1200, ref: 'b')]);
      udhaar.seed('Teja', '9000000001');
      stock.seed('Rice', StockUnit.kg, qty: 30000, alert: 10000, cost: 5000, code: 'rice');
      stock.seed('Sugar', StockUnit.kg, qty: 2000, alert: 5000, code: 'sugar');
    });

    test('who owes', () async {
      final most = await ask(QboxRole.business, 'Who owes me the most?');
      expect(most.text, 'Suresh owes the most: ₹1,200.');
      expect([for (final r in most.rows) (r.title, r.amount)], [('Suresh', '₹1,200'), ('Ramesh Kumar', '₹500')]);
      expect(await shop('total udhaar'), 'Customers owe you ₹1,700 in all. Customers: 2.');
      expect(await shop('how much does ramesh owe'), 'Ramesh Kumar owes you ₹500.');
      expect(await shop('Teja balance'), 'Teja owes you nothing.');
      expect(await shop('who is late'), 'Customers who are late: 1.');
      expect(await shop('తేజ బాకీ ఎంత', language: AppLanguage.telugu), 'Teja మీకు బాకీ లేదు.');
      expect(await shop('रमेश का कितना बाकी है', language: AppLanguage.hindi), 'Ramesh Kumar से ₹500 मिलने हैं.');
    });

    test('stock', () async {
      expect(await shop('what is running low'), 'Running low: 1.');
      expect(await shop('how much rice do I have'), 'You have 30 kg of Rice.');
      expect(await shop('బియ్యం ఎంత ఉంది', language: AppLanguage.telugu), 'Rice: 30 kg ఉంది.');
      expect(await shop('what is my stock worth'), 'Your stock is worth ₹1,500.');
      expect(await shop('how many items in stock'), 'Items in stock: 2. Running low: 1.');
    });

    test('payments and suppliers', () async {
      final ravi = suppliers.seed('Ravi Traders', mobile: '9848022338');
      suppliers.seed('Sri Oils');
      await suppliers.addEntry(
        ravi.id,
        SupplierEntryDraft(kind: SupplierEntryKind.purchase, amountPaise: 420000, entryAt: now),
      );
      expect(await shop('how much payment came today'), 'You received ₹0 today.');
      expect(await shop('any payments to check'), 'No payment is waiting for you.');
      expect(await shop('how much do I owe suppliers'), 'You owe suppliers ₹4,200 in all.');
      expect(await shop('how much for Ravi'), 'You owe Ravi Traders ₹4,200.');
      expect(await shop('supplier oils balance'), 'You owe Sri Oils nothing.');
      expect(await shop('my orders'), 'No order is waiting.');
    });

    test('fills in udhaar; nothing is saved', () async {
      final credit = await ask(QboxRole.business, 'Ramesh 250 udhaar');
      expect(credit.text, 'Udhaar given to Ramesh Kumar: ₹250. Check and save.');
      expect((await ask(QboxRole.business, 'suresh paid two hundred')).text, 'Payment from Suresh: ₹200. Check and save.');
      expect(udhaar.entries.values.expand((e) => e), hasLength(2));
      // Another language: the translation says who gave.
      final paid = await ask(
        QboxRole.business,
        'తేజ 500 ఇచ్చాడు',
        language: AppLanguage.telugu,
        english: 'Teja paid 500',
      );
      expect(paid.text, 'Teja ఇచ్చింది: ₹500. చూసి సేవ్ చేయండి.');
      // Not translated: it asks instead of guessing.
      final unsure = await ask(QboxRole.business, 'తేజ 500 ఇచ్చాడు', language: AppLanguage.telugu);
      expect(unsure.action, isNull);
      expect([for (final r in unsure.rows) r.title], ['ఉధార్ ఇచ్చాను', 'చెల్లింపు వచ్చింది']);
    });

    test('two people with the same name: it asks', () async {
      udhaar.seed('Ramesh Reddy', '9222222222');
      final which = await ask(QboxRole.business, 'ramesh balance');
      expect((which.text, which.rows.length), ('Which one?', 2));
      final write = await ask(QboxRole.business, 'ramesh 100 udhaar');
      expect([for (final r in write.rows) r.title], ['Ramesh Kumar', 'Ramesh Reddy']);
    });

    test('fills in stock', () async {
      expect(await shop('rice 10 kg came'), 'Stock in, Rice: 10 kg. Check and save.');
      expect(await shop('sugar 1 kilo sold'), 'Sold, Sugar: 1 kg. Check and save.');
      expect((await stock.stock()).items.first.quantityMilli, 30000);
    });

    test('not understood, help, and the translation as a second try', () async {
      final no = await ask(QboxRole.business, 'sing a song');
      expect((no.text, no.understood), ('I did not understand. Try one of these.', false));
      expect((await ask(QboxRole.business, 'help')).text, 'You can ask me like this.');
      expect(
        await shop('ஏதோ ஒன்று', language: AppLanguage.tamil, english: 'what is running low'),
        'குறைவாக உள்ளவை: 1.',
      );
    });

    test('offline: from the saved copy, and said so; payments need internet', () async {
      await services().stock.freshBook();
      stock.offline = true;
      udhaar.offline = true;
      final s = services();
      final low = await AskBrain(s, QboxRole.business, now: now).ask('low stock', AppLanguage.english);
      expect(low.text, 'This needs internet.'); // the udhaar book was never opened on this phone
      udhaar.offline = false;
      final again = await AskBrain(s, QboxRole.business, now: now).ask('low stock', AppLanguage.english);
      expect((again.text, again.saved), ('Running low: 1.', true));
    });
  });

  group('customer', () {
    test('dues, at one shop or all', () async {
      udhaar.books.addAll(const [
        MyBook(bookId: 1, shopName: 'Balaji Kirana', balancePaise: 50000),
        MyBook(bookId: 2, shopName: 'Lakshmi Stores', balancePaise: -2000),
      ]);
      expect((await ask(QboxRole.customer, 'how much do I owe')).text, 'You owe ₹500 in all. Shops: 1.');
      expect((await ask(QboxRole.customer, 'balaji udhaar')).text, 'You owe Balaji Kirana ₹500.');
      expect((await ask(QboxRole.customer, 'what about lakshmi')).text, 'You paid Lakshmi Stores ₹20 in advance.');
      expect((await ask(QboxRole.customer, 'pay balaji')).text, 'Choose the shop and the amount, then pay.');
    });

    test('spending, budget and payments', () async {
      transactions.all = [
        Transaction(
          id: 'entry-1',
          kind: EntryKind.payment,
          amountPaise: 30000,
          at: DateTime(2026, 11, 20),
          shopKey: 'shop-1',
          shopName: 'Balaji',
        ),
      ];
      expect((await ask(QboxRole.customer, 'how much did I spend')).text, 'You spent ₹300 this month.');
      transactions.budget = 100000;
      expect((await ask(QboxRole.customer, 'budget')).text, 'You spent ₹300 of ₹1,000. ₹700 is left.');
      transactions.budget = 20000;
      expect((await ask(QboxRole.customer, 'budget')).text, 'You spent ₹300. That is ₹100 over your budget of ₹200.');
      expect((await ask(QboxRole.customer, 'my payments')).text, 'Payments this month: 1. Total ₹300.');
    });

    test('lists', () async {
      final s = services();
      await s.pages.open();
      s.pages.put(
        QboxPage(
          ref: 'a',
          isList: true,
          title: 'Home',
          items: [PageItem.create('Milk', qty: '2 L'), PageItem.create('Rice').copyWith(done: true)],
          updatedAt: now,
        ),
      );
      final answer = await AskBrain(s, QboxRole.customer, now: now).ask('my list', AppLanguage.english);
      expect((answer.text, answer.rows.single.title), ('Left in your lists: 1.', 'Milk'));
    });
  });

  group('supplier', () {
    setUp(() {
      supply.shops = [
        const SupplyShop(linkId: 1, name: 'Balaji Kirana', openingPaise: 50000),
        const SupplyShop(linkId: 2, name: 'Lakshmi Stores'),
      ];
      supply.sells = const [
        Product(id: 1, name: 'Rice', unit: StockUnit.kg, counted: true, quantityMilli: 2000, alertMilli: 5000, low: true),
        Product(id: 2, name: 'Oil', unit: StockUnit.l),
      ];
      supply.reportAnswer = const SupplyReport(givenPaise: 900000);
    });

    test('answers', () async {
      Future<String> say(String w) async => (await ask(QboxRole.supplier, w)).text;
      supply.all = [
        SupplyOrder(id: 1, linkId: 1, shopName: 'Balaji Kirana', status: OrderStatus.sent, lines: const [], createdAt: now),
        SupplyOrder(id: 2, linkId: 1, shopName: 'Balaji Kirana', status: OrderStatus.accepted, lines: const [], createdAt: now),
      ];
      expect(await say('any new orders'), 'New orders: 1. To send: 1.');
      expect(await say('how much do shops owe me'), 'Shops owe you ₹500 in all.');
      expect(await say('how much does balaji owe'), 'Balaji Kirana owes you ₹500.');
      expect(await say('lakshmi balance'), 'Lakshmi Stores owes you nothing.');
      expect(await say('which products are low'), 'Running low: 1.');
      expect(await say('how much rice'), 'You have 2 kg of Rice.');
      expect(await say('oil stock'), 'You do not count Oil yet.');
      expect(await say('payments to confirm'), 'No payment is waiting for you.');
      expect(await say('how much money received'), 'You received ₹0 this month.');
      expect(await say('report'), 'You gave goods of ₹9,000 this month.');
      expect(await say('any requests'), 'No shop is asking to connect.');
    });
  });

  group('calendar, for every role', () {
    test('today, tomorrow, and a reminder filled in', () async {
      await calendar.create(
        QboxRole.business,
        EventDraft(title: 'Pay rent', day: DateTime(2026, 11, 26), minuteOfDay: 630, category: EventCategory.values.first),
      );
      final tomorrow = await ask(QboxRole.business, 'what is in my calendar tomorrow');
      expect((tomorrow.text, tomorrow.rows.single.amount), ('In your calendar tomorrow: 1.', '10:30 AM'));
      expect(await shop('calendar today'), 'Nothing in your calendar today.');
      final reminder = await ask(QboxRole.customer, 'remind me tomorrow 10 am pay rent');
      expect(reminder.text, allOf(startsWith('Reminder: '), contains('26 November 2026')));
      final telugu = await ask(
        QboxRole.supplier,
        'రేపు 10 గంటలకు అద్దె గుర్తు చేయి',
        language: AppLanguage.telugu,
        english: 'remind me tomorrow 10 am rent',
      );
      expect(telugu.text, startsWith('రిమైండర్: '));
    });
  });

  group('screen', () {
    Future<void> open(WidgetTester tester, AppServices s, {bool listen = false}) =>
        pumpScreen(tester, s, AskScreen(role: QboxRole.business, listen: listen, now: now));

    testWidgets('by voice, answered aloud in the language; opens the filled form', (tester) async {
      udhaar.seed('Ramesh Kumar', '9876543210');
      final voice = FakeVoiceInput()..nextWords = 'Ramesh 250 udhaar';
      final speaker = FakeSpeaker();
      await open(tester, services(voice: voice, speaker: speaker), listen: true);
      expect(textOf(tester, 'ask-answer-0'), 'Udhaar given to Ramesh Kumar: ₹250. Check and save.');
      expect(speaker.said, ['Udhaar given to Ramesh Kumar: 250. Check and save.']);
      await tapKey(tester, 'ask-action-0');
      expect(find.byType(UdhaarEntryForm), findsOneWidget);
      expect(udhaar.entries.values.expand((e) => e), isEmpty);
    });

    testWidgets('typed, an example, a row, and silently', (tester) async {
      udhaar.seed('Suresh', '9123456780', history: [line(1200)]);
      final speaker = FakeSpeaker();
      await open(tester, services(speaker: speaker));
      expect(at('ask-hello'), findsOneWidget);
      await tapKey(tester, 'ask-aloud');
      await tester.enterText(at('ask-text'), 'sing a song');
      await tester.pump();
      await tapKey(tester, 'ask-send');
      expect(textOf(tester, 'ask-answer-0'), 'I did not understand. Try one of these.');
      await tapKey(tester, 'ask-try-Who owes me the most?');
      expect(textOf(tester, 'ask-answer-1'), 'Suresh owes the most: ₹1,200.');
      expect(speaker.said, isEmpty);
      await tapKey(tester, 'ask-row-1-0');
      expect(find.byType(UdhaarCustomerScreen), findsOneWidget);
    });

    testWidgets('in Telugu, from the saved language; a phone without that voice stays quiet', (tester) async {
      final settings = MemorySettingsStore();
      await saveVoiceLanguage(settings, AppLanguage.telugu);
      final voice = FakeVoiceInput()..nextWords = 'ఏ స్టాక్ తక్కువగా ఉంది';
      final speaker = FakeSpeaker()..missingVoices.add('te-IN');
      await open(tester, services(voice: voice, speaker: speaker, settings: settings));
      expect(textOf(tester, 'ask-hello'), 'ఇలా అడగండి.');
      await tapKey(tester, 'ask-mic');
      expect(voice.lastLocale, 'te_IN');
      expect(textOf(tester, 'ask-answer-0'), 'ఏదీ తక్కువగా లేదు.');
      expect(speaker.said, isEmpty);
    });

    testWidgets('mic trouble, nothing heard, and offline', (tester) async {
      final voice = FakeVoiceInput()..nextError = const VoiceException('Allow microphone access');
      await open(tester, services(voice: voice));
      await tapKey(tester, 'ask-mic');
      expect(find.text('Allow microphone access'), findsOneWidget);
      voice.nextError = null;
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      await tapKey(tester, 'ask-mic');
      expect(find.textContaining('Did not hear anything'), findsOneWidget);
      udhaar.offline = true;
      await tester.enterText(at('ask-text'), 'total udhaar');
      await tester.pump();
      await tapKey(tester, 'ask-send');
      expect(textOf(tester, 'ask-answer-0'), 'This needs internet.');
    });

    testWidgets('the card opens it; its mic listens at once', (tester) async {
      final voice = FakeVoiceInput()..nextWords = 'low stock';
      const card = Scaffold(body: AskCard(role: QboxRole.business, title: 'Ask QBOX AI', about: 'By voice'));
      await pumpScreen(tester, services(voice: voice), card);
      await tapKey(tester, 'ask-card');
      expect(at('ask-hello'), findsOneWidget);
      expect(voice.listenCount, 0);
      await tapKey(tester, 'udhaar-back');
      await tapKey(tester, 'ask-card-mic');
      expect(voice.listenCount, 1);
      expect(at('ask-answer-0'), findsOneWidget);
    });

    testWidgets('a small phone with big text has room', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.4;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      udhaar.seed('A customer with a very long name indeed', '9123456780', history: [line(123456)]);
      for (final role in QboxRole.values) {
        await pumpScreen(tester, services(), const SizedBox());
        tester.view.physicalSize = const Size(1080, 1920);
        await tester.pumpWidget(
          ServicesScope(
            key: UniqueKey(),
            services: services(),
            child: MaterialApp(home: AskScreen(role: role, now: now)),
          ),
        );
        await tester.pumpAndSettle();
        await tester.enterText(at('ask-text'), askExamples(role, AppLanguage.english).first);
        await tester.pump();
        await tapKey(tester, 'ask-send');
        expect(tester.takeException(), isNull, reason: '$role');
      }
    });
  });
}
