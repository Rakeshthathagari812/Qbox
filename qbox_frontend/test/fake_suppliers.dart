import 'package:qbox_app/services/api_client.dart';
import 'package:qbox_app/stock/stock_models.dart';
import 'package:qbox_app/suppliers/supplier_api.dart';
import 'package:qbox_app/suppliers/supplier_models.dart';

import 'fake_stock.dart';

/// A pretend supplier backend following the FastAPI rules. Purchases add their
/// items to [stock] (the pretend stock backend).
class FakeSupplierApi implements SupplierApi {
  FakeSupplierApi({FakeStockApi? stock}) : stock = stock ?? FakeStockApi();

  final FakeStockApi stock;
  final Map<int, Supplier> known = {};
  final Map<int, List<SupplierEntry>> entries = {};
  final Map<int, List<SupplierOrder>> orders = {};
  bool offline = false;
  int _next = 100;

  /// Pay-by dates the backend would work out, per supplier (test setup).
  final Map<int, DateTime> dueDates = {};

  void _check() {
    if (offline) throw const ApiException('NETWORK', 'Cannot reach the QBOX server.');
  }

  Supplier seed(String name, {String? mobile, String? supplies}) {
    final id = _next++;
    known[id] = Supplier(id: id, name: name, mobile: mobile, supplies: supplies);
    entries[id] = [];
    orders[id] = [];
    return _withAccount(id);
  }

  Supplier _withAccount(int id) {
    final s = known[id]!;
    var balance = 0;
    DateTime? last;
    for (final e in entries[id]!) {
      if (e.deleted) continue;
      balance += e.kind == SupplierEntryKind.purchase ? e.amountPaise : -e.amountPaise;
      if (last == null || e.entryAt.isAfter(last)) last = e.entryAt;
    }
    final due = balance > 0 ? dueDates[id] : null;
    return Supplier(
      id: id,
      name: s.name,
      mobile: s.mobile,
      supplies: s.supplies,
      balancePaise: balance,
      lastEntryAt: last,
      nextDue: due,
      overdue: due != null && due.isBefore(DateTime(2026, 11, 23)),
      openOrders: orders[id]!.where((o) => o.open).length,
    );
  }

  @override
  Future<SupplierBook> suppliers() async {
    _check();
    return SupplierBook([for (final id in known.keys) _withAccount(id)]);
  }

  @override
  Future<Supplier> addSupplier({required String name, String? mobile, String? supplies, String? note, required String clientRef}) async {
    _check();
    if (known.values.any((s) => s.name.toLowerCase() == name.toLowerCase())) {
      throw ApiException('SUPPLIER_EXISTS', '$name is already in your supplier list', status: 409);
    }
    return seed(name, mobile: mobile, supplies: supplies);
  }

  @override
  Future<SupplierDetail> supplier(int id) async {
    _check();
    final list = [...entries[id]!]..sort((a, b) => b.entryAt.compareTo(a.entryAt));
    return SupplierDetail(supplier: _withAccount(id), entries: list, orders: [...orders[id]!.reversed]);
  }

  @override
  Future<Supplier> changeSupplier(int id, {required String name, String? mobile, String? supplies, String? note}) async {
    _check();
    known[id] = Supplier(id: id, name: name, mobile: mobile, supplies: supplies);
    return _withAccount(id);
  }

  @override
  Future<Supplier> archiveSupplier(int id) async {
    _check();
    final s = _withAccount(id);
    known.remove(id);
    return s;
  }

  @override
  Future<SupplierEntry> addEntry(int supplierId, SupplierEntryDraft d) async {
    _check();
    final list = entries[supplierId]!;
    final existing = list.where((e) => e.clientRef == d.clientRef).firstOrNull;
    if (existing != null) return existing;
    final entry = SupplierEntry(
      id: _next++, kind: d.kind, amountPaise: d.amountPaise, entryAt: d.entryAt, clientRef: d.clientRef,
      note: d.note.trim().isEmpty ? null : d.note.trim(), dueDate: d.dueDate, method: d.method, lines: d.lines,
    );
    list.add(entry);
    for (final line in d.lines) {
      await stock.addMove(line.itemId!, MoveDraft(kind: MoveKind.stockIn, qtyMilli: line.qtyMilli, moveAt: d.entryAt,
          note: 'From ${known[supplierId]!.name}', clientRef: 'purchase-${entry.id}-${line.itemId}'));
    }
    if (d.paidNow) {
      list.add(SupplierEntry(id: _next++, kind: SupplierEntryKind.payment, amountPaise: d.amountPaise, entryAt: d.entryAt,
          clientRef: '${d.clientRef}-paid', note: 'Paid on purchase', method: d.method ?? PayMethod.cash));
    }
    return entry;
  }

  @override
  Future<SupplierEntry> deleteEntry(int entryId, String reason) async {
    _check();
    for (final list in entries.values) {
      final i = list.indexWhere((e) => e.id == entryId);
      if (i < 0) continue;
      final e = list[i];
      list[i] = SupplierEntry(id: e.id, kind: e.kind, amountPaise: e.amountPaise, entryAt: e.entryAt, clientRef: e.clientRef,
          note: e.note, lines: e.lines, deletedAt: DateTime.now(), deleteReason: reason);
      return list[i];
    }
    throw const ApiException('ENTRY_NOT_FOUND', 'This entry no longer exists', status: 404);
  }

  @override
  Future<SupplierOrder> addOrder(int supplierId, List<EntryLine> lines, {String note = '', required String clientRef}) async {
    _check();
    final order = SupplierOrder(id: _next++, status: OrderStatus.sent, lines: lines, note: note, createdAt: DateTime(2026, 11, 23, 10));
    orders[supplierId]!.add(order);
    return order;
  }

  @override
  Future<SupplierOrder> receiveOrder(int orderId, SupplierEntryDraft p) async {
    _check();
    for (final entry in orders.entries) {
      final i = entry.value.indexWhere((o) => o.id == orderId);
      if (i < 0) continue;
      await addEntry(entry.key, p);
      final o = entry.value[i];
      entry.value[i] = SupplierOrder(id: o.id, status: OrderStatus.received, lines: o.lines, createdAt: o.createdAt, receivedAt: DateTime.now());
      return entry.value[i];
    }
    throw const ApiException('ORDER_NOT_FOUND', 'This order is not available', status: 404);
  }

  @override
  Future<SupplierOrder> cancelOrder(int orderId) async {
    _check();
    for (final list in orders.values) {
      final i = list.indexWhere((o) => o.id == orderId);
      if (i < 0) continue;
      final o = list[i];
      list[i] = SupplierOrder(id: o.id, status: OrderStatus.cancelled, lines: o.lines, createdAt: o.createdAt);
      return list[i];
    }
    throw const ApiException('ORDER_NOT_FOUND', 'This order is not available', status: 404);
  }
}
