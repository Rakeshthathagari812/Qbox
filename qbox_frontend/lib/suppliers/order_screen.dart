import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../services/app_services.dart';
import '../services/device_actions.dart';
import '../stock/stock_models.dart';
import '../translator/languages.dart';
import '../translator/voice_language.dart';
import '../udhaar/udhaar_models.dart' show newClientRef, rupees;
import '../udhaar/udhaar_widgets.dart';
import 'supplier_models.dart';
import 'supplier_widgets.dart';

/// Place an order.
/// - A connected supplier: what was chosen from their products, how it will be
///   paid, sent in QBOX (their bell rings).
/// - Any other: the items are typed, and it is sent on WhatsApp.
/// Returns true when sent.
class OrderScreen extends StatefulWidget {
  const OrderScreen({required this.supplier, this.chosen = const [], this.now, super.key});

  final Supplier supplier;

  /// From the supplier's products, with how much.
  final List<EntryLine> chosen;
  final DateTime? now;

  @override
  State<OrderScreen> createState() => _OrderScreenState();
}

class _OrderScreenState extends State<OrderScreen> {
  AppServices? _services;
  final _lines = LinesController();
  final _note = TextEditingController();
  final String _clientRef = newClientRef();
  AppLanguage _language = AppLanguage.english;
  PayPlan _plan = PayPlan.later;
  DateTime? _payBy;
  String? _error;
  bool _saving = false;

  AppServices get _app => _services!;
  bool get _connected => widget.supplier.connected;
  DateTime get _now => widget.now ?? DateTime.now();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_services != null) return;
    _services = ServicesScope.of(context);
    if (widget.chosen.isEmpty) _lines.add();
    _loadLanguage();
  }

  Future<void> _loadLanguage() async {
    final language = await readVoiceLanguage(_app.settings);
    if (mounted) setState(() => _language = language);
  }

  @override
  void dispose() {
    _lines.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDay() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _payBy ?? _now.add(const Duration(days: 7)),
      firstDate: DateTime(_now.year, _now.month, _now.day),
      lastDate: _now.add(const Duration(days: 365)),
      helpText: 'Pay by',
    );
    if (picked != null && mounted) setState(() => _payBy = picked);
  }

  Future<void> _send() async {
    final (typed, error) = _lines.read();
    final lines = [...widget.chosen, ...typed];
    if (error != null || lines.isEmpty) {
      setState(() => _error = error ?? 'Add at least one item');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _app.suppliers.addOrder(
        widget.supplier.id,
        lines,
        note: _note.text,
        payPlan: _connected ? _plan : null,
        payBy: _connected && _plan == PayPlan.later ? _payBy : null,
        clientRef: _clientRef,
      );
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e.isNetwork ? 'Sending an order needs internet.' : e.message;
        });
      }
      return;
    }
    if (!mounted) return;
    if (_connected) {
      Navigator.of(context).pop(true);
      return;
    }
    final text = orderMessage(shopName: shopNameOf(context), lines: lines, language: _language, note: _note.text);
    final mobile = widget.supplier.mobile;
    final opened = mobile == null
        ? await _app.device.openLink(Uri(scheme: 'whatsapp', host: 'send', queryParameters: {'text': text}))
        : await _app.device.openLink(whatsAppAppLink(mobile, text)) ||
            await _app.device.openLink(whatsAppLink(mobile, text));
    if (!mounted) return;
    setState(() => _saving = false);
    if (!opened) udNotify(context, 'Order saved. WhatsApp could not open on this phone.');
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: udBackground,
      body: SafeArea(
        child: Column(
          children: [
            UdHeader(title: _connected ? 'Place order' : 'New order', subtitle: widget.supplier.name, busy: _saving),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    UdCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text('Items to order', style: udText(14, weight: FontWeight.w700)),
                          const SizedBox(height: 8),
                          for (final l in widget.chosen) _chosen(l),
                          if (widget.chosen.isNotEmpty) ...[const Divider(height: 20), _total()],
                          LinesEditor(
                            controller: _lines,
                            addLabel: widget.chosen.isEmpty ? 'Type an item' : 'Need something else? Type it',
                            onChanged: () => setState(() => _error = null),
                          ),
                          TextField(
                            key: const Key('order-note'),
                            controller: _note,
                            maxLength: 200,
                            decoration: const InputDecoration(
                              labelText: 'Note (optional), e.g. deliver by Friday',
                              counterText: '',
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_connected) ...[const SizedBox(height: 12), _payment()],
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          _error!,
                          key: const Key('order-error'),
                          style: udText(13, weight: FontWeight.w600, color: udDue),
                        ),
                      ),
                    const SizedBox(height: 16),
                    WideButton(
                      key: const Key('order-send'),
                      label: _connected ? 'Place order' : 'Send on WhatsApp',
                      icon: Icons.send_rounded,
                      color: _connected ? udPurple : udPaid,
                      onPressed: _saving ? null : _send,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static int? _price(EntryLine l) => l.costPaise == null ? null : (l.costPaise! * l.qtyMilli / milli).round();

  Widget _chosen(EntryLine l) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Expanded(
          flex: 3,
          child: Text('${l.name}, ${formatQty(l.qtyMilli, l.unit)}', style: udText(14, weight: FontWeight.w600)),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 2,
          child: Text(
            _price(l) == null ? 'Price on the bill' : rupees(_price(l)!),
            textAlign: TextAlign.end,
            style: udText(14, color: udBody),
          ),
        ),
      ],
    ),
  );

  Widget _total() {
    final unpriced = widget.chosen.any((l) => l.costPaise == null);
    final sum = widget.chosen.fold<int>(0, (s, l) => s + (_price(l) ?? 0));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text('Total', style: udText(15, weight: FontWeight.w700))),
            Text(
              '${unpriced ? 'From ' : ''}${rupees(sum)}',
              key: const Key('order-total'),
              style: udText(20, weight: FontWeight.w800),
            ),
          ],
        ),
        Text('They confirm the final bill.', style: udText(12, color: udBody)),
      ],
    );
  }

  Widget _payment() {
    final s = widget.supplier;
    final (text, icon) = switch (_plan) {
      PayPlan.later => ('Added to what you owe when the goods come.', Icons.event_outlined),
      PayPlan.cash => ('You pay when the goods come. It counts after they say they got it.', Icons.payments_outlined),
      PayPlan.upi => ('You pay after they accept, in your UPI app. Never before.', Icons.account_balance_outlined),
    };
    return UdCard(
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('How will you pay?', style: udText(14, weight: FontWeight.w700)),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              children: [
                for (final p in PayPlan.values)
                  if (p != PayPlan.upi || s.takesUpi)
                    ChoiceChip(
                      key: Key('order-pay-${p.code}'),
                      label: Text(p.label),
                      selected: _plan == p,
                      onSelected: (_) => setState(() => _plan = p),
                    ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(icon, size: 20, color: udPurple),
                const SizedBox(width: 8),
                Expanded(child: Text(text, style: udText(12, color: udBody))),
              ],
            ),
            if (!s.takesUpi)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '${s.name} has not added a UPI ID yet.',
                  key: const Key('order-no-upi'),
                  style: udText(12, color: udBody),
                ),
              ),
            if (_plan == PayPlan.later)
              ListTile(
                key: const Key('order-pay-by'),
                contentPadding: EdgeInsets.zero,
                title: Text(
                  _payBy == null ? 'Pay by date (optional)' : 'Pay by ${shortDay(_payBy!, _now)}',
                  style: udText(14, weight: FontWeight.w600),
                ),
                trailing: _payBy == null
                    ? const Icon(Icons.chevron_right_rounded, color: udPurple)
                    : IconButton(
                        onPressed: () => setState(() => _payBy = null),
                        icon: const Icon(Icons.close_rounded),
                      ),
                onTap: _pickDay,
              ),
          ],
        ),
      ),
    );
  }
}
