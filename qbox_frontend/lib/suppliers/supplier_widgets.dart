import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../stock/stock_catalog.dart';
import '../stock/stock_models.dart';
import '../udhaar/udhaar_models.dart' show paiseToText, parsePaise, rupees;
import '../udhaar/udhaar_widgets.dart';
import 'supplier_models.dart';

/// One item in a purchase or order being filled in: a fixed one (from an order
/// or the supplier's products), or one typed by name.
class LineRow {
  LineRow(this.id, {this.line})
    : unit = line?.unit ?? StockUnit.kg,
      code = line?.catalogCode,
      name = TextEditingController(text: line?.name ?? ''),
      qty = TextEditingController(text: line == null || line.qtyMilli == 0 ? '' : qtyNumber(line.qtyMilli)),
      cost = TextEditingController(text: line?.costPaise == null ? '' : paiseToText(line!.costPaise!));

  final int id;

  /// Null = typed.
  final EntryLine? line;
  final TextEditingController name;
  final TextEditingController qty;
  final TextEditingController cost;
  StockUnit unit;

  /// Chosen from the ready list.
  String? code;

  bool get typed => line == null;
  String get title => line?.name ?? name.text.trim();
  bool get blank => typed && title.isEmpty && qty.text.trim().isEmpty && cost.text.trim().isEmpty;

  List<CatalogItem> get suggestions {
    final q = title.toLowerCase();
    if (!typed || q.length < 2 || code != null) return const [];
    return stockCatalog.where((c) => c.allNames.any((n) => n.toLowerCase().contains(q))).take(4).toList();
  }

  void dispose() {
    name.dispose();
    qty.dispose();
    cost.dispose();
  }
}

/// The items of a purchase or order.
class LinesController extends ChangeNotifier {
  final List<LineRow> rows = [];
  int _next = 1;

  void add([EntryLine? line]) {
    rows.add(LineRow(_next++, line: line));
    notifyListeners();
  }

  void remove(LineRow row) {
    rows.remove(row);
    row.dispose();
    notifyListeners();
  }

  /// The lines as typed (blank rows left out), or an error message.
  (List<EntryLine>, String?) read({bool withCost = false}) {
    final lines = <EntryLine>[];
    final seen = <String>{};
    for (final r in rows.where((r) => !r.blank)) {
      if (r.title.isEmpty) return (const [], 'Write the item name');
      if (!seen.add('${r.title.toLowerCase()} ${r.unit.code}')) return (const [], '${r.title} is there twice');
      final qty = parseQty(r.qty.text);
      if (qty == null || qty <= 0) return (const [], 'Enter how much ${r.title}');
      int? cost;
      if (withCost && r.cost.text.trim().isNotEmpty) {
        cost = parsePaise(r.cost.text);
        if (cost == null) return (const [], 'Check the price of ${r.title}');
      }
      lines.add(
        EntryLine(
          itemId: r.line?.lineId == null ? r.line?.itemId : null,
          lineId: r.line?.lineId,
          productId: r.line?.productId,
          name: r.title,
          unit: r.unit,
          catalogCode: r.code,
          qtyMilli: qty,
          costPaise: cost,
        ),
      );
    }
    return (lines, null);
  }

  /// Quantity x price over all lines that have both (null if none).
  int? get costTotal {
    var total = 0;
    var any = false;
    for (final r in rows) {
      final qty = parseQty(r.qty.text);
      final cost = parsePaise(r.cost.text);
      if (qty == null || cost == null) continue;
      total += (qty * cost / milli).round();
      any = true;
    }
    return any ? total : null;
  }

  @override
  void dispose() {
    for (final r in rows) {
      r.dispose();
    }
    super.dispose();
  }
}

class LinesEditor extends StatelessWidget {
  const LinesEditor({
    required this.controller,
    this.products = const [],
    this.withCost = false,
    this.addLabel = 'Type an item',
    this.productsLabel = 'Add from their products',
    this.onChanged,
    super.key,
  });

  final LinesController controller;

  /// A connected supplier's products that can be added.
  final List<SupplierProduct> products;
  final bool withCost;
  final String addLabel;
  final String productsLabel;
  final VoidCallback? onChanged;

  Future<void> _pick(BuildContext context) async {
    final names = {for (final r in controller.rows) '${r.title} ${r.unit.code}'};
    final p = await _pickProduct(context, [
      for (final p in products)
        if (!names.contains('${p.name} ${p.unit.code}')) p,
    ]);
    if (p == null) return;
    controller.add(EntryLine(name: p.name, unit: p.unit, qtyMilli: 0, costPaise: p.pricePaise, catalogCode: p.catalogCode));
    onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final r in controller.rows)
            _Row(
              key: ValueKey(r.id),
              row: r,
              withCost: withCost,
              onChanged: onChanged,
              onRemove: () {
                controller.remove(r);
                onChanged?.call();
              },
            ),
          Wrap(
            children: [
              if (products.isNotEmpty)
                TextButton.icon(
                  key: const Key('line-add-product'),
                  onPressed: () => _pick(context),
                  icon: const Icon(Icons.add_rounded),
                  label: Text(productsLabel),
                ),
              TextButton.icon(
                key: const Key('line-add'),
                onPressed: () {
                  controller.add();
                  onChanged?.call();
                },
                icon: const Icon(Icons.edit_outlined, size: 20),
                label: Text(addLabel),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Row extends StatefulWidget {
  const _Row({required this.row, required this.withCost, required this.onChanged, required this.onRemove, super.key});

  final LineRow row;
  final bool withCost;
  final VoidCallback? onChanged;
  final VoidCallback onRemove;

  @override
  State<_Row> createState() => _RowState();
}

class _RowState extends State<_Row> {
  LineRow get _row => widget.row;

  void _changed([VoidCallback? change]) {
    setState(change ?? () {});
    widget.onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    final r = _row;
    final remove = IconButton(
      key: Key('line-remove-${r.id}'),
      onPressed: widget.onRemove,
      icon: const Icon(Icons.close_rounded, size: 20),
      tooltip: 'Remove',
    );
    final numbers = [
      Expanded(child: _number('line-qty-${r.id}', r.qty, InputDecoration(hintText: 'Qty', suffixText: r.unit.short, isDense: true))),
      if (widget.withCost) ...[
        const SizedBox(width: 10),
        Expanded(
          child: _number(
            'line-cost-${r.id}',
            r.cost,
            InputDecoration(hintText: 'Price/${r.unit.short}', prefixText: '₹', isDense: true),
          ),
        ),
      ],
    ];
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 8),
      decoration: BoxDecoration(color: udSoft, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: r.typed
                    ? TextField(
                        key: Key('line-name-${r.id}'),
                        controller: r.name,
                        maxLength: 80,
                        textCapitalization: TextCapitalization.sentences,
                        onChanged: (_) => _changed(() => r.code = r.title.isEmpty ? null : r.code),
                        decoration: const InputDecoration(hintText: 'Item name', counterText: '', isDense: true),
                      )
                    : Text(r.title, style: udText(14, weight: FontWeight.w600)),
              ),
              if (r.typed) ...[
                const SizedBox(width: 8),
                DropdownButton<StockUnit>(
                  key: Key('line-unit-${r.id}'),
                  value: r.unit,
                  underline: const SizedBox.shrink(),
                  onChanged: (u) => _changed(() => r.unit = u ?? r.unit),
                  items: [for (final u in StockUnit.values) DropdownMenuItem(value: u, child: Text(u.short))],
                ),
              ],
              remove,
            ],
          ),
          if (r.suggestions.isNotEmpty)
            Wrap(
              spacing: 6,
              children: [
                for (final c in r.suggestions)
                  ActionChip(
                    key: Key('line-suggest-${c.code}'),
                    label: Text(c.en),
                    onPressed: () => _changed(() {
                      r.name.text = c.en;
                      r.unit = c.unit;
                      r.code = c.code;
                    }),
                  ),
              ],
            ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Row(children: numbers),
          ),
        ],
      ),
    );
  }

  Widget _number(String key, TextEditingController controller, InputDecoration decoration) => TextField(
    key: Key(key),
    controller: controller,
    onChanged: (_) => widget.onChanged?.call(),
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
    decoration: decoration,
  );
}

Future<SupplierProduct?> _pickProduct(BuildContext context, List<SupplierProduct> products) =>
    showModalBottomSheet<SupplierProduct>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: ListView(
          children: [
            for (final p in products)
              ListTile(
                key: Key('pick-product-${p.id}'),
                title: Text(p.name, style: udText(15, weight: FontWeight.w600)),
                subtitle: Text(
                  p.pricePaise == null ? p.unit.short : '${rupees(p.pricePaise!)}/${p.unit.short}',
                  style: udText(12, color: udBody),
                ),
                onTap: () => Navigator.of(context).pop(p),
              ),
          ],
        ),
      ),
    );

/// "Rice 25 kg, Sugar 10 kg".
String linesSummary(List<EntryLine> lines) =>
    lines.map((l) => '${l.name} ${formatQty(l.qtyMilli, l.unit)}').join(', ');

/// "₹7,000 due", "₹500 advance", "All paid".
String owedLabel(int paise) =>
    paise > 0 ? '${rupees(paise)} due' : (paise < 0 ? '${rupees(paise)} advance' : 'All paid');

/// A big button across the screen.
class WideButton extends StatelessWidget {
  const WideButton({required this.label, required this.onPressed, this.color = udPurple, this.icon, super.key});

  final String label;
  final VoidCallback? onPressed;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final style = FilledButton.styleFrom(
      backgroundColor: color,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      textStyle: udText(16, weight: FontWeight.w700),
    );
    final text = FittedBox(fit: BoxFit.scaleDown, child: Text(label, maxLines: 1));
    return SizedBox(
      height: 54,
      width: double.infinity,
      child: icon == null
          ? FilledButton(onPressed: onPressed, style: style, child: text)
          : FilledButton.icon(onPressed: onPressed, style: style, icon: Icon(icon), label: text),
    );
  }
}
