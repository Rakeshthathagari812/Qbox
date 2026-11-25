import 'dart:convert';

import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../services/app_services.dart';
import '../services/device_actions.dart';
import '../udhaar/udhaar_widgets.dart';
import '../widgets/whatsapp_icon.dart';
import 'profile_api.dart';

/// Pages of words kept in the app, so they open without internet. The server
/// shows the same words on the web.
enum LegalPage { help, privacy, terms }

class LegalText {
  const LegalText({required this.title, required this.updated, required this.sections});

  final String title;
  final String updated;
  final List<(String, List<String>)> sections;

  static Future<LegalText> load(AssetBundle bundle, LegalPage page) async {
    final all = jsonDecode(await bundle.loadString('assets/legal/texts.json', cache: false)) as Map<String, dynamic>;
    final json = all[page.name] as Map<String, dynamic>;
    return LegalText(
      title: json['title'] as String,
      updated: json['updated'] as String,
      sections: [
        for (final s in json['sections'] as List) (s[0] as String, [for (final line in s[1] as List) line as String]),
      ],
    );
  }
}

Future<void> openLegal(BuildContext context, LegalPage page) =>
    Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => LegalScreen(page: page)));

/// Help (questions that open), the Privacy Policy, or the Terms.
class LegalScreen extends StatefulWidget {
  const LegalScreen({required this.page, super.key});

  final LegalPage page;

  @override
  State<LegalScreen> createState() => _LegalScreenState();
}

class _LegalScreenState extends State<LegalScreen> {
  AppServices? _services;
  LegalText? _text;
  SupportContact? _support;

  bool get _help => widget.page == LegalPage.help;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_services != null) return;
    _services = ServicesScope.of(context);
    _load(DefaultAssetBundle.of(context));
  }

  Future<void> _load(AssetBundle bundle) async {
    final text = await LegalText.load(bundle, widget.page);
    if (!mounted) return;
    setState(() => _text = text);
    try {
      final support = await _services!.profile.support();
      if (mounted) setState(() => _support = support);
    } on ApiException {
      // Offline: the words are enough.
    }
  }

  Future<void> _open(Uri uri) async {
    if (!await _services!.device.openLink(uri) && mounted) udNotify(context, 'This phone could not open it.');
  }

  @override
  Widget build(BuildContext context) {
    final text = _text;
    return Scaffold(
      backgroundColor: udBackground,
      body: SafeArea(
        child: Column(
          children: [
            UdHeader(
              title: text?.title ?? '',
              subtitle: text == null || _help ? null : 'Last changed: ${text.updated}',
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                children: text == null
                    ? const []
                    : [
                        if (_help)
                          Material(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            clipBehavior: Clip.antiAlias,
                            child: Column(
                              children: [
                                for (final (heading, lines) in text.sections)
                                  ExpansionTile(
                                    key: Key('help-$heading'),
                                    shape: const Border(),
                                    title: Text(heading, style: udText(15, weight: FontWeight.w600)),
                                    childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                                    expandedCrossAxisAlignment: CrossAxisAlignment.start,
                                    children: [for (final l in lines) Text(l, style: udText(14, color: udBody))],
                                  ),
                              ],
                            ),
                          )
                        else
                          for (final (heading, lines) in text.sections) ...[
                            Padding(
                              padding: const EdgeInsets.only(top: 14, bottom: 4),
                              child: Text(heading, style: udText(16, weight: FontWeight.w700)),
                            ),
                            for (final l in lines)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Text(l, style: udText(14, color: udBody)),
                              ),
                          ],
                        ..._contact(),
                        if (_help) ...[
                          const SizedBox(height: 16),
                          TextButton(
                            key: const Key('help-privacy'),
                            onPressed: () => openLegal(context, LegalPage.privacy),
                            child: const Text('Privacy Policy'),
                          ),
                          TextButton(
                            key: const Key('help-terms'),
                            onPressed: () => openLegal(context, LegalPage.terms),
                            child: const Text('Terms of Use'),
                          ),
                        ],
                      ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Shown only when QBOX's own contact is set on the server.
  List<Widget> _contact() {
    final s = _support;
    if (s == null || s.isEmpty) return const [];
    final phone = s.phone;
    final email = s.email;
    final digits = (phone ?? '').replaceAll(RegExp(r'[^0-9]'), '');
    return [
      const SizedBox(height: 20),
      Text('Contact QBOX', style: udText(16, weight: FontWeight.w700)),
      const SizedBox(height: 8),
      UdCard(
        key: const Key('help-contact'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (s.name != null) Text(s.name!, style: udText(14, weight: FontWeight.w600)),
            if (phone != null) Text(phone, style: udText(14, color: udBody)),
            if (email != null) Text(email, style: udText(14, color: udBody)),
            Wrap(
              spacing: 4,
              children: [
                if (phone != null)
                  IconButton(
                    key: const Key('help-call'),
                    onPressed: () => _open(Uri(scheme: 'tel', path: phone)),
                    icon: const Icon(Icons.call_rounded, color: udPurple),
                    tooltip: 'Call',
                  ),
                if (digits.length == 10)
                  IconButton(
                    key: const Key('help-whatsapp'),
                    onPressed: () => _open(whatsAppAppLink(digits, '')),
                    icon: const WhatsAppIcon(),
                    tooltip: 'WhatsApp',
                  ),
                if (email != null)
                  IconButton(
                    key: const Key('help-email'),
                    onPressed: () => _open(Uri(scheme: 'mailto', path: email)),
                    icon: const Icon(Icons.mail_outline_rounded, color: udPurple),
                    tooltip: 'Email',
                  ),
              ],
            ),
          ],
        ),
      ),
    ];
  }
}

/// "By continuing you agree to the Terms and the Privacy Policy."
class LegalAgreement extends StatelessWidget {
  const LegalAgreement({super.key});

  @override
  Widget build(BuildContext context) {
    Widget link(String key, String label, LegalPage page) => InkWell(
      key: Key(key),
      onTap: () => openLegal(context, page),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(label, style: udText(12, weight: FontWeight.w700, color: udPurple)),
      ),
    );
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text('By continuing you agree to the ', style: udText(12, color: udBody)),
        link('agree-terms', 'Terms', LegalPage.terms),
        Text(' and the ', style: udText(12, color: udBody)),
        link('agree-privacy', 'Privacy Policy', LegalPage.privacy),
      ],
    );
  }
}
