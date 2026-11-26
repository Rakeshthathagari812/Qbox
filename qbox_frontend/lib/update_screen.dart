import 'package:flutter/material.dart';

import 'services/app_services.dart';
import 'splash_screen.dart';

/// True when this build is too old to be used. Never when it cannot be known
/// (no internet, or an older server): QBOX then opens as usual.
Future<String?> updateNeeded(AppServices services) async {
  try {
    final build = await services.device.appBuild();
    if (build == null) return null;
    final allowed = await services.profile.versions();
    return build < allowed.minBuild ? allowed.updateUrl ?? '' : null;
  } catch (_) {
    return null;
  }
}

/// This QBOX is too old: nothing else can be done until it is updated. What is
/// saved on the phone stays.
class UpdateScreen extends StatelessWidget {
  const UpdateScreen({required this.url, super.key});

  /// Where the new one is. Empty = not known.
  final String url;

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xFF1C0E57);
    final link = Uri.tryParse(url);
    final canOpen = link != null && link.scheme == 'https';
    return PopScope(
      canPop: false,
      child: Scaffold(
        key: const Key('update-screen'),
        backgroundColor: const Color(0xFFF4F0FD),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const QboxSymbol(size: 110),
                  const SizedBox(height: 24),
                  const Text(
                    'Please update QBOX',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 22, fontWeight: FontWeight.w700, color: ink),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    canOpen
                        ? 'This version is too old to use safely. Your data is safe and will be here after the update.'
                        : 'This version is too old to use safely. Get the new one from the Play Store. Your data is safe.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontFamily: 'Poppins', fontSize: 15, height: 1.5, color: ink),
                  ),
                  if (canOpen) ...[
                    const SizedBox(height: 24),
                    FilledButton(
                      key: const Key('update-now'),
                      onPressed: () => ServicesScope.of(context).device.openLink(link),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF5B21E6),
                        minimumSize: const Size(220, 52),
                        textStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                      child: const Text('Update now'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
