import 'package:flutter_test/flutter_test.dart';
import 'package:qbox_app/calendar/calendar_models.dart';
import 'package:qbox_app/calendar/reminders.dart';
import 'package:qbox_app/calendar/voice_event.dart';

CalendarEvent event({
  required DateTime day,
  int? minute,
  Repeat repeat = Repeat.none,
  int? remind,
}) =>
    CalendarEvent(
      id: 1,
      title: 'Test',
      day: day,
      minuteOfDay: minute,
      repeat: repeat,
      remindMinutes: remind,
    );

void main() {
  // Thursday, 19 November 2026, 3 PM
  final now = DateTime(2026, 11, 19, 15);

  group('repeats', () {
    test('a one-time event happens only on its day', () {
      final e = event(day: DateTime(2026, 11, 25));
      expect(e.occursOn(DateTime(2026, 11, 25)), isTrue);
      expect(e.occursOn(DateTime(2026, 11, 26)), isFalse);
    });

    test('daily and weekly', () {
      final daily = event(day: DateTime(2026, 11, 19), repeat: Repeat.daily);
      expect(daily.occursOn(DateTime(2027, 3, 1)), isTrue);
      expect(daily.occursOn(DateTime(2026, 11, 18)), isFalse); // before it starts
      final weekly = event(day: DateTime(2026, 11, 23), repeat: Repeat.weekly); // Monday
      expect(weekly.occursOn(DateTime(2026, 11, 30)), isTrue);
      expect(weekly.occursOn(DateTime(2026, 12, 1)), isFalse);
    });

    test('every month on the 31st falls on the last day of short months', () {
      final rent = event(day: DateTime(2026, 1, 31), repeat: Repeat.monthly);
      expect(rent.occursOn(DateTime(2026, 2, 28)), isTrue);
      expect(rent.occursOn(DateTime(2026, 4, 30)), isTrue);
      expect(rent.occursOn(DateTime(2026, 4, 29)), isFalse);
      expect(rent.occursOn(DateTime(2026, 5, 31)), isTrue);
    });

    test('yearly on 29 February uses 28 February in other years', () {
      final e = event(day: DateTime(2028, 2, 29), repeat: Repeat.yearly);
      expect(e.occursOn(DateTime(2029, 2, 28)), isTrue);
      expect(e.occursOn(DateTime(2032, 2, 29)), isTrue);
    });
  });

  group('next start and reminders', () {
    test('one-time event', () {
      final e = event(day: DateTime(2026, 11, 25), minute: 630, remind: 60);
      expect(e.nextStart(now), DateTime(2026, 11, 25, 10, 30));
      expect(nextReminderTime(e, now), DateTime(2026, 11, 25, 9, 30));
      expect(e.nextStart(DateTime(2026, 11, 26)), isNull);
    });

    test('no reminder chosen means no notification', () {
      expect(nextReminderTime(event(day: DateTime(2026, 11, 25), minute: 600), now), isNull);
    });

    test('all-day events remind at 9 AM', () {
      final e = event(day: DateTime(2026, 11, 25), remind: 0);
      expect(nextReminderTime(e, now), DateTime(2026, 11, 25, 9));
    });

    test('a passed reminder moves to the next repeat', () {
      // Monthly on the 5th at 10:00, remind 1 day before; it is now 4 Dec, noon.
      final e = event(day: DateTime(2026, 11, 5), minute: 600, repeat: Repeat.monthly, remind: 1440);
      expect(nextReminderTime(e, DateTime(2026, 12, 4, 12)), DateTime(2027, 1, 4, 10));
    });

    test('reminder text says the right day', () {
      String body(CalendarEvent e) => reminderBody(e, nextReminderTime(e, now)!);

      // All-day, 1 day before: rings 9 AM the day before -> "Tomorrow" (was "Today").
      expect(
        body(event(day: DateTime(2026, 11, 25), remind: 1440)),
        'Tomorrow · All day · Other',
      );
      // All-day, at the time: rings 9 AM that day.
      expect(
        body(event(day: DateTime(2026, 11, 25), remind: 0)),
        'Today · All day · Other',
      );
      // 10 AM, 1 day before.
      expect(
        body(event(day: DateTime(2026, 11, 25), minute: 600, remind: 1440)),
        'Tomorrow · 10:00 AM · Other',
      );
      // 10 AM, 1 hour before.
      expect(
        body(event(day: DateTime(2026, 11, 25), minute: 600, remind: 60)),
        'Today · 10:00 AM · Other',
      );
      // 12:10 AM, 15 min before: rings 11:55 PM the night before.
      expect(
        body(event(day: DateTime(2026, 11, 25), minute: 10, remind: 15)),
        'Tomorrow · 12:10 AM · Other',
      );
      // More than a day ahead: the date.
      expect(
        body(event(day: DateTime(2026, 11, 25), minute: 600, remind: 2880)),
        'Wed, 25 November 2026 · 10:00 AM · Other',
      );
      // The note is shown when there is one.
      final withNote = CalendarEvent(
        id: 2,
        title: 'Rent',
        day: DateTime(2026, 11, 25),
        minuteOfDay: 600,
        category: EventCategory.payment,
        note: 'Pay owner 15,000',
        remindMinutes: 1440,
      );
      expect(body(withNote), 'Tomorrow · 10:00 AM · Pay owner 15,000');
    });

    test('a past one-time event has no reminder', () {
      final e = event(day: DateTime(2026, 11, 1), minute: 600, remind: 0);
      expect(nextReminderTime(e, now), isNull);
    });
  });

  group('helpers', () {
    test('times and dates', () {
      expect(parseTime('10:30:00'), 630);
      expect(parseTime('25:00'), isNull);
      expect(timeLabel(630), '10:30 AM');
      expect(timeLabel(0), '12:00 AM');
      expect(timeLabel(13 * 60 + 5), '1:05 PM');
      expect(dateKey(DateTime(2026, 3, 9)), '2026-03-09');
      expect(longDate(DateTime(2026, 11, 19)), 'Thu, 19 November 2026');
    });

    test('server JSON is read safely', () {
      final e = CalendarEvent.fromJson({
        'id': 7,
        'title': 'Rent',
        'day': '2026-12-05',
        'time': '10:00:00',
        'category': 'PAYMENT',
        'repeat': 'MONTHLY',
        'remindMinutes': 1440,
        'note': null,
      })!;
      expect(e.minuteOfDay, 600);
      expect(e.category, EventCategory.payment);
      expect(e.repeat, Repeat.monthly);
      expect(CalendarEvent.fromJson({'id': 'x'}), isNull);
      expect(CalendarEvent.fromJson('junk'), isNull);
    });
  });

  group('voice: spoken sentence to event', () {
    EventDraft parse(String s) => parseSpokenEvent(s, now)!;

    test('tomorrow at 10 am, payment', () {
      final d = parse('Remind me tomorrow at 10 a.m. supplier payment');
      expect(d.title, 'Supplier payment');
      expect(d.day, DateTime(2026, 11, 20));
      expect(d.minuteOfDay, 600);
      expect(d.category, EventCategory.payment);
      expect(d.remindMinutes, 0);
    });

    test('every month on the 5th', () {
      final d = parse('rent every month on the 5th');
      expect(d.title, 'Rent');
      expect(d.repeat, Repeat.monthly);
      expect(d.day, DateTime(2026, 12, 5)); // the 5th has passed this month
      expect(d.minuteOfDay, isNull);
      expect(d.category, EventCategory.payment);
    });

    test('every Monday at 9 am', () {
      final d = parse('stock check every monday 9 am');
      expect(d.title, 'Stock check');
      expect(d.repeat, Repeat.weekly);
      expect(d.day, DateTime(2026, 11, 23));
      expect(d.minuteOfDay, 540);
      expect(d.category, EventCategory.supplier);
    });

    test('a date with a month name', () {
      final d = parse('doctor on 25 november at 6 pm');
      expect(d.title, 'Doctor');
      expect(d.day, DateTime(2026, 11, 25));
      expect(d.minuteOfDay, 18 * 60);
      expect(d.category, EventCategory.personal);
    });

    test('a passed date means next year', () {
      expect(parse('birthday party on 3 january').day, DateTime(2027, 1, 3));
      expect(parse('gst filing every year on 20 march').day, DateTime(2027, 3, 20));
    });

    test('day/month numbers (Indian order)', () {
      final d = parse('electricity bill 25/12');
      expect(d.day, DateTime(2026, 12, 25));
      expect(d.title, 'Electricity bill');
    });

    test('"at 5" in a shop means 5 PM; morning, tonight, 10.30', () {
      expect(parse('call ravi at 5').minuteOfDay, 17 * 60);
      expect(parse('pay salary on friday morning').minuteOfDay, 9 * 60);
      expect(parse('pay salary on friday morning').day, DateTime(2026, 11, 20));
      expect(parse('tonight family dinner').minuteOfDay, 20 * 60);
      expect(parse('10.30 am order milk').minuteOfDay, 630);
    });

    test('in 2 hours / in 3 days', () {
      final d = parse('meeting in 2 hours');
      expect(d.day, DateTime(2026, 11, 19));
      expect(d.minuteOfDay, 17 * 60);
      expect(parse('collect cheque in 3 days').day, DateTime(2026, 11, 22));
    });

    test('nothing but a title: today, all day', () {
      final d = parse('clean the shop');
      expect(d.title, 'Clean the shop');
      expect(d.day, DateTime(2026, 11, 19));
      expect(d.minuteOfDay, isNull);
    });

    test('empty speech gives nothing; no title becomes "Reminder"', () {
      expect(parseSpokenEvent('  ', now), isNull);
      expect(parse('remind me tomorrow').title, 'Reminder');
    });
  });
}
