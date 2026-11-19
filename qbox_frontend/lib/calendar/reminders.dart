import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/qbox_user.dart';
import '../onboarding_draft.dart';
import 'calendar_models.dart';

/// Phone notifications for calendar reminders. They are set on the phone
/// itself, so they ring even with no internet and with QBOX closed.
abstract class ReminderScheduler {
  /// Asks for permission to show notifications (Android 13+). True if allowed.
  Future<bool> askPermission();

  /// Replaces all reminders of one calendar with those of [events].
  Future<void> sync(QboxRole role, List<CalendarEvent> events);

  /// Removes every QBOX reminder (log out).
  Future<void> clearAll();
}

/// When a reminder should ring for [event], at or after [now]; null if never.
/// Pure date maths, kept outside the plugin so it can be tested.
DateTime? nextReminderTime(CalendarEvent event, DateTime now) {
  final before = event.remindMinutes;
  if (before == null) return null;
  // The reminder for an occurrence rings [before] minutes earlier, so look
  // for occurrences starting from now + before.
  final start = event.nextStart(now.add(Duration(minutes: before)));
  return start?.subtract(Duration(minutes: before));
}

/// The notification text for a reminder that rings at [remindAt]: which day
/// the event is (seen from the moment it rings), its time, and the note.
/// "Tomorrow · 10:00 AM · Payment", "Today · All day · Shop".
String reminderBody(CalendarEvent event, DateTime remindAt) {
  final start = remindAt.add(Duration(minutes: event.remindMinutes ?? 0));
  final days = DateTime.utc(start.year, start.month, start.day)
      .difference(DateTime.utc(remindAt.year, remindAt.month, remindAt.day))
      .inDays;
  final day = switch (days) {
    0 => 'Today',
    1 => 'Tomorrow',
    _ => longDate(start),
  };
  final time = event.minuteOfDay == null
      ? 'All day'
      : timeLabel(event.minuteOfDay!);
  final note = event.note.trim();
  return '$day · $time · ${note.isEmpty ? event.category.label : note}';
}

class LocalReminderScheduler implements ReminderScheduler {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _ready = false;

  static const _channel = AndroidNotificationDetails(
    'qbox_calendar',
    'Calendar reminders',
    channelDescription: 'Reminders for events in your QBOX calendar',
    importance: Importance.high,
    priority: Priority.high,
  );

  Future<bool> _init() async {
    if (_ready) return true;
    try {
      tzdata.initializeTimeZones();
      // QBOX is for Indian shops; reminders use Indian time.
      tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
      );
      _ready = true;
    } catch (_) {
      _ready = false;
    }
    return _ready;
  }

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  @override
  Future<bool> askPermission() async {
    if (!await _init()) return false;
    try {
      return await _android?.requestNotificationsPermission() ?? true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> sync(QboxRole role, List<CalendarEvent> events) async {
    if (!await _init()) return;
    try {
      final tag = 'role:${roleCode(role)}';
      for (final pending in await _plugin.pendingNotificationRequests()) {
        if (pending.payload == tag) await _plugin.cancel(id: pending.id);
      }
      final now = DateTime.now();
      for (final event in events) {
        final at = nextReminderTime(event, now);
        if (at == null) continue;
        await _plugin.zonedSchedule(
          id: _notificationId(role, event.id),
          scheduledDate: tz.TZDateTime.from(at, tz.local),
          notificationDetails: const NotificationDetails(android: _channel),
          // Inexact: may ring a few minutes late, but needs no special
          // "exact alarm" permission from the user.
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          title: event.title,
          body: reminderBody(event, at),
          payload: tag,
          matchDateTimeComponents: _repeatMatch(event.repeat),
        );
      }
    } catch (_) {
      // Reminders are a bonus: never let them break the calendar.
    }
  }

  @override
  Future<void> clearAll() async {
    if (!await _init()) return;
    try {
      await _plugin.cancelAll();
    } catch (_) {}
  }

  static int _notificationId(QboxRole role, int eventId) =>
      (eventId * 4 + role.index) & 0x7fffffff;

  static DateTimeComponents? _repeatMatch(Repeat repeat) => switch (repeat) {
    Repeat.none => null,
    Repeat.daily => DateTimeComponents.time,
    Repeat.weekly => DateTimeComponents.dayOfWeekAndTime,
    Repeat.monthly => DateTimeComponents.dayOfMonthAndTime,
    Repeat.yearly => DateTimeComponents.dateAndTime,
  };
}
