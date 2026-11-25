import 'package:flutter/material.dart';

import '../calendar/calendar_models.dart' show longDate;
import '../services/api_client.dart';
import '../services/app_services.dart';
import '../services/device_actions.dart';
import '../stock/stock_models.dart' show milli;
import '../supply/supply_page.dart' show askReason, askSure;
import '../translator/languages.dart';
import '../translator/voice_language.dart';
import '../widgets/whatsapp_icon.dart';
import '../udhaar/udhaar_models.dart' show rupees, whenLabel;
import '../udhaar/udhaar_widgets.dart';
import 'order_screen.dart';
import 'pay_supplier_screen.dart';
import 'supplier_code_screen.dart';
import 'supplier_entry_screen.dart';
import 'supplier_form_screen.dart';
import 'supplier_models.dart';
import 'supplier_products.dart';
import 'supplier_repository.dart';
import 'supplier_widgets.dart';

/// The tabs of a connected supplier.
enum _Tab { products, orders, history }

/// One supplier: what the shop owes, the pay-by date, purchases and payments
/// (never erased), and orders. A connected one opens with what they sell:
/// order it, and pay them.
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

  final _cart = Cart();
  _Tab _tab = _Tab.products;
  List<SupplierProduct>? _products;
  String? _productsError;
  String _search = '';
  AppLanguage _language = AppLanguage.english;

  /// UPI payments: "did it go through?" not answered yet.
  List<SupplierEntryDraft> _asking = const [];

  AppServices get _app => _services!;
  DateTime get _now => widget.now ?? DateTime.now();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_services != null) return;
    _services = ServicesScope.of(context);
    _load();
  }

  @override
  void dispose() {
    _cart.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final saved = await _app.suppliers.savedSupplier(_supplier.id);
    final asking = await _app.suppliers.asking(_supplier.id);
    if (!mounted) return;
    if (saved != null) _show(saved);
    setState(() => _asking = asking);
    setState(() => _busy = true);
    try {
      final fresh = await _app.suppliers.freshSupplier(_supplier.id);
      if (mounted) {
        _show(fresh);
        setState(() => _offline = false);
        if (fresh.supplier.connected) await _loadProducts();
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.isNetwork) {
        setState(() {
          _offline = true;
          if (_products == null) _productsError = 'Seeing products needs internet.';
        });
      } else {
        udNotify(context, e.message);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loadProducts() async {
    final language = await readVoiceLanguage(_app.settings);
    try {
      final products = await _app.suppliers.products(_supplier.id);
      if (mounted) {
        setState(() {
          _language = language;
          _products = products;
          _productsError = null;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _productsError = e.isNetwork ? 'Seeing products needs internet.' : e.message);
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
    final chosen = _supplier.connected ? _cart.lines(_products ?? const []) : const <EntryLine>[];
    if (chosen == null) {
      udNotify(context, 'Check the quantities');
      return;
    }
    final sent = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => OrderScreen(supplier: _supplier, chosen: chosen, now: widget.now)),
    );
    if (!mounted) return;
    if (sent == true && _supplier.connected) {
      // On WhatsApp they see it sent themselves.
      udNotify(context, 'Order sent to ${_supplier.name}');
      setState(() {
        _cart.clear();
        _tab = _Tab.orders;
      });
    }
    // A product may be gone, or not available any more.
    if (sent == true || _supplier.connected) await _load();
  }

  Future<void> _pay([SupplierOrder? order]) async {
    final result = await Navigator.of(context).push<EntryResult>(
      MaterialPageRoute(builder: (_) => PaySupplierScreen(supplier: _supplier, order: order)),
    );
    if (!mounted) return;
    if (result != null) _paidMessage(result == EntryResult.savedOffline);
    await _load(); // also asks again about a payment left unanswered
  }

  void _paidMessage(bool offline) => udNotify(
    context,
    offline
        ? 'Saved on the phone. It will sync when internet is back.'
        : 'Saved. It counts after ${_supplier.name} confirms it.',
  );

  Future<void> _answerAsking(SupplierEntryDraft draft, bool paid) async {
    try {
      if (paid) {
        final saved = await _app.suppliers.paid(_supplier.id, draft);
        if (mounted) _paidMessage(saved == EntrySaved.savedOffline);
      } else {
        await _app.suppliers.stopAsking(draft.clientRef);
      }
    } on ApiException catch (e) {
      if (mounted) udNotify(context, e.message);
    }
    if (mounted) await _load();
  }

  Future<void> _cancelOrder(SupplierOrder order) async {
    final sure = await askSure(
      context,
      title: 'Cancel this order?',
      text: order.paidSomething
          ? 'You paid ${rupees(order.paidPaise + order.payingPaise)} for it. That stays as your advance with ${_supplier.name}.'
          : linesSummary(order.lines),
      action: 'Cancel order',
      color: udDue,
    );
    if (!sure || !mounted) return;
    try {
      await _app.suppliers.cancelOrder(order.id);
      if (mounted) await _load();
    } on ApiException catch (e) {
      if (mounted) udNotify(context, e.isNetwork ? 'This needs internet.' : e.message);
    }
  }

  Future<void> _link(Future<Supplier> Function() action, String done) async {
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) udNotify(context, done);
    } on ApiException catch (e) {
      if (mounted) udNotify(context, e.isNetwork ? 'This needs internet.' : e.message);
    }
    if (mounted) await _load();
  }

  Future<void> _connect() async {
    if ((_supplier.mobile ?? '').isEmpty) {
      udNotify(context, 'Add the supplier\'s mobile number first');
      return;
    }
    final saved = await Navigator.of(context).push<Supplier>(
      MaterialPageRoute(
        builder: (_) => SupplierCodeScreen(
          name: _supplier.name,
          mobile: _supplier.mobile!,
          send: () => _app.suppliers.sendCode(_supplier.id),
          confirm: (code) => _app.suppliers.verify(_supplier.id, code),
        ),
      ),
    );
    if (!mounted) return;
    if (saved != null) {
      udNotify(
        context,
        saved.connected ? 'Connected with ${saved.name}' : 'Number verified. They connect when they join QBOX.',
      );
    }
    await _load();
  }

  Future<void> _disconnect() async {
    final on = _supplier.connected;
    if (on) {
      final sure = await askSure(
        context,
        title: 'Disconnect from ${_supplier.name}?',
        text: 'New entries will not be shared any more. They keep everything up to today.',
        action: 'Disconnect',
        color: udDue,
      );
      if (!sure || !mounted) return;
    }
    await _link(() => _app.suppliers.disconnect(_supplier.id), on ? 'Disconnected' : 'Taken back');
  }

  /// What the supplier wrote is right, or not.
  Future<void> _answerEntry(SupplierEntry e, {required bool right}) async {
    final goods = e.kind == SupplierEntryKind.purchase;
    Future<SupplierEntry> Function() send;
    if (right) {
      final sure = await askSure(
        context,
        title: goods ? 'Did these goods come?' : 'Did you pay ${rupees(e.amountPaise)}?',
        text: goods
            ? '${e.lines.isEmpty ? '' : '${linesSummary(e.lines)}\n\n'}${rupees(e.amountPaise)} is added to what you owe'
                '${e.lines.isEmpty ? '' : ', and the items go into your stock'}. This cannot be undone.'
            : 'After this, neither of you can delete it.',
        action: goods ? 'Yes, they came' : 'Yes, I paid',
        color: udPaid,
      );
      if (!sure) return;
      send = () => _app.suppliers.confirmEntry(e.id!);
    } else {
      final reason = await askReason(
        context,
        title: 'Not right?',
        text: '${_supplier.name} will see this and can correct it.',
        action: 'Send',
      );
      if (reason == null) return;
      send = () => _app.suppliers.disputeEntry(e.id!, reason);
    }
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      await send();
      if (mounted) udNotify(context, right ? 'Confirmed' : 'Sent to ${_supplier.name}');
    } on ApiException catch (error) {
      if (mounted) udNotify(context, error.isNetwork ? 'This needs internet.' : error.message);
    }
    if (mounted) await _load();
  }

  Future<void> _delete(SupplierEntry entry) async {
    if (entry.id == null || entry.deleted) return;
    if (entry.bySupplier && entry.confirm != Confirm.confirmed) {
      udNotify(context, '${_supplier.name} wrote this, so only they can delete it.');
      return;
    }
    if (entry.confirm == Confirm.confirmed) {
      udNotify(context, 'Both of you agreed on this, so it cannot be deleted. Add a new entry to correct it.');
      return;
    }
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
    final chosen = _cart.lines(_products ?? const []);
    final ordering = s.connected && _tab == _Tab.products && (chosen == null || chosen.isNotEmpty);
    return Scaffold(
      backgroundColor: udBackground,
      body: SafeArea(
        child: Column(
          children: [
            UdHeader(title: s.name, subtitle: s.supplies ?? 'Supplier', busy: _busy, actions: [_menu(s)]),
            if (_offline)
              const UdBanner(icon: Icons.wifi_off_rounded, text: 'Offline: showing the saved copy. Entries are kept on the phone.'),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  children: [
                    _account(s),
                    for (final d in _asking) _askCard(d),
                    if (s.connected)
                      for (final e in (_entries ?? const <SupplierEntry>[]).where((e) => e.toAnswer)) _theirCard(e),
                    const SizedBox(height: 12),
                    if (s.connected) ...[
                      _tabs(),
                      const SizedBox(height: 12),
                      ...switch (_tab) {
                        _Tab.products => _productList(),
                        _Tab.orders => _orderList(),
                        _Tab.history => _history(),
                      },
                    ] else ...[
                      _linkCard(s),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          _action('supplier-purchase', Icons.shopping_bag_outlined, 'Bought', udDue,
                              () => _entry(SupplierEntryKind.purchase)),
                          const SizedBox(width: 8),
                          _action('supplier-payment', Icons.payments_outlined, 'Payment', udPaid,
                              () => _entry(SupplierEntryKind.payment)),
                          const SizedBox(width: 8),
                          _action('supplier-order', Icons.send_rounded, 'Order', udPurple, _order),
                        ],
                      ),
                      if (_orders.any(_shownOrder)) ...[
                        const SizedBox(height: 16),
                        Text('Waiting for goods', style: udText(16, weight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        for (final o in _orders.where(_shownOrder)) _orderCard(o),
                      ],
                      const SizedBox(height: 16),
                      Text('History', style: udText(16, weight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      ..._history(),
                    ],
                  ],
                ),
              ),
            ),
            if (ordering) _cartBar(chosen),
          ],
        ),
      ),
    );
  }

  Widget _menu(Supplier s) => PopupMenuButton<VoidCallback>(
    key: const Key('supplier-menu'),
    iconColor: udPurple,
    onSelected: (action) => action(),
    itemBuilder: (_) => [
      if (s.connected)
        PopupMenuItem(
          key: const Key('supplier-purchase'),
          value: () => _entry(SupplierEntryKind.purchase),
          child: const Text('Bought without an order'),
        ),
      PopupMenuItem(key: const Key('supplier-edit'), value: _edit, child: const Text('Edit details')),
      if (s.connected)
        PopupMenuItem(key: const Key('supplier-disconnect'), value: _disconnect, child: const Text('Disconnect')),
      PopupMenuItem(key: const Key('supplier-remove'), value: _remove, child: const Text('Remove supplier')),
    ],
  );

  Widget _account(Supplier s) {
    final mobile = s.mobile;
    return UdCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.balancePaise > 0 ? 'You owe' : (s.balancePaise < 0 ? 'Paid in advance' : 'All paid'),
                      style: udText(13, color: udBody),
                    ),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        rupees(s.balancePaise),
                        key: const Key('supplier-balance'),
                        style: udText(32, weight: FontWeight.w800, color: s.balancePaise > 0 ? udDue : udPaid),
                      ),
                    ),
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
                  icon: const WhatsAppIcon(),
                  tooltip: 'WhatsApp',
                ),
              ],
            ],
          ),
          if (s.connected) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.link_rounded, size: 18, color: udPaid),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Connected in QBOX',
                    key: const Key('supplier-link'),
                    style: udText(12, weight: FontWeight.w600, color: udPaid),
                  ),
                ),
                FilledButton.icon(
                  key: const Key('supplier-pay'),
                  onPressed: () => _pay(),
                  icon: const Icon(Icons.currency_rupee_rounded, size: 18),
                  label: const Text('Pay'),
                  style: FilledButton.styleFrom(backgroundColor: udPaid),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// A UPI payment that was not answered: the phone may have closed QBOX.
  Widget _askCard(SupplierEntryDraft d) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: UdCard(
      key: const Key('supplier-asking'),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Did your UPI payment of ${rupees(d.amountPaise)} go through?',
            style: udText(14, weight: FontWeight.w700),
          ),
          Wrap(
            spacing: 8,
            children: [
              FilledButton(
                key: const Key('asking-yes'),
                onPressed: _busy ? null : () => _answerAsking(d, true),
                style: FilledButton.styleFrom(backgroundColor: udPaid),
                child: const Text('Yes, I paid'),
              ),
              TextButton(
                key: const Key('asking-no'),
                onPressed: _busy ? null : () => _answerAsking(d, false),
                child: const Text('No'),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  /// Something the supplier wrote, to be checked.
  Widget _theirCard(SupplierEntry e) {
    final goods = e.kind == SupplierEntryKind.purchase;
    final details = [
      if (e.lines.isNotEmpty) linesSummary(e.lines),
      if ((e.note ?? '').isNotEmpty) e.note!,
      if (e.method != null) e.method!.label,
      whenLabel(e.entryAt, _now),
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: UdCard(
        key: Key('their-${e.id}'),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              goods
                  ? '${_supplier.name} wrote: goods given, ${rupees(e.amountPaise)}'
                  : '${_supplier.name} wrote: you paid ${rupees(e.amountPaise)}',
              style: udText(14, weight: FontWeight.w700),
            ),
            for (final d in details) Text(d, style: udText(12, color: udBody)),
            const SizedBox(height: 2),
            UdBadge(
              goods ? 'Not counted until you say yes' : 'Already taken off what you owe',
              color: goods ? udWarn : udPaid,
            ),
            Wrap(
              spacing: 8,
              children: [
                FilledButton(
                  key: Key('their-yes-${e.id}'),
                  onPressed: _busy ? null : () => _answerEntry(e, right: true),
                  style: FilledButton.styleFrom(backgroundColor: udPaid),
                  child: const Text('Yes, right'),
                ),
                TextButton(
                  key: Key('their-no-${e.id}'),
                  onPressed: _busy ? null : () => _answerEntry(e, right: false),
                  style: TextButton.styleFrom(foregroundColor: udDue),
                  child: const Text('Not right'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _tabs() {
    final open = _orders.where((o) => o.open).length;
    return Wrap(
      spacing: 8,
      children: [
        for (final (tab, label) in [
          (_Tab.products, 'Products'),
          (_Tab.orders, open == 0 ? 'Orders' : 'Orders ($open)'),
          (_Tab.history, 'History'),
        ])
          ChoiceChip(
            key: Key('tab-${tab.name}'),
            label: Text(label),
            labelStyle: udText(14, weight: FontWeight.w600, color: _tab == tab ? Colors.white : udInk),
            selected: _tab == tab,
            selectedColor: udPurple,
            checkmarkColor: Colors.white,
            backgroundColor: Colors.white,
            onSelected: (_) => setState(() => _tab = tab),
          ),
      ],
    );
  }

  List<Widget> _productList() {
    final products = _products;
    final shown = [
      for (final p in products ?? const <SupplierProduct>[])
        if (productMatches(p, _search)) p,
    ];
    return [
      if (_productsError != null)
        UdBanner(
          key: const Key('products-error'),
          icon: Icons.wifi_off_rounded,
          text: _productsError!,
          actionLabel: 'Retry',
          onAction: _busy ? null : _load,
        ),
      if ((products?.length ?? 0) > 6)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: TextField(
            key: const Key('products-search'),
            onChanged: (v) => setState(() => _search = v),
            decoration: InputDecoration(
              hintText: 'Search in any language',
              isDense: true,
              filled: true,
              fillColor: Colors.white,
              prefixIcon: const Icon(Icons.search_rounded, color: udBody),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
            ),
          ),
        ),
      if (products != null && products.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 28),
          child: Text(
            '${_supplier.name} has not added products yet.',
            key: const Key('products-empty'),
            textAlign: TextAlign.center,
            style: udText(14, color: udBody),
          ),
        ),
      if (products != null && products.isNotEmpty && shown.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Center(child: Text('No products match.', style: udText(14, color: udBody))),
        ),
      for (final p in shown)
        SupplierProductTile(
          key: Key('product-${p.id}'),
          product: p,
          cart: _cart,
          language: _language,
          onChanged: () => setState(() {}),
        ),
      if (products != null)
        TextButton.icon(
          key: const Key('supplier-order'),
          onPressed: _busy ? null : _order,
          icon: const Icon(Icons.edit_outlined, size: 20),
          label: const Text('Not in the list? Type what you need'),
        ),
    ];
  }

  Widget _cartBar(List<EntryLine>? chosen) {
    final total = (chosen ?? const <EntryLine>[]).fold<int>(
      0,
      (sum, l) => sum + ((l.costPaise ?? 0) * l.qtyMilli / milli).round(),
    );
    final unpriced = (chosen ?? const <EntryLine>[]).any((l) => l.costPaise == null);
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  chosen == null
                      ? 'Check the quantities'
                      : chosen.length == 1
                      ? '1 item'
                      : '${chosen.length} items',
                  style: udText(12, color: chosen == null ? udDue : udBody),
                ),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '${unpriced ? 'From ' : ''}${rupees(total)}',
                    key: const Key('cart-total'),
                    style: udText(18, weight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            height: 52,
            child: FilledButton(
              key: const Key('cart-order'),
              onPressed: _busy || chosen == null ? null : _order,
              style: FilledButton.styleFrom(
                backgroundColor: udPurple,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                textStyle: udText(15, weight: FontWeight.w700),
              ),
              child: const Text('Place order'),
            ),
          ),
        ],
      ),
    );
  }

  /// Open orders, and the latest ones the supplier rejected.
  bool _shownOrder(SupplierOrder o) =>
      o.open || _orders.where((x) => x.status == OrderStatus.rejected).take(3).contains(o);

  List<Widget> _orderList() {
    final open = _orders.where((o) => o.open).toList();
    final past = _orders.where((o) => !o.open).take(30).toList();
    return [
      if (_orders.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 28),
          child: Text(
            'No orders yet. Choose from Products.',
            key: const Key('orders-empty'),
            textAlign: TextAlign.center,
            style: udText(14, color: udBody),
          ),
        ),
      for (final o in open) _orderCard(o),
      if (past.isNotEmpty) ...[
        const SizedBox(height: 8),
        Text('Past orders', style: udText(16, weight: FontWeight.w700)),
        const SizedBox(height: 8),
        for (final o in past) _orderCard(o),
      ],
    ];
  }

  List<Widget> _history() => [
    if (_entries != null && _entries!.isEmpty)
      Text('No purchases or payments yet.', style: udText(13, color: udBody)),
    for (final e in _entries ?? const <SupplierEntry>[]) _EntryTile(entry: e, now: _now, onTap: () => _delete(e)),
  ];

  Widget _orderCard(SupplierOrder o) {
    final s = _supplier;
    final plan = payPlanText(o.payPlan, o.payBy, _now);
    // They said what it costs: it can be paid.
    final payable = s.connected &&
        o.leftPaise > 0 &&
        (o.status == OrderStatus.accepted || o.status == OrderStatus.dispatched);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: UdCard(
        key: Key('order-${o.id}'),
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(linesSummary(o.lines), style: udText(14, weight: FontWeight.w600)),
            if (o.createdAt != null)
              Text('Ordered ${whenLabel(o.createdAt!, _now)}', style: udText(12, color: udBody)),
            if (o.shared || !o.open) ..._answer(o),
            if (plan != null)
              Text(
                o.payPlan == PayPlan.upi && o.status == OrderStatus.sent ? '$plan, after they accept' : plan,
                key: Key('order-plan-${o.id}'),
                style: udText(12, color: udBody),
              ),
            if (o.paidPaise > 0)
              Text('Paid ${rupees(o.paidPaise)}', style: udText(12, weight: FontWeight.w600, color: udPaid)),
            if (o.payingPaise > 0)
              Text(
                '${rupees(o.payingPaise)} paid: waiting for them to confirm',
                style: udText(12, weight: FontWeight.w600, color: udWarn),
              ),
            if (o.open)
              Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  FilledButton(
                    key: Key('order-receive-${o.id}'),
                    onPressed: () => _entry(SupplierEntryKind.purchase, order: o),
                    style: FilledButton.styleFrom(backgroundColor: udPaid),
                    child: const Text('Goods received'),
                  ),
                  if (payable)
                    FilledButton(
                      key: Key('order-pay-${o.id}'),
                      onPressed: () => _pay(o),
                      style: FilledButton.styleFrom(backgroundColor: udPurple),
                      child: Text('Pay ${rupees(o.leftPaise)}'),
                    ),
                  if (!(s.connected && o.status == OrderStatus.dispatched))
                    TextButton(
                      key: Key('order-cancel-${o.id}'),
                      onPressed: () => _cancelOrder(o),
                      child: const Text('Cancel order'),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  /// What the connected supplier answered to an order.
  List<Widget> _answer(SupplierOrder o) {
    final missing = o.lines.where((l) => !l.available).map((l) => l.name).join(', ');
    return [
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            UdBadge(
              switch (o.status) {
                OrderStatus.sent => 'Waiting for their answer',
                OrderStatus.rejected => 'They rejected it',
                _ => o.status.label,
              },
              color: switch (o.status) {
                OrderStatus.sent => udWarn,
                OrderStatus.rejected => udDue,
                OrderStatus.received => udPaid,
                OrderStatus.cancelled => udBody,
                _ => udPurple,
              },
            ),
            if (o.totalPaise != null)
              Text('Bill ${rupees(o.totalPaise!)}', style: udText(14, weight: FontWeight.w700)),
          ],
        ),
      ),
      if (missing.isNotEmpty) Text('Not available: $missing', style: udText(12, color: udDue)),
      if ((o.answerNote ?? '').isNotEmpty) Text('They wrote: ${o.answerNote}', style: udText(12, color: udBody)),
    ];
  }

  /// Connecting with the supplier's own QBOX account.
  Widget _linkCard(Supplier s) {
    final status = s.link?.status;
    final (icon, color, text) = switch (status) {
      LinkStatus.asked => (Icons.hourglass_top_rounded, udWarn, 'They joined QBOX. Waiting for their yes.'),
      LinkStatus.declined => (
        Icons.link_off_rounded,
        udDue,
        'They did not connect${(s.link?.reason ?? '').isEmpty ? '.' : ': ${s.link!.reason}'}',
      ),
      LinkStatus.ended => (Icons.link_off_rounded, udBody, 'Disconnected.'),
      _ when s.verified => (
        Icons.verified_user_outlined,
        udPaid,
        'Number verified. You connect when they join QBOX as a supplier.',
      ),
      _ => (Icons.link_rounded, udPurple, 'Connect with a code: see their products, order and pay here.'),
    };
    return UdCard(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(text, key: const Key('supplier-link'), style: udText(13, weight: FontWeight.w600)),
              ),
            ],
          ),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 4,
            children: [
              if (!(s.verified && status == null))
                TextButton(
                  key: const Key('supplier-connect'),
                  onPressed: _busy ? null : _connect,
                  child: const Text('Connect with code'),
                ),
              if (status == LinkStatus.asked)
                TextButton(
                  key: const Key('supplier-disconnect'),
                  onPressed: _busy ? null : _disconnect,
                  style: TextButton.styleFrom(foregroundColor: udDue),
                  child: const Text('Take back'),
                ),
            ],
          ),
        ],
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
      title: Text('Delete this ${widget.entry.kind == SupplierEntryKind.purchase ? 'purchase' : 'payment'}?'),
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
    final color = entry.deleted ? udBody : (!entry.counts ? udWarn : (purchase ? udDue : udPaid));
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
                      if (entry.bySupplier) Text('Written by them', style: udText(11, color: udBody)),
                      if (!entry.deleted && entry.confirm != null) _confirmBadge(entry),
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

  Widget _confirmBadge(SupplierEntry e) {
    final payment = e.kind == SupplierEntryKind.payment;
    if (e.bySupplier) {
      return switch (e.confirm!) {
        Confirm.waiting => UdBadge(payment ? 'Please check' : 'Not counted until you say yes', color: udWarn),
        Confirm.confirmed => const UdBadge('Both agreed', color: udPaid),
        Confirm.disputed => UdBadge('You said: ${e.disputeReason ?? 'not right'}'),
        Confirm.closed => UdBadge(payment ? 'Not confirmed' : 'Never agreed: not counted', color: udBody),
      };
    }
    return switch (e.confirm!) {
      Confirm.waiting => UdBadge(payment ? 'Not counted until they confirm' : 'They have not checked yet', color: udWarn),
      Confirm.confirmed => const UdBadge('Both agreed', color: udPaid),
      Confirm.disputed => UdBadge('They say not right: ${e.disputeReason ?? ''}'),
      Confirm.closed => const UdBadge('Not confirmed', color: udBody),
    };
  }
}
