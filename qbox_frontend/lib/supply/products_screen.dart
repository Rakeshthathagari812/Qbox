import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/api_client.dart';
import '../services/app_services.dart';
import '../stock/stock_catalog.dart';
import '../stock/stock_models.dart';
import '../translator/languages.dart';
import '../translator/voice_language.dart';
import '../udhaar/udhaar_models.dart' show paiseToText, parsePaise, rupees;
import '../udhaar/udhaar_widgets.dart';
import 'product_stock_screen.dart';
import 'supply_models.dart';
import 'supply_page.dart';

/// Opens "Products" (Supplier home tile).
Widget openProducts(BuildContext context) => const ProductsScreen();

/// What the supplier sells: price, available or not (connected shops see it),
/// and how much there is (only the supplier sees it).
class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key});

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> with SupplyPage<ProductsScreen, List<Product>> {
  String _search = '';
  AppLanguage _language = AppLanguage.english;

  @override
  Future<List<Product>?> loadSaved() async {
    _language = await readVoiceLanguage(app.settings);
    return app.supply.savedProducts();
  }

  @override
  Future<List<Product>> loadFresh() => app.supply.products();

  Future<void> _set(Product p, bool available) => act(
    () => app.supply.api.changeProduct(p.id, name: p.name, pricePaise: p.pricePaise, available: available),
    available ? '${p.name}: available' : '${p.name}: not available',
  );

  Future<void> _form([Product? product]) async {
    final message = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => ProductFormScreen(product: product)),
    );
    if (message == null || !mounted) return;
    udNotify(context, message);
    await load();
  }

  Future<void> _stock(Product product) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => ProductStockScreen(product: product)),
    );
    if (mounted) await load();
  }

  Future<void> _ready() async {
    final added = await Navigator.of(context).push<int>(
      MaterialPageRoute(
        builder: (_) => ReadyProductsScreen(
          have: {for (final p in data ?? const <Product>[]) ...[?p.catalogCode, p.name.toLowerCase()]},
          language: _language,
        ),
      ),
    );
    if (added == null || !mounted) return;
    udNotify(context, added == 1 ? '1 product added' : '$added products added');
    await load();
  }

  @override
  Widget build(BuildContext context) {
    final products = data;
    final q = _search.trim().toLowerCase();
    final shown = [
      for (final p in products ?? const <Product>[])
        if (q.isEmpty ||
            p.name.toLowerCase().contains(q) ||
            (catalogItem(p.catalogCode)?.allNames.any((n) => n.toLowerCase().contains(q)) ?? false))
          p,
    ];
    return Scaffold(
      backgroundColor: udBackground,
      body: SafeArea(
        child: Column(
          children: [
            UdHeader(title: 'Products', subtitle: 'Your connected shops see these', busy: busy),
            errorBanner(),
            if ((products?.length ?? 0) > 6)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: TextField(
                  key: const Key('my-products-search'),
                  onChanged: (v) => setState(() => _search = v),
                  decoration: InputDecoration(
                    hintText: 'Search in any language',
                    isDense: true,
                    filled: true,
                    fillColor: Colors.white,
                    prefixIcon: const Icon(Icons.search_rounded, color: udBody),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                  ),
                ),
              ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: load,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  children: [
                    if (products != null && products.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 32),
                        child: Text(
                          'No products yet.\nTick them in the ready list, or add your own.',
                          key: const Key('my-products-empty'),
                          textAlign: TextAlign.center,
                          style: udText(14, color: udBody),
                        ),
                      ),
                    if (products != null && products.isNotEmpty && shown.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Center(child: Text('No products match.', style: udText(14, color: udBody))),
                      ),
                    for (final p in shown) _tile(p),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                children: [
                  Expanded(child: _button('products-ready', Icons.checklist_rounded, 'Ready list', _ready, false)),
                  const SizedBox(width: 10),
                  Expanded(child: _button('products-add', Icons.add_rounded, 'Add product', _form, true)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _button(String key, IconData icon, String label, VoidCallback onTap, bool filled) => SizedBox(
    height: 52,
    child: FilledButton.icon(
      key: Key(key),
      onPressed: busy ? null : onTap,
      icon: Icon(icon, size: 20),
      label: FittedBox(fit: BoxFit.scaleDown, child: Text(label)),
      style: FilledButton.styleFrom(
        backgroundColor: filled ? udPurple : Colors.white,
        foregroundColor: filled ? Colors.white : udPurple,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: udText(15, weight: FontWeight.w700),
      ),
    ),
  );

  Widget _tile(Product p) {
    final local = _language == AppLanguage.english ? null : catalogItem(p.catalogCode)?.nameIn(_language);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: p.available ? Colors.white : const Color(0xFFF1EEF7),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          key: Key('my-product-${p.id}'),
          borderRadius: BorderRadius.circular(14),
          onTap: () => _form(p),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        local == null || local == p.name ? p.name : '${p.name} ($local)',
                        style: udText(15, weight: FontWeight.w600, color: p.available ? udInk : udBody),
                      ),
                      Text(
                        '${p.pricePaise == null ? 'No price' : rupees(p.pricePaise!)}/${p.unit.short}'
                        '${p.available ? '' : ', not available'}',
                        style: udText(13, color: udBody),
                      ),
                      if (p.counted)
                        Text(
                          p.quantityMilli <= 0 ? 'None left: shops see "Not available"' : 'You have ${formatQty(p.quantityMilli, p.unit)}',
                          key: Key('my-product-left-${p.id}'),
                          style: udText(12, weight: FontWeight.w600, color: p.low ? udDue : udPaid),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  key: Key('my-product-stock-${p.id}'),
                  onPressed: () => _stock(p),
                  icon: Icon(
                    p.counted ? Icons.inventory_2_rounded : Icons.inventory_2_outlined,
                    color: p.low ? udDue : udPurple,
                  ),
                  tooltip: 'Your stock',
                ),
                Switch(
                  key: Key('my-product-on-${p.id}'),
                  value: p.available,
                  activeTrackColor: udPaid,
                  onChanged: busy ? null : (on) => _set(p, on),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Add a product, or change one. Closes with the message to show.
class ProductFormScreen extends StatefulWidget {
  const ProductFormScreen({this.product, super.key});

  final Product? product;

  @override
  State<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends State<ProductFormScreen> {
  late final _name = TextEditingController(text: widget.product?.name ?? '');
  late final _price = TextEditingController(
    text: widget.product?.pricePaise == null ? '' : paiseToText(widget.product!.pricePaise!),
  );
  late final _draft = ProductDraft(name: '', unit: StockUnit.kg); // keeps one id for retries
  StockUnit _unit = StockUnit.kg;
  String? _code;
  late bool _available = widget.product?.available ?? true;
  String? _error;
  bool _busy = false;

  bool get _adding => widget.product == null;

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    super.dispose();
  }

  List<CatalogItem> get _suggestions {
    final typed = _name.text.trim().toLowerCase();
    if (!_adding || typed.length < 2 || _code != null) return const [];
    return stockCatalog.where((c) => c.allNames.any((n) => n.toLowerCase().contains(typed))).take(5).toList();
  }

  void _pick(CatalogItem c) => setState(() {
    _name.text = c.en;
    _unit = c.unit;
    _code = c.code;
  });

  Future<void> _run(Future<void> Function() action, String message) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      if (mounted) Navigator.of(context).pop(message);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.isNetwork ? 'This needs internet. Please try again.' : e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final price = _price.text.trim().isEmpty ? null : parsePaise(_price.text);
    if (name.isEmpty || (price == null && _price.text.trim().isNotEmpty)) {
      setState(() => _error = name.isEmpty ? 'Enter the product name' : 'Check the price');
      return;
    }
    final api = ServicesScope.of(context).supply.api;
    await _run(
      () => _adding
          ? api.addProducts([
              ProductDraft(
                name: name,
                unit: _unit,
                catalogCode: _code,
                pricePaise: price,
                available: _available,
                clientRef: _draft.clientRef,
              ),
            ])
          : api.changeProduct(widget.product!.id, name: name, pricePaise: price, available: _available),
      _adding ? '$name added' : 'Saved',
    );
  }

  Future<void> _remove() async {
    final sure = await askSure(
      context,
      title: 'Remove ${widget.product!.name}?',
      text: 'Shops will not see it any more. Orders already sent stay as they are.',
      action: 'Remove',
      color: udDue,
    );
    if (!sure || !mounted) return;
    final api = ServicesScope.of(context).supply.api;
    await _run(() => api.removeProduct(widget.product!.id), '${widget.product!.name} removed');
  }

  @override
  Widget build(BuildContext context) {
    final unit = _adding ? _unit : widget.product!.unit;
    return Scaffold(
      backgroundColor: udBackground,
      body: SafeArea(
        child: Column(
          children: [
            UdHeader(title: _adding ? 'Add product' : 'Change product', busy: _busy),
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
                          TextField(
                            key: const Key('product-name'),
                            controller: _name,
                            maxLength: 80,
                            textCapitalization: TextCapitalization.sentences,
                            onChanged: (_) => setState(() {
                              if (_name.text.trim().isEmpty) _code = null;
                            }),
                            decoration: const InputDecoration(labelText: 'Product name', counterText: ''),
                          ),
                          Wrap(
                            spacing: 6,
                            children: [
                              for (final c in _suggestions)
                                ActionChip(
                                  key: Key('product-suggest-${c.code}'),
                                  label: Text(c.en),
                                  onPressed: () => _pick(c),
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          if (_adding)
                            DropdownButtonFormField<StockUnit>(
                              key: ValueKey('product-unit-${_unit.code}'),
                              initialValue: _unit,
                              decoration: const InputDecoration(labelText: 'Sold in'),
                              items: [
                                for (final u in StockUnit.values)
                                  DropdownMenuItem(value: u, child: Text('${u.label} (${u.short})')),
                              ],
                              onChanged: (u) => setState(() => _unit = u ?? _unit),
                            )
                          else
                            Text('Sold in ${unit.label} (${unit.short})', style: udText(13, color: udBody)),
                          TextField(
                            key: const Key('product-price'),
                            controller: _price,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                            decoration: InputDecoration(
                              labelText: 'Price per ${unit.short} (optional)',
                              prefixText: '₹ ',
                            ),
                          ),
                          Material(
                            type: MaterialType.transparency,
                            child: SwitchListTile(
                              key: const Key('product-available'),
                              contentPadding: EdgeInsets.zero,
                              value: _available,
                              activeTrackColor: udPaid,
                              onChanged: (v) => setState(() => _available = v),
                              title: Text('Available', style: udText(15, weight: FontWeight.w600)),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          _error!,
                          key: const Key('product-error'),
                          style: udText(13, weight: FontWeight.w600, color: udDue),
                        ),
                      ),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 54,
                      child: FilledButton(
                        key: const Key('product-save'),
                        onPressed: _busy ? null : _save,
                        style: FilledButton.styleFrom(
                          backgroundColor: udPurple,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          textStyle: udText(16, weight: FontWeight.w700),
                        ),
                        child: Text(_adding ? 'Add product' : 'Save'),
                      ),
                    ),
                    if (!_adding)
                      TextButton(
                        key: const Key('product-remove'),
                        onPressed: _busy ? null : _remove,
                        style: TextButton.styleFrom(foregroundColor: udDue),
                        child: const Text('Remove product'),
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

/// Tick what is sold in the ready list (names in 5 languages) and type prices.
/// Closes with how many were added.
class ReadyProductsScreen extends StatefulWidget {
  const ReadyProductsScreen({required this.have, required this.language, super.key});

  /// Ready-list codes and names already in the products.
  final Set<String> have;
  final AppLanguage language;

  @override
  State<ReadyProductsScreen> createState() => _ReadyProductsScreenState();
}

class _ReadyProductsScreenState extends State<ReadyProductsScreen> {
  final Map<String, (ProductDraft, TextEditingController)> _picked = {};
  String _search = '';
  bool _busy = false;

  @override
  void dispose() {
    for (final (_, price) in _picked.values) {
      price.dispose();
    }
    super.dispose();
  }

  void _toggle(CatalogItem c) => setState(() {
    final old = _picked.remove(c.code);
    if (old != null) {
      old.$2.dispose();
    } else {
      _picked[c.code] = (ProductDraft(name: c.en, unit: c.unit, catalogCode: c.code), TextEditingController());
    }
  });

  Future<void> _add() async {
    final drafts = <ProductDraft>[];
    for (final (draft, price) in _picked.values) {
      final text = price.text.trim();
      final paise = text.isEmpty ? null : parsePaise(text);
      if (text.isNotEmpty && paise == null) {
        udNotify(context, 'Check the price of ${draft.name}');
        return;
      }
      drafts.add(
        ProductDraft(
          name: draft.name,
          unit: draft.unit,
          catalogCode: draft.catalogCode,
          pricePaise: paise,
          clientRef: draft.clientRef,
        ),
      );
    }
    setState(() => _busy = true);
    try {
      await ServicesScope.of(context).supply.api.addProducts(drafts);
      if (mounted) Navigator.of(context).pop(drafts.length);
    } on ApiException catch (e) {
      if (mounted) udNotify(context, e.isNetwork ? 'This needs internet. Please try again.' : e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _search.trim().toLowerCase();
    final shown = [
      for (final c in stockCatalog)
        if (q.isEmpty || c.allNames.any((n) => n.toLowerCase().contains(q))) c,
    ];
    return Scaffold(
      backgroundColor: udBackground,
      body: SafeArea(
        child: Column(
          children: [
            UdHeader(title: 'Ready list', subtitle: 'Tick what you sell', busy: _busy),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: TextField(
                key: const Key('ready-search'),
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
                children: [for (final c in shown) _row(c)],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: SizedBox(
                width: double.infinity,
                height: 54,
                child: FilledButton(
                  key: const Key('ready-add'),
                  onPressed: _picked.isEmpty || _busy ? null : _add,
                  style: FilledButton.styleFrom(
                    backgroundColor: udPurple,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    textStyle: udText(16, weight: FontWeight.w700),
                  ),
                  child: Text(
                    _picked.isEmpty
                        ? 'Tick products to add'
                        : _picked.length == 1
                        ? 'Add 1 product'
                        : 'Add ${_picked.length} products',
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(CatalogItem c) {
    final have = widget.have.contains(c.code) || widget.have.contains(c.en.toLowerCase());
    final picked = _picked[c.code];
    final local = widget.language == AppLanguage.english ? null : c.nameIn(widget.language);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(4, 2, 12, 2),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          Checkbox(
            key: Key('ready-${c.code}'),
            value: have || picked != null,
            onChanged: have ? null : (_) => _toggle(c),
            activeColor: udPurple,
          ),
          Expanded(
            child: InkWell(
              onTap: have ? null : () => _toggle(c),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(local ?? c.en, style: udText(15, weight: FontWeight.w600)),
                    Text(
                      local == null ? c.unit.label : '${c.en}, ${c.unit.label}',
                      style: udText(12, color: udBody),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (have) Text('Added', style: udText(12, weight: FontWeight.w600, color: udPaid)),
          if (picked != null)
            SizedBox(
              width: 104,
              child: TextField(
                key: Key('ready-price-${c.code}'),
                controller: picked.$2,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                textAlign: TextAlign.end,
                decoration: InputDecoration(
                  hintText: 'Price',
                  prefixText: '₹',
                  suffixText: '/${c.unit.short}',
                  isDense: true,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
