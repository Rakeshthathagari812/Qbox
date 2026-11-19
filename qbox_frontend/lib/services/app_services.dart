import 'package:flutter/widgets.dart';

import '../calculator/calculator_store.dart';
import '../calculator/voice_services.dart';
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
  });

  /// The real backend, on-phone storage, microphone and speaker.
  factory AppServices.live() => AppServices(
        auth: HttpAuthApi(baseUrl: qboxApiBaseUrl()),
        session: SecureSessionStore(),
        calculator: PrefsCalculatorStore(),
        voice: DeviceVoiceInput(),
        speaker: DeviceSpeaker(),
      );

  final AuthApi auth;
  final SessionStore session;
  final CalculatorStore calculator;
  final VoiceInput voice;
  final Speaker speaker;
}

class ServicesScope extends InheritedWidget {
  const ServicesScope({required this.services, required super.child, super.key});

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
