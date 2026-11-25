import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qbox_app/calendar/calendar_models.dart';
import 'package:qbox_app/calendar/calendar_screen.dart';
import 'package:qbox_app/calendar/calendar_store.dart';
import 'package:qbox_app/onboarding_draft.dart';
import 'package:qbox_app/services/app_services.dart';

import 'fake_auth_api.dart';

final today = DateTime(2026, 11, 19); // a Thursday

Future<void> openCalendar(
  WidgetTester tester,
  AppServices services, {
  QboxRole role = QboxRole.business,
}) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ServicesScope(
      services: services,
      child: MaterialApp(home: CalendarScreen(role: role, today: today)),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> tapKey(WidgetTester tester, String key) async {
  final finder = find.byKey(Key(key));
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle(); // let the scroll finish before tapping
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// Types a title, then closes the keyboard (as a person would before tapping Save).
Future<void> typeTitle(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(const Key('event-title')), text);
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the month, and festivals on their day', (tester) async {
    await openCalendar(tester, fakeServices());
    expect(find.text('November 2026'), findsOneWidget);
    expect(find.text('Today · Thu, 19 November 2026'), findsOneWidget);
    expect(find.byKey(const Key('calendar-empty')), findsOneWidget);

    await tapKey(tester, 'calendar-day-2026-11-08');
    expect(find.text('Deepavali'), findsOneWidget);
    expect(find.text('All India'), findsOneWidget);
  });

  testWidgets('month arrows and Today button', (tester) async {
    await openCalendar(tester, fakeServices());
    await tapKey(tester, 'calendar-next');
    expect(find.text('December 2026'), findsOneWidget);
    await tapKey(tester, 'calendar-today');
    expect(find.text('November 2026'), findsOneWidget);
  });

  testWidgets('add an event: saved on the server, shown, reminder set', (tester) async {
    final api = FakeCalendarApi();
    final reminders = FakeReminders();
    await openCalendar(tester, fakeServices(calendar: api, reminders: reminders));

    await tapKey(tester, 'calendar-add');
    await typeTitle(tester, 'Count cash');
    await tapKey(tester, 'event-save');

    expect(api.saved[QboxRole.business]!.single.title, 'Count cash');
    expect(find.text('Count cash'), findsOneWidget);
    expect(find.text('10:00 AM'), findsOneWidget);
    expect(reminders.permissionAsks, 1);
    expect(reminders.synced[QboxRole.business]!.single.title, 'Count cash');
  });

  testWidgets('an empty title is not saved', (tester) async {
    final api = FakeCalendarApi();
    await openCalendar(tester, fakeServices(calendar: api));
    await tapKey(tester, 'calendar-add');
    await tapKey(tester, 'event-save');
    expect(find.text('Enter a title'), findsOneWidget);
    expect(api.saved, isEmpty);
  });

  testWidgets('voice add fills the form for checking, then saves', (tester) async {
    final api = FakeCalendarApi();
    final voice = FakeVoiceInput()
      ..nextWords = 'remind me tomorrow at 10 am supplier payment';
    await openCalendar(tester, fakeServices(calendar: api, voice: voice));

    await tapKey(tester, 'calendar-speak');
    expect(find.byKey(const Key('event-voice-note')), findsOneWidget);
    expect(find.text('Supplier payment'), findsOneWidget);
    expect(find.text('Fri, 20 November 2026'), findsOneWidget);

    await tapKey(tester, 'event-save');
    final saved = api.saved[QboxRole.business]!.single;
    expect(saved.category, EventCategory.payment);
    expect(saved.minuteOfDay, 600);
    // The calendar jumps to the saved day.
    expect(find.text('Fri, 20 November 2026'), findsOneWidget);
    expect(find.text('Supplier payment'), findsOneWidget);
  });

  testWidgets('edit and delete an event', (tester) async {
    final api = FakeCalendarApi();
    final event = await api.create(
      QboxRole.business,
      EventDraft(title: 'Rent', day: today, minuteOfDay: 600),
    );
    await openCalendar(tester, fakeServices(calendar: api));

    await tapKey(tester, 'calendar-event-${event.id}');
    await typeTitle(tester, 'Shop rent');
    await tapKey(tester, 'event-save');
    expect(find.text('Shop rent'), findsOneWidget);

    await tapKey(tester, 'calendar-event-${event.id}');
    await tapKey(tester, 'event-delete');
    await tapKey(tester, 'event-delete-confirm');
    expect(api.saved[QboxRole.business], isEmpty);
    expect(find.text('Shop rent'), findsNothing);
  });

  testWidgets('a monthly event shows in the following months too', (tester) async {
    final api = FakeCalendarApi();
    await api.create(
      QboxRole.business,
      EventDraft(title: 'EMI', day: DateTime(2026, 11, 5), repeat: Repeat.monthly),
    );
    await openCalendar(tester, fakeServices(calendar: api));
    await tapKey(tester, 'calendar-next');
    await tapKey(tester, 'calendar-day-2026-12-05');
    expect(find.text('EMI'), findsOneWidget);
    expect(find.text('Every month'), findsOneWidget);
  });

  testWidgets('offline: shows the saved copy and says so', (tester) async {
    final store = MemoryCalendarStore()
      ..events[QboxRole.business] = [
        CalendarEvent(id: 9, title: 'Saved earlier', day: today, minuteOfDay: 480),
      ];
    final api = FakeCalendarApi()..offline = true;
    await openCalendar(tester, fakeServices(calendar: api, calendarStore: store));

    expect(find.byKey(const Key('calendar-offline')), findsOneWidget);
    expect(find.text('Saved earlier'), findsOneWidget);

    // Adding works too: it is sent later.
    await tapKey(tester, 'calendar-add');
    await typeTitle(tester, 'New');
    await tapKey(tester, 'event-save');
    await tester.pump(const Duration(seconds: 4)); // the message goes
    await tester.pumpAndSettle();
    await tester.drag(find.text('Saved earlier'), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(find.text('New'), findsOneWidget);
    expect(store.changes.single.draft!.title, 'New');
  });

  testWidgets('shop and personal calendars are separate', (tester) async {
    final api = FakeCalendarApi();
    await api.create(QboxRole.business, EventDraft(title: 'Shop thing', day: today));
    await openCalendar(tester, fakeServices(calendar: api), role: QboxRole.customer);
    expect(find.text('My Calendar'), findsOneWidget);
    expect(find.text('Shop thing'), findsNothing);
  });

  test('log out forgets the calendar copy and every reminder', () async {
    final store = MemoryCalendarStore()
      ..events[QboxRole.business] = [CalendarEvent(id: 1, title: 'x', day: today)];
    final reminders = FakeReminders();
    final services = fakeServices(calendarStore: store, reminders: reminders);
    await services.forgetUserData();
    expect(store.events, isEmpty);
    expect(reminders.cleared, isTrue);
  });
}
