import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/app_services.dart';
import '../udhaar/udhaar_models.dart';
import '../udhaar/udhaar_widgets.dart';
import 'scan_question.dart';
import 'scanned_qr.dart';
import 'transaction_models.dart';

/// Pay a UPI QR that is not a QBOX shop QR: the customer sees who and how much,
/// then their UPI app opens. QBOX cannot see or confirm this payment.
class ScannedUpiScreen extends StatefulWidget {
  const ScannedUpiScreen({required this.qr, super.key});

  final UpiQr qr;

  @override
  State<ScannedUpiScreen> createState() => _ScannedUpiScreenState();
}

class _ScannedUpiScreenState extends State<ScannedUpiScreen> {
  final _amount = TextEditingController();
  String? _error;
  String? _message;
  bool _opened = false;

  UpiQr get _qr => widget.qr;

  /// A signed QR with no amount: the amount is typed in the UPI app.
  bool get _asksAmount => _qr.amountPaise == null && !_qr.signed;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _pay() async {
    int? paise;
    if (_asksAmount) {
      paise = parsePaise(_amount.text);
      if (paise == null || paise < 100) {
        setState(() => _error = 'Enter at least ₹1');
        return;
      }
    }
    FocusScope.of(context).unfocus();
    setState(() => _error = null);
    final app = ServicesScope.of(context);
    final name = _qr.name ?? _qr.upiId;
    final question = ScanQuestion(
      title: name.length > 80 ? name.substring(0, 80) : name,
      at: DateTime.now(),
      upiId: _qr.upiId,
      amountPaise: _qr.amountPaise ?? paise,
    );
    // Kept first: if QBOX is closed meanwhile, it is asked again later.
    await app.transactions.ask(question);
    final opened = await app.device.openLink(_qr.linkFor(paise));
    if (!opened) {
      await app.transactions.answer(question);
      if (mounted) setState(() => _message = 'No UPI app could open.');
      return;
    }
    if (!mounted) return;
    setState(() => _opened = true);
    final message = await askScanQuestion(context, app, question);
    if (mounted) setState(() => _message = message ?? 'Check in your UPI app whether the payment went through.');
  }

  @override
  Widget build(BuildContext context) {
    final fixed = _qr.amountPaise;
    return Scaffold(
      backgroundColor: udBackground,
      body: SafeArea(
        child: Column(
          children: [
            const UdHeader(title: 'Pay by UPI', subtitle: 'From the scanned QR'),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  UdCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Name in the QR', style: udText(12, color: udBody)),
                        Text(
                          _qr.name ?? 'No name',
                          key: const Key('scanned-name'),
                          style: udText(20, weight: FontWeight.w800),
                        ),
                        const SizedBox(height: 6),
                        Text(_qr.upiId, key: const Key('scanned-upi'), style: udText(14, weight: FontWeight.w600)),
                      ],
                    ),
                  ),
                  const UdBanner(
                    icon: Icons.warning_amber_rounded,
                    text: 'QBOX has not checked this QR. Check the name in your UPI app before you enter your PIN.',
                  ),
                  const SizedBox(height: 12),
                  if (_asksAmount || fixed != null)
                    UdCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Amount', style: udText(13, color: udBody)),
                          if (fixed != null)
                            Text(
                              rupees(fixed),
                              key: const Key('scanned-fixed'),
                              style: udText(30, weight: FontWeight.w800),
                            )
                          else
                            TextField(
                              key: const Key('scanned-amount'),
                              controller: _amount,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                              style: udText(30, weight: FontWeight.w800),
                              decoration: InputDecoration(prefixText: '₹ ', errorText: _error),
                            ),
                        ],
                      ),
                    )
                  else
                    Text(
                      'You will enter the amount in your UPI app.',
                      textAlign: TextAlign.center,
                      style: udText(13, color: udBody),
                    ),
                  if (_message != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        _message!,
                        key: const Key('scanned-message'),
                        textAlign: TextAlign.center,
                        style: udText(13, weight: FontWeight.w600, color: udWarn),
                      ),
                    ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 54,
                    child: FilledButton(
                      key: const Key('scanned-pay'),
                      onPressed: _opened ? () => Navigator.of(context).pop() : _pay,
                      style: FilledButton.styleFrom(
                        backgroundColor: udPurple,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        textStyle: udText(17, weight: FontWeight.w700),
                      ),
                      child: Text(_opened ? 'Done' : 'Pay with UPI app'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Real money. QBOX cannot confirm it; you tell QBOX if it went through.',
                    textAlign: TextAlign.center,
                    style: udText(12, color: udBody),
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
