import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../services/api_client.dart';
import 'supplier_api.dart';
import 'supplier_models.dart';

/// A purchase or payment saved on the phone while offline.
class PendingSupplierEntry {
  const PendingSupplierEntry({required this.supplierId, required this.draft});

  final int supplierId;
  final SupplierEntryDraft draft;

  Map<String, dynamic> toJson() => {'supplierId': supplierId, 'draft': draft.toStore()};

  static PendingSupplierEntry? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final id = json['supplierId'];
    final draft = SupplierEntryDraft.fromJson(json['draft']);
    if (id is! int || draft == null) return null;
    return PendingSupplierEntry(supplierId: id, draft: draft);
  }
}

/// The supplier list kept on the phone (so it opens offline) and the entries
/// waiting to be sent. Cleared on log out.
abstract class SupplierStore {
  Future<SupplierBook?> loadBook();
  Future<void> saveBook(SupplierBook book);
  Future<SupplierDetail?> loadSupplier(int id);
  Future<void> saveSupplier(SupplierDetail detail);
  Future<List<PendingSupplierEntry>> loadPending();
  Future<void> savePending(List<PendingSupplierEntry> pending);
  Future<void> clear();
}

/// Encrypted with a key in the phone's secure hardware, like udhaar and stock.
class SecureSupplierStore implements SupplierStore {
  SecureSupplierStore({FlutterSecureStorage? storage}) : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _prefix = 'qbox_suppliers_';
  static const _bookKey = '${_prefix}book';
  static const _pendingKey = '${_prefix}pending';
  static String _supplierKey(int id) => '${_prefix}supplier_$id';

  @override
  Future<SupplierBook?> loadBook() async => SupplierBook.fromJson(await _read(_bookKey));

  @override
  Future<void> saveBook(SupplierBook book) => _write(_bookKey, book.toJson());

  @override
  Future<SupplierDetail?> loadSupplier(int id) async => SupplierDetail.fromJson(await _read(_supplierKey(id)));

  @override
  Future<void> saveSupplier(SupplierDetail detail) => _write(_supplierKey(detail.supplier.id), detail.toJson());

  @override
  Future<List<PendingSupplierEntry>> loadPending() async {
    final data = await _read(_pendingKey);
    return data is List
        ? data.map(PendingSupplierEntry.fromJson).whereType<PendingSupplierEntry>().toList()
        : <PendingSupplierEntry>[];
  }

  @override
  Future<void> savePending(List<PendingSupplierEntry> pending) =>
      _write(_pendingKey, [for (final p in pending) p.toJson()]);

  @override
  Future<void> clear() async {
    try {
      final all = await _storage.readAll();
      for (final key in all.keys.where((k) => k.startsWith(_prefix))) {
        await _storage.delete(key: key);
      }
    } catch (_) {}
  }

  Future<Object?> _read(String key) async {
    try {
      final text = await _storage.read(key: key);
      return text == null ? null : jsonDecode(text);
    } catch (_) {
      return null;
    }
  }

  Future<void> _write(String key, Object value) => _storage.write(key: key, value: jsonEncode(value));
}

/// In memory only. Used by tests.
class MemorySupplierStore implements SupplierStore {
  SupplierBook? book;
  final Map<int, SupplierDetail> details = {};
  List<PendingSupplierEntry> pending = [];

  @override
  Future<SupplierBook?> loadBook() async => book;
  @override
  Future<void> saveBook(SupplierBook value) async => book = value;
  @override
  Future<SupplierDetail?> loadSupplier(int id) async => details[id];
  @override
  Future<void> saveSupplier(SupplierDetail detail) async => details[detail.supplier.id] = detail;
  @override
  Future<List<PendingSupplierEntry>> loadPending() async => List.of(pending);
  @override
  Future<void> savePending(List<PendingSupplierEntry> list) async => pending = List.of(list);
  @override
  Future<void> clear() async {
    book = null;
    details.clear();
    pending = [];
  }
}

enum EntrySaved { saved, savedOffline }

/// Suppliers for the screens: the server copy, the phone copy, and the queue
/// of purchases/payments saved while offline (each kept once, by clientRef).
/// Adding suppliers and orders needs internet.
class SupplierRepository {
  SupplierRepository(this.api, this.store);

  final SupplierApi api;
  final SupplierStore store;
  Future<(int, List<String>)>? _sending;

  Future<SupplierBook?> savedBook() async {
    final book = await store.loadBook();
    return book == null ? null : _bookWithPending(book, await store.loadPending());
  }

  Future<SupplierBook> freshBook() async {
    await sendPending();
    final book = await api.suppliers();
    await store.saveBook(book);
    return _bookWithPending(book, await store.loadPending());
  }

  Future<SupplierDetail?> savedSupplier(int id) async {
    var detail = await store.loadSupplier(id);
    if (detail == null) {
      final inBook = (await store.loadBook())?.suppliers.where((s) => s.id == id).firstOrNull;
      if (inBook == null) return null;
      detail = SupplierDetail(supplier: inBook, entries: const [], orders: const []);
    }
    return _detailWithPending(detail, await store.loadPending());
  }

  Future<SupplierDetail> freshSupplier(int id) async {
    await sendPending();
    final detail = await api.supplier(id);
    await store.saveSupplier(detail);
    return _detailWithPending(detail, await store.loadPending());
  }

  Future<EntrySaved> addEntry(int supplierId, SupplierEntryDraft draft) async {
    await sendPending();
    try {
      await api.addEntry(supplierId, draft);
      return EntrySaved.saved;
    } on ApiException catch (e) {
      if (!e.isNetwork) rethrow;
      final pending = await store.loadPending()..add(PendingSupplierEntry(supplierId: supplierId, draft: draft));
      await store.savePending(pending);
      return EntrySaved.savedOffline;
    }
  }

  Future<int> pendingCount() async => (await store.loadPending()).length;

  /// Sends what was saved offline, oldest first. Returns (sent, refused messages).
  Future<(int, List<String>)> sendPending() => _sending ??= _send().whenComplete(() => _sending = null);

  Future<(int, List<String>)> _send() async {
    var sent = 0;
    final refused = <String>[];
    var pending = await store.loadPending();
    while (pending.isNotEmpty) {
      final next = pending.first;
      try {
        await api.addEntry(next.supplierId, next.draft);
        sent++;
      } on ApiException catch (e) {
        if (e.isNetwork || e.isUnauthorized) break;
        refused.add(e.message);
      }
      pending = await store.loadPending()..removeWhere((p) => p.draft.clientRef == next.draft.clientRef);
      await store.savePending(pending);
    }
    return (sent, refused);
  }

  Future<Supplier> addSupplier({required String name, String? mobile, String? supplies, String? note, required String clientRef}) =>
      api.addSupplier(name: name, mobile: mobile, supplies: supplies, note: note, clientRef: clientRef);

  Future<Supplier> changeSupplier(int id, {required String name, String? mobile, String? supplies, String? note}) =>
      api.changeSupplier(id, name: name, mobile: mobile, supplies: supplies, note: note);

  Future<Supplier> archiveSupplier(int id) => api.archiveSupplier(id);

  Future<SupplierEntry> deleteEntry(int entryId, String reason) => api.deleteEntry(entryId, reason);

  Future<SupplierOrder> addOrder(int supplierId, List<EntryLine> lines, {String note = '', required String clientRef}) =>
      api.addOrder(supplierId, lines, note: note, clientRef: clientRef);

  Future<SupplierOrder> receiveOrder(int orderId, SupplierEntryDraft purchase) => api.receiveOrder(orderId, purchase);

  Future<SupplierOrder> cancelOrder(int orderId) => api.cancelOrder(orderId);

  Future<void> clear() => store.clear();

  static SupplierBook _bookWithPending(SupplierBook book, List<PendingSupplierEntry> pending) {
    if (pending.isEmpty) return book;
    return SupplierBook([for (final s in book.suppliers) _supplierWithPending(s, pending)]);
  }

  static Supplier _supplierWithPending(Supplier s, List<PendingSupplierEntry> pending, {Set<String> skip = const {}}) {
    var balance = s.balancePaise;
    var last = s.lastEntryAt;
    for (final p in pending) {
      if (p.supplierId != s.id || skip.contains(p.draft.clientRef)) continue;
      balance += p.draft.effect;
      if (last == null || p.draft.entryAt.isAfter(last)) last = p.draft.entryAt;
    }
    return s.copyWith(balancePaise: balance, lastEntryAt: last);
  }

  static SupplierDetail _detailWithPending(SupplierDetail detail, List<PendingSupplierEntry> pending) {
    final known = {for (final e in detail.entries) e.clientRef};
    final waiting = [
      for (final p in pending)
        if (p.supplierId == detail.supplier.id && !known.contains(p.draft.clientRef)) SupplierEntry.pending(p.draft),
    ]..sort((a, b) => b.entryAt.compareTo(a.entryAt));
    if (waiting.isEmpty) return detail;
    return SupplierDetail(
      supplier: _supplierWithPending(detail.supplier, pending, skip: known),
      entries: [...waiting, ...detail.entries],
      orders: detail.orders,
    );
  }
}
