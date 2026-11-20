import 'package:flutter/widgets.dart';

import '../calculator/calculator_store.dart';
import '../calculator/voice_services.dart';
import '../calendar/calendar_api.dart';
import '../calendar/calendar_store.dart';
import '../calendar/reminders.dart';
import '../translator/speech_engines.dart';
import '../translator/translation_service.dart';
import '../udhaar/udhaar_api.dart';
import '../udhaar/udhaar_repository.dart';
import '../udhaar/udhaar_store.dart';
import 'api_client.dart';
import 'api_config.dart';
import 'auth_api.dart';
import 'device_actions.dart';
import 'language_api.dart';
import 'session_store.dart';
import 'settings_store.dart';

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
    required this.udhaar,
    required this.device,
    required this.translator,
    required this.settings,
  });

  /// The real backend, on-phone storage, microphone, speaker and notifications.
  factory AppServices.live() {
    final session = SecureSessionStore();
    final api = ApiClient(baseUrl: qboxApiBaseUrl(), token: session.readToken);
    final language = HttpLanguageApi(api);
    final settings = PrefsSettingsStore();
    return AppServices(
      auth: HttpAuthApi(api),
      session: session,
      calculator: PrefsCalculatorStore(),
      // Indian languages: the QBOX server's speech model when reachable;
      // English, or offline: the phone's own. Chosen by itself.
      voice: SmartVoiceInput(
        phone: DeviceVoiceInput(),
        server: IndicVoiceInput(language),
        language: language,
      ),
      speaker: DeviceSpeaker(),
      calendar: HttpCalendarApi(api),
      calendarStore: PrefsCalendarStore(),
      reminders: LocalReminderScheduler(),
      udhaar: UdhaarRepository(HttpUdhaarApi(api), PrefsUdhaarStore()),
      device: PhoneDeviceActions(),
      // The QBOX server (IndicTrans2); the on-phone translator when offline.
      translator: SmartTextTranslator(online: language, offline: OnDeviceTextTranslator()),
      settings: settings,
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
  final UdhaarRepository udhaar;
  final DeviceActions device;

  /// On-phone translation (free, offline once language packs are downloaded).
  final TextTranslator translator;

  /// Chosen languages and similar small settings.
  final SettingsStore settings;

  /// Forgets everything this user kept on the phone (log out, expired login).
  Future<void> forgetUserData() async {
    await session.clear();
    await calculator.clear();
    await calendarStore.clear();
    await reminders.clearAll();
    await udhaar.clear();
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
