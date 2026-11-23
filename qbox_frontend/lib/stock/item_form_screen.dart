import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/api_client.dart';
import '../services/app_services.dart';
import '../udhaar/udhaar_models.dart' show paiseToText, parsePaise;
import '../udhaar/udhaar_widgets.dart';
import 'stock_catalog.dart';
import 'stock_models.dart';

/// Add a new item, or change one ([item] given). Returns the saved item.
/// The unit is chosen once: the history is counted in it.
class ItemFormScreen extends StatefulWidget {
  const ItemFormScreen({
    this.item,
    this.catalog,
    this.name = '',
    this.openingMilli,
    this.pastItems = const [],
    super.key,
  });

  /// The shop's own removed items, suggested first while typing a name.
  final List<PastItem> pastItems;

  /// Changing this item (null = adding a new one).
  final StockItem? item;

  /// Adding a ready-list item (name and unit filled in).
  final CatalogItem? catalog;
  final String name;
  final int? openingMilli;

  @override
  State<ItemFormScreen> createState() => _ItemFormScreenState();
}

class _ItemFormScreenState extends State<ItemFormScreen> {
  late final StockItem? _editing = widget.item;
  late final _name = TextEditingController(text: _editing?.name ?? widget.catalog?.en ?? widget.name);
  late StockUnit _unit = _editing?.unit ?? widget.catalog?.unit ?? StockUnit.kg;
  late String? _catalogCode = _editing?.catalogCode ?? widget.catalog?.code;
  late final _opening = TextEditingController(text: widget.openingMilli == null ? '' : qtyNumber(widget.openingMilli!));
  late final _cost = TextEditingController(text: _paise(_editing?.costPaise));
  late final _price = TextEditingController(text: _paise(_editing?.pricePaise));
  late final _alert = TextEditingController(text: _editing?.alertMilli == null ? '' : qtyNumber(_editing!.alertMilli!));
  String? _error;
  bool _saving = false;

  bool get _adding => _editing == null;

  static String _paise(int? paise) => paise == null ? '' : paiseToText(paise);

  @override
  void dispose() {
    for (final c in [_name, _opening, _cost, _price, _alert]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Ready-list items matching what is typed, to fill in the name and unit.
  List<CatalogItem> get _suggestions {
    final typed = _name.text.trim().toLowerCase();
    if (!_adding || typed.length < 2 || _catalogCode != null) return const [];
    return stockCatalog
        .where((c) => c.allNames.any((n) => n.toLowerCase().startsWith(typed) || n.toLowerCase().contains(' $typed')))
        .take(5)
        .toList();
  }

  void _pick(CatalogItem c) => setState(() {
    _name.text = c.en;
    _unit = c.unit;
    _catalogCode = c.code;
  });

  /// The shop's own past items matching what is typed.
  List<PastItem> get _pastSuggestions {
    final typed = _name.text.trim().toLowerCase();
    if (!_adding || typed.length < 2) return const [];
    return widget.pastItems
        .where((p) => p.name.toLowerCase().contains(typed) && p.name.toLowerCase() != typed)
        .take(5)
        .toList();
  }

  void _pickPast(PastItem p) => setState(() {
    _name.text = p.name;
    _unit = p.unit;
    _catalogCode = p.catalogCode;
  });

  /// An optional number field: null when empty; throws [FormatException] when wrong.
  int? _optional(TextEditingController c, int? Function(String) parse, String what) {
    if (c.text.trim().isEmpty) return null;
    final value = parse(c.text);
    if (value == null) throw FormatException('Check the $what');
    return value;
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Enter the item name');
      return;
    }
    final int? opening, cost, price, alert;
    try {
      opening = _adding ? _optional(_opening, parseQty, 'stock you have now') : null;
      cost = _optional(_cost, parsePaise, 'buying price');
      price = _optional(_price, parsePaise, 'selling price');
      alert = _optional(_alert, parseQty, 'alert level');
    } on FormatException catch (e) {
      setState(() => _error = e.message);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final stock = ServicesScope.of(context).stock;
    try {
      final saved = _adding
          ? await stock.addItem(ItemDraft(
              name: name,
              unit: _unit,
              catalogCode: _catalogCode,
              openingMilli: opening ?? 0,
              costPaise: cost,
              pricePaise: price,
              alertMilli: alert,
            ))
          : await stock.changeItem(_editing!.id, name: name, costPaise: cost, pricePaise: price, alertMilli: alert);
      if (mounted) Navigator.of(context).pop(saved);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.isNetwork ? 'Adding or changing items needs internet.' : e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final unit = _unit.short;
    return Scaffold(
      backgroundColor: udBackground,
      body: SafeArea(
        child: Column(
          children: [
            UdHeader(title: _adding ? 'Add item' : 'Change item', subtitle: _adding ? 'Stock' : _editing!.name, busy: _saving),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                children: [
                  UdCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          key: const Key('item-name'),
                          controller: _name,
                          maxLength: 80,
                          textCapitalization: TextCapitalization.sentences,
                          // A ready-list item renamed ("Rice" -> "Sona rice") keeps its
                          // names in 5 languages for voice; clearing the name drops them.
                          onChanged: (_) => setState(() {
                            if (_name.text.trim().isEmpty) _catalogCode = null;
                          }),
                          decoration: const InputDecoration(labelText: 'Item name', counterText: ''),
                        ),
                        if (_pastSuggestions.isNotEmpty || _suggestions.isNotEmpty)
                          Wrap(
                            spacing: 6,
                            children: [
                              for (final p in _pastSuggestions)
                                ActionChip(
                                  key: Key('item-past-${p.name.toLowerCase()}'),
                                  avatar: const Icon(Icons.history_rounded, size: 16),
                                  label: Text(p.name),
                                  onPressed: () => _pickPast(p),
                                ),
                              for (final c in _suggestions)
                                ActionChip(
                                  key: Key('item-suggest-${c.code}'),
                                  label: Text(c.en),
                                  onPressed: () => _pick(c),
                                ),
                            ],
                          ),
                        const SizedBox(height: 8),
                        if (_adding)
                          DropdownButtonFormField<StockUnit>(
                            key: const Key('item-unit'),
                            initialValue: _unit,
                            decoration: const InputDecoration(labelText: 'Counted in'),
                            items: [
                              for (final u in StockUnit.values)
                                DropdownMenuItem(value: u, child: Text('${u.label} (${u.short})')),
                            ],
                            onChanged: (u) => setState(() => _unit = u ?? _unit),
                          )
                        else
                          Text('Counted in ${_unit.label} (${_unit.short})', style: udText(13, color: udBody)),
                        if (_adding) ...[
                          const SizedBox(height: 8),
                          _number('item-opening', _opening, 'Stock you have now (optional)', suffix: unit),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  UdCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('Optional', style: udText(13, weight: FontWeight.w600, color: udBody)),
                        _number('item-cost', _cost, 'Buying price per $unit', prefix: '₹ '),
                        _number('item-price', _price, 'Selling price per $unit', prefix: '₹ '),
                        _number('item-alert', _alert, 'Warn me when stock is at or below', suffix: unit),
                      ],
                    ),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(_error!, key: const Key('item-error'), style: udText(13, weight: FontWeight.w600, color: udDue)),
                    ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 54,
                    child: FilledButton(
                      key: const Key('item-save'),
                      onPressed: _saving ? null : _save,
                      style: FilledButton.styleFrom(
                        backgroundColor: udPurple,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        textStyle: udText(16, weight: FontWeight.w700),
                      ),
                      child: Text(_adding ? 'Add item' : 'Save'),
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

  Widget _number(String key, TextEditingController c, String label, {String? prefix, String? suffix}) => TextField(
    key: Key(key),
    controller: c,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
    decoration: InputDecoration(labelText: label, prefixText: prefix, suffixText: suffix),
  );
}
