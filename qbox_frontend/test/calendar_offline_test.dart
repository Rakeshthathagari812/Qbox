import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qbox_app/calendar/calendar_models.dart';
import 'package:qbox_app/calendar/calendar_repository.dart';
import 'package:qbox_app/calendar/calendar_store.dart';
import 'package:qbox_app/calendar/reminders.dart';
import 'package:qbox_app/calendar/spoken_time.dart';
import 'package:qbox_app/calendar/voice_event.dart';
import 'package:qbox_app/onboarding_draft.dart';
import 'package:qbox_app/translator/languages.dart';

import 'calendar_screen_test.dart' show openCalendar, tapKey, today, typeTitle;
import 'calculator_screen_test.dart' show HeldVoice;
import 'fake_auth_api.dart';

void main() {
  group('times, however they are said', () {
    final noon = DateTime(2026, 11, 25, 12);
    String at(String words, [DateTime? now]) {
      final d = parseSpokenEvent(words, now ?? noon)!;
      final m = d.minuteOfDay;
      return m == null ? 'none | ${d.title}' : '${timeKey(m)} | ${d.title}';
    }

    test('3:10', () {
      for (final said in [
        'meeting at 3:10', 'meeting at 3.10 p.m.', 'meeting at 3:10 p m', 'meeting at 3 10', 'meeting at 3 10 pm',
        'meeting 310 pm', 'meeting at 310', 'meeting at 3 oclock 10 minutes', 'meeting at 3 hours 10 minutes',
        'meeting at ten past three', 'meeting 10 minutes past 3', 'meeting at three ten', 'meeting three ten pm',
        'meeting at 10 past 3 in the afternoon', "meeting at 3 o'clock and 10 minutes",
      ]) {
        expect(at(said), '15:10 | Meeting', reason: said);
      }
    });

    test('10:29 at night, however it is said', () {
      final night = DateTime(2026, 11, 25, 22, 27);
      String said(String words) {
        final d = parseSpokenEvent(words, night)!;
        return '${d.day.day} ${d.minuteOfDay == null ? 'none' : timeKey(d.minuteOfDay!)} ${d.title}';
      }

      for (final s in [
        'meeting at 10:29', 'meeting at 10 29', 'meeting 10 29', '10 29 meeting', 'meeting by 10 29', 'meeting at 10 to 29',
        'meeting at 10 and 29 minutes', 'meeting 10 oclock 29 minutes', 'meeting at ten twenty nine', 'meeting ten twenty nine',
        'meeting at 10:00 29', 'today at 10:29 meeting', 'today at 10:29 meeting pm', 'meeting 10:29 p.m.',
      ]) {
        expect(said(s), '25 22:29 Meeting', reason: s);
      }
      expect(said('today at 10:30 I should go to shopping pm'), '25 22:30 I should go to shopping');
      expect(said('remind me 10 29'), '25 22:29 Reminder');
      expect(said('reminder 1029'), '25 22:29 Reminder');
      expect(said('tomorrow at 10:29 i am going'), '26 10:29 I am going');
      expect(said('today at 9 am meeting'), '25 09:00 Meeting'); // as said
      for (final s in [
        '10 గంటల 29 నిమిషాలకు మీటింగ్', 'పది గంటల ఇరవై తొమ్మిది నిమిషాలకు మీటింగ్', 'పది గంటల ఇరవైతొమ్మిది నిమిషాలకు',
        'పదిగంటల ఇరవైతొమ్మిది నిమిషాలకి', '10 గంటల 29 కి', '10:29 కి మీటింగ్', '10 29 కి మీటింగ్', 'పది ఇరవై తొమ్మిదికి మీటింగ్',
        'రాత్రి పది ఇరవై తొమ్మిది కి', 'టెన్ ట్వంటీ నైన్ కి మీటింగ్', 'టెన్ ట్వంటీ నైన్ పీఎం కి మీటింగ్',
      ]) {
        final t = nativeTime(s, AppLanguage.telugu);
        expect(t, isNotNull, reason: s);
        expect(t!.minute % 720, 10 * 60 + 29, reason: s);
        final d = parseSpokenEvent('meeting', night, spokenTime: t)!;
        expect((d.day.day, timeKey(d.minuteOfDay!)), (25, '22:29'), reason: s);
      }
      expect(nativeTime('10 29 पर मीटिंग', AppLanguage.hindi)!.minute, 629);
      expect(nativeTime('ರಾತ್ರಿ 10 ಗಂಟೆ 29 ನಿಮಿಷಕ್ಕೆ', AppLanguage.kannada)!.minute, 22 * 60 + 29);
      expect(nativeTime('இரவு 10 மணி 29 நிமிடத்திற்கு', AppLanguage.tamil)!.minute, 22 * 60 + 29);
      expect(nativeTime('రేపు 10 కిలోల బియ్యం', AppLanguage.telugu), isNull);
    });

    test('others', () {
      expect(at('meeting at half past 3'), '15:30 | Meeting');
      expect(at('meeting at quarter past 3'), '15:15 | Meeting');
      expect(at('meeting at quarter to 4'), '15:45 | Meeting');
      expect(at('meeting 10 minutes to 4'), '15:50 | Meeting');
      expect(at('meeting at four forty five'), '16:45 | Meeting');
      expect(at('meeting at 6 05 pm'), '18:05 | Meeting');
      expect(at('meeting at 1030 pm'), '22:30 | Meeting');
      expect(at('call ravi at 5'), '17:00 | Call ravi');
      expect(at('tomorrow morning at 7 20 doctor'), '07:20 | Doctor');
      expect(at('tomorrow at 10 am supplier payment'), '10:00 | Supplier payment');
    });

    test('numbers that are not times stay in the title', () {
      expect(at('tomorrow collect 310 rupees from ravi'), 'none | Collect 310 rupees from ravi');
      expect(at('tomorrow buy 5 50 kg bags'), 'none | Buy 5 50 kg bags');
      expect(at('doctor on 25 november at 6 pm'), '18:00 | Doctor');
      expect(at('tomorrow at 5 50 kg rice comes'), '17:00 | 50 kg rice comes');
    });

    test('in 2 hours 10 minutes, after 10 minutes, in half an hour', () {
      expect(at('meeting in 2 hours 10 minutes'), '14:10 | Meeting');
      expect(at('meeting after 10 minutes'), '12:10 | Meeting');
      expect(at('meeting in half an hour'), '12:30 | Meeting');
      final late = parseSpokenEvent('meeting in 30 minutes', DateTime(2026, 11, 25, 23, 50))!;
      expect((late.day, late.minuteOfDay), (DateTime(2026, 11, 26), 20));
    });

    test('a time that has passed today can still ring', () {
      final evening = DateTime(2026, 11, 25, 18);
      expect(parseSpokenEvent('meeting at 3:10 pm', evening)!.day, DateTime(2026, 11, 26));
      final nine = parseSpokenEvent('meeting at 9', evening)!;
      expect((nine.day, nine.minuteOfDay), (DateTime(2026, 11, 25), 21 * 60)); // 9 tonight
      final nineAm = parseSpokenEvent('meeting at 9 am', evening)!;
      expect((nineAm.day, nineAm.minuteOfDay), (DateTime(2026, 11, 26), 9 * 60));
      expect(parseSpokenEvent('today at 3:10 pm meeting', evening)!.day, DateTime(2026, 11, 25)); // as said
    });

    test('in Telugu, Hindi, Kannada and Tamil, before translating', () {
      String? said(String words, AppLanguage lang) {
        final t = nativeTime(words, lang);
        return t == null ? null : timeKey(t.minute);
      }

      expect(said('మధ్యాహ్నం 3 గంటల 10 నిమిషాలకు మీటింగ్', AppLanguage.telugu), '15:10');
      expect(said('మూడు గంటల పది నిమిషాలకు మీటింగ్', AppLanguage.telugu), '15:10');
      expect(said('రేపు ఉదయం 10 గంటలకు సప్లయర్ పేమెంట్', AppLanguage.telugu), '10:00');
      expect(said('3:10 కి మీటింగ్', AppLanguage.telugu), '15:10');
      expect(said('మూడున్నర గంటలకు', AppLanguage.telugu), '15:30');
      expect(said('రాత్రి 9 గంటలకు', AppLanguage.telugu), '21:00');
      expect(said('3 గంటల తర్వాత గుర్తు చేయి', AppLanguage.telugu), isNull); // after 3 hours
      expect(said('दोपहर 3 बजकर 10 मिनट पर मीटिंग', AppLanguage.hindi), '15:10');
      expect(said('शाम 6 बजे', AppLanguage.hindi), '18:00');
      expect(said('साढ़े तीन बजे', AppLanguage.hindi), '15:30');
      expect(said('ಮಧ್ಯಾಹ್ನ 3 ಗಂಟೆ 10 ನಿಮಿಷಕ್ಕೆ', AppLanguage.kannada), '15:10');
      expect(said('ಬೆಳಿಗ್ಗೆ 9 ಗಂಟೆಗೆ', AppLanguage.kannada), '09:00');
      expect(said('மாலை 3 மணி 10 நிமிடத்திற்கு', AppLanguage.tamil), '15:10');
      expect(said('காலை 9 மணிக்கு', AppLanguage.tamil), '09:00');
      expect(said('2 மணி நேரம் கழித்து', AppLanguage.tamil), isNull);
      expect(said('త్రీ గంటల టెన్ నిమిషాలకు', AppLanguage.telugu), '15:10');
      // The translation lost the minutes; what was said counts.
      final d = parseSpokenEvent(
        "meeting at 3 o'clock",
        noon,
        spokenTime: nativeTime('3 గంటల 10 నిమిషాలకు మీటింగ్', AppLanguage.telugu),
      )!;
      expect((d.title, timeKey(d.minuteOfDay!)), ('Meeting', '15:10'));
    });
  });

  group('without internet', () {
    late FakeCalendarApi api;
    late MemoryCalendarStore store;
    late FakeReminders reminders;
    late CalendarRepository repo;
    const role = QboxRole.business;

    setUp(() {
      api = FakeCalendarApi();
      store = MemoryCalendarStore();
      reminders = FakeReminders();
      repo = CalendarRepository(api, store, reminders);
    });

    EventDraft draft(String title, [int minute = 600]) =>
        EventDraft(title: title, day: today, minuteOfDay: minute, remindMinutes: 0);
    List<String> titles(List<CalendarEvent>? events) => [for (final e in events ?? const <CalendarEvent>[]) e.title];

    test('added: shown and reminded of at once, sent later', () async {
      api.offline = true;
      final made = await repo.create(role, draft('Rent'));
      expect(made.id, lessThan(0));
      expect(titles(store.events[role]), ['Rent']);
      expect(titles(reminders.synced[role]), ['Rent']);
      expect(await repo.pendingCount(), 1);
      api.offline = false;
      expect(titles(await repo.events(role)), ['Rent']);
      expect(titles(api.saved[role]), ['Rent']);
      expect(store.events[role]!.single.id, greaterThan(0));
      expect(await repo.pendingCount(), 0);
    });

    test('changed and deleted', () async {
      final a = await repo.create(role, draft('A'));
      final b = await repo.create(role, draft('B'));
      api.offline = true;
      await repo.update(role, a.id, draft('A two', 700));
      await repo.update(role, a.id, draft('A three', 710));
      await repo.delete(b.id);
      expect(titles(store.events[role]), ['A three']);
      expect(titles(reminders.synced[role]), ['A three']);
      expect(await repo.pendingCount(), 2);
      api.offline = false;
      expect(titles(await repo.events(role)), ['A three']);
      expect(api.saved[role]!.single.minuteOfDay, 710);
    });

    test('added, changed and deleted before it was ever sent', () async {
      api.offline = true;
      final a = await repo.create(role, draft('A'));
      final b = await repo.create(role, draft('B'));
      expect(a.id, isNot(b.id));
      await repo.update(role, a.id, draft('A two'));
      await repo.delete(b.id);
      expect(titles(store.events[role]), ['A two']);
      api.offline = false;
      await repo.events(role);
      expect(titles(api.saved[role]), ['A two']);
    });

    test('saved by the server but no answer came: not twice, and the later change counts', () async {
      api.loseAnswer = true;
      final a = await repo.create(role, draft('A'));
      expect(titles(api.saved[role]), ['A']);
      api.offline = true;
      await repo.update(role, a.id, draft('A two'));
      api.offline = false;
      expect(titles(await repo.events(role)), ['A two']);
      expect(titles(api.saved[role]), ['A two']);
    });

    test('a screen still holding the old id', () async {
      api.offline = true;
      final a = await repo.create(role, draft('A'));
      api.offline = false;
      await repo.events(role);
      await repo.update(role, a.id, draft('A two'));
      expect(titles(api.saved[role]), ['A two']);
      await repo.delete(a.id);
      expect(api.saved[role], isEmpty);
      expect(titles(store.events[role]), isEmpty);
    });

    test('the phone was restarted: still there, still sent', () async {
      api.offline = true;
      await repo.create(role, draft('A'));
      final saved = [for (final c in store.changes) CalendarChange.fromJson(c.toJson())!];
      store.changes = saved;
      final again = CalendarRepository(api, store, reminders);
      api.offline = false;
      expect(titles(await again.events(role)), ['A']);
      expect(CalendarChange.fromJson('x'), isNull);
    });

    test('QBOX opened again: every reminder is set, with and without internet', () async {
      await repo.create(role, draft('A'));
      reminders.synced.clear();
      api.offline = true;
      await repo.remindAgain([role, QboxRole.customer]);
      expect(titles(reminders.synced[role]), ['A']);
      // Added on another phone.
      api.offline = false;
      await api.create(role, draft('B'));
      await repo.remindAgain([role]);
      expect(titles(reminders.synced[role]), ['A', 'B']);
    });

    testWidgets('on the screen', (tester) async {
      api.offline = true;
      final services = fakeServices(calendar: api, calendarStore: store, reminders: reminders);
      await openCalendar(tester, services);
      await tapKey(tester, 'calendar-add');
      await typeTitle(tester, 'Pay rent');
      await tapKey(tester, 'event-save');
      expect(find.text('Pay rent'), findsOneWidget);
      expect(find.text('Saved on this phone. It will be sent when there is internet.'), findsOneWidget);
      expect(find.text('Offline: saved on this phone. 1 to send when there is internet.'), findsOneWidget);
      expect(await services.unsentCount(), 1);
      await tester.pump(const Duration(seconds: 4)); // the message goes
      await tester.pumpAndSettle();
      await tapKey(tester, 'calendar-event--1');
      await tapKey(tester, 'event-delete');
      await tapKey(tester, 'event-delete-confirm');
      expect(find.text('Pay rent'), findsNothing);
      expect(await services.unsentCount(), 0);
    });
  });

  group('ringing on time', () {
    testWidgets('asks for exact time, then sets the reminders again', (tester) async {
      final reminders = FakeReminders()..now = ReminderProblem.notExact;
      await openCalendar(tester, fakeServices(reminders: reminders));
      expect(find.text('Make reminders ring on time'), findsOneWidget);
      reminders.synced.clear();
      await tapKey(tester, 'calendar-on-time');
      await tapKey(tester, 'on-time-allow');
      expect(reminders.exactAsks, 1);
      expect(find.byKey(const Key('calendar-on-time')), findsNothing);
      expect(reminders.synced.containsKey(QboxRole.business), isTrue);
    });

    testWidgets('notifications off: opens the settings', (tester) async {
      final device = FakeDeviceActions();
      final reminders = FakeReminders()..now = ReminderProblem.notificationsOff;
      await openCalendar(tester, fakeServices(reminders: reminders, device: device));
      expect(find.text('Notifications are off: reminders cannot ring'), findsOneWidget);
      await tapKey(tester, 'calendar-on-time');
      expect(find.byKey(const Key('on-time-allow')), findsNothing);
      await tapKey(tester, 'on-time-settings');
      expect(device.settingsOpened, 1);
    });
  });

  testWidgets('the Speak button says Getting ready, then Listening; a tap still stops', (tester) async {
    final voice = HeldVoice();
    await openCalendar(tester, fakeServices(voice: voice));
    await tester.tap(find.byKey(const Key('calendar-speak')));
    await tester.pump();
    Finder onButton(String words) => find.descendant(of: find.byKey(const Key('calendar-speak')), matching: find.text(words));
    expect(onButton('Getting ready…'), findsOneWidget);
    voice.ready!();
    await tester.pump();
    expect(onButton('Listening…'), findsOneWidget);
    expect(find.text('Stop'), findsNothing);
    voice.words('meeting at 3 10 pm');
    await tester.tap(find.byKey(const Key('calendar-speak')));
    await tester.pumpAndSettle();
    expect(find.text('3:10 PM'), findsOneWidget);
  });
}
