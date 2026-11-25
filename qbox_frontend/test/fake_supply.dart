import 'package:qbox_app/services/api_client.dart';
import 'package:qbox_app/stock/stock_models.dart' show MoveKind;
import 'package:qbox_app/suppliers/supplier_models.dart' show Confirm, OrderStatus, SupplierEntryDraft, dayText;
import 'package:qbox_app/supply/supply_models.dart';
import 'package:qbox_app/supply/supply_repository.dart';

/// Pretend supplier-side server.
class FakeSupplyApi implements SupplyApi {
  List<SupplyShop> requests = [];
  List<SupplyShop> shops = [];
  Map<int, List<SupplyEntry>> entries = {};
  List<SupplyOrder> all = [];
  List<Product> sells = [];
  int _next = 500;
  final List<String> calls = [];
  bool offline = false;

  /// Answered to the next change with this error.
  ApiException? nextError;

  void _check([String? call]) {
    if (call != null) calls.add(call);
    if (offline) {
      throw const ApiException('NETWORK', 'Cannot reach the QBOX server. Check your internet connection.');
    }
    final error = nextError;
    if (call != null && error != null) {
      nextError = null;
      throw error;
    }
  }

  SupplyShop _changed(SupplyShop s, Map<String, dynamic> changes) => SupplyShop.fromJson({...s.toJson(), ...changes})!;

  SupplyShop _withAccount(SupplyShop s) {
    var balance = s.openingPaise;
    for (final e in entries[s.linkId] ?? const <SupplyEntry>[]) {
      if (e.counts) balance += e.payment ? -e.amountPaise : e.amountPaise;
    }
    return _changed(s, {
      'balancePaise': balance,
      'toConfirm': (entries[s.linkId] ?? const [])
          .where((e) => !e.deleted && !e.bySupplier && e.confirm == Confirm.waiting)
          .length,
      'openOrders': all.where((o) => o.linkId == s.linkId && o.status.open).length,
    });
  }

  @override
  Future<SupplyHome> home() async {
    _check();
    final list = shops.map(_withAccount).toList();
    return SupplyHome(
      requests: requests,
      shops: list,
      totalDuePaise: list.fold(0, (sum, s) => sum + (s.balancePaise > 0 ? s.balancePaise : 0)),
    );
  }

  @override
  Future<SupplyShopDetail> shop(int linkId) async {
    _check();
    return SupplyShopDetail(
      shop: _withAccount(shops.firstWhere((s) => s.linkId == linkId)),
      entries: entries[linkId] ?? const [],
      orders: all.where((o) => o.linkId == linkId).toList(),
    );
  }

  @override
  Future<List<SupplyOrder>> orders() async {
    _check();
    return all;
  }

  @override
  Future<void> acceptShop(int linkId, int balancePaise) async {
    _check('accept shop $linkId $balancePaise');
    final r = requests.firstWhere((r) => r.linkId == linkId);
    requests = [for (final x in requests) if (x != r) x];
    shops = [...shops, _changed(r, {'openingPaise': balancePaise, 'askedAt': null})];
  }

  @override
  Future<void> declineShop(int linkId, String reason) async {
    _check('decline shop $linkId $reason');
    requests = [for (final x in requests) if (x.linkId != linkId) x];
  }

  @override
  Future<void> endShop(int linkId) async {
    _check('end shop $linkId');
    shops = [for (final s in shops) s.linkId == linkId ? _changed(s, {'connected': false}) : s];
  }

  void _answer(int id, Confirm confirm, [String? reason]) {
    entries = {
      for (final MapEntry(:key, :value) in entries.entries)
        key: [
          for (final e in value)
            e.id == id ? SupplyEntry.fromJson({...e.toJson(), 'confirm': confirm.code, 'disputeReason': reason})! : e,
        ],
    };
  }

  @override
  Future<void> addEntry(int linkId, SupplierEntryDraft d) async {
    _check('write $linkId ${d.kind.code} ${d.amountPaise} ${d.method?.code} ${[for (final l in d.lines) '${l.name} ${l.qtyMilli}'].join(',')}');
    entries = {
      ...entries,
      linkId: [
        ...?entries[linkId],
        SupplyEntry(
          id: _next++,
          kind: d.kind,
          amountPaise: d.amountPaise,
          entryAt: d.entryAt,
          note: d.note,
          method: d.method,
          bySupplier: true,
        ),
      ],
    };
  }

  @override
  Future<void> deleteEntry(int entryId, String reason) async {
    _check('delete $entryId $reason');
    entries = {
      for (final MapEntry(:key, :value) in entries.entries)
        key: [
          for (final e in value)
            e.id == entryId
                ? SupplyEntry.fromJson({...e.toJson(), 'deletedAt': '2026-11-24T10:00:00Z', 'deleteReason': reason})!
                : e,
        ],
    };
  }

  @override
  Future<void> confirmEntry(int entryId) async {
    _check('confirm $entryId');
    _answer(entryId, Confirm.confirmed);
  }

  @override
  Future<void> disputeEntry(int entryId, String reason) async {
    _check('dispute $entryId $reason');
    _answer(entryId, Confirm.disputed, reason);
  }

  void _order(int id, Map<String, dynamic> changes) =>
      all = [for (final o in all) o.id == id ? SupplyOrder.fromJson({...o.toJson(), ...changes})! : o];

  @override
  Future<void> acceptOrder(int orderId, List<LineAnswer> lines, {required int totalPaise, String note = ''}) async {
    _check('accept order $orderId $totalPaise');
    final order = all.firstWhere((o) => o.id == orderId);
    _order(orderId, {
      'status': OrderStatus.accepted.code,
      'totalPaise': totalPaise,
      'answerNote': note.isEmpty ? null : note,
      'lines': [
        for (final l in order.lines)
          {
            ...l.toJson(),
            'available': lines.firstWhere((a) => a.id == l.id).available,
            'costPaise': lines.firstWhere((a) => a.id == l.id).costPaise,
          },
      ],
    });
  }

  @override
  Future<void> rejectOrder(int orderId, String reason) async {
    _check('reject order $orderId $reason');
    _order(orderId, {'status': OrderStatus.rejected.code, 'answerNote': reason});
  }

  @override
  Future<List<Product>> products() async {
    _check();
    return sells;
  }

  @override
  Future<void> addProducts(List<ProductDraft> drafts) async {
    _check('add ${drafts.map((d) => '${d.name} ${d.unit.code} ${d.pricePaise}').join(', ')}');
    sells = [
      ...sells,
      for (final d in drafts)
        Product(
          id: _next++,
          name: d.name,
          unit: d.unit,
          catalogCode: d.catalogCode,
          pricePaise: d.pricePaise,
          available: d.available,
        ),
    ];
  }

  @override
  Future<void> changeProduct(int id, {required String name, int? pricePaise, required bool available}) async {
    _check('change $id $name $pricePaise $available');
    sells = [
      for (final p in sells)
        p.id == id
            ? Product.fromJson({...p.toJson(), 'name': name, 'pricePaise': pricePaise, 'available': available})!
            : p,
    ];
  }

  @override
  Future<void> removeProduct(int id) async {
    _check('remove $id');
    sells = [for (final p in sells) if (p.id != id) p];
  }

  final Map<int, List<ProductMove>> moves = {};

  @override
  Future<ProductStock> productStock(int id) async {
    _check();
    return ProductStock(product: sells.firstWhere((p) => p.id == id), moves: [...?moves[id]?.reversed]);
  }

  void _product(int id, Map<String, dynamic> changes) =>
      sells = [for (final p in sells) p.id == id ? Product.fromJson({...p.toJson(), ...changes})! : p];

  @override
  Future<void> addMove(int id, CountKind kind, int qtyMilli, {String note = '', required String clientRef}) async {
    _check('move $id ${kind.code} $qtyMilli $note');
    final p = sells.firstWhere((p) => p.id == id);
    final m = ProductMove(
      id: _next++,
      kind: switch (kind) {
        CountKind.stockIn => MoveKind.stockIn,
        CountKind.out => MoveKind.out,
        CountKind.count => MoveKind.adjust,
      },
      qtyMilli: kind == CountKind.count ? qtyMilli - p.quantityMilli : qtyMilli,
      at: DateTime(2026, 11, 24),
      note: note,
    );
    moves.putIfAbsent(id, () => []).add(m);
    final left = p.quantityMilli + m.effect;
    _product(id, {'counted': true, 'quantityMilli': left, 'low': left <= (p.alertMilli ?? 0)});
  }

  @override
  Future<void> setCounting(int id, {required bool counted, int? alertMilli}) async {
    _check('counting $id $counted $alertMilli');
    final left = sells.firstWhere((p) => p.id == id).quantityMilli;
    _product(id, {'counted': counted, 'alertMilli': alertMilli, 'low': counted && left <= (alertMilli ?? 0)});
  }

  SupplyReport reportAnswer = const SupplyReport();

  @override
  Future<SupplyReport> report(DateTime start, DateTime end) async {
    _check('report ${dayText(start)} ${dayText(end)}');
    return reportAnswer;
  }

  String? upiId;
  String? upiName;

  @override
  Future<SupplyPayments> payments() async {
    _check();
    final all = [
      for (final s in shops)
        for (final e in entries[s.linkId] ?? const <SupplyEntry>[])
          if (e.payment && !e.deleted)
            SupplyPayment(entry: e, linkId: s.linkId, shopName: s.name, connected: s.connected),
    ];
    return SupplyPayments(
      upiId: upiId,
      upiName: upiName,
      toGetPaise: (await home()).totalDuePaise,
      receivedMonthPaise: all.where((p) => p.entry.counts).fold(0, (sum, p) => sum + p.entry.amountPaise),
      payments: all,
    );
  }

  @override
  Future<void> saveUpi(String id, String name) async {
    _check('upi $id $name');
    upiId = id.isEmpty ? null : id;
    upiName = id.isEmpty ? null : name;
  }

  @override
  Future<void> dispatchOrder(int orderId) async {
    _check('dispatch $orderId');
    _order(orderId, {'status': OrderStatus.dispatched.code});
  }
}
