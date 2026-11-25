import 'package:flutter/material.dart';

import 'widgets/qbox_brand.dart';
import 'package:flutter/services.dart';

import 'calculator/calculator_screen.dart';
import 'calendar/calendar_screen.dart';
import 'onboarding_draft.dart';
import 'profile/home_actions.dart';
import 'supply/products_screen.dart';
import 'supply/supply_orders_screen.dart';
import 'supply/supply_payments_screen.dart';
import 'supply/supply_report_screen.dart';
import 'supply/supply_shops_screen.dart';
import 'translator/translator_screen.dart';
import 'widgets/qbox_wave.dart';
import 'widgets/tool_tap.dart';

/// Supplier home shown after the user chooses Supplier.
class SupplierHomeScreen extends StatelessWidget {
  const SupplierHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final draft = OnboardingScope.of(context);
    final entered = draft.supplier.supplierName.trim();
    final name = entered.isEmpty ? 'Sri Venkateswara Suppliers' : entered;
    final qboxId = draft.user?.supplier?.qboxId ?? '—';
    return Scaffold(
      backgroundColor: const Color(0xFFF7F4FF),
      body: Stack(
        children: [
          const Align(
            alignment: Alignment.bottomCenter,
            child: QboxWaveFooter(),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 36, 16, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _TopBar(),
                  const SizedBox(height: 16),
                  _SupplierBar(name: name, qboxId: qboxId),
                  const SizedBox(height: 14),
                  const _DashboardCard(),
                  const SizedBox(height: 14),
                  const _ToolGrid(),
                  const SizedBox(height: 14),
                  const _AskQbox(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        QboxWordmark(fontSize: 26, letterSpacing: 0),
        SizedBox(width: 10),
        DecoratedBox(
          decoration: BoxDecoration(
            color: Color(0xFFE6DCFF),
            borderRadius: BorderRadius.all(Radius.circular(20)),
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            child: Text(
              'Supplier',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 13,
                height: 1,
                fontWeight: FontWeight.w600,
                color: _purple,
              ),
            ),
          ),
        ),
        Spacer(),
        HomeActions(role: QboxRole.supplier),
      ],
    );
  }
}

class _SupplierBar extends StatelessWidget {
  const _SupplierBar({required this.name, required this.qboxId});

  final String name;
  final String qboxId;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: const BoxDecoration(
            color: Color(0xFFEDE4FF),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.local_shipping, color: _purple, size: 24),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 15,
                  height: 1.15,
                  fontWeight: FontWeight.w700,
                  color: _ink,
                ),
              ),
              Row(
                children: [
                  Flexible(
                    child: Text(
                      'Supplier ID: $qboxId',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: _body,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  _CopyId(qboxId: qboxId),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          key: const Key('switch-role'),
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.swap_horiz, size: 16),
          label: const Text('Switch Role'),
          style: OutlinedButton.styleFrom(
            foregroundColor: _purple,
            side: const BorderSide(color: Color(0xFFD9CEF5)),
            backgroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            minimumSize: const Size(0, 38),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            shape: const StadiumBorder(),
            textStyle: const TextStyle(
              fontFamily: 'Poppins',
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _CopyId extends StatelessWidget {
  const _CopyId({required this.qboxId});

  final String qboxId;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Clipboard.setData(ClipboardData(text: qboxId));
      },
      child: const Icon(Icons.copy_rounded, size: 14, color: _purple),
    );
  }
}

class _DashboardCard extends StatelessWidget {
  const _DashboardCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
      decoration: BoxDecoration(
        color: const Color(0xFFEFE8FF),
        borderRadius: BorderRadius.circular(22),
      ),
      child: const Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Supplier Dashboards',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 20,
                    height: 1.15,
                    fontWeight: FontWeight.w800,
                    color: _ink,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Manage orders, supply, payments and ledgers with QBOX.',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 13,
                    height: 1.3,
                    fontWeight: FontWeight.w500,
                    color: _body,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 112,
            height: 86,
            child: Image(
              image: AssetImage('assets/images/art_supplier.png'),
              fit: BoxFit.contain,
            ),
          ),
        ],
      ),
    );
  }
}

class _ToolGrid extends StatelessWidget {
  const _ToolGrid();

  static const _tools = [
    _Tool('Orders', '(From shops)', icon: Icons.add_shopping_cart_outlined, opens: openSupplyOrders),
    _Tool('Shop Ledger', '(All shops)', icon: Icons.menu_book_outlined, opens: openSupplyShops),
    _Tool('Payments', '(From shops)', rupee: true, opens: openSupplyPayments),
    _Tool('Products', '(Prices, stock)', icon: Icons.widgets_outlined, opens: openProducts),
    _Tool('Reports', '', icon: Icons.bar_chart_rounded, opens: openSupplyReport),
    _Tool('Calendar', '', icon: Icons.calendar_month_outlined, opens: openSupplierCalendar),
    _Tool('Calculator', '', icon: Icons.calculate_outlined, opens: openCalculator),
    _Tool('Translator', '', icon: Icons.translate, opens: openTranslator),
  ];

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 0.82,
      children: [
        for (final tool in _tools) _ToolTile(tool: tool),
      ],
    );
  }
}

class _Tool {
  const _Tool(this.title, this.caption, {this.icon, this.rupee = false, this.opens});

  final String title;
  final String caption;
  final IconData? icon;
  final bool rupee;

  /// The screen this tile opens, once the feature is built.
  final WidgetBuilder? opens;
}

class _ToolTile extends StatelessWidget {
  const _ToolTile({required this.tool});

  final _Tool tool;

  @override
  Widget build(BuildContext context) {
    return ToolTap(
      label: tool.title,
      opens: tool.opens,
      child: DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Color(0x120E1B4D),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 12, 6, 10),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (tool.rupee)
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: _purple, width: 1.6),
                ),
                child: const Icon(Icons.currency_rupee, color: _purple, size: 18),
              )
            else
              Icon(tool.icon, color: _purple, size: 30),
            const SizedBox(height: 6),
            Text(
              tool.title,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontSize: 12,
                height: 1.15,
                fontWeight: FontWeight.w700,
                color: _ink,
              ),
            ),
            if (tool.caption.isNotEmpty)
              Text(
                tool.caption,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 10,
                  height: 1.2,
                  fontWeight: FontWeight.w500,
                  color: _body,
                ),
              ),
          ],
        ),
      ),
      ),
    );
  }
}

class _AskQbox extends StatelessWidget {
  const _AskQbox();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF3EEFF),
        borderRadius: BorderRadius.circular(22),
      ),
      child: const Row(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: _purple,
              shape: BoxShape.circle,
            ),
            child: SizedBox(
              width: 52,
              height: 52,
              child: Icon(Icons.mic, color: Colors.white, size: 26),
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Ask QBOX AI',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: _ink,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Check orders, stock, payments and more by voice.',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 12,
                    height: 1.3,
                    fontWeight: FontWeight.w500,
                    color: _body,
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: _purple, size: 22),
        ],
      ),
    );
  }
}

const _ink = Color(0xFF1C0E57);
const _body = Color(0xFF5C5872);
const _purple = Color(0xFF651CE4);
