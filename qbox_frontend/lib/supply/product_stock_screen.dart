import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../stock/stock_models.dart';
import '../udhaar/udhaar_models.dart' show newClientRef, whenLabel;
import '../udhaar/udhaar_widgets.dart';
import 'supply_models.dart';
import 'supply_page.dart';

/// The supplier's own count of one product: how much there is, stock in and out,
/// when to warn, and the history (never erased).
class ProductStockScreen extends StatefulWidget {
  const ProductStockScreen({required this.product, this.now, super.key});

  final Product product;
  final DateTime? now;

  @override
  State<ProductStockScreen> createState() => _ProductStockScreenState();
}

class _ProductStockScreenState extends State<ProductStockScreen> with SupplyPage<ProductStockScreen, ProductStock> {
  Product get _product => data?.product ?? widget.product;

  @override
  Future<ProductStock?> loadSaved() async => null;

  @override
  Future<ProductStock> loadFresh() => app.supply.api.productStock(widget.product.id);

  Future<void> _move(CountKind kind) async {
    final answer = await showModalBottomSheet<(int, String)>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _MoveSheet(product: _product, kind: kind),
    );
    if (answer == null || !mounted) return;
    final (qty, note) = answer;
    final ref = newClientRef();
    await act(() => app.supply.api.addMove(_product.id, kind, qty, note: note, clientRef: ref), 'Saved');
  }

  Future<void> _warn() async {
    final answer = await showDialog<(int?,)>(context: context, builder: (_) => _WarnDialog(product: _product));
    if (answer == null || !mounted) return;
    await act(
      () => app.supply.api.setCounting(_product.id, counted: true, alertMilli: answer.$1),
      answer.$1 == null ? 'No warning' : 'You will be warned',
    );
  }

  Future<void> _stop() async {
    final sure = await askSure(
      context,
      title: 'Stop counting ${_product.name}?',
      text: 'The history is kept. Shops then see only your Available switch.',
      action: 'Stop counting',
      color: udDue,
    );
    if (!sure || !mounted) return;
    await act(
      () => app.supply.api.setCounting(_product.id, counted: false, alertMilli: _product.alertMilli),
      'Not counted any more',
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = _product;
    final now = widget.now ?? DateTime.now();
    final moves = data?.moves ?? const <ProductMove>[];
    return Scaffold(
      backgroundColor: udBackground,
      body: SafeArea(
        child: Column(
          children: [
            UdHeader(
              title: p.name,
              subtitle: 'Your stock',
              busy: busy,
              actions: [
                if (p.counted)
                  PopupMenuButton<VoidCallback>(
                    key: const Key('stock-menu'),
                    iconColor: udPurple,
                    onSelected: (action) => action(),
                    itemBuilder: (_) => [
                      PopupMenuItem(key: const Key('stock-warn'), value: _warn, child: const Text('Warn me when low')),
                      PopupMenuItem(key: const Key('stock-stop'), value: _stop, child: const Text('Stop counting')),
                    ],
                  ),
              ],
            ),
            errorBanner(),
            Expanded(
              child: RefreshIndicator(
                onRefresh: load,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  children: [
                    UdCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: p.counted
                            ? [
                                Text('You have', style: udText(13, color: udBody)),
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    formatQty(p.quantityMilli, p.unit),
                                    key: const Key('stock-left'),
                                    style: udText(34, weight: FontWeight.w800, color: p.low ? udDue : udInk),
                                  ),
                                ),
                                if (p.low) UdBadge(p.quantityMilli <= 0 ? 'Shops see: not available' : 'Running low'),
                                if (p.alertMilli != null)
                                  Text(
                                    'Warns at ${formatQty(p.alertMilli!, p.unit)}',
                                    style: udText(12, color: udBody),
                                  ),
                              ]
                            : [
                                Text('Not counted yet', style: udText(17, weight: FontWeight.w700)),
                                const SizedBox(height: 4),
                                Text(
                                  'Say how much you have now. Goods you send to your shops go out by themselves, and at 0 '
                                  'shops see "Not available". They never see how much you have.',
                                  key: const Key('stock-why'),
                                  style: udText(13, color: udBody),
                                ),
                              ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (!p.counted)
                      _button('stock-start', Icons.inventory_2_outlined, 'Start counting', udPurple, CountKind.count)
                    else
                      Row(
                        children: [
                          Expanded(child: _button('stock-in', Icons.add_rounded, 'In', udPaid, CountKind.stockIn)),
                          const SizedBox(width: 8),
                          Expanded(child: _button('stock-out', Icons.remove_rounded, 'Out', udDue, CountKind.out)),
                          const SizedBox(width: 8),
                          Expanded(child: _button('stock-count', Icons.edit_outlined, 'Correct', udWarn, CountKind.count)),
                        ],
                      ),
                    if (moves.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(2, 16, 2, 8),
                        child: Text('History', style: udText(16, weight: FontWeight.w700)),
                      ),
                      for (final m in moves) _tile(m, p.unit, now),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _button(String key, IconData icon, String label, Color color, CountKind kind) => SizedBox(
    height: 52,
    child: FilledButton.icon(
      key: Key(key),
      onPressed: busy ? null : () => _move(kind),
      icon: Icon(icon, size: 20),
      label: FittedBox(fit: BoxFit.scaleDown, child: Text(label, maxLines: 1)),
      style: FilledButton.styleFrom(
        backgroundColor: color,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: udText(14, weight: FontWeight.w700),
      ),
    ),
  );

  Widget _tile(ProductMove m, StockUnit unit, DateTime now) {
    final (icon, color, label) = switch (m.kind) {
      MoveKind.stockIn => (Icons.south_west_rounded, udPaid, 'Stock in'),
      MoveKind.out => (Icons.north_east_rounded, udDue, 'Stock out'),
      MoveKind.adjust => (Icons.edit_outlined, udWarn, 'Corrected'),
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: udText(14, weight: FontWeight.w700)),
                if ((m.note ?? '').isNotEmpty) Text(m.note!, style: udText(13, color: udBody)),
                Text(whenLabel(m.at, now), style: udText(11, color: udBody)),
              ],
            ),
          ),
          Text(
            '${m.effect >= 0 ? '+' : '−'} ${formatQty(m.effect.abs(), unit)}',
            style: udText(16, weight: FontWeight.w700, color: color),
          ),
        ],
      ),
    );
  }
}

class _MoveSheet extends StatefulWidget {
  const _MoveSheet({required this.product, required this.kind});

  final Product product;
  final CountKind kind;

  @override
  State<_MoveSheet> createState() => _MoveSheetState();
}

class _MoveSheetState extends State<_MoveSheet> {
  final _qty = TextEditingController();
  final _note = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _qty.dispose();
    _note.dispose();
    super.dispose();
  }

  void _save() {
    final qty = parseQty(_qty.text);
    if (qty == null || (qty == 0 && widget.kind != CountKind.count)) {
      setState(() => _error = 'Enter how much');
    } else {
      Navigator.of(context).pop((qty, _note.text));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    final title = switch (widget.kind) {
      CountKind.stockIn => 'How much came in?',
      CountKind.out => 'How much went out?',
      CountKind.count => 'How much do you have now?',
    };
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('${p.name}: $title', style: udText(17, weight: FontWeight.w700)),
            if (widget.kind == CountKind.out)
              Text('Only for goods outside QBOX. Orders go out by themselves.', style: udText(12, color: udBody)),
            TextField(
              key: const Key('move-qty'),
              controller: _qty,
              autofocus: true,
              onChanged: (_) => setState(() => _error = null),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
              style: udText(28, weight: FontWeight.w800),
              decoration: InputDecoration(suffixText: p.unit.short, errorText: _error),
            ),
            TextField(
              key: const Key('move-note'),
              controller: _note,
              maxLength: 100,
              decoration: const InputDecoration(labelText: 'Note (optional)', counterText: ''),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 52,
              child: FilledButton(
                key: const Key('move-save'),
                onPressed: _save,
                style: FilledButton.styleFrom(
                  backgroundColor: udPurple,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  textStyle: udText(16, weight: FontWeight.w700),
                ),
                child: const Text('Save'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// When to warn. Closes with (null,) for no warning.
class _WarnDialog extends StatefulWidget {
  const _WarnDialog({required this.product});

  final Product product;

  @override
  State<_WarnDialog> createState() => _WarnDialogState();
}

class _WarnDialogState extends State<_WarnDialog> {
  late final _qty = TextEditingController(
    text: widget.product.alertMilli == null ? '' : qtyNumber(widget.product.alertMilli!),
  );
  String? _error;

  @override
  void dispose() {
    _qty.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: const Text('Warn me when low'),
    content: TextField(
      key: const Key('warn-qty'),
      controller: _qty,
      autofocus: true,
      onChanged: (_) => setState(() => _error = null),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
      decoration: InputDecoration(
        labelText: 'When this much or less is left',
        helperText: 'Empty = no warning',
        suffixText: widget.product.unit.short,
        errorText: _error,
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
      FilledButton(
        key: const Key('warn-save'),
        onPressed: () {
          final text = _qty.text.trim();
          final qty = text.isEmpty ? null : parseQty(text);
          if (text.isNotEmpty && qty == null) {
            setState(() => _error = 'Check the number');
          } else {
            Navigator.of(context).pop((qty,));
          }
        },
        style: FilledButton.styleFrom(backgroundColor: udPurple),
        child: const Text('Save'),
      ),
    ],
  );
}
