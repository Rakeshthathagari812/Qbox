import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qbox_app/main.dart';
import 'package:qbox_app/splash_screen.dart';

import 'fake_auth_api.dart';

void main() {
  testWidgets('opening animation: symbol forms, QBOX, powered by Quadrant, then the next screen', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SplashScreen(next: Text('login page'))));
    expect(find.byKey(const Key('splash')), findsOneWidget);
    expect(find.byType(QboxSymbol), findsOneWidget);
    expect(find.text('QBOX'), findsOneWidget);
    expect(find.textContaining('Quadrant IT Services', findRichText: true), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 3200));
    expect(find.byKey(const Key('splash')), findsOneWidget); // words stay a moment
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('splash')), findsNothing);
    expect(find.text('login page'), findsOneWidget);
  });

  testWidgets('the real app: animation, then the welcome screen with no extra QBOX screen', (tester) async {
    await tester.pumpWidget(QboxApp(services: fakeServices(), showSplash: true));
    expect(find.byKey(const Key('splash')), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('splash')), findsNothing);
    expect(find.byKey(const Key('startup-offline')), findsNothing);
  });
}
