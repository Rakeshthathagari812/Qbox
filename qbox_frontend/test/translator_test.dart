import 'dart:typed_data';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qbox_app/calculator/calculator_screen.dart';
import 'package:qbox_app/calculator/voice_services.dart';
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

import 'calculator_screen_test.dart' show HeldVoice;
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

  group('the server hears while one speaks', () {
    test('the answer is asked for at the first quiet, so it is ready at the end', () async {
      final mic = FakeMic();
      final api = FakeLanguageApi();
      final words = <String>[];
      var ready = 0;
      final result = IndicVoiceInput(api, mic: mic).listen(
        onWords: words.add,
        localeId: 'te_IN',
        pace: const VoicePace(serverPause: Duration(milliseconds: 1000)),
        onReady: () => ready++,
      );
      await mic.opened.future;
      await mic.play(60, 5);
      await mic.play(9000, 15, voice: true);
      expect(api.heardClips, 0);
      await mic.play(60, 6); // 0.6 s quiet: asked already
      expect(api.heardClips, 1);
      await mic.play(60, 8);
      expect(await result, api.speechText);
      expect((api.heardClips, ready, mic.stopped), (1, 1, true));
      expect(words, ['…', api.speechText]);
    });

    test('they went on speaking: asked again with all of it', () async {
      final mic = FakeMic();
      final api = FakeLanguageApi();
      final result = IndicVoiceInput(api, mic: mic).listen(onWords: (_) {}, localeId: 'te_IN');
      await mic.opened.future;
      await mic.play(60, 5);
      await mic.play(9000, 10, voice: true);
      await mic.play(60, 7);
      await mic.play(9000, 10, voice: true);
      await mic.play(60, 16);
      await result;
      expect(api.heardClips, 2);
      expect(api.lastClip, greaterThan(16000 * 2 * 3)); // more than 3 s of sound
    });

    test('nothing said: the server is not asked', () async {
      final mic = FakeMic();
      final api = FakeLanguageApi();
      final result = IndicVoiceInput(api, mic: mic).listen(onWords: (_) {}, localeId: 'te_IN');
      await mic.opened.future;
      await mic.play(60, 85);
      expect(await result, '');
      expect(api.heardClips, 0);
    });

    test('tapped Stop early: what was said counts', () async {
      final mic = FakeMic();
      final api = FakeLanguageApi();
      final voice = IndicVoiceInput(api, mic: mic);
      final result = voice.listen(onWords: (_) {}, localeId: 'te_IN');
      await mic.opened.future;
      await mic.play(60, 5);
      await mic.play(9000, 10, voice: true);
      await voice.stop();
      expect(await result, api.speechText);
    });

    test('a wav file is made as the server reads it', () {
      final wav = wavOf(Uint8List(320), 16000);
      expect(wav.length, 364);
      expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
      expect(loudness(Uint8List(320), 0, 320), -160);
    });

    test('the server was up a little while ago: no waiting to ask again', () async {
      var now = DateTime(2026, 11, 25, 10);
      final api = FakeLanguageApi();
      final server = FakeVoiceInput()..nextWords = 'server';
      final voice = SmartVoiceInput(phone: FakeVoiceInput(), server: server, language: api, clock: () => now);
      await voice.warmUp(localeId: 'te_IN');
      now = now.add(const Duration(minutes: 2));
      expect(await voice.listen(onWords: (_) {}, localeId: 'te_IN'), 'server');
    });

    test('spoken commands are translated fast', () async {
      final api = FakeLanguageApi();
      final smart = SmartTextTranslator(online: api, offline: FakeTranslator());
      await smart.translate('a', from: AppLanguage.telugu, to: AppLanguage.english, fast: true);
      expect(api.lastFast, isTrue);
      await smart.translate('a', from: AppLanguage.telugu, to: AppLanguage.english);
      expect(api.lastFast, isFalse);
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
      expect(t, 3500 + 1200); // just over 1.1 s after the last word
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

    /// Feeds one loudness after another; the time it stopped, or null.
    int? stopsAt(SpeechEnd ear, Iterable<double> levels) {
      var t = 0;
      for (final db in levels) {
        t += 100;
        if (ear.hear(db, ms(t))) return t;
      }
      return null;
    }

    List<double> flat(double db, int times) => [for (var i = 0; i < times; i++) db + (i.isEven ? 1 : -1)];
    // A voice: up and down, with gaps.
    List<double> voice(double db, int times) => [for (var i = 0; i < times; i++) db - const [0, 4, 9, 2, 14, 1][i % 6]];
    const opening = [-160.0, -160.0];

    test('the microphone opening (no sound yet) is not taken as the quiet of the room', () {
      // It used to go on for 25 s here: the room itself was "speech".
      for (final room in [-58.0, -46.0, -40.0, -34.0]) {
        final ear = SpeechEnd(quietAfterSpeech: ms(1300));
        final at = stopsAt(ear, [...opening, ...flat(room, 8), ...voice(-12, 20), ...flat(room, 60)]);
        expect(at, inInclusiveRange(3000 + 1000, 3000 + 1900), reason: 'room $room');
      }
      final nobody = SpeechEnd(waitForSpeech: ms(8000));
      expect(stopsAt(nobody, [...opening, ...flat(-40, 100)]), 8100);
      expect(nobody.heardSpeech, isFalse);
    });

    test('speaking at once, and a phone that makes the room louder afterwards', () {
      expect(
        stopsAt(SpeechEnd(quietAfterSpeech: ms(1300)), [...opening, ...voice(-14, 20), ...flat(-45, 60)]),
        inInclusiveRange(3000, 4200),
      );
      expect(
        stopsAt(SpeechEnd(quietAfterSpeech: ms(1300)), [
          ...opening,
          ...flat(-55, 5),
          ...voice(-14, 20),
          for (var i = 0; i < 10; i++) -50 + i * 2.0, // turning itself up
          ...flat(-32, 60),
        ]),
        inInclusiveRange(3500, 6500),
      );
    });

    test('a pause between words does not cut the sum', () {
      final ear = SpeechEnd(quietAfterSpeech: ms(1300));
      final at = stopsAt(ear, [...opening, ...flat(-42, 5), ...voice(-15, 8), ...flat(-42, 10), ...voice(-15, 8), ...flat(-42, 50)]);
      expect(at, greaterThan(3300 + 1000));
    });

    test('a soft voice, and a voice in a noisy shop', () {
      for (final (room, speech) in [(-58.0, -30.0), (-32.0, -8.0)]) {
        final ear = SpeechEnd(quietAfterSpeech: ms(1300));
        final at = stopsAt(ear, [...opening, ...flat(room, 8), ...voice(speech, 24), ...flat(room, 60)]);
        expect(ear.heardSpeech, isTrue);
        expect(at, inInclusiveRange(3400 + 900, 3400 + 2000), reason: '$room $speech');
      }
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

    testWidgets('it stops talking before it listens, and says when the mic is open', (tester) async {
      final voice = HeldVoice();
      final speaker = FakeSpeaker();
      await pump(tester, fakeServices(voice: voice, speaker: speaker), const TranslatorScreen());
      final before = speaker.stops;
      await tester.tap(find.byKey(const Key('translator-mic-left')));
      await tester.pump();
      expect(speaker.stops, before + 1);
      expect(find.text('Getting ready…'), findsOneWidget);
      voice.ready!();
      await tester.pump();
      expect(find.text('Speak now in తెలుగు'), findsOneWidget);
      expect(find.text('Listening…'), findsOneWidget);
      voice.words('ఎంత?');
      voice.finish();
      await tester.pumpAndSettle();
      expect(find.text('[hi] ఎంత?'), findsOneWidget);
    });

    testWidgets('heard wrongly: corrected, and translated again in the same place', (tester) async {
      final voice = FakeVoiceInput()..nextWords = 'పాలు';
      final speaker = FakeSpeaker();
      await pump(tester, fakeServices(voice: voice, speaker: speaker), const TranslatorScreen());
      await tapKey(tester, 'translator-mic-left');
      await tapKey(tester, 'translator-correct-0');
      expect(find.text('పాలు'), findsOneWidget); // ready to correct
      await tester.enterText(find.byKey(const Key('translator-type-text')), 'పాలు ఉన్నాయా?');
      await tapKey(tester, 'translator-type-go');
      expect(find.text('తెలుగు: పాలు ఉన్నాయా?'), findsOneWidget);
      expect(find.text('తెలుగు: పాలు'), findsNothing);
      expect(speaker.said.last, '[hi] పాలు ఉన్నాయా?');
    });

    testWidgets('sound turned down, or no voice: it says what to do', (tester) async {
      final device = FakeDeviceActions()..volume = 0;
      final speaker = FakeSpeaker()..missingVoices.add('te-IN');
      final voice = FakeVoiceInput()..nextWords = 'hello';
      await pump(tester, fakeServices(voice: voice, speaker: speaker, device: device), const TranslatorScreen());
      await tapKey(tester, 'translator-mic-left'); // to Hindi
      expect(find.textContaining('Turn up the volume'), findsOneWidget);
      await tapKey(tester, 'translator-mic-right'); // to Telugu
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      expect(device.voiceSettingsOpened, 1);
    });

    testWidgets('not translated: the line goes away', (tester) async {
      final translator = FakeTranslator()..error = const TranslateException('Could not translate. Please try again.');
      await pump(tester, fakeServices(voice: FakeVoiceInput()..nextWords = 'a', translator: translator), const TranslatorScreen());
      await tapKey(tester, 'translator-mic-left');
      expect(find.byKey(const Key('translator-line-0')), findsNothing);
      expect(find.text('Could not translate. Please try again.'), findsOneWidget);
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
    testWidgets('Telugu sum: translated, worked out, the whole sum said in Telugu', (tester) async {
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
      expect(speaker.said, ['250 ప్లస్ 180 సమానం 430']);
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

/// A pretend microphone: 100 ms of sound at a time.
class FakeMic implements MicStream {
  final opened = Completer<void>();
  final _sound = StreamController<Uint8List>();
  bool stopped = false;

  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<Stream<Uint8List>> start() async {
    Future(opened.complete);
    return _sound.stream;
  }

  @override
  Future<void> stop() async => stopped = true;

  /// [frames] x 100 ms, as loud as [peak]; a [voice] goes up and down.
  Future<void> play(int peak, int frames, {bool voice = false}) async {
    const parts = [1.0, 0.6, 0.3, 0.8, 0.15, 0.9];
    for (var i = 0; i < frames; i++) {
      final data = ByteData(3200);
      data.setInt16(100, (voice ? peak * parts[i % 6] : peak).round(), Endian.little);
      if (!_sound.isClosed) _sound.add(data.buffer.asUint8List());
      await Future<void>.delayed(Duration.zero);
    }
  }
}
