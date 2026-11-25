import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../stock/stock_models.dart' show formatQty, milli;
import '../suppliers/supplier_models.dart' show OrderStatus, payPlanText;
import '../udhaar/udhaar_models.dart' show paiseToText, parsePaise, rupees, whenLabel;
import '../udhaar/udhaar_widgets.dart';
import 'supply_models.dart';
import 'supply_page.dart';

Color orderColor(OrderStatus status) => switch (status) {
  OrderStatus.sent => udWarn,
  OrderStatus.accepted || OrderStatus.dispatched => udPurple,
  OrderStatus.received => udPaid,
  OrderStatus.rejected => udDue,
  OrderStatus.cancelled => udBody,
};

/// One order in a list.
class SupplyOrderTile extends StatelessWidget {
  const SupplyOrderTile({required this.order, required this.now, required this.onTap, this.showShop = false, super.key});

  final SupplyOrder order;
  final DateTime now;
  final VoidCallback onTap;
  final bool showShop;

  @override
  Widget build(BuildContext context) {
    final o = order;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          key: Key('order-${o.id}'),
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (showShop) Text(o.shopName, style: udText(15, weight: FontWeight.w700)),
                      Text(
                        supplyLinesText(o.lines),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: udText(13, weight: showShop ? FontWeight.w500 : FontWeight.w600),
                      ),
                      Text(whenLabel(o.createdAt, now), style: udText(11, color: udBody)),
                      const SizedBox(height: 4),
                      UdBadge(supplyStatus(o.status), color: orderColor(o.status)),
                    ],
                  ),
                ),
                if (o.totalPaise != null) ...[
                  const SizedBox(width: 8),
                  Text(rupees(o.totalPaise!), style: udText(15, weight: FontWeight.w700)),
                ],
                const Icon(Icons.chevron_right_rounded, color: udPurple),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Line {
  _Line(this.line)
    : available = line.available,
      price = TextEditingController(text: line.costPaise == null ? '' : paiseToText(line.costPaise!));

  final SupplyLine line;
  final TextEditingController price;
  bool available;
}

/// One order: what can be given and at what price, the bill, and sending it.
class SupplyOrderScreen extends StatefulWidget {
  const SupplyOrderScreen({required this.order, this.now, super.key});

  final SupplyOrder order;
  final DateTime? now;

  @override
  State<SupplyOrderScreen> createState() => _SupplyOrderScreenState();
}

class _SupplyOrderScreenState extends State<SupplyOrderScreen> with SupplyPage<SupplyOrderScreen, SupplyOrder> {
  late final List<_Line> _rows = [for (final l in widget.order.lines) _Line(l)];
  late final _total = TextEditingController(text: _firstTotal);
  late final _note = TextEditingController(text: widget.order.answerNote ?? '');
  bool _editing = false;
  String? _problem;

  SupplyOrder get _order => data ?? widget.order;

  bool get _form => _order.connected && (_order.status == OrderStatus.sent || (_editing && _order.status == OrderStatus.accepted));

  /// The bill already sent, or what the products' prices come to.
  String get _firstTotal {
    final total = widget.order.totalPaise ?? _sum;
    return total == null ? '' : paiseToText(total);
  }

  @override
  Future<SupplyOrder?> loadSaved() async => widget.order;

  @override
  Future<SupplyOrder> loadFresh() async {
    final all = await app.supply.orders();
    return all.where((o) => o.id == widget.order.id).firstOrNull ?? _order;
  }

  @override
  void dispose() {
    for (final r in _rows) {
      r.price.dispose();
    }
    _total.dispose();
    _note.dispose();
    super.dispose();
  }

  /// Quantity x price of what is available (null until a price is typed).
  int? get _sum {
    int? sum;
    for (final r in _rows.where((r) => r.available)) {
      final price = parsePaise(r.price.text);
      if (price != null) sum = (sum ?? 0) + (r.line.qtyMilli * price / milli).round();
    }
    return sum;
  }

  void _changed() {
    final sum = _sum;
    setState(() {
      _problem = null;
      _total.text = sum == null ? '' : paiseToText(sum);
    });
  }

  Future<void> _accept() async {
    final lines = <LineAnswer>[];
    for (final r in _rows) {
      final text = r.price.text.trim();
      final price = text.isEmpty ? null : parsePaise(text);
      if (r.available && text.isNotEmpty && price == null) {
        setState(() => _problem = 'Check the price of ${r.line.name}');
        return;
      }
      lines.add(LineAnswer(id: r.line.id, available: r.available, costPaise: r.available ? price : null));
    }
    if (!lines.any((l) => l.available)) {
      setState(() => _problem = 'Nothing is available. Reject the order instead.');
      return;
    }
    final total = parsePaise(_total.text);
    if (total == null || total <= 0) {
      setState(() => _problem = 'Enter the bill total');
      return;
    }
    FocusScope.of(context).unfocus();
    final ok = await act(
      () => app.supply.api.acceptOrder(_order.id, lines, totalPaise: total, note: _note.text),
      'Accepted. ${_order.shopName} can see the bill.',
    );
    if (ok && mounted) setState(() => _editing = false);
  }

  Future<void> _reject() async {
    final reason = await askReason(
      context,
      title: 'Reject this order?',
      text: _order.paidPaise + _order.payingPaise > 0
          ? '${_order.shopName} will see why. What they paid for it stays as their advance.'
          : '${_order.shopName} will see why.',
      action: 'Reject',
    );
    if (reason == null || !mounted) return;
    await act(() => app.supply.api.rejectOrder(_order.id, reason), 'Rejected');
  }

  Future<void> _dispatch() async {
    final sure = await askSure(
      context,
      title: 'Are the goods on the way?',
      text: '${_order.shopName} will be told. The prices can no longer be changed.',
      action: 'Yes, sent',
    );
    if (!sure || !mounted) return;
    await act(() => app.supply.api.dispatchOrder(_order.id), 'Marked as on the way');
  }

  @override
  Widget build(BuildContext context) {
    final o = _order;
    final now = widget.now ?? DateTime.now();
    return Scaffold(
      backgroundColor: udBackground,
      body: SafeArea(
        child: Column(
          children: [
            UdHeader(
              title: 'Order',
              subtitle: o.shopName,
              busy: busy,
              actions: contactButtons(o.shopPhone, 'order'),
            ),
            errorBanner(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    UdCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              UdBadge(supplyStatus(o.status), color: orderColor(o.status)),
                              Text(whenLabel(o.createdAt, now), style: udText(12, color: udBody)),
                            ],
                          ),
                          if ((o.note ?? '').isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text('Note: ${o.note}', style: udText(13, weight: FontWeight.w600)),
                            ),
                          if (payPlanText(o.payPlan, o.payBy, now) != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                'Payment: ${payPlanText(o.payPlan, o.payBy, now)}',
                                key: const Key('order-plan'),
                                style: udText(13, weight: FontWeight.w600),
                              ),
                            ),
                          if (o.paidPaise > 0)
                            Text(
                              'They paid ${rupees(o.paidPaise)}',
                              style: udText(13, weight: FontWeight.w600, color: udPaid),
                            ),
                          if (o.payingPaise > 0)
                            Text(
                              'They say they paid ${rupees(o.payingPaise)}. Check your bank, and confirm it in Payments.',
                              key: const Key('order-paying'),
                              style: udText(13, weight: FontWeight.w600, color: udWarn),
                            ),
                          if (!o.connected)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                'You are no longer connected with this shop.',
                                key: const Key('order-disconnected'),
                                style: udText(13, color: udDue),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_form) _answerForm() else _summary(o),
                    if (_problem != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          _problem!,
                          key: const Key('order-problem'),
                          style: udText(13, weight: FontWeight.w600, color: udDue),
                        ),
                      ),
                    const SizedBox(height: 16),
                    ..._buttons(o),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _answerForm() => UdCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('What can you give?', style: udText(15, weight: FontWeight.w700)),
        for (final r in _rows)
          Row(
            children: [
              Checkbox(
                key: Key('line-have-${r.line.id}'),
                value: r.available,
                activeColor: udPaid,
                onChanged: (v) {
                  r.available = v ?? false;
                  _changed();
                },
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.line.name,
                      style: udText(
                        14,
                        weight: FontWeight.w600,
                        color: r.available ? udInk : udBody,
                        decoration: r.available ? null : TextDecoration.lineThrough,
                      ),
                    ),
                    Text(r.line.qty, style: udText(12, color: udBody)),
                    if (r.line.haveMilli != null)
                      Text(
                        'You have ${formatQty(r.line.haveMilli!, r.line.unit)}',
                        key: Key('line-left-${r.line.id}'),
                        style: udText(
                          12,
                          weight: FontWeight.w600,
                          color: r.line.haveMilli! < r.line.qtyMilli ? udDue : udPaid,
                        ),
                      ),
                  ],
                ),
              ),
              SizedBox(
                width: 104,
                child: TextField(
                  key: Key('line-price-${r.line.id}'),
                  controller: r.price,
                  enabled: r.available,
                  onChanged: (_) => _changed(),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                  textAlign: TextAlign.end,
                  decoration: InputDecoration(
                    hintText: 'Price',
                    prefixText: '₹',
                    suffixText: '/${r.line.unit.short}',
                    isDense: true,
                  ),
                ),
              ),
            ],
          ),
        const SizedBox(height: 8),
        TextField(
          key: const Key('order-total'),
          controller: _total,
          onChanged: (_) => setState(() => _problem = null),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
          style: udText(22, weight: FontWeight.w800),
          decoration: const InputDecoration(labelText: 'Bill total', prefixText: '₹ '),
        ),
        TextField(
          key: const Key('order-note'),
          controller: _note,
          maxLength: 200,
          decoration: const InputDecoration(labelText: 'Note (optional), e.g. coming Friday', counterText: ''),
        ),
      ],
    ),
  );

  Widget _summary(SupplyOrder o) => UdCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final l in o.lines)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${l.name}, ${l.qty}',
                    style: udText(
                      14,
                      weight: FontWeight.w600,
                      color: l.available ? udInk : udBody,
                      decoration: l.available ? null : TextDecoration.lineThrough,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  !l.available
                      ? 'Not available'
                      : l.costPaise == null
                      ? ''
                      : '${rupees(l.costPaise!)}/${l.unit.short}',
                  style: udText(13, color: udBody),
                ),
              ],
            ),
          ),
        if (o.totalPaise != null) ...[
          const Divider(height: 20),
          Row(
            children: [
              Expanded(child: Text('Bill total', style: udText(15, weight: FontWeight.w700))),
              Text(
                rupees(o.totalPaise!),
                key: const Key('order-bill'),
                style: udText(18, weight: FontWeight.w800),
              ),
            ],
          ),
        ],
        if ((o.answerNote ?? '').isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('You wrote: ${o.answerNote}', style: udText(13, color: udBody)),
          ),
      ],
    ),
  );

  List<Widget> _buttons(SupplyOrder o) {
    if (!o.connected) return const [];
    return [
      if (_form) ...[
        _button('order-accept', _editing ? 'Save the new bill' : 'Accept and send bill', udPurple, _accept),
        if (_editing)
          TextButton(
            key: const Key('order-edit-cancel'),
            onPressed: busy ? null : () => setState(() => _editing = false),
            child: const Text('Do not change'),
          ),
      ] else if (o.status == OrderStatus.accepted) ...[
        _button('order-dispatch', 'Goods sent', udPaid, _dispatch),
        TextButton(
          key: const Key('order-edit'),
          onPressed: busy ? null : () => setState(() => _editing = true),
          child: const Text('Change prices'),
        ),
      ],
      if (o.status == OrderStatus.sent || o.status == OrderStatus.accepted)
        TextButton(
          key: const Key('order-reject'),
          onPressed: busy ? null : _reject,
          style: TextButton.styleFrom(foregroundColor: udDue),
          child: const Text('Reject order'),
        ),
      if (o.status == OrderStatus.dispatched)
        Text(
          'Waiting for the shop to receive the goods.',
          textAlign: TextAlign.center,
          style: udText(13, color: udBody),
        ),
    ];
  }

  Widget _button(String key, String label, Color color, VoidCallback onTap) => SizedBox(
    height: 54,
    child: FilledButton(
      key: Key(key),
      onPressed: busy ? null : onTap,
      style: FilledButton.styleFrom(
        backgroundColor: color,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: udText(16, weight: FontWeight.w700),
      ),
      child: Text(label),
    ),
  );
}
