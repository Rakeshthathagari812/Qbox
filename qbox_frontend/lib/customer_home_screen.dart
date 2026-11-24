import 'package:flutter/material.dart';

import 'widgets/qbox_brand.dart';
import 'package:flutter/services.dart';

import 'calculator/calculator_screen.dart';
import 'calendar/calendar_screen.dart';
import 'customer/checklist_notes_screen.dart';
import 'customer/expenses_screen.dart';
import 'customer/pay_shop_screen.dart';
import 'customer/transactions_screen.dart';
import 'onboarding_draft.dart';
import 'profile/home_actions.dart';
import 'translator/translator_screen.dart';
import 'udhaar/my_udhaar_screen.dart';
import 'widgets/qr_mark.dart';
import 'widgets/qbox_wave.dart';
import 'widgets/tool_tap.dart';

/// Customer home shown after the user chooses Customer.
class CustomerHomeScreen extends StatelessWidget {
  const CustomerHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final draft = OnboardingScope.of(context);
    final entered = draft.customer.fullName.trim();
    final name = entered.isEmpty ? 'Ramu' : entered;
    final qboxId = draft.user?.customer?.qboxId ?? '—';
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
                  _HelloBar(name: name, qboxId: qboxId),
                  const SizedBox(height: 14),
                  const _YourQboxCard(),
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
              'Customer',
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
        HomeActions(role: QboxRole.customer),
      ],
    );
  }
}

class _HelloBar extends StatelessWidget {
  const _HelloBar({required this.name, required this.qboxId});

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
          child: const Icon(Icons.person, color: _purple, size: 26),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Hello, $name 👋',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: _ink,
                ),
              ),
              Row(
                children: [
                  Flexible(
                    child: Text(
                      'QBOX ID: $qboxId',
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

class _YourQboxCard extends StatelessWidget {
  const _YourQboxCard();

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
                  'Your QBOX',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 22,
                    height: 1.15,
                    fontWeight: FontWeight.w800,
                    color: _ink,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Manage your payments, udhaar and shop accounts in one place.',
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
              image: AssetImage('assets/images/art_customer.png'),
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

  /// My QR is not built yet (customers are found by phone number): hidden.
  static const _showMyQr = false;

  static const _tools = [
    if (_showMyQr) _Tool('My QR', '(Customer ID)', qr: true),
    _Tool('Pay to Shop', '(QR or number)', icon: Icons.account_balance_wallet_outlined, opens: openPayShop),
    _Tool('My Udhaar', '(Dues)', icon: Icons.receipt_long_outlined, opens: openMyUdhaar),
    _Tool('Transaction History', '', icon: Icons.history, opens: openTransactions),
    _Tool('Translator', '', icon: Icons.translate, opens: openTranslator),
    _Tool('Calculator', '', icon: Icons.calculate_outlined, opens: openCalculator),
    _Tool('Calendar', '', icon: Icons.calendar_month_outlined, opens: openCustomerCalendar),
    _Tool('Expenses Tracking', '', coins: true, opens: openExpenses),
    _Tool('Checklist & Notes', '', icon: Icons.checklist_rounded, opens: openChecklistNotes),
  ];

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 0.86,
      children: [
        for (final tool in _tools) _ToolTile(tool: tool),
      ],
    );
  }
}

class _Tool {
  const _Tool(
    this.title,
    this.caption, {
    this.icon,
    this.qr = false,
    this.coins = false,
    this.opens,
  });

  final String title;
  final String caption;
  final IconData? icon;
  final bool qr;
  final bool coins;

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
            _ToolMark(tool: tool),
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

class _ToolMark extends StatelessWidget {
  const _ToolMark({required this.tool});

  final _Tool tool;

  @override
  Widget build(BuildContext context) {
    if (tool.qr) return const QrMark(size: 30);
    if (tool.coins) {
      return const CustomPaint(
        size: Size.square(30),
        painter: _CoinsPainter(),
      );
    }
    return Icon(tool.icon, color: _purple, size: 30);
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
                  'Ask QBOX',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: _ink,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Check dues, payments, shop details and more by voice.',
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

class _CoinsPainter extends CustomPainter {
  const _CoinsPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = _purple
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.07;
    final w = size.width;
    final h = size.height;
    for (var i = 0; i < 3; i++) {
      final top = h * (0.08 + (2 - i) * 0.22);
      canvas.drawOval(
        Rect.fromLTWH(w * 0.14, top, w * 0.72, h * 0.26),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

const _ink = Color(0xFF1C0E57);
const _body = Color(0xFF5C5872);
const _purple = Color(0xFF651CE4);
