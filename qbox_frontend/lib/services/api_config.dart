import 'package:flutter/foundation.dart';

/// Where the QBOX backend (FastAPI) is running.
///
/// - Android emulator: 10.0.2.2 is the emulator's name for "this PC".
/// - Anything else (web, desktop): localhost.
/// - A real phone on the PC's cable or wireless debugging (adb reverse):
///   --dart-define=QBOX_API_URL=http://127.0.0.1:8080
/// - The live server: --dart-define=QBOX_API_URL=https://...
String qboxApiBaseUrl() {
  const fromBuild = String.fromEnvironment('QBOX_API_URL');
  if (fromBuild.isNotEmpty) return fromBuild;
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    return 'http://10.0.2.2:8080';
  }
  return 'http://localhost:8080';
}

/// Why an app made for people to use must not talk to [url]; null = fine.
/// Logins and money go there, so it must be https. Only the phone itself
/// (adb reverse, for testing) may be plain http.
String? apiUrlProblem(String url, {required bool release}) {
  if (!release) return null;
  final uri = Uri.tryParse(url);
  if (uri == null || uri.host.isEmpty) return 'no server address';
  if (uri.scheme == 'https') return null;
  if (uri.scheme == 'http' && (uri.host == '127.0.0.1' || uri.host == 'localhost')) return null;
  return 'the server address is not secure (https)';
}
