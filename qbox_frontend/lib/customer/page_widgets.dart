import 'dart:async';

import 'package:flutter/material.dart';

import '../calculator/voice_services.dart';
import '../services/app_services.dart';
import '../services/device_actions.dart';
import '../translator/languages.dart';
import '../translator/voice_language.dart';
import '../udhaar/udhaar_widgets.dart';
import 'page_models.dart';
import 'pages_repository.dart';

/// Speaking into a list or a note, in the shared "Speak in" language.
mixin VoiceWords<T extends StatefulWidget> on State<T> {
  AppServices? _services;
  bool listening = false;
  String heard = '';
  AppLanguage voiceLang = AppLanguage.english;

  AppServices get app => _services!;

  void onServices() {}

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_services != null) return;
    _services = ServicesScope.of(context);
    onServices();
    _readLanguage();
  }

  @override
  void dispose() {
    if (listening) unawaited(app.voice.stop());
    super.dispose();
  }

  Future<void> _readLanguage() async {
    final lang = await readVoiceLanguage(app.settings);
    if (mounted) setState(() => voiceLang = lang);
  }

  Future<void> _pickLanguage() async {
    final picked = await pickVoiceLanguage(
      context,
      current: voiceLang,
      settings: app.settings,
      translator: app.translator,
    );
    if (picked != null && mounted) setState(() => voiceLang = picked);
  }

  /// Starts listening (or stops). [onHeard] gets what was said.
  Future<void> speak(void Function(String words) onHeard, {VoicePace pace = const VoicePace()}) async {
    if (listening) {
      await app.voice.stop();
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      listening = true;
      heard = '';
    });
    try {
      final words = await app.voice.listen(
        localeId: voiceLang.speechLocale,
        pace: pace,
        onWords: (w) {
          if (mounted) setState(() => heard = w);
        },
      );
      if (!mounted) return;
      if (words.trim().isEmpty) {
        udNotify(context, 'Did not hear anything. Tap the mic and try again.');
      } else {
        onHeard(words.trim());
      }
    } on VoiceException catch (e) {
      if (mounted) udNotify(context, e.message);
    } finally {
      if (mounted) setState(() => listening = false);
    }
  }

  Widget voiceChip() => VoiceLanguageChip(
    key: const Key('pages-voice-lang'),
    language: voiceLang,
    onPressed: listening ? null : _pickLanguage,
  );

  Widget heardBox(String hint) => listening
      ? Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: udSoft, borderRadius: BorderRadius.circular(14)),
          child: Text(
            heard.isEmpty ? hint : heard,
            key: const Key('pages-heard'),
            style: udText(14, weight: FontWeight.w600),
          ),
        )
      : const SizedBox.shrink();

  Widget micButton(VoidCallback onPressed) => IconButton.filled(
    key: const Key('pages-mic'),
    onPressed: onPressed,
    style: IconButton.styleFrom(
      backgroundColor: listening ? udDue : udSoft,
      foregroundColor: listening ? Colors.white : udPurple,
      minimumSize: const Size(50, 50),
    ),
    icon: Icon(listening ? Icons.stop_rounded : Icons.mic_rounded),
    tooltip: listening ? 'Stop' : 'Speak',
  );

  Future<void> sendOnWhatsApp(QboxPage page) async {
    final text = shareText(page);
    if (await app.device.openLink(whatsAppShareAppLink(text))) return;
    if (!await app.device.openLink(whatsAppShareLink(text)) && mounted) {
      udNotify(context, 'WhatsApp is not installed on this phone.');
    }
  }
}

/// A message with Undo.
void notifyUndo(BuildContext context, String message, VoidCallback onUndo) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 6),
        persist: false,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 90),
        action: SnackBarAction(label: 'Undo', onPressed: onUndo),
      ),
    );
}

/// No internet, or the server refused something.
class PagesBanner extends StatelessWidget {
  const PagesBanner(this.pages, {super.key});

  final PagesRepository pages;

  @override
  Widget build(BuildContext context) {
    final problem = pages.problem;
    if (!pages.offline && problem == null) return const SizedBox.shrink();
    return UdBanner(
      key: const Key('pages-banner'),
      icon: pages.offline ? Icons.wifi_off_rounded : Icons.error_outline_rounded,
      text: problem != null && !pages.offline
          ? problem
          : pages.waiting
          ? 'Offline: saved on this phone. It will be sent when there is internet.'
          : 'Offline: showing the copy on this phone.',
      actionLabel: 'Retry',
      onAction: pages.busy ? null : pages.refresh,
    );
  }
}

Future<bool> sureToDelete(BuildContext context, QboxPage page) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(page.isList ? 'Delete this list?' : 'Delete this note?'),
        content: Text('"${page.name}" will be deleted.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(
            key: const Key('page-delete-sure'),
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: udDue),
            child: const Text('Delete'),
          ),
        ],
      ),
    ) ??
    false;

/// The name of a list, new or changed. Null = cancelled.
Future<String?> askListName(BuildContext context, {String name = ''}) =>
    showDialog<String>(context: context, builder: (_) => _NameDialog(name));

class _NameDialog extends StatefulWidget {
  const _NameDialog(this.name);

  final String name;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final _name = TextEditingController(text: widget.name);
  String? _error;

  static const _ideas = ['Groceries', 'Vegetables', 'Medicines', 'School', 'Shopping'];

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save() {
    final name = oneLine(_name.text);
    if (name.isEmpty) {
      setState(() => _error = 'Enter a name, like Groceries');
    } else {
      Navigator.of(context).pop(name);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.name.isEmpty;
    return AlertDialog(
      scrollable: true,
      title: Text(isNew ? 'New list' : 'Rename list'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            key: const Key('list-name'),
            controller: _name,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            inputFormatters: [CharLimit(maxTitleChars)],
            decoration: InputDecoration(labelText: 'Name', hintText: 'Groceries', errorText: _error),
            onSubmitted: (_) => _save(),
          ),
          if (isNew) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                for (final idea in _ideas)
                  ActionChip(
                    key: Key('list-idea-$idea'),
                    label: Text(idea, style: udText(12, weight: FontWeight.w600)),
                    onPressed: () => Navigator.of(context).pop(idea),
                  ),
              ],
            ),
          ],
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          key: const Key('list-name-save'),
          onPressed: _save,
          style: FilledButton.styleFrom(backgroundColor: udPurple),
          child: Text(isNew ? 'Create' : 'Save'),
        ),
      ],
    );
  }
}
