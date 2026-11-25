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

  /// Connections, per supplier.
  final Map<int, SupplierLink> links = {};

  /// Numbers of people who use QBOX as suppliers: a code connects them at once.
  final Set<String> onQbox = {};
  final Set<int> verified = {};
  final Map<int, List<SupplierProduct>> sells = {};
  final List<String> codes = [];

  /// UPI IDs, per supplier.
  final Map<int, String> upi = {};

  /// Answered to the next change with this error.
  ApiException? nextError;
  static const code = '482915';

  /// Answered to the next code request with this error.
  ApiException? codeError;

  SupplierCode _code(String to, int owed) {
    _check();
    final error = codeError;
    if (error != null) {
      codeError = null;
      throw error;
    }
    codes.add(to);
    return SupplierCode(balancePaise: owed, resendInSeconds: 30, devOtp: code);
  }

  void _connect(int id, String given) {
    if (given != code) {
      throw const ApiException('OTP_WRONG', 'Wrong OTP. Please check and try again', status: 400);
    }
    verified.add(id);
    if (onQbox.contains(known[id]!.mobile)) links[id] = const SupplierLink(status: LinkStatus.on);
  }

  @override
  Future<SupplierCode> sendNewCode({required String name, required String mobile}) async => _code(mobile, 0);

  @override
  Future<SupplierCode> sendCode(int id) async => _code(known[id]!.mobile!, _withAccount(id).balancePaise);

  @override
  Future<Supplier> verify(int id, String otp) async {
    _check();
    _connect(id, otp);
    return _withAccount(id);
  }

  @override
  Future<List<SupplierProduct>> products(int id) async {
    _check();
    return [...?sells[id]];
  }

  @override
  Future<SupplierPay> payInfo(int id) async {
    _check();
    return SupplierPay(name: known[id]!.name, upiId: upi[id]);
  }

  @override
  Future<Supplier> disconnect(int id) async {
    _check();
    links[id] = SupplierLink(status: links[id]?.status == LinkStatus.on ? LinkStatus.ended : LinkStatus.cancelled);
    return _withAccount(id);
  }

  /// Pay-by dates the backend would work out, per supplier (test setup).
  final Map<int, DateTime> dueDates = {};

  void _check() {
    if (offline) throw const ApiException('NETWORK', 'Cannot reach the QBOX server.');
  }

  void _change() {
    _check();
    final error = nextError;
    nextError = null;
    if (error != null) throw error;
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
      if (!e.counts) continue;
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
      link: links[id],
      verified: verified.contains(id),
      toConfirm: entries[id]!.where((e) => e.toAnswer).length,
      takesUpi: links[id]?.status == LinkStatus.on && upi.containsKey(id),
    );
  }

  @override
  Future<SupplierBook> suppliers() async {
    _check();
    return SupplierBook([for (final id in known.keys) _withAccount(id)]);
  }

  @override
  Future<Supplier> addSupplier({required String name, String? mobile, String? supplies, String? note, String? otp, required String clientRef}) async {
    _check();
    if (known.values.any((s) => s.name.toLowerCase() == name.toLowerCase())) {
      throw ApiException('SUPPLIER_EXISTS', '$name is already in your supplier list', status: 409);
    }
    if (otp != null && otp != code) {
      throw const ApiException('OTP_WRONG', 'Wrong OTP. Please check and try again', status: 400);
    }
    final made = seed(name, mobile: mobile, supplies: supplies);
    if (otp != null) _connect(made.id, otp);
    return _withAccount(made.id);
  }

  @override
  Future<SupplierDetail> supplier(int id) async {
    _check();
    final list = [...entries[id]!]..sort((a, b) => b.entryAt.compareTo(a.entryAt));
    return SupplierDetail(
      supplier: _withAccount(id),
      entries: list,
      orders: [for (final o in orders[id]!.reversed) _withPaid(id, o)],
    );
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
    _change();
    final list = entries[supplierId]!;
    final existing = list.where((e) => e.clientRef == d.clientRef).firstOrNull;
    if (existing != null) return existing;
    final entry = SupplierEntry(
      id: _next++, kind: d.kind, amountPaise: d.amountPaise, entryAt: d.entryAt, clientRef: d.clientRef,
      note: d.note.trim().isEmpty ? null : d.note.trim(), dueDate: d.dueDate, method: d.method, lines: d.lines,
      orderId: d.orderId, confirm: _shared(supplierId),
    );
    list.add(entry);
    for (final line in d.lines) {
      final id = await _itemOf(line);
      await stock.addMove(id, MoveDraft(kind: MoveKind.stockIn, qtyMilli: line.qtyMilli, moveAt: d.entryAt,
          note: 'From ${known[supplierId]!.name}', clientRef: 'purchase-${entry.id}-$id'));
    }
    if (d.paidNow) {
      list.add(SupplierEntry(id: _next++, kind: SupplierEntryKind.payment, amountPaise: d.amountPaise, entryAt: d.entryAt,
          clientRef: '${d.clientRef}-paid', note: 'Paid on purchase', method: d.method ?? PayMethod.cash,
          orderId: d.orderId, confirm: _shared(supplierId)));
    }
    return entry;
  }

  Confirm? _shared(int id) => links[id]?.status == LinkStatus.on ? Confirm.waiting : null;

  /// The stock item: by id, or by name and unit (made if the shop has none).
  Future<int> _itemOf(EntryLine line) async {
    if (line.itemId != null) return line.itemId!;
    final found = (await stock.stock()).items.where((i) => i.name.toLowerCase() == line.name.toLowerCase() && i.unit == line.unit);
    return found.isEmpty ? stock.seed(line.name, line.unit).id : found.first.id;
  }

  SupplierOrder _withPaid(int supplierId, SupplierOrder o) {
    int sum(bool Function(SupplierEntry) test) => entries[supplierId]!
        .where((e) => e.orderId == o.id && e.kind == SupplierEntryKind.payment && !e.deleted && test(e))
        .fold(0, (s, e) => s + e.amountPaise);
    final json = o.toJson();
    return SupplierOrder.fromJson({
      ...json,
      'paidPaise': o.paidPaise + sum((e) => e.counts),
      'payingPaise': o.payingPaise + sum((e) => e.confirm == Confirm.waiting),
    })!;
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

  SupplierEntry _answer(int id, Confirm confirm, [String? reason]) {
    for (final list in entries.values) {
      final i = list.indexWhere((e) => e.id == id);
      if (i < 0) continue;
      return list[i] = SupplierEntry.fromJson({...list[i].toJson(), 'confirm': confirm.code, 'disputeReason': reason})!;
    }
    throw const ApiException('ENTRY_NOT_FOUND', 'This entry no longer exists', status: 404);
  }

  @override
  Future<SupplierEntry> confirmEntry(int entryId) async {
    _change();
    final e = _answer(entryId, Confirm.confirmed);
    for (final line in e.lines) {
      final id = await _itemOf(line);
      await stock.addMove(id, MoveDraft(kind: MoveKind.stockIn, qtyMilli: line.qtyMilli, moveAt: e.entryAt,
          clientRef: 'their-${e.id}-$id'));
    }
    return e;
  }

  @override
  Future<SupplierEntry> disputeEntry(int entryId, String reason) async {
    _change();
    return _answer(entryId, Confirm.disputed, reason);
  }

  @override
  Future<SupplierOrder> addOrder(
    int supplierId,
    List<EntryLine> lines, {
    String note = '',
    PayPlan? payPlan,
    DateTime? payBy,
    required String clientRef,
  }) async {
    _change();
    final order = SupplierOrder(
      id: _next++,
      status: OrderStatus.sent,
      lines: [for (final l in lines) EntryLine.fromJson({...l.toJson(), 'id': _next++})!],
      note: note,
      createdAt: DateTime(2026, 11, 23, 10),
      payPlan: payPlan,
      payBy: payBy,
      shared: links[supplierId]?.status == LinkStatus.on,
    );
    orders[supplierId]!.add(order);
    return order;
  }

  @override
  Future<SupplierOrder> receiveOrder(int orderId, SupplierEntryDraft p) async {
    _check();
    for (final entry in orders.entries) {
      final i = entry.value.indexWhere((o) => o.id == orderId);
      if (i < 0) continue;
      await addEntry(
        entry.key,
        SupplierEntryDraft.fromJson({...p.toStore(), 'orderId': orderId})!,
      );
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
