import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../stock/stock_catalog.dart';
import '../stock/stock_models.dart';
import '../udhaar/udhaar_models.dart' show paiseToText, parsePaise, rupees;
import '../udhaar/udhaar_widgets.dart';
import 'supplier_models.dart';

/// One stock item in a purchase or order being filled in.
class LineRow {
  LineRow(this.item, {int? qtyMilli, int? costPaise})
    : qty = TextEditingController(text: qtyMilli == null ? '' : qtyNumber(qtyMilli)),
      cost = TextEditingController(text: costPaise == null ? '' : paiseToText(costPaise));

  final StockItem item;
  final TextEditingController qty;
  final TextEditingController cost;

  void dispose() {
    qty.dispose();
    cost.dispose();
  }
}

/// The items of a purchase or order: add from stock, type quantities (and
/// buying prices for purchases).
class LinesController extends ChangeNotifier {
  LinesController([List<LineRow>? rows]) : rows = rows ?? [];

  final List<LineRow> rows;

  void add(StockItem item, {int? qtyMilli}) {
    if (rows.any((r) => r.item.id == item.id)) return;
    rows.add(LineRow(item, qtyMilli: qtyMilli, costPaise: item.costPaise));
    notifyListeners();
  }

  void remove(LineRow row) {
    rows.remove(row);
    row.dispose();
    notifyListeners();
  }

  /// The lines as typed, or an error message.
  (List<EntryLine>, String?) read({bool withCost = false}) {
    final lines = <EntryLine>[];
    for (final r in rows) {
      final qty = parseQty(r.qty.text);
      if (qty == null || qty <= 0) return (const [], 'Enter how much ${r.item.name}');
      int? cost;
      if (withCost && r.cost.text.trim().isNotEmpty) {
        cost = parsePaise(r.cost.text);
        if (cost == null) return (const [], 'Check the price of ${r.item.name}');
      }
      lines.add(EntryLine(itemId: r.item.id, name: r.item.name, unit: r.item.unit, qtyMilli: qty, costPaise: cost));
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
  const LinesEditor({required this.controller, required this.items, this.withCost = false, this.onChanged, super.key});

  final LinesController controller;

  /// Stock items that can be added.
  final List<StockItem> items;
  final bool withCost;
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final r in controller.rows)
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
              decoration: BoxDecoration(color: udSoft, borderRadius: BorderRadius.circular(12)),
              child: Row(
                children: [
                  Expanded(child: Text(r.item.name, style: udText(14, weight: FontWeight.w600))),
                  SizedBox(
                    width: 84,
                    child: TextField(
                      key: Key('line-qty-${r.item.id}'),
                      controller: r.qty,
                      onChanged: (_) => onChanged?.call(),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                      textAlign: TextAlign.end,
                      decoration: InputDecoration(hintText: 'Qty', suffixText: r.item.unit.short, isDense: true),
                    ),
                  ),
                  if (withCost) ...[
                    const SizedBox(width: 6),
                    SizedBox(
                      width: 84,
                      child: TextField(
                        key: Key('line-cost-${r.item.id}'),
                        controller: r.cost,
                        onChanged: (_) => onChanged?.call(),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                        textAlign: TextAlign.end,
                        decoration: InputDecoration(hintText: '₹/${r.item.unit.short}', prefixText: '₹', isDense: true),
                      ),
                    ),
                  ],
                  IconButton(
                    key: Key('line-remove-${r.item.id}'),
                    onPressed: () {
                      controller.remove(r);
                      onChanged?.call();
                    },
                    icon: const Icon(Icons.close_rounded, size: 20),
                  ),
                ],
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const Key('line-add'),
              onPressed: () async {
                final item = await pickStockItem(context, items, exclude: {for (final r in controller.rows) r.item.id});
                if (item != null) {
                  controller.add(item);
                  onChanged?.call();
                }
              },
              icon: const Icon(Icons.add_rounded),
              label: Text(items.isEmpty ? 'Add items in Stock first' : 'Add item from stock'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Choose a stock item (search in any language).
Future<StockItem?> pickStockItem(BuildContext context, List<StockItem> items, {Set<int> exclude = const {}}) {
  if (items.isEmpty) return Future.value(null);
  return showModalBottomSheet<StockItem>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _ItemPicker(items: [for (final i in items) if (!exclude.contains(i.id)) i]),
  );
}

class _ItemPicker extends StatefulWidget {
  const _ItemPicker({required this.items});

  final List<StockItem> items;

  @override
  State<_ItemPicker> createState() => _ItemPickerState();
}

class _ItemPickerState extends State<_ItemPicker> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final q = _q.trim().toLowerCase();
    final shown = [
      for (final i in widget.items)
        if (q.isEmpty ||
            i.name.toLowerCase().contains(q) ||
            (catalogItem(i.catalogCode)?.allNames.any((n) => n.toLowerCase().contains(q)) ?? false))
          i,
    ];
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.7,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              key: const Key('pick-search'),
              autofocus: false,
              onChanged: (v) => setState(() => _q = v),
              decoration: const InputDecoration(hintText: 'Search items', prefixIcon: Icon(Icons.search_rounded)),
            ),
          ),
          Expanded(
            child: ListView(
              children: [
                for (final i in shown)
                  ListTile(
                    key: Key('pick-${i.id}'),
                    title: Text(i.name, style: udText(15, weight: FontWeight.w600)),
                    subtitle: Text('In stock: ${formatQty(i.quantityMilli, i.unit)}', style: udText(12, color: udBody)),
                    trailing: i.isLow ? const UdBadge('Low') : null,
                    onTap: () => Navigator.of(context).pop(i),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "Rice 25 kg, Sugar 10 kg".
String linesSummary(List<EntryLine> lines) =>
    lines.map((l) => '${l.name} ${formatQty(l.qtyMilli, l.unit)}').join(', ');

/// "₹7,000 due", "₹500 advance", "All paid".
String owedLabel(int paise) =>
    paise > 0 ? '${rupees(paise)} due' : (paise < 0 ? '${rupees(paise)} advance' : 'All paid');
