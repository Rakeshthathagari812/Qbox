import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/api_client.dart';
import '../services/app_services.dart';
import '../stock/stock_models.dart';
import '../udhaar/udhaar_models.dart' show paiseToText, parsePaise, rupees;
import '../udhaar/udhaar_widgets.dart';
import 'supplier_models.dart';
import 'supplier_repository.dart';
import 'supplier_widgets.dart';

/// What happened when the form was saved.
enum EntryResult { saved, savedOffline, received }

/// A purchase or a payment for one supplier. With [order], it records the
/// order's goods as received (a purchase made from what actually came).
class SupplierEntryScreen extends StatefulWidget {
  const SupplierEntryScreen({required this.supplier, required this.kind, this.order, this.now, super.key});

  final Supplier supplier;
  final SupplierEntryKind kind;
  final SupplierOrder? order;
  final DateTime? now;

  @override
  State<SupplierEntryScreen> createState() => _SupplierEntryScreenState();
}

class _SupplierEntryScreenState extends State<SupplierEntryScreen> {
  AppServices? _services;
  final _amount = TextEditingController();
  final _note = TextEditingController();
  final _lines = LinesController();
  List<StockItem> _items = const [];
  bool _paidNow = false;
  PayMethod _method = PayMethod.cash;
  DateTime? _due;
  String? _error;
  bool _saving = false;

  AppServices get _app => _services!;
  bool get _purchase => widget.kind == SupplierEntryKind.purchase;
  DateTime get _now => widget.now ?? DateTime.now();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_services != null) return;
    _services = ServicesScope.of(context);
    if (_purchase) _loadItems();
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    _lines.dispose();
    super.dispose();
  }

  Future<void> _loadItems() async {
    var book = await _app.stock.savedBook();
    try {
      book = await _app.stock.freshBook();
    } on ApiException {
      // Offline: the phone copy is enough to choose items.
    }
    if (!mounted) return;
    final items = book?.items ?? const <StockItem>[];
    setState(() => _items = items);
    final order = widget.order;
    if (order != null) {
      for (final line in order.lines) {
        final item = items.where((i) => i.id == line.itemId).firstOrNull;
        if (item != null) _lines.add(item, qtyMilli: line.qtyMilli);
      }
      _useItemsTotal();
    }
  }

  void _useItemsTotal() {
    final total = _lines.costTotal;
    if (total != null) setState(() => _amount.text = paiseToText(total));
  }

  Future<void> _pickDue() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _due ?? _now.add(const Duration(days: 7)),
      firstDate: DateTime(_now.year, _now.month, _now.day),
      lastDate: _now.add(const Duration(days: 365)),
      helpText: 'Pay by',
    );
    if (picked != null && mounted) setState(() => _due = picked);
  }

  Future<void> _save() async {
    final amount = parsePaise(_amount.text);
    if (amount == null) {
      setState(() => _error = 'Enter the amount');
      return;
    }
    final (lines, lineError) = _purchase ? _lines.read(withCost: true) : (const <EntryLine>[], null);
    if (lineError != null) {
      setState(() => _error = lineError);
      return;
    }
    final draft = SupplierEntryDraft(
      kind: widget.kind,
      amountPaise: amount,
      entryAt: DateTime.now(),
      note: _note.text,
      dueDate: _purchase && !_paidNow ? _due : null,
      method: !_purchase || _paidNow ? _method : null,
      paidNow: _purchase && _paidNow,
      lines: lines,
    );
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final order = widget.order;
      EntryResult result;
      if (order != null) {
        await _app.suppliers.receiveOrder(order.id, draft);
        result = EntryResult.received;
      } else {
        final saved = await _app.suppliers.addEntry(widget.supplier.id, draft);
        result = saved == EntrySaved.saved ? EntryResult.saved : EntryResult.savedOffline;
      }
      if (mounted) Navigator.of(context).pop(result);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.isNetwork ? 'This needs internet. Please try again.' : e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.order != null ? 'Goods received' : (_purchase ? 'Purchase' : 'Payment');
    final total = _lines.costTotal;
    return Scaffold(
      backgroundColor: udBackground,
      body: SafeArea(
        child: Column(
          children: [
            UdHeader(title: title, subtitle: widget.supplier.name, busy: _saving),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                children: [
                  if (_purchase)
                    UdCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(widget.order != null ? 'What came (stock goes up)' : 'Items bought (optional, added to stock)',
                              style: udText(14, weight: FontWeight.w700)),
                          const SizedBox(height: 8),
                          LinesEditor(controller: _lines, items: _items, withCost: true, onChanged: () => setState(() {})),
                          if (total != null)
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                key: const Key('entry-use-total'),
                                onPressed: _useItemsTotal,
                                child: Text('Use items total ${rupees(total)}'),
                              ),
                            ),
                        ],
                      ),
                    ),
                  if (_purchase) const SizedBox(height: 12),
                  UdCard(
                    child: Material(
                      type: MaterialType.transparency,
                      child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          key: const Key('entry-amount'),
                          controller: _amount,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                          style: udText(28, weight: FontWeight.w800),
                          decoration: InputDecoration(
                            labelText: _purchase ? 'Bill amount' : 'Amount paid',
                            prefixText: '₹ ',
                          ),
                        ),
                        if (_purchase)
                          SwitchListTile(
                            key: const Key('entry-paid-now'),
                            contentPadding: EdgeInsets.zero,
                            value: _paidNow,
                            onChanged: (v) => setState(() => _paidNow = v),
                            title: Text('Paid now', style: udText(14, weight: FontWeight.w600)),
                            subtitle: Text(_paidNow ? 'Nothing is added to what you owe' : 'Added to what you owe',
                                style: udText(12, color: udBody)),
                          ),
                        if (!_purchase || _paidNow)
                          Wrap(
                            spacing: 6,
                            children: [
                              for (final m in PayMethod.values)
                                ChoiceChip(
                                  key: Key('entry-method-${m.code}'),
                                  label: Text(m.label),
                                  selected: _method == m,
                                  onSelected: (_) => setState(() => _method = m),
                                ),
                            ],
                          ),
                        if (_purchase && !_paidNow)
                          ListTile(
                            key: const Key('entry-due'),
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.event_outlined, color: udPurple),
                            title: Text(_due == null ? 'Pay by date (optional)' : 'Pay by ${shortDay(_due!, _now)}',
                                style: udText(14, weight: FontWeight.w600)),
                            subtitle: Text('A reminder rings on that day', style: udText(12, color: udBody)),
                            trailing: _due == null
                                ? null
                                : IconButton(onPressed: () => setState(() => _due = null), icon: const Icon(Icons.close_rounded)),
                            onTap: _pickDue,
                          ),
                        TextField(
                          key: const Key('entry-note'),
                          controller: _note,
                          maxLength: 200,
                          decoration: const InputDecoration(labelText: 'Note (optional), e.g. bill number', counterText: ''),
                        ),
                      ],
                    ),
                    ),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(_error!, key: const Key('entry-error'), style: udText(13, weight: FontWeight.w600, color: udDue)),
                    ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 54,
                    child: FilledButton(
                      key: const Key('entry-save'),
                      onPressed: _saving ? null : _save,
                      style: FilledButton.styleFrom(
                        backgroundColor: _purchase ? udDue : udPaid,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        textStyle: udText(16, weight: FontWeight.w700),
                      ),
                      child: Text(widget.order != null ? 'Save: goods received' : 'Save'),
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
