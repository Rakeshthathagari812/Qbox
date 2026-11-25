import 'package:flutter/material.dart';

import '../profile/photos.dart';
import '../udhaar/udhaar_models.dart' show rupees, whenLabel;
import '../udhaar/udhaar_widgets.dart';
import 'supply_models.dart';
import 'supply_page.dart';
import 'supply_shop_screen.dart';

/// Opens "Shop Ledger" (Supplier home tile).
Widget openSupplyShops(BuildContext context) => const SupplyShopsScreen();

/// Shops asking to connect, and every connected shop with what it owes.
class SupplyShopsScreen extends StatefulWidget {
  const SupplyShopsScreen({this.now, super.key});

  final DateTime? now;

  @override
  State<SupplyShopsScreen> createState() => _SupplyShopsScreenState();
}

class _SupplyShopsScreenState extends State<SupplyShopsScreen> with SupplyPage<SupplyShopsScreen, SupplyHome> {
  String _search = '';

  @override
  Future<SupplyHome?> loadSaved() => app.supply.savedHome();

  @override
  Future<SupplyHome> loadFresh() => app.supply.home();

  static String _says(int paise) => paise > 0
      ? 'They say they owe you ${rupees(paise)} now.'
      : paise < 0
      ? 'They say they paid you ${rupees(paise)} in advance.'
      : 'They say nothing is due now.';

  Future<void> _accept(SupplyShop shop) async {
    final sure = await askSure(
      context,
      title: 'Connect with ${shop.name}?',
      text: '${_says(shop.balancePaise)}\n\n'
          'Is this right? It becomes the opening balance you both agree on. '
          'From now on you both see the same orders, purchases and payments.',
      action: 'Yes, connect',
    );
    if (!sure || !mounted) return;
    await act(() => app.supply.api.acceptShop(shop.linkId, shop.balancePaise), 'Connected with ${shop.name}');
  }

  Future<void> _decline(SupplyShop shop) async {
    final reason = await askReason(
      context,
      title: 'Do not connect?',
      text: 'If the amount is not right, write it here. ${shop.name} can correct it and ask again.',
      action: 'Do not connect',
      needed: false,
    );
    if (reason == null || !mounted) return;
    await act(() => app.supply.api.declineShop(shop.linkId, reason), 'Not connected');
  }

  Future<void> _open(SupplyShop shop) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => SupplyShopScreen(shop: shop, now: widget.now)),
    );
    if (mounted) await load();
  }

  @override
  Widget build(BuildContext context) {
    final home = data;
    final shops = home?.shops ?? const <SupplyShop>[];
    final shown = shops.where((s) => s.matches(_search)).toList();
    final now = widget.now ?? DateTime.now();
    return Scaffold(
      backgroundColor: udBackground,
      body: SafeArea(
        child: Column(
          children: [
            UdHeader(title: 'Shop Ledger', subtitle: 'What shops owe you', busy: busy),
            errorBanner(),
            Expanded(
              child: RefreshIndicator(
                onRefresh: load,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  children: [
                    if (home != null)
                      UdCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('To get from shops', style: udText(13, color: udBody)),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                rupees(home.totalDuePaise),
                                key: const Key('supply-total'),
                                style: udText(32, weight: FontWeight.w800, color: udDue),
                              ),
                            ),
                          ],
                        ),
                      ),
                    for (final r in home?.requests ?? const <SupplyShop>[]) _request(r, now),
                    if (shops.length > 4)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: TextField(
                          key: const Key('supply-search'),
                          onChanged: (v) => setState(() => _search = v),
                          decoration: InputDecoration(
                            hintText: 'Search shops',
                            isDense: true,
                            filled: true,
                            fillColor: Colors.white,
                            prefixIcon: const Icon(Icons.search_rounded, color: udBody),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: 12),
                    if (home != null && shops.isEmpty && home.requests.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 32),
                        child: Text(
                          'No shops yet.\n\nAsk a shop to add you as a supplier in their QBOX with your login number. '
                          'A code comes to your phone: read it out to them, and you are connected.',
                          key: const Key('supply-empty'),
                          textAlign: TextAlign.center,
                          style: udText(14, color: udBody),
                        ),
                      ),
                    if (shops.isNotEmpty && shown.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Center(child: Text('No shops match.', style: udText(14, color: udBody))),
                      ),
                    for (final s in shown) _tile(s, now),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _request(SupplyShop r, DateTime now) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: UdCard(
      key: Key('request-${r.linkId}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              QboxPhoto(photo: r.photo, icon: Icons.storefront_rounded, size: 46),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${r.name} wants to connect', style: udText(15, weight: FontWeight.w700)),
                    for (final line in [r.category, r.address, r.phone])
                      if ((line ?? '').isNotEmpty) Text(line!, style: udText(12, color: udBody)),
                    if (r.askedAt != null) Text(whenLabel(r.askedAt!, now), style: udText(11, color: udBody)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(_says(r.balancePaise), style: udText(14, weight: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton(
                key: Key('request-yes-${r.linkId}'),
                onPressed: busy ? null : () => _accept(r),
                style: FilledButton.styleFrom(backgroundColor: udPurple),
                child: const Text('Yes, my customer'),
              ),
              OutlinedButton(
                key: Key('request-no-${r.linkId}'),
                onPressed: busy ? null : () => _decline(r),
                child: const Text('No'),
              ),
              ...contactButtons(r.phone, 'request-${r.linkId}'),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _tile(SupplyShop s, DateTime now) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Material(
      color: s.connected ? Colors.white : const Color(0xFFF1EEF7),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        key: Key('shop-${s.linkId}'),
        borderRadius: BorderRadius.circular(16),
        onTap: () => _open(s),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              QboxPhoto(photo: s.photo, icon: Icons.storefront_rounded, size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.name, style: udText(15, weight: FontWeight.w700)),
                    if (s.lastEntryAt != null)
                      Text('Last: ${whenLabel(s.lastEntryAt!, now)}', style: udText(12, color: udBody)),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        if (!s.connected) const UdBadge('Disconnected', color: udBody),
                        if (s.toConfirm > 0) UdBadge('${s.toConfirm} to confirm', color: udWarn),
                        if (s.openOrders > 0)
                          UdBadge(s.openOrders == 1 ? '1 order' : '${s.openOrders} orders', color: udPurple),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 110),
                child: Text(
                  toGetLabel(s.balancePaise),
                  textAlign: TextAlign.end,
                  style: udText(14, weight: FontWeight.w700, color: s.balancePaise > 0 ? udDue : udPaid),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
