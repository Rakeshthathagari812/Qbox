/// The clock time in a spoken sentence, in any of the 5 languages.
///
///   "at 3 10 pm", "310 pm", "ten past three", "half past 3", "3 o'clock 10 minutes"
///   "మధ్యాహ్నం 3 గంటల 10 నిమిషాలకు", "दोपहर 3 बजकर 10 मिनट", "सवा 3 बजे"
///
/// Read on the phone before translating: translation often drops the minutes.
library;

import '../translator/english_numbers.dart';
import '../translator/indic_numbers.dart';
import '../translator/languages.dart';

class SpokenTime {
  const SpokenTime(this.minute, {required this.sure});

  /// Minutes after midnight.
  final int minute;

  /// True if am/pm or the part of day was said; else it is a guess (shop hours).
  final bool sure;
}

/// Hour and minute to minutes after midnight, using am/pm or the part of day.
/// Without either, shop hours are assumed: 7-11 morning, 12-6 afternoon/evening.
SpokenTime? clockTime(int hour, int minute, String? ampm, String? daypart) {
  if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
  var h = hour;
  final pm =
      ampm == 'pm' ||
      (ampm == null &&
          (daypart == 'afternoon' || daypart == 'evening' || (daypart == 'night' && hour >= 5)));
  final am = ampm == 'am' || (ampm == null && (daypart == 'morning' || (daypart == 'night' && hour < 5)));
  if (pm && h < 12) h += 12;
  if (am && h == 12) h = 0;
  if (!pm && !am && hour <= 12) {
    if (hour >= 1 && hour <= 6) h += 12; // "at 5" in a shop means 5 PM
  }
  if (daypart == 'night' && hour == 12) h = 0;
  return SpokenTime(h * 60 + minute, sure: pm || am || hour > 12 || hour == 0);
}

const _numbers = {
  'one': 1, 'two': 2, 'three': 3, 'four': 4, 'five': 5, 'six': 6, 'seven': 7, 'eight': 8, 'nine': 9, 'ten': 10,
  'eleven': 11, 'twelve': 12, 'thirteen': 13, 'fourteen': 14, 'fifteen': 15, 'sixteen': 16, 'seventeen': 17,
  'eighteen': 18, 'nineteen': 19, 'twenty': 20, 'thirty': 30, 'forty': 40, 'fifty': 50,
};
final _word = _numbers.keys.join('|');
final _hour = '(\\d{1,2}|$_word)';
final _minutes = '((?:twenty|thirty|forty|fifty)[ -](?:one|two|three|four|five|six|seven|eight|nine)|\\d{1,2}|$_word)';
const _ampm = r'(?: ?(am|pm))?';
const _part = r'(?: (?:in the |at )?(morning|afternoon|evening|night))?';

/// What the number counts, when it is not a time ("at 5 50 kg rice").
const _notThings = r'(?! ?(?:kgs?|kilos?|g|grams?|litres?|liters?|packets?|pieces?|rupees?|rs|bags?|boxes|items?|people|days?|%|percent))';

int? _read(String? text) {
  if (text == null) return null;
  final n = int.tryParse(text);
  if (n != null) return n;
  final parts = text.split(RegExp('[ -]'));
  var sum = 0;
  for (final p in parts) {
    final v = _numbers[p];
    if (v == null) return null;
    sum += v;
  }
  return sum;
}

/// Finds an English clock time in [text] (lower case) and cuts it out.
({SpokenTime? time, String rest}) takeEnglishTime(String text) {
  SpokenTime? time;
  bool tryOne(String pattern, SpokenTime? Function(RegExpMatch m) read) {
    for (final m in RegExp(pattern).allMatches(text)) {
      final t = read(m);
      if (t == null) continue;
      time = t;
      text = text.replaceRange(m.start, m.end, ' ');
      return true;
    }
    return false;
  }

  // "3 p m" -> "3 pm"
  text = text.replaceAllMapped(RegExp(r'(\d) ?([ap]) m\b'), (m) => '${m[1]} ${m[2]}m');

  final found =
      // 10:00 29
      tryOne('\\b(?:at )?(\\d{1,2}):00 (\\d{2})\\b$_notThings$_ampm$_part', (m) => _two(m[1], m[2], m[3], m[4])) ||
      // 3:10, 3.10
      tryOne('\\b(?:at )?(\\d{1,2})[:.](\\d{2})\\b$_ampm$_part\\b', (m) => clockTime(int.parse(m[1]!), int.parse(m[2]!), m[3], m[4])) ||
      // 10 and 29 minutes
      tryOne('\\b(?:at )?$_hour and $_minutes (?:minutes?|mins?)\\b$_ampm$_part', (m) => clockTime(_read(m[1])!, _read(m[2]) ?? 60, m[3], m[4])) ||
      // 3 oclock 10 minutes; 3 hours 10 minutes
      tryOne(
        '\\b(?:at )?$_hour (?:oclock|hours?)(?: and)? $_minutes (?:minutes?|mins?)\\b$_ampm$_part\\b',
        (m) => clockTime(_read(m[1])!, _read(m[2]) ?? 60, m[3], m[4]),
      ) ||
      // half past 3, quarter past 3, quarter to 4
      tryOne(
        '\\b(?:at )?(?:a )?(half|quarter) (past|after|to|before) $_hour\\b$_ampm$_part\\b',
        (m) => _around(m[1] == 'half' ? 30 : 15, m[2]!, _read(m[3])!, m[4], m[5]),
      ) ||
      // ten past three, 10 minutes past 3
      tryOne(
        '\\b(?:at )?$_minutes (?:(?:minutes?|mins?) )?(past|after) $_hour\\b$_ampm$_part\\b',
        (m) => _around(_read(m[1]) ?? 60, m[2]!, _read(m[3])!, m[4], m[5]),
      ) ||
      // 10 minutes to 4; at ten to four
      tryOne(
        '\\b(?:(?:at )?$_minutes (?:minutes?|mins?)|at (5|10|20|25|five|ten|twenty|twenty five)) (to|before) $_hour\\b$_ampm$_part\\b',
        (m) => _around(_read(m[1] ?? m[2]) ?? 60, m[3]!, _read(m[4])!, m[5], m[6]),
      ) ||
      // 3 10 pm; three ten in the afternoon
      tryOne('\\b(?:at )?$_hour $_minutes ?(am|pm)$_part\\b', (m) => _two(m[1], m[2], m[3], m[4])) ||
      tryOne('\\b(?:at )?$_hour $_minutes (?:in the )?(morning|afternoon|evening|night)\\b', (m) => _two(m[1], m[2], null, m[3])) ||
      // at 3 10; by 10 29; at 10 to 29 (how "ten twenty nine" is sometimes heard)
      tryOne('\\b(?:at|by|for|around) $_hour (?:to )?$_minutes\\b$_notThings', (m) => _two(m[1], m[2], null, null)) ||
      // meeting 10 29; 10 29 meeting
      tryOne('\\b$_hour $_minutes(?=\\s*\$)', (m) => _two(m[1], m[2], null, null)) ||
      tryOne('^\\s*$_hour $_minutes\\b$_notThings', (m) => _two(m[1], m[2], null, null)) ||
      // 310 pm; at 1030
      tryOne('\\b(?:at )?(\\d{1,2})(\\d{2}) ?(am|pm)$_part\\b', (m) => _two(m[1], m[2], m[3], m[4])) ||
      tryOne('\\b(?:at|by|for|around) (\\d{1,2})(\\d{2})\\b$_notThings$_part', (m) => _two(m[1], m[2], null, m[3])) ||
      tryOne('\\b(?:reminder|me) (\\d{1,2})(\\d{2})(?=\\s*\$)', (m) => _two(m[1], m[2], null, null)) ||
      // 3 pm, 3 oclock
      tryOne('\\b(?:at )?$_hour ?(am|pm|oclock)$_part\\b', (m) => clockTime(_read(m[1])!, 0, m[2] == 'oclock' ? null : m[2], m[3])) ||
      // at 5
      tryOne('\\bat $_hour\\b$_notThings$_part\\b', (m) => clockTime(_read(m[1])!, 0, null, m[2])) ||
      tryOne(r'\b(?:at )?noon\b', (_) => const SpokenTime(12 * 60, sure: true)) ||
      tryOne(r'\b(?:at )?midnight\b', (_) => const SpokenTime(0, sure: true));
  if (found) {
    // "tomorrow morning at 10", with the part of day elsewhere.
    final part = RegExp(r'\b(?:in the )?(morning|afternoon|evening|night)\b').firstMatch(text);
    final t = time!;
    if (part != null && !t.sure) {
      final h = t.minute ~/ 60;
      time = clockTime(h > 12 ? h - 12 : h, t.minute % 60, null, part[1]) ?? t;
      text = text.replaceRange(part.start, part.end, ' ');
    }
    // "today at 10:30 I should go shopping pm"
    final late = RegExp(r'\bpm\b|(?<!\bi )\bam\b(?=\s*\$)').firstMatch(text);
    final now = time!;
    if (late != null) {
      if (!now.sure) {
        final h = now.minute ~/ 60;
        time = clockTime(h > 12 ? h - 12 : h, now.minute % 60, late[0], null) ?? now;
      }
      text = text.replaceRange(late.start, late.end, ' ');
    }
  } else {
    tryOne(r'\b(?:in the )?(morning|afternoon|evening|night)\b', (m) => SpokenTime(switch (m[1]) {
          'morning' => 9 * 60,
          'afternoon' => 14 * 60,
          'evening' => 18 * 60,
          _ => 20 * 60,
        }, sure: true));
  }
  return (time: time, rest: text);
}

SpokenTime? _two(String? hour, String? minute, String? ampm, String? part) {
  final h = _read(hour);
  final m = _read(minute);
  if (h == null || m == null || h < 1 || h > 12) return null;
  // "3 5 pm" is not how a time is said ("3 05" is).
  if (m < 10 && !(minute!.length == 2 && minute.startsWith('0'))) return null;
  return clockTime(h, m, ampm, part);
}

SpokenTime? _around(int minutes, String side, int hour, String? ampm, String? part) {
  if (minutes > 59 || hour < 1 || hour > 12) return null;
  if (side == 'past' || side == 'after') return clockTime(hour, minutes, ampm, part);
  final before = hour == 1 ? 12 : hour - 1;
  return clockTime(before, 60 - minutes, ampm, part);
}

typedef _Lang = ({String hour, String minute, String at, Map<String, String> parts, String notClock});

const _langs = <AppLanguage, _Lang>{
  AppLanguage.telugu: (
    hour: r'గం(?:ట|\.)\S*',
    minute: r'నిమి\S*',
    at: r'కి(?![^\s])|కు(?![^\s])',
    parts: {
      'ఉదయ': 'morning', 'పొద్దున': 'morning', 'తెల్లవారు': 'morning', 'మధ్యాహ్న': 'afternoon', 'సాయంత్ర': 'evening',
      'రాత్రి': 'night',
    },
    notClock: r'తర్వాత|తరువాత|లోపు|పాటు',
  ),
  AppLanguage.hindi: (
    hour: r'बज\S*',
    minute: r'मिनट\S*',
    at: r'पर(?![^\s])|को(?![^\s])',
    parts: {'सुबह': 'morning', 'सवेरे': 'morning', 'दोपहर': 'afternoon', 'शाम': 'evening', 'रात': 'night'},
    notClock: r'बाद',
  ),
  AppLanguage.kannada: (
    hour: r'ಗಂಟೆ\S*',
    minute: r'ನಿಮಿಷ\S*',
    at: r'ಕ್ಕೆ|ಗೆ(?![^\s])',
    parts: {
      'ಬೆಳಿಗ್ಗೆ': 'morning', 'ಬೆಳಗ್ಗೆ': 'morning', 'ಮಧ್ಯಾಹ್ನ': 'afternoon', 'ಸಂಜೆ': 'evening', 'ಸಾಯಂಕಾಲ': 'evening',
      'ರಾತ್ರಿ': 'night',
    },
    notClock: r'ನಂತರ|ಆದಮೇಲೆ',
  ),
  AppLanguage.tamil: (
    hour: r'மணி(?:க்கு|யளவில்)?',
    minute: r'நிமிட\S*',
    at: r'க்கு',
    parts: {'காலை': 'morning', 'மதிய': 'afternoon', 'மாலை': 'evening', 'இரவு': 'night'},
    notClock: r'நேர\S*|பிறகு|கழித்து',
  ),
};

/// The clock time said in Telugu, Hindi, Kannada or Tamil; null if none was.
SpokenTime? nativeTime(String words, AppLanguage language) {
  final l = _langs[language];
  if (l == null) return null;
  var text = words;
  // Words joined together: పదిగంటల, ఇరవైతొమ్మిది.
  for (final w in const ['గంట', 'నిమి', 'ಗಂಟೆ', 'ನಿಮಿ', 'மணி', 'நிமி', 'बज', 'मिनट']) {
    text = text.replaceAll(w, ' $w');
  }
  text = text.replaceAllMapped(RegExp('(ఇరవై|ముప్పై|నలభై|యాభై|ఇరవయ్యి|ముప్పయ్యి)(?=[^\\s])'), (m) => '${m[1]} ');
  text = englishToDigits(numbersToDigits(text, language)).replaceAll(RegExp(r'[,!?;।]'), ' ').replaceAll(RegExp(r'\s+'), ' ');
  // "20 9" is 29.
  text = text.replaceAllMapped(RegExp(r'\b(20|30|40|50) ([1-9])\b'), (m) => '${int.parse(m[1]!) + int.parse(m[2]!)}');
  String? ampm;
  if (RegExp(r'పీ\s?ఎం|పి\s?ఎం|पी\s?एम|ಪಿ\s?ಎಂ|பி\s?எம்|\bp\.?\s?m\b', caseSensitive: false).hasMatch(text)) ampm = 'pm';
  if (RegExp(r'ఏ\s?ఎం|ఎ\s?ఎం|एएम|ए एम|ಎ\s?ಎಂ|ஏ\s?எம்|\ba\.?\s?m\b', caseSensitive: false).hasMatch(text)) ampm ??= 'am';
  String? part;
  for (final e in l.parts.entries) {
    if (text.contains(e.key)) part = e.value;
  }

  // 3:10, 3.10 కి (but 3.5 గంటలకు is half past three)
  final colon = RegExp(r'(?<![\d.:])(\d{1,2}):(\d{2})(?!\d)').firstMatch(text) ??
      RegExp(r'(?<![\d.:])(\d{1,2})\.(\d{2})(?!\d)').firstMatch(text);
  if (colon != null) return clockTime(int.parse(colon[1]!), int.parse(colon[2]!), ampm, part);

  final hours = RegExp(
    '(?<![\\d.])(\\d{1,2})(?:\\.(25|5|75))? ?(?:${l.hour})(?: (\\d{1,2}) ?(?:${l.minute}|${l.at}|\$))?',
  );
  for (final m in hours.allMatches(text)) {
    final after = text.substring(m.end).trimLeft();
    if (RegExp('^(?:${l.notClock})').hasMatch(after)) continue; // "after 3 hours"
    if (m[0]!.endsWith('లో')) continue; // "in 3 hours"
    final fraction = switch (m[2]) {
      '25' => 15,
      '5' => 30,
      '75' => 45,
      _ => 0,
    };
    return clockTime(int.parse(m[1]!), int.tryParse(m[3] ?? '') ?? fraction, ampm, part);
  }
  // 10 29 కి; రాత్రి 10 29
  final bare = RegExp('(?<![\\d.])(\\d{1,2}) (\\d{2})(?:(?= ?(?:${l.at}))|(?=\\s*\$))').firstMatch(text);
  if (bare != null || (ampm ?? part) != null) {
    final m = bare ?? RegExp(r'(?<![\d.])(\d{1,2}) (\d{2})(?!\d)').firstMatch(text);
    if (m != null && int.parse(m[1]!) >= 1 && int.parse(m[1]!) <= 12) return clockTime(int.parse(m[1]!), int.parse(m[2]!), ampm, part);
  }
  return null;
}

/// English numbers written in Indian letters, as digits ("త్రీ టెన్" -> "3 10").
String englishToDigits(String text) =>
    englishNumberWords(text).replaceAllMapped(RegExp(r'\b[a-z]+\b'), (m) => _numbers.containsKey(m[0]) ? '${_numbers[m[0]]}' : m[0]!);
