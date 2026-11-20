import 'package:flutter_test/flutter_test.dart';
import 'package:qbox_app/calculator/spoken_operators.dart';
import 'package:qbox_app/calculator/voice_math.dart';
import 'package:qbox_app/translator/indic_numbers.dart';
import 'package:qbox_app/translator/languages.dart';

void main() {
  String te(String s) => numbersToDigits(s, AppLanguage.telugu);
  String hi(String s) => numbersToDigits(s, AppLanguage.hindi);
  String kn(String s) => numbersToDigits(s, AppLanguage.kannada);
  String ta(String s) => numbersToDigits(s, AppLanguage.tamil);

  group('Telugu numbers', () {
    test('words become digits', () {
      expect(te('రెండు వందల యాభై'), '250');
      expect(te('నూట ఎనభై'), '180');
      expect(te('పన్నెండు వందల యాభై'), '1250');
      expect(te('ఇరవై ఐదు'), '25');
      expect(te('వెయ్యి'), '1000');
      expect(te('రెండు వేల ఐదు వందలు'), '2500');
      expect(te('రెండొందల యాభై'), '250');
      expect(te('రెండున్నర వేలు'), '2500');
      expect(te('రెండు లక్షల యాభై వేలు'), '250000');
      expect(te('ఒక వంద'), '100');
    });

    test('inside a sentence, the rest is kept', () {
      expect(te('రమేష్ రెండు వందల యాభై ఉద్దెర'), 'రమేష్ 250 ఉద్దెర');
      expect(te('రమేష్ వంద రూపాయలు ఇచ్చాడు'), 'రమేష్ 100 రూపాయలు ఇచ్చాడు');
      expect(te('రేపు ఉదయం పది గంటలకు'), 'రేపు ఉదయం 10 గంటలకు');
      expect(te('వందకు'), '100కు');
    });

    test('"at ten o\'clock" in one word', () {
      expect(te('రేపు పదింటికి సప్లయర్ పేమెంట్'), 'రేపు 10 గంటలకు సప్లయర్ పేమెంట్');
    });

    test('two numbers side by side stay two numbers', () {
      expect(te('ఐదు మూడు'), '5 3');
      expect(te('యాభై, ఇరవై'), '50, 20');
    });

    test('"a" alone is not a number', () {
      expect(te('ఒక కిలో'), 'ఒక కిలో');
    });

    test('Telugu digits', () {
      expect(te('౨౫౦ ప్లస్ ౧౮౦'), '250 ప్లస్ 180');
    });
  });

  group('Hindi numbers', () {
    test('words become digits', () {
      expect(hi('एक सौ अस्सी'), '180');
      expect(hi('ढाई सौ'), '250');
      expect(hi('डेढ़ हज़ार'), '1500');
      expect(hi('साढ़े तीन सौ'), '350');
      expect(hi('पाँच सौ'), '500');
      expect(hi('बारह सौ पचास'), '1250');
      expect(hi('दो हजार पांच सौ'), '2500');
      expect(hi('पच्चीस'), '25');
    });

    test('inside a sentence', () {
      expect(hi('रमेश को ढाई सौ रुपये उधार'), 'रमेश को 250 रुपये उधार');
      expect(hi('कल सुबह दस बजे'), 'कल सुबह 10 बजे');
    });

    test('"दो" alone can mean "give", "एक" can mean "a"', () {
      expect(hi('पैसे दो'), 'पैसे दो');
      expect(hi('एक बार'), 'एक बार');
      expect(hi('दो सौ'), '200');
    });

    test('Hindi digits', () {
      expect(hi('२५० प्लस १८०'), '250 प्लस 180');
    });
  });

  group('Kannada numbers', () {
    test('words become digits', () {
      expect(kn('ಎರಡು ನೂರ ಐವತ್ತು'), '250');
      expect(kn('ನೂರ ಎಂಬತ್ತು'), '180');
      expect(kn('ಇನ್ನೂರ ಐವತ್ತು'), '250');
      expect(kn('ಐನೂರು'), '500');
      expect(kn('ಇಪ್ಪತ್ತೈದು'), '25');
      expect(kn('ಇಪ್ಪತ್ಮೂರು'), '23');
      expect(kn('ಎರಡು ಸಾವಿರದ ಐನೂರು'), '2500');
    });

    test('inside a sentence', () {
      expect(kn('ನಾಳೆ ಬೆಳಿಗ್ಗೆ ಹತ್ತು ಗಂಟೆಗೆ'), 'ನಾಳೆ ಬೆಳಿಗ್ಗೆ 10 ಗಂಟೆಗೆ');
    });
  });

  group('Tamil numbers', () {
    test('words become digits', () {
      expect(ta('இருநூற்று ஐம்பது'), '250');
      expect(ta('நூற்று எண்பது'), '180');
      expect(ta('ஐநூறு'), '500');
      expect(ta('இருபத்தைந்து'), '25');
      expect(ta('இருபத்தி ஐந்து'), '25');
      expect(ta('இருபத்திரண்டு'), '22');
      expect(ta('இரண்டாயிரத்து ஐநூறு'), '2500');
      expect(ta('ஆயிரம்'), '1000');
    });

    test('inside a sentence', () {
      expect(ta('ரமேஷ் நூறு ரூபாய் கொடுத்தார்'), 'ரமேஷ் 100 ரூபாய் கொடுத்தார்');
      expect(ta('ஒரு கிலோ'), 'ஒரு கிலோ');
    });
  });

  test('English is left alone', () {
    expect(numbersToDigits('two fifty plus 180', AppLanguage.english), 'two fifty plus 180');
  });

  group('spoken sums are worked out without translating', () {
    String? sum(String s, AppLanguage l) => parseSpokenMath(operatorsToSymbols(numbersToDigits(s, l), l));

    test('Telugu', () {
      expect(sum('రెండు వందల యాభై ప్లస్ నూట ఎనభై', AppLanguage.telugu), '250+180');
      expect(sum('ఐదు వందలు ఇంటు మూడు', AppLanguage.telugu), '500×3');
      expect(sum('వెయ్యి మైనస్ రెండు వందలు', AppLanguage.telugu), '1000−200');
      expect(sum('పన్నెండు వందల యాభై భాగించు ఐదు', AppLanguage.telugu), '1250÷5');
      expect(sum('వెయ్యి బై నాలుగు', AppLanguage.telugu), '1000÷4');
      expect(sum('250 ఇంటు 3', AppLanguage.telugu), '250×3');
    });

    test('Hindi', () {
      expect(sum('ढाई सौ जोड़ एक सौ अस्सी', AppLanguage.hindi), '250+180');
      expect(sum('पांच सौ गुणा तीन', AppLanguage.hindi), '500×3');
      expect(sum('एक हज़ार माइनस दो सौ', AppLanguage.hindi), '1000−200');
      expect(sum('बारह सौ पचास भाग पांच', AppLanguage.hindi), '1250÷5');
    });

    test('Kannada', () {
      expect(sum('ಎರಡು ನೂರ ಐವತ್ತು ಪ್ಲಸ್ ನೂರ ಎಂಬತ್ತು', AppLanguage.kannada), '250+180');
      expect(sum('ಐನೂರು ಗುಣಿಸು ಮೂರು', AppLanguage.kannada), '500×3');
      expect(sum('ಸಾವಿರ ಭಾಗಿಸು ನಾಲ್ಕು', AppLanguage.kannada), '1000÷4');
    });

    test('Tamil', () {
      expect(sum('இருநூற்று ஐம்பது கூட்டல் நூற்று எண்பது', AppLanguage.tamil), '250+180');
      expect(sum('ஐநூறு பெருக்கல் மூன்று', AppLanguage.tamil), '500×3');
      expect(sum('ஆயிரம் வகுத்தல் நான்கு', AppLanguage.tamil), '1000÷4');
    });
  });
}
