import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qbox_app/main.dart';
import 'package:qbox_app/profile/profile_api.dart';
import 'package:qbox_app/services/api_client.dart';
import 'package:qbox_app/services/api_config.dart';
import 'package:qbox_app/update_screen.dart';

import 'fake_auth_api.dart';

class _Broken extends FakeProfileApi {
  @override
  Future<AppVersions> versions() async => throw const ApiException('NETWORK', 'offline');
}

void main() {
  test('an app for people must use https (only the phone itself may be plain)', () {
    String? problem(String url) => apiUrlProblem(url, release: true);
    expect(problem('https://api.example.in'), isNull);
    expect(problem('http://127.0.0.1:8080'), isNull);
    expect(problem('http://10.0.2.2:8080'), isNotNull); // a build without an address
    expect(problem('http://api.example.in'), isNotNull);
    expect(problem('http://127.0.0.1.example.in'), isNotNull);
    expect(problem('ftp://127.0.0.1'), isNotNull);
    expect(problem(''), isNotNull);
    expect(apiUrlProblem('http://10.0.2.2:8080', release: false), isNull);
  });

  testWidgets('too old: only Update can be tapped', (tester) async {
    final profile = FakeProfileApi()..allowed = const AppVersions(minBuild: 5, updateUrl: 'https://play.example/qbox');
    final device = FakeDeviceActions()..build = 4;
    await tester.pumpWidget(QboxApp(services: fakeServices(profile: profile, device: device)));
    await tester.pumpAndSettle();
    expect(find.byType(UpdateScreen), findsOneWidget);
    expect(find.text('Log in'), findsNothing);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(UpdateScreen), findsOneWidget);
    await tester.tap(find.byKey(const Key('update-now')));
    expect(device.opened.single.toString(), 'https://play.example/qbox');
  });

  testWidgets('new enough, not known, or no internet: opens as usual', (tester) async {
    for (final (profile, build) in [
      (FakeProfileApi()..allowed = const AppVersions(minBuild: 5), 5),
      (FakeProfileApi()..allowed = const AppVersions(minBuild: 5), null),
      (_Broken(), 1),
    ]) {
      final device = FakeDeviceActions()..build = build;
      await tester.pumpWidget(QboxApp(key: UniqueKey(), services: fakeServices(profile: profile, device: device)));
      await tester.pumpAndSettle();
      expect(find.byType(UpdateScreen), findsNothing);
      expect(find.text('Log in'), findsOneWidget);
    }
  });

  testWidgets('an unsafe or missing link is not opened', (tester) async {
    for (final url in ['', 'http://example.in', 'javascript:x']) {
      await tester.pumpWidget(MaterialApp(key: UniqueKey(), home: UpdateScreen(url: url)));
      expect(find.byKey(const Key('update-now')), findsNothing);
      expect(find.textContaining('Play Store'), findsOneWidget);
    }
  });
}
