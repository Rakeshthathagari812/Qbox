import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../payments/payment_models.dart';
import '../services/api_client.dart';
import '../services/app_services.dart';
import '../udhaar/udhaar_models.dart';
import '../profile/photos.dart';
import '../udhaar/udhaar_widgets.dart';
import 'pay_amount_screen.dart';

/// Pay a shop by its QBOX number, or choose one of your own shops.
class PayNumberScreen extends StatefulWidget {
  const PayNumberScreen({super.key});

  @override
  State<PayNumberScreen> createState() => _PayNumberScreenState();
}

class _PayNumberScreenState extends State<PayNumberScreen> {
  final _mobile = TextEditingController();
  AppServices? _services;
  List<PayShop> _shops = const [];
  String? _error;
  String? _findError;
  bool _busy = false;

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
    _mobile.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _busy = true);
    try {
      final shops = await _app.payments.payShops();
      if (mounted) {
        setState(() {
          _shops = shops.shops;
          _error = null;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.isNetwork ? 'Paying needs internet.' : e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickContact() async {
    final contact = await _app.device.pickContact();
    if (contact == null || !mounted) return;
    final mobile = normalizeMobile(contact.phone);
    setState(() {
      _mobile.text = mobile ?? '';
      _findError = mobile == null ? 'That contact has no 10-digit mobile number' : null;
    });
  }

  Future<void> _find() async {
    final mobile = normalizeMobile(_mobile.text);
    if (mobile == null) {
      setState(() => _findError = 'Enter a 10-digit mobile number');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _findError = null;
    });
    PayShop? shop;
    try {
      shop = await _app.payments.findShop(mobile);
    } on ApiException catch (e) {
      if (mounted) setState(() => _findError = e.isNetwork ? 'Paying needs internet.' : e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (shop != null && mounted) await _open(shop);
  }

  Future<void> _open(PayShop shop) async {
    await Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => PayAmountScreen(shop: shop)));
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: udBackground,
      body: SafeArea(
        child: Column(
          children: [
            UdHeader(title: 'Phone number', subtitle: 'Pay to Shop', busy: _busy),
            if (_error != null)
              UdBanner(
                key: const Key('paynumber-error'),
                icon: Icons.wifi_off_rounded,
                text: _error!,
                actionLabel: 'Retry',
                onAction: _busy ? null : _load,
              ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                children: [
                  UdCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Shop's QBOX number", style: udText(13, color: udBody)),
                        TextField(
                          key: const Key('payshop-mobile'),
                          controller: _mobile,
                          keyboardType: TextInputType.phone,
                          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+ -]'))],
                          style: udText(18, weight: FontWeight.w700),
                          onSubmitted: (_) => _find(),
                          decoration: InputDecoration(
                            prefixText: '+91 ',
                            errorText: _findError,
                            errorMaxLines: 3,
                            suffixIcon: IconButton(
                              key: const Key('payshop-contact'),
                              onPressed: _pickContact,
                              icon: const Icon(Icons.contacts_outlined, color: udPurple),
                              tooltip: 'Contacts',
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: FilledButton(
                            key: const Key('payshop-find'),
                            onPressed: _busy ? null : _find,
                            style: FilledButton.styleFrom(
                              backgroundColor: udPurple,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              textStyle: udText(16, weight: FontWeight.w700),
                            ),
                            child: const Text('Find shop'),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_shops.isNotEmpty) ...[
                    Text('Your shops', style: udText(16, weight: FontWeight.w700)),
                    const SizedBox(height: 8),
                  ],
                  for (final s in _shops)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: Material(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        child: InkWell(
                          key: Key('payshop-${s.ref}'),
                          borderRadius: BorderRadius.circular(18),
                          onTap: _busy ? null : () => _open(s),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                QboxPhoto(photo: s.shopPhoto, icon: Icons.storefront_rounded),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(s.shopName, style: udText(15, weight: FontWeight.w700)),
                                      if ((s.shopCategory ?? '').isNotEmpty)
                                        Text(s.shopCategory!, style: udText(12, color: udBody)),
                                    ],
                                  ),
                                ),
                                const Icon(Icons.chevron_right_rounded, color: udPurple),
                              ],
                            ),
                          ),
                        ),
                      ),
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
