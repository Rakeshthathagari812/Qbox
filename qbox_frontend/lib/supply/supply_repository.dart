import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../services/api_client.dart';
import '../suppliers/supplier_models.dart' show SupplierEntryDraft, dayText;
import 'supply_models.dart';

/// The supplier's shops and orders. Needs login (supplier).
abstract class SupplyApi {
  Future<SupplyHome> home();

  Future<SupplyShopDetail> shop(int linkId);

  Future<List<SupplyOrder>> orders();

  /// Connect, agreeing the amount that was shown.
  Future<void> acceptShop(int linkId, int balancePaise);

  Future<void> declineShop(int linkId, String reason);

  Future<void> endShop(int linkId);

  /// Goods given, or money received. The shop answers.
  Future<void> addEntry(int linkId, SupplierEntryDraft draft);

  /// The supplier's own entry, until the shop confirms it.
  Future<void> deleteEntry(int entryId, String reason);

  Future<void> confirmEntry(int entryId);

  Future<void> disputeEntry(int entryId, String reason);

  Future<void> acceptOrder(int orderId, List<LineAnswer> lines, {required int totalPaise, String note});

  Future<void> rejectOrder(int orderId, String reason);

  Future<void> dispatchOrder(int orderId);

  Future<List<Product>> products();

  Future<void> addProducts(List<ProductDraft> drafts);

  Future<void> changeProduct(int id, {required String name, int? pricePaise, required bool available});

  Future<void> removeProduct(int id);

  /// The supplier's own stock of a product.
  Future<ProductStock> productStock(int id);

  Future<void> addMove(int id, CountKind kind, int qtyMilli, {String note, required String clientRef});

  Future<void> setCounting(int id, {required bool counted, int? alertMilli});

  Future<SupplyReport> report(DateTime start, DateTime end);

  Future<SupplyPayments> payments();

  /// Empty = remove it.
  Future<void> saveUpi(String upiId, String name);
}

class HttpSupplyApi implements SupplyApi {
  HttpSupplyApi(this._api);

  final ApiClient _api;

  static const _base = '/api/supply';
  static const _bad = ApiException('ERROR', 'Something went wrong. Please try again.');

  @override
  Future<SupplyHome> home() async => SupplyHome.fromJson(await _api.get('$_base/shops')) ?? (throw _bad);

  @override
  Future<SupplyShopDetail> shop(int linkId) async =>
      SupplyShopDetail.fromJson(await _api.get('$_base/shops/$linkId')) ?? (throw _bad);

  @override
  Future<List<SupplyOrder>> orders() async {
    final json = await _api.get('$_base/orders');
    if (json is! List) throw _bad;
    return json.map(SupplyOrder.fromJson).whereType<SupplyOrder>().toList();
  }

  @override
  Future<void> acceptShop(int linkId, int balancePaise) =>
      _api.post('$_base/shops/$linkId/accept', {'balancePaise': balancePaise});

  @override
  Future<void> declineShop(int linkId, String reason) =>
      _api.post('$_base/shops/$linkId/decline', {'reason': reason.trim().isEmpty ? null : reason.trim()});

  @override
  Future<void> endShop(int linkId) => _api.post('$_base/shops/$linkId/end', {});

  @override
  Future<void> addEntry(int linkId, SupplierEntryDraft d) => _api.post('$_base/shops/$linkId/entries', {
    'kind': d.kind.code,
    'amountPaise': d.amountPaise,
    'note': d.note.trim().isEmpty ? null : d.note.trim(),
    'entryAt': d.entryAt.toUtc().toIso8601String(),
    'method': d.method?.code,
    'lines': [for (final l in d.lines) l.toInput()],
    'clientRef': d.clientRef,
  });

  @override
  Future<void> deleteEntry(int entryId, String reason) =>
      _api.post('$_base/entries/$entryId/delete', {'reason': reason});

  @override
  Future<void> confirmEntry(int entryId) => _api.post('$_base/entries/$entryId/confirm', {});

  @override
  Future<void> disputeEntry(int entryId, String reason) =>
      _api.post('$_base/entries/$entryId/dispute', {'reason': reason});

  @override
  Future<void> acceptOrder(int orderId, List<LineAnswer> lines, {required int totalPaise, String note = ''}) =>
      _api.post('$_base/orders/$orderId/accept', {
        'lines': [for (final l in lines) l.toJson()],
        'totalPaise': totalPaise,
        'note': note.trim().isEmpty ? null : note.trim(),
      });

  @override
  Future<void> rejectOrder(int orderId, String reason) => _api.post('$_base/orders/$orderId/reject', {'reason': reason});

  @override
  Future<void> dispatchOrder(int orderId) => _api.post('$_base/orders/$orderId/dispatch', {});

  @override
  Future<List<Product>> products() async {
    final json = await _api.get('$_base/products');
    if (json is! List) throw _bad;
    return json.map(Product.fromJson).whereType<Product>().toList();
  }

  @override
  Future<void> addProducts(List<ProductDraft> drafts) =>
      _api.post('$_base/products', {'products': [for (final d in drafts) d.toJson()]});

  @override
  Future<void> changeProduct(int id, {required String name, int? pricePaise, required bool available}) =>
      _api.put('$_base/products/$id', {'name': name, 'pricePaise': pricePaise, 'available': available});

  @override
  Future<void> removeProduct(int id) => _api.delete('$_base/products/$id');

  @override
  Future<ProductStock> productStock(int id) async =>
      ProductStock.fromJson(await _api.get('$_base/products/$id/stock')) ?? (throw _bad);

  @override
  Future<void> addMove(int id, CountKind kind, int qtyMilli, {String note = '', required String clientRef}) =>
      _api.post('$_base/products/$id/moves', {
        'kind': kind.code,
        'qtyMilli': qtyMilli,
        'note': note.trim().isEmpty ? null : note.trim(),
        'clientRef': clientRef,
      });

  @override
  Future<void> setCounting(int id, {required bool counted, int? alertMilli}) =>
      _api.put('$_base/products/$id/stock', {'counted': counted, 'alertMilli': alertMilli});

  @override
  Future<SupplyReport> report(DateTime start, DateTime end) async =>
      SupplyReport.fromJson(await _api.get('$_base/report?start=${dayText(start)}&end=${dayText(end)}')) ?? (throw _bad);

  @override
  Future<SupplyPayments> payments() async =>
      SupplyPayments.fromJson(await _api.get('$_base/payments')) ?? (throw _bad);

  @override
  Future<void> saveUpi(String upiId, String name) =>
      _api.put('$_base/upi', {'upiId': upiId.trim(), 'upiName': name.trim()});
}

/// The last copy of each screen, to read it offline. Cleared on log out.
abstract class SupplyStore {
  Future<Object?> load(String key);

  Future<void> save(String key, Object value);

  Future<void> clear();
}

/// Encrypted with a key in the phone's secure hardware.
class SecureSupplyStore implements SupplyStore {
  SecureSupplyStore({FlutterSecureStorage? storage}) : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _prefix = 'qbox_supply_';

  @override
  Future<Object?> load(String key) async {
    try {
      final text = await _storage.read(key: '$_prefix$key');
      return text == null ? null : jsonDecode(text);
    } catch (_) {
      return null; // damaged copy: the next load replaces it
    }
  }

  @override
  Future<void> save(String key, Object value) => _storage.write(key: '$_prefix$key', value: jsonEncode(value));

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
}

/// In memory only. Used by tests.
class MemorySupplyStore implements SupplyStore {
  final Map<String, Object?> saved = {};

  @override
  Future<Object?> load(String key) async => saved[key];

  @override
  Future<void> save(String key, Object value) async => saved[key] = jsonDecode(jsonEncode(value));

  @override
  Future<void> clear() async => saved.clear();
}

/// The supplier's shops and orders for the screens: the phone copy to read
/// offline, and the server's. Answering needs internet.
class SupplyRepository {
  SupplyRepository(this.api, this.store);

  final SupplyApi api;
  final SupplyStore store;

  Future<SupplyHome?> savedHome() async => SupplyHome.fromJson(await store.load('home'));

  Future<SupplyHome> home() async {
    final fresh = await api.home();
    await store.save('home', fresh.toJson());
    return fresh;
  }

  Future<SupplyShopDetail?> savedShop(int linkId) async => SupplyShopDetail.fromJson(await store.load('shop_$linkId'));

  Future<SupplyShopDetail> shop(int linkId) async {
    final fresh = await api.shop(linkId);
    await store.save('shop_$linkId', fresh.toJson());
    return fresh;
  }

  Future<List<SupplyOrder>?> savedOrders() async {
    final json = await store.load('orders');
    return json is List ? json.map(SupplyOrder.fromJson).whereType<SupplyOrder>().toList() : null;
  }

  Future<List<SupplyOrder>> orders() async {
    final fresh = await api.orders();
    await store.save('orders', [for (final o in fresh) o.toJson()]);
    return fresh;
  }

  Future<List<Product>?> savedProducts() async {
    final json = await store.load('products');
    return json is List ? json.map(Product.fromJson).whereType<Product>().toList() : null;
  }

  Future<List<Product>> products() async {
    final fresh = await api.products();
    await store.save('products', [for (final p in fresh) p.toJson()]);
    return fresh;
  }

  Future<SupplyPayments?> savedPayments() async => SupplyPayments.fromJson(await store.load('payments'));

  Future<SupplyPayments> payments() async {
    final fresh = await api.payments();
    await store.save('payments', fresh.toJson());
    return fresh;
  }

  Future<void> clear() => store.clear();
}
