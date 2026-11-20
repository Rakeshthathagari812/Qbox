import 'package:flutter/material.dart';

import 'languages.dart';
import 'translation_service.dart';

/// Makes sure the translation packs for [languages] are on the phone.
/// Asks before downloading (one time, about 30 MB each), shows progress,
/// and returns true when every pack is ready.
Future<bool> ensureLanguagePacks(
  BuildContext context,
  TextTranslator translator,
  Iterable<AppLanguage> languages,
) async {
  final missing = <AppLanguage>[];
  for (final l in {...languages, AppLanguage.english}) {
    if (!await translator.isReady(l)) missing.add(l);
  }
  if (missing.isEmpty) return true;
  if (!context.mounted) return false;

  final names = missing.map((l) => l.englishName).join(', ');
  final go = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Download language packs?'),
      content: Text(
        'To translate on this phone (free, and later without internet), QBOX needs '
        'the $names language pack${missing.length > 1 ? 's' : ''}: about 30 MB each, one time only.\n\n'
        'Use Wi-Fi if you can.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Not now')),
        FilledButton(
          key: const Key('pack-download'),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Download'),
        ),
      ],
    ),
  );
  if (go != true || !context.mounted) return false;

  final navigator = Navigator.of(context, rootNavigator: true);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => AlertDialog(
      key: const Key('pack-downloading'),
      content: Row(
        children: [
          const CircularProgressIndicator(),
          const SizedBox(width: 16),
          Expanded(child: Text('Downloading $names…\nThis can take a minute.')),
        ],
      ),
    ),
  );
  var ok = true;
  for (final l in missing) {
    if (!await translator.download(l)) {
      ok = false;
      break;
    }
  }
  navigator.pop();
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Download did not finish. Check the internet and try again.')),
    );
  }
  return ok;
}
