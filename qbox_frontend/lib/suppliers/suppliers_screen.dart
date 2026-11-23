import 'package:flutter/material.dart';

import '../calendar/calendar_models.dart' show longDate;
import '../calendar/reminders.dart';
import '../services/api_client.dart';
import '../services/app_services.dart';
import '../udhaar/udhaar_models.dart' show rupees;
import '../udhaar/udhaar_widgets.dart';
import 'supplier_form_screen.dart';
import 'supplier_models.dart';
import 'supplier_screen.dart';
import 'supplier_widgets.dart';

/// Opens the supplier list (the "Supplier" home tile).
Widget openSuppliers(BuildContext context) => const SuppliersScreen();

/// Pay-by reminders for every supplier with money due on a date.
List<DueReminder> dueReminders(SupplierBook book) => [
  for (final s in book.suppliers)
    if (s.nextDue != null && s.balancePaise > 0)
      DueReminder(
        id: s.id,
        day: s.nextDue!,
        title: 'Pay ${s.name} today',
        body: 'You owe ${rupees(s.balancePaise)}. Due today, ${longDate(s.nextDue!)}.',
      ),
];

/// Everyone the shop buys from, what it owes each, and pay-by dates.
class SuppliersScreen extends StatefulWidget {
  const SuppliersScreen({this.now, super.key});

  final DateTime? now;

  @override
  State<SuppliersScreen> createState() => _SuppliersScreenState();
}

class _SuppliersScreenState extends State<SuppliersScreen> {
  AppServices? _services;
  SupplierBook? _book;
  bool _syncing = false;
  bool _offline = false;
  int _waiting = 0;
  String _search = '';

  AppServices get _app => _services!;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_services != null) return;
    _services = ServicesScope.of(context);
    _start();
  }

  Future<void> _start() async {
    final saved = await _app.suppliers.savedBook();
    final waiting = await _app.suppliers.pendingCount();
    if (!mounted) return;
    setState(() {
      _book = saved;
      _waiting = waiting;
    });
    await _sync();
  }

  Future<void> _sync() async {
    setState(() => _syncing = true);
    try {
      final (sent, refused) = await _app.suppliers.sendPending();
      final book = await _app.suppliers.freshBook();
      if (!mounted) return;
      setState(() {
        _book = book;
        _offline = false;
      });
      final dues = dueReminders(book);
      if (dues.isNotEmpty) await _app.reminders.askPermission();
      await _app.reminders.syncDues(dues);
      if (!mounted) return;
      if (refused.isNotEmpty) {
        udNotify(context, 'An offline entry could not be saved: ${refused.first}');
      } else if (sent > 0) {
        udNotify(context, sent == 1 ? '1 offline entry is now saved' : '$sent offline entries are now saved');
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.isNetwork) {
        final saved = await _app.suppliers.savedBook();
        if (mounted) {
          setState(() {
            _offline = true;
            _book = saved ?? _book;
          });
        }
      } else {
        udNotify(context, e.message);
      }
    } finally {
      final waiting = await _app.suppliers.pendingCount();
      if (mounted) {
        setState(() {
          _syncing = false;
          _waiting = waiting;
        });
      }
    }
  }

  Future<void> _open(Supplier s) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => SupplierScreen(supplier: s, now: widget.now)),
    );
    if (mounted) await _sync();
  }

  Future<void> _add() async {
    final added = await Navigator.of(context).push<Supplier>(
      MaterialPageRoute(builder: (_) => const SupplierFormScreen()),
    );
    if (added == null || !mounted) return;
    udNotify(context, '${added.name} added');
    await _sync();
    if (mounted) await _open(added);
  }

  @override
  Widget build(BuildContext context) {
    final book = _book;
    final q = _search.trim().toLowerCase();
    final shown = [
      for (final s in book?.suppliers ?? const <Supplier>[])
        if (q.isEmpty || s.name.toLowerCase().contains(q) || (s.supplies ?? '').toLowerCase().contains(q) || (s.mobile ?? '').contains(q))
          s,
    ];
    final overdue = book?.suppliers.where((s) => s.overdue).length ?? 0;
    return Scaffold(
      backgroundColor: udBackground,
      body: SafeArea(
        child: Column(
          children: [
            UdHeader(title: 'Suppliers', subtitle: 'Who you buy from', busy: _syncing),
            if (_offline)
              const UdBanner(icon: Icons.wifi_off_rounded, text: 'Offline: showing your saved list. Entries are kept on the phone.'),
            if (_waiting > 0)
              UdBanner(
                icon: Icons.cloud_upload_outlined,
                color: udPurple,
                background: udSoft,
                text: _waiting == 1 ? '1 entry waiting to sync' : '$_waiting entries waiting to sync',
                actionLabel: 'Sync now',
                onAction: _syncing ? null : _sync,
              ),
            if (overdue > 0)
              UdBanner(
                key: const Key('suppliers-overdue'),
                icon: Icons.event_busy_rounded,
                color: udDue,
                background: const Color(0xFFFFE9EB),
                text: overdue == 1 ? '1 supplier payment is overdue' : '$overdue supplier payments are overdue',
              ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _sync,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  children: [
                    UdCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('You owe suppliers', style: udText(13, color: udBody)),
                          Text(rupees(book?.totalDuePaise ?? 0),
                              key: const Key('suppliers-total'),
                              style: udText(32, weight: FontWeight.w800, color: (book?.totalDuePaise ?? 0) > 0 ? udDue : udInk)),
                          Text((book?.suppliers.length ?? 0) == 1 ? '1 supplier' : '${book?.suppliers.length ?? 0} suppliers',
                              style: udText(13, color: udBody)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const Key('suppliers-search'),
                      onChanged: (v) => setState(() => _search = v),
                      decoration: InputDecoration(
                        hintText: 'Search name, item or number',
                        prefixIcon: const Icon(Icons.search_rounded),
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: EdgeInsets.zero,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (book != null && book.suppliers.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 32),
                        child: Column(
                          children: [
                            const Icon(Icons.local_shipping_outlined, size: 48, color: udPurple),
                            const SizedBox(height: 8),
                            Text('No suppliers yet.\nTap "Add supplier" to start.',
                                key: const Key('suppliers-empty'), textAlign: TextAlign.center, style: udText(14, color: udBody)),
                          ],
                        ),
                      ),
                    for (final s in shown) _SupplierTile(supplier: s, onTap: () => _open(s)),
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: SizedBox(
                width: double.infinity,
                height: 54,
                child: FilledButton.icon(
                  key: const Key('suppliers-add'),
                  onPressed: _add,
                  icon: const Icon(Icons.add_business_outlined),
                  label: const Text('Add supplier'),
                  style: FilledButton.styleFrom(
                    backgroundColor: udPurple,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    textStyle: udText(16, weight: FontWeight.w700),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SupplierTile extends StatelessWidget {
  const _SupplierTile({required this.supplier, required this.onTap});

  final Supplier supplier;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = supplier;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          key: Key('supplier-${s.id}'),
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                UdAvatar(name: s.name),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.name, style: udText(15, weight: FontWeight.w700)),
                      if ((s.supplies ?? '').isNotEmpty)
                        Text(s.supplies!, maxLines: 1, overflow: TextOverflow.ellipsis, style: udText(12, color: udBody)),
                      Wrap(
                        spacing: 6,
                        children: [
                          if (s.nextDue != null)
                            UdBadge(s.overdue ? 'Overdue' : 'Pay by ${shortDay(s.nextDue!)}', color: s.overdue ? udDue : udWarn),
                          if (s.openOrders > 0)
                            UdBadge(s.openOrders == 1 ? '1 order waiting' : '${s.openOrders} orders waiting', color: udPurple),
                        ],
                      ),
                    ],
                  ),
                ),
                Text(owedLabel(s.balancePaise),
                    style: udText(14, weight: FontWeight.w700, color: s.balancePaise > 0 ? udDue : udPaid)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
