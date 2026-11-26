/// Turns a spoken sentence into a calendar event draft.
///
///   "remind me tomorrow at 10 am supplier payment"
///       -> "Supplier payment", tomorrow, 10:00 AM, Payment
///   "rent every month on the 5th"   -> "Rent", monthly from the next 5th
///   "stock check every monday 9 am" -> "Stock check", weekly, 9:00 AM
///   "doctor on 25 november at 6 pm" -> "Doctor", 25 Nov, 6:00 PM, Personal
///
/// English only for now. The result is shown in the form for the user to
/// check before saving, so a wrong guess is easy to fix.
library;

import 'calendar_models.dart';
import 'spoken_time.dart';

const _weekdays = {
  'monday': 1,
  'tuesday': 2,
  'wednesday': 3,
  'thursday': 4,
  'friday': 5,
  'saturday': 6,
  'sunday': 7,
};

const _months = {
  'january': 1,
  'jan': 1,
  'february': 2,
  'feb': 2,
  'march': 3,
  'mar': 3,
  'april': 4,
  'apr': 4,
  'may': 5,
  'june': 6,
  'jun': 6,
  'july': 7,
  'jul': 7,
  'august': 8,
  'aug': 8,
  'september': 9,
  'sep': 9,
  'sept': 9,
  'october': 10,
  'oct': 10,
  'november': 11,
  'nov': 11,
  'december': 12,
  'dec': 12,
};

const _smallNumbers = {
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
  'a': 1,
  'an': 1,
};

const _paymentWords = {
  'payment',
  'pay',
  'paid',
  'bill',
  'bills',
  'rent',
  'emi',
  'loan',
  'due',
  'dues',
  'udhaar',
  'udhar',
  'salary',
  'salaries',
  'fees',
  'fee',
  'electricity',
  'tax',
  'gst',
  'insurance',
  'cheque',
  'premium',
};
const _supplierWords = {
  'supplier',
  'suppliers',
  'delivery',
  'deliveries',
  'stock',
  'order',
  'orders',
  'wholesale',
  'wholesaler',
  'distributor',
  'goods',
  'purchase',
  'restock',
  'vendor',
  'dealer',
};
const _personalWords = {
  'doctor',
  'birthday',
  'anniversary',
  'family',
  'wedding',
  'marriage',
  'personal',
  'school',
  'hospital',
  'medicine',
  'temple',
  'function',
};

EventDraft? parseSpokenEvent(
  String spoken,
  DateTime now, {
  EventCategory defaultCategory = EventCategory.other,
  SpokenTime? spokenTime,
}) {
  var text = ' ${_normalise(spoken)} ';
  if (text.trim().isEmpty) return null;

  final today = DateTime(now.year, now.month, now.day);
  DateTime? day;
  int? minute;
  var guessed = false;
  var soon = false; // "in 10 minutes"
  var repeat = Repeat.none;

  String take(RegExp pattern, void Function(RegExpMatch m) use) {
    final match = pattern.firstMatch(text);
    if (match == null) return text;
    use(match);
    return text.replaceRange(match.start, match.end, ' ');
  }

  // ---- leading command words ----
  text = text.replaceFirst(
    RegExp(
      r'^\s*(?:(?:hey |ok )?qbox\s+)?(?:please\s+)?(?:remind me(?: (?:to|about|of|that))?|'
      r'set (?:a )?reminder(?: to| for)?|add (?:an? )?(?:event|reminder)(?: for| to)?|'
      r'create (?:an? )?(?:event|reminder)(?: for| to)?|schedule|add|note)\s+',
    ),
    ' ',
  );

  // ---- repeats ----
  text = take(
    RegExp(r'\b(?:every ?day|each day|daily)\b'),
    (_) => repeat = Repeat.daily,
  );
  text = take(
    RegExp(
      r'\b(?:every|each) (monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b',
    ),
    (m) {
      repeat = Repeat.weekly;
      day = _nextWeekday(today, _weekdays[m[1]]!, allowToday: true);
    },
  );
  text = take(
    RegExp(r'\b(?:(?:every|each) week|weekly)\b'),
    (_) => repeat = Repeat.weekly,
  );
  void monthly(String? domText) {
    repeat = Repeat.monthly;
    final dom = int.tryParse(domText ?? '');
    if (dom != null && dom >= 1 && dom <= 31) {
      day = _nextDayOfMonth(today, dom);
    }
  }

  // "on the 5th of each month" (how a Telugu/Hindi "ప్రతి నెల 5వ తేదీ" is translated)
  text = take(
    RegExp(r'\b(?:on )?(?:the )?(\d{1,2}) (?:of )?(?:every|each) month\b'),
    (m) => monthly(m[1]),
  );
  text = take(
    RegExp(r'\b(?:(?:every|each) month|monthly|per month)(?: on)?(?: the)? ?(\d{1,2})?\b'),
    (m) => monthly(m[1]),
  );
  text = take(
    RegExp(r'\b(?:(?:every|each) year|yearly|annually)\b'),
    (_) => repeat = Repeat.yearly,
  );

  // ---- "in 2 hours", "in 30 minutes", "in 3 days" ----
  void after(int minutes) {
    final at = now.add(Duration(minutes: minutes));
    day = DateTime(at.year, at.month, at.day);
    minute = at.hour * 60 + at.minute;
    soon = true;
  }

  text = take(
    RegExp(r'\b(?:in|after) (\d+|an?|one|two|three|four|five|six) hours?(?: and)? (\d+|five|ten|half|a half) ?(?:minutes?|mins?)?\b'),
    (m) {
      final hours = int.tryParse(m[1]!) ?? _smallNumbers[m[1]] ?? 1;
      final extra = m[2]!.endsWith('half') ? 30 : int.tryParse(m[2]!) ?? _smallNumbers[m[2]] ?? 0;
      after(hours * 60 + extra);
    },
  );
  text = take(RegExp(r'\b(?:in|after) half an hour\b'), (_) => after(30));
  text = take(
    RegExp(
      r'\b(?:in|after) (\d+|an?|one|two|three|four|five|six|seven|eight|nine|ten) (minute|minutes|min|mins|hour|hours|day|days|week|weeks)\b',
    ),
    (m) {
      final n = int.tryParse(m[1]!) ?? _smallNumbers[m[1]] ?? 1;
      final unit = m[2]!;
      if (unit.startsWith('min') || unit.startsWith('hour')) {
        after(unit.startsWith('hour') ? n * 60 : n);
      } else {
        day = today.add(Duration(days: unit.startsWith('week') ? n * 7 : n));
      }
    },
  );

  // ---- dates ----
  text = take(
    RegExp(r'\bday after tomorrow\b'),
    (_) => day = today.add(const Duration(days: 2)),
  );
  text = take(
    RegExp(r'\btomorrow\b'),
    (_) => day = today.add(const Duration(days: 1)),
  );
  text = take(RegExp(r'\btonight\b'), (_) {
    day = today;
    minute ??= 20 * 60;
  });
  text = take(RegExp(r'\btoday\b'), (_) => day = today);
  text = take(
    RegExp(r'\bnext week\b'),
    (_) => day = today.add(const Duration(days: 7)),
  );
  text = take(RegExp(r'\bnext month\b'), (_) {
    final dom = today.day.clamp(1, daysInMonth(today.year, today.month + 1));
    day = DateTime(today.year, today.month + 1, dom);
  });
  final monthAlternation = _months.keys.join('|');
  // "25 november", "25 of november 2027"
  text = take(
    RegExp('\\b(\\d{1,2})(?: of)? ($monthAlternation)\\b(?: (\\d{4}))?'),
    (m) => day = _dateFrom(today, int.parse(m[1]!), _months[m[2]]!, m[3]),
  );
  // "november 25", "nov 25 2027"
  text = take(
    RegExp('\\b($monthAlternation) (\\d{1,2})\\b(?: (\\d{4}))?'),
    (m) => day = _dateFrom(today, int.parse(m[2]!), _months[m[1]]!, m[3]),
  );
  // "25/11", "25-11-2027" (Indian order: day first)
  text = take(RegExp(r'\b(\d{1,2})[/-](\d{1,2})(?:[/-](\d{2,4}))?\b'), (m) {
    var year = m[3];
    if (year != null && year.length == 2) year = '20$year';
    day = _dateFrom(today, int.parse(m[1]!), int.parse(m[2]!), year);
  });
  // "on monday", "next friday", "this saturday"
  text = take(
    RegExp(
      r'\b(?:on |next |this |coming )?(monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b',
    ),
    (m) => day ??= _nextWeekday(today, _weekdays[m[1]]!, allowToday: false),
  );
  // "on the 25th", "on 5"
  text = take(RegExp(r'\bon(?: the)? (\d{1,2})\b(?! ?(?:am|pm|oclock|:|\d))'), (
    m,
  ) {
    final dom = int.parse(m[1]!);
    if (dom >= 1 && dom <= 31) day ??= _nextDayOfMonth(today, dom);
  });

  // ---- times ----
  final english = takeEnglishTime(text);
  text = english.rest;
  final clock = spokenTime ?? english.time;
  if (clock != null && (minute == null || clock.sure)) {
    minute = clock.minute;
    guessed = !clock.sure;
  }

  // ---- what is left is the title ----
  var title = text
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .replaceAll(
        RegExp(r'^(?:(?:to|for|about|on|at|the|of|by|and|is|my)\s+)+'),
        '',
      )
      .replaceAll(
        RegExp(r'(?:\s+(?:to|for|about|on|at|the|of|by|and|is))+$'),
        '',
      )
      .trim();
  if (title.isEmpty) title = 'Reminder';
  title = _keepCapitals(title, spoken);
  title = title[0].toUpperCase() + title.substring(1);

  var eventDay = day ?? today;
  // "at 9", said at 5 in the evening, is 9 tonight; "at 3:10 pm" is tomorrow.
  final saidToday = day != null && day == today;
  if ((day == null || saidToday) && minute != null && repeat == Repeat.none && !soon) {
    final nowMinute = now.hour * 60 + now.minute;
    if (minute! <= nowMinute) {
      if (guessed && minute! < 12 * 60 && minute! + 12 * 60 > nowMinute) {
        minute = minute! + 12 * 60;
      } else if (!saidToday) {
        eventDay = DateTime(today.year, today.month, today.day + 1);
      }
    }
  }
  return EventDraft(
    title: title.length > 120 ? title.substring(0, 120) : title,
    day: eventDay,
    minuteOfDay: minute,
    category: _guessCategory(title, defaultCategory),
    repeat: repeat,
    remindMinutes: 0,
  );
}

/// Names keep their capitals: "call Ravi" stays "Call Ravi", not "Call ravi".
/// The first word said is skipped (it has a capital only for starting the sentence).
String _keepCapitals(String title, String spoken) {
  final cased = <String, String>{};
  final said = spoken.trim().split(RegExp(r'\s+'));
  for (final w in said.skip(1)) {
    final word = w.replaceAll(RegExp(r'[^A-Za-z]'), '');
    if (word.length > 1 && word != word.toLowerCase() && word != word.toUpperCase()) cased[word.toLowerCase()] = word;
  }
  if (cased.isEmpty) return title;
  return title.split(' ').map((w) => cased[w] ?? w).join(' ');
}

String _normalise(String spoken) {
  var t = spoken.toLowerCase();
  // "3: 10 p.m" (how a translation sometimes writes 3:10) -> "3:10 p.m"
  t = t.replaceAllMapped(RegExp(r'\b(\d{1,2}):\s+(\d{2})\b'), (m) => '${m[1]}:${m[2]}');
  t = t
      .replaceAll(RegExp(r'\ba\.m\.?'), 'am')
      .replaceAll(RegExp(r'\bp\.m\.?'), 'pm');
  t = t.replaceAll("o'clock", 'oclock').replaceAll('o clock', 'oclock');
  t = t.replaceAllMapped(RegExp(r'(\d+)(?:st|nd|rd|th)\b'), (m) => m[1]!);
  t = t.replaceAll(RegExp(r'[,!?;"]'), ' ');
  t = t.replaceAll(RegExp(r'\.(?!\d)'), ' '); // keep "10.30", drop full stops
  return t.replaceAll(RegExp(r'\s+'), ' ').trim();
}

DateTime _nextWeekday(DateTime today, int weekday, {required bool allowToday}) {
  var diff = (weekday - today.weekday) % 7;
  if (diff == 0 && !allowToday) diff = 7;
  return today.add(Duration(days: diff));
}

DateTime _nextDayOfMonth(DateTime today, int dom) {
  var year = today.year;
  var month = today.month;
  if (dom < today.day) month += 1;
  if (month > 12) {
    month = 1;
    year += 1;
  }
  final last = daysInMonth(year, month);
  return DateTime(year, month, dom > last ? last : dom);
}

/// A date this year, or next year if it has already passed (unless a year was said).
DateTime? _dateFrom(DateTime today, int dom, int month, String? yearText) {
  if (month < 1 || month > 12 || dom < 1) return null;
  var year = int.tryParse(yearText ?? '') ?? today.year;
  if (dom > daysInMonth(year, month)) return null;
  var date = DateTime(year, month, dom);
  if (yearText == null && date.isBefore(today)) {
    year += 1;
    if (dom > daysInMonth(year, month)) return null;
    date = DateTime(year, month, dom);
  }
  return date;
}

EventCategory _guessCategory(String title, EventCategory fallback) {
  final words = title.toLowerCase().split(RegExp(r'[^a-z]+')).toSet();
  if (words.any(_paymentWords.contains)) return EventCategory.payment;
  if (words.any(_supplierWords.contains)) return EventCategory.supplier;
  if (words.any(_personalWords.contains)) return EventCategory.personal;
  return fallback;
}
