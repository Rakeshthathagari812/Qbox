import 'package:flutter/material.dart';

import '../suppliers/supplier_models.dart' show OrderStatus;
import '../udhaar/udhaar_widgets.dart';
import 'supply_models.dart';
import 'supply_order_screen.dart';
import 'supply_page.dart';

/// Opens "Orders" (Supplier home tile).
Widget openSupplyOrders(BuildContext context) => const SupplyOrdersScreen();

/// Every shop's orders: new ones to answer, those being done, and the past.
class SupplyOrdersScreen extends StatefulWidget {
  const SupplyOrdersScreen({this.now, super.key});

  final DateTime? now;

  @override
  State<SupplyOrdersScreen> createState() => _SupplyOrdersScreenState();
}

class _SupplyOrdersScreenState extends State<SupplyOrdersScreen>
    with SingleTickerProviderStateMixin, SupplyPage<SupplyOrdersScreen, List<SupplyOrder>> {
  late final _tabs = TabController(length: 3, vsync: this);

  @override
  Future<List<SupplyOrder>?> loadSaved() => app.supply.savedOrders();

  @override
  Future<List<SupplyOrder>> loadFresh() => app.supply.orders();

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  /// 0 = new, 1 = being done, 2 = past.
  static int _place(SupplyOrder o) => !o.connected
      ? 2
      : switch (o.status) {
          OrderStatus.sent => 0,
          OrderStatus.accepted || OrderStatus.dispatched => 1,
          _ => 2,
        };

  Future<void> _open(SupplyOrder order) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => SupplyOrderScreen(order: order, now: widget.now)),
    );
    if (mounted) await load();
  }

  @override
  Widget build(BuildContext context) {
    final orders = data ?? const <SupplyOrder>[];
    final fresh = orders.where((o) => _place(o) == 0).length;
    final doing = orders.where((o) => _place(o) == 1).length;
    return Scaffold(
      backgroundColor: udBackground,
      body: SafeArea(
        child: Column(
          children: [
            UdHeader(title: 'Orders', subtitle: 'From your shops', busy: busy),
            errorBanner(),
            TabBar(
              controller: _tabs,
              labelColor: udPurple,
              indicatorColor: udPurple,
              unselectedLabelColor: udBody,
              labelStyle: udText(14, weight: FontWeight.w700),
              unselectedLabelStyle: udText(14, weight: FontWeight.w600),
              tabs: [
                Tab(key: const Key('orders-new'), text: fresh == 0 ? 'New' : 'New ($fresh)'),
                Tab(key: const Key('orders-doing'), text: doing == 0 ? 'To give' : 'To give ($doing)'),
                const Tab(key: Key('orders-past'), text: 'Past'),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: [
                  _list(orders, 0, 'No new orders.'),
                  _list(orders, 1, 'Nothing to give now.'),
                  _list(orders, 2, 'No past orders yet.'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _list(List<SupplyOrder> all, int place, String empty) {
    final shown = all.where((o) => _place(o) == place).toList();
    final now = widget.now ?? DateTime.now();
    return RefreshIndicator(
      onRefresh: load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          if (data != null && shown.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 48),
              child: Text(
                empty,
                key: Key('orders-empty-$place'),
                textAlign: TextAlign.center,
                style: udText(14, color: udBody),
              ),
            ),
          for (final o in shown) SupplyOrderTile(order: o, now: now, showShop: true, onTap: () => _open(o)),
        ],
      ),
    );
  }
}
