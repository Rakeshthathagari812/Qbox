import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/api_client.dart';
import '../services/app_services.dart';
import '../services/device_actions.dart';
import 'add_customer_screen.dart';
import 'entry_form_screen.dart';
import 'udhaar_models.dart';
import 'udhaar_repository.dart';
import 'udhaar_widgets.dart';

/// One customer: what they owe, their full history, reminders, and the two
/// big buttons "Gave udhaar" / "Got payment".
class UdhaarCustomerScreen extends StatefulWidget {
  const UdhaarCustomerScreen({required this.customer, this.now, super.key});

  final UdhaarCustomer customer;

  /// For tests: pretend it is this moment.
  final DateTime? now;

  @override
  State<UdhaarCustomerScreen> createState() => _UdhaarCustomerScreenState();
}

class _UdhaarCustomerScreenState extends State<UdhaarCustomerScreen> {
  AppServices? _services;
  late UdhaarCustomer _customer;
  List<UdhaarEntry> _entries = const [];
  bool _loaded = false;
  bool _syncing = false;
  bool _offline = false;

  AppServices get _app => _services!;
  DateTime get _now => widget.now ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    _customer = widget.customer;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_services != null) return;
    _services = ServicesScope.of(context);
    _start();
  }

  Future<void> _start() async {
    final saved = await _app.udhaar.savedCustomer(_customer.id);
    if (!mounted) return;
    if (saved != null) _show(saved);
    await _sync();
  }

  void _show(CustomerDetail detail) {
    setState(() {
      _customer = detail.customer;
      _entries = detail.entries;
      _loaded = true;
    });
  }

  Future<void> _sync() async {
    setState(() => _syncing = true);
    try {
      _show(await _app.udhaar.freshCustomer(_customer.id));
      if (mounted) setState(() => _offline = false);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.isNetwork) {
        // Offline: show the phone copy plus entries waiting to sync.
        final saved = await _app.udhaar.savedCustomer(_customer.id);
        if (!mounted) return;
        if (saved != null) _show(saved);
        setState(() {
          _offline = true;
          _loaded = true;
        });
      } else {
        udNotify(context, e.message);
      }
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _addEntry(EntryKind kind) async {
    final outcome = await Navigator.of(context).push<SaveOutcome>(
      MaterialPageRoute(
        builder: (_) => UdhaarEntryForm(customer: _customer, kind: kind, now: widget.now),
      ),
    );
    if (outcome == null || !mounted) return;
    await _sync();
    if (!mounted) return;
    udNotify(
      context,
      outcome == SaveOutcome.saved
          ? 'Saved'
          : 'Saved on the phone. It will sync when internet is back.',
    );
  }

  String _reminderText() {
    final shop = shopNameOf(context);
    final at = shop.isEmpty ? 'our shop' : shop;
    return 'Namaste ${_customer.name}, your pending udhaar at $at is '
        '${rupees(_customer.balancePaise)}. Please pay when convenient. Thank you!';
  }

  Future<void> _open(Uri uri, String failMessage) async {
    final opened = await _app.device.openLink(uri);
    if (!opened && mounted) udNotify(context, failMessage);
  }

  void _remind({required bool whatsApp}) {
    if (_customer.balancePaise <= 0) {
      udNotify(context, 'Nothing pending for ${_customer.name}.');
      return;
    }
    final text = _reminderText();
    if (whatsApp) {
      _openWhatsApp(text);
    } else {
      _open(smsLink(_customer.mobile, text), 'Could not open messages.');
    }
  }

  /// Straight into the WhatsApp app; the web link only as a fallback.
  Future<void> _openWhatsApp(String text) async {
    if (await _app.device.openLink(whatsAppAppLink(_customer.mobile, text))) return;
    if (!mounted) return;
    await _open(whatsAppLink(_customer.mobile, text), 'WhatsApp is not installed on this phone.');
  }

  Future<void> _entryActions(UdhaarEntry entry) async {
    if (entry.pending) {
      udNotify(context, 'This entry is waiting for internet. It can be deleted after it syncs.');
      return;
    }
    if (entry.deleted || entry.id == null) return;
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => _DeleteDialog(entry: entry),
    );
    if (reason == null || !mounted) return;
    try {
      await _app.udhaar.deleteEntry(entry.id!, reason);
      await _sync();
      if (mounted) udNotify(context, 'Entry deleted. It stays in the history, crossed out.');
    } on ApiException catch (e) {
      if (mounted) {
        udNotify(context, e.isNetwork ? 'Deleting needs internet. Please try again.' : e.message);
      }
    }
  }

  Future<void> _edit() async {
    final result = await showModalBottomSheet<Object>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _EditSheet(customer: _customer),
    );
    if (!mounted) return;
    if (result == _EditSheet.changeNumber) {
      await _changeNumber();
    } else if (result is UdhaarCustomer) {
      setState(() => _customer = result.copyWith(balancePaise: _customer.balancePaise));
      udNotify(context, 'Customer updated');
      await _sync();
    }
  }

  /// Moves this customer (and all their history) to a new number, checked by code.
  Future<void> _changeNumber() async {
    final changed = await Navigator.of(context).push<UdhaarCustomer>(
      MaterialPageRoute(builder: (_) => AddCustomerScreen(changeNumberOf: _customer)),
    );
    if (changed == null || !mounted) return;
    udNotify(context, 'Number changed to +91 ${changed.mobile}');
    await _sync();
  }

  /// The shop's decision on a "this is not me" report.
  Future<void> _decide({required bool confirm}) async {
    final name = _customer.name;
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(confirm ? 'Number is correct?' : 'Wrong number?'),
        content: Text(
          confirm
              ? 'You are sure +91 ${_customer.mobile} is $name\'s number. '
                    'The udhaar stays visible on that phone, and they cannot report it again.'
              : 'The udhaar will be hidden from +91 ${_customer.mobile}. '
                    'You keep every entry. Then add $name\'s right number.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(
            key: const Key('dispute-sure'),
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: confirm ? udPaid : udDue),
            child: Text(confirm ? 'Yes, correct' : 'Yes, unlink'),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    try {
      final updated = confirm
          ? await _app.udhaar.confirmDispute(_customer.id)
          : await _app.udhaar.unlinkDispute(_customer.id);
      if (!mounted) return;
      setState(() => _customer = updated);
      udNotify(
        context,
        confirm ? 'Confirmed. The customer has been told.' : 'Unlinked. Now add the right number.',
      );
      await _sync();
    } on ApiException catch (e) {
      if (mounted) udNotify(context, e.isNetwork ? 'This needs internet. Please try again.' : e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final balances = runningBalances(_entries);
    return Scaffold(
      backgroundColor: udBackground,
      body: SafeArea(
        child: Column(
          children: [
            UdHeader(
              title: _customer.name,
              subtitle: '+91 ${_customer.mobile}',
              busy: _syncing,
              actions: [
                IconButton(
                  key: const Key('customer-edit'),
                  onPressed: _edit,
                  icon: const Icon(Icons.edit_rounded, color: udPurple),
                  tooltip: 'Change name or limit',
                ),
              ],
            ),
            if (_offline)
              const UdBanner(
                key: Key('customer-offline'),
                icon: Icons.wifi_off_rounded,
                text: 'Offline: showing the saved copy. New entries are kept on the phone.',
              ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _sync,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  children: [
                    _BalanceCard(customer: _customer, now: _now),
                    if (_customer.dispute == Dispute.reported)
                      _DisputeCard(
                        customer: _customer,
                        now: _now,
                        busy: _syncing,
                        onConfirm: () => _decide(confirm: true),
                        onUnlink: () => _decide(confirm: false),
                      ),
                    if (_customer.dispute == Dispute.unlinked)
                      UdBanner(
                        key: const Key('customer-unlinked'),
                        icon: Icons.link_off_rounded,
                        color: udDue,
                        background: const Color(0xFFFFE9EB),
                        text: 'Unlinked: +91 ${_customer.mobile} is not this customer\'s number. '
                            'Add their right number to link the history again.',
                        actionLabel: 'Right number',
                        onAction: _changeNumber,
                      ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _Action(
                          key: const Key('customer-call'),
                          icon: Icons.call_rounded,
                          label: 'Call',
                          onTap: () => _open(callLink(_customer.mobile), 'Could not open the dialer.'),
                        ),
                        const SizedBox(width: 10),
                        _Action(
                          key: const Key('customer-whatsapp'),
                          icon: Icons.chat_rounded,
                          label: 'WhatsApp',
                          color: udPaid,
                          onTap: () => _remind(whatsApp: true),
                        ),
                        const SizedBox(width: 10),
                        _Action(
                          key: const Key('customer-sms'),
                          icon: Icons.sms_rounded,
                          label: 'SMS',
                          onTap: () => _remind(whatsApp: false),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Text('History', style: udText(16, weight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    if (_loaded && _entries.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: Text(
                            'No entries yet. Tap "Gave udhaar" or "Got payment".',
                            key: const Key('customer-empty'),
                            textAlign: TextAlign.center,
                            style: udText(14, color: udBody),
                          ),
                        ),
                      ),
                    for (final e in _entries)
                      EntryTile(
                        key: Key('entry-${e.clientRef}'),
                        entry: e,
                        balanceAfter: balances[e] ?? 0,
                        now: _now,
                        onTap: () => _entryActions(e),
                      ),
                    if (_entries.any((e) => !e.deleted && !e.pending))
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Tap an entry to delete it (it stays in the history, crossed out).',
                          textAlign: TextAlign.center,
                          style: udText(11, color: udBody),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            UdBottomButtons(
              leftKey: const Key('customer-credit'),
              leftIcon: Icons.north_east_rounded,
              leftLabel: 'Gave udhaar',
              leftColor: udDue,
              leftFilled: true,
              onLeft: () => _addEntry(EntryKind.credit),
              rightKey: const Key('customer-payment'),
              rightIcon: Icons.south_west_rounded,
              rightLabel: 'Got payment',
              rightColor: udPaid,
              onRight: () => _addEntry(EntryKind.payment),
            ),
          ],
        ),
      ),
    );
  }
}

/// "This customer says it is not their number": the shop decides.
class _DisputeCard extends StatelessWidget {
  const _DisputeCard({
    required this.customer,
    required this.now,
    required this.busy,
    required this.onConfirm,
    required this.onUnlink,
  });

  final UdhaarCustomer customer;
  final DateTime now;
  final bool busy;
  final VoidCallback onConfirm;
  final VoidCallback onUnlink;

  @override
  Widget build(BuildContext context) {
    final when = customer.disputedAt;
    return Container(
      key: const Key('customer-dispute'),
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFE9EB),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF5B5BC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.report_problem_rounded, color: udDue),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Says this is not their number',
                  style: udText(15, weight: FontWeight.w700, color: udDue),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'The person using +91 ${customer.mobile} reported this in their QBOX app'
            '${when == null ? '' : ' (${whenLabel(when, now)})'}. '
            'Nothing is hidden until you decide. The balance does not change.',
            style: udText(12.5),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                key: const Key('dispute-confirm'),
                onPressed: busy ? null : onConfirm,
                icon: const Icon(Icons.verified_rounded, size: 18),
                label: const Text('Number is correct'),
                style: FilledButton.styleFrom(backgroundColor: udPaid),
              ),
              OutlinedButton.icon(
                key: const Key('dispute-unlink'),
                onPressed: busy ? null : onUnlink,
                icon: const Icon(Icons.link_off_rounded, size: 18),
                label: const Text('Wrong number, unlink'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: udDue,
                  side: const BorderSide(color: udDue),
                  backgroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.customer, required this.now});

  final UdhaarCustomer customer;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final balance = customer.balancePaise;
    final limit = customer.creditLimitPaise;
    final days = customer.daysOwing(now);
    final String heading;
    if (balance > 0) {
      heading = '${customer.name} owes you';
    } else if (balance < 0) {
      heading = 'Advance paid by ${customer.name}';
    } else {
      heading = 'All settled';
    }
    return UdCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(heading, style: udText(13, color: udBody)),
          Text(
            rupees(balance),
            key: const Key('customer-balance'),
            style: udText(36, weight: FontWeight.w800, color: balanceColor(balance)),
          ),
          if (limit != null)
            Text(
              customer.overLimit
                  ? 'Over the ${rupees(limit)} limit by ${rupees(balance - limit)}'
                  : 'Limit ${rupees(limit)} · ${rupees(limit - (balance > 0 ? balance : 0))} left',
              key: const Key('customer-limit'),
              style: udText(
                13,
                weight: FontWeight.w600,
                color: customer.overLimit ? udDue : udBody,
              ),
            ),
          if (days >= overdueDays)
            Text(
              'No payment for $days days',
              key: const Key('customer-overdue'),
              style: udText(13, weight: FontWeight.w600, color: udDue),
            ),
        ],
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color = udPurple,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              children: [
                Icon(icon, color: color),
                const SizedBox(height: 4),
                Text(label, style: udText(12, weight: FontWeight.w600, color: color)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Asks why the entry is being deleted. Pops with the reason.
class _DeleteDialog extends StatefulWidget {
  const _DeleteDialog({required this.entry});

  final UdhaarEntry entry;

  @override
  State<_DeleteDialog> createState() => _DeleteDialogState();
}

class _DeleteDialogState extends State<_DeleteDialog> {
  final _reason = TextEditingController();
  static const _quick = ['Wrong amount', 'Wrong customer', 'Entered twice'];

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.entry;
    return AlertDialog(
      title: const Text('Delete this entry?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${e.kind.label} · ${rupees(e.amountPaise)}', style: udText(15, weight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(
              'It will stay in the history, crossed out, with your reason. '
              'The customer can see it too.',
              style: udText(12, color: udBody),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final q in _quick)
                  ActionChip(
                    label: Text(q),
                    onPressed: () => setState(() => _reason.text = q),
                  ),
              ],
            ),
            TextField(
              key: const Key('delete-reason'),
              controller: _reason,
              maxLength: 200,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: 'Reason', counterText: ''),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          key: const Key('delete-confirm'),
          onPressed: _reason.text.trim().isEmpty
              ? null
              : () => Navigator.of(context).pop(_reason.text.trim()),
          style: FilledButton.styleFrom(backgroundColor: udDue),
          child: const Text('Delete'),
        ),
      ],
    );
  }
}

/// Change the customer's name or credit limit. Pops with the updated customer.
class _EditSheet extends StatefulWidget {
  const _EditSheet({required this.customer});

  final UdhaarCustomer customer;

  /// Popped when the shopkeeper wants to change the mobile number.
  static const changeNumber = 'change-number';

  @override
  State<_EditSheet> createState() => _EditSheetState();
}

class _EditSheetState extends State<_EditSheet> {
  late final _name = TextEditingController(text: widget.customer.name);
  late final _limit = TextEditingController(
    text: widget.customer.creditLimitPaise == null ? '' : paiseToText(widget.customer.creditLimitPaise!),
  );
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _limit.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final limitText = _limit.text.trim();
    final limit = limitText.isEmpty ? null : parsePaise(limitText);
    if (name.isEmpty) {
      setState(() => _error = 'Enter customer name');
      return;
    }
    if (limitText.isNotEmpty && limit == null) {
      setState(() => _error = 'Enter the limit in rupees, or leave it empty');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final changed = await ServicesScope.of(context).udhaar.changeCustomer(
        widget.customer.id,
        name: name,
        creditLimitPaise: limit,
      );
      if (mounted) Navigator.of(context).pop(changed);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _error = e.isNetwork ? 'Changing needs internet. Please try again.' : e.message);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Change customer', style: udText(18, weight: FontWeight.w700)),
          Row(
            children: [
              Expanded(
                child: Text('Mobile: +91 ${widget.customer.mobile}', style: udText(13, color: udBody)),
              ),
              TextButton(
                key: const Key('edit-change-number'),
                onPressed: () => Navigator.of(context).pop(_EditSheet.changeNumber),
                child: const Text('Change number'),
              ),
            ],
          ),
          TextField(
            key: const Key('edit-name'),
            controller: _name,
            maxLength: 80,
            decoration: const InputDecoration(labelText: 'Customer name', counterText: ''),
          ),
          TextField(
            key: const Key('edit-limit'),
            controller: _limit,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
            decoration: const InputDecoration(
              labelText: 'Credit limit (empty = no limit)',
              prefixText: '₹ ',
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!, style: udText(13, weight: FontWeight.w600, color: udDue)),
            ),
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('edit-save'),
            onPressed: _busy ? null : _save,
            style: FilledButton.styleFrom(
              backgroundColor: udPurple,
              minimumSize: const Size.fromHeight(50),
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
