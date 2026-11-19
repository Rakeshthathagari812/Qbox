/// Calendar data and date rules. No Flutter here, so it can be tested alone.
library;

import '../models/qbox_user.dart';
import '../onboarding_draft.dart';

enum EventCategory {
  shop('SHOP', 'Shop'),
  supplier('SUPPLIER', 'Supplier'),
  payment('PAYMENT', 'Payment due'),
  personal('PERSONAL', 'Personal'),
  other('OTHER', 'Other');

  const EventCategory(this.code, this.label);
  final String code;
  final String label;

  static EventCategory fromCode(String? code) =>
      values.firstWhere((c) => c.code == code, orElse: () => other);
}

enum Repeat {
  none('NONE', 'Does not repeat'),
  daily('DAILY', 'Every day'),
  weekly('WEEKLY', 'Every week'),
  monthly('MONTHLY', 'Every month'),
  yearly('YEARLY', 'Every year');

  const Repeat(this.code, this.label);
  final String code;
  final String label;

  static Repeat fromCode(String? code) =>
      values.firstWhere((r) => r.code == code, orElse: () => none);
}

/// Reminder choices offered in the form (minutes before the event).
const reminderChoices = <int?, String>{
  null: 'No reminder',
  0: 'At the time',
  15: '15 minutes before',
  60: '1 hour before',
  1440: '1 day before',
};

/// All-day events remind at this time (9:00 AM).
const allDayReminderMinute = 9 * 60;

/// What the user fills in; also what is sent to the backend.
class EventDraft {
  const EventDraft({
    required this.title,
    required this.day,
    this.minuteOfDay,
    this.category = EventCategory.other,
    this.repeat = Repeat.none,
    this.remindMinutes,
    this.note = '',
  });

  final String title;

  /// The date (time part ignored).
  final DateTime day;

  /// Minutes after midnight, or null for an all-day event.
  final int? minuteOfDay;
  final EventCategory category;
  final Repeat repeat;
  final int? remindMinutes;
  final String note;

  Map<String, dynamic> toJson(QboxRole role) => {
    'role': roleCode(role),
    'title': title.trim(),
    'note': note.trim().isEmpty ? null : note.trim(),
    'category': category.code,
    'day': dateKey(day),
    'time': minuteOfDay == null ? null : timeKey(minuteOfDay!),
    'repeat': repeat.code,
    'remindMinutes': remindMinutes,
  };
}

/// An event saved on the server.
class CalendarEvent extends EventDraft {
  const CalendarEvent({
    required this.id,
    required super.title,
    required super.day,
    super.minuteOfDay,
    super.category,
    super.repeat,
    super.remindMinutes,
    super.note,
  });

  final int id;

  static CalendarEvent? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final title = json['title'];
    final day = DateTime.tryParse('${json['day']}');
    if (id is! int || title is! String || day == null) return null;
    return CalendarEvent(
      id: id,
      title: title,
      day: DateTime(day.year, day.month, day.day),
      minuteOfDay: parseTime(json['time'] as String?),
      category: EventCategory.fromCode(json['category'] as String?),
      repeat: Repeat.fromCode(json['repeat'] as String?),
      remindMinutes: (json['remindMinutes'] as num?)?.toInt(),
      note: json['note'] as String? ?? '',
    );
  }

  Map<String, dynamic> toCacheJson() => {
    'id': id,
    'title': title,
    'day': dateKey(day),
    'time': minuteOfDay == null ? null : timeKey(minuteOfDay!),
    'category': category.code,
    'repeat': repeat.code,
    'remindMinutes': remindMinutes,
    'note': note,
  };

  /// True if this event happens on [date] (repeats included).
  bool occursOn(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    if (d.isBefore(day)) return false;
    return switch (repeat) {
      Repeat.none => isSameDay(d, day),
      Repeat.daily => true,
      Repeat.weekly => d.weekday == day.weekday,
      Repeat.monthly => d.day == _clampedDay(d.year, d.month, day.day),
      Repeat.yearly =>
        d.month == day.month && d.day == _clampedDay(d.year, d.month, day.day),
    };
  }

  /// The next start (date + time) at or after [from], or null if none.
  DateTime? nextStart(DateTime from) {
    final minute = minuteOfDay ?? allDayReminderMinute;
    var d = DateTime(from.year, from.month, from.day);
    if (d.isBefore(day)) d = day;
    // Look ahead up to just over a year: enough for every repeat type.
    for (var i = 0; i < 400; i++) {
      if (occursOn(d)) {
        final start = DateTime(
          d.year,
          d.month,
          d.day,
          minute ~/ 60,
          minute % 60,
        );
        if (!start.isBefore(from)) return start;
      }
      if (repeat == Repeat.none && d.isAfter(day)) return null;
      d = DateTime(d.year, d.month, d.day + 1);
    }
    return null;
  }
}

/// A built-in festival or holiday.
class Festival {
  const Festival({required this.day, required this.name, required this.telugu});

  final DateTime day;
  final String name;

  /// True for Telangana / Andhra festivals, false for all-India ones.
  final bool telugu;

  static Festival? fromJson(Object? json) {
    if (json is! Map) return null;
    final day = DateTime.tryParse('${json['day']}');
    final name = json['name'];
    if (day == null || name is! String) return null;
    return Festival(
      day: DateTime(day.year, day.month, day.day),
      name: name,
      telugu: json['region'] == 'TELUGU',
    );
  }

  Map<String, dynamic> toJson() => {
    'day': dateKey(day),
    'name': name,
    'region': telugu ? 'TELUGU' : 'ALL',
  };
}

// ---- date helpers ----------------------------------------------------------

bool isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

int daysInMonth(int year, int month) => DateTime(year, month + 1, 0).day;

/// "Every month on the 31st" falls on the last day of shorter months.
int _clampedDay(int year, int month, int wanted) =>
    wanted > daysInMonth(year, month) ? daysInMonth(year, month) : wanted;

String dateKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String timeKey(int minute) =>
    '${(minute ~/ 60).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')}';

/// "10:30" or "10:30:00" -> 630. Null for empty or bad text.
int? parseTime(String? text) {
  if (text == null || text.isEmpty) return null;
  final parts = text.split(':');
  if (parts.length < 2) return null;
  final h = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  if (h == null || m == null || h > 23 || m > 59) return null;
  return h * 60 + m;
}

/// 630 -> "10:30 AM"
String timeLabel(int minute) {
  final h = minute ~/ 60;
  final m = minute % 60;
  final hour12 = h % 12 == 0 ? 12 : h % 12;
  return '$hour12:${m.toString().padLeft(2, '0')} ${h < 12 ? 'AM' : 'PM'}';
}

const monthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];
const weekdayShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// "Wed, 25 November 2026"
String longDate(DateTime d) =>
    '${weekdayShort[d.weekday - 1]}, ${d.day} ${monthNames[d.month - 1]} ${d.year}';
