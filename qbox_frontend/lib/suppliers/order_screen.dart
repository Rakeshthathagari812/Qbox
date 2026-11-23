import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../services/app_services.dart';
import '../services/device_actions.dart';
import '../stock/stock_models.dart';
import '../translator/languages.dart';
import '../translator/voice_language.dart';
import '../udhaar/udhaar_models.dart' show newClientRef;
import '../udhaar/udhaar_widgets.dart';
import 'supplier_models.dart';
import 'supplier_widgets.dart';

/// How much to order of a low item: enough to reach twice its alert level,
/// in whole units.
int suggestedOrder(StockItem item) {
  final alert = item.alertMilli ?? 0;
  final need = alert * 2 - item.quantityMilli;
  final qty = need > alert ? need : alert;
  return qty <= 0 ? milli : ((qty + milli - 1) ~/ milli) * milli;
}

/// Make an order for a supplier: items running low are filled in, then it is
/// saved and sent on WhatsApp. Returns true when sent.
class OrderScreen extends StatefulWidget {
  const OrderScreen({required this.supplier, super.key});

  final Supplier supplier;

  @override
  State<OrderScreen> createState() => _OrderScreenState();
}

class _OrderScreenState extends State<OrderScreen> {
  AppServices? _services;
  final _lines = LinesController();
  final _note = TextEditingController();
  final String _clientRef = newClientRef();
  List<StockItem> _items = const [];
  AppLanguage _language = AppLanguage.english;
  String? _error;
  bool _saving = false;

  AppServices get _app => _services!;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_services != null) return;
    _services = ServicesScope.of(context);
    _load();
  }

  @override
  void dispose() {
    _lines.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    _language = await readVoiceLanguage(_app.settings);
    var book = await _app.stock.savedBook();
    try {
      book = await _app.stock.freshBook();
    } on ApiException {
      // Offline: the phone copy is enough to choose items.
    }
    if (!mounted) return;
    final items = book?.items ?? const <StockItem>[];
    setState(() => _items = items);
    for (final item in items.where((i) => i.isLow)) {
      _lines.add(item, qtyMilli: suggestedOrder(item));
    }
  }

  Future<void> _send() async {
    final (lines, error) = _lines.read();
    if (error != null || lines.isEmpty) {
      setState(() => _error = error ?? 'Add at least one item');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _app.suppliers.addOrder(widget.supplier.id, lines, note: _note.text, clientRef: _clientRef);
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
    final text = orderMessage(
      shopName: shopNameOf(context),
      lines: lines,
      catalogCodes: {for (final i in _items) i.id: i.catalogCode},
      language: _language,
      note: _note.text,
    );
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
            UdHeader(title: 'New order', subtitle: widget.supplier.name, busy: _saving),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                children: [
                  UdCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('Items to order', style: udText(14, weight: FontWeight.w700)),
                        Text('Items running low are already added.', style: udText(12, color: udBody)),
                        const SizedBox(height: 8),
                        LinesEditor(controller: _lines, items: _items, onChanged: () => setState(() => _error = null)),
                        TextField(
                          key: const Key('order-note'),
                          controller: _note,
                          maxLength: 200,
                          decoration: const InputDecoration(labelText: 'Note (optional), e.g. deliver by Friday', counterText: ''),
                        ),
                      ],
                    ),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(_error!, key: const Key('order-error'), style: udText(13, weight: FontWeight.w600, color: udDue)),
                    ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 54,
                    child: FilledButton.icon(
                      key: const Key('order-send'),
                      onPressed: _saving ? null : _send,
                      icon: const Icon(Icons.send_rounded),
                      label: const Text('Send on WhatsApp'),
                      style: FilledButton.styleFrom(
                        backgroundColor: udPaid,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        textStyle: udText(16, weight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
