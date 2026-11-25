import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/api_client.dart';
import '../services/app_services.dart';
import '../suppliers/supplier_models.dart';
import '../suppliers/supplier_widgets.dart';
import '../udhaar/udhaar_models.dart' show newClientRef, paiseToText, parsePaise, rupees;
import '../udhaar/udhaar_widgets.dart';
import 'supply_models.dart';

/// The supplier writes goods given to a shop, or money received from it. The
/// shop answers. Closes with true when saved.
class SupplyEntryScreen extends StatefulWidget {
  const SupplyEntryScreen({required this.shop, required this.kind, super.key});

  final SupplyShop shop;
  final SupplierEntryKind kind;

  @override
  State<SupplyEntryScreen> createState() => _SupplyEntryScreenState();
}

class _SupplyEntryScreenState extends State<SupplyEntryScreen> {
  AppServices? _services;
  final _amount = TextEditingController();
  final _note = TextEditingController();
  final _lines = LinesController();
  final _ref = newClientRef(); // the same when tried again, so it is written once
  List<SupplierProduct> _products = const [];
  PayMethod _method = PayMethod.cash;
  String? _error;
  bool _busy = false;

  AppServices get _app => _services!;
  bool get _goods => widget.kind == SupplierEntryKind.purchase;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_services != null) return;
    _services = ServicesScope.of(context);
    if (_goods) _loadProducts();
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    _lines.dispose();
    super.dispose();
  }

  Future<void> _loadProducts() async {
    List<Product>? mine;
    try {
      mine = await _app.supply.products();
    } on ApiException {
      mine = await _app.supply.savedProducts(); // the items can also be typed
    }
    if (!mounted) return;
    setState(
      () => _products = [
        for (final p in mine ?? const <Product>[])
          SupplierProduct(id: p.id, name: p.name, unit: p.unit, catalogCode: p.catalogCode, pricePaise: p.pricePaise),
      ],
    );
  }

  void _useTotal() {
    final total = _lines.costTotal;
    if (total != null) setState(() => _amount.text = paiseToText(total));
  }

  Future<void> _save() async {
    final amount = parsePaise(_amount.text);
    final (lines, problem) = _goods ? _lines.read(withCost: true) : (const <EntryLine>[], null);
    if (amount == null || amount <= 0 || problem != null) {
      setState(() => _error = problem ?? 'Enter the amount');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _app.supply.api.addEntry(
        widget.shop.linkId,
        SupplierEntryDraft(
          kind: widget.kind,
          amountPaise: amount,
          entryAt: DateTime.now(),
          note: _note.text,
          method: _goods ? null : _method,
          lines: lines,
          clientRef: _ref,
        ),
      );
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.isNetwork ? 'This needs internet. Please try again.' : e.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = _goods ? _lines.costTotal : null;
    final shop = widget.shop.name;
    return Scaffold(
      backgroundColor: udBackground,
      body: SafeArea(
        child: Column(
          children: [
            UdHeader(title: _goods ? 'Goods given' : 'Got money', subtitle: shop, busy: _busy),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_goods) ...[
                      UdCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text('What did you give? (optional)', style: udText(14, weight: FontWeight.w700)),
                            Text(
                              'Not for orders in QBOX: those are written by themselves.',
                              style: udText(12, color: udBody),
                            ),
                            const SizedBox(height: 8),
                            LinesEditor(
                              controller: _lines,
                              products: _products,
                              productsLabel: 'Add from my products',
                              withCost: true,
                              onChanged: () => setState(() => _error = null),
                            ),
                            if (total != null)
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  key: const Key('give-use-total'),
                                  onPressed: _useTotal,
                                  child: Text('Use items total ${rupees(total)}'),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    UdCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextField(
                            key: const Key('give-amount'),
                            controller: _amount,
                            onChanged: (_) => setState(() => _error = null),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                            style: udText(28, weight: FontWeight.w800),
                            decoration: InputDecoration(
                              labelText: _goods ? 'Bill amount' : 'Amount received',
                              prefixText: '₹ ',
                            ),
                          ),
                          if (!_goods)
                            Wrap(
                              spacing: 6,
                              children: [
                                for (final m in PayMethod.values)
                                  ChoiceChip(
                                    key: Key('give-method-${m.code}'),
                                    label: Text(m.label),
                                    selected: _method == m,
                                    onSelected: (_) => setState(() => _method = m),
                                  ),
                              ],
                            ),
                          TextField(
                            key: const Key('give-note'),
                            controller: _note,
                            maxLength: 200,
                            decoration: const InputDecoration(
                              labelText: 'Note (optional), e.g. bill number',
                              counterText: '',
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 10, 8, 0),
                      child: Text(
                        _goods
                            ? 'It counts after $shop says yes.'
                            : 'It is taken off what $shop owes you now, and they can check it.',
                        textAlign: TextAlign.center,
                        style: udText(12, color: udBody),
                      ),
                    ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          _error!,
                          key: const Key('give-error'),
                          style: udText(13, weight: FontWeight.w600, color: udDue),
                        ),
                      ),
                    const SizedBox(height: 16),
                    WideButton(
                      key: const Key('give-save'),
                      label: 'Save and tell the shop',
                      onPressed: _busy ? null : _save,
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
}
