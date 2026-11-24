import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../services/api_client.dart';
import '../services/app_services.dart';
import '../udhaar/udhaar_widgets.dart';
import 'payment_models.dart';

/// The shop's own QR, always the same: customers scan it in QBOX
/// (Pay to Shop), type the amount and pay.
class ShopQrScreen extends StatefulWidget {
  const ShopQrScreen({super.key});

  @override
  State<ShopQrScreen> createState() => _ShopQrScreenState();
}

class _ShopQrScreenState extends State<ShopQrScreen> {
  AppServices? _services;
  ShopQrCode? _qr;
  String? _error;
  bool _busy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_services != null) return;
    _services = ServicesScope.of(context);
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final qr = await _services!.payments.shopQr();
      if (mounted) setState(() => _qr = qr);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.isNetwork ? 'Your QR needs internet the first time.' : e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final qr = _qr;
    return Scaffold(
      backgroundColor: udBackground,
      body: SafeArea(
        child: Column(
          children: [
            UdHeader(title: 'My shop QR', subtitle: 'Customers scan this to pay', busy: _busy),
            if (_error != null)
              UdBanner(
                key: const Key('shopqr-error'),
                icon: Icons.wifi_off_rounded,
                text: _error!,
                actionLabel: 'Retry',
                onAction: _busy ? null : _load,
              ),
            if (qr != null)
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    UdCard(
                      child: Column(
                        children: [
                          Text(
                            qr.shopName,
                            textAlign: TextAlign.center,
                            style: udText(24, weight: FontWeight.w800),
                          ),
                          const SizedBox(height: 12),
                          QrImageView(
                            key: const Key('shopqr'),
                            data: qr.data,
                            size: 270,
                            backgroundColor: Colors.white,
                            errorCorrectionLevel: QrErrorCorrectLevel.M,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Scan with QBOX: Pay to Shop',
                            textAlign: TextAlign.center,
                            style: udText(14, weight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      qr.worksInUpiApps
                          ? 'It also holds your UPI ID, for PhonePe, GPay and Paytm. Test it once with ₹1 before '
                                'you print it. If you change your UPI ID, print a new QR.'
                          : 'Add your UPI ID in Payment settings if you want PhonePe, GPay and Paytm to read it too.',
                      key: const Key('shopqr-note'),
                      textAlign: TextAlign.center,
                      style: udText(13, color: udBody),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Take a screenshot to print it. Check sometimes that nobody stuck another QR over yours.',
                      textAlign: TextAlign.center,
                      style: udText(13, color: udBody),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
