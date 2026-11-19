import 'package:flutter/material.dart';

import 'onboarding_draft.dart';
import 'widgets/qbox_wave.dart';
import 'widgets/qr_mark.dart';

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
        Text(
          'QBOX',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 26,
            height: 1,
            fontWeight: FontWeight.w800,
            color: _ink,
          ),
        ),
        Spacer(),
        _Bell(),
        SizedBox(width: 10),
        _Profile(),
      ],
    );
  }
}

class _Bell extends StatelessWidget {
  const _Bell();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 36,
      height: 36,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Align(
            alignment: Alignment.center,
            child: Icon(Icons.notifications_none, color: _ink, size: 26),
          ),
          Positioned(
            top: 4,
            right: 4,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Color(0xFFE11D48),
                shape: BoxShape.circle,
              ),
              child: SizedBox(width: 8, height: 8),
            ),
          ),
        ],
      ),
    );
  }
}

class _Profile extends StatelessWidget {
  const _Profile();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFFE4DDF3)),
        color: Colors.white,
      ),
      child: const Icon(Icons.person_outline, color: _purple, size: 22),
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
    _Tool(Icons.grid_view_rounded, 'Payments', drawn: _Drawn.payments, caption: '(Receive and track)'),
    _Tool(Icons.qr_code_2, 'QR & UPI'),
    _Tool(Icons.groups_outlined, 'Udhaar'),
    _Tool(Icons.inventory_2_outlined, 'Stock', drawn: _Drawn.stock, caption: '(Inventory)'),
    _Tool(Icons.local_shipping_outlined, 'Supplier'),
    _Tool(Icons.calculate_outlined, 'Calculator'),
    _Tool(Icons.calendar_month_outlined, 'Calendar'),
    _Tool(Icons.translate, 'Translator'),
    _Tool(Icons.auto_awesome, 'QBOX AI', caption: '(Voice assistant)'),
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
  const _Tool(this.icon, this.label, {this.drawn, this.caption = ''});

  final IconData icon;
  final String label;
  final _Drawn? drawn;
  final String caption;
}

class _ToolTile extends StatelessWidget {
  const _ToolTile({required this.tool});

  final _Tool tool;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
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
            switch (tool.drawn) {
              _Drawn.payments => const QrMark(size: 38),
              _Drawn.stock => const CustomPaint(
                  size: Size.square(38),
                  painter: _StockIconPainter(),
                ),
              null => Icon(tool.icon, color: _purple, size: 38),
            },
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
                  'Manage business, stock, udhaar and more by voice.',
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
