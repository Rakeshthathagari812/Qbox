import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qbox_app/calculator/voice_services.dart';
import 'package:qbox_app/calculator/voice_talk.dart';
import 'package:qbox_app/translator/english_numbers.dart';
import 'package:qbox_app/translator/languages.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// A pretend Android: like the real one, it refuses to start while it still
/// counts itself as listening.
class FakePhone {
  FakePhone(this.messenger) {
    messenger.setMockMethodCallHandler(_channel, (call) async {
      calls.add(call.method);
      switch (call.method) {
        case 'initialize' || 'has_permission':
          return true;
        case 'listen':
          if (listening) {
            refused++;
            return false;
          }
          listening = true;
          await send('notifyStatus', 'listening');
          return true;
        case 'stop' || 'cancel':
          if (!listening) return false;
          listening = false;
          await send('notifyStatus', 'notListening');
          return true;
      }
      return null;
    });
  }

  static const _channel = MethodChannel('plugin.csdcorp.com/speech_to_text');
  final TestDefaultBinaryMessenger messenger;
  final List<String> calls = [];
  bool listening = false;
  int refused = 0;

  Future<void> send(String method, Object arguments) => messenger.handlePlatformMessage(
    _channel.name,
    _channel.codec.encodeMethodCall(MethodCall(method, arguments)),
    (_) {},
  );

  Future<void> words(List<String> said, {bool last = false}) => send(
    'textRecognition',
    jsonEncode({
      'alternates': [for (final w in said) {'recognizedWords': w, 'confidence': 0.9}],
      'resultType': last ? 2 : 0,
      'finalResult': last,
    }),
  );
}

void main() {
  group("the phone's own hearing", () {
    late FakePhone phone;
    late DeviceVoiceInput voice;

    FakePhone start(WidgetTester tester) {
      phone = FakePhone(tester.binding.defaultBinaryMessenger);
      voice = DeviceVoiceInput(speech: SpeechToText.withMethodChannel());
      return phone;
    }

    testWidgets('a second tap straight after the first really listens again', (tester) async {
      start(tester);
      final one = voice.listen(onWords: (_) {});
      await tester.pump();
      await phone.words(['20 + 30', '20 and 30'], last: true);
      expect(await one, '20 + 30');
      expect(voice.guesses, ['20 + 30', '20 and 30']);

      final two = voice.listen(onWords: (_) {});
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect((phone.listening, phone.refused), (true, 0));
      // The first one's late "done" must not end the second.
      await phone.words(['40 + 2'], last: true);
      expect(await two, '40 + 2');
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('it waits for someone to start, and ends by itself after the last word', (tester) async {
      start(tester);
      var ready = 0;
      String? result;
      unawaited(
        voice
            .listen(
              onWords: (_) {},
              onReady: () => ready++,
              pace: VoicePace(
                pause: const Duration(milliseconds: 1500),
                unfinished: (w) => sumUnfinished(w, AppLanguage.english),
              ),
            )
            .then((w) => result = w),
      );
      await tester.pump();
      await phone.send('soundLevelChange', 2.5);
      expect(ready, 1);
      await tester.pump(const Duration(seconds: 6)); // thinking: still listening
      expect((phone.listening, result), (true, null));
      await phone.words(['20 plus']);
      await tester.pump(const Duration(milliseconds: 3500)); // more must follow
      expect(phone.listening, isTrue);
      await phone.words(['20 plus 30']);
      await tester.pump(const Duration(milliseconds: 1600));
      expect(phone.calls.last, 'stop');
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      expect(result, '20 plus 30');
    });

    testWidgets('nothing said: it stops by itself', (tester) async {
      start(tester);
      String? result;
      unawaited(voice.listen(onWords: (_) {}).then((w) => result = w));
      await tester.pump();
      await tester.pump(const Duration(seconds: 9));
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      expect((result, phone.listening), ('', false));
    });

    testWidgets('a phone that will not start says so, instead of waiting for ever', (tester) async {
      start(tester);
      phone.messenger.setMockMethodCallHandler(FakePhone._channel, (call) async => call.method == 'initialize');
      Object? problem;
      unawaited(voice.listen(onWords: (_) {}).then((_) {}, onError: (Object e) => problem = e));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(problem, isA<VoiceException>());
    });
  });

  group('sums', () {
    test('carrying on from the answer', () {
      expect(readSum('plus 10', AppLanguage.english, last: 50), '50+10');
      expect(readSum('into 3', AppLanguage.english, last: 50), '50×3');
      expect(readSum('divided by 2', AppLanguage.english, last: 50), '50÷2');
      expect(readSum('ప్లస్ పది', AppLanguage.telugu, last: 50), '50+10');
      expect(readSum('20 plus 30', AppLanguage.english, last: 50), '20+30');
      expect(readSum('plus 10', AppLanguage.english), isNull);
    });

    test("the phone's other guesses", () {
      expect(bestSum('2030', ['2030', '20 + 30'], AppLanguage.english), '20+30');
      expect(bestSum('twenty thirsty', ['twenty thirsty', 'twenty plus thirty'], AppLanguage.english), '20+30');
      expect(bestSum('2030', ['2030', '40 + 30'], AppLanguage.english), '2030'); // other numbers
      expect(bestSum('20 + 30', ['20 + 30', '20 - 30'], AppLanguage.english), '20+30'); // the first is a sum
      expect(bestSum('hello', ['hello'], AppLanguage.english), isNull);
    });

    test('unfinished', () {
      expect(sumUnfinished('20 plus', AppLanguage.english), isTrue);
      expect(sumUnfinished('18 percent of', AppLanguage.english), isTrue);
      expect(sumUnfinished('20 ప్లస్', AppLanguage.telugu), isTrue);
      expect(sumUnfinished('20 plus 30', AppLanguage.english), isFalse);
      expect(sumUnfinished('', AppLanguage.english), isFalse);
    });

    test('English numbers in Indian letters', () {
      expect(englishNumberWords('ట్వంటీ ప్లస్ థర్టీ'), 'twenty ప్లస్ thirty');
      expect(readSum('ట్వెంటీ ప్లస్ థర్టీ', AppLanguage.telugu), '20+30');
      expect(readSum('ट्वेंटी प्लस थर्टी', AppLanguage.hindi), '20+30');
      expect(readSum('ಟ್ವೆಂಟಿ ಪ್ಲಸ್ ತರ್ಟಿ', AppLanguage.kannada), '20+30');
      expect(readSum('ட்வென்ட்டி ப்ளஸ் தேர்ட்டி', AppLanguage.tamil), '20+30');
      expect(readSum('టూ హండ్రెడ్ ఫిఫ్టీ మైనస్ టెన్', AppLanguage.telugu), '250−10');
      expect(englishNumberWords('వెన్న కొబ్బరి నూనె'), 'వెన్న కొబ్బరి నూనె');
    });

    test('the whole sum is said in every language', () {
      expect(spokenSum('20+30', 50, AppLanguage.english), 'twenty plus thirty equals fifty');
      expect(spokenSum('20+30', 50, AppLanguage.telugu), '20 ప్లస్ 30 సమానం 50');
      expect(spokenSum('20−30', -10, AppLanguage.hindi), '20 माइनस 30 बराबर माइनस 10');
      expect(spokenSum('6×7', 42, AppLanguage.kannada), '6 ಇಂಟು 7 ಸಮ 42');
      expect(spokenSum('9÷2', 4.5, AppLanguage.tamil), '9 வகுத்தல் 2 சமம் 4.5');
      expect(spokenSum('18%×1200', 216, AppLanguage.telugu), '18 శాతం ఇంటూ 1200 సమానం 216');
      expect(spokenSum('50', 50, AppLanguage.telugu), '50');
    });

    test('stop and clear', () {
      expect([saysStop('Stop.'), saysStop('చాలు'), saysStop('20 plus 30')], [true, true, false]);
      expect([saysClear('clear'), saysClear('क्लियर'), saysClear('5')], [true, true, false]);
      for (final lang in AppLanguage.values) {
        expect(sayAgain(lang), isNotEmpty);
      }
    });
  });
}
