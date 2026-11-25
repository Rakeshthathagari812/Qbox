import '../stock/stock_models.dart';
import '../suppliers/supplier_models.dart';
import '../udhaar/udhaar_models.dart' show newClientRef;

/// The supplier's side of a shop's supplier account.

class SupplyShop {
  const SupplyShop({
    required this.linkId,
    required this.name,
    this.category,
    this.address,
    this.phone,
    this.photo,
    this.connected = true,
    this.connectedAt,
    this.endedAt,
    this.openingPaise = 0,
    this.balancePaise = 0,
    this.lastEntryAt,
    this.toConfirm = 0,
    this.openOrders = 0,
    this.askedAt,
  });

  final int linkId;
  final String name;
  final String? category;
  final String? address;
  final String? phone;
  final String? photo;

  /// False = disconnected: the account stays readable.
  final bool connected;
  final DateTime? connectedAt;
  final DateTime? endedAt;

  /// Agreed when connecting.
  final int openingPaise;

  /// Positive = the shop owes this supplier. For a question: what it says it owes.
  final int balancePaise;
  final DateTime? lastEntryAt;
  final int toConfirm;
  final int openOrders;

  /// Set for a shop that is asking to connect.
  final DateTime? askedAt;

  bool matches(String search) {
    final q = search.trim().toLowerCase();
    return q.isEmpty || name.toLowerCase().contains(q) || (phone ?? '').contains(q);
  }

  static SupplyShop? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final id = json['linkId'];
    final name = json['shopName'];
    if (id is! int || name is! String) return null;
    return SupplyShop(
      linkId: id,
      name: name,
      category: json['shopCategory'] as String?,
      address: json['shopAddress'] as String?,
      phone: json['shopPhone'] as String?,
      photo: json['shopPhoto'] as String?,
      connected: json['connected'] != false,
      connectedAt: _time(json['connectedAt']),
      endedAt: _time(json['endedAt']),
      openingPaise: _int(json['openingPaise']),
      balancePaise: _int(json['balancePaise']),
      lastEntryAt: _time(json['lastEntryAt']),
      toConfirm: _int(json['toConfirm']),
      openOrders: _int(json['openOrders']),
      askedAt: _time(json['askedAt']),
    );
  }

  Map<String, dynamic> toJson() => {
    'linkId': linkId,
    'shopName': name,
    'shopCategory': category,
    'shopAddress': address,
    'shopPhone': phone,
    'shopPhoto': photo,
    'connected': connected,
    'connectedAt': connectedAt?.toUtc().toIso8601String(),
    'endedAt': endedAt?.toUtc().toIso8601String(),
    'openingPaise': openingPaise,
    'balancePaise': balancePaise,
    'lastEntryAt': lastEntryAt?.toUtc().toIso8601String(),
    'toConfirm': toConfirm,
    'openOrders': openOrders,
    'askedAt': askedAt?.toUtc().toIso8601String(),
  };
}

class SupplyHome {
  const SupplyHome({this.requests = const [], this.shops = const [], this.totalDuePaise = 0});

  final List<SupplyShop> requests;
  final List<SupplyShop> shops;
  final int totalDuePaise;

  static SupplyHome? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final requests = json['requests'];
    final shops = json['shops'];
    if (requests is! List || shops is! List) return null;
    return SupplyHome(
      requests: requests.map(SupplyShop.fromJson).whereType<SupplyShop>().toList(),
      shops: shops.map(SupplyShop.fromJson).whereType<SupplyShop>().toList(),
      totalDuePaise: _int(json['totalDuePaise']),
    );
  }

  Map<String, dynamic> toJson() => {
    'requests': [for (final r in requests) r.toJson()],
    'shops': [for (final s in shops) s.toJson()],
    'totalDuePaise': totalDuePaise,
  };
}

class SupplyLine {
  const SupplyLine({
    required this.id,
    required this.name,
    required this.unit,
    required this.qtyMilli,
    this.costPaise,
    this.available = true,
    this.haveMilli,
  });

  final int id;
  final String name;
  final StockUnit unit;
  final int qtyMilli;

  /// What the supplier has of it, in an order to answer (if they count it).
  final int? haveMilli;

  /// Price per unit.
  final int? costPaise;
  final bool available;

  String get qty => formatQty(qtyMilli, unit);

  static SupplyLine? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final id = json['id'];
    final name = json['name'];
    final unit = StockUnit.fromCode(json['unit']);
    final qty = json['qtyMilli'];
    if (id is! int || name is! String || unit == null || qty is! int) return null;
    return SupplyLine(
      id: id,
      name: name,
      unit: unit,
      qtyMilli: qty,
      costPaise: json['costPaise'] as int?,
      available: json['available'] != false,
      haveMilli: json['haveMilli'] as int?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'unit': unit.code,
    'qtyMilli': qtyMilli,
    'costPaise': costPaise,
    'available': available,
    'haveMilli': haveMilli,
  };
}

List<SupplyLine> _lines(Object? json) =>
    json is List ? json.map(SupplyLine.fromJson).whereType<SupplyLine>().toList() : const [];

String supplyLinesText(List<SupplyLine> lines) => lines.map((l) => '${l.name} ${l.qty}').join(', ');

class SupplyEntry {
  const SupplyEntry({
    required this.id,
    required this.kind,
    required this.amountPaise,
    required this.entryAt,
    this.note,
    this.dueDate,
    this.method,
    this.lines = const [],
    this.confirm = Confirm.waiting,
    this.disputeReason,
    this.deletedAt,
    this.deleteReason,
    this.bySupplier = false,
  });

  final int id;
  final SupplierEntryKind kind;
  final int amountPaise;
  final DateTime entryAt;
  final String? note;
  final DateTime? dueDate;
  final PayMethod? method;
  final List<SupplyLine> lines;
  final Confirm confirm;
  final String? disputeReason;
  final DateTime? deletedAt;
  final String? deleteReason;

  /// The supplier wrote it: the shop answers.
  final bool bySupplier;

  bool get payment => kind == SupplierEntryKind.payment;
  bool get deleted => deletedAt != null;

  /// Counted in the balance: at once when written against oneself, otherwise
  /// when the other side agrees.
  bool get counts => !deleted && (payment == bySupplier || confirm == Confirm.confirmed);

  static SupplyEntry? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final id = json['id'];
    final kind = SupplierEntryKind.fromCode(json['kind']);
    final amount = json['amountPaise'];
    final at = _time(json['entryAt']);
    if (id is! int || kind == null || amount is! int || at == null) return null;
    return SupplyEntry(
      id: id,
      kind: kind,
      amountPaise: amount,
      entryAt: at,
      note: json['note'] as String?,
      dueDate: _day(json['dueDate']),
      method: PayMethod.fromCode(json['method']),
      lines: _lines(json['lines']),
      confirm: Confirm.fromCode(json['confirm']) ?? Confirm.waiting,
      disputeReason: json['disputeReason'] as String?,
      deletedAt: _time(json['deletedAt']),
      deleteReason: json['deleteReason'] as String?,
      bySupplier: json['bySupplier'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind.code,
    'amountPaise': amountPaise,
    'entryAt': entryAt.toUtc().toIso8601String(),
    'note': note,
    'dueDate': dueDate == null ? null : dayText(dueDate!),
    'method': method?.code,
    'lines': [for (final l in lines) l.toJson()],
    'confirm': confirm.code,
    'disputeReason': disputeReason,
    'deletedAt': deletedAt?.toUtc().toIso8601String(),
    'deleteReason': deleteReason,
    'bySupplier': bySupplier,
  };
}

class SupplyOrder {
  const SupplyOrder({
    required this.id,
    required this.linkId,
    required this.shopName,
    required this.status,
    required this.lines,
    required this.createdAt,
    this.shopPhone,
    this.note,
    this.totalPaise,
    this.answerNote,
    this.dispatchedAt,
    this.receivedAt,
    this.connected = true,
    this.payPlan,
    this.payBy,
    this.paidPaise = 0,
    this.payingPaise = 0,
  });

  final int id;
  final int linkId;
  final String shopName;
  final String? shopPhone;
  final OrderStatus status;
  final String? note;
  final List<SupplyLine> lines;

  /// The supplier's bill.
  final int? totalPaise;
  final String? answerNote;
  final DateTime createdAt;
  final DateTime? dispatchedAt;
  final DateTime? receivedAt;

  /// Still connected with the shop: it can be answered.
  final bool connected;

  /// How the shop said it will pay.
  final PayPlan? payPlan;
  final DateTime? payBy;

  /// Paid for this order: confirmed, and to be confirmed.
  final int paidPaise;
  final int payingPaise;

  static SupplyOrder? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final id = json['id'];
    final link = json['linkId'];
    final name = json['shopName'];
    final at = _time(json['createdAt']);
    if (id is! int || link is! int || name is! String || at == null) return null;
    return SupplyOrder(
      id: id,
      linkId: link,
      shopName: name,
      shopPhone: json['shopPhone'] as String?,
      status: OrderStatus.fromCode(json['status']),
      note: json['note'] as String?,
      lines: _lines(json['lines']),
      totalPaise: json['totalPaise'] as int?,
      answerNote: json['answerNote'] as String?,
      createdAt: at,
      dispatchedAt: _time(json['dispatchedAt']),
      receivedAt: _time(json['receivedAt']),
      connected: json['connected'] != false,
      payPlan: PayPlan.fromCode(json['payPlan']),
      payBy: _day(json['payBy']),
      paidPaise: _int(json['paidPaise']),
      payingPaise: _int(json['payingPaise']),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'linkId': linkId,
    'shopName': shopName,
    'shopPhone': shopPhone,
    'status': status.code,
    'note': note,
    'lines': [for (final l in lines) l.toJson()],
    'totalPaise': totalPaise,
    'answerNote': answerNote,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'dispatchedAt': dispatchedAt?.toUtc().toIso8601String(),
    'receivedAt': receivedAt?.toUtc().toIso8601String(),
    'connected': connected,
    'payPlan': payPlan?.code,
    'payBy': payBy == null ? null : dayText(payBy!),
    'paidPaise': paidPaise,
    'payingPaise': payingPaise,
  };
}

/// A payment from one of the shops.
class SupplyPayment {
  const SupplyPayment({required this.entry, required this.linkId, required this.shopName, this.connected = true});

  final SupplyEntry entry;
  final int linkId;
  final String shopName;

  /// It can still be answered.
  final bool connected;

  static SupplyPayment? fromJson(Object? json) {
    final entry = SupplyEntry.fromJson(json);
    if (entry == null || json is! Map<String, dynamic>) return null;
    final link = json['linkId'];
    final name = json['shopName'];
    if (link is! int || name is! String) return null;
    return SupplyPayment(entry: entry, linkId: link, shopName: name, connected: json['connected'] != false);
  }

  Map<String, dynamic> toJson() => {
    ...entry.toJson(),
    'linkId': linkId,
    'shopName': shopName,
    'connected': connected,
  };
}

/// Everything shops paid this supplier, and their UPI ID.
class SupplyPayments {
  const SupplyPayments({
    this.upiId,
    this.upiName,
    this.toGetPaise = 0,
    this.receivedMonthPaise = 0,
    this.payments = const [],
  });

  final String? upiId;
  final String? upiName;
  final int toGetPaise;

  /// Confirmed, this month.
  final int receivedMonthPaise;
  final List<SupplyPayment> payments;

  static SupplyPayments? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final list = json['payments'];
    if (list is! List) return null;
    return SupplyPayments(
      upiId: json['upiId'] as String?,
      upiName: json['upiName'] as String?,
      toGetPaise: _int(json['toGetPaise']),
      receivedMonthPaise: _int(json['receivedMonthPaise']),
      payments: list.map(SupplyPayment.fromJson).whereType<SupplyPayment>().toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    'upiId': upiId,
    'upiName': upiName,
    'toGetPaise': toGetPaise,
    'receivedMonthPaise': receivedMonthPaise,
    'payments': [for (final p in payments) p.toJson()],
  };
}

/// The supplier's own words for an order's state.
String supplyStatus(OrderStatus status) => switch (status) {
  OrderStatus.sent => 'New',
  OrderStatus.accepted => 'Accepted',
  OrderStatus.dispatched => 'On the way',
  OrderStatus.received => 'Received by the shop',
  OrderStatus.rejected => 'Rejected',
  OrderStatus.cancelled => 'Cancelled by the shop',
};

class SupplyShopDetail {
  const SupplyShopDetail({required this.shop, this.entries = const [], this.orders = const []});

  final SupplyShop shop;
  final List<SupplyEntry> entries;
  final List<SupplyOrder> orders;

  static SupplyShopDetail? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final shop = SupplyShop.fromJson(json['shop']);
    final entries = json['entries'];
    final orders = json['orders'];
    if (shop == null || entries is! List || orders is! List) return null;
    return SupplyShopDetail(
      shop: shop,
      entries: entries.map(SupplyEntry.fromJson).whereType<SupplyEntry>().toList(),
      orders: orders.map(SupplyOrder.fromJson).whereType<SupplyOrder>().toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    'shop': shop.toJson(),
    'entries': [for (final e in entries) e.toJson()],
    'orders': [for (final o in orders) o.toJson()],
  };
}

/// The supplier's answer about one line of an order.
class LineAnswer {
  const LineAnswer({required this.id, required this.available, this.costPaise});

  final int id;
  final bool available;
  final int? costPaise;

  Map<String, dynamic> toJson() => {'id': id, 'available': available, 'costPaise': costPaise};
}

/// Something the supplier sells.
class Product {
  const Product({
    required this.id,
    required this.name,
    required this.unit,
    this.catalogCode,
    this.pricePaise,
    this.available = true,
    this.counted = false,
    this.quantityMilli = 0,
    this.alertMilli,
    this.low = false,
  });

  final int id;
  final String name;
  final StockUnit unit;
  final String? catalogCode;

  /// Per unit.
  final int? pricePaise;
  final bool available;

  /// The supplier counts it; at 0, shops see "not available".
  final bool counted;
  final int quantityMilli;
  final int? alertMilli;
  final bool low;

  static Product? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final id = json['id'];
    final name = json['name'];
    final unit = StockUnit.fromCode(json['unit']);
    if (id is! int || name is! String || unit == null) return null;
    return Product(
      id: id,
      name: name,
      unit: unit,
      catalogCode: json['catalogCode'] as String?,
      pricePaise: json['pricePaise'] as int?,
      available: json['available'] != false,
      counted: json['counted'] == true,
      quantityMilli: _int(json['quantityMilli']),
      alertMilli: json['alertMilli'] as int?,
      low: json['low'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'unit': unit.code,
    'catalogCode': catalogCode,
    'pricePaise': pricePaise,
    'available': available,
    'counted': counted,
    'quantityMilli': quantityMilli,
    'alertMilli': alertMilli,
    'low': low,
  };
}

/// Stock in, out, or "I counted: there is this much".
enum CountKind {
  stockIn('IN', 'Stock in'),
  out('OUT', 'Stock out'),
  count('COUNT', 'Count');

  const CountKind(this.code, this.label);

  final String code;
  final String label;
}

/// One change of the supplier's own stock.
class ProductMove {
  const ProductMove({required this.id, required this.kind, required this.qtyMilli, required this.at, this.note});

  final int id;
  final MoveKind kind;

  /// Corrections: the change, + or -.
  final int qtyMilli;
  final DateTime at;
  final String? note;

  int get effect => kind == MoveKind.out ? -qtyMilli : qtyMilli;

  static ProductMove? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final id = json['id'];
    final kind = MoveKind.fromCode(json['kind']);
    final qty = json['qtyMilli'];
    final at = _time(json['moveAt']);
    if (id is! int || kind == null || qty is! int || at == null) return null;
    return ProductMove(id: id, kind: kind, qtyMilli: qty, at: at, note: json['note'] as String?);
  }
}

class ProductStock {
  const ProductStock({required this.product, this.moves = const []});

  final Product product;
  final List<ProductMove> moves;

  static ProductStock? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final product = Product.fromJson(json['product']);
    final moves = json['moves'];
    if (product == null || moves is! List) return null;
    return ProductStock(product: product, moves: moves.map(ProductMove.fromJson).whereType<ProductMove>().toList());
  }
}

class ReportShop {
  const ReportShop({
    required this.name,
    this.givenPaise = 0,
    this.receivedPaise = 0,
    this.toGetPaise = 0,
    this.connected = true,
  });

  final String name;
  final int givenPaise;
  final int receivedPaise;

  /// Now.
  final int toGetPaise;
  final bool connected;

  static ReportShop? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final name = json['shopName'];
    if (name is! String) return null;
    return ReportShop(
      name: name,
      givenPaise: _int(json['givenPaise']),
      receivedPaise: _int(json['receivedPaise']),
      toGetPaise: _int(json['toGetPaise']),
      connected: json['connected'] != false,
    );
  }
}

class ReportProduct {
  const ReportProduct({required this.name, required this.unit, required this.qtyMilli, this.amountPaise});

  final String name;
  final StockUnit unit;
  final int qtyMilli;

  /// Null = no prices written.
  final int? amountPaise;

  static ReportProduct? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final name = json['name'];
    final unit = StockUnit.fromCode(json['unit']);
    final qty = json['qtyMilli'];
    if (name is! String || unit == null || qty is! int) return null;
    return ReportProduct(name: name, unit: unit, qtyMilli: qty, amountPaise: json['amountPaise'] as int?);
  }
}

/// What was given and got between two days.
class SupplyReport {
  const SupplyReport({
    this.givenPaise = 0,
    this.receivedPaise = 0,
    this.waitingPaise = 0,
    this.toGetPaise = 0,
    this.orders = const {},
    this.shops = const [],
    this.products = const [],
  });

  final int givenPaise;
  final int receivedPaise;

  /// Payments not answered yet.
  final int waitingPaise;

  /// Now.
  final int toGetPaise;
  final Map<OrderStatus, int> orders;
  final List<ReportShop> shops;
  final List<ReportProduct> products;

  int get orderCount => orders.values.fold(0, (a, b) => a + b);

  static SupplyReport? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final orders = json['orders'];
    final shops = json['shops'];
    final products = json['products'];
    if (orders is! Map<String, dynamic> || shops is! List || products is! List) return null;
    return SupplyReport(
      givenPaise: _int(json['givenPaise']),
      receivedPaise: _int(json['receivedPaise']),
      waitingPaise: _int(json['waitingPaise']),
      toGetPaise: _int(json['toGetPaise']),
      orders: {for (final e in orders.entries) OrderStatus.fromCode(e.key): _int(e.value)},
      shops: shops.map(ReportShop.fromJson).whereType<ReportShop>().toList(),
      products: products.map(ReportProduct.fromJson).whereType<ReportProduct>().toList(),
    );
  }
}

/// A product being added. [clientRef] is made once, so sending it again adds it once.
class ProductDraft {
  ProductDraft({
    required this.name,
    required this.unit,
    this.catalogCode,
    this.pricePaise,
    this.available = true,
    String? clientRef,
  }) : clientRef = clientRef ?? newClientRef();

  final String name;
  final StockUnit unit;
  final String? catalogCode;
  final int? pricePaise;
  final bool available;
  final String clientRef;

  Map<String, dynamic> toJson() => {
    'name': name,
    'unit': unit.code,
    'catalogCode': catalogCode,
    'pricePaise': pricePaise,
    'available': available,
    'clientRef': clientRef,
  };
}

int _int(Object? v) => v is int ? v : 0;

DateTime? _time(Object? v) => v is String ? DateTime.tryParse(v)?.toLocal() : null;

DateTime? _day(Object? v) {
  final day = v is String ? DateTime.tryParse(v) : null;
  return day == null ? null : DateTime(day.year, day.month, day.day);
}
