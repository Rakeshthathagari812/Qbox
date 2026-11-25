import 'package:flutter/material.dart';

import '../suppliers/supplier_models.dart' show Confirm, SupplierEntryKind, shortDay;
import '../udhaar/udhaar_models.dart' show rupees, whenLabel;
import '../udhaar/udhaar_widgets.dart';
import 'supply_entry_screen.dart';
import 'supply_models.dart';
import 'supply_order_screen.dart';
import 'supply_page.dart';

/// One shop's account with this supplier: the balance, what must be confirmed,
/// open orders and every entry.
class SupplyShopScreen extends StatefulWidget {
  const SupplyShopScreen({required this.shop, this.now, super.key});

  final SupplyShop shop;
  final DateTime? now;

  @override
  State<SupplyShopScreen> createState() => _SupplyShopScreenState();
}

class _SupplyShopScreenState extends State<SupplyShopScreen> with SupplyPage<SupplyShopScreen, SupplyShopDetail> {
  @override
  Future<SupplyShopDetail?> loadSaved() => app.supply.savedShop(widget.shop.linkId);

  @override
  Future<SupplyShopDetail> loadFresh() => app.supply.shop(widget.shop.linkId);

  SupplyShop get _shop => data?.shop ?? widget.shop;

  Future<void> _write(SupplierEntryKind kind) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => SupplyEntryScreen(shop: _shop, kind: kind)),
    );
    if (saved != true || !mounted) return;
    udNotify(context, 'Saved. ${_shop.name} can see it.');
    await load();
  }

  Future<void> _delete(SupplyEntry e) async {
    final reason = await askReason(
      context,
      title: 'Delete this?',
      text: 'It stays in the history, crossed out. ${_shop.name} sees why. Goods you count come back to your stock.',
      action: 'Delete',
    );
    if (reason == null || !mounted) return;
    await act(() => app.supply.api.deleteEntry(e.id, reason), 'Deleted');
  }

  Future<void> _end() async {
    final sure = await askSure(
      context,
      title: 'Disconnect from ${_shop.name}?',
      text: 'New orders, purchases and payments will not be shared any more. You keep everything up to today.',
      action: 'Disconnect',
      color: udDue,
    );
    if (!sure || !mounted) return;
    await act(() => app.supply.api.endShop(_shop.linkId), 'Disconnected');
  }

  Future<void> _openOrder(SupplyOrder order) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => SupplyOrderScreen(order: order, now: widget.now)),
    );
    if (mounted) await load();
  }

  @override
  Widget build(BuildContext context) {
    final s = _shop;
    final now = widget.now ?? DateTime.now();
    final entries = data?.entries ?? const <SupplyEntry>[];
    final orders = (data?.orders ?? const <SupplyOrder>[]).where((o) => o.status.open).toList();
    final agreed = s.connectedAt == null ? '' : ', agreed ${whenLabel(s.connectedAt!, now)}';
    return Scaffold(
      backgroundColor: udBackground,
      body: SafeArea(
        child: Column(
          children: [
            UdHeader(
              title: s.name,
              subtitle: s.connected ? s.category : 'Disconnected',
              busy: busy,
              actions: [
                ...contactButtons(s.phone, 'supply'),
                if (s.connected)
                  PopupMenuButton<String>(
                    key: const Key('supply-menu'),
                    iconColor: udPurple,
                    onSelected: (_) => _end(),
                    itemBuilder: (_) => const [PopupMenuItem(value: 'end', child: Text('Disconnect'))],
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
                        children: [
                          Text(
                            s.balancePaise < 0 ? 'Paid in advance' : 'They owe you',
                            style: udText(13, color: udBody),
                          ),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              rupees(s.balancePaise),
                              key: const Key('supply-balance'),
                              style: udText(32, weight: FontWeight.w800, color: s.balancePaise > 0 ? udDue : udPaid),
                            ),
                          ),
                          Text(
                            'Opening balance ${rupees(s.openingPaise)}${s.openingPaise < 0 ? ' advance' : ''}$agreed',
                            key: const Key('supply-opening'),
                            style: udText(12, color: udBody),
                          ),
                        ],
                      ),
                    ),
                    if (s.connected) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          _action('supply-give', Icons.north_east_rounded, 'Goods given', udDue, SupplierEntryKind.purchase),
                          const SizedBox(width: 10),
                          _action('supply-got', Icons.south_west_rounded, 'Got money', udPaid, SupplierEntryKind.payment),
                        ],
                      ),
                    ],
                    if (orders.isNotEmpty) ...[
                      _heading('Orders'),
                      for (final o in orders) SupplyOrderTile(order: o, now: now, onTap: () => _openOrder(o)),
                    ],
                    _heading('Account'),
                    if (data != null && entries.isEmpty)
                      Text(
                        'Nothing written since you connected.',
                        key: const Key('supply-no-entries'),
                        style: udText(13, color: udBody),
                      ),
                    for (final e in entries) _entry(e, now, s.connected),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _action(String key, IconData icon, String label, Color color, SupplierEntryKind kind) => Expanded(
    child: SizedBox(
      height: 52,
      child: FilledButton.icon(
        key: Key(key),
        onPressed: busy ? null : () => _write(kind),
        icon: Icon(icon, size: 20),
        label: FittedBox(fit: BoxFit.scaleDown, child: Text(label, maxLines: 1)),
        style: FilledButton.styleFrom(
          backgroundColor: color,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: udText(14, weight: FontWeight.w700),
        ),
      ),
    ),
  );

  Widget _heading(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(2, 16, 2, 8),
    child: Text(text, style: udText(16, weight: FontWeight.w700)),
  );

  Widget _entry(SupplyEntry e, DateTime now, bool connected) {
    final strike = e.deleted ? TextDecoration.lineThrough : null;
    final color = e.deleted
        ? udBody
        : !e.counts
        ? udWarn
        : e.payment
        ? udPaid
        : udDue;
    final details = [
      if (e.lines.isNotEmpty) supplyLinesText(e.lines),
      if ((e.note ?? '').isNotEmpty) e.note!,
      if (e.method != null) e.method!.label,
      if (e.dueDate != null) 'Will pay by ${shortDay(e.dueDate!, now)}',
      if (e.bySupplier) 'Written by you',
    ];
    final open = connected && !e.deleted && e.confirm != Confirm.confirmed && e.confirm != Confirm.closed;
    final answerable = open && !e.bySupplier && (e.confirm == Confirm.waiting || e.confirm == Confirm.disputed);
    return Container(
      key: Key('supply-entry-${e.id}'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      decoration: BoxDecoration(
        color: e.deleted ? const Color(0xFFF4F3F7) : Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(e.payment ? Icons.south_west_rounded : Icons.north_east_rounded, color: color, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      e.payment ? 'They paid' : 'Goods given',
                      style: udText(14, weight: FontWeight.w700, decoration: strike),
                    ),
                    for (final d in details)
                      Text(d, maxLines: 3, overflow: TextOverflow.ellipsis, style: udText(12, color: udBody)),
                    Text(whenLabel(e.entryAt, now), style: udText(11, color: udBody)),
                    const SizedBox(height: 2),
                    if (e.deleted)
                      Text(
                        '${e.bySupplier ? 'You deleted it' : 'Deleted by the shop'}: ${e.deleteReason ?? ''}',
                        style: udText(11, weight: FontWeight.w600, color: udDue),
                      )
                    else
                      _badge(e),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${e.payment ? '−' : '+'} ${rupees(e.amountPaise)}',
                style: udText(15, weight: FontWeight.w700, color: color, decoration: strike),
              ),
            ],
          ),
          if (open && e.bySupplier)
            TextButton(
              key: Key('entry-delete-${e.id}'),
              onPressed: busy ? null : () => _delete(e),
              style: TextButton.styleFrom(foregroundColor: udDue),
              child: const Text('Delete'),
            ),
          if (answerable)
            Wrap(
              spacing: 8,
              children: [
                FilledButton(
                  key: Key('entry-yes-${e.id}'),
                  onPressed: busy ? null : () => confirmEntry(e, _shop.name),
                  style: FilledButton.styleFrom(backgroundColor: udPaid),
                  child: Text(e.payment ? 'Received' : 'Right'),
                ),
                if (e.confirm == Confirm.waiting)
                  TextButton(
                    key: Key('entry-no-${e.id}'),
                    onPressed: busy ? null : () => disputeEntry(e, _shop.name),
                    style: TextButton.styleFrom(foregroundColor: udDue),
                    child: Text(e.payment ? 'Not received' : 'Not right'),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _badge(SupplyEntry e) => e.bySupplier
      ? switch (e.confirm) {
          Confirm.waiting => UdBadge(
            e.payment ? 'The shop has not checked yet' : 'Not counted until the shop says yes',
            color: udWarn,
          ),
          Confirm.confirmed => const UdBadge('Both agreed', color: udPaid),
          Confirm.disputed => UdBadge('The shop says not right: ${e.disputeReason ?? ''}'),
          Confirm.closed => UdBadge(e.payment ? 'Not confirmed' : 'Never agreed: not counted', color: udBody),
        }
      : switch (e.confirm) {
    Confirm.waiting => UdBadge(e.payment ? 'Not counted until you confirm' : 'Please check', color: udWarn),
    Confirm.confirmed => const UdBadge('Confirmed', color: udPaid),
    Confirm.disputed => UdBadge('You said: ${e.disputeReason ?? 'not right'}'),
    Confirm.closed => UdBadge(e.payment ? 'Never confirmed: not counted' : 'Never confirmed', color: udBody),
  };
}
