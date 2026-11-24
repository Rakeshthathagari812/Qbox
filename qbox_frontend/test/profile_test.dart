import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:qbox_app/choose_role_screen.dart';
import 'package:qbox_app/customer/page_models.dart';
import 'package:qbox_app/customer_home_screen.dart';
import 'package:qbox_app/models/qbox_user.dart';
import 'package:qbox_app/onboarding_draft.dart';
import 'package:qbox_app/profile/add_role_screen.dart';
import 'package:qbox_app/profile/crop_screen.dart';
import 'package:qbox_app/profile/edit_profile_screen.dart';
import 'package:qbox_app/profile/photos.dart';
import 'package:qbox_app/profile/profile_screen.dart';
import 'package:qbox_app/services/app_services.dart';
import 'package:qbox_app/services/session_store.dart';
import 'package:qbox_app/shop_home_screen.dart';
import 'package:qbox_app/supplier_home_screen.dart';
import 'package:qbox_app/udhaar/my_udhaar_screen.dart';
import 'package:qbox_app/udhaar/udhaar_models.dart';

import 'fake_auth_api.dart';
import 'udhaar_screen_test.dart' show pumpScreen, tapKey;

/// A real picture: left half red, right half blue.
Uint8List picture({int width = 400, int height = 200}) {
  final image = img.Image(width: width, height: height);
  for (final p in image) {
    p.setRgb(p.x < width / 2 ? 255 : 0, 0, p.x < width / 2 ? 0 : 255);
  }
  return img.encodePng(image);
}

void main() {
  late FakeProfileApi api;
  late FakePhotoPicker picker;
  late MemoryPhotoStore photoStore;
  late MemorySessionStore session;
  late OnboardingDraft draft;

  setUp(() {
    api = FakeProfileApi();
    picker = FakePhotoPicker();
    photoStore = MemoryPhotoStore();
    session = MemorySessionStore();
    draft = OnboardingDraft()..applyUser(api.user);
  });

  Future<AppServices> open(WidgetTester tester, Widget home, {FakePagesApi? pages}) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final services = fakeServices(
      profile: api,
      photoPicker: picker,
      photoStore: photoStore,
      session: session,
      pages: pages,
    );
    await tester.pumpWidget(
      ServicesScope(
        services: services,
        child: OnboardingScope(draft: draft, child: MaterialApp(home: home)),
      ),
    );
    await tester.pumpAndSettle();
    return services;
  }

  Future<AppServices> profile(WidgetTester tester, QboxRole role) => open(tester, ProfileScreen(role: role));

  /// Lets real decoding and drawing finish.
  Future<void> real(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Finder at(String key) => find.byKey(Key(key));

  group('photo', () {
    Future<void> choose(WidgetTester tester, String how) async {
      await tapKey(tester, 'profile-photo');
      await tester.tap(at(how));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await real(tester);
    }

    testWidgets('choose, fit and save: a small JPEG with only the picture', (tester) async {
      picker.next = picture();
      await profile(tester, QboxRole.customer);
      await choose(tester, 'photo-gallery');
      await tester.tap(at('crop-use'));
      await real(tester);
      await tester.pumpAndSettle();
      expect(picker.cameras, [false]);
      expect(find.text('Photo saved'), findsOneWidget);
      final saved = api.photos['photo1']!;
      expect(saved.length, lessThan(photoMaxBytes));
      final image = img.decodeJpg(saved)!;
      expect((image.width, image.height), (photoSide, photoSide));
      // The middle of the picture: red on the left, blue on the right.
      expect(image.getPixel(100, 256).r, greaterThan(200));
      expect(image.getPixel(412, 256).b, greaterThan(200));
      expect(draft.user!.customer!.photo, 'photo1');
      expect((await session.readUser())!.customer!.photo, 'photo1');
      expect(photoStore.saved.keys, ['photo1']);
      // Already on the phone: not asked from the server.
      expect(api.calls, ['set photo']);
      expect(find.byKey(const Key('photo-photo1')), findsOneWidget);
    });

    testWidgets('cancel, nothing chosen, refused, unreadable', (tester) async {
      await profile(tester, QboxRole.customer);
      await choose(tester, 'photo-camera');
      expect(picker.cameras, [true]);
      expect(find.byType(CropScreen), findsNothing);
      picker.error = const PhotoException('Allow camera access for QBOX in phone settings.');
      await choose(tester, 'photo-camera');
      expect(find.text('Allow camera access for QBOX in phone settings.'), findsOneWidget);
      picker
        ..error = null
        ..next = Uint8List.fromList([1, 2, 3]);
      await choose(tester, 'photo-gallery');
      expect(at('crop-bad'), findsOneWidget);
      expect(tester.widget<FilledButton>(at('crop-use')).onPressed, isNull);
      await tapKey(tester, 'crop-cancel');
      picker.next = picture();
      await choose(tester, 'photo-gallery');
      await tapKey(tester, 'crop-cancel');
      expect(api.calls, isEmpty);
    });

    testWidgets('offline says so; remove', (tester) async {
      picker.next = picture();
      await profile(tester, QboxRole.business);
      await tapKey(tester, 'profile-photo');
      expect(at('photo-remove'), findsNothing);
      await tester.tapAt(const Offset(20, 60));
      await tester.pumpAndSettle();
      api.offline = true;
      await choose(tester, 'photo-gallery');
      await tester.tap(at('crop-use'));
      await real(tester);
      await tester.pumpAndSettle();
      expect(find.text('This needs internet. Please try again.'), findsOneWidget);
      api.offline = false;
      await choose(tester, 'photo-gallery');
      await tester.tap(at('crop-use'));
      await real(tester);
      await tester.pumpAndSettle();
      expect(draft.user!.shop!.photo, 'photo1');
      await tapKey(tester, 'profile-photo');
      await tapKey(tester, 'photo-remove');
      expect(draft.user!.shop!.photo, isNull);
      expect(find.text('Photo removed'), findsOneWidget);
    });

    test('a photo too big is saved smaller', () {
      final noise = img.Image(width: 512, height: 512);
      var seed = 7;
      for (final p in noise) {
        seed = (seed * 1103515245 + 12345) & 0x7fffffff;
        p.setRgb(seed & 255, (seed >> 8) & 255, (seed >> 16) & 255);
      }
      final rgba = noise.convert(numChannels: 4).getBytes(order: img.ChannelOrder.rgba);
      expect(encodeJpeg(Uint8List.fromList(rgba).buffer, 512, 512).length, lessThanOrEqualTo(photoMaxBytes));
    });

    test('kept on the phone, asked once, forgotten on log out', () async {
      api.photos['a'] = Uint8List.fromList([1]);
      final photos = PhotoRepository(api, photoStore);
      expect(await Future.wait([photos.load('a'), photos.load('a')]), [api.photos['a'], api.photos['a']]);
      expect(api.calls, ['photo a']);
      expect(await photos.load('gone'), isNull);
      final again = PhotoRepository(api..offline = true, photoStore);
      expect(await again.load('a'), api.photos['a']);
      await again.clear();
      expect(photoStore.saved, isEmpty);
      expect(await again.load('a'), isNull);
    });

    testWidgets('customers see the shop photo in My Udhaar', (tester) async {
      api.photos['p1'] = picture();
      final udhaar = FakeUdhaarApi()..books.add(const MyBook(bookId: 1, shopName: 'Balaji', shopPhoto: 'p1'));
      await pumpScreen(tester, fakeServices(udhaar: udhaar, profile: api), const MyUdhaarScreen());
      expect(at('photo-p1'), findsOneWidget);
      final copy = MyBook.fromJson(udhaar.books.single.toJson())!;
      expect(copy.shopPhoto, 'p1');
    });
  });

  group('details', () {
    testWidgets('shop: shown, checked, changed', (tester) async {
      await profile(tester, QboxRole.business);
      expect(find.text('Sri Rama Kirana'), findsOneWidget);
      expect(find.text('QBOX ID: QBM10001'), findsOneWidget);
      expect(find.text('Your customers can see this photo.'), findsOneWidget);
      await tapKey(tester, 'profile-edit');
      await tester.enterText(at('profile-shopName'), '  ');
      await tester.enterText(at('profile-contactNumber'), '123');
      await tapKey(tester, 'profile-save');
      expect(find.text('Enter shop name'), findsOneWidget);
      expect(find.text('Enter a 10-digit mobile number'), findsOneWidget);
      expect(api.calls, isEmpty);
      await tester.enterText(at('profile-shopName'), 'Rama  Stores');
      await tester.enterText(at('profile-contactNumber'), '9000000001');
      await tapKey(tester, 'profile-save');
      expect(find.text('Saved'), findsOneWidget);
      expect(find.text('Rama Stores'), findsOneWidget);
      expect(draft.shop.shopName, 'Rama Stores');
      expect((await session.readUser())!.shop!.contactNumber, '9000000001');
    });

    testWidgets('"Other" needs its own words', (tester) async {
      await profile(tester, QboxRole.supplier);
      await tapKey(tester, 'profile-edit');
      await tapKey(tester, 'profile-businessType');
      await tester.tap(find.text('Other').last);
      await tester.pumpAndSettle();
      await tapKey(tester, 'profile-save');
      expect(find.text('Enter your business type'), findsOneWidget);
      await tester.enterText(at('profile-businessTypeDetail'), 'Cold storage');
      await tapKey(tester, 'profile-save');
      expect(find.text('Cold storage'), findsOneWidget);
    });

    testWidgets('customer: email checked, empty allowed; offline says so', (tester) async {
      await profile(tester, QboxRole.customer);
      expect(find.text('Not added'), findsNWidgets(2));
      expect(find.text('Only you can see this photo.'), findsOneWidget);
      await tapKey(tester, 'profile-edit');
      await tester.enterText(at('profile-email'), 'nope');
      await tapKey(tester, 'profile-save');
      expect(find.text('Enter a valid email'), findsOneWidget);
      await tester.enterText(at('profile-email'), '');
      await tester.enterText(at('profile-address'), 'Main\nRoad');
      api.offline = true;
      await tapKey(tester, 'profile-save');
      expect(find.text('This needs internet. Please try again.'), findsOneWidget);
      api.offline = false;
      await tapKey(tester, 'profile-save');
      expect(find.text('Main Road'), findsOneWidget);
    });
  });

  group('PIN and leaving', () {
    testWidgets('change PIN: checks, then the new login is kept', (tester) async {
      await session.saveToken('old-token');
      await profile(tester, QboxRole.customer);
      await tapKey(tester, 'profile-pin');
      await tapKey(tester, 'pin-save');
      expect(find.text('Enter your old PIN'), findsOneWidget);
      await tester.enterText(at('pin-old'), '1111');
      await tester.enterText(at('pin-new'), '7391');
      await tester.enterText(at('pin-again'), '7392');
      await tapKey(tester, 'pin-save');
      expect(find.text('PINs do not match'), findsOneWidget);
      await tester.enterText(at('pin-again'), '7391');
      await tapKey(tester, 'pin-save');
      expect(find.text('The old PIN is not right'), findsOneWidget);
      await tester.enterText(at('pin-old'), '4826');
      await tester.enterText(at('pin-new'), '1234');
      await tester.enterText(at('pin-again'), '1234');
      await tapKey(tester, 'pin-save');
      expect(find.text('This PIN is too easy to guess. Choose a different PIN'), findsOneWidget);
      await tester.enterText(at('pin-new'), '7391');
      await tester.enterText(at('pin-again'), '7391');
      await tapKey(tester, 'pin-save');
      expect(find.text('PIN changed'), findsOneWidget);
      expect((api.pin, await session.readToken()), ('7391', 'new-token'));
    });

    testWidgets('log out warns about changes not sent yet', (tester) async {
      await session.saveToken('token');
      final pages = FakePagesApi()..offline = true;
      final services = await open(tester, const ProfileScreen(role: QboxRole.customer), pages: pages);
      await services.pages.open();
      services.pages.put(QboxPage(ref: 'a', isList: false, text: 'x', updatedAt: DateTime(2026)));
      await tester.pumpAndSettle();
      await tapKey(tester, 'profile-log-out');
      expect(find.text('1 change on this phone is not sent yet. It will be lost.'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(await session.readToken(), 'token');
      await tapKey(tester, 'profile-log-out');
      await tapKey(tester, 'log-out-sure');
      expect(await session.readToken(), isNull);
      expect(draft.user, isNull);
      expect(find.text('Get started with QBOX'), findsOneWidget);
    });

    testWidgets('log out with nothing waiting does not ask', (tester) async {
      await session.saveToken('token');
      await profile(tester, QboxRole.business);
      await tapKey(tester, 'profile-log-out');
      expect(find.text('Get started with QBOX'), findsOneWidget);
    });

    testWidgets('log out from all phones', (tester) async {
      await session.saveToken('token');
      await profile(tester, QboxRole.business);
      api.offline = true;
      await tapKey(tester, 'profile-log-out-all');
      await tapKey(tester, 'log-out-all-sure');
      expect(find.text('This needs internet. Please try again.'), findsOneWidget);
      expect(await session.readToken(), 'token');
      api.offline = false;
      await tester.pump(const Duration(seconds: 4)); // the message goes
      await tester.pumpAndSettle();
      await tapKey(tester, 'profile-log-out-all');
      await tapKey(tester, 'log-out-all-sure');
      expect(api.calls.last, 'log out all');
      expect(await session.readToken(), isNull);
      expect(find.text('Get started with QBOX'), findsOneWidget);
    });

    testWidgets('voice language', (tester) async {
      await profile(tester, QboxRole.customer);
      await tapKey(tester, 'profile-language');
      await tapKey(tester, 'voice-lang-te');
      expect(find.text('తెలుగు'), findsOneWidget);
    });
  });

  group('adding a role', () {
    QboxUser only(Set<QboxRole> roles) => QboxUser(
      id: 1,
      mobile: '9123456789',
      roles: roles,
      shop: roles.contains(QboxRole.business) ? api.user.shop : null,
      customer: roles.contains(QboxRole.customer) ? api.user.customer : null,
    );

    void start(Set<QboxRole> roles) {
      api.user = only(roles);
      draft.applyUser(api.user);
    }

    testWidgets('from the profile: details, PIN, then it is there', (tester) async {
      start({QboxRole.customer});
      await profile(tester, QboxRole.customer);
      await tapKey(tester, 'profile-add-role');
      expect(at('add-customer'), findsNothing); // they have it
      await tapKey(tester, 'add-supplier');
      expect(find.byType(EditProfileScreen), findsNothing); // coming soon
      await tapKey(tester, 'add-business');
      expect(tester.widget<TextField>(at('profile-contactNumber')).controller!.text, '9123456789');
      await tapKey(tester, 'profile-save');
      expect(find.text('Enter shop name'), findsOneWidget);
      await tester.enterText(at('profile-shopName'), 'My Shop');
      await tester.enterText(at('profile-address'), 'Main Road');
      for (final (key, value) in [('profile-businessType', 'Retail'), ('profile-shopCategory', 'Pet Supplies')]) {
        await tapKey(tester, key);
        await tester.tap(find.text(value).last);
        await tester.pumpAndSettle();
      }
      await tapKey(tester, 'profile-save');
      await tapKey(tester, 'role-pin-ok');
      expect(find.text('Enter your 4-digit PIN'), findsOneWidget);
      await tester.enterText(at('role-pin'), '1111');
      await tapKey(tester, 'role-pin-ok');
      expect(find.text('The PIN is not right'), findsOneWidget);
      await tester.enterText(at('role-pin'), '4826');
      api.offline = true;
      await tapKey(tester, 'role-pin-ok');
      expect(find.text('This needs internet. Please try again.'), findsOneWidget);
      api.offline = false;
      await tapKey(tester, 'role-pin-ok');
      expect(find.text('Business / Shop added. Use Switch role to open it.'), findsOneWidget);
      expect(draft.orderedRoles(), [QboxRole.business, QboxRole.customer]);
      expect(draft.shop.shopName, 'My Shop');
      expect((await session.readUser())!.roles, {QboxRole.business, QboxRole.customer});
      expect(at('profile-add-role'), findsNothing); // only Supplier is left
    });

    testWidgets('a customer, with the login number; then Choose Your Role lists it, with no add button', (tester) async {
      start({QboxRole.business});
      await profile(tester, QboxRole.business);
      await tapKey(tester, 'profile-add-role');
      await tapKey(tester, 'add-customer');
      await tester.enterText(at('profile-fullName'), 'Ravi');
      await tapKey(tester, 'profile-save');
      await tester.enterText(at('role-pin'), '4826');
      await tapKey(tester, 'role-pin-ok');
      expect(draft.user!.customer!.mobileNumber, '9123456789');
      await tester.pumpWidget(const SizedBox());
      await open(tester, const ChooseRoleScreen());
      expect(find.text('Customer'), findsOneWidget);
      expect(find.text('Add a role'), findsNothing);
    });

    testWidgets('going back adds nothing; hidden with every role', (tester) async {
      start({QboxRole.customer});
      await profile(tester, QboxRole.customer);
      await tapKey(tester, 'profile-add-role');
      await tapKey(tester, 'add-business');
      await tapKey(tester, 'udhaar-back');
      await tapKey(tester, 'udhaar-back');
      expect(api.calls, isEmpty);
      expect(at('profile-add-role'), findsOneWidget);
      expect(canAddRole(FakeProfileApi().user), isFalse);
      expect(canAddRole(only({QboxRole.business, QboxRole.customer})), isFalse);
    });
  });

  testWidgets('all three homes open the profile, and show a change at once', (tester) async {
    for (final (home, name) in [
      (const ShopHomeScreen() as Widget, 'Sri Rama Kirana'),
      (const CustomerHomeScreen(), 'Ramu'),
      (const SupplierHomeScreen(), 'Sri Venkateswara Suppliers'),
    ]) {
      await open(tester, home);
      await tapKey(tester, 'home-profile');
      expect(tester.widget<Text>(at('profile-name')).data, name);
      await tester.pumpWidget(const SizedBox());
    }
    await open(tester, const ShopHomeScreen());
    draft.applyUser(
      QboxUser.fromJson({
        ...api.user.toJson(),
        'shop': {...api.user.shop!.toJson(), 'shopName': 'New Name'},
      }),
    );
    await tester.pumpAndSettle();
    expect(find.text('New Name'), findsOneWidget);
  });

  test('the account copy on the phone keeps every detail', () {
    final copy = QboxUser.fromJson(api.user.toJson());
    expect(copy.toJson(), api.user.toJson());
  });

  test('a real decoder agrees the test picture is fine', () async {
    final codec = await ui.instantiateImageCodec(picture());
    expect((await codec.getNextFrame()).image.width, 400);
  });
}
