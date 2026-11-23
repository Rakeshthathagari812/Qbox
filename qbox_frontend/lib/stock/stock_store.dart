import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'stock_models.dart';

/// A stock move saved on the phone while offline, waiting to be sent.
class PendingMove {
  const PendingMove({required this.itemId, required this.draft});

  final int itemId;
  final MoveDraft draft;

  Map<String, dynamic> toJson() => {'itemId': itemId, 'draft': draft.toJson()};

  static PendingMove? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final id = json['itemId'];
    final draft = MoveDraft.fromJson(json['draft']);
    if (id is! int || draft == null) return null;
    return PendingMove(itemId: id, draft: draft);
  }
}

/// The stock kept on the phone: a copy of the server's list (so it opens
/// offline) and the moves still waiting to be sent. Cleared on log out.
abstract class StockStore {
  Future<StockBook?> loadBook();

  Future<void> saveBook(StockBook book);

  Future<ItemDetail?> loadItem(int id);

  Future<void> saveItem(ItemDetail detail);

  Future<List<PendingMove>> loadPending();

  Future<void> savePending(List<PendingMove> pending);

  Future<void> clear();
}

/// The phone copy, encrypted with a key in the phone's secure hardware
/// (Android Keystore), like the udhaar book.
class SecureStockStore implements StockStore {
  SecureStockStore({FlutterSecureStorage? storage}) : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _prefix = 'qbox_stock_';
  static const _bookKey = '${_prefix}book';
  static const _pendingKey = '${_prefix}pending';
  static String _itemKey(int id) => '${_prefix}item_$id';

  @override
  Future<StockBook?> loadBook() async => StockBook.fromJson(await _read(_bookKey));

  @override
  Future<void> saveBook(StockBook book) => _write(_bookKey, book.toJson());

  @override
  Future<ItemDetail?> loadItem(int id) async => ItemDetail.fromJson(await _read(_itemKey(id)));

  @override
  Future<void> saveItem(ItemDetail detail) => _write(_itemKey(detail.item.id), detail.toJson());

  @override
  Future<List<PendingMove>> loadPending() async {
    final data = await _read(_pendingKey);
    return data is List ? data.map(PendingMove.fromJson).whereType<PendingMove>().toList() : <PendingMove>[];
  }

  @override
  Future<void> savePending(List<PendingMove> pending) =>
      _write(_pendingKey, [for (final p in pending) p.toJson()]);

  @override
  Future<void> clear() async {
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
    try {
      final text = await _storage.read(key: key);
      return text == null ? null : jsonDecode(text);
    } catch (_) {
      return null; // damaged copy: the next sync replaces it
    }
  }

  Future<void> _write(String key, Object value) => _storage.write(key: key, value: jsonEncode(value));
}

/// In memory only. Used by tests.
class MemoryStockStore implements StockStore {
  StockBook? book;
  final Map<int, ItemDetail> items = {};
  List<PendingMove> pending = [];

  @override
  Future<StockBook?> loadBook() async => book;

  @override
  Future<void> saveBook(StockBook value) async => book = value;

  @override
  Future<ItemDetail?> loadItem(int id) async => items[id];

  @override
  Future<void> saveItem(ItemDetail detail) async => items[detail.item.id] = detail;

  @override
  Future<List<PendingMove>> loadPending() async => List.of(pending);

  @override
  Future<void> savePending(List<PendingMove> list) async => pending = List.of(list);

  @override
  Future<void> clear() async {
    book = null;
    items.clear();
    pending = [];
  }
}
