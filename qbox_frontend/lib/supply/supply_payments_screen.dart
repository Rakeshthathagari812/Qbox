import 'package:flutter/material.dart';

import '../suppliers/supplier_models.dart' show Confirm;
import '../udhaar/udhaar_models.dart' show rupees, whenLabel;
import '../udhaar/udhaar_widgets.dart';
import 'supply_models.dart';
import 'supply_page.dart';

/// Opens "Payments" (Supplier home tile).
Widget openSupplyPayments(BuildContext context) => const SupplyPaymentsScreen();

/// What shops paid: confirm what came; and the supplier's own UPI ID.
class SupplyPaymentsScreen extends StatefulWidget {
  const SupplyPaymentsScreen({this.now, super.key});

  final DateTime? now;

  @override
  State<SupplyPaymentsScreen> createState() => _SupplyPaymentsScreenState();
}

class _SupplyPaymentsScreenState extends State<SupplyPaymentsScreen> with SupplyPage<SupplyPaymentsScreen, SupplyPayments> {
  @override
  Future<SupplyPayments?> loadSaved() => app.supply.savedPayments();

  @override
  Future<SupplyPayments> loadFresh() => app.supply.payments();

  Future<void> _editUpi() async {
    final answer = await showDialog<(String, String)>(
      context: context,
      builder: (_) => _UpiDialog(upiId: data?.upiId ?? '', name: data?.upiName ?? ''),
    );
    if (answer == null || !mounted) return;
    final (upi, name) = answer;
    await act(() => app.supply.api.saveUpi(upi, name), upi.isEmpty ? 'UPI ID removed' : 'UPI ID saved');
  }

  @override
  Widget build(BuildContext context) {
    final d = data;
    final now = widget.now ?? DateTime.now();
    final all = d?.payments ?? const <SupplyPayment>[];
    final waiting = all
        .where((p) => p.connected && !p.entry.bySupplier && p.entry.confirm == Confirm.waiting)
        .toList();
    final rest = all.where((p) => !waiting.contains(p)).toList();
    return Scaffold(
      backgroundColor: udBackground,
      body: SafeArea(
        child: Column(
          children: [
            UdHeader(title: 'Payments', subtitle: 'From shops', busy: busy),
            errorBanner(),
            Expanded(
              child: RefreshIndicator(
                onRefresh: load,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  children: [
                    if (d != null) ...[
                      UdCard(
                        child: Row(
                          children: [
                            _figure('pay-month', 'Received this month', d.receivedMonthPaise, udPaid),
                            const SizedBox(width: 12),
                            _figure('pay-to-get', 'Still to get', d.toGetPaise, udDue),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      _upiCard(d),
                    ],
                    if (waiting.isNotEmpty) ...[
                      _heading('Did these come?'),
                      for (final p in waiting) _tile(p, now),
                    ],
                    if (d != null) _heading('All payments'),
                    if (d != null && all.isEmpty)
                      Text(
                        'No payments yet. They show here when a shop pays you.',
                        key: const Key('payments-empty'),
                        style: udText(13, color: udBody),
                      ),
                    for (final p in rest) _tile(p, now),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _figure(String key, String label, int paise, Color color) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: udText(12, color: udBody)),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(rupees(paise), key: Key(key), style: udText(24, weight: FontWeight.w800, color: color)),
        ),
      ],
    ),
  );

  Widget _upiCard(SupplyPayments d) => UdCard(
    padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
    child: Row(
      children: [
        const Icon(Icons.account_balance_outlined, color: udPurple),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Your UPI ID', style: udText(14, weight: FontWeight.w700)),
              Text(
                d.upiId ?? 'Add it, so your shops can pay you by UPI.',
                key: const Key('payments-upi'),
                style: udText(13, color: udBody),
              ),
              if ((d.upiName ?? '').isNotEmpty) Text(d.upiName!, style: udText(12, color: udBody)),
            ],
          ),
        ),
        TextButton(
          key: const Key('payments-upi-edit'),
          onPressed: busy ? null : _editUpi,
          child: Text(d.upiId == null ? 'Add' : 'Change'),
        ),
      ],
    ),
  );

  Widget _heading(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(2, 16, 2, 8),
    child: Text(text, style: udText(16, weight: FontWeight.w700)),
  );

  Widget _tile(SupplyPayment p, DateTime now) {
    final e = p.entry;
    final came = e.counts;
    final answerable = p.connected && !e.bySupplier && (e.confirm == Confirm.waiting || e.confirm == Confirm.disputed);
    final details = [
      if (e.method != null) e.method!.label,
      if ((e.note ?? '').isNotEmpty) e.note!,
      whenLabel(e.entryAt, now),
    ];
    return Container(
      key: Key('payment-${e.id}'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.south_west_rounded, color: came ? udPaid : udWarn, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.shopName, style: udText(14, weight: FontWeight.w700)),
                    Text(details.join(', '), style: udText(12, color: udBody)),
                    const SizedBox(height: 2),
                    switch (e.confirm) {
                      _ when e.bySupplier && e.confirm != Confirm.confirmed => const UdBadge('Written by you', color: udPaid),
                      Confirm.waiting when p.connected => const UdBadge('Not counted until you confirm', color: udWarn),
                      Confirm.confirmed => const UdBadge('Received', color: udPaid),
                      Confirm.disputed => UdBadge('You said: ${e.disputeReason ?? 'not received'}'),
                      _ => const UdBadge('Never confirmed: not counted', color: udBody),
                    },
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                rupees(e.amountPaise),
                style: udText(16, weight: FontWeight.w700, color: came ? udPaid : udWarn),
              ),
            ],
          ),
          if (answerable)
            Wrap(
              spacing: 8,
              children: [
                FilledButton(
                  key: Key('payment-yes-${e.id}'),
                  onPressed: busy ? null : () => confirmEntry(e, p.shopName),
                  style: FilledButton.styleFrom(backgroundColor: udPaid),
                  child: const Text('Yes, I got it'),
                ),
                if (e.confirm == Confirm.waiting)
                  TextButton(
                    key: Key('payment-no-${e.id}'),
                    onPressed: busy ? null : () => disputeEntry(e, p.shopName),
                    style: TextButton.styleFrom(foregroundColor: udDue),
                    child: const Text('Not received'),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

/// The UPI ID and the name UPI apps show.
class _UpiDialog extends StatefulWidget {
  const _UpiDialog({required this.upiId, required this.name});

  final String upiId;
  final String name;

  @override
  State<_UpiDialog> createState() => _UpiDialogState();
}

class _UpiDialogState extends State<_UpiDialog> {
  late final _upi = TextEditingController(text: widget.upiId);
  late final _name = TextEditingController(text: widget.name);
  String? _error;

  @override
  void dispose() {
    _upi.dispose();
    _name.dispose();
    super.dispose();
  }

  void _save() {
    final upi = _upi.text.trim();
    if (upi.isNotEmpty && !RegExp(r'^[A-Za-z0-9._-]{2,50}@[A-Za-z0-9]{2,30}$').hasMatch(upi)) {
      setState(() => _error = 'Like ravitraders@okaxis');
    } else {
      Navigator.of(context).pop((upi, _name.text.trim()));
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: const Text('Your UPI ID'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Money goes straight to it. Check it twice. Only shops connected with you see it.'),
        TextField(
          key: const Key('upi-id'),
          controller: _upi,
          maxLength: 60,
          autocorrect: false,
          keyboardType: TextInputType.emailAddress,
          onChanged: (_) => setState(() => _error = null),
          decoration: InputDecoration(labelText: 'UPI ID, e.g. ravitraders@okaxis', errorText: _error, counterText: ''),
        ),
        TextField(
          key: const Key('upi-name'),
          controller: _name,
          maxLength: 60,
          decoration: const InputDecoration(labelText: 'Name shown in UPI apps', counterText: ''),
        ),
        if (widget.upiId.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('Leave it empty to remove it.', style: udText(12, color: udBody)),
          ),
      ],
    ),
    actions: [
      TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
      FilledButton(
        key: const Key('upi-save'),
        onPressed: _save,
        style: FilledButton.styleFrom(backgroundColor: udPurple),
        child: const Text('Save'),
      ),
    ],
  );
}
