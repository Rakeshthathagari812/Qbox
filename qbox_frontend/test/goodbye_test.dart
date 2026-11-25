import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qbox_app/onboarding_draft.dart';
import 'package:qbox_app/profile/delete_account_screen.dart';
import 'package:qbox_app/profile/legal_screen.dart';
import 'package:qbox_app/profile/profile_api.dart';
import 'package:qbox_app/profile/profile_screen.dart';
import 'package:qbox_app/services/app_services.dart';
import 'package:qbox_app/services/session_store.dart';
import 'package:qbox_app/signup_screen.dart';
import 'package:qbox_app/udhaar/my_udhaar_screen.dart';
import 'package:qbox_app/udhaar/udhaar_models.dart';

import 'fake_auth_api.dart';
import 'udhaar_screen_test.dart' show tapKey;

Finder at(String key) => find.byKey(Key(key));

String textOf(WidgetTester tester, String key) => tester.widget<Text>(at(key)).data!;

void main() {
  late FakeProfileApi api;
  late MemorySessionStore session;
  late OnboardingDraft draft;
  late FakeDeviceActions device;

  setUp(() {
    api = FakeProfileApi();
    session = MemorySessionStore();
    draft = OnboardingDraft()..applyUser(api.user);
    device = FakeDeviceActions();
  });

  Future<void> show(WidgetTester tester, Widget screen, {Size size = const Size(1080, 2340), FakeUdhaarApi? udhaar}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ServicesScope(
        key: UniqueKey(),
        services: fakeServices(profile: api, session: session, device: device, udhaar: udhaar),
        child: OnboardingScope(draft: draft, child: MaterialApp(home: screen)),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('delete my account', () {
    testWidgets('a tick and the right PIN, then everything is forgotten', (tester) async {
      await session.saveToken('token');
      await show(tester, const DeleteAccountScreen());
      expect(find.textContaining('All your roles'), findsOneWidget);
      expect(at('delete-pin'), findsNothing);
      expect(tester.widget<FilledButton>(at('delete-account')).onPressed, isNull);
      await tapKey(tester, 'delete-sure');
      await tapKey(tester, 'delete-account');
      expect(find.text('Enter your 4-digit PIN'), findsOneWidget);
      await tester.enterText(at('delete-pin'), '0000');
      await tapKey(tester, 'delete-account');
      expect(find.text('The PIN is not right'), findsOneWidget);
      expect(await session.readToken(), 'token');
      await tester.enterText(at('delete-pin'), '4826');
      await tapKey(tester, 'delete-account');
      expect(await session.readToken(), isNull);
      expect(draft.user, isNull);
      expect(find.text('Get started with QBOX'), findsOneWidget);
    });

    testWidgets('says what is owed; an open payment must be finished first', (tester) async {
      api.toDelete = const DeleteCheck(youOwePaise: 50000, owedToYouPaise: 120000);
      await show(tester, const DeleteAccountScreen());
      expect(find.text('You still owe ₹500.'), findsOneWidget);
      expect(find.textContaining('₹1,200 is still owed to you'), findsOneWidget);
      api.toDelete = const DeleteCheck(paymentsOpen: true);
      await show(tester, const DeleteAccountScreen());
      expect(at('delete-open'), findsOneWidget);
      expect(at('delete-account'), findsNothing);
    });

    testWidgets('needs internet', (tester) async {
      api.offline = true;
      await show(tester, const DeleteAccountScreen());
      expect(at('delete-load-error'), findsOneWidget);
      expect(at('delete-account'), findsNothing);
      api.offline = false;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      await tapKey(tester, 'delete-sure');
      await tester.enterText(at('delete-pin'), '4826');
      api.offline = true;
      await tapKey(tester, 'delete-account');
      expect(find.text('This needs internet. Please try again.'), findsOneWidget);
    });

    testWidgets('from Profile', (tester) async {
      await show(tester, const ProfileScreen(role: QboxRole.customer));
      await tapKey(tester, 'profile-delete');
      expect(find.byType(DeleteAccountScreen), findsOneWidget);
    });
  });

  group('help, privacy and terms', () {
    test('every page has a title, a date and words', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      for (final page in LegalPage.values) {
        final text = await LegalText.load(rootBundle, page);
        expect(text.title, isNotEmpty);
        expect(text.sections.length, greaterThan(6));
        expect(text.sections.every((s) => s.$1.isNotEmpty && s.$2.isNotEmpty), isTrue);
      }
    });

    testWidgets('help opens its answers; without a contact set there are no buttons', (tester) async {
      await show(tester, const ProfileScreen(role: QboxRole.business));
      await tapKey(tester, 'profile-help');
      expect(find.textContaining('On the login page tap Forgot PIN'), findsNothing);
      await tapKey(tester, 'help-I forgot my PIN');
      expect(find.textContaining('On the login page tap Forgot PIN'), findsOneWidget);
      expect(at('help-contact'), findsNothing);
      await tester.scrollUntilVisible(at('help-terms'), 200, scrollable: find.byType(Scrollable).last);
      await tapKey(tester, 'help-terms');
      expect(find.text('Terms of Use'), findsWidgets);
      expect(find.text('Last changed: 25 November 2026'), findsOneWidget);
    });

    testWidgets('the contact, when it is set', (tester) async {
      api.contact = const SupportContact(name: 'QBOX Support', phone: '9000000000', email: 'help@example.in');
      await show(tester, const LegalScreen(page: LegalPage.help));
      await tester.scrollUntilVisible(at('help-email'), 200, scrollable: find.byType(Scrollable).last);
      await tapKey(tester, 'help-call');
      await tapKey(tester, 'help-whatsapp');
      await tapKey(tester, 'help-email');
      expect(device.opened.map((u) => u.scheme), ['tel', 'whatsapp', 'mailto']);
      device.failScheme = 'tel';
      await tapKey(tester, 'help-call');
      expect(find.text('This phone could not open it.'), findsOneWidget);
    });

    testWidgets('offline, and before logging in', (tester) async {
      api.offline = true;
      draft = OnboardingDraft();
      await show(tester, const SignupScreen());
      await tapKey(tester, 'agree-terms');
      expect(find.text('Terms of Use'), findsOneWidget);
      await tapKey(tester, 'udhaar-back');
      await tapKey(tester, 'agree-privacy');
      expect(find.text('Privacy Policy'), findsWidgets);
      expect(find.textContaining('run by Quadrant IT Services'), findsOneWidget);
    });
  });

  testWidgets('a shop that left QBOX: only to look at', (tester) async {
    const book = MyBook(bookId: 1, shopName: 'Balaji', balancePaise: 50000, closed: true);
    expect(MyBook.fromJson(book.toJson())!.closed, isTrue);
    final udhaar = FakeUdhaarApi()
      ..books.add(book)
      ..bookEntries[1] = [];
    await show(tester, const MyBookScreen(book: book), udhaar: udhaar);
    expect(at('mybook-closed'), findsOneWidget);
    expect(at('mybook-pay'), findsNothing);
    expect(at('mybook-not-me'), findsNothing);
  });

  testWidgets('a small phone with big text has room', (tester) async {
    api.toDelete = const DeleteCheck(youOwePaise: 12345678900, owedToYouPaise: 12345678900);
    api.contact = const SupportContact(name: 'A long support name', phone: '9000000000', email: 'a.long.address@example.in');
    tester.platformDispatcher.textScaleFactorTestValue = 1.4;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    for (final screen in [
      const DeleteAccountScreen(),
      for (final p in LegalPage.values) LegalScreen(page: p),
      const SignupScreen(),
    ]) {
      await show(tester, screen, size: const Size(1080, 1920));
      expect(tester.takeException(), isNull, reason: '$screen');
    }
  });
}
