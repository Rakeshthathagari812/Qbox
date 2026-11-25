import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../calculator/voice_services.dart';
import '../services/app_services.dart';
import '../udhaar/udhaar_widgets.dart';
import 'indic_numbers.dart';
import 'language_packs.dart';
import 'languages.dart';
import 'translation_service.dart';

/// Opens the Translator (home tile).
Widget openTranslator(BuildContext context) => const TranslatorScreen();

/// Two people, two languages: each taps their own mic and speaks; QBOX shows
/// the words in both languages and says the translation out loud.
///
/// Hearing: the QBOX server's speech model for Indian languages (the phone's
/// own for English, or when offline). Translating: the QBOX server, or the
/// on-phone translator when offline. Speaking: the phone's own voice.
/// No model or company names are shown to the user.
class TranslatorScreen extends StatefulWidget {
  const TranslatorScreen({super.key});

  @override
  State<TranslatorScreen> createState() => _TranslatorScreenState();
}

class _Line {
  const _Line({
    required this.fromLeft,
    required this.from,
    required this.to,
    required this.heard,
    this.translated,
  });

  final bool fromLeft;
  final AppLanguage from;
  final AppLanguage to;
  final String heard;

  /// Null while it is being translated.
  final String? translated;
}

class _TranslatorScreenState extends State<TranslatorScreen> {
  static const _leftKey = 'translator_left';
  static const _rightKey = 'translator_right';

  AppServices? _services;
  AppLanguage _left = AppLanguage.telugu; // usually the shopkeeper
  AppLanguage _right = AppLanguage.hindi; // usually the customer
  final List<_Line> _lines = [];
  final _scroll = ScrollController();
  bool? _listeningLeft; // null = not listening
  bool _working = false;

  /// The microphone is really open (else it is still getting ready).
  bool _micOpen = false;
  String _heard = '';
  final Set<AppLanguage> _missingVoices = {};

  AppServices get _app => _services!;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_services != null) return;
    _services = ServicesScope.of(context);
    final voice = _app.voice;
    if (voice is VoiceWarmUp) unawaited((voice as VoiceWarmUp).warmUp(localeId: _left.speechLocale));
    _loadChoices();
  }

  @override
  void dispose() {
    if (_listeningLeft != null) unawaited(_app.voice.stop());
    unawaited(_app.speaker.stop());
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadChoices() async {
    final left = AppLanguage.fromCode(await _app.settings.read(_leftKey), fallback: _left);
    final right = AppLanguage.fromCode(await _app.settings.read(_rightKey), fallback: _right);
    if (!mounted || left == right) return;
    setState(() {
      _left = left;
      _right = right;
    });
  }

  void _choose({required bool left, required AppLanguage language}) {
    setState(() {
      if (left) {
        if (language == _right) _right = _left; // picking the other side's language swaps them
        _left = language;
      } else {
        if (language == _left) _left = _right;
        _right = language;
      }
    });
    _saveChoices();
  }

  void _swap() {
    setState(() {
      final l = _left;
      _left = _right;
      _right = l;
    });
    _saveChoices();
  }

  void _saveChoices() {
    unawaited(_app.settings.write(_leftKey, _left.code));
    unawaited(_app.settings.write(_rightKey, _right.code));
  }

  /// Above the mic buttons, so it never covers them.
  void _notify(String message) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 150),
      ),
    );

  Future<void> _speak({required bool left}) async {
    if (_listeningLeft != null) {
      await _app.voice.stop();
      return;
    }
    if (_working) return;
    final from = left ? _left : _right;
    // It must not hear itself.
    await _app.speaker.stop();
    if (!mounted) return;
    setState(() {
      _listeningLeft = left;
      _micOpen = false;
      _heard = '';
    });
    String words;
    try {
      words = await _app.voice.listen(
        localeId: from.speechLocale,
        onReady: () {
          if (!mounted || _listeningLeft == null) return;
          HapticFeedback.mediumImpact();
          setState(() => _micOpen = true);
        },
        onWords: (w) {
          if (mounted) setState(() => _heard = w);
        },
      );
    } on VoiceException catch (e) {
      if (mounted) {
        setState(() => _listeningLeft = null);
        _notify(e.message);
      }
      return;
    }
    if (!mounted) return;
    setState(() => _listeningLeft = null);
    if (words.trim().isEmpty) {
      _notify('Did not hear anything. Tap the mic and speak in ${from.englishName}.');
      return;
    }
    await _translate(words, fromLeft: left, spoken: true);
  }

  Future<void> _type({required bool left}) async {
    final from = left ? _left : _right;
    final text = await showDialog<String>(
      context: context,
      builder: (_) => _TypeDialog(language: from),
    );
    if (text == null || text.trim().isEmpty || !mounted) return;
    await _translate(text.trim(), fromLeft: left);
  }

  /// Heard wrongly: correct the words, and it is translated again.
  Future<void> _correct(int i) async {
    final line = _lines[i];
    if (_working || line.translated == null) return;
    final text = await showDialog<String>(
      context: context,
      builder: (_) => _TypeDialog(language: line.from, text: line.heard),
    );
    if (text == null || text.trim().isEmpty || !mounted || i >= _lines.length) return;
    await _translate(text.trim(), fromLeft: line.fromLeft, from: line.from, to: line.to, at: i);
  }

  /// What was heard shows at once; its translation follows. [at] = a line being
  /// corrected.
  Future<void> _translate(
    String words, {
    required bool fromLeft,
    bool spoken = false,
    AppLanguage? from,
    AppLanguage? to,
    int? at,
  }) async {
    final source = from ?? (fromLeft ? _left : _right);
    final target = to ?? (fromLeft ? _right : _left);
    final translator = _app.translator;
    final before = at == null ? null : _lines[at];
    _Line line([String? translated]) =>
        _Line(fromLeft: fromLeft, from: source, to: target, heard: words, translated: translated);
    final waiting = line();
    setState(() {
      _working = true;
      if (at == null) {
        _lines.add(waiting);
      } else {
        _lines[at] = waiting;
      }
    });
    if (at == null) _scrollToEnd();
    String? text;
    try {
      final input = numbersToDigits(words, source);
      // Amounts are worth the careful way; the rest of a conversation should be quick.
      final fast = spoken && !RegExp(r'\d').hasMatch(input);
      try {
        text = await translator.translate(input, from: source, to: target, fast: fast);
      } on TranslateException catch (e) {
        if (!e.needsPack) {
          if (mounted) _notify(e.message);
          return;
        }
      }
      if (text == null) {
        // Offline and the pack is missing: ask (without a spinner behind the question).
        if (!mounted) return;
        setState(() => _working = false);
        if (!await ensureLanguagePacks(context, translator, [source, target]) || !mounted) return;
        setState(() => _working = true);
        try {
          text = await translator.translate(input, from: source, to: target);
        } on TranslateException catch (e) {
          if (mounted) _notify(e.message);
          return;
        }
      }
      if (!mounted) return;
      final i = _lines.indexOf(waiting);
      if (i < 0) return; // cleared meanwhile
      final done = text;
      setState(() => _lines[i] = line(done));
      if (at == null) _scrollToEnd();
      await _sayOut(done, target);
    } finally {
      if (mounted) {
        setState(() {
          _working = false;
          final i = _lines.indexOf(waiting);
          if (text == null && i >= 0) {
            // Not translated: gone, or as it was.
            if (before == null) {
              _lines.removeAt(i);
            } else {
              _lines[i] = before;
            }
          }
        });
      }
    }
  }

  Future<void> _sayOut(String text, AppLanguage language) async {
    if (!await _app.speaker.hasVoice(language.voiceLocale)) {
      if (mounted) setState(() => _missingVoices.add(language));
      return;
    }
    if (mounted && _missingVoices.contains(language)) setState(() => _missingVoices.remove(language));
    final volume = await _app.device.mediaVolume();
    if (volume != null && volume < 10 && mounted) _notify('The phone\'s sound is very low. Turn up the volume to hear it.');
    await _app.speaker.say(text, locale: language.voiceLocale);
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: udBackground,
      body: SafeArea(
        child: Column(
          children: [
            UdHeader(
              title: 'Translator',
              subtitle: 'Speak in your language, hear it in theirs',
              busy: _working,
              actions: [
                if (_lines.isNotEmpty)
                  IconButton(
                    key: const Key('translator-clear'),
                    tooltip: 'Clear',
                    onPressed: () => setState(_lines.clear),
                    icon: const Icon(Icons.delete_sweep_outlined, color: udPurple),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: _LanguagePicker(
                      key: const Key('translator-lang-left'),
                      value: _left,
                      color: udPurple,
                      onChanged: (l) => _choose(left: true, language: l),
                    ),
                  ),
                  IconButton(
                    key: const Key('translator-swap'),
                    tooltip: 'Swap languages',
                    onPressed: _swap,
                    icon: const Icon(Icons.swap_horiz_rounded, color: udPurple),
                  ),
                  Expanded(
                    child: _LanguagePicker(
                      key: const Key('translator-lang-right'),
                      value: _right,
                      color: _teal,
                      onChanged: (l) => _choose(left: false, language: l),
                    ),
                  ),
                ],
              ),
            ),
            for (final l in _missingVoices)
              UdBanner(
                key: Key('translator-no-voice-${l.code}'),
                icon: Icons.volume_off_rounded,
                text: 'This phone has no ${l.englishName} voice, so QBOX shows the words but cannot say them. '
                    'Tap Add, then Install voice data → ${l.englishName}.',
                actionLabel: 'Add',
                onAction: () async {
                  if (!await _app.device.openVoiceSettings() && mounted) {
                    _notify('Open phone Settings > Text-to-speech > Install voice data');
                  }
                },
              ),
            Expanded(
              child: _lines.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          'Each person taps their own mic and speaks.\n'
                          'QBOX writes it in both languages and says it out loud.',
                          key: const Key('translator-empty'),
                          textAlign: TextAlign.center,
                          style: udText(14, color: udBody),
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                      itemCount: _lines.length,
                      itemBuilder: (_, i) => _Bubble(
                        key: Key('translator-line-$i'),
                        line: _lines[i],
                        onReplay: () => _sayOut(_lines[i].translated ?? '', _lines[i].to),
                        replayKey: Key('translator-replay-$i'),
                        onCorrect: () => _correct(i),
                        correctKey: Key('translator-correct-$i'),
                      ),
                    ),
            ),
            if (_listeningLeft != null)
              Container(
                key: const Key('translator-listening'),
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: udSoft, borderRadius: BorderRadius.circular(14)),
                child: Text(
                  !_micOpen
                      ? 'Getting ready…'
                      : _heard.isEmpty
                      ? 'Speak now in ${(_listeningLeft! ? _left : _right).nativeName}'
                      : _heard == '…'
                      ? 'Working it out…'
                      : _heard,
                  style: udText(15, weight: FontWeight.w600),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: _MicButton(
                      micKey: const Key('translator-mic-left'),
                      typeKey: const Key('translator-type-left'),
                      language: _left,
                      color: udPurple,
                      listening: _listeningLeft == true,
                      enabled: !_working && _listeningLeft != false,
                      onMic: () => _speak(left: true),
                      onType: () => _type(left: true),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _MicButton(
                      micKey: const Key('translator-mic-right'),
                      typeKey: const Key('translator-type-right'),
                      language: _right,
                      color: _teal,
                      listening: _listeningLeft == false,
                      enabled: !_working && _listeningLeft != true,
                      onMic: () => _speak(left: false),
                      onType: () => _type(left: false),
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

const _teal = Color(0xFF0C8599);

class _LanguagePicker extends StatelessWidget {
  const _LanguagePicker({required this.value, required this.color, required this.onChanged, super.key});

  final AppLanguage value;
  final Color color;
  final ValueChanged<AppLanguage> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.5), width: 1.5),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<AppLanguage>(
          value: value,
          isExpanded: true,
          icon: Icon(Icons.expand_more_rounded, color: color),
          onChanged: (l) {
            if (l != null) onChanged(l);
          },
          items: [
            for (final l in AppLanguage.values)
              DropdownMenuItem(
                value: l,
                child: Text(
                  l.nativeName,
                  key: Key('lang-option-${l.code}'),
                  overflow: TextOverflow.ellipsis,
                  style: udText(15, weight: FontWeight.w700, color: color),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.line,
    required this.onReplay,
    required this.replayKey,
    required this.onCorrect,
    required this.correctKey,
    super.key,
  });

  final _Line line;
  final VoidCallback onReplay;
  final Key replayKey;
  final VoidCallback onCorrect;
  final Key correctKey;

  @override
  Widget build(BuildContext context) {
    final color = line.fromLeft ? udPurple : _teal;
    return Align(
      alignment: line.fromLeft ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 320),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  InkWell(
                    key: correctKey,
                    onTap: line.translated == null ? null : onCorrect,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          Flexible(
                            child: Text('${line.from.nativeName}: ${line.heard}', style: udText(12.5, color: udBody)),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.edit_outlined, size: 14, color: udBody),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(line.translated ?? '…', style: udText(17, weight: FontWeight.w700, color: color)),
                ],
              ),
            ),
            IconButton(
              key: replayKey,
              tooltip: 'Say again',
              onPressed: line.translated == null ? null : onReplay,
              icon: Icon(Icons.volume_up_rounded, color: color),
            ),
          ],
        ),
      ),
    );
  }
}

class _MicButton extends StatelessWidget {
  const _MicButton({
    required this.micKey,
    required this.typeKey,
    required this.language,
    required this.color,
    required this.listening,
    required this.enabled,
    required this.onMic,
    required this.onType,
  });

  final Key micKey;
  final Key typeKey;
  final AppLanguage language;
  final Color color;
  final bool listening;
  final bool enabled;
  final VoidCallback onMic;
  final VoidCallback onType;

  @override
  Widget build(BuildContext context) {
    final shown = listening ? udDue : color;
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          height: 64,
          child: FilledButton.icon(
            key: micKey,
            onPressed: enabled || listening ? onMic : null,
            icon: Icon(listening ? Icons.graphic_eq_rounded : Icons.mic_rounded, size: 26),
            label: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(listening ? 'Listening…' : language.nativeName, maxLines: 1),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: shown,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              textStyle: udText(17, weight: FontWeight.w800),
            ),
          ),
        ),
        TextButton.icon(
          key: typeKey,
          onPressed: enabled ? onType : null,
          icon: Icon(Icons.keyboard_rounded, size: 18, color: color),
          label: Text('Type', style: udText(12, weight: FontWeight.w600, color: color)),
        ),
      ],
    );
  }
}

class _TypeDialog extends StatefulWidget {
  const _TypeDialog({required this.language, this.text = ''});

  final AppLanguage language;
  final String text;

  @override
  State<_TypeDialog> createState() => _TypeDialogState();
}

class _TypeDialogState extends State<_TypeDialog> {
  late final _text = TextEditingController(text: widget.text);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Type in ${widget.language.englishName}'),
      content: TextField(
        key: const Key('translator-type-text'),
        controller: _text,
        autofocus: true,
        minLines: 1,
        maxLines: 4,
        maxLength: 500,
        decoration: const InputDecoration(counterText: ''),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          key: const Key('translator-type-go'),
          onPressed: () => Navigator.of(context).pop(_text.text),
          child: const Text('Translate'),
        ),
      ],
    );
  }
}
