/// The shop calculator's brain: keys in, expression and answer out.
/// No Flutter here, so every rule can be tested on its own.
///
/// Rules:
/// - × and ÷ are worked out before + and − (250 + 180 × 3 = 790).
/// - % works like a shop calculator: 500 + 10% = 550, 500 − 10% = 450,
///   500 × 10% = 50, and 50% alone = 0.5.
/// - Every answer from = is added to GT (grand total).
/// - AC clears the sum; AC again on an empty screen clears GT.
library;

const plus = '+';
const minus = '−';
const times = '×';
const divide = '÷';
const percent = '%';
const operators = {plus, minus, times, divide};

/// One finished calculation in the history list.
class CalcEntry {
  const CalcEntry({
    required this.expression,
    required this.result,
    required this.at,
  });

  final String expression;
  final double result;
  final DateTime at;

  Map<String, dynamic> toJson() => {
    'e': expression,
    'r': result,
    't': at.millisecondsSinceEpoch,
  };

  static CalcEntry? fromJson(Object? json) {
    if (json is! Map) return null;
    final e = json['e'];
    final r = json['r'];
    final t = json['t'];
    if (e is! String || r is! num || t is! int) return null;
    return CalcEntry(
      expression: e,
      result: r.toDouble(),
      at: DateTime.fromMillisecondsSinceEpoch(t),
    );
  }
}

class CalculatorEngine {
  static const maxHistory = 50;
  static const _maxDigits = 12;
  static const _maxLength = 80;

  /// What is being typed (or the last answer, right after =).
  String expression = '';

  /// The sum that produced the answer, shown above it after =.
  String evaluatedExpression = '';

  /// True right after =: a digit starts a new sum, an operator continues from the answer.
  bool justEvaluated = false;

  /// Shown instead of an answer when the sum cannot be worked out.
  String? error;

  double grandTotal = 0;
  double memory = 0;
  final List<CalcEntry> history = [];

  /// Goes up by one every time = produces an answer (including a fixed sum
  /// that replaces an old answer), so the screen knows when to speak.
  int answerCount = 0;

  /// The answer right after =.
  double? get result => justEvaluated ? evaluate(expression) : null;

  /// The answer so far while typing (empty until there is an operator).
  String get preview {
    if (justEvaluated || !_hasOperatorAfterFirst(expression)) return '';
    final value = evaluate(expression);
    return value == null ? '' : formatNumber(value);
  }

  // ---- fixing a mistake in the middle of a sum ------------------------------

  /// Which piece of the sum (number or operator) is picked for fixing, if any.
  int? selected;

  /// True right after picking a number: the first digit typed replaces it.
  bool _freshPick = false;

  /// True while re-editing the last answered sum: the next = replaces that
  /// answer in history and GT instead of adding a second one.
  bool _replacingLast = false;

  /// The sum split into pieces for the screen: numbers ("250", "10%", "−5")
  /// and operators ("+", "×").
  List<String> get pieces => splitPieces(expression);

  /// Brings the last answered sum back so a wrong number can be fixed.
  void editLastSum() {
    if (!justEvaluated || evaluatedExpression.isEmpty) return;
    expression = evaluatedExpression;
    justEvaluated = false;
    error = null;
    selected = null;
    _replacingLast = true;
  }

  /// Picks piece [index] for fixing; picking it again lets go.
  void select(int index) {
    if (justEvaluated || index < 0 || index >= pieces.length) return;
    if (selected == index) {
      selected = null;
      return;
    }
    selected = index;
    _freshPick = true;
    error = null;
  }

  /// Handles one key. Returns a short message to show, if any.
  String? press(String key) {
    if (key != 'AC') error = null;
    if (selected != null) {
      if (_editSelected(key)) return null;
      selected = null; // any other key finishes the fix and works as usual
    }
    switch (key) {
      case 'AC':
        return _allClear();
      case '⌫':
        _backspace();
        return null;
      case '=':
        return _equals();
      case percent:
        _percent();
        return null;
      case '.':
        _dot();
        return null;
      case 'MC':
        memory = 0;
        return 'Memory cleared';
      case 'MR':
        return _insertNumber(memory);
      case 'M+':
      case 'M−':
        return _memoryAdd(key == 'M+' ? 1 : -1);
      case 'GT':
        return _insertNumber(grandTotal);
    }
    if (operators.contains(key)) {
      _operator(key);
      return null;
    }
    if (key == '00' || RegExp(r'^[0-9]$').hasMatch(key)) {
      _digits(key);
      return null;
    }
    return null;
  }

  /// Works out a whole sum at once (used by voice). Same as typing it and pressing =.
  String? calculate(String sum) {
    expression = sum;
    justEvaluated = false;
    error = null;
    selected = null;
    _replacingLast = false;
    return _equals();
  }

  /// Puts a number (e.g. from history) on the screen as a new sum.
  void useNumber(double value) {
    expression = formatPlain(value);
    justEvaluated = false;
    error = null;
    selected = null;
    _replacingLast = false;
  }

  /// Applies [key] to the picked piece. Returns false if the key is not an
  /// editing key (it then finishes the fix and is handled normally).
  bool _editSelected(String key) {
    final parts = pieces;
    final i = selected!;
    if (i >= parts.length) {
      selected = null;
      return false;
    }
    final piece = parts[i];
    final isOperator = operators.contains(piece) && !(i == 0 && piece == minus);

    if (isOperator) {
      if (operators.contains(key)) {
        parts[i] = key; // change + to −, × to ÷ ...
      } else if (key == '⌫') {
        // Remove the operator and the number after it.
        parts.removeAt(i);
        if (i < parts.length) parts.removeAt(i);
        selected = null;
      } else if (key == '=' || key == 'AC') {
        return false;
      } else {
        return true; // digits do nothing on an operator
      }
      expression = parts.join();
      return true;
    }

    // A number is picked.
    final isDigitKey =
        key == '00' || key == '.' || RegExp(r'^[0-9]$').hasMatch(key);
    if (isDigitKey) {
      var number = piece;
      if (_freshPick) {
        number = number.startsWith(minus) ? minus : '';
        _freshPick = false;
      }
      parts[i] = _typeInto(number, key);
    } else if (key == percent) {
      parts[i] = piece.endsWith(percent)
          ? piece.substring(0, piece.length - 1)
          : '$piece$percent';
      _freshPick = false;
    } else if (key == '⌫') {
      _freshPick = false;
      final shorter = piece.substring(0, piece.length - 1);
      if (shorter.isEmpty || shorter == minus) {
        // Number gone: remove it with the operator before it (or after, if first).
        parts.removeAt(i);
        if (i > 0) {
          parts.removeAt(i - 1);
        } else if (parts.isNotEmpty) {
          parts.removeAt(0);
        }
        selected = null;
      } else {
        parts[i] = shorter;
      }
    } else if (operators.contains(key) && i > 0) {
      parts[i - 1] = key; // change the operator in front of the picked number
    } else {
      return false;
    }
    expression = parts.join();
    if (expression.isEmpty) selected = null;
    return true;
  }

  /// Types one digit key into a number, with the same rules as normal typing.
  String _typeInto(String number, String key) {
    if (number.endsWith(percent)) return number;
    final sign = number.startsWith(minus) ? minus : '';
    var digits = number.substring(sign.length);
    final count = digits.replaceAll('.', '').length;
    if (key == '.') {
      if (!digits.contains('.')) digits = digits.isEmpty ? '0.' : '$digits.';
    } else if (count >= _maxDigits) {
      // full
    } else if (key == '00') {
      if (digits.isEmpty || digits == '0') {
        digits = '0';
      } else {
        digits += count + 2 > _maxDigits ? '0' : '00';
      }
    } else if (digits == '0') {
      digits = key;
    } else {
      digits += key;
    }
    return '$sign$digits';
  }

  // ---- keys --------------------------------------------------------------

  String? _allClear() {
    final screenEmpty = expression.isEmpty && error == null;
    expression = '';
    evaluatedExpression = '';
    justEvaluated = false;
    error = null;
    selected = null;
    _replacingLast = false;
    if (screenEmpty && grandTotal != 0) {
      grandTotal = 0;
      return 'GT cleared';
    }
    return null;
  }

  void _backspace() {
    justEvaluated = false;
    if (expression.isNotEmpty) {
      expression = expression.substring(0, expression.length - 1);
    }
  }

  void _digits(String key) {
    _startFreshIfAnswered();
    if (expression.length >= _maxLength) return;
    if (expression.endsWith(percent)) return;
    final number = _trailingNumber().replaceAll(minus, '');
    final digitCount = number.replaceAll('.', '').length;
    if (digitCount >= _maxDigits) return;
    if (key == '00') {
      if (number.isEmpty || number == '0') {
        if (number.isEmpty) expression += '0';
        return;
      }
      expression += digitCount + 2 > _maxDigits ? '0' : '00';
      return;
    }
    if (number == '0') {
      expression = expression.substring(0, expression.length - 1) + key;
      return;
    }
    expression += key;
  }

  void _dot() {
    _startFreshIfAnswered();
    if (expression.endsWith(percent)) return;
    final number = _trailingNumber().replaceAll(minus, '');
    if (number.contains('.')) return;
    expression += number.isEmpty ? '0.' : '.';
  }

  void _operator(String op) {
    justEvaluated = false;
    if (expression.length >= _maxLength) return;
    if (expression.isEmpty) {
      if (op == minus) expression = minus;
      return;
    }
    final last = expression[expression.length - 1];
    if (operators.contains(last)) {
      if (expression.length == 1) {
        // Only a leading minus so far: another operator makes no sense.
        if (op != minus) expression = '';
        return;
      }
      expression = expression.substring(0, expression.length - 1) + op;
      return;
    }
    expression += op;
  }

  void _percent() {
    justEvaluated = false;
    if (expression.isEmpty) return;
    final last = expression[expression.length - 1];
    if (RegExp(r'[0-9.]').hasMatch(last)) expression += percent;
  }

  String? _equals() {
    if (justEvaluated) return null;
    final sum = _withoutTrailingOperator(expression);
    if (sum.isEmpty || sum == minus) return null;
    final tokens = _tokenize(sum);
    if (tokens == null) {
      error = 'Check the sum';
      return null;
    }
    final value = _evaluateTokens(tokens);
    if (value == null) return null;
    selected = null;
    if (_replacingLast && history.isNotEmpty) {
      // A fixed sum replaces its old answer, so GT does not count it twice.
      grandTotal = _clean(grandTotal - history.first.result) ?? grandTotal;
      history.removeAt(0);
    }
    _replacingLast = false;
    history.insert(
      0,
      CalcEntry(expression: sum, result: value, at: DateTime.now()),
    );
    if (history.length > maxHistory) {
      history.removeRange(maxHistory, history.length);
    }
    grandTotal = _clean(grandTotal + value) ?? grandTotal;
    answerCount++;
    evaluatedExpression = sum;
    expression = formatPlain(value);
    justEvaluated = true;
    return null;
  }

  String? _memoryAdd(int sign) {
    final value = evaluate(expression);
    if (value == null) return 'Nothing to add to memory';
    memory = _clean(memory + sign * value) ?? memory;
    return sign > 0 ? 'Added to memory' : 'Taken from memory';
  }

  String? _insertNumber(double value) {
    final text = formatPlain(value);
    if (justEvaluated || expression.isEmpty) {
      expression = text;
      justEvaluated = false;
      return null;
    }
    final last = expression[expression.length - 1];
    if (operators.contains(last)) {
      if (value >= 0) {
        expression += text;
        return null;
      }
      // A negative number after + or − flips that sign.
      final positive = formatPlain(-value);
      if (last == plus || last == minus) {
        final flipped = last == plus ? minus : plus;
        expression =
            expression.substring(0, expression.length - 1) + flipped + positive;
        return null;
      }
      return 'Cannot use a negative number here';
    }
    // Replace the number being typed.
    final number = _trailingNumber(includePercent: true);
    final start = expression.length - number.length;
    final before = expression.substring(0, start);
    if (before.isEmpty || value >= 0) {
      expression = before + text;
    } else {
      return 'Cannot use a negative number here';
    }
    return null;
  }

  void _startFreshIfAnswered() {
    selected = null;
    if (justEvaluated) {
      expression = '';
      evaluatedExpression = '';
      justEvaluated = false;
    }
  }

  /// The number at the end of the expression ("12.5" in "3+12.5").
  String _trailingNumber({bool includePercent = false}) {
    var end = expression.length;
    if (includePercent && expression.endsWith(percent)) end -= 1;
    var start = end;
    while (start > 0 && RegExp(r'[0-9.]').hasMatch(expression[start - 1])) {
      start--;
    }
    // A leading minus belongs to the first number.
    if (start == 1 && expression[0] == minus) start = 0;
    return expression.substring(
      start,
      includePercent ? expression.length : end,
    );
  }

  // ---- working out a sum -------------------------------------------------

  /// The value of [sum], or null if it is not complete or cannot be worked out.
  double? evaluate(String sum) {
    final trimmed = _withoutTrailingOperator(sum);
    if (trimmed.isEmpty || trimmed == minus) return null;
    final tokens = _tokenize(trimmed);
    if (tokens == null) return null;
    final saved = error;
    final value = _evaluateTokens(tokens);
    error = saved;
    return value;
  }

  double? _evaluateTokens(List<_Token> tokens) {
    final first = tokens.first as _Num;
    var sum = 0.0;
    var term = first.percent ? first.value / 100 : first.value;
    for (var i = 1; i + 1 < tokens.length; i += 2) {
      final op = (tokens[i] as _Op).symbol;
      final number = tokens[i + 1] as _Num;
      if (op == plus || op == minus) {
        sum += term;
        final value = number.percent ? sum * number.value / 100 : number.value;
        term = op == plus ? value : -value;
      } else {
        final value = number.percent ? number.value / 100 : number.value;
        if (op == divide) {
          if (value == 0) {
            error = 'Cannot divide by zero';
            return null;
          }
          term /= value;
        } else {
          term *= value;
        }
      }
    }
    final value = _clean(sum + term);
    if (value == null) error = 'Number too big';
    return value;
  }

  List<_Token>? _tokenize(String sum) {
    final tokens = <_Token>[];
    var i = 0;
    while (i < sum.length) {
      final ch = sum[i];
      if (operators.contains(ch) && !(tokens.isEmpty && ch == minus)) {
        if (tokens.isEmpty || tokens.last is _Op) return null;
        tokens.add(_Op(ch));
        i++;
        continue;
      }
      var negative = false;
      if (ch == minus) {
        negative = true;
        i++;
      }
      final start = i;
      while (i < sum.length && RegExp(r'[0-9.]').hasMatch(sum[i])) {
        i++;
      }
      final text = sum.substring(start, i);
      final value = double.tryParse(text);
      if (text.isEmpty || value == null) return null;
      var isPercent = false;
      if (i < sum.length && sum[i] == percent) {
        isPercent = true;
        i++;
      }
      if (tokens.isNotEmpty && tokens.last is _Num) return null;
      tokens.add(_Num(negative ? -value : value, percent: isPercent));
    }
    if (tokens.isEmpty || tokens.last is _Op) return null;
    return tokens;
  }

  static String _withoutTrailingOperator(String sum) {
    if (sum.isNotEmpty && operators.contains(sum[sum.length - 1])) {
      return sum.substring(0, sum.length - 1);
    }
    return sum;
  }

  static bool _hasOperatorAfterFirst(String sum) {
    for (var i = 1; i < sum.length; i++) {
      if (operators.contains(sum[i]) || sum[i] == percent) return true;
    }
    return false;
  }

  /// Removes tiny floating-point noise (0.1 + 0.2 = 0.3, not 0.30000000000000004).
  static double? _clean(double value) {
    if (!value.isFinite || value.abs() >= 1e15) return null;
    final rounded = double.parse(value.toStringAsFixed(8));
    return rounded == 0 ? 0 : rounded;
  }

  // ---- saving on the phone ------------------------------------------------

  Map<String, dynamic> toJson() => {
    'gt': grandTotal,
    'memory': memory,
    'history': [for (final entry in history) entry.toJson()],
  };

  void restore(Map<String, dynamic>? json) {
    if (json == null) return;
    final gt = json['gt'];
    final mem = json['memory'];
    final items = json['history'];
    if (gt is num) grandTotal = gt.toDouble();
    if (mem is num) memory = mem.toDouble();
    if (items is List) {
      history
        ..clear()
        ..addAll(
          items.map(CalcEntry.fromJson).whereType<CalcEntry>().take(maxHistory),
        );
    }
  }
}

sealed class _Token {
  const _Token();
}

class _Num extends _Token {
  const _Num(this.value, {this.percent = false});

  final double value;
  final bool percent;
}

class _Op extends _Token {
  const _Op(this.symbol);

  final String symbol;
}

// ---- number formatting ----------------------------------------------------

/// A number as the calculator types it: no commas, − for negative.
String formatPlain(double value) {
  if (value == 0) return '0';
  final negative = value < 0;
  final abs = value.abs();
  String text;
  if (abs == abs.roundToDouble()) {
    text = abs.toStringAsFixed(0);
  } else {
    text = abs.toStringAsFixed(8).replaceFirst(RegExp(r'\.?0+$'), '');
  }
  return negative ? '$minus$text' : text;
}

/// A number for people to read, with Indian commas: 12,34,567.5
String formatNumber(double value) => groupIndian(formatPlain(value));

/// Adds Indian commas to every number inside [text] (e.g. "100000+2500").
String groupIndian(String text) {
  return text.replaceAllMapped(RegExp(r'[0-9]+'), (match) {
    final start = match.start;
    // Digits after a decimal point are not grouped.
    if (start > 0 && text[start - 1] == '.') return match[0]!;
    return _indianDigits(match[0]!);
  });
}

String _indianDigits(String digits) {
  if (digits.length <= 3) return digits;
  final last3 = digits.substring(digits.length - 3);
  var rest = digits.substring(0, digits.length - 3);
  final parts = <String>[];
  while (rest.length > 2) {
    parts.insert(0, rest.substring(rest.length - 2));
    rest = rest.substring(0, rest.length - 2);
  }
  if (rest.isNotEmpty) parts.insert(0, rest);
  return '${parts.join(',')},$last3';
}

/// The sum with spaces and commas, for the screen: "1,00,000 + 2,500 × 3"
String displaySum(String sum) {
  final spaced = sum.replaceAllMapped(
    RegExp('(?<=[0-9.%])([${RegExp.escape(operators.join())}])'),
    (m) => ' ${m[1]} ',
  );
  return groupIndian(spaced);
}

const _ones = [
  'zero',
  'one',
  'two',
  'three',
  'four',
  'five',
  'six',
  'seven',
  'eight',
  'nine',
  'ten',
  'eleven',
  'twelve',
  'thirteen',
  'fourteen',
  'fifteen',
  'sixteen',
  'seventeen',
  'eighteen',
  'nineteen',
];
const _tens = [
  '',
  '',
  'twenty',
  'thirty',
  'forty',
  'fifty',
  'sixty',
  'seventy',
  'eighty',
  'ninety',
];

/// Splits a sum into numbers and operators: "−5+10%×2" -> ["−5", "+", "10%", "×", "2"].
List<String> splitPieces(String sum) {
  final pieces = <String>[];
  final number = StringBuffer();
  for (var i = 0; i < sum.length; i++) {
    final ch = sum[i];
    if (operators.contains(ch) && !(i == 0 && ch == minus)) {
      if (number.isNotEmpty) {
        pieces.add(number.toString());
        number.clear();
      }
      pieces.add(ch);
    } else {
      number.write(ch);
    }
  }
  if (number.isNotEmpty) pieces.add(number.toString());
  return pieces;
}

/// A whole calculation read out: "six plus five minus three equals eight".
String spokenCalculation(String sum, double answer) {
  final pieces = splitPieces(sum);
  if (pieces.length <= 1) return spokenNumber(answer);
  final words = <String>[];
  for (final piece in pieces) {
    switch (piece) {
      case plus:
        words.add('plus');
      case minus:
        words.add('minus');
      case times:
        words.add('into');
      case divide:
        words.add('divided by');
      default:
        final isPercent = piece.endsWith(percent);
        final digits = piece.replaceAll(percent, '').replaceAll(minus, '-');
        final value = double.tryParse(digits);
        if (value == null) continue;
        words.add(spokenNumber(value) + (isPercent ? ' percent' : ''));
    }
  }
  return '${words.join(' ')} equals ${spokenNumber(answer)}';
}

/// How the phone should say a number out loud, fully in words and the
/// Indian way: 10,00,10,000 -> "ten crore ten thousand".
/// (The phone's own voice reads long numbers digit by digit, "one oh oh oh...",
/// and a lone 0 as the letter "O", so QBOX writes the words itself.)
String spokenNumber(double value) {
  final parts = formatPlain(value.abs()).split('.');
  var spoken = indianWords(int.parse(parts[0]));
  if (parts.length > 1) {
    final decimals = [for (final d in parts[1].split('')) _ones[int.parse(d)]];
    spoken += ' point ${decimals.join(' ')}';
  }
  return value < 0 ? 'minus $spoken' : spoken;
}

/// A whole number in words with crore, lakh, thousand and hundred.
String indianWords(int n) {
  if (n == 0) return 'zero';
  final words = <String>[];
  final crore = n ~/ 10000000;
  var rest = n % 10000000;
  if (crore > 0) words.add('${indianWords(crore)} crore');
  final lakh = rest ~/ 100000;
  rest %= 100000;
  if (lakh > 0) words.add('${_below100(lakh)} lakh');
  final thousand = rest ~/ 1000;
  rest %= 1000;
  if (thousand > 0) words.add('${_below100(thousand)} thousand');
  final hundred = rest ~/ 100;
  rest %= 100;
  if (hundred > 0) words.add('${_ones[hundred]} hundred');
  if (rest > 0) words.add(_below100(rest));
  return words.join(' ');
}

String _below100(int n) {
  if (n < 20) return _ones[n];
  final unit = n % 10;
  return unit == 0 ? _tens[n ~/ 10] : '${_tens[n ~/ 10]} ${_ones[unit]}';
}
