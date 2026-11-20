import 'package:flutter_test/flutter_test.dart';
import 'package:qbox_app/services/api_client.dart';
import 'package:qbox_app/udhaar/udhaar_models.dart';
import 'package:qbox_app/udhaar/udhaar_repository.dart';
import 'package:qbox_app/udhaar/udhaar_store.dart';
import 'package:qbox_app/udhaar/voice_udhaar.dart';

import 'fake_auth_api.dart';

final now = DateTime(2026, 11, 19, 15);

UdhaarEntry entry(EntryKind kind, int rupeesAmount, {DateTime? at, String ref = 'r', bool deleted = false}) =>
    UdhaarEntry(
      id: 1,
      kind: kind,
      amountPaise: rupeesAmount * 100,
      entryAt: at ?? now,
      clientRef: ref,
      deletedAt: deleted ? now : null,
      deleteReason: deleted ? 'Wrong amount' : null,
    );

/// A server that refuses every entry (e.g. a wrong date), to test dropping it.
class RefusingUdhaarApi extends FakeUdhaarApi {
  @override
  Future<UdhaarEntry> addEntry(int customerId, EntryDraft draft) async =>
      throw const ApiException('INVALID_INPUT', 'The date cannot be in the future', status: 400);
}

void main() {
  group('money', () {
    test('rupees with Indian commas', () {
      expect(rupees(0), '₹0');
      expect(rupees(25000), '₹250');
      expect(rupees(125050), '₹1,250.50');
      expect(rupees(12345678900), '₹12,34,56,789');
      expect(rupees(-5000), '₹50');
    });

    test('typed amounts to paise', () {
      expect(parsePaise('250'), 25000);
      expect(parsePaise('1,250.5'), 125050);
      expect(parsePaise('₹ 99'), 9900);
      expect(parsePaise('12.05'), 1205);
      for (final bad in ['', '0', 'abc', '1.234', '-5', '1.2.3']) {
        expect(parsePaise(bad), isNull, reason: bad);
      }
      expect(paiseToText(25000), '250');
      expect(paiseToText(125050), '1250.50');
    });
  });

  test('phone numbers from contacts become 10 digits', () {
    expect(normalizeMobile('+91 98765-43210'), '9876543210');
    expect(normalizeMobile('098765 43210'), '9876543210');
    expect(normalizeMobile('919876543210'), '9876543210');
    expect(normalizeMobile('12345'), isNull);
    expect(normalizeMobile('5876543210'), isNull); // not a mobile number
  });

  test('dates in the history', () {
    expect(whenLabel(DateTime(2026, 11, 19, 10, 30), now), 'Today, 10:30 AM');
    expect(whenLabel(DateTime(2026, 11, 18, 18, 5), now), 'Yesterday, 6:05 PM');
    expect(whenLabel(DateTime(2026, 9, 3, 9), now), '3 Sep, 9:00 AM');
    expect(whenLabel(DateTime(2025, 1, 3, 9), now), '3 Jan 2025');
  });

  test('running balance skips deleted entries', () {
    final newestFirst = [
      entry(EntryKind.payment, 100),
      entry(EntryKind.credit, 3000, deleted: true),
      entry(EntryKind.credit, 300),
    ];
    final balances = runningBalances(newestFirst);
    expect(balances[newestFirst[2]], 30000);
    expect(balances[newestFirst[1]], 30000); // deleted: no change
    expect(balances[newestFirst[0]], 20000);
  });

  test('overdue and over limit', () {
    final c = UdhaarCustomer(
      id: 1,
      name: 'Ramesh',
      mobile: '9876543210',
      balancePaise: 25000,
      creditLimitPaise: 20000,
      owingSince: DateTime(2026, 10, 1),
    );
    expect(c.overLimit, isTrue);
    expect(c.daysOwing(now), 49);
    expect(c.isOverdue(now), isTrue);
    expect(c.copyWith(balancePaise: 0).isOverdue(now), isFalse);
    expect(UdhaarBook([c, c.copyWith(balancePaise: -500)]).totalPendingPaise, 25000);
  });

  group('voice', () {
    const book = [
      UdhaarCustomer(id: 1, name: 'Ramesh Kumar', mobile: '9000000001'),
      UdhaarCustomer(id: 2, name: 'Suresh', mobile: '9000000002'),
      UdhaarCustomer(id: 3, name: 'Ramesh Rao', mobile: '9000000003'),
      UdhaarCustomer(id: 4, name: 'Lakshmi', mobile: '9000000004'),
    ];
    SpokenUdhaar parse(String s) => parseSpokenUdhaar(s, book)!;

    test('name, amount and udhaar', () {
      final r = parse('Lakshmi 250 udhaar');
      expect(r.matches.single.id, 4);
      expect(r.kind, EntryKind.credit);
      expect(r.amountPaise, 25000);
    });

    test('payments', () {
      expect(parse('Lakshmi paid 100').kind, EntryKind.payment);
      final r = parse('received two fifty from Suresh');
      expect(r.matches.single.id, 2);
      expect(r.kind, EntryKind.payment);
      expect(r.amountPaise, 25000);
    });

    test('"gave" depends on who gave', () {
      expect(parse('gave Suresh 500').kind, EntryKind.credit);
      expect(parse('Suresh gave 500').kind, EntryKind.payment);
      expect(parse('Suresh gave me 500').kind, EntryKind.payment);
    });

    test('two customers with the same first name: ask which one', () {
      expect(parse('Ramesh 300').matches.map((c) => c.id), [1, 3]);
      expect(parse('Ramesh Kumar 300 credit').matches.single.id, 1);
    });

    test('small spelling mistakes from the phone still match', () {
      expect(parse('Sureshh 40 udhaar').matches.single.id, 2);
      expect(parse('Lakshmy 40').matches.single.id, 4);
    });

    test('number words and "add"', () {
      expect(parse('Lakshmi one thousand five hundred udhaar').amountPaise, 150000);
      expect(parse('add 250 udhaar for Lakshmi').amountPaise, 25000);
      expect(parse('Lakshmi 99.50').amountPaise, 9950);
    });

    test('unknown name: offered as a new customer', () {
      final r = parse('Mahesh 400 udhaar');
      expect(r.matches, isEmpty);
      expect(r.spokenName, 'Mahesh');
      expect(r.amountPaise, 40000);
    });

    test('nothing useful', () {
      expect(parseSpokenUdhaar('hello there', book), isNull);
      expect(parseSpokenUdhaar('', book), isNull);
    });
  });

  group('offline queue', () {
    test('saved on the phone without internet, sent once when back', () async {
      final api = FakeUdhaarApi();
      final c = api.seed('Ramesh', '9876543210');
      final repo = UdhaarRepository(api, MemoryUdhaarStore());
      await repo.freshBook(); // book saved on the phone

      api.offline = true;
      final draft = EntryDraft(kind: EntryKind.credit, amountPaise: 25000, entryAt: now);
      expect(await repo.addEntry(c.id, draft), SaveOutcome.savedOffline);
      expect(await repo.pendingCount(), 1);
      // Shown straight away, marked as waiting.
      expect((await repo.savedBook())!.customers.single.balancePaise, 25000);
      final detail = (await repo.savedCustomer(c.id))!;
      expect(detail.entries.single.pending, isTrue);

      api.offline = false;
      final report = await repo.sendPending();
      expect(report.sent, 1);
      expect(await repo.pendingCount(), 0);
      expect(api.entries[c.id]!.length, 1);

      // Sending the same entry again (e.g. the reply was lost) keeps one.
      await api.addEntry(c.id, draft);
      expect(api.entries[c.id]!.length, 1);
      expect((await repo.freshBook()).customers.single.balancePaise, 25000);
    });

    test('an entry the server refuses is dropped and reported', () async {
      final api = RefusingUdhaarApi();
      final c = api.seed('Ramesh', '9876543210');
      final store = MemoryUdhaarStore()
        ..pending = [
          PendingEntry(
            customerId: c.id,
            draft: EntryDraft(kind: EntryKind.credit, amountPaise: 100, entryAt: now),
          ),
        ];
      final report = await UdhaarRepository(api, store).sendPending();
      expect(report.refused, ['The date cannot be in the future']);
      expect(store.pending, isEmpty);
    });

    test('still offline: entries stay on the phone', () async {
      final api = FakeUdhaarApi()..offline = true;
      final store = MemoryUdhaarStore()
        ..pending = [
          PendingEntry(
            customerId: 1,
            draft: EntryDraft(kind: EntryKind.credit, amountPaise: 100, entryAt: now),
          ),
        ];
      final report = await UdhaarRepository(api, store).sendPending();
      expect(report.sent, 0);
      expect(report.waiting, 1);
      expect(store.pending.length, 1);
    });

    test('pending entries survive being saved and read back as JSON', () {
      final draft = EntryDraft(kind: EntryKind.payment, amountPaise: 9950, entryAt: now, note: 'cash');
      final back = PendingEntry.fromJson(PendingEntry(customerId: 7, draft: draft).toJson())!;
      expect(back.customerId, 7);
      expect(back.draft.clientRef, draft.clientRef);
      expect(back.draft.amountPaise, 9950);
      expect(back.draft.kind, EntryKind.payment);
      expect(back.draft.note, 'cash');
    });
  });
}
