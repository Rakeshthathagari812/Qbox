import 'package:flutter/foundation.dart';

/// Where the QBOX backend (FastAPI) is running.
///
/// - Android emulator: 10.0.2.2 is the emulator's name for "this PC".
/// - Anything else (web, desktop): localhost.
/// - A real phone or a live server: run with
///   flutter run --dart-define=QBOX_API_URL=http://<address>:8080
String qboxApiBaseUrl() {
  const fromBuild = String.fromEnvironment('QBOX_API_URL');
  if (fromBuild.isNotEmpty) return fromBuild;
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    return 'http://10.0.2.2:8080';
  }
  return 'http://localhost:8080';
}
