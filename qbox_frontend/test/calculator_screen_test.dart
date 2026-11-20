import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qbox_app/calculator/calculator_screen.dart';
import 'package:qbox_app/calculator/calculator_store.dart';
import 'package:qbox_app/calculator/voice_services.dart';
import 'package:qbox_app/services/app_services.dart';

import 'fake_auth_api.dart';

Future<void> openCalculator(WidgetTester tester, AppServices services) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ServicesScope(
      services: services,
      child: const MaterialApp(home: CalculatorScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> tapKeys(WidgetTester tester, List<String> keys) async {
  for (final key in keys) {
    await tester.tap(find.byKey(Key('calc-$key')));
    await tester.pump();
  }
}

/// Everything written in the big line (a plain answer, or the tappable sum pieces).
String mainLine(WidgetTester tester) => tester
    .widgetList<Text>(
      find.descendant(
        of: find.byKey(const Key('calc-main-line')),
        matching: find.byType(Text),
      ),
    )
    .map((t) => t.data)
    .join();

String topLine(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('calc-top-line'))).data!;

const _spoken790 =
    'two hundred fifty plus one hundred eighty into three equals seven hundred ninety';

void main() {
  testWidgets('typed sum shows the answer, speaks it and adds to GT', (tester) async {
    final speaker = FakeSpeaker();
    await openCalculator(tester, fakeServices(speaker: speaker));

    await tapKeys(tester, ['2', '5', '0', '+', '1', '8', '0', '×', '3']);
    expect(mainLine(tester), '250 + 180 × 3');
    expect(topLine(tester), '= 790');

    await tapKeys(tester, ['=']);
    expect(mainLine(tester), '790');
    expect(topLine(tester), '250 + 180 × 3 =');
    expect(speaker.said, [_spoken790]);
    expect(find.text('GT 790'), findsOneWidget);
  });

  testWidgets('voice sum is worked out and spoken', (tester) async {
    final voice = FakeVoiceInput()..nextWords = 'two fifty plus one eighty into 3';
    final speaker = FakeSpeaker();
    await openCalculator(tester, fakeServices(voice: voice, speaker: speaker));

    await tester.tap(find.byKey(const Key('calc-mic')));
    await tester.pumpAndSettle();
    expect(mainLine(tester), '790');
    expect(topLine(tester), '250 + 180 × 3 =');
    expect(speaker.said, [_spoken790]);
  });

  testWidgets('voice that is not a sum shows a hint', (tester) async {
    final voice = FakeVoiceInput()..nextWords = 'hello qbox';
    await openCalculator(tester, fakeServices(voice: voice));

    await tester.tap(find.byKey(const Key('calc-mic')));
    await tester.pump();
    expect(find.textContaining('Could not understand "hello qbox"'), findsOneWidget);
    expect(mainLine(tester), '0');
  });

  testWidgets('voice problems show the message', (tester) async {
    final voice = FakeVoiceInput()
      ..nextError = const VoiceException('Allow microphone access for QBOX in phone settings.');
    await openCalculator(tester, fakeServices(voice: voice));

    await tester.tap(find.byKey(const Key('calc-mic')));
    await tester.pump();
    expect(find.text('Allow microphone access for QBOX in phone settings.'), findsOneWidget);
  });

  testWidgets('mute stops spoken answers and is remembered', (tester) async {
    final speaker = FakeSpeaker();
    final store = MemoryCalculatorStore();
    await openCalculator(tester, fakeServices(speaker: speaker, calculator: store));

    await tester.tap(find.byKey(const Key('calc-sound')));
    await tester.pump();
    await tapKeys(tester, ['5', '×', '5', '=']);
    expect(mainLine(tester), '25');
    expect(speaker.said, isEmpty);
    expect(store.data!['muted'], isTrue);
  });

  testWidgets('history, GT and memory are kept after reopening', (tester) async {
    final store = MemoryCalculatorStore();
    await openCalculator(tester, fakeServices(calculator: store));
    await tapKeys(tester, ['1', '2', '0', '+', '8', '0', '=', 'M+']);

    // Reopen with the same saved data.
    await tester.pumpWidget(const SizedBox());
    await openCalculator(tester, fakeServices(calculator: store));
    expect(find.text('GT 200'), findsOneWidget);
    expect(find.byKey(const Key('calc-memory-badge')), findsOneWidget);

    await tester.tap(find.byKey(const Key('calc-history')));
    await tester.pumpAndSettle();
    expect(find.text('120 + 80 ='), findsOneWidget);

    // Tapping a history line brings its answer back.
    await tester.tap(find.byKey(const Key('calc-history-0')));
    await tester.pumpAndSettle();
    expect(mainLine(tester), '200');
  });

  testWidgets('clear history empties the list', (tester) async {
    final store = MemoryCalculatorStore();
    await openCalculator(tester, fakeServices(calculator: store));
    await tapKeys(tester, ['9', '+', '1', '=']);

    await tester.tap(find.byKey(const Key('calc-history')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('calc-clear-history')));
    await tester.pumpAndSettle();
    expect(find.text('No calculations yet'), findsOneWidget);
    expect(store.data!['history'], isEmpty);
  });

  testWidgets('while listening, the display shows the Listening panel and Stop', (
    tester,
  ) async {
    final voice = _HeldVoice();
    await openCalculator(tester, fakeServices(voice: voice));

    await tester.tap(find.byKey(const Key('calc-mic')));
    await tester.pump();
    expect(find.byKey(const Key('calc-listening')), findsOneWidget);
    expect(find.text('Stop'), findsOneWidget);

    voice.words('500 minus 50');
    await tester.pump();
    expect(find.text('500 minus 50'), findsOneWidget);

    voice.finish();
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('calc-listening')), findsNothing);
    expect(mainLine(tester), '450');
  });

  testWidgets('tap a wrong number in the sum and type the right one', (
    tester,
  ) async {
    await openCalculator(tester, fakeServices());
    await tapKeys(tester, ['6', '+', '5', '−', '3', '+', '1', '+', '6']);
    expect(mainLine(tester), '6 + 5 − 3 + 1 + 6');

    // The 5 should have been 50.
    await tester.tap(find.byKey(const Key('calc-piece-2')));
    await tester.pump();
    expect(topLine(tester), 'Type the right number, or ⌫ to remove it');
    await tapKeys(tester, ['5', '0']);
    expect(mainLine(tester), '6 + 50 − 3 + 1 + 6');

    // The − should have been +.
    await tester.tap(find.byKey(const Key('calc-piece-3')));
    await tester.pump();
    await tapKeys(tester, ['+', '=']);
    expect(mainLine(tester), '66');
  });

  testWidgets('tap the answered sum to fix it; GT is not counted twice', (
    tester,
  ) async {
    final speaker = FakeSpeaker();
    await openCalculator(tester, fakeServices(speaker: speaker));
    await tapKeys(tester, ['1', '0', '0', '+', '5', '0', '=']);
    expect(find.text('GT 150'), findsOneWidget);

    await tester.tap(find.byKey(const Key('calc-edit-sum')));
    await tester.pump();
    expect(mainLine(tester), '100 + 50');
    await tester.tap(find.byKey(const Key('calc-piece-2')));
    await tester.pump();
    await tapKeys(tester, ['6', '0', '=']);
    expect(mainLine(tester), '160');
    expect(find.text('GT 160'), findsOneWidget);
    // The fixed sum is spoken too.
    expect(speaker.said.last, 'one hundred plus sixty equals one hundred sixty');
  });

  testWidgets('Speak and = are the same size', (tester) async {
    await openCalculator(tester, fakeServices());
    final speak = tester.getSize(find.byKey(const Key('calc-mic')));
    final equals = tester.getSize(find.byKey(const Key('calc-=')));
    expect(speak, equals);
  });

  testWidgets('divide by zero shows a message, not a crash', (tester) async {
    await openCalculator(tester, fakeServices());
    await tapKeys(tester, ['5', '÷', '0', '=']);
    expect(mainLine(tester), 'Cannot divide by zero');
  });
}

/// A microphone that keeps listening until the test says it is done.
class _HeldVoice implements VoiceInput {
  final _done = Completer<String>();
  void Function(String)? _onWords;
  String _heard = '';

  void words(String text) {
    _heard = text;
    _onWords?.call(text);
  }

  void finish() => _done.complete(_heard);

  @override
  Future<String> listen({
    required void Function(String words) onWords,
    String localeId = 'en_IN',
  }) {
    _onWords = onWords;
    return _done.future;
  }

  @override
  Future<void> stop() async => finish();
}