import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/app_services.dart';
import '../translator/indic_numbers.dart';
import '../translator/languages.dart';
import '../translator/voice_language.dart';
import 'calculator_engine.dart';
import 'spoken_operators.dart';
import 'voice_math.dart';
import 'voice_services.dart';

const _ink = Color(0xFF1C0E57);
const _body = Color(0xFF5C5872);
const _purple = Color(0xFF651CE4);
const _soft = Color(0xFFF3EEFF);
const _background = Color(0xFFF7F4FF);
const _red = Color(0xFFD93B4A);

/// Opens the calculator (used by the home-screen tiles).
Widget openCalculator(BuildContext context) => const CalculatorScreen();

/// Shop calculator: typed sums, GT, memory, history, and voice sums
/// through the mic button ("250 plus 180 into 3").
class CalculatorScreen extends StatefulWidget {
  const CalculatorScreen({super.key});

  @override
  State<CalculatorScreen> createState() => _CalculatorScreenState();
}

class _CalculatorScreenState extends State<CalculatorScreen> {
  final CalculatorEngine _engine = CalculatorEngine();
  AppServices? _services;
  bool _muted = false;
  bool _listening = false;
  String _heard = '';
  String? _message;
  Timer? _messageTimer;
  AppLanguage _voiceLang = AppLanguage.english;

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
    _messageTimer?.cancel();
    if (_listening) unawaited(_app.voice.stop());
    unawaited(_app.speaker.stop());
    super.dispose();
  }

  Future<void> _load() async {
    final lang = await readVoiceLanguage(_app.settings);
    if (mounted) setState(() => _voiceLang = lang);
    final saved = await _app.calculator.load();
    if (!mounted || saved == null) return;
    setState(() {
      _engine.restore(saved);
      _muted = saved['muted'] == true;
    });
  }

  void _save() {
    unawaited(_app.calculator.save({..._engine.toJson(), 'muted': _muted}));
  }

  void _press(String key) {
    if (_listening) return;
    HapticFeedback.selectionClick();
    final before = _engine.answerCount;
    String? notice;
    setState(() {
      _message = null; // any old message goes away once the user carries on
      notice = _engine.press(key);
    });
    _afterChange(notice, calculated: _engine.answerCount != before);
  }

  void _afterChange(String? notice, {required bool calculated}) {
    if (notice != null) _notify(notice);
    _save();
    if (calculated && !_muted) {
      final value = _engine.result;
      if (value != null) unawaited(_sayAnswer(value));
    }
  }

  /// English: reads the whole sum back, so a wrong number is easy to catch.
  /// Other languages: says the answer in that language's voice (the phone
  /// reads the number in Telugu/Hindi/...), or in English if it has no such voice.
  Future<void> _sayAnswer(double value) async {
    final lang = _voiceLang;
    if (lang != AppLanguage.english && await _app.speaker.hasVoice(lang.voiceLocale)) {
      await _app.speaker.say(formatPlain(value), locale: lang.voiceLocale);
      return;
    }
    await _app.speaker.say(spokenCalculation(_engine.evaluatedExpression, value));
  }

  Future<void> _pickVoiceLanguage() async {
    final picked = await pickVoiceLanguage(
      context,
      current: _voiceLang,
      settings: _app.settings,
      translator: _app.translator,
    );
    if (picked != null && mounted) setState(() => _voiceLang = picked);
  }

  /// The sum in what was said. Other languages: numbers and calculator words
  /// are read on the phone ("రెండు వందల యాభై ప్లస్ నూట ఎనభై" -> 250+180), which
  /// is exact and works offline. Only if that finds no sum is it translated.
  Future<String?> _sumFrom(String words) async {
    if (_voiceLang == AppLanguage.english) return parseSpokenMath(words);
    final local = parseSpokenMath(operatorsToSymbols(numbersToDigits(words, _voiceLang), _voiceLang));
    if (local != null) return local;
    final english = await voiceToEnglish(
      context,
      words: words,
      language: _voiceLang,
      translator: _app.translator,
      onError: _notify,
    );
    return (english == null ? null : parseSpokenMath(english)) ?? parseSpokenMath(words);
  }

  /// Shows a short message inside the display (never over the keys).
  void _notify(String message) {
    _messageTimer?.cancel();
    setState(() => _message = message);
    _messageTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _message = null);
    });
  }

  Future<void> _voice() async {
    if (_listening) {
      await _app.voice.stop();
      return;
    }
    await _app.speaker.stop();
    setState(() {
      _listening = true;
      _heard = '';
      _message = null;
    });
    try {
      final words = await _app.voice.listen(
        localeId: _voiceLang.speechLocale,
        onWords: (words) {
          if (mounted) setState(() => _heard = words);
        },
      );
      if (!mounted) return;
      if (words.trim().isEmpty) {
        _notify(
          'Didn'
          't hear you. Tap Speak and say a sum.',
        );
        return;
      }
      setState(() => _listening = false); // done hearing; may now ask for a language pack
      final sum = await _sumFrom(words);
      if (!mounted) return;
      if (sum == null) {
        _notify('Could not understand "$words". Try: 250 plus 180');
        return;
      }
      final before = _engine.answerCount;
      String? notice;
      setState(() => notice = _engine.calculate(sum));
      _afterChange(notice, calculated: _engine.answerCount != before);
    } on VoiceException catch (e) {
      if (mounted) _notify(e.message);
    } finally {
      if (mounted) setState(() => _listening = false);
    }
  }

  void _toggleSound() {
    setState(() => _muted = !_muted);
    if (_muted) unawaited(_app.speaker.stop());
    _save();
    _notify(_muted ? 'Voice answers off' : 'Voice answers on');
  }

  Future<void> _showHistory() async {
    final picked = await showModalBottomSheet<double>(
      context: context,
      backgroundColor: Colors.white,
      showDragHandle: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => _HistorySheet(
        entries: List.of(_engine.history),
        onClear: () {
          setState(_engine.history.clear);
          _save();
        },
      ),
    );
    if (picked != null && mounted) {
      setState(() => _engine.useNumber(picked));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(
            children: [
              _Header(
                muted: _muted,
                onBack: () => Navigator.of(context).pop(),
                onSound: _toggleSound,
                onHistory: _showHistory,
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: VoiceLanguageChip(
                  key: const Key('calc-voice-lang'),
                  language: _voiceLang,
                  onPressed: _listening ? null : _pickVoiceLanguage,
                ),
              ),
              _Display(
                engine: _engine,
                listening: _listening,
                heard: _heard,
                message: _message,
                onPieceTap: (index) => setState(() {
                  _message = null;
                  _engine.select(index);
                }),
                onEditSum: () => setState(() {
                  _message = null;
                  _engine.editLastSum();
                }),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: _Keypad(
                  onKey: _press,
                  onMic: _voice,
                  listening: _listening,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.muted,
    required this.onBack,
    required this.onSound,
    required this.onHistory,
  });

  final bool muted;
  final VoidCallback onBack;
  final VoidCallback onSound;
  final VoidCallback onHistory;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _RoundButton(
          icon: Icons.arrow_back,
          tooltip: 'Back',
          onTap: onBack,
          buttonKey: const Key('calc-back'),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Text(
            'Calculator',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: _ink,
            ),
          ),
        ),
        _RoundButton(
          icon: muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
          tooltip: muted ? 'Turn voice answers on' : 'Turn voice answers off',
          onTap: onSound,
          buttonKey: const Key('calc-sound'),
        ),
        const SizedBox(width: 8),
        _RoundButton(
          icon: Icons.history_rounded,
          tooltip: 'History',
          onTap: onHistory,
          buttonKey: const Key('calc-history'),
        ),
      ],
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    required this.buttonKey,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final Key buttonKey;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white,
        shape: const CircleBorder(),
        child: InkWell(
          key: buttonKey,
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(icon, color: _purple, size: 22),
          ),
        ),
      ),
    );
  }
}

class _Display extends StatelessWidget {
  const _Display({
    required this.engine,
    required this.listening,
    required this.heard,
    required this.message,
    required this.onPieceTap,
    required this.onEditSum,
  });

  final CalculatorEngine engine;
  final bool listening;
  final String heard;

  /// A short note (e.g. "GT cleared"), shown in place of the top line.
  final String? message;

  /// Tapping a number or operator in the sum picks it for fixing.
  final void Function(int index) onPieceTap;

  /// Tapping the answered sum brings it back for fixing.
  final VoidCallback onEditSum;

  @override
  Widget build(BuildContext context) {
    String top;
    Widget main;
    final editable =
        engine.error == null &&
        !engine.justEvaluated &&
        engine.expression.isNotEmpty;

    if (engine.error != null) {
      top = displaySum(engine.expression);
      main = _bigText(engine.error!, _red);
    } else if (engine.justEvaluated) {
      top = '${displaySum(engine.evaluatedExpression)} =';
      main = _bigText(formatNumber(engine.result ?? 0), _purple);
    } else if (editable) {
      final preview = engine.preview;
      top = preview.isEmpty ? '' : '= $preview';
      main = _SumLine(
        pieces: engine.pieces,
        selected: engine.selected,
        onTap: onPieceTap,
      );
    } else {
      top = '';
      main = _bigText('0', _ink);
    }

    // While a piece is picked, the top line says what to do next.
    final picked = engine.selected;
    if (picked != null && picked < engine.pieces.length) {
      final isOperator =
          operators.contains(engine.pieces[picked]) &&
          !(picked == 0 && engine.pieces[picked] == minus);
      top = isOperator
          ? 'Press + − × ÷ to change it, or ⌫ to remove it'
          : 'Type the right number, or ⌫ to remove it';
    }

    final Widget topLine = FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (engine.justEvaluated &&
              engine.evaluatedExpression.isNotEmpty) ...[
            const Icon(Icons.edit_outlined, size: 16, color: _purple),
            const SizedBox(width: 6),
          ],
          Text(
            top,
            key: const Key('calc-top-line'),
            maxLines: 1,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 15,
              fontWeight: picked != null ? FontWeight.w600 : FontWeight.w500,
              color: picked != null ? _purple : _body,
            ),
          ),
        ],
      ),
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
            color: Color(0x120E1B4D),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: listening
          ? _ListeningPanel(heard: heard)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                SizedBox(
                  height: _badgeRowHeight,
                  child: Row(
                    children: [
                      if (engine.memory != 0)
                        const _Badge(
                          label: 'M',
                          badgeKey: Key('calc-memory-badge'),
                        ),
                      if (engine.grandTotal != 0) ...[
                        if (engine.memory != 0) const SizedBox(width: 6),
                        _Badge(
                          label: 'GT ${formatNumber(engine.grandTotal)}',
                          badgeKey: const Key('calc-gt-badge'),
                        ),
                      ],
                      const Spacer(),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                SizedBox(
                  height: 44,
                  child: Align(
                    alignment: Alignment.bottomRight,
                    child: message != null
                        ? _MessageChip(message: message!)
                        : engine.justEvaluated
                        ? GestureDetector(
                            key: const Key('calc-edit-sum'),
                            behavior: HitTestBehavior.opaque,
                            onTap: onEditSum,
                            child: topLine,
                          )
                        : topLine,
                  ),
                ),
                SizedBox(
                  height: 54,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: FittedBox(
                      key: const Key('calc-main-line'),
                      fit: BoxFit.scaleDown,
                      child: main,
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  static Widget _bigText(String text, Color color) => Text(
    text,
    maxLines: 1,
    style: TextStyle(
      fontFamily: 'Poppins',
      fontSize: 38,
      fontWeight: FontWeight.w700,
      color: color,
    ),
  );
}

/// The sum being typed, with every number and operator tappable for fixing.
class _SumLine extends StatelessWidget {
  const _SumLine({
    required this.pieces,
    required this.selected,
    required this.onTap,
  });

  final List<String> pieces;
  final int? selected;
  final void Function(int index) onTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < pieces.length; i++)
          GestureDetector(
            key: Key('calc-piece-$i'),
            behavior: HitTestBehavior.opaque,
            onTap: () => onTap(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
              decoration: BoxDecoration(
                color: i == selected ? _soft : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: i == selected ? _purple : Colors.transparent,
                  width: 2,
                ),
              ),
              child: Text(
                _isOperatorPiece(i) ? ' ${pieces[i]} ' : groupIndian(pieces[i]),
                maxLines: 1,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 38,
                  fontWeight: FontWeight.w700,
                  color: i == selected ? _purple : _ink,
                ),
              ),
            ),
          ),
      ],
    );
  }

  bool _isOperatorPiece(int i) =>
      operators.contains(pieces[i]) && !(i == 0 && pieces[i] == minus);
}

/// The display's inner height stays the same in every state, so nothing jumps.
const _badgeRowHeight = 22.0;
const _displayHeight = _badgeRowHeight + 4 + 44 + 54;

/// A short note in a soft purple chip with an info icon.
class _MessageChip extends StatelessWidget {
  const _MessageChip({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('calc-message'),
      padding: const EdgeInsets.fromLTRB(10, 5, 12, 5),
      decoration: BoxDecoration(
        color: _soft,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFDCCBFF)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.info_outline_rounded, size: 18, color: _purple),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              message,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontSize: 12.5,
                height: 1.3,
                fontWeight: FontWeight.w600,
                color: _purple,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown in the display while the microphone is on.
class _ListeningPanel extends StatelessWidget {
  const _ListeningPanel({required this.heard});

  final String heard;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _displayHeight,
      child: Row(
        children: [
          const _PulsingMic(size: 60),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Listening…',
                  key: Key('calc-listening'),
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: _purple,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  heard.isEmpty
                      ? 'Say a sum, like\n"250 plus 180 into 3"'
                      : heard,
                  key: const Key('calc-heard'),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: heard.isEmpty ? 14 : 20,
                    height: 1.3,
                    fontWeight: heard.isEmpty
                        ? FontWeight.w500
                        : FontWeight.w700,
                    color: heard.isEmpty ? _body : _ink,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A mic in a purple circle with a soft ring that breathes in and out.
class _PulsingMic extends StatefulWidget {
  const _PulsingMic({required this.size});

  final double size;

  @override
  State<_PulsingMic> createState() => _PulsingMicState();
}

class _PulsingMicState extends State<_PulsingMic>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    return SizedBox(
      width: size * 1.35,
      height: size * 1.35,
      child: Stack(
        alignment: Alignment.center,
        children: [
          ScaleTransition(
            scale: Tween<double>(
              begin: 0.85,
              end: 1.15,
            ).animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut)),
            child: Container(
              width: size * 1.15,
              height: size * 1.15,
              decoration: const BoxDecoration(
                color: Color(0x33651CE4),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Container(
            width: size,
            height: size,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF8B5CF6), _purple],
              ),
            ),
            child: Icon(
              Icons.mic_rounded,
              color: Colors.white,
              size: size * 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.badgeKey});

  final String label;
  final Key badgeKey;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: badgeKey,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: _soft,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontFamily: 'Poppins',
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: _purple,
        ),
      ),
    );
  }
}

enum _Style { digit, function, operator, clear, equals }

class _Keypad extends StatelessWidget {
  const _Keypad({
    required this.onKey,
    required this.onMic,
    required this.listening,
  });

  final void Function(String key) onKey;
  final VoidCallback onMic;
  final bool listening;

  static const _rows = [
    ['MC', 'MR', 'M−', 'M+'],
    ['GT', percent, '⌫', 'AC'],
    ['7', '8', '9', divide],
    ['4', '5', '6', times],
    ['1', '2', '3', minus],
    ['0', '00', '.', plus],
  ];

  static _Style _styleOf(String key) {
    if (key == 'AC') return _Style.clear;
    if (operators.contains(key)) return _Style.operator;
    if (RegExp(r'^[0-9.]+$').hasMatch(key)) return _Style.digit;
    return _Style.function;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final row in _rows)
          Expanded(
            flex: 8,
            child: Row(
              children: [
                for (final key in row)
                  Expanded(
                    child: _Key(
                      label: key,
                      style: _styleOf(key),
                      onTap: () => onKey(key),
                    ),
                  ),
              ],
            ),
          ),
        // The Speak / = row is just a little taller than the others.
        Expanded(
          flex: 9,
          child: Row(
            children: [
              Expanded(
                flex: 2,
                child: _MicKey(listening: listening, onTap: onMic),
              ),
              Expanded(
                flex: 2,
                child: _Key(
                  label: '=',
                  style: _Style.equals,
                  onTap: () => onKey('='),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Shrinks a little and darkens while a finger is on it, so every tap is felt.
class _Pressable extends StatefulWidget {
  const _Pressable({
    required this.background,
    required this.ink,
    required this.onTap,
    required this.inkKey,
    required this.child,
    this.border,
  });

  final Color background;
  final Color ink;
  final VoidCallback onTap;
  final Key inkKey;
  final Widget child;
  final BorderSide? border;

  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: widget.border ?? BorderSide.none,
    );
    final color = _down
        ? Color.lerp(widget.background, widget.ink, 0.18)!
        : widget.background;
    return Padding(
      padding: const EdgeInsets.all(4),
      child: AnimatedScale(
        scale: _down ? 0.9 : 1,
        duration: const Duration(milliseconds: 90),
        curve: Curves.easeOut,
        child: Material(
          color: color,
          shape: shape,
          elevation: _down ? 0 : 1,
          shadowColor: const Color(0x330E1B4D),
          child: InkWell(
            key: widget.inkKey,
            customBorder: shape,
            splashColor: widget.ink.withValues(alpha: 0.22),
            highlightColor: Colors.transparent,
            onHighlightChanged: (down) => setState(() => _down = down),
            onTap: widget.onTap,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({required this.label, required this.style, required this.onTap});

  final String label;
  final _Style style;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (Color background, Color text) = switch (style) {
      _Style.digit => (Colors.white, _ink),
      _Style.function => (_soft, _purple),
      _Style.operator => (const Color(0xFFE6DAFF), _purple),
      _Style.clear => (const Color(0xFFFFE9EB), _red),
      _Style.equals => (_purple, Colors.white),
    };
    final small = label.length > 2 || style == _Style.function;
    return _Pressable(
      background: background,
      ink: style == _Style.equals ? Colors.black : text,
      // Same 2px border as the Speak key next to it, so the pair matches.
      border: style == _Style.equals
          ? const BorderSide(color: Color(0xFF4B12B8), width: 2)
          : null,
      onTap: onTap,
      inkKey: Key('calc-$label'),
      child: Center(
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: small ? 17 : 24,
            fontWeight: style == _Style.digit
                ? FontWeight.w600
                : FontWeight.w700,
            color: text,
          ),
        ),
      ),
    );
  }
}

class _MicKey extends StatelessWidget {
  const _MicKey({required this.listening, required this.onTap});

  final bool listening;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = listening ? _red : _purple;
    return _Pressable(
      background: listening ? const Color(0xFFFFE9EB) : _soft,
      ink: accent,
      border: BorderSide(color: accent, width: 2),
      onTap: onTap,
      inkKey: const Key('calc-mic'),
      // Center fills the whole key, so Speak is exactly as tall as =.
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Round icon badge, like the mic on the home screen's Ask QBOX card.
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: listening
                        ? const [Color(0xFFFF6B78), _red]
                        : const [Color(0xFF8B5CF6), _purple],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.35),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Icon(
                  listening ? Icons.stop_rounded : Icons.mic_rounded,
                  color: Colors.white,
                  size: 26,
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    listening ? 'Stop' : 'Speak',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: accent,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HistorySheet extends StatefulWidget {
  const _HistorySheet({required this.entries, required this.onClear});

  final List<CalcEntry> entries;
  final VoidCallback onClear;

  @override
  State<_HistorySheet> createState() => _HistorySheetState();
}

class _HistorySheetState extends State<_HistorySheet> {
  late final List<CalcEntry> _entries = widget.entries;

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * 0.6;
    return SizedBox(
      height: height,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'History',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: _ink,
                    ),
                  ),
                ),
                if (_entries.isNotEmpty)
                  TextButton(
                    key: const Key('calc-clear-history'),
                    onPressed: () {
                      widget.onClear();
                      setState(_entries.clear);
                    },
                    child: const Text('Clear'),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Expanded(
              child: _entries.isEmpty
                  ? const Center(
                      child: Text(
                        'No calculations yet',
                        style: TextStyle(fontFamily: 'Poppins', color: _body),
                      ),
                    )
                  : ListView.separated(
                      itemCount: _entries.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final entry = _entries[i];
                        return ListTile(
                          key: Key('calc-history-$i'),
                          contentPadding: EdgeInsets.zero,
                          onTap: () => Navigator.of(context).pop(entry.result),
                          title: Text(
                            '${displaySum(entry.expression)} =',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 13,
                              color: _body,
                            ),
                          ),
                          subtitle: Text(
                            formatNumber(entry.result),
                            style: const TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: _ink,
                            ),
                          ),
                          trailing: Text(
                            _time(entry.at),
                            style: const TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 12,
                              color: _body,
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  static String _time(DateTime at) {
    final now = DateTime.now();
    final hour = at.hour % 12 == 0 ? 12 : at.hour % 12;
    final clock =
        '$hour:${at.minute.toString().padLeft(2, '0')} ${at.hour < 12 ? 'AM' : 'PM'}';
    final sameDay =
        at.year == now.year && at.month == now.month && at.day == now.day;
    return sameDay ? clock : '${at.day}/${at.month} $clock';
  }
}
