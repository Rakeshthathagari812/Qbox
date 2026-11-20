import 'dart:async';

import '../services/api_client.dart';
import 'udhaar_api.dart';
import 'udhaar_models.dart';
import 'udhaar_store.dart';

enum SaveOutcome {
  /// On the server.
  saved,

  /// No internet: kept on the phone, sent automatically later.
  savedOffline,
}

/// What happened when the waiting entries were sent.
class SyncReport {
  const SyncReport({this.sent = 0, this.refused = const [], this.waiting = 0});

  final int sent;

  /// Entries the server would not take (shown to the shopkeeper, then dropped).
  final List<String> refused;

  /// Still on the phone (no internet yet).
  final int waiting;
}

/// The udhaar book for the screens: the server copy, the phone copy for
/// offline use, and the queue of entries saved while offline.
///
/// Each entry carries its own id made on the phone (clientRef), so if a
/// sending is retried the server still keeps it only once.
class UdhaarRepository {
  UdhaarRepository(this.api, this.store);

  final UdhaarApi api;
  final UdhaarStore store;

  Future<SyncReport>? _sending;

  // ---------- shop side ----------

  /// The phone copy, including entries not sent yet. Null if never loaded.
  Future<UdhaarBook?> savedBook() async {
    final book = await store.loadBook();
    return book == null ? null : _bookWithPending(book, await store.loadPending());
  }

  /// Sends waiting entries, then gets the latest book from the server.
  /// Throws [ApiException] (e.g. no internet).
  Future<UdhaarBook> freshBook() async {
    await sendPending();
    final book = await api.book();
    await store.saveBook(book);
    return _bookWithPending(book, await store.loadPending());
  }

  /// The phone copy of one customer. If their page was never opened online,
  /// uses their line in the saved book (history then shows only entries
  /// waiting to sync). Null if neither is saved.
  Future<CustomerDetail?> savedCustomer(int id) async {
    var detail = await store.loadCustomer(id);
    if (detail == null) {
      final inBook = (await store.loadBook())?.customers.where((c) => c.id == id).firstOrNull;
      if (inBook == null) return null;
      detail = CustomerDetail(customer: inBook, entries: const []);
    }
    return _detailWithPending(detail, await store.loadPending());
  }

  Future<CustomerDetail> freshCustomer(int id) async {
    await sendPending();
    final detail = await api.customer(id);
    await store.saveCustomer(detail);
    return _detailWithPending(detail, await store.loadPending());
  }

  /// Saves on the server, or on the phone when there is no internet.
  Future<SaveOutcome> addEntry(int customerId, EntryDraft draft) async {
    await sendPending(); // keep entries in the order they were made
    try {
      await api.addEntry(customerId, draft);
      return SaveOutcome.saved;
    } on ApiException catch (e) {
      if (!e.isNetwork) rethrow;
      final pending = await store.loadPending()
        ..add(PendingEntry(customerId: customerId, draft: draft));
      await store.savePending(pending);
      return SaveOutcome.savedOffline;
    }
  }

  Future<int> pendingCount() async => (await store.loadPending()).length;

  /// Sends the entries saved while offline, oldest first. Stops quietly at
  /// the first network problem; they stay on the phone for next time.
  Future<SyncReport> sendPending() {
    return _sending ??= _send().whenComplete(() => _sending = null);
  }

  Future<SyncReport> _send() async {
    var sent = 0;
    final refused = <String>[];
    var pending = await store.loadPending();
    while (pending.isNotEmpty) {
      final next = pending.first;
      try {
        await api.addEntry(next.customerId, next.draft);
        sent++;
      } on ApiException catch (e) {
        if (e.isNetwork || e.isUnauthorized) break;
        refused.add(e.message); // e.g. the amount was refused: drop it
      }
      // Re-read: an entry may have been added while this one was sending.
      pending = await store.loadPending()
        ..removeWhere((p) => p.draft.clientRef == next.draft.clientRef);
      await store.savePending(pending);
    }
    return SyncReport(sent: sent, refused: refused, waiting: pending.length);
  }

  Future<InviteSent> sendInvite(String name, String mobile) =>
      api.sendInvite(name, mobile);

  Future<UdhaarCustomer> addCustomer({
    required String name,
    required String mobile,
    required String otp,
    int? creditLimitPaise,
  }) => api.addCustomer(
    name: name,
    mobile: mobile,
    otp: otp,
    creditLimitPaise: creditLimitPaise,
  );

  Future<UdhaarCustomer> changeCustomer(
    int id, {
    required String name,
    int? creditLimitPaise,
  }) => api.changeCustomer(id, name: name, creditLimitPaise: creditLimitPaise);

  Future<UdhaarEntry> deleteEntry(int entryId, String reason) =>
      api.deleteEntry(entryId, reason);

  // ---------- customer side ----------

  Future<List<MyBook>?> savedMyBooks() => store.loadMyBooks();

  Future<List<MyBook>> freshMyBooks() async {
    final books = await api.myBooks();
    await store.saveMyBooks(books);
    return books;
  }

  Future<InviteSent> sendNumberInvite(int customerId, String mobile) =>
      api.sendNumberInvite(customerId, mobile);

  Future<UdhaarCustomer> changeNumber(int customerId, String mobile, String otp) =>
      api.changeNumber(customerId, mobile, otp);

  Future<UdhaarCustomer> confirmDispute(int customerId) => api.confirmDispute(customerId);

  Future<UdhaarCustomer> unlinkDispute(int customerId) => api.unlinkDispute(customerId);

  Future<MyBookDetail> myBook(int bookId) => api.myBook(bookId);

  Future<MyBook> notMe(int bookId) => api.notMe(bookId);

  Future<MyBook> cancelNotMe(int bookId) => api.cancelNotMe(bookId);

  /// Log out: forget the book and anything not sent.
  Future<void> clear() => store.clear();

  // ---------- adding waiting entries to what is shown ----------

  static UdhaarBook _bookWithPending(UdhaarBook book, List<PendingEntry> pending) {
    if (pending.isEmpty) return book;
    return UdhaarBook([
      for (final c in book.customers) _customerWithPending(c, pending),
    ]);
  }

  static UdhaarCustomer _customerWithPending(
    UdhaarCustomer c,
    List<PendingEntry> pending, {
    Set<String> skip = const {},
  }) {
    var balance = c.balancePaise;
    var last = c.lastEntryAt;
    for (final p in pending) {
      if (p.customerId != c.id || skip.contains(p.draft.clientRef)) continue;
      balance += UdhaarEntry.pending(p.draft).effect;
      if (last == null || p.draft.entryAt.isAfter(last)) last = p.draft.entryAt;
    }
    return c.copyWith(balancePaise: balance, lastEntryAt: last);
  }

  static CustomerDetail _detailWithPending(
    CustomerDetail detail,
    List<PendingEntry> pending,
  ) {
    // Already on the server (sent, but not yet removed from the queue).
    final known = {for (final e in detail.entries) e.clientRef};
    final waiting = [
      for (final p in pending)
        if (p.customerId == detail.customer.id && !known.contains(p.draft.clientRef))
          UdhaarEntry.pending(p.draft),
    ]..sort((a, b) => b.entryAt.compareTo(a.entryAt));
    if (waiting.isEmpty) return detail;
    return CustomerDetail(
      customer: _customerWithPending(detail.customer, pending, skip: known),
      entries: [...waiting, ...detail.entries],
    );
  }
}
