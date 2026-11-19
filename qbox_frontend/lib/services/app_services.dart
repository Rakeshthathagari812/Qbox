import 'package:flutter/widgets.dart';

import 'api_config.dart';
import 'auth_api.dart';
import 'session_store.dart';

/// The backend connection and saved login, shared by every screen.
class AppServices {
  AppServices({required this.auth, required this.session});

  /// The real backend and on-phone storage.
  factory AppServices.live() => AppServices(
        auth: HttpAuthApi(baseUrl: qboxApiBaseUrl()),
        session: SecureSessionStore(),
      );

  final AuthApi auth;
  final SessionStore session;
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
