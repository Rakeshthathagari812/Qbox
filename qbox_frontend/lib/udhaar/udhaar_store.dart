import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'udhaar_models.dart';

/// An entry saved on the phone while offline, waiting to be sent.
class PendingEntry {
  const PendingEntry({required this.customerId, required this.draft});

  final int customerId;
  final EntryDraft draft;

  Map<String, dynamic> toJson() => {
    'customerId': customerId,
    'draft': draft.toJson(),
  };

  static PendingEntry? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final id = json['customerId'];
    final draft = EntryDraft.fromJson(json['draft']);
    if (id is! int || draft == null) return null;
    return PendingEntry(customerId: id, draft: draft);
  }
}

/// The udhaar book kept on the phone: a copy of the server's book (so it opens
/// offline) and the entries still waiting to be sent. Cleared on log out.
abstract class UdhaarStore {
  Future<UdhaarBook?> loadBook();

  Future<void> saveBook(UdhaarBook book);

  Future<CustomerDetail?> loadCustomer(int id);

  Future<void> saveCustomer(CustomerDetail detail);

  Future<List<PendingEntry>> loadPending();

  Future<void> savePending(List<PendingEntry> pending);

  Future<List<MyBook>?> loadMyBooks();

  Future<void> saveMyBooks(List<MyBook> books);

  Future<void> clear();
}

/// The phone copy, encrypted with a key kept in the phone's secure hardware
/// (Android Keystore), like the login token: customer names, numbers and
/// balances cannot be read by other apps, from backups or from the phone's files.
class SecureUdhaarStore implements UdhaarStore {
  SecureUdhaarStore({FlutterSecureStorage? storage}) : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  bool _moved = false;

  static const _prefix = 'qbox_udhaar_';
  static const _bookKey = '${_prefix}book';
  static const _pendingKey = '${_prefix}pending';
  static const _myBooksKey = '${_prefix}mine';
  static String _customerKey(int id) => '${_prefix}customer_$id';

  @override
  Future<UdhaarBook?> loadBook() async => UdhaarBook.fromJson(await _read(_bookKey));

  @override
  Future<void> saveBook(UdhaarBook book) => _write(_bookKey, book.toJson());

  @override
  Future<CustomerDetail?> loadCustomer(int id) async =>
      CustomerDetail.fromJson(await _read(_customerKey(id)));

  @override
  Future<void> saveCustomer(CustomerDetail detail) =>
      _write(_customerKey(detail.customer.id), detail.toJson());

  @override
  Future<List<PendingEntry>> loadPending() async {
    final data = await _read(_pendingKey);
    return data is List
        ? data.map(PendingEntry.fromJson).whereType<PendingEntry>().toList()
        : <PendingEntry>[];
  }

  @override
  Future<void> savePending(List<PendingEntry> pending) =>
      _write(_pendingKey, [for (final p in pending) p.toJson()]);

  @override
  Future<List<MyBook>?> loadMyBooks() async {
    final data = await _read(_myBooksKey);
    return data is List ? data.map(MyBook.fromJson).whereType<MyBook>().toList() : null;
  }

  @override
  Future<void> saveMyBooks(List<MyBook> books) =>
      _write(_myBooksKey, [for (final b in books) b.toJson()]);

  @override
  Future<void> clear() async {
    await _moveOldCopy();
    try {
      final all = await _storage.readAll();
      for (final key in all.keys.where((k) => k.startsWith(_prefix))) {
        await _storage.delete(key: key);
      }
    } catch (_) {
      // Storage unreadable: nothing that can be read is left.
    }
  }

  Future<Object?> _read(String key) async {
    await _moveOldCopy();
    try {
      final text = await _storage.read(key: key);
      return text == null ? null : jsonDecode(text);
    } catch (_) {
      return null; // damaged copy: the next sync replaces it
    }
  }

  Future<void> _write(String key, Object value) async {
    await _moveOldCopy();
    await _storage.write(key: key, value: jsonEncode(value));
  }

  /// Earlier versions kept the copy unencrypted. Moved over once (unsent
  /// entries included, so nothing is lost), then the old copy is deleted.
  Future<void> _moveOldCopy() async {
    if (_moved) return;
    _moved = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final key in prefs.getKeys().where((k) => k.startsWith(_prefix)).toList()) {
        final text = prefs.getString(key);
        if (text != null && await _storage.read(key: key) == null) {
          await _storage.write(key: key, value: text);
        }
        await prefs.remove(key);
      }
    } catch (_) {
      _moved = false; // try again next time
    }
  }
}

/// In memory only. Used by tests.
class MemoryUdhaarStore implements UdhaarStore {
  UdhaarBook? book;
  final Map<int, CustomerDetail> customers = {};
  List<PendingEntry> pending = [];
  List<MyBook>? myBooks;

  @override
  Future<UdhaarBook?> loadBook() async => book;

  @override
  Future<void> saveBook(UdhaarBook value) async => book = value;

  @override
  Future<CustomerDetail?> loadCustomer(int id) async => customers[id];

  @override
  Future<void> saveCustomer(CustomerDetail detail) async =>
      customers[detail.customer.id] = detail;

  @override
  Future<List<PendingEntry>> loadPending() async => List.of(pending);

  @override
  Future<void> savePending(List<PendingEntry> list) async => pending = List.of(list);

  @override
  Future<List<MyBook>?> loadMyBooks() async => myBooks;

  @override
  Future<void> saveMyBooks(List<MyBook> books) async => myBooks = List.of(books);

  @override
  Future<void> clear() async {
    book = null;
    customers.clear();
    pending = [];
    myBooks = null;
  }
}
