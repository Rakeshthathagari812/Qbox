import '../udhaar/udhaar_models.dart' show newClientRef;

/// Quantities are whole thousandths of the item's unit ("milli"): 1.5 kg = 1500,
/// 3 pieces = 3000. So loose goods never drift by rounding.
const milli = 1000;

enum UnitGroup { weight, volume, count, other }

enum StockUnit {
  kg('KG', 'kg', 'Kilogram', UnitGroup.weight, 1000),
  g('G', 'g', 'Gram', UnitGroup.weight, 1),
  l('L', 'L', 'Litre', UnitGroup.volume, 1000),
  ml('ML', 'ml', 'Millilitre', UnitGroup.volume, 1),
  piece('PIECE', 'pcs', 'Piece', UnitGroup.count, 1),
  dozen('DOZEN', 'dozen', 'Dozen', UnitGroup.count, 12),
  packet('PACKET', 'pkt', 'Packet', UnitGroup.other, 1),
  box('BOX', 'box', 'Box', UnitGroup.other, 1),
  bag('BAG', 'bag', 'Bag', UnitGroup.other, 1);

  const StockUnit(this.code, this.short, this.label, this.group, this.size);

  final String code;

  /// "kg", "pcs": shown after a number.
  final String short;
  final String label;
  final UnitGroup group;

  /// Size in the group's smallest unit (1 kg = 1000 g, 1 dozen = 12 pieces).
  final int size;

  static StockUnit? fromCode(Object? code) {
    for (final u in values) {
      if (u.code == code) return u;
    }
    return null;
  }

  /// [qtyMilli] said in [from] (e.g. 500 g) written in this unit (0.5 kg).
  /// Null when the two cannot be converted (kg and packets).
  int? convert(int qtyMilli, StockUnit from) {
    if (from == this) return qtyMilli;
    if (from.group != group || group == UnitGroup.other) return null;
    return (qtyMilli * from.size / size).round();
  }
}

/// 1500 kg-milli -> "1.5 kg"; 3000 pieces -> "3 pcs"; -500 -> "-0.5 kg".
String formatQty(int qtyMilli, StockUnit unit) => '${qtyNumber(qtyMilli)} ${unit.short}';

/// 1500 -> "1.5", 3000 -> "3", 1250 -> "1.25".
String qtyNumber(int qtyMilli) {
  final negative = qtyMilli < 0;
  final abs = qtyMilli.abs();
  final whole = abs ~/ milli;
  final rest = abs % milli;
  var text = '$whole';
  if (rest != 0) {
    text = '$whole.${rest.toString().padLeft(3, '0').replaceFirst(RegExp(r'0+$'), '')}';
  }
  return negative ? '-$text' : text;
}

/// "1.5" -> 1500, "12" -> 12000. Null if not a number with at most 3 decimals.
int? parseQty(String text) {
  final clean = text.replaceAll(RegExp(r'[,\s]'), '');
  final match = RegExp(r'^([0-9]{1,7})(?:\.([0-9]{0,3}))?$').firstMatch(clean);
  if (match == null) return null;
  return int.parse(match[1]!) * milli + int.parse((match[2] ?? '').padRight(3, '0'));
}

enum MoveKind {
  stockIn('IN', 'Stock in'),
  out('OUT', 'Sold / used'),
  adjust('ADJUST', 'Count corrected');

  const MoveKind(this.code, this.label);

  final String code;
  final String label;

  static MoveKind? fromCode(Object? code) {
    for (final k in values) {
      if (k.code == code) return k;
    }
    return null;
  }
}

class StockItem {
  const StockItem({
    required this.id,
    required this.name,
    required this.unit,
    this.catalogCode,
    this.quantityMilli = 0,
    this.costPaise,
    this.pricePaise,
    this.alertMilli,
    this.lastMoveAt,
  });

  final int id;
  final String name;
  final StockUnit unit;
  final String? catalogCode;
  final int quantityMilli;
  final int? costPaise;
  final int? pricePaise;

  /// "Running low" at or below this.
  final int? alertMilli;
  final DateTime? lastMoveAt;

  bool get isLow => alertMilli != null && quantityMilli <= alertMilli!;

  /// Quantity x buying price; null without a buying price.
  int? get valuePaise => costPaise == null ? null : ((quantityMilli < 0 ? 0 : quantityMilli) * costPaise! / milli).round();

  StockItem copyWith({int? quantityMilli, DateTime? lastMoveAt}) => StockItem(
    id: id,
    name: name,
    unit: unit,
    catalogCode: catalogCode,
    quantityMilli: quantityMilli ?? this.quantityMilli,
    costPaise: costPaise,
    pricePaise: pricePaise,
    alertMilli: alertMilli,
    lastMoveAt: lastMoveAt ?? this.lastMoveAt,
  );

  static StockItem? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final id = json['id'];
    final name = json['name'];
    final unit = StockUnit.fromCode(json['unit']);
    if (id is! int || name is! String || unit == null) return null;
    return StockItem(
      id: id,
      name: name,
      unit: unit,
      catalogCode: json['catalogCode'] as String?,
      quantityMilli: _int(json['quantityMilli']) ?? 0,
      costPaise: _int(json['costPaise']),
      pricePaise: _int(json['pricePaise']),
      alertMilli: _int(json['alertMilli']),
      lastMoveAt: _time(json['lastMoveAt']),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'unit': unit.code,
    'catalogCode': catalogCode,
    'quantityMilli': quantityMilli,
    'costPaise': costPaise,
    'pricePaise': pricePaise,
    'alertMilli': alertMilli,
    'lastMoveAt': lastMoveAt?.toUtc().toIso8601String(),
  };
}

/// An item the shop added itself before and removed: offered again in "Your items".
class PastItem {
  const PastItem({required this.name, required this.unit, this.catalogCode});

  final String name;
  final StockUnit unit;
  final String? catalogCode;

  static PastItem? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final name = json['name'];
    final unit = StockUnit.fromCode(json['unit']);
    if (name is! String || unit == null) return null;
    return PastItem(name: name, unit: unit, catalogCode: json['catalogCode'] as String?);
  }

  Map<String, dynamic> toJson() => {'name': name, 'unit': unit.code, 'catalogCode': catalogCode};
}

/// Every item in the shop's stock.
class StockBook {
  const StockBook(this.items, {this.pastItems = const []});

  final List<StockItem> items;

  /// Removed items (not in stock now), newest first.
  final List<PastItem> pastItems;

  int get totalValuePaise => items.fold(0, (sum, i) => sum + (i.valuePaise ?? 0));

  int get lowCount => items.where((i) => i.isLow).length;

  static StockBook? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final list = json['items'];
    if (list is! List) return null;
    final past = json['pastItems'];
    return StockBook(
      list.map(StockItem.fromJson).whereType<StockItem>().toList(),
      pastItems: past is List ? past.map(PastItem.fromJson).whereType<PastItem>().toList() : const [],
    );
  }

  Map<String, dynamic> toJson() => {
    'items': [for (final i in items) i.toJson()],
    'pastItems': [for (final p in pastItems) p.toJson()],
  };
}

/// A new item the shopkeeper fills in.
class ItemDraft {
  ItemDraft({
    required this.name,
    required this.unit,
    this.catalogCode,
    this.openingMilli = 0,
    this.costPaise,
    this.pricePaise,
    this.alertMilli,
    String? clientRef,
  }) : clientRef = clientRef ?? newClientRef();

  final String name;
  final StockUnit unit;
  final String? catalogCode;
  final int openingMilli;
  final int? costPaise;
  final int? pricePaise;
  final int? alertMilli;
  final String clientRef;

  Map<String, dynamic> toJson() => {
    'name': name.trim(),
    'unit': unit.code,
    'catalogCode': catalogCode,
    'openingMilli': openingMilli,
    'costPaise': costPaise,
    'pricePaise': pricePaise,
    'alertMilli': alertMilli,
    'clientRef': clientRef,
  };
}

/// Stock in / out / corrected, as filled in. [clientRef] is made on the phone,
/// so sending it twice (after being offline) keeps one.
class MoveDraft {
  MoveDraft({
    required this.kind,
    required this.qtyMilli,
    required this.moveAt,
    this.note = '',
    String? clientRef,
  }) : clientRef = clientRef ?? newClientRef();

  final MoveKind kind;

  /// In and out: positive. Correction: + or - (the change).
  final int qtyMilli;
  final DateTime moveAt;
  final String note;
  final String clientRef;

  Map<String, dynamic> toJson() => {
    'kind': kind.code,
    'qtyMilli': qtyMilli,
    'note': note.trim().isEmpty ? null : note.trim(),
    'moveAt': moveAt.toUtc().toIso8601String(),
    'clientRef': clientRef,
  };

  static MoveDraft? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final kind = MoveKind.fromCode(json['kind']);
    final qty = _int(json['qtyMilli']);
    final at = _time(json['moveAt']);
    final ref = json['clientRef'];
    if (kind == null || qty == null || at == null || ref is! String) return null;
    return MoveDraft(kind: kind, qtyMilli: qty, moveAt: at, note: json['note'] as String? ?? '', clientRef: ref);
  }
}

/// One line of an item's history.
class StockMove {
  const StockMove({
    required this.id,
    required this.kind,
    required this.qtyMilli,
    required this.moveAt,
    required this.clientRef,
    this.note,
    this.pending = false,
  });

  /// Saved on the phone, not yet on the server ([pending]): no id yet.
  factory StockMove.pending(MoveDraft d) => StockMove(
    id: null,
    kind: d.kind,
    qtyMilli: d.qtyMilli,
    moveAt: d.moveAt,
    clientRef: d.clientRef,
    note: d.note.trim().isEmpty ? null : d.note.trim(),
    pending: true,
  );

  final int? id;
  final MoveKind kind;
  final int qtyMilli;
  final DateTime moveAt;
  final String clientRef;
  final String? note;
  final bool pending;

  /// How this move changes the quantity.
  int get effect => kind == MoveKind.out ? -qtyMilli : qtyMilli;

  static StockMove? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final kind = MoveKind.fromCode(json['kind']);
    final qty = _int(json['qtyMilli']);
    final at = _time(json['moveAt']);
    if (kind == null || qty == null || at == null) return null;
    return StockMove(
      id: _int(json['id']),
      kind: kind,
      qtyMilli: qty,
      moveAt: at,
      clientRef: json['clientRef'] as String? ?? '',
      note: json['note'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind.code,
    'qtyMilli': qtyMilli,
    'moveAt': moveAt.toUtc().toIso8601String(),
    'clientRef': clientRef,
    'note': note,
  };
}

/// One item with its history (newest first).
class ItemDetail {
  const ItemDetail({required this.item, required this.moves});

  final StockItem item;
  final List<StockMove> moves;

  static ItemDetail? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final item = StockItem.fromJson(json['item']);
    final moves = json['moves'];
    if (item == null || moves is! List) return null;
    return ItemDetail(item: item, moves: moves.map(StockMove.fromJson).whereType<StockMove>().toList());
  }

  Map<String, dynamic> toJson() => {
    'item': item.toJson(),
    'moves': [for (final m in moves) m.toJson()],
  };
}

int? _int(Object? v) => v is int ? v : (v is num ? v.toInt() : null);

DateTime? _time(Object? v) => v is String ? DateTime.tryParse(v)?.toLocal() : null;
