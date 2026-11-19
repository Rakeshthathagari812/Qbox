import 'package:flutter_test/flutter_test.dart';
import 'package:qbox_app/calculator/calculator_engine.dart';
import 'package:qbox_app/calculator/voice_math.dart';

double? answer(String spoken) {
  final sum = parseSpokenMath(spoken);
  return sum == null ? null : CalculatorEngine().evaluate(sum);
}

void main() {
  test('digits and operator words', () {
    expect(parseSpokenMath('250 plus 180 into 3'), '250+180×3');
    expect(answer('250 plus 180 into 3'), 790);
    expect(answer('1000 minus 250'), 750);
    expect(answer('500 less 50'), 450);
    expect(answer('12 times 4'), 48);
    expect(answer('100 by 4'), 25);
    expect(answer('100 divided by 8'), 12.5);
    expect(answer('6 multiplied by 7'), 42);
  });

  test('symbols the phone may write instead of words', () {
    expect(answer('250 + 180 x 3'), 790);
    expect(answer('3x4'), 12);
    expect(answer('100/4'), 25);
    expect(answer('10-4'), 6);
    expect(answer('₹1,500 + ₹250'), 1750);
  });

  test('number words, including Indian price style', () {
    expect(answer('two hundred fifty plus one hundred eighty'), 430);
    expect(answer('two fifty plus one eighty'), 430);
    expect(answer('twelve fifty minus fifty'), 1200);
    expect(answer('two hundred and fifty'), 250);
    expect(answer('twenty-five into four'), 100);
    expect(answer('one thousand five hundred by four'), 375);
    expect(answer('a hundred plus ninety nine'), 199);
    expect(answer('two fifty five plus five'), 260);
  });

  test('lakh, crore and thousand', () {
    expect(answer('2 lakh minus 25 thousand'), 175000);
    expect(answer('two lakh fifty thousand'), 250000);
    expect(answer('1.5 lakh plus 50000'), 200000);
    expect(answer('one crore by 100'), 100000);
  });

  test('decimals', () {
    expect(answer('two point five into four'), 10);
    expect(answer('12.5 plus 7.5'), 20);
  });

  test('percent', () {
    expect(answer('500 plus 10 percent'), 550);
    expect(answer('18 percent of 1200'), 216);
    expect(answer('2000 minus 5 per cent'), 1900);
  });

  test('"o" and "oh" heard for zero', () {
    expect(answer('10 minus o'), 10);
    expect(answer('o plus 5'), 5);
    expect(answer('five point o five'), 5.05);
    expect(answer('oh what is 2 plus 3'), 5); // "oh" not next to a number: ignored
  });

  test('extra words are ignored', () {
    expect(answer('what is 250 plus 180'), 430);
    expect(answer('250 rupees plus 180 rupees equals'), 430);
    expect(answer('Calculate 40 into 3?'), 120);
  });

  test('a single number, a leading minus and a trailing operator', () {
    expect(parseSpokenMath('five hundred'), '500');
    expect(answer('minus 50 plus 80'), 30);
    expect(parseSpokenMath('250 plus'), '250');
  });

  test('nonsense gives null instead of a wrong answer', () {
    expect(parseSpokenMath(''), isNull);
    expect(parseSpokenMath('hello qbox'), isNull);
    expect(parseSpokenMath('plus plus'), isNull);
    expect(parseSpokenMath('250 180'), isNull);
    expect(parseSpokenMath('into 5'), isNull);
  });
}
