import 'package:flutter_test/flutter_test.dart';
import 'package:qbox_app/calculator/calculator_engine.dart';

/// Presses keys one by one; "250+180×3=" or a list for multi-letter keys.
CalculatorEngine typed(Object keys, [CalculatorEngine? engine]) {
  final calc = engine ?? CalculatorEngine();
  final list = keys is String ? keys.split('') : keys as List<String>;
  for (final key in list) {
    calc.press(key);
  }
  return calc;
}

void main() {
  group('sums', () {
    test('× and ÷ before + and −', () {
      expect(typed('250+180×3=').result, 790);
      expect(typed('10−2×3=').result, 4);
      expect(typed('100÷4+5=').result, 30);
    });

    test('decimals without floating-point noise', () {
      expect(typed('0.1+0.2=').result, 0.3);
      expect(typed('10÷4=').result, 2.5);
      expect(typed('1÷3=').expression, '0.33333333');
    });

    test('percent works like a shop calculator', () {
      expect(typed('500+10%=').result, 550);
      expect(typed('500−10%=').result, 450);
      expect(typed('500×10%=').result, 50);
      expect(typed('50%=').result, 0.5);
      expect(typed('200+100+10%=').result, 330);
    });

    test('negative first number and negative answers', () {
      expect(typed('−5+3=').result, -2);
      expect(typed('3−10=').expression, '−7');
    });

    test('dividing by zero shows a message', () {
      final calc = typed('5÷0=');
      expect(calc.error, 'Cannot divide by zero');
      expect(calc.history, isEmpty);
      expect(calc.grandTotal, 0);
    });

    test('preview while typing', () {
      final calc = typed('250+180×');
      expect(calc.preview, '430');
      calc.press('3');
      expect(calc.preview, '790');
      expect(typed('250').preview, '');
    });
  });

  group('typing rules', () {
    test('a second operator replaces the first', () {
      expect(typed('5+×2').expression, '5×2');
    });

    test('only one dot per number, and a leading dot becomes 0.', () {
      expect(typed('1.2.3').expression, '1.23');
      expect(typed('.5').expression, '0.5');
      expect(typed('3+.5=').result, 3.5);
    });

    test('00 key and leading zeros', () {
      expect(typed(['5', '00']).expression, '500');
      expect(typed(['00']).expression, '0');
      expect(typed('007').expression, '7');
    });

    test('backspace removes the last character', () {
      expect(typed('123⌫').expression, '12');
    });

    test('after =, a digit starts fresh and an operator continues', () {
      expect(typed('2+3=4').expression, '4');
      expect(typed('2+3=×2=').result, 10);
    });

    test('numbers are limited to 12 digits', () {
      expect(typed('1234567890123456').expression, '123456789012');
    });

    test('= twice does not count twice', () {
      final calc = typed('2+3==');
      expect(calc.history.length, 1);
      expect(calc.grandTotal, 5);
    });
  });

  group('GT (grand total)', () {
    test('adds every answer from =', () {
      final calc = typed('120+80=');
      typed('50×3=', calc);
      typed('300−20=', calc);
      expect(calc.grandTotal, 630);
      calc.press('GT');
      expect(calc.expression, '630');
    });

    test('a plain number with = is added too', () {
      expect(typed('500=').grandTotal, 500);
    });

    test('AC clears the screen, AC again clears GT', () {
      final calc = typed('100+50=');
      expect(calc.press('AC'), isNull);
      expect(calc.grandTotal, 150);
      expect(calc.press('AC'), 'GT cleared');
      expect(calc.grandTotal, 0);
    });
  });

  group('memory', () {
    test('M+, M−, MR and MC', () {
      final calc = typed('100');
      expect(calc.press('M+'), 'Added to memory');
      calc.press('AC');
      typed('30', calc);
      calc.press('M−');
      expect(calc.memory, 70);
      calc.press('AC');
      typed('5+', calc);
      calc.press('MR');
      expect(calc.expression, '5+70');
      expect(calc.press('MC'), 'Memory cleared');
      expect(calc.memory, 0);
    });

    test('M+ on an empty screen says nothing to add', () {
      expect(CalculatorEngine().press('M+'), 'Nothing to add to memory');
    });
  });

  group('history and saving', () {
    test('keeps only the last 50', () {
      final calc = CalculatorEngine();
      for (var i = 1; i <= 55; i++) {
        typed('$i+1=', calc);
      }
      expect(calc.history.length, 50);
      expect(calc.history.first.result, 56);
    });

    test('survives saving and loading', () {
      final calc = typed('120+80=');
      calc.press('M+');
      final restored = CalculatorEngine()..restore(calc.toJson());
      expect(restored.grandTotal, 200);
      expect(restored.memory, 200);
      expect(restored.history.single.expression, '120+80');
    });

    test('damaged saved data is ignored', () {
      final calc = CalculatorEngine()
        ..restore({'gt': 'x', 'history': [1, {'e': 5}]});
      expect(calc.grandTotal, 0);
      expect(calc.history, isEmpty);
    });
  });

  group('fixing a mistake in the middle', () {
    test('pick a number and type over it', () {
      final calc = typed('6+5−3');
      calc.select(2); // the 5
      typed('50', calc);
      expect(calc.expression, '6+50−3');
      calc.press('=');
      expect(calc.result, 53);
    });

    test('⌫ on a picked number removes it with its operator', () {
      final calc = typed('6+5−3');
      calc.select(2);
      calc.press('⌫'); // 5 has one digit: the number and its "+" go
      expect(calc.expression, '6−3');
      expect(calc.selected, isNull);
    });

    test('pick an operator and change it, or remove it with its number', () {
      final calc = typed('6+5−3');
      calc.select(3);
      calc.press(plus);
      expect(calc.expression, '6+5+3');
      calc.press('⌫');
      expect(calc.expression, '6+5');
    });

    test('an operator key on a picked number changes the operator before it', () {
      final calc = typed('10+4');
      calc.select(2);
      calc.press(times);
      expect(calc.expression, '10×4');
    });

    test('picking the same piece again lets go', () {
      final calc = typed('1+2');
      calc.select(0);
      calc.select(0);
      expect(calc.selected, isNull);
    });

    test('editing the last answer replaces it in history and GT', () {
      final calc = typed('100+50=');
      calc.editLastSum();
      expect(calc.expression, '100+50');
      calc.select(2);
      typed('60=', calc);
      expect(calc.result, 160);
      expect(calc.grandTotal, 160);
      expect(calc.history.length, 1);
    });

    test('AC while editing the last answer keeps the old one', () {
      final calc = typed('100+50=');
      calc.editLastSum();
      calc.press('AC');
      typed('5=', calc);
      expect(calc.grandTotal, 155);
      expect(calc.history.length, 2);
    });

    test('splitting a sum into pieces', () {
      expect(splitPieces('−5+10%×2'), ['−5', '+', '10%', '×', '2']);
      expect(splitPieces('7'), ['7']);
    });
  });

  group('formatting', () {
    test('Indian commas', () {
      expect(formatNumber(1234567.5), '12,34,567.5');
      expect(formatNumber(100000), '1,00,000');
      expect(formatNumber(-2500), '−2,500');
      expect(displaySum('100000+2500×3'), '1,00,000 + 2,500 × 3');
      expect(displaySum('−5+0.12345'), '−5 + 0.12345');
    });

    test('spoken answers', () {
      expect(spokenNumber(790), 'seven hundred ninety');
      expect(spokenNumber(-7), 'minus seven');
      expect(spokenNumber(0), 'zero');
      expect(spokenNumber(2.5), 'two point five');
      expect(spokenNumber(2.05), 'two point zero five');
      expect(spokenNumber(-0.5), 'minus zero point five');
      expect(spokenNumber(100010000), 'ten crore ten thousand');
      expect(spokenNumber(1234567), 'twelve lakh thirty four thousand five hundred sixty seven');
      expect(spokenNumber(100000), 'one lakh');
      expect(spokenNumber(1000000000), 'one hundred crore');
      expect(spokenNumber(15), 'fifteen');
      expect(spokenNumber(250.75), 'two hundred fifty point seven five');
      expect(spokenNumber(200000000000), 'twenty thousand crore');
    });

    test('whole calculation read out', () {
      expect(
        spokenCalculation('6+5−3+1+6', 15),
        'six plus five minus three plus one plus six equals fifteen',
      );
      expect(
        spokenCalculation('500×10%', 50),
        'five hundred into ten percent equals fifty',
      );
      expect(spokenCalculation('100÷4', 25), 'one hundred divided by four equals twenty five');
      expect(spokenCalculation('−5+3', -2), 'minus five plus three equals minus two');
      expect(spokenCalculation('500', 500), 'five hundred');
    });
  });
}
