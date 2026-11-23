import 'package:flutter/material.dart';

import '../calendar/calendar_models.dart' show longDate;
import '../services/api_client.dart';
import '../services/app_services.dart';
import '../services/device_actions.dart';
import '../udhaar/udhaar_models.dart' show rupees, whenLabel;
import '../udhaar/udhaar_widgets.dart';
import 'order_screen.dart';
import 'supplier_entry_screen.dart';
import 'supplier_form_screen.dart';
import 'supplier_models.dart';
import 'supplier_widgets.dart';

/// One supplier: what the shop owes, the pay-by date, purchases and payments
/// (never erased), and orders waiting for goods.
class SupplierScreen extends StatefulWidget {
  const SupplierScreen({required this.supplier, this.now, super.key});

  final Supplier supplier;
  final DateTime? now;

  @override
  State<SupplierScreen> createState() => _SupplierScreenState();
}

class _SupplierScreenState extends State<SupplierScreen> {
  AppServices? _services;
  late Supplier _supplier = widget.supplier;
  List<SupplierEntry>? _entries;
  List<SupplierOrder> _orders = const [];
  bool _busy = false;
  bool _offline = false;

  AppServices get _app => _services!;
  DateTime get _now => widget.now ?? DateTime.now();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_services != null) return;
    _services = ServicesScope.of(context);
    _load();
  }

  Future<void> _load() async {
    final saved = await _app.suppliers.savedSupplier(_supplier.id);
    if (saved != null && mounted) _show(saved);
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      final fresh = await _app.suppliers.freshSupplier(_supplier.id);
      if (mounted) {
        _show(fresh);
        setState(() => _offline = false);
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.isNetwork) {
        setState(() => _offline = true);
      } else {
        udNotify(context, e.message);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _show(SupplierDetail d) => setState(() {
    _supplier = d.supplier;
    _entries = d.entries;
    _orders = d.orders;
  });

  Future<void> _entry(SupplierEntryKind kind, {SupplierOrder? order}) async {
    final result = await Navigator.of(context).push<EntryResult>(
      MaterialPageRoute(builder: (_) => SupplierEntryScreen(supplier: _supplier, kind: kind, order: order, now: widget.now)),
    );
    if (result == null || !mounted) return;
    udNotify(context, switch (result) {
      EntryResult.saved => 'Saved',
      EntryResult.savedOffline => 'Saved on the phone. It will sync when internet is back.',
      EntryResult.received => 'Goods received: stock updated',
    });
    await _load();
  }

  Future<void> _order() async {
    final sent = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => OrderScreen(supplier: _supplier)),
    );
    if (sent == true && mounted) await _load();
  }

  Future<void> _cancelOrder(SupplierOrder order) async {
    try {
      await _app.suppliers.cancelOrder(order.id);
      if (mounted) await _load();
    } on ApiException catch (e) {
      if (mounted) udNotify(context, e.isNetwork ? 'This needs internet.' : e.message);
    }
  }

  Future<void> _delete(SupplierEntry entry) async {
    if (entry.id == null || entry.deleted) return;
    final why = await showDialog<String>(context: context, builder: (_) => _DeleteDialog(entry: entry));
    if (why == null || !mounted) return;
    try {
      await _app.suppliers.deleteEntry(entry.id!, why);
      if (mounted) await _load();
    } on ApiException catch (e) {
      if (mounted) udNotify(context, e.isNetwork ? 'Deleting needs internet.' : e.message);
    }
  }

  Future<void> _edit() async {
    final saved = await Navigator.of(context).push<Supplier>(
      MaterialPageRoute(builder: (_) => SupplierFormScreen(supplier: _supplier)),
    );
    if (saved != null && mounted) await _load();
  }

  Future<void> _remove() async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove ${_supplier.name}?'),
        content: Text(_supplier.balancePaise > 0
            ? 'You still owe ${rupees(_supplier.balancePaise)}. The history is kept, but they leave your list.'
            : 'They leave your list. The history is kept.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(
            key: const Key('supplier-remove-yes'),
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: udDue),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    try {
      await _app.suppliers.archiveSupplier(_supplier.id);
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (mounted) udNotify(context, e.isNetwork ? 'This needs internet.' : e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _supplier;
    final open = _orders.where((o) => o.open).toList();
    final mobile = s.mobile;
    return Scaffold(
      backgroundColor: udBackground,
      body: SafeArea(
        child: Column(
          children: [
            UdHeader(
              title: s.name,
              subtitle: s.supplies ?? 'Supplier',
              busy: _busy,
              actions: [
                IconButton(key: const Key('supplier-edit'), onPressed: _edit, icon: const Icon(Icons.edit_outlined, color: udPurple)),
                IconButton(key: const Key('supplier-remove'), onPressed: _remove, icon: const Icon(Icons.delete_outline_rounded, color: udDue)),
              ],
            ),
            if (_offline)
              const UdBanner(icon: Icons.wifi_off_rounded, text: 'Offline: showing the saved copy. Entries are kept on the phone.'),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  children: [
                    UdCard(
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(s.balancePaise > 0 ? 'You owe' : (s.balancePaise < 0 ? 'Paid in advance' : 'All paid'),
                                    style: udText(13, color: udBody)),
                                Text(rupees(s.balancePaise),
                                    key: const Key('supplier-balance'),
                                    style: udText(32, weight: FontWeight.w800, color: s.balancePaise > 0 ? udDue : udPaid)),
                                if (s.nextDue != null)
                                  Text(
                                    s.overdue ? 'Overdue since ${longDate(s.nextDue!)}' : 'Pay by ${longDate(s.nextDue!)}',
                                    key: const Key('supplier-due'),
                                    style: udText(13, weight: FontWeight.w600, color: s.overdue ? udDue : udWarn),
                                  ),
                              ],
                            ),
                          ),
                          if (mobile != null) ...[
                            IconButton.filledTonal(
                              key: const Key('supplier-call'),
                              onPressed: () => _app.device.openLink(callLink(mobile)),
                              icon: const Icon(Icons.call_rounded),
                            ),
                            IconButton.filledTonal(
                              key: const Key('supplier-whatsapp'),
                              onPressed: () async {
                                if (!await _app.device.openLink(whatsAppAppLink(mobile, ''))) {
                                  await _app.device.openLink(whatsAppLink(mobile, ''));
                                }
                              },
                              icon: const Icon(Icons.chat_rounded),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _action('supplier-purchase', Icons.shopping_bag_outlined, 'Purchase', udDue,
                            () => _entry(SupplierEntryKind.purchase)),
                        const SizedBox(width: 8),
                        _action('supplier-payment', Icons.payments_outlined, 'Payment', udPaid,
                            () => _entry(SupplierEntryKind.payment)),
                        const SizedBox(width: 8),
                        _action('supplier-order', Icons.send_rounded, 'Order', udPurple, _order),
                      ],
                    ),
                    if (open.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text('Waiting for goods', style: udText(16, weight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      for (final o in open)
                        UdCard(
                          key: Key('order-${o.id}'),
                          padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(linesSummary(o.lines), style: udText(14, weight: FontWeight.w600)),
                              if (o.createdAt != null)
                                Text('Ordered ${whenLabel(o.createdAt!, _now)}', style: udText(12, color: udBody)),
                              Wrap(
                                alignment: WrapAlignment.end,
                                spacing: 4,
                                children: [
                                  TextButton(
                                    key: Key('order-cancel-${o.id}'),
                                    onPressed: () => _cancelOrder(o),
                                    child: const Text('Cancel order'),
                                  ),
                                  FilledButton(
                                    key: Key('order-receive-${o.id}'),
                                    onPressed: () => _entry(SupplierEntryKind.purchase, order: o),
                                    style: FilledButton.styleFrom(backgroundColor: udPaid),
                                    child: const Text('Goods received'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                    ],
                    const SizedBox(height: 16),
                    Text('History', style: udText(16, weight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    if (_entries != null && _entries!.isEmpty)
                      Text('No purchases or payments yet.', style: udText(13, color: udBody)),
                    for (final e in _entries ?? const <SupplierEntry>[])
                      _EntryTile(entry: e, now: _now, onTap: () => _delete(e)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _action(String key, IconData icon, String label, Color color, VoidCallback onTap) => Expanded(
    child: SizedBox(
      height: 52,
      child: FilledButton.icon(
        key: Key(key),
        onPressed: onTap,
        icon: Icon(icon, size: 20),
        label: Text(label, maxLines: 1),
        style: FilledButton.styleFrom(
          backgroundColor: color,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: udText(14, weight: FontWeight.w700),
        ),
      ),
    ),
  );
}

/// Asks why an entry is deleted. Returns the reason, or null if cancelled.
class _DeleteDialog extends StatefulWidget {
  const _DeleteDialog({required this.entry});

  final SupplierEntry entry;

  @override
  State<_DeleteDialog> createState() => _DeleteDialogState();
}

class _DeleteDialogState extends State<_DeleteDialog> {
  final _reason = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Delete this ${widget.entry.kind.label.toLowerCase()}?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(widget.entry.lines.isEmpty
              ? 'It stays in the history, crossed out, with your reason.'
              : 'It stays in the history, crossed out. Its items are taken back out of stock.'),
          TextField(
            key: const Key('delete-reason'),
            controller: _reason,
            autofocus: true,
            maxLength: 200,
            decoration: InputDecoration(labelText: 'Why?', errorText: _error, counterText: ''),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          key: const Key('delete-yes'),
          onPressed: () {
            final why = _reason.text.trim();
            if (why.isEmpty) {
              setState(() => _error = 'Write why it is being deleted');
            } else {
              Navigator.of(context).pop(why);
            }
          },
          style: FilledButton.styleFrom(backgroundColor: udDue),
          child: const Text('Delete'),
        ),
      ],
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.entry, required this.now, required this.onTap});

  final SupplierEntry entry;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final purchase = entry.kind == SupplierEntryKind.purchase;
    final color = entry.deleted ? udBody : (purchase ? udDue : udPaid);
    final strike = entry.deleted ? TextDecoration.lineThrough : null;
    final details = [
      if (entry.lines.isNotEmpty) linesSummary(entry.lines),
      if ((entry.note ?? '').isNotEmpty) entry.note!,
      if (entry.method != null) entry.method!.label,
      if (entry.dueDate != null) 'Pay by ${shortDay(entry.dueDate!)}',
    ];
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: entry.deleted ? const Color(0xFFF4F3F7) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Row(
              children: [
                Icon(purchase ? Icons.shopping_bag_outlined : Icons.payments_outlined, color: color, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(entry.kind.label, style: udText(14, weight: FontWeight.w700, decoration: strike)),
                      for (final d in details)
                        Text(d, maxLines: 2, overflow: TextOverflow.ellipsis, style: udText(12, color: udBody, decoration: strike)),
                      Text(whenLabel(entry.entryAt, now), style: udText(11, color: udBody)),
                      if (entry.deleted)
                        Text('Deleted: ${entry.deleteReason ?? ''}', style: udText(11, weight: FontWeight.w600, color: udDue)),
                      if (entry.pending)
                        Text('⏳ Waiting for internet to sync', style: udText(11, weight: FontWeight.w600, color: udWarn)),
                    ],
                  ),
                ),
                Text('${purchase ? '+' : '−'} ${rupees(entry.amountPaise)}',
                    style: udText(16, weight: FontWeight.w700, color: color, decoration: strike)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
