/// Spoken numbers in Telugu, Hindi, Kannada and Tamil -> digits.
///
///   "రెండు వందల యాభై"        -> "250"
///   "ढाई सौ" / "साढ़े तीन सौ" -> "250" / "350"
///   "ಇಪ್ಪತ್ತೈದು"              -> "25"
///   "இருநூற்று ஐம்பது"       -> "250"
///   "౨౫౦" / "२५०"            -> "250"
///
/// Amounts are the most important words in a shop, and translation models
/// sometimes get them wrong, so numbers are turned into digits on the phone
/// first (works offline too). Everything else in the sentence is left as it is.
library;

import 'languages.dart';

/// Native-script digits (०-९, ౦-౯, ೦-೯, ௦-௯) -> 0-9.
String asciiDigits(String text) {
  const starts = [0x0966, 0x0C66, 0x0CE6, 0x0BE6];
  final out = StringBuffer();
  for (final rune in text.runes) {
    var ch = rune;
    for (final start in starts) {
      if (rune >= start && rune <= start + 9) ch = 0x30 + rune - start;
    }
    out.writeCharCode(ch);
  }
  return out.toString();
}

/// [text] with every spoken number in [language] written as digits.
String numbersToDigits(String text, AppLanguage language) {
  text = asciiDigits(text);
  final table = _tables[language];
  if (table == null) return text;

  final tokens = RegExp(r'\S+').allMatches(text).toList();
  final out = StringBuffer();
  var copiedUpTo = 0;
  final run = _Run();

  void flush() {
    if (run.isEmpty) return;
    final replacement = run.result();
    if (replacement != null) {
      out.write(text.substring(copiedUpTo, run.start));
      out.write(replacement);
      copiedUpTo = run.end;
    }
    run.clear();
  }

  for (final m in tokens) {
    final split = _splitPunctuation(m[0]!);
    final word = _normalise(split.core, language);
    final clock = table.clock[word];
    if (clock != null) {
      flush();
      out.write(text.substring(copiedUpTo, m.start));
      out.write('${split.before}$clock ${table.clockWord}${split.after}');
      copiedUpTo = m.end;
      continue;
    }
    var found = table.lookup(word);
    var suffix = '';
    if (found == null) {
      for (final s in table.suffixes) {
        if (word.length > s.length && word.endsWith(s)) {
          found = table.lookup(word.substring(0, word.length - s.length));
          if (found != null) {
            suffix = s;
            break;
          }
        }
      }
    }
    if (found == null || (split.before.isNotEmpty && !run.isEmpty)) {
      flush();
      if (found == null) continue;
    }
    if (!run.accepts(found)) flush();
    run.add(found, m.start, m.end, word: word, after: '$suffix${split.after}', before: split.before);
    // Punctuation or a case ending closes the number ("250, 180").
    if (split.after.isNotEmpty || suffix.isNotEmpty) flush();
  }
  flush();
  out.write(text.substring(copiedUpTo));
  return out.toString();
}

// ---------------------------------------------------------------------------

enum _Kind { number, scale, prefix }

class _Word {
  const _Word(this.kind, this.value);
  final _Kind kind;
  final double value;
}

/// Words that alone usually mean "a" / "give", not a number.
const _alone = {'ఒక', 'ఒక్క', 'एक', 'दो', 'ಒಂದು', 'ஒரு'};

class _Run {
  int start = 0;
  int end = 0;
  double total = 0;
  double current = 0;
  double pending = 0;
  int count = 0;
  String firstWord = '';
  String before = '';
  String after = '';

  bool get isEmpty => count == 0;

  void clear() {
    total = current = pending = 0;
    count = 0;
    after = before = firstWord = '';
  }

  /// Can [w] continue this number? ("ఇరవై ఐదు" yes; "ఐదు మూడు" no.)
  bool accepts(_Word w) {
    if (isEmpty || w.kind != _Kind.number || pending != 0) return true;
    final v = w.value;
    final c = current;
    if (c == 0) return v >= 1000 ? total % (v * 10) == 0 : true;
    if (c % 1000 == 0 && v < 1000) return true;
    if (c % 100 == 0 && v < 100) return true;
    return c % 10 == 0 && c % 100 >= 20 && v < 10 && v == v.roundToDouble();
  }

  void add(_Word w, int from, int to, {required String word, required String after, required String before}) {
    if (isEmpty) {
      start = from;
      firstWord = word;
      this.before = before;
    }
    end = to;
    count++;
    this.after = after;
    switch (w.kind) {
      case _Kind.prefix:
        pending += w.value;
      case _Kind.number:
        final v = w.value + (w.value < 100 ? pending : 0);
        pending = 0;
        if (v >= 1000) {
          total += v;
        } else {
          current += v;
        }
      case _Kind.scale:
        final s = w.value;
        if (s < 1000) {
          current = (current == 0 ? 1 : current) * s;
        } else {
          total += (current == 0 ? 1 : current) * s;
          current = 0;
        }
    }
  }

  /// The digits, or null to leave the words as they were.
  String? result() {
    if (count == 1 && _alone.contains(firstWord)) return null;
    final value = total + current;
    if (count == 1 && pending != 0) return null; // a lone "साढ़े"
    final whole = value == value.roundToDouble();
    final digits = whole
        ? value.round().toString()
        : value.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
    return '$before$digits$after';
  }
}

class _Split {
  const _Split(this.before, this.core, this.after);
  final String before;
  final String core;
  final String after;
}

final _punctuation = RegExp('^([.,!?;:"\'()\\[\\]“”‘’।॥-]*)(.*?)([.,!?;:"\'()\\[\\]“”‘’।॥-]*)\$');

_Split _splitPunctuation(String token) {
  final m = _punctuation.firstMatch(token)!;
  return _Split(m[1]!, m[2]!, m[3]!);
}

/// Hindi spellings vary (हज़ार/हजार, पाँच/पांच): compare without the dot and the moon.
String _normalise(String word, AppLanguage language) {
  word = word.replaceAll('‌', '').replaceAll('‍', '');
  if (language == AppLanguage.hindi) {
    word = word.replaceAll('़', '').replaceAll('ँ', 'ं');
  }
  return word;
}

class _Table {
  const _Table({
    required this.numbers,
    required this.scales,
    this.prefixes = const {},
    this.tens = const {},
    this.tensEndings = const {},
    this.suffixes = const [],
    this.clock = const {},
    this.clockWord = '',
  });

  final Map<String, double> numbers;
  final Map<String, double> scales;
  final Map<String, double> prefixes;

  /// Joined tens + unit words ("ಇಪ್ಪತ್ತೈದು" = ಇಪ್ಪತ್ತ + ೈದು): tens -> word beginnings.
  final Map<int, List<String>> tens;
  final Map<String, int> tensEndings;

  /// Case endings that may follow a number ("వందకు" = to a hundred).
  final List<String> suffixes;

  /// Telugu "పదింటికి" = at 10 o'clock.
  final Map<String, int> clock;
  final String clockWord;

  _Word? lookup(String word) {
    final n = numbers[word];
    if (n != null) return _Word(_Kind.number, n);
    final s = scales[word];
    if (s != null) return _Word(_Kind.scale, s);
    final p = prefixes[word];
    if (p != null) return _Word(_Kind.prefix, p);
    for (final entry in tens.entries) {
      for (final stem in entry.value) {
        if (word.length > stem.length && word.startsWith(stem)) {
          final unit = tensEndings[word.substring(stem.length)];
          if (unit != null) return _Word(_Kind.number, (entry.key + unit).toDouble());
        }
      }
    }
    return null;
  }
}

const _tables = {
  AppLanguage.telugu: _Table(
    numbers: {
      'సున్నా': 0,
      'ఒకటి': 1,
      'ఒక': 1,
      'ఒక్క': 1,
      'ఒక్కటి': 1,
      'రెండు': 2,
      'మూడు': 3,
      'నాలుగు': 4,
      'నాల్గు': 4,
      'ఐదు': 5,
      'అయిదు': 5,
      'ఆరు': 6,
      'ఏడు': 7,
      'ఎనిమిది': 8,
      'తొమ్మిది': 9,
      'పది': 10,
      'పదకొండు': 11,
      'పన్నెండు': 12,
      'పదమూడు': 13,
      'పద్నాలుగు': 14,
      'పదునాలుగు': 14,
      'పదిహేను': 15,
      'పదహేను': 15,
      'పదహారు': 16,
      'పదిహేడు': 17,
      'పద్దెనిమిది': 18,
      'పందొమ్మిది': 19,
      'ఇరవై': 20,
      'ముప్పై': 30,
      'ముప్ఫై': 30,
      'నలభై': 40,
      'నలబై': 40,
      'యాభై': 50,
      'యాబై': 50,
      'ఏభై': 50,
      'అరవై': 60,
      'డెబ్బై': 70,
      'డబ్బై': 70,
      'ఎనభై': 80,
      'ఎనబై': 80,
      'తొంభై': 90,
      'తొంబై': 90,
      'అర': 0.5,
      'రెండొందలు': 200,
      'రెండొందల': 200,
      'మూడొందలు': 300,
      'మూడొందల': 300,
      'నాలుగొందలు': 400,
      'నాలుగొందల': 400,
      'ఐదొందలు': 500,
      'ఐదొందల': 500,
      'అయిదొందలు': 500,
      'ఆరొందలు': 600,
      'ఆరొందల': 600,
      'ఏడొందలు': 700,
      'ఏడొందల': 700,
      'ఎనిమిదొందలు': 800,
      'ఎనిమిదొందల': 800,
      'తొమ్మిదొందలు': 900,
      'తొమ్మిదొందల': 900,
      'ఒకటిన్నర': 1.5,
      'రెండున్నర': 2.5,
      'మూడున్నర': 3.5,
      'నాలుగున్నర': 4.5,
      'ఐదున్నర': 5.5,
      'ఆరున్నర': 6.5,
      'ఏడున్నర': 7.5,
      'ఎనిమిదిన్నర': 8.5,
      'తొమ్మిదిన్నర': 9.5,
      'పదిన్నర': 10.5,
    },
    scales: {
      'వంద': 100,
      'వందలు': 100,
      'వందల': 100,
      'నూరు': 100,
      'నూట': 100,
      'వెయ్యి': 1000,
      'వేయి': 1000,
      'వేలు': 1000,
      'వేల': 1000,
      'లక్ష': 100000,
      'లక్షలు': 100000,
      'లక్షల': 100000,
      'కోటి': 10000000,
      'కోట్లు': 10000000,
      'కోట్ల': 10000000,
    },
    suffixes: ['కి', 'కు'],
    clock: {
      'ఒంటికి': 1,
      'రెండింటికి': 2,
      'మూడింటికి': 3,
      'నాలుగింటికి': 4,
      'ఐదింటికి': 5,
      'అయిదింటికి': 5,
      'ఆరింటికి': 6,
      'ఏడింటికి': 7,
      'ఎనిమిదింటికి': 8,
      'తొమ్మిదింటికి': 9,
      'పదింటికి': 10,
      'పదకొండింటికి': 11,
      'పన్నెండింటికి': 12,
    },
    clockWord: 'గంటలకు',
  ),
  AppLanguage.hindi: _Table(
    // Written without the nukta dot, and ँ as ं (see _normalise).
    numbers: {
      'शून्य': 0,
      'एक': 1,
      'दो': 2,
      'तीन': 3,
      'चार': 4,
      'पांच': 5,
      'छह': 6,
      'छः': 6,
      'छे': 6,
      'छै': 6,
      'सात': 7,
      'आठ': 8,
      'नौ': 9,
      'दस': 10,
      'ग्यारह': 11,
      'बारह': 12,
      'तेरह': 13,
      'चौदह': 14,
      'पंद्रह': 15,
      'पन्द्रह': 15,
      'सोलह': 16,
      'सत्रह': 17,
      'अठारह': 18,
      'उन्नीस': 19,
      'बीस': 20,
      'इक्कीस': 21,
      'बाईस': 22,
      'तेईस': 23,
      'चौबीस': 24,
      'पच्चीस': 25,
      'छब्बीस': 26,
      'सत्ताईस': 27,
      'अट्ठाईस': 28,
      'अठाईस': 28,
      'उनतीस': 29,
      'तीस': 30,
      'इकतीस': 31,
      'इकत्तीस': 31,
      'बत्तीस': 32,
      'तैंतीस': 33,
      'चौंतीस': 34,
      'पैंतीस': 35,
      'छत्तीस': 36,
      'सैंतीस': 37,
      'अडतीस': 38,
      'उनतालीस': 39,
      'चालीस': 40,
      'इकतालीस': 41,
      'बयालीस': 42,
      'तैंतालीस': 43,
      'चवालीस': 44,
      'चौवालीस': 44,
      'पैंतालीस': 45,
      'छियालीस': 46,
      'सैंतालीस': 47,
      'अडतालीस': 48,
      'उनचास': 49,
      'पचास': 50,
      'इक्यावन': 51,
      'बावन': 52,
      'तिरपन': 53,
      'तिरेपन': 53,
      'चौवन': 54,
      'पचपन': 55,
      'छप्पन': 56,
      'सत्तावन': 57,
      'अट्ठावन': 58,
      'उनसठ': 59,
      'साठ': 60,
      'इकसठ': 61,
      'बासठ': 62,
      'तिरसठ': 63,
      'चौंसठ': 64,
      'पैंसठ': 65,
      'छियासठ': 66,
      'सडसठ': 67,
      'अडसठ': 68,
      'उनहत्तर': 69,
      'सत्तर': 70,
      'इकहत्तर': 71,
      'बहत्तर': 72,
      'तिहत्तर': 73,
      'चौहत्तर': 74,
      'पचहत्तर': 75,
      'छिहत्तर': 76,
      'सतहत्तर': 77,
      'अठहत्तर': 78,
      'उन्यासी': 79,
      'उनासी': 79,
      'अस्सी': 80,
      'इक्यासी': 81,
      'बयासी': 82,
      'तिरासी': 83,
      'चौरासी': 84,
      'पचासी': 85,
      'छियासी': 86,
      'सत्तासी': 87,
      'अट्ठासी': 88,
      'नवासी': 89,
      'नब्बे': 90,
      'इक्यानवे': 91,
      'बानवे': 92,
      'तिरानवे': 93,
      'चौरानवे': 94,
      'पंचानवे': 95,
      'पचानवे': 95,
      'छियानवे': 96,
      'सत्तानवे': 97,
      'अट्ठानवे': 98,
      'निन्यानवे': 99,
      'डेढ': 1.5,
      'ढाई': 2.5,
      'आधा': 0.5,
    },
    scales: {'सौ': 100, 'हजार': 1000, 'लाख': 100000, 'करोड': 10000000},
    prefixes: {'साढे': 0.5, 'सवा': 0.25, 'पौने': -0.25},
  ),
  AppLanguage.kannada: _Table(
    numbers: {
      'ಸೊನ್ನೆ': 0,
      'ಒಂದು': 1,
      'ಎರಡು': 2,
      'ಮೂರು': 3,
      'ನಾಲ್ಕು': 4,
      'ಐದು': 5,
      'ಆರು': 6,
      'ಏಳು': 7,
      'ಎಂಟು': 8,
      'ಒಂಬತ್ತು': 9,
      'ಹತ್ತು': 10,
      'ಹನ್ನೊಂದು': 11,
      'ಹನ್ನೆರಡು': 12,
      'ಹದಿಮೂರು': 13,
      'ಹದಿನಾಲ್ಕು': 14,
      'ಹದಿನೈದು': 15,
      'ಹದಿನಾರು': 16,
      'ಹದಿನೇಳು': 17,
      'ಹದಿನೆಂಟು': 18,
      'ಹತ್ತೊಂಬತ್ತು': 19,
      'ಇಪ್ಪತ್ತು': 20,
      'ಮೂವತ್ತು': 30,
      'ನಲವತ್ತು': 40,
      'ನಲುವತ್ತು': 40,
      'ಐವತ್ತು': 50,
      'ಅರವತ್ತು': 60,
      'ಎಪ್ಪತ್ತು': 70,
      'ಎಂಬತ್ತು': 80,
      'ತೊಂಬತ್ತು': 90,
      'ಇನ್ನೂರು': 200,
      'ಇನ್ನೂರ': 200,
      'ಇನ್ನೂರಾ': 200,
      'ಮುನ್ನೂರು': 300,
      'ಮುನ್ನೂರ': 300,
      'ಮುನ್ನೂರಾ': 300,
      'ನಾನೂರು': 400,
      'ನಾನೂರ': 400,
      'ನಾನೂರಾ': 400,
      'ಐನೂರು': 500,
      'ಐನೂರ': 500,
      'ಐನೂರಾ': 500,
      'ಆರುನೂರು': 600,
      'ಆರ್ನೂರು': 600,
      'ಏಳುನೂರು': 700,
      'ಎಂಟುನೂರು': 800,
      'ಒಂಬೈನೂರು': 900,
      'ಒಂಬತ್ತುನೂರು': 900,
      'ಅರ್ಧ': 0.5,
    },
    scales: {
      'ನೂರು': 100,
      'ನೂರ': 100,
      'ನೂರಾ': 100,
      'ಸಾವಿರ': 1000,
      'ಸಾವಿರದ': 1000,
      'ಸಾವಿರಾ': 1000,
      'ಲಕ್ಷ': 100000,
      'ಲಕ್ಷದ': 100000,
      'ಕೋಟಿ': 10000000,
    },
    tens: {
      20: ['ಇಪ್ಪತ್ತ', 'ಇಪ್ಪತ್'],
      30: ['ಮೂವತ್ತ', 'ಮೂವತ್'],
      40: ['ನಲವತ್ತ', 'ನಲವತ್', 'ನಲುವತ್ತ', 'ನಲುವತ್'],
      50: ['ಐವತ್ತ', 'ಐವತ್'],
      60: ['ಅರವತ್ತ', 'ಅರವತ್'],
      70: ['ಎಪ್ಪತ್ತ', 'ಎಪ್ಪತ್'],
      80: ['ಎಂಬತ್ತ', 'ಎಂಬತ್'],
      90: ['ತೊಂಬತ್ತ', 'ತೊಂಬತ್'],
    },
    tensEndings: {'ೊಂದು': 1, 'ೆರಡು': 2, 'ಮೂರು': 3, 'ನಾಲ್ಕು': 4, 'ೈದು': 5, 'ಾರು': 6, 'ೇಳು': 7, 'ೆಂಟು': 8, 'ೊಂಬತ್ತು': 9},
    suffixes: ['ಕ್ಕೆ'],
  ),
  AppLanguage.tamil: _Table(
    numbers: {
      'பூஜ்ஜியம்': 0,
      'பூஜ்யம்': 0,
      'ஒன்று': 1,
      'ஒண்ணு': 1,
      'ஒரு': 1,
      'இரண்டு': 2,
      'ரெண்டு': 2,
      'மூன்று': 3,
      'மூணு': 3,
      'நான்கு': 4,
      'நாலு': 4,
      'ஐந்து': 5,
      'அஞ்சு': 5,
      'ஆறு': 6,
      'ஏழு': 7,
      'எட்டு': 8,
      'ஒன்பது': 9,
      'பத்து': 10,
      'பதினொன்று': 11,
      'பதினொண்ணு': 11,
      'பன்னிரண்டு': 12,
      'பன்னெண்டு': 12,
      'பதிமூன்று': 13,
      'பதின்மூன்று': 13,
      'பதினான்கு': 14,
      'பதினாலு': 14,
      'பதினைந்து': 15,
      'பதினஞ்சு': 15,
      'பதினாறு': 16,
      'பதினேழு': 17,
      'பதினெட்டு': 18,
      'பத்தொன்பது': 19,
      'இருபது': 20,
      'முப்பது': 30,
      'நாற்பது': 40,
      'ஐம்பது': 50,
      'அறுபது': 60,
      'எழுபது': 70,
      'எண்பது': 80,
      'தொண்ணூறு': 90,
      'இருபத்தி': 20,
      'இருபத்து': 20,
      'முப்பத்தி': 30,
      'முப்பத்து': 30,
      'நாற்பத்தி': 40,
      'நாற்பத்து': 40,
      'ஐம்பத்தி': 50,
      'ஐம்பத்து': 50,
      'அறுபத்தி': 60,
      'அறுபத்து': 60,
      'எழுபத்தி': 70,
      'எழுபத்து': 70,
      'எண்பத்தி': 80,
      'எண்பத்து': 80,
      'தொண்ணூற்றி': 90,
      'தொண்ணூற்று': 90,
      'இருநூறு': 200,
      'இருநூற்று': 200,
      'முந்நூறு': 300,
      'முன்னூறு': 300,
      'முந்நூற்று': 300,
      'முன்னூற்று': 300,
      'நானூறு': 400,
      'நானூற்று': 400,
      'ஐநூறு': 500,
      'ஐந்நூறு': 500,
      'ஐநூற்று': 500,
      'ஐந்நூற்று': 500,
      'அறுநூறு': 600,
      'அறுநூற்று': 600,
      'எழுநூறு': 700,
      'எழுநூற்று': 700,
      'எண்ணூறு': 800,
      'எண்ணூற்று': 800,
      'தொள்ளாயிரம்': 900,
      'தொள்ளாயிரத்து': 900,
      'இரண்டாயிரம்': 2000,
      'இரண்டாயிரத்து': 2000,
      'ரெண்டாயிரம்': 2000,
      'மூவாயிரம்': 3000,
      'மூவாயிரத்து': 3000,
      'நாலாயிரம்': 4000,
      'நான்காயிரம்': 4000,
      'நாலாயிரத்து': 4000,
      'ஐந்தாயிரம்': 5000,
      'அஞ்சாயிரம்': 5000,
      'ஐந்தாயிரத்து': 5000,
      'ஆறாயிரம்': 6000,
      'ஏழாயிரம்': 7000,
      'எட்டாயிரம்': 8000,
      'ஒன்பதாயிரம்': 9000,
      'பத்தாயிரம்': 10000,
      'அரை': 0.5,
    },
    scales: {
      'நூறு': 100,
      'நூற்று': 100,
      'ஆயிரம்': 1000,
      'ஆயிரத்து': 1000,
      'லட்சம்': 100000,
      'லட்சத்து': 100000,
      'கோடி': 10000000,
    },
    tens: {
      20: ['இருபத்தி', 'இருபத்து', 'இருபத்த'],
      30: ['முப்பத்தி', 'முப்பத்து', 'முப்பத்த'],
      40: ['நாற்பத்தி', 'நாற்பத்து', 'நாற்பத்த'],
      50: ['ஐம்பத்தி', 'ஐம்பத்து', 'ஐம்பத்த'],
      60: ['அறுபத்தி', 'அறுபத்து', 'அறுபத்த'],
      70: ['எழுபத்தி', 'எழுபத்து', 'எழுபத்த'],
      80: ['எண்பத்தி', 'எண்பத்து', 'எண்பத்த'],
      90: ['தொண்ணூற்றி', 'தொண்ணூற்று', 'தொண்ணூற்ற'],
    },
    tensEndings: {
      'ொன்று': 1,
      'ிரண்டு': 2,
      'ைந்து': 5,
      'ாறு': 6,
      'ேழு': 7,
      'ெட்டு': 8,
      'ொன்பது': 9,
      'ஒன்று': 1,
      'இரண்டு': 2,
      'ரெண்டு': 2,
      'மூன்று': 3,
      'நான்கு': 4,
      'நாலு': 4,
      'ஐந்து': 5,
      'ஆறு': 6,
      'ஏழு': 7,
      'எட்டு': 8,
      'ஒன்பது': 9,
    },
    suffixes: ['க்கு'],
  ),
};
