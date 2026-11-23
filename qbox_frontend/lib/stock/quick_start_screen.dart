import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/api_client.dart';
import '../services/app_services.dart';
import '../translator/languages.dart';
import '../udhaar/udhaar_widgets.dart';
import 'stock_catalog.dart';
import 'stock_models.dart';

/// An item the shop added itself: in stock now, or removed earlier (then it
/// can be ticked to add again).
class YourItem {
  const YourItem({required this.name, required this.unit, this.catalogCode, this.inStock = false});

  final String name;
  final StockUnit unit;
  final String? catalogCode;
  final bool inStock;
}

/// Quick start: tick the items the shop sells (its own items first, then the
/// common ones) and type how much is there now. All of them are added in one
/// go. Returns how many were added.
class QuickStartScreen extends StatefulWidget {
  const QuickStartScreen({
    required this.inStock,
    this.yourItems = const [],
    this.language = AppLanguage.english,
    super.key,
  });

  /// Ready-list codes and names already in stock (shown as "In stock").
  final Set<String> inStock;

  /// Items the shop added itself ("Your items", shown first).
  final List<YourItem> yourItems;
  final AppLanguage language;

  @override
  State<QuickStartScreen> createState() => _QuickStartScreenState();
}

class _QuickStartScreenState extends State<QuickStartScreen> {
  final Map<String, TextEditingController> _picked = {};
  String _search = '';
  bool _saving = false;

  @override
  void dispose() {
    for (final c in _picked.values) {
      c.dispose();
    }
    super.dispose();
  }

  bool _have(CatalogItem c) => widget.inStock.contains(c.code) || widget.inStock.contains(c.en.toLowerCase());

  static String _ownKey(YourItem y) => 'own:${y.name.toLowerCase()}';

  void _toggle(String key) => setState(() {
    final old = _picked.remove(key);
    if (old != null) {
      old.dispose();
    } else {
      _picked[key] = TextEditingController();
    }
  });

  Future<void> _add() async {
    final drafts = <ItemDraft>[];
    int? opening(TextEditingController qty) => qty.text.trim().isEmpty ? 0 : parseQty(qty.text);
    for (final y in widget.yourItems) {
      final qty = _picked[_ownKey(y)];
      if (qty == null) continue;
      final value = opening(qty);
      if (value == null) {
        udNotify(context, 'Check the quantity for ${y.name}');
        return;
      }
      drafts.add(ItemDraft(name: y.name, unit: y.unit, catalogCode: y.catalogCode, openingMilli: value));
    }
    for (final c in stockCatalog) {
      final qty = _picked[c.code];
      if (qty == null) continue;
      final value = opening(qty);
      if (value == null) {
        udNotify(context, 'Check the quantity for ${c.en}');
        return;
      }
      drafts.add(ItemDraft(name: c.en, unit: c.unit, catalogCode: c.code, openingMilli: value));
    }
    setState(() => _saving = true);
    try {
      final added = await ServicesScope.of(context).stock.addItems(drafts);
      if (mounted) Navigator.of(context).pop(added.length);
    } on ApiException catch (e) {
      if (mounted) udNotify(context, e.isNetwork ? 'Adding items needs internet.' : e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _search.trim().toLowerCase();
    final shown = [
      for (final c in stockCatalog)
        if (q.isEmpty || c.allNames.any((n) => n.toLowerCase().contains(q))) c,
    ];
    final own = [
      for (final y in widget.yourItems)
        if (q.isEmpty ||
            y.name.toLowerCase().contains(q) ||
            (catalogItem(y.catalogCode)?.allNames.any((n) => n.toLowerCase().contains(q)) ?? false))
          y,
    ];
    return Scaffold(
      backgroundColor: udBackground,
      body: SafeArea(
        child: Column(
          children: [
            UdHeader(title: 'Common items', subtitle: 'Tick what you sell', busy: _saving),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: TextField(
                key: const Key('quick-search'),
                onChanged: (v) => setState(() => _search = v),
                decoration: InputDecoration(
                  hintText: 'Search in any language',
                  prefixIcon: const Icon(Icons.search_rounded),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: EdgeInsets.zero,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                children: [
                  if (own.isNotEmpty) ...[
                    _heading('Your items'),
                    for (final y in own) _ownRow(y),
                    _heading('Common items'),
                  ],
                  for (final c in shown) _row(c),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: SizedBox(
                width: double.infinity,
                height: 54,
                child: FilledButton(
                  key: const Key('quick-add'),
                  onPressed: _picked.isEmpty || _saving ? null : _add,
                  style: FilledButton.styleFrom(
                    backgroundColor: udPurple,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    textStyle: udText(16, weight: FontWeight.w700),
                  ),
                  child: Text(_picked.isEmpty
                      ? 'Tick items to add'
                      : (_picked.length == 1 ? 'Add 1 item' : 'Add ${_picked.length} items')),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _heading(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
    child: Text(text, style: udText(14, weight: FontWeight.w700, color: udBody)),
  );

  Widget _ownRow(YourItem y) {
    final key = _ownKey(y);
    final local = widget.language == AppLanguage.english ? null : catalogItem(y.catalogCode)?.nameIn(widget.language);
    return _tile(
      key: key,
      checkKey: 'quick-own-${y.name.toLowerCase()}',
      title: y.name,
      subtitle: local == null ? y.unit.label : '$local · ${y.unit.label}',
      unit: y.unit,
      have: y.inStock,
    );
  }

  Widget _row(CatalogItem c) {
    final local = widget.language == AppLanguage.english ? null : c.nameIn(widget.language);
    return _tile(
      key: c.code,
      checkKey: 'quick-${c.code}',
      title: local ?? c.en,
      subtitle: local == null ? c.unit.label : '${c.en} · ${c.unit.label}',
      unit: c.unit,
      have: _have(c),
    );
  }

  Widget _tile({
    required String key,
    required String checkKey,
    required String title,
    required String subtitle,
    required StockUnit unit,
    required bool have,
  }) {
    final qty = _picked[key];
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(4, 2, 12, 2),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          Checkbox(
            key: Key(checkKey),
            value: have || qty != null,
            onChanged: have ? null : (_) => _toggle(key),
            activeColor: udPurple,
          ),
          Expanded(
            child: InkWell(
              onTap: have ? null : () => _toggle(key),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: udText(15, weight: FontWeight.w600)),
                    Text(subtitle, style: udText(12, color: udBody)),
                  ],
                ),
              ),
            ),
          ),
          if (have) Text('In stock', style: udText(12, weight: FontWeight.w600, color: udPaid)),
          if (qty != null)
            SizedBox(
              width: 96,
              child: TextField(
                key: Key(checkKey.replaceFirst('quick-', 'quick-qty-')),
                controller: qty,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                textAlign: TextAlign.end,
                decoration: InputDecoration(hintText: 'Qty', suffixText: unit.short, isDense: true),
              ),
            ),
        ],
      ),
    );
  }
}
