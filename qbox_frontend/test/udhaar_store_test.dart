import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qbox_app/udhaar/udhaar_models.dart';
import 'package:qbox_app/udhaar/udhaar_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final draft = EntryDraft(
    kind: EntryKind.credit,
    amountPaise: 25000,
    entryAt: DateTime.utc(2026, 11, 20, 10),
    clientRef: 'abcd1234-ef56',
  );

  test('the udhaar copy is kept in encrypted storage, not in plain app storage', () async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final store = SecureUdhaarStore();
    await store.savePending([PendingEntry(customerId: 7, draft: draft)]);

    final plain = await SharedPreferences.getInstance();
    expect(plain.getKeys().where((k) => k.startsWith('qbox_udhaar_')), isEmpty);
    final secure = await const FlutterSecureStorage().readAll();
    expect(secure.keys, contains('qbox_udhaar_pending'));

    final back = await SecureUdhaarStore().loadPending();
    expect(back.single.customerId, 7);
    expect(back.single.draft.amountPaise, 25000);
  });

  test('an old unencrypted copy is moved over (unsent entries kept) and deleted', () async {
    SharedPreferences.setMockInitialValues({
      'qbox_udhaar_pending': jsonEncode([PendingEntry(customerId: 3, draft: draft).toJson()]),
      'other_setting': 'kept',
    });
    FlutterSecureStorage.setMockInitialValues({});

    final pending = await SecureUdhaarStore().loadPending();
    expect(pending.single.customerId, 3); // nothing lost
    expect(pending.single.draft.clientRef, 'abcd1234-ef56');

    final plain = await SharedPreferences.getInstance();
    expect(plain.getString('qbox_udhaar_pending'), isNull); // the plain copy is gone
    expect(plain.getString('other_setting'), 'kept');
  });

  test('log out clears everything', () async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({'unrelated': 'x'});
    final store = SecureUdhaarStore();
    await store.savePending([PendingEntry(customerId: 1, draft: draft)]);
    await store.clear();
    expect(await store.loadPending(), isEmpty);
    expect(await const FlutterSecureStorage().readAll(), {'unrelated': 'x'});
  });
}
