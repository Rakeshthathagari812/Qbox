import 'package:qbox_app/services/api_client.dart';
import 'package:qbox_app/stock/stock_api.dart';
import 'package:qbox_app/stock/stock_models.dart';

/// A pretend stock backend that follows the FastAPI rules: names unique per
/// shop, quantity = sum of moves, the same clientRef kept once.
class FakeStockApi implements StockApi {
  final Map<int, StockItem> items = {};
  final Map<int, List<StockMove>> moves = {};

  /// Removed items, newest first.
  final List<PastItem> removed = [];
  bool offline = false;
  int _next = 1;

  void _check() {
    if (offline) throw const ApiException('NETWORK', 'Cannot reach the QBOX server.');
  }

  /// Puts an item in stock directly (test setup).
  StockItem seed(String name, StockUnit unit, {int qty = 0, int? alert, int? cost, int? price, String? code}) {
    final id = _next++;
    items[id] = StockItem(id: id, name: name, unit: unit, catalogCode: code, alertMilli: alert, costPaise: cost, pricePaise: price);
    moves[id] = [
      if (qty > 0)
        StockMove(id: _next++, kind: MoveKind.stockIn, qtyMilli: qty, moveAt: DateTime(2026, 11, 1), clientRef: 'seed-$id', note: 'Opening stock'),
    ];
    return _withQty(id);
  }

  StockItem _withQty(int id) {
    final list = moves[id]!;
    final qty = list.fold(0, (s, m) => s + m.effect);
    DateTime? last;
    for (final m in list) {
      if (last == null || m.moveAt.isAfter(last)) last = m.moveAt;
    }
    return items[id]!.copyWith(quantityMilli: qty, lastMoveAt: last);
  }

  @override
  Future<StockBook> stock() async {
    _check();
    final list = [for (final id in items.keys) _withQty(id)]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final live = {for (final i in list) i.name.toLowerCase()};
    return StockBook(list, pastItems: [for (final p in removed) if (!live.contains(p.name.toLowerCase())) p]);
  }

  @override
  Future<StockItem> addItem(ItemDraft d) async {
    _check();
    if (items.values.any((i) => i.name.toLowerCase() == d.name.trim().toLowerCase())) {
      throw ApiException('ITEM_EXISTS', '${d.name.trim()} is already in your stock', status: 409);
    }
    return seed(d.name.trim(), d.unit, qty: d.openingMilli, alert: d.alertMilli, cost: d.costPaise, price: d.pricePaise, code: d.catalogCode);
  }

  @override
  Future<List<StockItem>> addItems(List<ItemDraft> drafts) async {
    _check();
    return [
      for (final d in drafts)
        items.values.where((i) => i.name.toLowerCase() == d.name.toLowerCase()).firstOrNull ?? await addItem(d),
    ];
  }

  @override
  Future<ItemDetail> item(int id) async {
    _check();
    final list = [...moves[id]!]..sort((a, b) => b.moveAt.compareTo(a.moveAt));
    return ItemDetail(item: _withQty(id), moves: list);
  }

  @override
  Future<StockItem> changeItem(int id, {required String name, int? costPaise, int? pricePaise, int? alertMilli}) async {
    _check();
    final old = items[id]!;
    items[id] = StockItem(id: id, name: name, unit: old.unit, catalogCode: old.catalogCode, costPaise: costPaise, pricePaise: pricePaise, alertMilli: alertMilli);
    return _withQty(id);
  }

  @override
  Future<StockItem> archiveItem(int id) async {
    _check();
    final item = _withQty(id);
    items.remove(id);
    removed.insert(0, PastItem(name: item.name, unit: item.unit, catalogCode: item.catalogCode));
    return item;
  }

  @override
  Future<StockMove> addMove(int itemId, MoveDraft d) async {
    _check();
    final list = moves[itemId]!;
    final existing = list.where((m) => m.clientRef == d.clientRef).firstOrNull;
    if (existing != null) return existing;
    final move = StockMove(id: _next++, kind: d.kind, qtyMilli: d.qtyMilli, moveAt: d.moveAt, clientRef: d.clientRef,
        note: d.note.trim().isEmpty ? null : d.note.trim());
    list.add(move);
    return move;
  }
}
