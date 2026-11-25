import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../stock/stock_catalog.dart';
import '../stock/stock_models.dart';
import '../translator/languages.dart';
import '../udhaar/udhaar_models.dart' show rupees;
import '../udhaar/udhaar_widgets.dart';
import 'supplier_models.dart';

/// How much of each of a supplier's products the shop wants.
class Cart {
  final Map<int, TextEditingController> _qty = {};

  TextEditingController controller(int id) => _qty.putIfAbsent(id, TextEditingController.new);

  bool has(int id) => (_qty[id]?.text ?? '').isNotEmpty;

  void set(int id, int qtyMilli) => controller(id).text = qtyMilli <= 0 ? '' : qtyNumber(qtyMilli);

  /// One more, or one less (less than one = taken out).
  void step(int id, int by) => set(id, (parseQty(controller(id).text) ?? 0) + by);

  /// What was chosen, of [products] that can be ordered. Null = something typed
  /// is not a number.
  List<EntryLine>? lines(List<SupplierProduct> products) {
    final out = <EntryLine>[];
    for (final p in products) {
      if (!p.available || !has(p.id)) continue;
      final qty = parseQty(_qty[p.id]!.text);
      if (qty == null) return null;
      if (qty == 0) continue;
      out.add(
        EntryLine(
          productId: p.id,
          name: p.name,
          unit: p.unit,
          qtyMilli: qty,
          costPaise: p.pricePaise,
          catalogCode: p.catalogCode,
        ),
      );
    }
    return out;
  }

  void clear() {
    for (final c in _qty.values) {
      c.clear();
    }
  }

  void dispose() {
    for (final c in _qty.values) {
      c.dispose();
    }
  }
}

/// Does a product match a search, in any of the app's languages?
bool productMatches(SupplierProduct p, String search) {
  final q = search.trim().toLowerCase();
  return q.isEmpty ||
      p.name.toLowerCase().contains(q) ||
      (catalogItem(p.catalogCode)?.allNames.any((n) => n.toLowerCase().contains(q)) ?? false);
}

/// One product: price, and Add, then - how much +.
class SupplierProductTile extends StatelessWidget {
  const SupplierProductTile({
    required this.product,
    required this.cart,
    required this.onChanged,
    this.language = AppLanguage.english,
    super.key,
  });

  final SupplierProduct product;
  final Cart cart;
  final VoidCallback onChanged;
  final AppLanguage language;

  void _step(int by) {
    cart.step(product.id, by);
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final p = product;
    final local = language == AppLanguage.english ? null : catalogItem(p.catalogCode)?.nameIn(language);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      decoration: BoxDecoration(
        color: p.available ? Colors.white : const Color(0xFFF1EEF7),
        borderRadius: BorderRadius.circular(16),
      ),
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
                if (p.pricePaise != null || p.available)
                  Text(
                    p.pricePaise == null ? 'Price on the bill' : '${rupees(p.pricePaise!)}/${p.unit.short}',
                    style: udText(13, color: udBody),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (!p.available)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Text('Not available', style: udText(12, weight: FontWeight.w600, color: udDue)),
            )
          else if (!cart.has(p.id))
            OutlinedButton(
              key: Key('product-add-${p.id}'),
              onPressed: () => _step(milli),
              style: OutlinedButton.styleFrom(
                foregroundColor: udPurple,
                side: const BorderSide(color: udPurple, width: 1.5),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Add'),
            )
          else ...[
            IconButton(
              key: Key('product-less-${p.id}'),
              onPressed: () => _step(-milli),
              icon: const Icon(Icons.remove_circle_outline_rounded, color: udPurple),
              tooltip: 'Less',
            ),
            SizedBox(
              width: 62,
              child: TextField(
                key: Key('product-qty-${p.id}'),
                controller: cart.controller(p.id),
                onChanged: (_) => onChanged(),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                textAlign: TextAlign.center,
                decoration: InputDecoration(suffixText: p.unit.short, isDense: true),
              ),
            ),
            IconButton(
              key: Key('product-more-${p.id}'),
              onPressed: () => _step(milli),
              icon: const Icon(Icons.add_circle_outline_rounded, color: udPurple),
              tooltip: 'More',
            ),
          ],
        ],
      ),
    );
  }
}
