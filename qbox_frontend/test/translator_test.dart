import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qbox_app/calculator/calculator_screen.dart';
import 'package:qbox_app/calendar/calendar_screen.dart';
import 'package:qbox_app/onboarding_draft.dart';
import 'package:qbox_app/services/api_client.dart';
import 'package:qbox_app/services/app_services.dart';
import 'package:qbox_app/services/settings_store.dart';
import 'package:qbox_app/translator/languages.dart';
import 'package:qbox_app/translator/speech_engines.dart';
import 'package:qbox_app/translator/translation_service.dart';
import 'package:qbox_app/translator/translator_screen.dart';
import 'package:qbox_app/translator/transliterate.dart';
import 'package:qbox_app/udhaar/udhaar_models.dart';
import 'package:qbox_app/udhaar/udhaar_screen.dart';
import 'package:qbox_app/udhaar/voice_udhaar.dart';

import 'fake_auth_api.dart';

Future<void> pump(WidgetTester tester, AppServices services, Widget screen) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ServicesScope(services: services, child: MaterialApp(home: screen)));
  await tester.pumpAndSettle();
}

Future<void> tapKey(WidgetTester tester, String key) async {
  final finder = find.byKey(Key(key));
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  group('Indian script in English letters', () {
    test('names in each script', () {
      expect(transliterate('తేజ'), 'teja'); // Telugu
      expect(transliterate('रमेश'), 'ramesha'); // Hindi
      expect(transliterate('ಸುರೇಶ'), 'suresha'); // Kannada
      expect(transliterate('தேஜா'), 'tejaa'); // Tamil
      expect(transliterate('లక్ష్మి'), 'lakshmi'); // joined letters
    });

    test('digits and mixed text', () {
      expect(transliterate('౫౦౦'), '500');
      expect(transliterate('Teja 500'), 'Teja 500');
      expect(hasIndianScript('తేజ 500'), isTrue);
      expect(hasIndianScript('Teja 500'), isFalse);
    });

    test('spoken names match saved English names', () {
      const book = [
        UdhaarCustomer(id: 1, name: 'Teja', mobile: '9000000001'),
        UdhaarCustomer(id: 2, name: 'Ramesh Kumar', mobile: '9000000002'),
        UdhaarCustomer(id: 3, name: 'Suresh', mobile: '9000000003'),
      ];
      expect(customersIn(transliterate('తేజ 500 ఇచ్చాడు'), book).single.id, 1);
      expect(customersIn(transliterate('रमेश को 200 दिए'), book).single.id, 2);
      expect(customersIn(transliterate('ಸುರೇಶ 50'), book).single.id, 3);
      expect(customersIn('nobody here', book), isEmpty);
    });

    test('amount in digits from the heard words', () {
      expect(digitsAmount('తేజ 500 ఇచ్చాడు'), 50000);
      expect(digitsAmount('Teja 1,250.50'), 125050);
      expect(digitsAmount('200 of 500'), isNull); // two numbers: unclear
      expect(digitsAmount('no number'), isNull);
    });
  });

  group('Telugu and Hindi words in English letters', () {
    const book = [UdhaarCustomer(id: 1, name: 'Teja', mobile: '9000000001')];
    SpokenUdhaar parse(String s) => parseSpokenUdhaar(s, book)!;

    test('Telugu', () {
      expect(parse('Teja 500 ichadu').kind, EntryKind.payment); // he gave
      expect(parse('Teja 500 kattadu').kind, EntryKind.payment); // he paid
      expect(parse('Teja ki 500 ichanu').kind, EntryKind.credit); // I gave him
      expect(parse('Teja 300 teesukunnadu').kind, EntryKind.credit); // he took
      expect(parse('Teja 300 teesukunnadu').amountPaise, 30000);
    });

    test('Hindi', () {
      expect(parse('Teja ne 500 diye').kind, EntryKind.payment);
      expect(parse('Teja ko 500 diye').kind, EntryKind.credit);
      expect(parse('Teja ne 200 wapas kiye').kind, EntryKind.payment);
      expect(parse('Teja ne 100 liye').kind, EntryKind.credit);
    });
  });

  group('online first (IndicTrans2), on the phone when offline', () {
    test('online when it works', () async {
      final online = FakeLanguageApi();
      final smart = SmartTextTranslator(online: online, offline: FakeTranslator());
      expect(await smart.translate('ఎంత?', from: AppLanguage.telugu, to: AppLanguage.hindi),
          'online[te>hi] ఎంత?');
      expect(smart.lastWasOnline, isTrue);
    });

    test('no internet: the phone translates (if its pack is there)', () async {
      final online = FakeLanguageApi()..error = const ApiException('NETWORK', 'Cannot reach');
      final smart = SmartTextTranslator(online: online, offline: FakeTranslator());
      expect(await smart.translate('ఎంత?', from: AppLanguage.telugu, to: AppLanguage.hindi), '[hi] ఎంత?');
      expect(smart.lastWasOnline, isFalse);
    });

    test('no internet and no pack: says the pack is needed', () async {
      final online = FakeLanguageApi()..error = const ApiException('NETWORK', 'Cannot reach');
      final offline = FakeTranslator()..downloaded.remove(AppLanguage.telugu);
      final smart = SmartTextTranslator(online: online, offline: offline);
      await expectLater(
        smart.translate('ఎంత?', from: AppLanguage.telugu, to: AppLanguage.hindi),
        throwsA(isA<TranslateException>().having((e) => e.needsPack, 'needsPack', isTrue)),
      );
    });

    test('AI server not running: stops asking it for a minute', () async {
      var now = DateTime(2026, 11, 20, 10);
      final online = FakeLanguageApi()
        ..error = const ApiException('LANGUAGE_OFF', 'Not set up', status: 503);
      final smart = SmartTextTranslator(online: online, offline: FakeTranslator(), clock: () => now);
      await smart.translate('a', from: AppLanguage.english, to: AppLanguage.hindi);
      await smart.translate('b', from: AppLanguage.english, to: AppLanguage.hindi);
      expect(online.translateCalls, 1);
      now = now.add(const Duration(seconds: 61));
      online.error = null;
      expect(await smart.translate('c', from: AppLanguage.english, to: AppLanguage.hindi), 'online[en>hi] c');
    });

    test('a login problem is shown, not hidden by the offline translator', () async {
      final online = FakeLanguageApi()
        ..error = const ApiException('TOKEN_INVALID', 'Please log in again', status: 401);
      final smart = SmartTextTranslator(online: online, offline: FakeTranslator());
      await expectLater(
        smart.translate('a', from: AppLanguage.english, to: AppLanguage.hindi),
        throwsA(isA<TranslateException>().having((e) => e.message, 'message', 'Please log in again')),
      );
    });
  });

  group('the best way to hear is chosen by itself', () {
    late FakeVoiceInput phone;
    late FakeVoiceInput server;
    late FakeLanguageApi language;
    late DateTime now;
    late SmartVoiceInput voice;

    setUp(() {
      phone = FakeVoiceInput()..nextWords = 'from the phone';
      server = FakeVoiceInput()..nextWords = 'from the server';
      language = FakeLanguageApi();
      now = DateTime(2026, 11, 20, 10);
      voice = SmartVoiceInput(phone: phone, server: server, language: language, clock: () => now);
    });

    test('Indian languages use the server when it is up', () async {
      expect(await voice.listen(onWords: (_) {}, localeId: 'te_IN'), 'from the server');
      expect(server.lastLocale, 'te_IN');
      expect(await voice.listen(onWords: (_) {}, localeId: 'ta_IN'), 'from the server');
      expect(language.statusCalls, 1); // the answer is remembered for a while
    });

    test('English always uses the phone (the server model has no English)', () async {
      expect(await voice.listen(onWords: (_) {}, localeId: 'en_IN'), 'from the phone');
      expect(language.statusCalls, 0);
    });

    test('server not reachable: the phone is used', () async {
      language.online = false;
      expect(await voice.listen(onWords: (_) {}, localeId: 'te_IN'), 'from the phone');
      // checked again after a while: back on the server
      language.online = true;
      now = now.add(const Duration(seconds: 31));
      expect(await voice.listen(onWords: (_) {}, localeId: 'te_IN'), 'from the server');
    });

    test('server lost while sending: say it again, then the phone is used', () async {
      server.nextError = const VoiceServerUnavailable();
      await expectLater(
        voice.listen(onWords: (_) {}, localeId: 'hi_IN'),
        throwsA(isA<VoiceServerUnavailable>()),
      );
      expect(await voice.listen(onWords: (_) {}, localeId: 'hi_IN'), 'from the phone');
    });
  });

  group('knowing when someone has finished speaking', () {
    Duration ms(int n) => Duration(milliseconds: n);

    test('quiet room: stops shortly after the person stops', () {
      final ear = SpeechEnd();
      var t = 0;
      bool feed(double db, int times) {
        for (var i = 0; i < times; i++) {
          t += 100;
          if (ear.hear(db, ms(t))) return true;
        }
        return false;
      }

      expect(feed(-55, 5), isFalse); // room
      expect(feed(-20, 15), isFalse); // speaking
      expect(ear.heardSpeech, isTrue);
      expect(feed(-55, 10), isFalse); // a short pause between words is fine
      expect(feed(-20, 5), isFalse);
      expect(feed(-55, 20), isTrue); // done
      expect(t, 3500 + 1500); // 1.5 s after the last word
    });

    test('noisy shop: the noise is not taken as speech, clear speech is', () {
      final ear = SpeechEnd();
      var t = 0;
      var stopped = false;
      for (var i = 0; i < 30 && !stopped; i++) {
        t += 100;
        stopped = ear.hear(i.isEven ? -32 : -30, ms(t)); // steady noise
      }
      expect(ear.heardSpeech, isFalse);
      for (var i = 0; i < 10; i++) {
        t += 100;
        ear.hear(-12, ms(t)); // speaking over it
      }
      expect(ear.heardSpeech, isTrue);
    });

    test('a single click is not speech; nothing said = gives up', () {
      final ear = SpeechEnd(waitForSpeech: const Duration(seconds: 2));
      expect(ear.hear(-55, ms(100)), isFalse);
      expect(ear.hear(-10, ms(200)), isFalse); // one tap on the phone
      expect(ear.hear(-55, ms(300)), isFalse);
      expect(ear.heardSpeech, isFalse);
      expect(ear.hear(-55, ms(2100)), isTrue);
    });
  });

  test('every language has speech, voice and translator codes', () {
    expect(AppLanguage.values.map((l) => l.code), ['en', 'te', 'hi', 'kn', 'ta']);
    expect(AppLanguage.telugu.speechLocale, 'te_IN');
    expect(AppLanguage.tamil.voiceLocale, 'ta-IN');
    expect(AppLanguage.fromCode('kn'), AppLanguage.kannada);
    expect(AppLanguage.fromCode('xx'), AppLanguage.english);
  });

  group('Translator screen', () {
    testWidgets('left person speaks Telugu: shown in both, spoken in Hindi', (tester) async {
      final voice = FakeVoiceInput()..nextWords = 'బియ్యం ఎంత?';
      final speaker = FakeSpeaker();
      final translator = FakeTranslator()..phrases['te>hi:బియ్యం ఎంత?'] = 'चावल कितने का है?';
      await pump(tester, fakeServices(voice: voice, speaker: speaker, translator: translator),
          const TranslatorScreen());
      expect(find.byKey(const Key('translator-empty')), findsOneWidget);

      await tapKey(tester, 'translator-mic-left');
      expect(voice.lastLocale, 'te_IN');
      expect(find.text('తెలుగు: బియ్యం ఎంత?'), findsOneWidget);
      expect(find.text('चावल कितने का है?'), findsOneWidget);
      expect(speaker.said.single, 'चावल कितने का है?');
      expect(speaker.locales.single, 'hi-IN');
    });

    testWidgets('right person answers in Hindi: spoken in Telugu', (tester) async {
      final voice = FakeVoiceInput()..nextWords = 'सौ रुपये';
      final speaker = FakeSpeaker();
      // The number is made digits on the phone before translating: the amount cannot change.
      final translator = FakeTranslator()..phrases['hi>te:100 रुपये'] = '100 రూపాయలు';
      await pump(tester, fakeServices(voice: voice, speaker: speaker, translator: translator),
          const TranslatorScreen());
      await tapKey(tester, 'translator-mic-right');
      expect(voice.lastLocale, 'hi_IN');
      expect(find.text('100 రూపాయలు'), findsOneWidget);
      expect(find.text('हिंदी: सौ रुपये'), findsOneWidget); // what was said is shown as said
      expect(speaker.locales.single, 'te-IN');

      await tapKey(tester, 'translator-replay-0');
      expect(speaker.said, ['100 రూపాయలు', '100 రూపాయలు']);
    });

    testWidgets('swap and choose languages; the choice is remembered', (tester) async {
      final settings = MemorySettingsStore();
      await pump(tester, fakeServices(settings: settings), const TranslatorScreen());
      await tapKey(tester, 'translator-swap');
      expect(settings.values['translator_left'], 'hi');
      expect(settings.values['translator_right'], 'te');

      // Picking Tamil on the left.
      await tapKey(tester, 'translator-lang-left');
      await tester.tap(find.byKey(const Key('lang-option-ta')).last);
      await tester.pumpAndSettle();
      expect(settings.values['translator_left'], 'ta');

      // Picking the right side's language on the left swaps them.
      await tapKey(tester, 'translator-lang-left');
      await tester.tap(find.byKey(const Key('lang-option-te')).last);
      await tester.pumpAndSettle();
      expect(settings.values['translator_left'], 'te');
      expect(settings.values['translator_right'], 'ta');
    });

    testWidgets('asks before downloading a missing language pack', (tester) async {
      final voice = FakeVoiceInput()..nextWords = 'ನಮಸ್ಕಾರ';
      final translator = FakeTranslator()..downloaded.remove(AppLanguage.kannada);
      final settings = MemorySettingsStore()
        ..values['translator_left'] = 'kn'
        ..values['translator_right'] = 'en';
      await pump(tester, fakeServices(voice: voice, translator: translator, settings: settings),
          const TranslatorScreen());

      // Heard first; the pack is asked for only because translating needs it.
      await tapKey(tester, 'translator-mic-left');
      expect(voice.listenCount, 1);
      expect(voice.lastLocale, 'kn_IN');
      expect(find.text('Download language packs?'), findsOneWidget);
      await tapKey(tester, 'pack-download');
      expect(translator.downloads, [AppLanguage.kannada]);
      expect(find.text('[en] ನಮಸ್ಕಾರ'), findsOneWidget);
    });

    testWidgets('no voice for a language: words shown, with a hint', (tester) async {
      final voice = FakeVoiceInput()..nextWords = 'hello';
      final speaker = FakeSpeaker()..missingVoices.add('ta-IN');
      final settings = MemorySettingsStore()
        ..values['translator_left'] = 'en'
        ..values['translator_right'] = 'ta';
      await pump(tester, fakeServices(voice: voice, speaker: speaker, settings: settings),
          const TranslatorScreen());
      await tapKey(tester, 'translator-mic-left');
      expect(find.text('[ta] hello'), findsOneWidget);
      expect(speaker.said, isEmpty);
      expect(find.byKey(const Key('translator-no-voice-ta')), findsOneWidget);
    });

    testWidgets('typing instead of speaking', (tester) async {
      final speaker = FakeSpeaker();
      await pump(tester, fakeServices(speaker: speaker), const TranslatorScreen());
      await tapKey(tester, 'translator-type-left');
      await tester.enterText(find.byKey(const Key('translator-type-text')), 'ఎంత?');
      await tapKey(tester, 'translator-type-go');
      expect(find.text('[hi] ఎంత?'), findsOneWidget);
      expect(speaker.locales.single, 'hi-IN');
    });
  });

  group('voice udhaar in other languages', () {
    testWidgets('Telugu: translated on the phone, then understood', (tester) async {
      final api = FakeUdhaarApi();
      final teja = api.seed('Teja', '9876543210');
      final voice = FakeVoiceInput()..nextWords = 'తేజ 500 ఇచ్చాడు';
      final translator = FakeTranslator()..phrases['te>en:తేజ 500 ఇచ్చాడు'] = 'Teja gave 500';
      final settings = MemorySettingsStore()..values['udhaar_voice_lang'] = 'te';
      await pump(tester,
          fakeServices(udhaar: api, voice: voice, translator: translator, settings: settings),
          const UdhaarScreen());

      expect(find.text('Speak in: తెలుగు'), findsOneWidget);
      await tapKey(tester, 'udhaar-speak');
      expect(voice.lastLocale, 'te_IN');
      expect(find.text('Payment received'), findsOneWidget);
      expect(find.text('500'), findsOneWidget);
      expect(find.text('Heard: "తేజ 500 ఇచ్చాడు"'), findsOneWidget);
      expect(find.text('Meaning: "Teja gave 500"'), findsOneWidget);
      await tapKey(tester, 'entry-save');
      expect(api.entries[teja.id]!.single.kind, EntryKind.payment);
    });

    testWidgets('Hindi: name garbled by translation still found from the heard words', (tester) async {
      final api = FakeUdhaarApi();
      final ramesh = api.seed('Ramesh', '9876543210');
      final voice = FakeVoiceInput()..nextWords = 'रमेश को 200 उधार';
      final translator = FakeTranslator()..phrases['hi>en:रमेश को 200 उधार'] = 'Lend 200 to Rams';
      final settings = MemorySettingsStore()..values['udhaar_voice_lang'] = 'hi';
      await pump(tester,
          fakeServices(udhaar: api, voice: voice, translator: translator, settings: settings),
          const UdhaarScreen());

      await tapKey(tester, 'udhaar-speak');
      await tapKey(tester, 'entry-save');
      expect(api.entries[ramesh.id]!.single.amountPaise, 20000);
    });

    testWidgets('choosing the language saves it (shared), with no download', (tester) async {
      final settings = MemorySettingsStore();
      final translator = FakeTranslator()..downloaded.remove(AppLanguage.tamil);
      await pump(tester, fakeServices(settings: settings, translator: translator), const UdhaarScreen());
      await tapKey(tester, 'udhaar-voice-lang');
      await tapKey(tester, 'voice-lang-ta');
      expect(settings.values['voice_lang'], 'ta');
      expect(find.text('Download language packs?'), findsNothing); // only needed offline
      expect(translator.downloads, isEmpty);
      expect(find.text('Speak in: தமிழ்'), findsOneWidget);
    });

    testWidgets('the menu shows only languages: no engine or company names', (tester) async {
      await pump(tester, fakeServices(), const UdhaarScreen());
      await tapKey(tester, 'udhaar-voice-lang');
      for (final name in ['Google', 'IndicConformer', 'IndicTrans2', 'Speech recognition']) {
        expect(find.textContaining(name), findsNothing);
      }
      expect(find.byKey(const Key('voice-lang-te')), findsOneWidget);
    });
  });

  group('calculator in other languages', () {
    testWidgets('Telugu sum: translated, worked out, answer said in Telugu', (tester) async {
      final voice = FakeVoiceInput()..nextWords = 'రెండు వందల యాభై ప్లస్ నూట ఎనభై';
      final speaker = FakeSpeaker();
      final translator = FakeTranslator()
        ..phrases['te>en:రెండు వందల యాభై ప్లస్ నూట ఎనభై'] = 'Two hundred fifty plus one hundred eighty';
      final settings = MemorySettingsStore()..values['voice_lang'] = 'te';
      await pump(tester,
          fakeServices(voice: voice, speaker: speaker, translator: translator, settings: settings),
          const CalculatorScreen());

      expect(find.text('Speak in: తెలుగు'), findsOneWidget);
      await tapKey(tester, 'calc-mic');
      expect(voice.lastLocale, 'te_IN');
      expect(find.text('430'), findsWidgets);
      expect(speaker.said, ['430']);
      expect(speaker.locales, ['te-IN']);
    });

    testWidgets('digits heard as they are still work if translation gives no sum', (tester) async {
      final voice = FakeVoiceInput()..nextWords = '250 + 180';
      final speaker = FakeSpeaker()..missingVoices.add('hi-IN');
      final translator = FakeTranslator()..phrases['hi>en:250 + 180'] = 'Calculate this, please';
      final settings = MemorySettingsStore()..values['voice_lang'] = 'hi';
      await pump(tester,
          fakeServices(voice: voice, speaker: speaker, translator: translator, settings: settings),
          const CalculatorScreen());
      await tapKey(tester, 'calc-mic');
      expect(find.text('430'), findsWidgets);
      // No Hindi voice on this phone: the sum is read back in English.
      expect(speaker.locales, ['en-IN']);
      expect(speaker.said.single, contains('four hundred thirty'));
    });

    testWidgets('the language chosen in the calculator is used by udhaar too', (tester) async {
      final settings = MemorySettingsStore();
      await pump(tester, fakeServices(settings: settings), const CalculatorScreen());
      await tapKey(tester, 'calc-voice-lang');
      await tapKey(tester, 'voice-lang-kn');
      expect(settings.values['voice_lang'], 'kn');

      await pump(tester, fakeServices(settings: settings), const UdhaarScreen());
      expect(find.text('Speak in: ಕನ್ನಡ'), findsOneWidget);
    });
  });

  group('calendar in other languages', () {
    testWidgets('Telugu reminder: date, time and title understood', (tester) async {
      final voice = FakeVoiceInput()..nextWords = 'రేపు ఉదయం 10 గంటలకు సప్లయర్ పేమెంట్';
      final translator = FakeTranslator()
        ..phrases['te>en:రేపు ఉదయం 10 గంటలకు సప్లయర్ పేమెంట్'] =
            'Supplier payment tomorrow at 10 am';
      final settings = MemorySettingsStore()..values['voice_lang'] = 'te';
      final api = FakeCalendarApi();
      await pump(tester,
          fakeServices(voice: voice, translator: translator, settings: settings, calendar: api),
          CalendarScreen(role: QboxRole.business, today: DateTime(2026, 11, 19)));

      await tapKey(tester, 'calendar-speak');
      expect(voice.lastLocale, 'te_IN');
      expect(find.text('Supplier payment'), findsOneWidget);
      expect(find.text('Fri, 20 November 2026'), findsOneWidget);
      expect(find.byKey(const Key('event-heard')), findsOneWidget);
      expect(find.text('Meaning: "Supplier payment tomorrow at 10 am"'), findsOneWidget);
      await tapKey(tester, 'event-save');
      expect(api.saved[QboxRole.business]!.single.minuteOfDay, 600);
    });
  });
}
