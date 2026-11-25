import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../services/app_services.dart';
import '../translator/languages.dart';
import '../udhaar/udhaar_models.dart' show rupees, whenLabel;
import '../udhaar/udhaar_widgets.dart';
import 'item_form_screen.dart';
import 'stock_models.dart';
import 'stock_repository.dart';
import 'stock_widgets.dart';

/// One item: how much is left, its value, the buttons to add, sell or correct
/// stock, and its full history (never erased).
class ItemScreen extends StatefulWidget {
  const ItemScreen({required this.item, this.language = AppLanguage.english, this.now, super.key});

  final StockItem item;
  final AppLanguage language;
  final DateTime? now;

  @override
  State<ItemScreen> createState() => _ItemScreenState();
}

class _ItemScreenState extends State<ItemScreen> {
  AppServices? _services;
  late StockItem _item = widget.item;
  List<StockMove>? _moves;
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
    final saved = await _app.stock.savedItem(_item.id);
    if (saved != null && mounted) {
      setState(() {
        _item = saved.item;
        _moves = saved.moves;
      });
    }
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      final fresh = await _app.stock.freshItem(_item.id);
      if (mounted) {
        setState(() {
          _item = fresh.item;
          _moves = fresh.moves;
          _offline = false;
        });
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

  Future<void> _move(MoveKind kind) async {
    final before = _item;
    MoveSaved? outcome;
    final draft = await showMoveSheet(
      context,
      item: _item,
      kind: kind,
      save: (d) async => outcome = await _app.stock.addMove(before.id, d),
    );
    if (draft == null || !mounted) return;
    await notifyIfNowLow(_app, before, draft);
    if (!mounted) return;
    udNotify(
      context,
      outcome == MoveSaved.savedOffline
          ? 'Saved on the phone: ${moveSummary(before, draft)}. It will sync when internet is back.'
          : 'Saved: ${moveSummary(before, draft)}',
    );
    await _load();
  }

  Future<void> _edit() async {
    final saved = await Navigator.of(context).push<StockItem>(
      MaterialPageRoute(builder: (_) => ItemFormScreen(item: _item)),
    );
    if (saved != null && mounted) {
      udNotify(context, 'Saved');
      await _load();
    }
  }

  Future<void> _remove() async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove ${_item.name}?'),
        content: const Text('It leaves your stock list. Its history is kept.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(
            key: const Key('item-remove-yes'),
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: udDue),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    try {
      await _app.stock.archiveItem(_item.id);
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (mounted) udNotify(context, e.isNetwork ? 'Removing an item needs internet.' : e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = _item;
    final local = localName(item, widget.language);
    return Scaffold(
      backgroundColor: udBackground,
      body: SafeArea(
        child: Column(
          children: [
            UdHeader(
              title: item.name,
              subtitle: local ?? 'Stock',
              busy: _busy,
              actions: [
                IconButton(
                  key: const Key('item-edit'),
                  onPressed: _edit,
                  icon: const Icon(Icons.edit_outlined, color: udPurple),
                  tooltip: 'Change',
                ),
                IconButton(
                  key: const Key('item-remove'),
                  onPressed: _remove,
                  icon: const Icon(Icons.delete_outline_rounded, color: udDue),
                  tooltip: 'Remove from stock',
                ),
              ],
            ),
            if (_offline)
              const UdBanner(icon: Icons.wifi_off_rounded, text: 'Offline: showing the saved copy. New entries are kept on the phone.'),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  children: [
                    UdCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text('In stock', style: udText(13, color: udBody)),
                              const Spacer(),
                              if (item.isLow) const UdBadge('Running low'),
                            ],
                          ),
                          Text(
                            formatQty(item.quantityMilli, item.unit),
                            key: const Key('item-qty'),
                            style: udText(34, weight: FontWeight.w800, color: qtyColor(item)),
                          ),
                          if (item.valuePaise != null)
                            Text('Worth ${rupees(item.valuePaise!)}', style: udText(13, color: udBody)),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 12,
                            children: [
                              if (item.costPaise != null)
                                Text('Buy ${rupees(item.costPaise!)}/${item.unit.short}', style: udText(12, color: udBody)),
                              if (item.pricePaise != null)
                                Text('Sell ${rupees(item.pricePaise!)}/${item.unit.short}', style: udText(12, color: udBody)),
                              if (item.alertMilli != null)
                                Text('Warn at ${formatQty(item.alertMilli!, item.unit)}', style: udText(12, color: udBody)),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _action('item-in', Icons.add_rounded, 'Stock in', udPaid, () => _move(MoveKind.stockIn)),
                        const SizedBox(width: 8),
                        _action('item-out', Icons.remove_rounded, 'Sold', udDue, () => _move(MoveKind.out)),
                        const SizedBox(width: 8),
                        _action('item-adjust', Icons.edit_outlined, 'Correct', udWarn, () => _move(MoveKind.adjust)),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text('History', style: udText(16, weight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    if (_moves != null && _moves!.isEmpty)
                      Text('Nothing yet.', style: udText(13, color: udBody)),
                    for (final m in _moves ?? const <StockMove>[]) _MoveTile(move: m, unit: item.unit, now: _now),
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
        label: FittedBox(fit: BoxFit.scaleDown, child: Text(label, maxLines: 1)),
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

class _MoveTile extends StatelessWidget {
  const _MoveTile({required this.move, required this.unit, required this.now});

  final StockMove move;
  final StockUnit unit;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final effect = move.effect;
    final color = switch (move.kind) {
      MoveKind.stockIn => udPaid,
      MoveKind.out => udDue,
      MoveKind.adjust => udWarn,
    };
    final icon = switch (move.kind) {
      MoveKind.stockIn => Icons.south_west_rounded,
      MoveKind.out => Icons.north_east_rounded,
      MoveKind.adjust => Icons.edit_outlined,
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
                Text(move.kind.label, style: udText(14, weight: FontWeight.w700)),
                if ((move.note ?? '').isNotEmpty)
                  Text(move.note!, maxLines: 2, overflow: TextOverflow.ellipsis, style: udText(13, color: udBody)),
                Text(whenLabel(move.moveAt, now), style: udText(11, color: udBody)),
                if (move.pending)
                  Text('⏳ Waiting for internet to sync', style: udText(11, weight: FontWeight.w600, color: udWarn)),
              ],
            ),
          ),
          Text(
            '${effect >= 0 ? '+' : '−'} ${formatQty(effect.abs(), unit)}',
            style: udText(16, weight: FontWeight.w700, color: color),
          ),
        ],
      ),
    );
  }
}
