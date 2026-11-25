import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qbox_app/calculator/calculator_store.dart';
import 'package:qbox_app/main.dart';
import 'package:qbox_app/services/session_store.dart';
import 'package:qbox_app/widgets/tool_tap.dart';

import 'fake_auth_api.dart';

void usePhone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  backendTests();

  testWidgets('sign up opens the role screen', (tester) async {
    usePhone(tester);
    await tester.pumpWidget(QboxApp(services: fakeServices()));
    await tester.pumpAndSettle();

    expect(find.text('Log in'), findsOneWidget);

    await tester.tap(find.textContaining('Sign up'));
    await tester.pumpAndSettle();
    expect(find.text('Verify Your Mobile Number'), findsOneWidget);

    await _passOtp(tester);

    expect(find.text('How will you use QBOX?'), findsOneWidget);
    expect(find.text('Business / Shop'), findsOneWidget);
    expect(find.text('Customer'), findsOneWidget);
    expect(find.text('Supplier'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
  });

  testWidgets('roles can be combined and are kept after going back', (
    tester,
  ) async {
    usePhone(tester);
    await tester.pumpWidget(QboxApp(services: fakeServices()));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Sign up'));
    await tester.pumpAndSettle();
    await _passOtp(tester);

    expect(
      tester.widget<InkWell>(find.byKey(const Key('continue-button'))).onTap,
      isNull,
    );

    await tester.tap(find.text('Business / Shop'));
    await tester.pump();
    await tester.tap(find.text('Supplier'));
    await tester.pump();

    expect(find.byIcon(Icons.check), findsNWidgets(2));
    expect(
      tester.widget<InkWell>(find.byKey(const Key('continue-button'))).onTap,
      isNotNull,
    );

    await tester.tap(find.text('Business / Shop'));
    await tester.pump();
    expect(find.byIcon(Icons.check), findsOneWidget);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Verify Your Mobile Number'), findsOneWidget);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Log in'), findsOneWidget);

    await tester.tap(find.textContaining('Sign up'));
    await tester.pumpAndSettle();
    await _passOtp(tester);
    expect(find.byIcon(Icons.check), findsOneWidget);
    expect(find.text('Supplier'), findsOneWidget);
  });

  testWidgets('only the customer form is shown when customer is selected', (
    tester,
  ) async {
    await _openRegistration(tester, ['Customer']);

    expect(find.text('Tell us about yourself'), findsOneWidget);
    expect(find.text('Tell us about your shop'), findsNothing);
    expect(find.text('Tell us about your business'), findsNothing);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('customer-phone')))
          .controller
          ?.text,
      '98765 43210',
    );
  });

  testWidgets('customer then supplier, and typed values stay on back', (
    tester,
  ) async {
    await _openRegistration(tester, ['Supplier', 'Customer']);

    expect(find.text('Tell us about yourself'), findsOneWidget);
    expect(find.text('Tell us about your shop'), findsNothing);

    await tester.enterText(find.byKey(const Key('customer-name')), 'Raju');
    await tester.enterText(
      find.byKey(const Key('customer-phone')),
      '98765 43210',
    );
    await tester.ensureVisible(find.byKey(const Key('registration-continue')));
    await tester.tap(find.byKey(const Key('registration-continue')));
    await tester.pumpAndSettle();

    expect(find.text('Tell us about your business'), findsOneWidget);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    expect(find.text('Tell us about yourself'), findsOneWidget);
    expect(find.text('Raju'), findsOneWidget);
  });

  testWidgets('all three roles stay in business, customer, supplier order', (
    tester,
  ) async {
    await _openRegistration(tester, [
      'Supplier',
      'Customer',
      'Business / Shop',
    ]);

    expect(find.text('Tell us about your shop'), findsOneWidget);
    await _fillShop(tester);
    await tester.ensureVisible(find.byKey(const Key('registration-continue')));
    await tester.tap(find.byKey(const Key('registration-continue')));
    await tester.pumpAndSettle();
    expect(find.text('Tell us about yourself'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('customer-name')), 'Raju');
    await tester.enterText(
      find.byKey(const Key('customer-phone')),
      '98765 43210',
    );
    await tester.ensureVisible(find.byKey(const Key('registration-continue')));
    await tester.tap(find.byKey(const Key('registration-continue')));
    await tester.pumpAndSettle();
    expect(find.text('Tell us about your business'), findsOneWidget);
  });

  testWidgets('missing shop fields show validation', (tester) async {
    await _openRegistration(tester, ['Business / Shop']);
    await tester.ensureVisible(find.byKey(const Key('registration-continue')));
    await tester.tap(find.byKey(const Key('registration-continue')));
    await tester.pump();

    expect(find.text('Enter shop name'), findsOneWidget);
    expect(find.text('Select business type'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('shop-phone')))
          .controller
          ?.text,
      '98765 43210',
    );
    expect(
      find.text('Tell us about your shop', skipOffstage: false),
      findsOneWidget,
    );
  });

  testWidgets('finished registration asks for a PIN then shows success', (
    tester,
  ) async {
    await _openRegistration(tester, ['Customer']);
    await tester.enterText(find.byKey(const Key('customer-name')), 'Raju');
    await tester.enterText(
      find.byKey(const Key('customer-phone')),
      '98765 43210',
    );
    await tester.ensureVisible(find.byKey(const Key('registration-continue')));
    await tester.tap(find.byKey(const Key('registration-continue')));
    await tester.pumpAndSettle();

    expect(find.text('Set Your Login PIN'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('pin-input')), '1234');
    await tester.enterText(find.byKey(const Key('pin-confirm')), '9999');
    await tester.tap(find.byKey(const Key('save-pin')));
    await tester.pump();
    expect(find.text('PINs do not match'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('pin-confirm')), '1234');
    await tester.tap(find.byKey(const Key('save-pin')));
    await tester.pumpAndSettle();

    expect(find.text('Successfully Signed Up!'), findsOneWidget);
    await tester.tap(find.byKey(const Key('signup-login')));
    await tester.pumpAndSettle();
    expect(find.text('Get started with QBOX'), findsOneWidget);
    expect(find.text('Log in'), findsOneWidget);
  });

  testWidgets('log in opens the welcome back screen', (tester) async {
    usePhone(tester);
    await tester.pumpWidget(QboxApp(services: fakeServices()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Log in'));
    await tester.pumpAndSettle();
    expect(find.text('Welcome Back!'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byKey(const Key('login-phone'))).controller?.text,
      '',
    );
    expect(
      tester.widget<TextField>(find.byKey(const Key('login-pin'))).controller?.text,
      '',
    );
    expect(find.text('Forgot PIN?'), findsOneWidget);
    expect(find.text('Log In'), findsOneWidget);
    expect(find.text('New to QBOX?'), findsOneWidget);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Get started with QBOX'), findsOneWidget);

    await tester.tap(find.text('Log in'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create Account'));
    await tester.pumpAndSettle();
    expect(find.text('Verify Your Mobile Number'), findsOneWidget);
  });

  testWidgets('account with all roles sees all three roles', (tester) async {
    usePhone(tester);
    await tester.pumpWidget(QboxApp(services: fakeServices()));
    await tester.pumpAndSettle();
    await _logInDemo(tester);

    expect(find.text('Choose Your Role'), findsOneWidget);
    expect(find.text('Business / Shop'), findsOneWidget);
    expect(find.text('Customer'), findsOneWidget);
    expect(find.text('Supplier'), findsOneWidget);

    await tester.tap(find.text('Business / Shop'));
    await tester.pumpAndSettle();
    expect(find.text('Sri Rama Kirana'), findsOneWidget);
  });

  testWidgets('customer role opens the customer home', (tester) async {
    usePhone(tester);
    await tester.pumpWidget(QboxApp(services: fakeServices()));
    await tester.pumpAndSettle();
    await _logInDemo(tester);

    await tester.tap(find.text('Customer'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Hello, Ramu'), findsOneWidget);
    expect(find.text('QBOX ID: QBC10001'), findsOneWidget);
    expect(find.text('My Udhaar'), findsOneWidget);
    expect(find.text('My QR'), findsNothing); // hidden until it is built
    expect(find.text('Ask QBOX'), findsOneWidget);

    await tester.tap(find.byKey(const Key('switch-role')));
    await tester.pumpAndSettle();
    expect(find.text('Choose Your Role'), findsOneWidget);
  });

  testWidgets('supplier role opens the supplier home', (tester) async {
    usePhone(tester);
    await tester.pumpWidget(QboxApp(services: fakeServices()));
    await tester.pumpAndSettle();
    await _logInDemo(tester);

    await tester.tap(find.text('Supplier'));
    await tester.pumpAndSettle();
    expect(find.text('Sri Venkateswara Suppliers'), findsOneWidget);
    expect(find.text('Supplier ID: QBS10001'), findsOneWidget);
    expect(find.text('Shop Ledger'), findsOneWidget);
    expect(find.text('Ask QBOX AI'), findsOneWidget);

    await tester.tap(find.byKey(const Key('switch-role')));
    await tester.pumpAndSettle();
    expect(find.text('Choose Your Role'), findsOneWidget);
  });

  testWidgets('forgot PIN resets the PIN and returns to login', (
    tester,
  ) async {
    usePhone(tester);
    await tester.pumpWidget(QboxApp(services: fakeServices()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Log in'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('forgot-pin')));
    await tester.pumpAndSettle();
    expect(find.text('Enter Mobile Number'), findsOneWidget);
    expect(find.text('Enter 6-Digit OTP'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('forgot-phone')),
      FakeAuthApi.demoMobile,
    );
    await tester.tap(find.byKey(const Key('forgot-send')));
    await tester.pump();
    expect(find.textContaining('OTP Sent to +91'), findsOneWidget);
    expect(find.text('Test mode OTP: 123456'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('forgot-otp')), '123456');
    await tester.tap(find.byKey(const Key('forgot-verify')));
    await tester.pumpAndSettle();
    expect(find.text('Set New PIN'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('new-pin')), '4321');
    await tester.enterText(find.byKey(const Key('new-pin-confirm')), '1111');
    await tester.tap(find.byKey(const Key('save-new-pin')));
    await tester.pump();
    expect(find.text('PINs do not match'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('new-pin-confirm')), '4321');
    await tester.tap(find.byKey(const Key('save-new-pin')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Successfully'), findsOneWidget);

    await tester.tap(find.byKey(const Key('back-to-login')));
    await tester.pumpAndSettle();
    expect(find.text('Welcome Back!'), findsOneWidget);
  });

  testWidgets('login shows only the roles chosen at signup', (tester) async {
    await _openRegistration(tester, ['Customer']);
    await tester.enterText(find.byKey(const Key('customer-name')), 'Raju');
    await tester.enterText(
      find.byKey(const Key('customer-phone')),
      '98765 43210',
    );
    await tester.ensureVisible(find.byKey(const Key('registration-continue')));
    await tester.tap(find.byKey(const Key('registration-continue')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('pin-input')), '1234');
    await tester.enterText(find.byKey(const Key('pin-confirm')), '1234');
    await tester.tap(find.byKey(const Key('save-pin')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('signup-login')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Log in'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('login-phone')), '9876543210');
    await tester.enterText(find.byKey(const Key('login-pin')), '0000');
    await tester.tap(find.byKey(const Key('login-submit')));
    await tester.pump();
    expect(find.text('Choose Your Role'), findsNothing);

    await tester.enterText(find.byKey(const Key('login-pin')), '1234');
    await tester.tap(find.byKey(const Key('login-submit')));
    await tester.pumpAndSettle();

    expect(find.text('Choose Your Role'), findsOneWidget);
    expect(find.text('Customer'), findsOneWidget);
    expect(find.text('Business / Shop'), findsNothing);
    expect(find.text('Supplier'), findsNothing);
  });

  testWidgets('business role opens the shop home', (tester) async {
    await _openRegistration(tester, ['Business / Shop']);
    await _fillShop(tester);
    await tester.ensureVisible(find.byKey(const Key('registration-continue')));
    await tester.tap(find.byKey(const Key('registration-continue')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('pin-input')), '1234');
    await tester.enterText(find.byKey(const Key('pin-confirm')), '1234');
    await tester.tap(find.byKey(const Key('save-pin')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('signup-login')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Log in'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('login-phone')), '9876543210');
    await tester.enterText(find.byKey(const Key('login-pin')), '1234');
    await tester.tap(find.byKey(const Key('login-submit')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Business / Shop'));
    await tester.pumpAndSettle();
    expect(find.text('Sri Balaji Kirana'), findsOneWidget);
    expect(find.text('Payments'), findsOneWidget);
    expect(find.byKey(const Key('tool-QBOX AI')), findsNothing);
    expect(find.text('Ask QBOX AI'), findsOneWidget);
    expect(find.textContaining('Good '), findsOneWidget);

    await tester.tap(find.byKey(const Key('switch-role')));
    await tester.pumpAndSettle();
    expect(find.text('Choose Your Role'), findsOneWidget);
  });

  testWidgets('back from the first form returns to the role choices', (
    tester,
  ) async {
    await _openRegistration(tester, ['Supplier']);
    expect(find.text('Tell us about your business'), findsOneWidget);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    expect(find.text('How will you use QBOX?'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsOneWidget);
  });
}

void backendTests() {
  testWidgets('wrong OTP shows the backend message', (tester) async {
    usePhone(tester);
    await tester.pumpWidget(QboxApp(services: fakeServices()));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Sign up'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('otp-phone')), '9876543210');
    await tester.tap(find.byKey(const Key('send-otp')));
    await tester.pump();
    expect(find.text('Test mode OTP: 123456'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('otp-input')), '000000');
    await tester.tap(find.byKey(const Key('verify-otp')));
    await tester.pumpAndSettle();
    expect(find.text('Wrong OTP. Please check and try again'), findsOneWidget);
    expect(find.text('How will you use QBOX?'), findsNothing);
  });

  testWidgets('a registered mobile cannot sign up again', (tester) async {
    usePhone(tester);
    await tester.pumpWidget(QboxApp(services: fakeServices()));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Sign up'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('otp-phone')),
      FakeAuthApi.demoMobile,
    );
    await tester.tap(find.byKey(const Key('send-otp')));
    await tester.pumpAndSettle();
    expect(
      find.text('This mobile number is already registered. Please log in'),
      findsOneWidget,
    );
  });

  testWidgets('wrong PIN shows the backend message', (tester) async {
    usePhone(tester);
    await tester.pumpWidget(QboxApp(services: fakeServices()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Log in'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('login-phone')),
      FakeAuthApi.demoMobile,
    );
    await tester.enterText(find.byKey(const Key('login-pin')), '9999');
    await tester.tap(find.byKey(const Key('login-submit')));
    await tester.pumpAndSettle();
    expect(find.text('Mobile number or PIN does not match'), findsOneWidget);
    expect(find.text('Choose Your Role'), findsNothing);
  });

  testWidgets('sign up sends the typed details to the backend', (tester) async {
    final api = FakeAuthApi();
    usePhone(tester);
    await tester.pumpWidget(QboxApp(services: fakeServices(api: api)));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Sign up'));
    await tester.pumpAndSettle();
    await _passOtp(tester);
    await tester.tap(find.text('Business / Shop'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('continue-button')));
    await tester.pumpAndSettle();
    await _fillShop(tester);
    await tester.ensureVisible(find.byKey(const Key('registration-continue')));
    await tester.tap(find.byKey(const Key('registration-continue')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('pin-input')), '2468');
    await tester.enterText(find.byKey(const Key('pin-confirm')), '2468');
    await tester.tap(find.byKey(const Key('save-pin')));
    await tester.pumpAndSettle();

    expect(find.text('Successfully Signed Up!'), findsOneWidget);
    final body = api.lastRegistration!;
    expect(body['pin'], '2468');
    expect(body['roles'], ['BUSINESS']);
    expect(body['verificationToken'], 'verify:SIGNUP:9876543210');
    final shop = body['shop'] as Map<String, dynamic>;
    expect(shop['shopName'], 'Sri Balaji Kirana');
    expect(shop['businessType'], 'Retail');
    expect(shop['shopCategory'], 'Grocery & Daily Needs');
    expect(shop['contactNumber'], '9876543210');
    expect(body.containsKey('customer'), isFalse);
  });

  testWidgets('saved login opens Choose Role, and log out forgets it', (
    tester,
  ) async {
    final session = MemorySessionStore();
    await session.saveToken('access:${FakeAuthApi.demoMobile}');
    usePhone(tester);
    await tester.pumpWidget(QboxApp(services: fakeServices(session: session)));
    await tester.pumpAndSettle();

    expect(find.text('Choose Your Role'), findsOneWidget);
    expect(find.text('Supplier'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('log-out')));
    await tester.tap(find.byKey(const Key('log-out')));
    await tester.pumpAndSettle();
    expect(find.text('Get started with QBOX'), findsOneWidget);
    expect(await session.readToken(), isNull);
  });

  testWidgets('an expired saved login shows the Welcome screen', (tester) async {
    final session = MemorySessionStore();
    await session.saveToken('access:0000000000');
    usePhone(tester);
    await tester.pumpWidget(QboxApp(services: fakeServices(session: session)));
    await tester.pumpAndSettle();

    expect(find.text('Get started with QBOX'), findsOneWidget);
    expect(await session.readToken(), isNull);
  });

  testWidgets('server unreachable at startup keeps the login and retries', (
    tester,
  ) async {
    final api = FakeAuthApi()..offline = true;
    final session = MemorySessionStore();
    await session.saveToken('access:${FakeAuthApi.demoMobile}');
    usePhone(tester);
    await tester.pumpWidget(
      QboxApp(services: fakeServices(api: api, session: session)),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('startup-offline')), findsOneWidget);
    expect(await session.readToken(), isNotNull);

    api.offline = false;
    await tester.tap(find.byKey(const Key('startup-retry')));
    await tester.pumpAndSettle();
    expect(find.text('Choose Your Role'), findsOneWidget);
  });

  testWidgets('offline with a saved login opens the app and the calculator', (
    tester,
  ) async {
    final api = FakeAuthApi();
    final session = MemorySessionStore();
    usePhone(tester);

    // Log in once while online: the account details are saved on the phone.
    await tester.pumpWidget(QboxApp(services: fakeServices(api: api, session: session)));
    await tester.pumpAndSettle();
    await _logInDemo(tester);
    expect((await session.readUser())?.mobile, FakeAuthApi.demoMobile);

    // Reopen the app with no internet.
    api.offline = true;
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(QboxApp(services: fakeServices(api: api, session: session)));
    await tester.pumpAndSettle();
    expect(find.text('Choose Your Role'), findsOneWidget);
    expect(find.byKey(const Key('offline-note')), findsOneWidget);

    await tester.tap(find.text('Business / Shop'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('tool-Calculator')));
    await tester.tap(find.byKey(const Key('tool-Calculator')));
    await tester.pumpAndSettle();
    for (final key in ['7', '×', '6', '=']) {
      await tester.tap(find.byKey(Key('calc-$key')));
      await tester.pump();
    }
    expect(find.text('42'), findsOneWidget);
  });

  testWidgets('log out forgets the saved account details too', (tester) async {
    final session = MemorySessionStore();
    usePhone(tester);
    await tester.pumpWidget(QboxApp(services: fakeServices(session: session)));
    await tester.pumpAndSettle();
    await _logInDemo(tester);
    expect(await session.readUser(), isNotNull);

    await tester.ensureVisible(find.byKey(const Key('log-out')));
    await tester.tap(find.byKey(const Key('log-out')));
    await tester.pumpAndSettle();
    expect(await session.readUser(), isNull);
    expect(await session.readToken(), isNull);
  });

  testWidgets('Calculator tile opens the calculator from shop and customer homes', (
    tester,
  ) async {
    usePhone(tester);
    await tester.pumpWidget(QboxApp(services: fakeServices()));
    await tester.pumpAndSettle();
    await _logInDemo(tester);

    for (final role in ['Business / Shop', 'Customer']) {
      await tester.tap(find.text(role));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('tool-Calculator')));
      await tester.tap(find.byKey(const Key('tool-Calculator')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('calc-mic')), findsOneWidget, reason: role);

      await tester.tap(find.byKey(const Key('calc-back')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('switch-role')));
      await tester.pumpAndSettle();
    }
  });

  testWidgets('a tile not built yet says coming soon', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: ToolTap(label: 'New Orders', child: SizedBox(width: 100, height: 100))),
      ),
    );
    await tester.tap(find.byKey(const Key('tool-New Orders')));
    await tester.pump(const Duration(milliseconds: 200)); // tile grow effect
    await tester.pump();
    expect(find.text('New Orders is coming soon'), findsOneWidget);
  });

  testWidgets('Udhaar tiles open the shop book and My Udhaar', (tester) async {
    usePhone(tester);
    await tester.pumpWidget(QboxApp(services: fakeServices()));
    await tester.pumpAndSettle();
    await _logInDemo(tester);

    await tester.tap(find.text('Business / Shop'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tool-Udhaar')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('udhaar-empty')), findsOneWidget);
    await tester.tap(find.byKey(const Key('udhaar-back')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('switch-role')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Customer'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('tool-My Udhaar')));
    await tester.tap(find.byKey(const Key('tool-My Udhaar')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('myudhaar-empty')), findsOneWidget);
  });

  testWidgets('log out also clears the calculator history', (tester) async {
    final calculator = MemoryCalculatorStore()
      ..data = {'gt': 500, 'memory': 0, 'history': []};
    final session = MemorySessionStore();
    await session.saveToken('access:${FakeAuthApi.demoMobile}');
    usePhone(tester);
    await tester.pumpWidget(
      QboxApp(services: fakeServices(session: session, calculator: calculator)),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('log-out')));
    await tester.tap(find.byKey(const Key('log-out')));
    await tester.pumpAndSettle();
    expect(calculator.data, isNull);
  });

  testWidgets('after login, Back does not return to the login page', (
    tester,
  ) async {
    usePhone(tester);
    await tester.pumpWidget(QboxApp(services: fakeServices()));
    await tester.pumpAndSettle();
    await _logInDemo(tester);

    expect(find.text('Choose Your Role'), findsOneWidget);
    final navigator = tester.state<NavigatorState>(find.byType(Navigator).first);
    expect(navigator.canPop(), isFalse);
  });
}

Future<void> _logInDemo(WidgetTester tester) async {
  await tester.tap(find.text('Log in'));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const Key('login-phone')),
    FakeAuthApi.demoMobile,
  );
  await tester.enterText(find.byKey(const Key('login-pin')), FakeAuthApi.demoPin);
  await tester.tap(find.byKey(const Key('login-submit')));
  await tester.pumpAndSettle();
}

Future<void> _passOtp(WidgetTester tester) async {
  await tester.enterText(find.byKey(const Key('otp-phone')), '9876543210');
  await tester.tap(find.byKey(const Key('send-otp')));
  await tester.pump();
  await tester.enterText(find.byKey(const Key('otp-input')), '123456');
  await tester.tap(find.byKey(const Key('verify-otp')));
  await tester.pumpAndSettle();
}

Future<void> _openRegistration(
  WidgetTester tester,
  List<String> roles,
) async {
  usePhone(tester);
  await tester.pumpWidget(QboxApp(services: fakeServices()));
  await tester.pumpAndSettle();
  await tester.tap(find.textContaining('Sign up'));
  await tester.pumpAndSettle();
  await _passOtp(tester);
  for (final role in roles) {
    await tester.tap(find.text(role));
    await tester.pump();
  }
  await tester.tap(find.byKey(const Key('continue-button')));
  await tester.pumpAndSettle();
}

Future<void> _fillShop(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const Key('shop-name')),
    'Sri Balaji Kirana',
  );
  await tester.tap(find.byKey(const Key('shop-type')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Retail').last);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('shop-category')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Grocery & Daily Needs').last);
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const Key('shop-address')),
    'Bandlaguda',
  );
  await tester.enterText(find.byKey(const Key('shop-phone')), '9876543210');
}
