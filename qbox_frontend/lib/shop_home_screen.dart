import 'package:flutter/material.dart';

import 'widgets/qbox_brand.dart';

import 'ask/ask_screen.dart';
import 'calculator/calculator_screen.dart';
import 'calendar/calendar_screen.dart';
import 'onboarding_draft.dart';
import 'profile/home_actions.dart';
import 'payments/collect_screen.dart';
import 'payments/payments_screen.dart';
import 'services/app_services.dart';
import 'stock/stock_screen.dart';
import 'suppliers/suppliers_screen.dart';
import 'translator/translator_screen.dart';
import 'udhaar/udhaar_screen.dart';
import 'widgets/qbox_wave.dart';
import 'widgets/qr_mark.dart';
import 'widgets/tool_tap.dart';

/// Shop home shown after the user chooses Business / Shop.
class ShopHomeScreen extends StatelessWidget {
  const ShopHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final shopName = OnboardingScope.of(context).shop.shopName.trim();
    final name = shopName.isEmpty ? 'Your Shop' : shopName;
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
                  _ShopBar(name: name),
                  const SizedBox(height: 14),
                  const _GreetingCard(),
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
        Spacer(),
        HomeActions(role: QboxRole.business),
      ],
    );
  }
}

class _ShopBar extends StatelessWidget {
  const _ShopBar({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SizedBox(
          width: 46,
          height: 46,
          child: Image(
            image: AssetImage('assets/images/icon_shop.png'),
            fit: BoxFit.contain,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: _ink,
                      ),
                    ),
                  ),
                  const Icon(Icons.keyboard_arrow_down, color: _ink, size: 20),
                ],
              ),
              const Text(
                'Business / Shop',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: _body,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          key: const Key('switch-role'),
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.swap_horiz, size: 18),
          label: const Text('Switch Role'),
          style: OutlinedButton.styleFrom(
            foregroundColor: _purple,
            side: const BorderSide(color: Color(0xFFD9CEF5)),
            backgroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            minimumSize: const Size(0, 40),
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

class _GreetingCard extends StatelessWidget {
  const _GreetingCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
      decoration: BoxDecoration(
        color: const Color(0xFFEFE8FF),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _greeting(),
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 22,
                    height: 1.15,
                    fontWeight: FontWeight.w800,
                    color: _ink,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Manage your business with QBOX',
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
          const SizedBox(
            width: 120,
            height: 84,
            child: Image(
              image: AssetImage('assets/images/art_business_shop.png'),
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
    _Tool(Icons.grid_view_rounded, 'Payments', drawn: _Drawn.payments, caption: '(Receive and track)',
        opens: openPayments),
    _Tool(Icons.qr_code_2, 'QR & UPI', caption: '(Collect now)', opens: openCollect),
    _Tool(Icons.groups_outlined, 'Udhaar', caption: '(Credit book)', opens: openUdhaar),
    _Tool(Icons.inventory_2_outlined, 'Stock', drawn: _Drawn.stock, caption: '(Inventory)', opens: openStock,
        lowStockBadge: true),
    _Tool(Icons.local_shipping_outlined, 'Supplier', caption: '(Buy and pay)', opens: openSuppliers),
    _Tool(Icons.calculate_outlined, 'Calculator', opens: openCalculator),
    _Tool(Icons.calendar_month_outlined, 'Calendar', opens: openShopCalendar),
    _Tool(Icons.translate, 'Translator', caption: '(Voice, 5 languages)', opens: openTranslator),
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

enum _Drawn { payments, stock }

class _Tool {
  const _Tool(this.icon, this.label, {this.drawn, this.caption = '', this.opens, this.lowStockBadge = false});

  final IconData icon;
  final String label;
  final _Drawn? drawn;
  final String caption;

  /// Shows a red count of items running low.
  final bool lowStockBadge;

  /// The screen this tile opens, once the feature is built.
  final WidgetBuilder? opens;
}

class _ToolTile extends StatelessWidget {
  const _ToolTile({required this.tool});

  final _Tool tool;

  @override
  Widget build(BuildContext context) {
    return ToolTap(
      label: tool.label,
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
        padding: const EdgeInsets.fromLTRB(6, 14, 6, 12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                switch (tool.drawn) {
                  _Drawn.payments => const QrMark(size: 38),
                  _Drawn.stock => const CustomPaint(
                      size: Size.square(38),
                      painter: _StockIconPainter(),
                    ),
                  null => Icon(tool.icon, color: _purple, size: 38),
                },
                if (tool.lowStockBadge) const Positioned(top: -6, right: -10, child: _LowStockBadge()),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              tool.label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontSize: 12,
                height: 1.1,
                fontWeight: FontWeight.w600,
                color: _ink,
              ),
            ),
            if (tool.caption.isNotEmpty)
              Text(
                tool.caption,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 10,
                  height: 1.15,
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

/// Red count of items running low (from the stock saved on the phone).
class _LowStockBadge extends StatefulWidget {
  const _LowStockBadge();

  @override
  State<_LowStockBadge> createState() => _LowStockBadgeState();
}

class _LowStockBadgeState extends State<_LowStockBadge> {
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    ServicesScope.of(context).stock.savedBook(); // fills in the count
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: ServicesScope.of(context).stock.lowCount,
      builder: (context, low, _) => low == 0
          ? const SizedBox.shrink()
          : Container(
              key: const Key('stock-low-badge'),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(color: const Color(0xFFE11D48), borderRadius: BorderRadius.circular(10)),
              child: Text(
                '$low',
                style: const TextStyle(fontFamily: 'Poppins', fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white),
              ),
            ),
    );
  }
}

class _AskQbox extends StatelessWidget {
  const _AskQbox();

  @override
  Widget build(BuildContext context) =>
      const AskCard(role: QboxRole.business, title: 'Ask QBOX AI', about: 'Manage business, stock, udhaar and more by voice.');
}

String _greeting() {
  final hour = DateTime.now().hour;
  if (hour < 12) return 'Good Morning!';
  if (hour < 17) return 'Good Afternoon!';
  return 'Good Evening!';
}

const _ink = Color(0xFF1C0E57);
const _body = Color(0xFF5C5872);
const _purple = Color(0xFF651CE4);

/// A simple box, drawn to match the Stock tile.
class _StockIconPainter extends CustomPainter {
  const _StockIconPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.shortestSide;
    final paint = Paint()
      ..color = _purple
      ..style = PaintingStyle.stroke
      ..strokeWidth = side * 0.07
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;

    Offset at(double x, double y) => Offset(side * x, side * y);
    final top = at(0.50, 0.08);
    final left = at(0.10, 0.28);
    final right = at(0.90, 0.28);
    final mid = at(0.50, 0.48);
    final lowLeft = at(0.10, 0.72);
    final lowRight = at(0.90, 0.72);
    final bottom = at(0.50, 0.92);

    final path = Path()
      ..moveTo(top.dx, top.dy)
      ..lineTo(right.dx, right.dy)
      ..lineTo(lowRight.dx, lowRight.dy)
      ..lineTo(bottom.dx, bottom.dy)
      ..lineTo(lowLeft.dx, lowLeft.dy)
      ..lineTo(left.dx, left.dy)
      ..close()
      ..moveTo(left.dx, left.dy)
      ..lineTo(mid.dx, mid.dy)
      ..lineTo(right.dx, right.dy)
      ..moveTo(mid.dx, mid.dy)
      ..lineTo(bottom.dx, bottom.dy);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
