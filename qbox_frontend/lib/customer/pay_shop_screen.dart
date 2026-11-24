import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../payments/payment_models.dart';
import '../services/api_client.dart';
import '../services/app_services.dart';
import '../udhaar/udhaar_models.dart';
import '../udhaar/udhaar_widgets.dart';
import '../widgets/qbox_brand.dart';
import 'pay_amount_screen.dart';
import 'pay_number_screen.dart';
import 'scan_camera.dart';
import 'scan_question.dart';
import 'scanned_qr.dart';
import 'scanned_upi_screen.dart';
import 'transaction_models.dart';

/// Opens "Pay to Shop" (Customer home tile).
Widget openPayShop(BuildContext context) => const PayShopScreen();

/// Opens straight on the camera; below it: Upload QR, Torch and Number.
class PayShopScreen extends StatefulWidget {
  const PayShopScreen({this.camera, super.key});

  /// For tests: a pretend camera.
  final QrCamera? camera;

  @override
  State<PayShopScreen> createState() => _PayShopScreenState();
}

class _PayShopScreenState extends State<PayShopScreen> {
  /// The camera sees the same QR many times a second; it counts once.
  static const _sameAgainAfter = Duration(seconds: 3);

  late final QrCamera _camera = widget.camera ?? PhoneQrCamera();
  AppServices? _services;
  List<UnfinishedUpi> _unfinished = const [];
  List<ScanQuestion> _questions = const [];
  String? _error;
  bool _busy = false;

  /// Another screen or a question is open: the camera is off.
  bool _paused = false;
  String _lastText = '';
  DateTime _lastAt = DateTime(2000);

  AppServices get _app => _services!;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_services != null) return;
    _services = ServicesScope.of(context);
    _load();
  }

  @override
  void dispose() {
    _camera.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final questions = await _app.transactions.questions();
    if (!mounted) return;
    setState(() => _questions = questions);
    try {
      final shops = await _app.payments.payShops();
      if (mounted) {
        setState(() {
          _unfinished = shops.unfinished;
          _error = null;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.isNetwork ? 'Paying needs internet.' : e.message);
    }
  }

  /// Runs [work] with the camera off, then scans again.
  Future<void> _withoutCamera(Future<void> Function() work) async {
    if (_paused) return;
    setState(() => _paused = true);
    try {
      await work();
    } finally {
      if (mounted) {
        setState(() => _paused = false);
        _lastAt = DateTime.now(); // the same QR is probably still in front of the camera
      }
    }
  }

  Future<void> _push(Widget screen) async {
    await Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => screen));
    if (mounted) await _load();
  }

  void _onText(String text) {
    if (!mounted || _paused || text.trim().isEmpty) return;
    final now = DateTime.now();
    if (text == _lastText && now.difference(_lastAt) < _sameAgainAfter) return;
    _lastText = text;
    _lastAt = now;
    _open(text);
  }

  Future<void> _open(String text) async {
    final qr = readQr(text);
    if (qr is UnknownQr) {
      udNotify(context, 'This is not a payment QR.');
      return;
    }
    HapticFeedback.mediumImpact();
    await _withoutCamera(() async {
      switch (qr) {
        case ShopQr(:final code):
          await _openShop(code);
        case UpiQr():
          await _push(ScannedUpiScreen(qr: qr));
        case PageQr(:final uri):
          await _openPage(uri);
        case UnknownQr():
      }
    });
  }

  Future<void> _openShop(String code) async {
    setState(() => _busy = true);
    PayShop? shop;
    try {
      shop = await _app.payments.scanShop(code);
    } on ApiException catch (e) {
      if (mounted) udNotify(context, e.isNetwork ? 'Paying needs internet. Please try again.' : e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (shop != null && mounted) await _push(PayAmountScreen(shop: shop));
  }

  Future<void> _openPage(Uri uri) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Open Razorpay payment page?'),
        content: const Text('Check the shop name and the amount on the page before you pay.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(
            key: const Key('page-open'),
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: udPurple),
            child: const Text('Open'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    final question = ScanQuestion(title: 'Razorpay payment', at: DateTime.now());
    await _app.transactions.ask(question);
    if (!await _app.device.openLink(uri)) {
      await _app.transactions.answer(question);
      if (mounted) udNotify(context, 'The page could not open.');
      return;
    }
    if (!mounted) return;
    final message = await askScanQuestion(context, _app, question);
    if (mounted && message != null) udNotify(context, message);
    if (mounted) await _load();
  }

  Future<void> _upload() async {
    String? text;
    await _withoutCamera(() async => text = await _camera.readPicture());
    final found = text;
    if (found == null || !mounted) return;
    if (found.isEmpty) {
      udNotify(context, 'No QR was found in that picture.');
    } else {
      await _open(found);
    }
  }

  /// The question left open when a UPI app was opened and QBOX was closed.
  Future<void> _answer(UnfinishedUpi u, {required bool paid}) async {
    setState(() => _busy = true);
    try {
      paid ? await _app.payments.claimUpi(u.payment.id) : await _app.payments.dropUpi(u.payment.id);
      if (mounted) udNotify(context, paid ? '${u.shopName} will confirm your payment.' : 'Not recorded.');
    } on ApiException catch (e) {
      if (mounted) udNotify(context, e.isNetwork ? 'This needs internet. Please try again.' : e.message);
    }
    if (mounted) await _load();
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _answerScan(ScanQuestion q, {required bool paid}) async {
    String? message;
    if (paid && q.amountPaise == null) {
      await _withoutCamera(() async => message = await askScanQuestion(context, _app, q)); // asks the amount
    } else {
      message = await answerScanQuestion(_app, q, paid ? q.amountPaise : null);
    }
    if (!mounted) return;
    if (message != null) udNotify(context, message!);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final asked = _unfinished.firstOrNull;
    final scan = _questions.firstOrNull;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            if (!_paused) _camera.view(_onText),
            SafeArea(
              child: Column(
                children: [
                  _header(),
                  if (_error != null)
                    UdBanner(
                      key: const Key('payshop-error'),
                      icon: Icons.wifi_off_rounded,
                      text: _error!,
                      actionLabel: 'Retry',
                      onAction: _load,
                    ),
                  if (asked != null)
                    _question(
                      id: '${asked.payment.id}',
                      text: 'Did you pay ${rupees(asked.payment.amountPaise)} to ${asked.shopName} by UPI?',
                      onAnswer: (paid) => _answer(asked, paid: paid),
                    )
                  else if (scan != null)
                    _question(
                      id: 'scan',
                      text: scan.amountPaise == null
                          ? 'Did your payment to ${scan.title} go through?'
                          : 'Did you pay ${rupees(scan.amountPaise!)} to ${scan.title}?',
                      onAnswer: (paid) => _answerScan(scan, paid: paid),
                    ),
                  Expanded(
                    child: IgnorePointer(
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(40),
                          child: AspectRatio(
                            aspectRatio: 1,
                            child: CustomPaint(
                              painter: const _Corners(),
                              child: _busy
                                  ? const Center(child: CircularProgressIndicator(color: Colors.white))
                                  : null,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  _buttons(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header() => Padding(
    padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
    child: Row(
      children: [
        IconButton(
          key: const Key('udhaar-back'),
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 28),
          tooltip: 'Back',
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Scan any QR', style: udText(20, weight: FontWeight.w700, color: Colors.white)),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  'QBOX • PhonePe • Google Pay • BHIM • Paytm',
                  style: udText(13, color: Colors.white70),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _buttons() => Container(
    width: double.infinity,
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 28),
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0x00000000), Color(0xB3000000)],
      ),
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _RoundButton(
          key: const Key('payshop-upload'),
          icon: Icons.image_outlined,
          label: 'Upload QR',
          onTap: _busy ? null : _upload,
        ),
        ValueListenableBuilder(
          valueListenable: _camera.torch,
          builder: (context, on, _) => _RoundButton(
            key: const Key('payshop-torch'),
            icon: on ? Icons.flashlight_off_rounded : Icons.flashlight_on_rounded,
            label: 'Torch',
            lit: on,
            onTap: _camera.toggleTorch,
          ),
        ),
        _RoundButton(
          key: const Key('payshop-number'),
          icon: Icons.dialpad_rounded,
          label: 'Number',
          onTap: _busy ? null : () => _withoutCamera(() => _push(const PayNumberScreen())),
        ),
      ],
    ),
  );

  Widget _question({required String id, required String text, required void Function(bool paid) onAnswer}) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
    child: UdCard(
      key: Key('payshop-unfinished-$id'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(text, style: udText(15, weight: FontWeight.w700)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              TextButton(
                key: Key('payshop-no-$id'),
                onPressed: _busy ? null : () => onAnswer(false),
                child: const Text('No'),
              ),
              FilledButton(
                key: Key('payshop-yes-$id'),
                onPressed: _busy ? null : () => onAnswer(true),
                style: FilledButton.styleFrom(backgroundColor: udPaid),
                child: const Text('Yes, I paid'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.label, required this.onTap, this.lit = false, super.key});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool lit;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: InkResponse(
        onTap: onTap,
        radius: 56,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: lit ? Colors.white : const Color(0x4DFFFFFF),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 28, color: lit ? Colors.black : Colors.white),
            ),
            const SizedBox(height: 8),
            ExcludeSemantics(child: Text(label, style: udText(13, color: Colors.white))),
          ],
        ),
      ),
    );
  }
}

/// The four corners of the scanning square, in the QBOX colours.
class _Corners extends CustomPainter {
  const _Corners();

  @override
  void paint(Canvas canvas, Size size) {
    final area = Offset.zero & size;
    final paint = Paint()
      ..shader = const LinearGradient(colors: qboxBrandColors).createShader(area)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
    final arm = size.width * 0.12;
    const bend = 24.0;
    final w = size.width, h = size.height;
    for (final (x, y, dx, dy) in [(0.0, 0.0, 1, 1), (w, 0.0, -1, 1), (0.0, h, 1, -1), (w, h, -1, -1)]) {
      canvas.drawPath(
        Path()
          ..moveTo(x, y + dy * (bend + arm))
          ..lineTo(x, y + dy * bend)
          ..quadraticBezierTo(x, y, x + dx * bend, y)
          ..lineTo(x + dx * (bend + arm), y),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_Corners oldDelegate) => false;
}
