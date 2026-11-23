import '../stock/stock_catalog.dart';
import '../stock/stock_models.dart';
import '../translator/languages.dart';
import '../udhaar/udhaar_models.dart' show newClientRef;

enum SupplierEntryKind {
  purchase('PURCHASE', 'Purchase'),
  payment('PAYMENT', 'Payment');

  const SupplierEntryKind(this.code, this.label);

  final String code;
  final String label;

  static SupplierEntryKind? fromCode(Object? code) {
    for (final k in values) {
      if (k.code == code) return k;
    }
    return null;
  }
}

enum PayMethod {
  cash('CASH', 'Cash'),
  upi('UPI', 'UPI'),
  bank('BANK', 'Bank'),
  other('OTHER', 'Other');

  const PayMethod(this.code, this.label);

  final String code;
  final String label;

  static PayMethod? fromCode(Object? code) {
    for (final m in values) {
      if (m.code == code) return m;
    }
    return null;
  }
}

enum OrderStatus {
  sent('SENT', 'Waiting for goods'),
  received('RECEIVED', 'Received'),
  cancelled('CANCELLED', 'Cancelled');

  const OrderStatus(this.code, this.label);

  final String code;
  final String label;

  static OrderStatus fromCode(Object? code) =>
      values.firstWhere((s) => s.code == code, orElse: () => OrderStatus.sent);
}

class Supplier {
  const Supplier({
    required this.id,
    required this.name,
    this.mobile,
    this.supplies,
    this.note,
    this.balancePaise = 0,
    this.lastEntryAt,
    this.nextDue,
    this.overdue = false,
    this.openOrders = 0,
  });

  final int id;
  final String name;
  final String? mobile;
  final String? supplies;
  final String? note;

  /// Positive = the shop owes the supplier. Negative = paid in advance.
  final int balancePaise;
  final DateTime? lastEntryAt;

  /// The earliest pay-by date not yet paid off.
  final DateTime? nextDue;
  final bool overdue;
  final int openOrders;

  Supplier copyWith({int? balancePaise, DateTime? lastEntryAt}) => Supplier(
    id: id,
    name: name,
    mobile: mobile,
    supplies: supplies,
    note: note,
    balancePaise: balancePaise ?? this.balancePaise,
    lastEntryAt: lastEntryAt ?? this.lastEntryAt,
    nextDue: nextDue,
    overdue: overdue,
    openOrders: openOrders,
  );

  static Supplier? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final id = json['id'];
    final name = json['name'];
    if (id is! int || name is! String) return null;
    return Supplier(
      id: id,
      name: name,
      mobile: json['mobile'] as String?,
      supplies: json['supplies'] as String?,
      note: json['note'] as String?,
      balancePaise: _int(json['balancePaise']) ?? 0,
      lastEntryAt: _time(json['lastEntryAt']),
      nextDue: _day(json['nextDue']),
      overdue: json['overdue'] == true,
      openOrders: _int(json['openOrders']) ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'mobile': mobile,
    'supplies': supplies,
    'note': note,
    'balancePaise': balancePaise,
    'lastEntryAt': lastEntryAt?.toUtc().toIso8601String(),
    'nextDue': nextDue == null ? null : dayText(nextDue!),
    'overdue': overdue,
    'openOrders': openOrders,
  };
}

class SupplierBook {
  const SupplierBook(this.suppliers);

  final List<Supplier> suppliers;

  int get totalDuePaise => suppliers.fold(0, (s, x) => s + (x.balancePaise > 0 ? x.balancePaise : 0));

  static SupplierBook? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final list = json['suppliers'];
    if (list is! List) return null;
    return SupplierBook(list.map(Supplier.fromJson).whereType<Supplier>().toList());
  }

  Map<String, dynamic> toJson() => {
    'suppliers': [for (final s in suppliers) s.toJson()],
  };
}

/// An item bought or ordered.
class EntryLine {
  const EntryLine({required this.name, required this.unit, required this.qtyMilli, this.itemId, this.costPaise});

  final int? itemId;
  final String name;
  final StockUnit unit;
  final int qtyMilli;

  /// Buying price per unit (optional).
  final int? costPaise;

  static EntryLine? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final name = json['name'];
    final unit = StockUnit.fromCode(json['unit']);
    final qty = _int(json['qtyMilli']);
    if (name is! String || unit == null || qty == null) return null;
    return EntryLine(itemId: _int(json['itemId']), name: name, unit: unit, qtyMilli: qty, costPaise: _int(json['costPaise']));
  }

  Map<String, dynamic> toJson() => {
    'itemId': itemId,
    'name': name,
    'unit': unit.code,
    'qtyMilli': qtyMilli,
    'costPaise': costPaise,
  };

  /// What the backend needs: which stock item, how much, at what price.
  Map<String, dynamic> toInput() => {'itemId': itemId, 'qtyMilli': qtyMilli, 'costPaise': costPaise};
}

/// A purchase or payment as filled in. [clientRef] is made on the phone, so
/// sending it twice (after being offline) keeps one.
class SupplierEntryDraft {
  SupplierEntryDraft({
    required this.kind,
    required this.amountPaise,
    required this.entryAt,
    this.note = '',
    this.dueDate,
    this.method,
    this.paidNow = false,
    this.lines = const [],
    String? clientRef,
  }) : clientRef = clientRef ?? newClientRef();

  final SupplierEntryKind kind;
  final int amountPaise;
  final DateTime entryAt;
  final String note;
  final DateTime? dueDate;
  final PayMethod? method;
  final bool paidNow;
  final List<EntryLine> lines;
  final String clientRef;

  /// How this changes what the shop owes.
  int get effect => kind == SupplierEntryKind.payment ? -amountPaise : (paidNow ? 0 : amountPaise);

  Map<String, dynamic> toJson() => {
    'kind': kind.code,
    'amountPaise': amountPaise,
    'note': note.trim().isEmpty ? null : note.trim(),
    'entryAt': entryAt.toUtc().toIso8601String(),
    'dueDate': dueDate == null ? null : dayText(dueDate!),
    'method': method?.code,
    'paidNow': paidNow,
    'lines': [for (final l in lines) l.toInput()],
    'clientRef': clientRef,
  };

  /// For the phone's offline queue (keeps the line names too).
  Map<String, dynamic> toStore() => {...toJson(), 'lines': [for (final l in lines) l.toJson()]};

  static SupplierEntryDraft? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final kind = SupplierEntryKind.fromCode(json['kind']);
    final amount = _int(json['amountPaise']);
    final at = _time(json['entryAt']);
    final ref = json['clientRef'];
    final lines = json['lines'];
    if (kind == null || amount == null || at == null || ref is! String) return null;
    return SupplierEntryDraft(
      kind: kind,
      amountPaise: amount,
      entryAt: at,
      note: json['note'] as String? ?? '',
      dueDate: _day(json['dueDate']),
      method: PayMethod.fromCode(json['method']),
      paidNow: json['paidNow'] == true,
      lines: lines is List ? lines.map(EntryLine.fromJson).whereType<EntryLine>().toList() : const [],
      clientRef: ref,
    );
  }
}

class SupplierEntry {
  const SupplierEntry({
    required this.id,
    required this.kind,
    required this.amountPaise,
    required this.entryAt,
    required this.clientRef,
    this.note,
    this.dueDate,
    this.method,
    this.orderId,
    this.lines = const [],
    this.deletedAt,
    this.deleteReason,
    this.pending = false,
  });

  /// Saved on the phone and not yet sent: no id yet. A purchase paid on the
  /// spot shows as one line here (its payment is added on the server).
  factory SupplierEntry.pending(SupplierEntryDraft d) => SupplierEntry(
    id: null,
    kind: d.kind,
    amountPaise: d.amountPaise,
    entryAt: d.entryAt,
    clientRef: d.clientRef,
    note: d.note.trim().isEmpty ? (d.paidNow ? 'Paid on purchase' : null) : d.note.trim(),
    dueDate: d.dueDate,
    method: d.method,
    lines: d.lines,
    pending: true,
  );

  final int? id;
  final SupplierEntryKind kind;
  final int amountPaise;
  final DateTime entryAt;
  final String clientRef;
  final String? note;
  final DateTime? dueDate;
  final PayMethod? method;
  final int? orderId;
  final List<EntryLine> lines;
  final DateTime? deletedAt;
  final String? deleteReason;
  final bool pending;

  bool get deleted => deletedAt != null;

  static SupplierEntry? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final kind = SupplierEntryKind.fromCode(json['kind']);
    final amount = _int(json['amountPaise']);
    final at = _time(json['entryAt']);
    final lines = json['lines'];
    if (kind == null || amount == null || at == null) return null;
    return SupplierEntry(
      id: _int(json['id']),
      kind: kind,
      amountPaise: amount,
      entryAt: at,
      clientRef: json['clientRef'] as String? ?? '',
      note: json['note'] as String?,
      dueDate: _day(json['dueDate']),
      method: PayMethod.fromCode(json['method']),
      orderId: _int(json['orderId']),
      lines: lines is List ? lines.map(EntryLine.fromJson).whereType<EntryLine>().toList() : const [],
      deletedAt: _time(json['deletedAt']),
      deleteReason: json['deleteReason'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind.code,
    'amountPaise': amountPaise,
    'entryAt': entryAt.toUtc().toIso8601String(),
    'clientRef': clientRef,
    'note': note,
    'dueDate': dueDate == null ? null : dayText(dueDate!),
    'method': method?.code,
    'orderId': orderId,
    'lines': [for (final l in lines) l.toJson()],
    'deletedAt': deletedAt?.toUtc().toIso8601String(),
    'deleteReason': deleteReason,
  };
}

class SupplierOrder {
  const SupplierOrder({
    required this.id,
    required this.status,
    required this.lines,
    this.note,
    this.createdAt,
    this.receivedAt,
  });

  final int id;
  final OrderStatus status;
  final List<EntryLine> lines;
  final String? note;
  final DateTime? createdAt;
  final DateTime? receivedAt;

  bool get open => status == OrderStatus.sent;

  static SupplierOrder? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final id = json['id'];
    final lines = json['lines'];
    if (id is! int || lines is! List) return null;
    return SupplierOrder(
      id: id,
      status: OrderStatus.fromCode(json['status']),
      lines: lines.map(EntryLine.fromJson).whereType<EntryLine>().toList(),
      note: json['note'] as String?,
      createdAt: _time(json['createdAt']),
      receivedAt: _time(json['receivedAt']),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'status': status.code,
    'lines': [for (final l in lines) l.toJson()],
    'note': note,
    'createdAt': createdAt?.toUtc().toIso8601String(),
    'receivedAt': receivedAt?.toUtc().toIso8601String(),
  };
}

class SupplierDetail {
  const SupplierDetail({required this.supplier, required this.entries, required this.orders});

  final Supplier supplier;
  final List<SupplierEntry> entries;
  final List<SupplierOrder> orders;

  static SupplierDetail? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final supplier = Supplier.fromJson(json['supplier']);
    final entries = json['entries'];
    final orders = json['orders'];
    if (supplier == null || entries is! List || orders is! List) return null;
    return SupplierDetail(
      supplier: supplier,
      entries: entries.map(SupplierEntry.fromJson).whereType<SupplierEntry>().toList(),
      orders: orders.map(SupplierOrder.fromJson).whereType<SupplierOrder>().toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    'supplier': supplier.toJson(),
    'entries': [for (final e in entries) e.toJson()],
    'orders': [for (final o in orders) o.toJson()],
  };
}

/// The WhatsApp message for an order: English, with each item's name in the
/// shop's language too when it came from the ready list.
String orderMessage({
  required String shopName,
  required List<EntryLine> lines,
  required Map<int, String?> catalogCodes,
  AppLanguage language = AppLanguage.english,
  String note = '',
}) {
  final buffer = StringBuffer('Order from ${shopName.isEmpty ? 'our shop' : shopName}:\n');
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final local = language == AppLanguage.english
        ? null
        : catalogItem(catalogCodes[line.itemId])?.nameIn(language);
    final name = local == null || local == line.name ? line.name : '${line.name} ($local)';
    buffer.writeln('${i + 1}. $name - ${formatQty(line.qtyMilli, line.unit)}');
  }
  if (note.trim().isNotEmpty) buffer.writeln('Note: ${note.trim()}');
  buffer.write('Please confirm. Thank you.');
  return buffer.toString();
}

/// "30 Nov" (with the year when it is not this year).
String shortDay(DateTime day, [DateTime? now]) {
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final text = '${day.day} ${months[day.month - 1]}';
  return day.year == (now ?? DateTime.now()).year ? text : '$text ${day.year}';
}

/// "2026-11-30" for the backend.
String dayText(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';

int? _int(Object? v) => v is int ? v : (v is num ? v.toInt() : null);

DateTime? _time(Object? v) => v is String ? DateTime.tryParse(v)?.toLocal() : null;

DateTime? _day(Object? v) {
  if (v is! String) return null;
  final parsed = DateTime.tryParse(v);
  return parsed == null ? null : DateTime(parsed.year, parsed.month, parsed.day);
}
