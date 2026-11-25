import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qbox_app/translator/indic_numbers.dart';
import 'package:qbox_app/translator/languages.dart';
import 'package:qbox_app/translator/say_numbers.dart';
import 'package:qbox_app/udhaar/udhaar_widgets.dart';

void main() {
  test('200 is two hundred, never "two O O"', () {
    String en(String s) => sayable(s, AppLanguage.english);
    expect(en('The total is 200'), 'The total is two hundred');
    expect(en('The total was Rs 200.'), 'The total was two hundred rupees.');
    expect(en('₹2,500 received'), 'two thousand five hundred rupees received');
    expect(en('₹500 rupees'), 'five hundred rupees');
    expect(en('10 and 0'), 'ten and zero');
    expect(en('2.50 kg'), 'two point five kg');
    expect(en('5kg'), 'five kg');
    expect(en('18% GST'), 'eighteen percent GST');
    expect(en('at 10:05'), 'at ten five');
    expect(en('at 10:00 AM'), 'at ten AM');
    expect(en('call 9876543210'), 'call nine eight seven six five four three two one zero');
    expect(en('1,00,000'), 'one lakh');
    expect(en('rice 200, milk 20'), 'rice two hundred, milk twenty');
    expect(en('B12'), 'B12');
    expect(en('no numbers'), 'no numbers');
  });

  test('in Telugu, Hindi, Kannada and Tamil', () {
    expect(sayable('మొత్తం 250 రూపాయలు', AppLanguage.telugu), 'మొత్తం రెండు వందల యాభై రూపాయలు');
    expect(sayable('రూ. 200 చెల్లించండి', AppLanguage.telugu), 'రెండు వందల రూపాయలు చెల్లించండి');
    expect(sayable('कुल 200 रुपये', AppLanguage.hindi), 'कुल दो सौ रुपये');
    expect(sayable('ಒಟ್ಟು 200 ರೂಪಾಯಿ', AppLanguage.kannada), 'ಒಟ್ಟು ಇನ್ನೂರು ರೂಪಾಯಿ');
    expect(sayable('மொத்தம் 200 ரூபாய்', AppLanguage.tamil), 'மொத்தம் இருநூறு ரூபாய்');
    expect(numberWords(1150, AppLanguage.telugu), 'వెయ్యి నూట యాభై');
    expect(numberWords(100000, AppLanguage.hindi), 'एक लाख');
  });

  test('every number from 0 to 9,999 reads back as itself, in all four', () {
    for (final lang in AppLanguage.values) {
      if (lang == AppLanguage.english) continue;
      final wrong = <String>[];
      for (var n = 0; n < 10000; n++) {
        final words = numberWords(n, lang);
        // 1 and 2 alone are also "a" and "give", so they are not read as numbers.
        final back = numbersToDigits(words, lang);
        if (back != '$n' && n > 2) wrong.add('$n: $words -> $back');
      }
      expect(wrong.take(8), isEmpty, reason: '${lang.name}: ${wrong.length} wrong');
      for (final n in [12500, 99999, 100000, 250000, 1234567, 10000000, 25050075]) {
        expect(numbersToDigits(numberWords(n, lang), lang), '$n', reason: '${lang.name} $n');
      }
    }
  });

  testWidgets('big buttons show all their words on a phone with large text', (tester) async {
    tester.view.physicalSize = const Size(720, 1600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.6)),
          child: child!,
        ),
        home: Scaffold(
          bottomNavigationBar: UdBottomButtons(
            leftKey: const Key('l'),
            leftIcon: Icons.north_east_rounded,
            leftLabel: 'Gave udhaar',
            leftFilled: true,
            onLeft: () {},
            rightKey: const Key('r'),
            rightIcon: Icons.south_west_rounded,
            rightLabel: 'Got payment',
            onRight: () {},
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    for (final (key, words) in [('l', 'Gave udhaar'), ('r', 'Got payment')]) {
      final text = tester.renderObject<RenderBox>(find.text(words));
      // One whole line: as wide as it needs, made smaller to fit the button.
      expect(text.size.width, greaterThanOrEqualTo(text.getMaxIntrinsicWidth(double.infinity) - 1), reason: words);
      final button = tester.getRect(find.byKey(Key(key)));
      final shown = tester.getRect(find.text(words));
      expect(shown.left >= button.left && shown.right <= button.right, isTrue, reason: words);
    }
  });
}
