import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../payments/payment_models.dart' show upiLink;
import '../services/api_client.dart';
import '../services/app_services.dart';
import '../udhaar/udhaar_models.dart' show paiseToText, parsePaise, rupees;
import '../udhaar/udhaar_widgets.dart';
import 'supplier_entry_screen.dart' show EntryResult;
import 'supplier_models.dart';
import 'supplier_repository.dart';
import 'supplier_widgets.dart';

/// Asks whether a payment in the UPI app went through. Null = not answered.
Future<bool?> askWentThrough(BuildContext context, int paise, String name) => showDialog<bool>(
  context: context,
  barrierDismissible: false,
  builder: (context) => AlertDialog(
    scrollable: true,
    title: const Text('Did the payment go through?'),
    content: Text('${rupees(paise)} to $name in your UPI app.'),
    actions: [
      TextButton(key: const Key('upi-no'), onPressed: () => Navigator.of(context).pop(false), child: const Text('No')),
      FilledButton(
        key: const Key('upi-yes'),
        onPressed: () => Navigator.of(context).pop(true),
        style: FilledButton.styleFrom(backgroundColor: udPaid),
        child: const Text('Yes, I paid'),
      ),
    ],
  ),
);

/// Pay a connected supplier: in the UPI app (straight to their own UPI ID), or
/// write down what was paid already. Either way it counts after they confirm.
class PaySupplierScreen extends StatefulWidget {
  const PaySupplierScreen({required this.supplier, this.order, super.key});

  final Supplier supplier;

  /// Paying for this order.
  final SupplierOrder? order;

  @override
  State<PaySupplierScreen> createState() => _PaySupplierScreenState();
}

class _PaySupplierScreenState extends State<PaySupplierScreen> {
  AppServices? _services;
  late final _amount = TextEditingController(text: _first);
  final _note = TextEditingController();
  SupplierPay? _pay;
  String? _payProblem;
  String? _error;
  PayMethod _method = PayMethod.cash;
  bool _busy = false;

  AppServices get _app => _services!;
  Supplier get _supplier => widget.supplier;

  String get _first {
    final paise = widget.order?.leftPaise ?? widget.supplier.balancePaise;
    return paise > 0 ? paiseToText(paise) : '';
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_services != null) return;
    _services = ServicesScope.of(context);
    _load();
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _busy = true);
    try {
      final pay = await _app.suppliers.payInfo(_supplier.id);
      if (mounted) {
        setState(() {
          _pay = pay;
          _payProblem = null;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _payProblem = e.isNetwork ? 'Paying by UPI needs internet.' : e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  SupplierEntryDraft? _draft(PayMethod method, int least) {
    final amount = parsePaise(_amount.text);
    if (amount == null || amount < least) {
      setState(() => _error = least > 1 ? 'Enter at least ₹1' : 'Enter the amount');
      return null;
    }
    FocusScope.of(context).unfocus();
    return SupplierEntryDraft(
      kind: SupplierEntryKind.payment,
      amountPaise: amount,
      entryAt: DateTime.now(),
      note: _note.text,
      method: method,
      orderId: widget.order?.id,
    );
  }

  Future<void> _byUpi() async {
    final upiId = _pay?.upiId;
    final draft = _draft(PayMethod.upi, 100);
    if (draft == null || upiId == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    await _app.suppliers.startAsking(_supplier.id, draft);
    final link = upiLink(upiId: upiId, name: _pay!.name, amountPaise: draft.amountPaise, note: draft.note.trim());
    if (!await _app.device.openLink(Uri.parse(link))) {
      await _app.suppliers.stopAsking(draft.clientRef);
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'No UPI app could open. Pay $upiId from any UPI app, then save it below.';
        });
      }
      return;
    }
    if (!mounted) return;
    setState(() => _busy = false); // waiting for the person, not the network
    final paid = await askWentThrough(context, draft.amountPaise, _pay!.name);
    if (paid == null || !mounted) return; // asked again on the supplier's page
    if (paid) {
      await _save(draft);
    } else {
      await _app.suppliers.stopAsking(draft.clientRef);
      if (mounted) setState(() => _error = 'Not paid. Nothing was written.');
    }
  }

  Future<void> _already() async {
    final draft = _draft(_method, 1);
    if (draft != null) await _save(draft);
  }

  Future<void> _save(SupplierEntryDraft draft) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final saved = await _app.suppliers.paid(_supplier.id, draft);
      if (mounted) Navigator.of(context).pop(saved == EntrySaved.saved ? EntryResult.saved : EntryResult.savedOffline);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final pay = _pay;
    final owed = _supplier.balancePaise;
    return Scaffold(
      backgroundColor: udBackground,
      body: SafeArea(
        child: Column(
          children: [
            UdHeader(title: 'Pay', subtitle: _supplier.name, busy: _busy),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    UdCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            order != null
                                ? 'For the order: ${linesSummary(order.lines)}'
                                : owed > 0
                                ? 'You owe ${rupees(owed)}. Pay all of it, or a part.'
                                : 'You owe nothing now. It is kept as your advance.',
                            key: const Key('pay-for'),
                            style: udText(13, color: udBody),
                          ),
                          TextField(
                            key: const Key('pay-amount'),
                            controller: _amount,
                            enabled: !_busy,
                            onChanged: (_) => setState(() => _error = null),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                            style: udText(30, weight: FontWeight.w800),
                            decoration: const InputDecoration(prefixText: '₹ '),
                          ),
                          TextField(
                            key: const Key('pay-note'),
                            controller: _note,
                            enabled: !_busy,
                            maxLength: 80,
                            decoration: const InputDecoration(labelText: 'Note (optional)', counterText: ''),
                          ),
                        ],
                      ),
                    ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          _error!,
                          key: const Key('pay-error'),
                          textAlign: TextAlign.center,
                          style: udText(13, weight: FontWeight.w600, color: udDue),
                        ),
                      ),
                    const SizedBox(height: 16),
                    if (pay?.upiId != null) ...[
                      WideButton(
                        key: const Key('pay-upi'),
                        label: 'Pay by UPI app',
                        onPressed: _busy ? null : _byUpi,
                      ),
                      _hint('Real money, straight to ${pay!.name} (${pay.upiId}).'),
                    ] else if (_payProblem != null)
                      UdBanner(
                        icon: Icons.wifi_off_rounded,
                        text: _payProblem!,
                        actionLabel: 'Retry',
                        onAction: _busy ? null : _load,
                      )
                    else if (pay != null)
                      Text(
                        '${_supplier.name} has not added a UPI ID yet. They can add it in Payments.',
                        key: const Key('pay-no-upi'),
                        textAlign: TextAlign.center,
                        style: udText(13, color: udBody),
                      ),
                    const SizedBox(height: 12),
                    UdCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text('Already paid?', style: udText(15, weight: FontWeight.w700)),
                          Text('Write it down, without opening a UPI app.', style: udText(12, color: udBody)),
                          Wrap(
                            spacing: 6,
                            children: [
                              for (final m in PayMethod.values)
                                ChoiceChip(
                                  key: Key('pay-method-${m.code}'),
                                  label: Text(m.label),
                                  selected: _method == m,
                                  onSelected: (_) => setState(() => _method = m),
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          WideButton(
                            key: const Key('pay-save'),
                            label: 'Save payment',
                            color: udPaid,
                            onPressed: _busy ? null : _already,
                          ),
                        ],
                      ),
                    ),
                    _hint('It counts after ${_supplier.name} confirms it.'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _hint(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
    child: Text(text, textAlign: TextAlign.center, style: udText(12, color: udBody)),
  );
}
