import 'dart:async';

import 'package:flutter/material.dart';

import '../calculator/voice_services.dart';
import '../onboarding_draft.dart';
import '../services/api_client.dart';
import '../services/app_services.dart';
import '../translator/languages.dart';
import '../translator/voice_language.dart';
import '../udhaar/udhaar_widgets.dart';
import 'ask_brain.dart';
import 'ask_words.dart';

/// Ask QBOX: a question by voice or typing, answered from the user's own records,
/// in their language. It never saves, pays or deletes: it opens the right screen.
class AskScreen extends StatefulWidget {
  const AskScreen({required this.role, this.listen = false, this.now, super.key});

  final QboxRole role;

  /// Start listening as soon as it opens.
  final bool listen;
  final DateTime? now;

  @override
  State<AskScreen> createState() => _AskScreenState();
}

class _Turn {
  _Turn(this.question);

  final String question;
  AskAnswer? answer;
  String? problem;
}

class _AskScreenState extends State<AskScreen> {
  AppServices? _services;
  final _text = TextEditingController();
  final _scroll = ScrollController();
  final List<_Turn> _turns = [];
  AppLanguage _lang = AppLanguage.english;
  bool _listening = false;
  bool _thinking = false;
  bool _aloud = true;
  String _heard = '';

  AppServices get _app => _services!;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_services != null) return;
    _services = ServicesScope.of(context);
    _start();
  }

  @override
  void dispose() {
    if (_listening) unawaited(_app.voice.stop());
    unawaited(_app.speaker.stop());
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final lang = await readVoiceLanguage(_app.settings);
    if (!mounted) return;
    setState(() => _lang = lang);
    if (widget.listen) await _speak();
  }

  Future<void> _pickLanguage() async {
    final picked = await pickVoiceLanguage(
      context,
      current: _lang,
      settings: _app.settings,
      translator: _app.translator,
    );
    if (picked != null && mounted) setState(() => _lang = picked);
  }

  Future<void> _speak() async {
    if (_listening) {
      await _app.voice.stop();
      return;
    }
    FocusScope.of(context).unfocus();
    await _app.speaker.stop();
    if (!mounted) return;
    setState(() {
      _listening = true;
      _heard = '';
    });
    var words = '';
    try {
      words = await _app.voice.listen(
        localeId: _lang.speechLocale,
        onWords: (w) {
          if (mounted) setState(() => _heard = w);
        },
      );
      if (mounted && words.trim().isEmpty) udNotify(context, 'Did not hear anything. Tap the mic and try again.');
    } on VoiceException catch (e) {
      if (mounted) udNotify(context, e.message);
    } finally {
      if (mounted) setState(() => _listening = false);
    }
    if (mounted && words.trim().isNotEmpty) await _ask(words.trim());
  }

  Future<void> _ask(String words) async {
    if (words.trim().isEmpty || _thinking) return;
    final turn = _Turn(words.trim());
    setState(() {
      _turns.add(turn);
      _thinking = true;
      _text.clear();
    });
    _toEnd();
    final lang = _lang;
    try {
      final answer = await AskBrain(_app, widget.role, now: widget.now).ask(
        turn.question,
        lang,
        english: () => voiceToEnglish(
          context,
          words: turn.question,
          language: lang,
          translator: _app.translator,
          onError: (_) {}, // it is then simply not understood
        ),
      );
      if (!mounted) return;
      setState(() => turn.answer = answer);
      if (_aloud && await _app.speaker.hasVoice(lang.voiceLocale) && mounted) {
        unawaited(_app.speaker.say(answer.text.replaceAll('₹', ''), locale: lang.voiceLocale));
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => turn.problem = e.message);
    } finally {
      if (mounted) setState(() => _thinking = false);
      _toEnd();
    }
  }

  void _toEnd() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (_scroll.hasClients) {
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: udBackground,
      body: SafeArea(
        child: Column(
          children: [
            UdHeader(
              title: 'Ask QBOX',
              busy: _thinking,
              actions: [
                IconButton(
                  key: const Key('ask-aloud'),
                  onPressed: () {
                    setState(() => _aloud = !_aloud);
                    if (!_aloud) unawaited(_app.speaker.stop());
                  },
                  icon: Icon(_aloud ? Icons.volume_up_rounded : Icons.volume_off_rounded, color: udPurple),
                  tooltip: _aloud ? 'Answer silently' : 'Answer aloud',
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: VoiceLanguageChip(
                  key: const Key('ask-lang'),
                  language: _lang,
                  onPressed: _listening || _thinking ? null : _pickLanguage,
                ),
              ),
            ),
            Expanded(
              child: ListView(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                children: [
                  if (_turns.isEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        askSays('help', _lang),
                        key: const Key('ask-hello'),
                        style: udText(18, weight: FontWeight.w700),
                      ),
                    ),
                    _examples(),
                  ],
                  for (var i = 0; i < _turns.length; i++) ..._turn(_turns[i], i),
                ],
              ),
            ),
            if (_listening)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: udSoft, borderRadius: BorderRadius.circular(14)),
                child: Text(
                  _heard.isEmpty ? askSays('listening', _lang) : _heard,
                  key: const Key('ask-heard'),
                  style: udText(15, weight: FontWeight.w600),
                ),
              ),
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(16, 10, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('ask-text'),
                      controller: _text,
                      maxLength: 200,
                      textInputAction: TextInputAction.send,
                      onSubmitted: _ask,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        hintText: askSays('asking', _lang),
                        counterText: '',
                        isDense: true,
                        filled: true,
                        fillColor: udBackground,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (_text.text.trim().isNotEmpty)
                    IconButton.filled(
                      key: const Key('ask-send'),
                      onPressed: _thinking ? null : () => _ask(_text.text),
                      style: IconButton.styleFrom(backgroundColor: udPurple, minimumSize: const Size(54, 54)),
                      icon: const Icon(Icons.send_rounded),
                      tooltip: 'Ask',
                    )
                  else
                    IconButton.filled(
                      key: const Key('ask-mic'),
                      onPressed: _thinking ? null : _speak,
                      style: IconButton.styleFrom(
                        backgroundColor: _listening ? udDue : udPurple,
                        minimumSize: const Size(54, 54),
                      ),
                      icon: Icon(_listening ? Icons.stop_rounded : Icons.mic_rounded, size: 28),
                      tooltip: _listening ? 'Stop' : 'Speak',
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _examples() => Wrap(
    spacing: 8,
    runSpacing: 4,
    children: [
      for (final e in askExamples(widget.role, _lang))
        ActionChip(
          key: Key('ask-try-$e'),
          label: Text(e, style: udText(13, weight: FontWeight.w600, color: udPurple)),
          backgroundColor: Colors.white,
          side: const BorderSide(color: Color(0xFFD9CEF5)),
          onPressed: _thinking ? null : () => _ask(e),
        ),
    ],
  );

  List<Widget> _turn(_Turn t, int i) {
    final a = t.answer;
    return [
      Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(top: 10, left: 48),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(color: udPurple, borderRadius: BorderRadius.circular(18)),
          child: Text(t.question, style: udText(15, weight: FontWeight.w600, color: Colors.white)),
        ),
      ),
      if (t.problem != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(t.problem!, key: Key('ask-problem-$i'), style: udText(14, color: udDue)),
        ),
      if (a != null)
        Padding(
          padding: const EdgeInsets.only(top: 8, right: 24),
          child: UdCard(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(a.text, key: Key('ask-answer-$i'), style: udText(16, weight: FontWeight.w700)),
                if (a.saved)
                  Text(askSays('saved', _lang), key: Key('ask-saved-$i'), style: udText(12, color: udWarn)),
                if (a.rows.isNotEmpty) const SizedBox(height: 6),
                for (final (n, r) in a.rows.indexed) _row(r, 'ask-row-$i-$n'),
                if (!a.understood) Padding(padding: const EdgeInsets.only(top: 8), child: _examples()),
                if (a.action != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: FilledButton(
                      key: Key('ask-action-$i'),
                      onPressed: () => a.action!.run(context),
                      style: FilledButton.styleFrom(backgroundColor: udPurple),
                      child: Text(a.action!.label),
                    ),
                  ),
              ],
            ),
          ),
        ),
    ];
  }

  Widget _row(AskRow r, String key) => InkWell(
    key: Key(key),
    onTap: r.open == null ? null : () => Navigator.of(context).push<void>(MaterialPageRoute(builder: r.open!)),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(r.title, style: udText(14, weight: FontWeight.w600)),
                if (r.detail.isNotEmpty)
                  Text(r.detail, maxLines: 2, overflow: TextOverflow.ellipsis, style: udText(12, color: udBody)),
              ],
            ),
          ),
          if (r.amount.isNotEmpty) ...[
            const SizedBox(width: 8),
            Text(r.amount, style: udText(14, weight: FontWeight.w700)),
          ],
          if (r.open != null) const Icon(Icons.chevron_right_rounded, color: udPurple, size: 20),
        ],
      ),
    ),
  );
}

/// The card on every home page.
class AskCard extends StatelessWidget {
  const AskCard({required this.role, required this.title, required this.about, super.key});

  final QboxRole role;
  final String title;
  final String about;

  void _open(BuildContext context, {bool listen = false}) =>
      Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => AskScreen(role: role, listen: listen)));

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF3EEFF),
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: const Key('ask-card'),
        onTap: () => _open(context),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
          child: Row(
            children: [
              Material(
                color: udPurple,
                shape: const CircleBorder(),
                child: InkWell(
                  key: const Key('ask-card-mic'),
                  customBorder: const CircleBorder(),
                  onTap: () => _open(context, listen: true),
                  child: const SizedBox(
                    width: 52,
                    height: 52,
                    child: Icon(Icons.mic, color: Colors.white, size: 26),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: udText(15, weight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(about, style: udText(12, color: udBody)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: udPurple, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}
