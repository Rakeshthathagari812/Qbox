import 'package:flutter/widgets.dart';

import '../calculator/calculator_store.dart';
import '../calculator/voice_services.dart';
import '../calendar/calendar_api.dart';
import '../calendar/calendar_store.dart';
import '../calendar/reminders.dart';
import 'api_client.dart';
import 'api_config.dart';
import 'auth_api.dart';
import 'session_store.dart';

/// The backend connection, saved login and phone features, shared by every screen.
/// Tests pass pretend versions of each.
class AppServices {
  AppServices({
    required this.auth,
    required this.session,
    required this.calculator,
    required this.voice,
    required this.speaker,
    required this.calendar,
    required this.calendarStore,
    required this.reminders,
  });

  /// The real backend, on-phone storage, microphone, speaker and notifications.
  factory AppServices.live() {
    final session = SecureSessionStore();
    final api = ApiClient(baseUrl: qboxApiBaseUrl(), token: session.readToken);
    return AppServices(
      auth: HttpAuthApi(api),
      session: session,
      calculator: PrefsCalculatorStore(),
      voice: DeviceVoiceInput(),
      speaker: DeviceSpeaker(),
      calendar: HttpCalendarApi(api),
      calendarStore: PrefsCalendarStore(),
      reminders: LocalReminderScheduler(),
    );
  }

  final AuthApi auth;
  final SessionStore session;
  final CalculatorStore calculator;
  final VoiceInput voice;
  final Speaker speaker;
  final CalendarApi calendar;
  final CalendarStore calendarStore;
  final ReminderScheduler reminders;

  /// Forgets everything this user kept on the phone (log out, expired login).
  Future<void> forgetUserData() async {
    await session.clear();
    await calculator.clear();
    await calendarStore.clear();
    await reminders.clearAll();
  }
}

class ServicesScope extends InheritedWidget {
  const ServicesScope({
    required this.services,
    required super.child,
    super.key,
  });

  final AppServices services;

  static AppServices of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<ServicesScope>();
    assert(scope != null, 'ServicesScope is missing above this screen');
    return scope!.services;
  }

  @override
  bool updateShouldNotify(ServicesScope oldWidget) =>
      oldWidget.services != services;
}
