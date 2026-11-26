/// Turns what the shopkeeper says into a sum the calculator understands.
///
///   "250 plus 180 into 3"               -> 250+180×3
///   "two fifty plus one eighty"          -> 250+180
///   "one thousand five hundred by 4"     -> 1500÷4
///   "18 percent of 1200"                 -> 18%×1200
///   "2 lakh minus 25 thousand"           -> 200000−25000
///
/// English only for now. Returns null when no sum can be made out.
library;

import 'calculator_engine.dart';

const _units = {
  'zero': 0,
  'one': 1,
  'two': 2,
  'three': 3,
  'four': 4,
  'five': 5,
  'six': 6,
  'seven': 7,
  'eight': 8,
  'nine': 9,
  'ten': 10,
  'eleven': 11,
  'twelve': 12,
  'thirteen': 13,
  'fourteen': 14,
  'fifteen': 15,
  'sixteen': 16,
  'seventeen': 17,
  'eighteen': 18,
  'nineteen': 19,
  'twenty': 20,
  'thirty': 30,
  'forty': 40,
  'fourty': 40,
  'fifty': 50,
  'sixty': 60,
  'seventy': 70,
  'eighty': 80,
  'ninety': 90,
};

const _scales = {
  'hundred': 100,
  'thousand': 1000,
  'lakh': 100000,
  'lakhs': 100000,
  'lac': 100000,
  'lacs': 100000,
  'crore': 10000000,
  'crores': 10000000,
};

const _operatorWords = {
  'plus': plus,
  'add': plus,
  '+': plus,
  'minus': minus,
  'less': minus,
  'subtract': minus,
  '-': minus,
  minus: minus,
  'into': times,
  'times': times,
  'multiply': times,
  'multiplied': times,
  '×': times,
  '*': times,
  'x': times,
  'by': divide,
  'divide': divide,
  'divided': divide,
  'over': divide,
  '÷': divide,
  '/': divide,
};

/// "plus 10", "into 3": does it carry on from the answer before?
bool startsWithOperator(String spoken) {
  final words = _words(spoken);
  return words.length > 1 && _operatorWords.containsKey(words.first);
}

/// "20 plus", "18 percent of": must more follow?
bool endsWithOperator(String spoken) {
  final words = _words(spoken);
  return words.length > 1 && (words.last == 'of' || _operatorWords.containsKey(words.last));
}

/// "subtract 120 from 500", "take 120 from 500" -> "500 minus 120".
final _takeFrom = RegExp(r'^\s*(?:please\s+)?(?:subtract|remove|take away|take|deduct|minus|less)\s+(.+?)\s+from\s+(.+?)\s*$');

String? parseSpokenMath(String spoken) {
  final from = _takeFrom.firstMatch(spoken.toLowerCase());
  final words = _words(from == null ? spoken : '${from[2]} minus ${from[1]}');
  final parts = <Object>[]; // double (number), String (operator) or percent
  final number = _NumberWords();

  void flush() {
    final value = number.take();
    if (value != null) parts.add(value);
  }

  for (var i = 0; i < words.length; i++) {
    final word = words[i];
    final next = i + 1 < words.length ? words[i + 1] : '';

    if (word == 'point' || word == '.') {
      number.point();
      continue;
    }
    // The phone often writes a spoken "zero" as "o" or "oh" ("10 minus o").
    // Only counted as 0 next to numbers or operators, so "oh, what is..." is ignored.
    if ((word == 'o' || word == 'oh') &&
        (number.started ||
            _isNumberWord(next) ||
            _operatorWords.containsKey(next) ||
            (parts.isNotEmpty &&
                parts.last is String &&
                parts.last != percent))) {
      number.add(0);
      continue;
    }
    if (word == 'a' && _scales.containsKey(next)) {
      number.add(1); // "a hundred", "a lakh"
      continue;
    }
    final unit = _units[word];
    if (unit != null) {
      number.add(unit.toDouble());
      continue;
    }
    final scale = _scales[word];
    if (scale != null) {
      number.scale(scale.toDouble());
      continue;
    }
    final literal = double.tryParse(word);
    if (literal != null) {
      // "250 180" is two numbers, not 430 (unless it follows "point").
      if (number.endsOnValue && !number.inDecimals) flush();
      number.add(literal);
      continue;
    }
    if (word == 'and') {
      // "two hundred and fifty" is one number; "twenty and thirty" is a sum.
      if (number.started && number.endsOnValue && _isNumberWord(next)) {
        flush();
        parts.add(plus);
      }
      continue;
    }

    // Anything else ends the number being spoken.
    flush();
    if (word == 'percent' || word == '%') {
      parts.add(percent);
    } else if (word == 'of' && parts.isNotEmpty && parts.last == percent) {
      parts.add(times); // "18 percent of 1200"
    } else if (_operatorWords.containsKey(word)) {
      // "multiplied by" / "divided by": the "by" is already covered.
      if (word == 'by' &&
          parts.isNotEmpty &&
          (parts.last == times || parts.last == divide)) {
        continue;
      }
      parts.add(_operatorWords[word]!);
    }
    // Other words ("rupees", "what is", "equals"...) are ignored.
  }
  flush();
  return _build(parts);
}

bool _isNumberWord(String word) =>
    word == 'point' ||
    _units.containsKey(word) ||
    _scales.containsKey(word) ||
    double.tryParse(word) != null;

/// Lower-case words, with symbols split off and number commas removed.
List<String> _words(String spoken) {
  var text = spoken.toLowerCase();
  text = text.replaceAll(RegExp(r'(?<=[0-9]),(?=[0-9])'), ''); // 1,500 -> 1500
  text = text.replaceAll(RegExp(r'(?<=[a-z])-(?=[a-z])'), ' '); // twenty-five
  text = text.replaceAll(RegExp(r'(?<=[0-9])\s*x\s*(?=[0-9])'), ' x '); // 3x4
  text = text
      .replaceAll('per cent', 'percent')
      .replaceAll('percentage', 'percent');
  text = text.replaceAll(RegExp(r'₹|\brs\.?|\brupees?\b'), ' ');
  text = text.replaceAllMapped(RegExp(r'([+\-*/×÷%−])'), (m) => ' ${m[1]} ');
  // A dot between digits is a decimal point; any other dot is punctuation.
  text = text.replaceAll(RegExp(r'(?<![0-9])\.|\.(?![0-9])'), ' ');
  text = text.replaceAll(
    RegExp(
      r"[?!,;:'"
      '"]',
    ),
    ' ',
  );
  return text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
}

/// Checks the pieces form number, operator, number... and writes the sum.
String? _build(List<Object> parts) {
  final out = StringBuffer();
  var expectNumber = true;
  var sawNumber = false;
  for (var i = 0; i < parts.length; i++) {
    final part = parts[i];
    if (part is double) {
      if (!expectNumber) return null; // two numbers with nothing between
      out.write(formatPlain(part));
      expectNumber = false;
      sawNumber = true;
    } else if (part == percent) {
      if (expectNumber) return null;
      out.write(percent);
    } else {
      if (expectNumber) {
        // Only a leading minus is allowed before the first number.
        if (out.isEmpty && part == minus) {
          out.write(minus);
          continue;
        }
        return null;
      }
      out.write(part);
      expectNumber = true;
    }
  }
  if (!sawNumber) return null;
  var sum = out.toString();
  if (expectNumber &&
      sum.isNotEmpty &&
      operators.contains(sum[sum.length - 1])) {
    sum = sum.substring(0, sum.length - 1); // "250 plus" -> 250
  }
  return sum;
}

/// Builds one number from spoken words: "two lakh fifty thousand",
/// "twelve fifty" (= 1250, the Indian way of saying prices), "two point five".
class _NumberWords {
  double _total = 0;
  double _current = 0;
  bool _has = false;
  bool _lastWasSmall = false;
  String? _decimals;

  bool _endsOnValue = false;

  /// True when the last word was a number (not "lakh", "thousand"...).
  bool get endsOnValue => _endsOnValue;
  bool get inDecimals => _decimals != null;

  /// True once any part of a number has been heard.
  bool get started => _has;

  void add(double value) {
    if (_decimals != null) {
      _decimals = _decimals! + formatPlain(value).replaceAll('.', '');
      _has = true;
      return;
    }
    final isWhole = value == value.roundToDouble();
    if (_lastWasSmall &&
        isWhole &&
        value >= 10 &&
        value < 100 &&
        _current > 0 &&
        _current < 100) {
      _current = _current * 100 + value; // "two fifty" -> 250
    } else {
      _current += value;
    }
    _has = true;
    _lastWasSmall = isWhole && value < 100;
    _endsOnValue = true;
  }

  void point() {
    _decimals ??= '';
    _has = true;
  }

  void scale(double size) {
    _applyDecimals();
    if (size == 100) {
      _current = (_current == 0 ? 1 : _current) * 100;
    } else {
      _total += (_current == 0 ? 1 : _current) * size;
      _current = 0;
    }
    _has = true;
    _lastWasSmall = false;
    _endsOnValue = false;
  }

  double? take() {
    if (!_has) return null;
    _applyDecimals();
    final value = _total + _current;
    _total = 0;
    _current = 0;
    _has = false;
    _lastWasSmall = false;
    _endsOnValue = false;
    return value;
  }

  void _applyDecimals() {
    final digits = _decimals;
    if (digits == null) return;
    if (digits.isNotEmpty) _current += double.parse('0.$digits');
    _decimals = null;
  }
}
