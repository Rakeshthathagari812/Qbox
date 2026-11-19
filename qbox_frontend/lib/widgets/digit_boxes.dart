import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A row of code boxes with a blinking cursor in the box being typed.
class DigitBoxes extends StatefulWidget {
  const DigitBoxes({
    required this.controller,
    required this.length,
    required this.fieldKey,
    this.obscure = false,
    this.expand = true,
    this.boxSize = 52,
    this.gap = 12,
    super.key,
  });

  final TextEditingController controller;
  final int length;
  final Key fieldKey;
  final bool obscure;
  final bool expand;
  final double boxSize;
  final double gap;

  @override
  State<DigitBoxes> createState() => _DigitBoxesState();
}

class _DigitBoxesState extends State<DigitBoxes> {
  late final FocusNode _focus;
  Timer? _blinkTimer;
  bool _cursorOn = true;

  @override
  void initState() {
    super.initState();
    _focus = FocusNode()..addListener(_onFocus);
    widget.controller.addListener(_rebuild);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncCursor();
  }

  @override
  void dispose() {
    _blinkTimer?.cancel();
    widget.controller.removeListener(_rebuild);
    _focus.removeListener(_onFocus);
    _focus.dispose();
    super.dispose();
  }

  void _rebuild() => setState(() {});

  void _onFocus() {
    _syncCursor();
    if (mounted) setState(() {});
  }

  void _syncCursor() {
    final visible = ModalRoute.of(context)?.isCurrent ?? true;
    final blink = visible && _focus.hasFocus;
    if (blink && _blinkTimer == null) {
      _cursorOn = true;
      _blinkTimer = Timer.periodic(const Duration(milliseconds: 520), (_) {
        if (!mounted) return;
        setState(() => _cursorOn = !_cursorOn);
      });
    } else if (!blink && _blinkTimer != null) {
      _blinkTimer?.cancel();
      _blinkTimer = null;
      _cursorOn = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final code = widget.controller.text;
    final cursorAt = code.length >= widget.length
        ? widget.length - 1
        : code.length;

    return SizedBox(
      height: widget.boxSize,
      child: Stack(
        alignment: Alignment.center,
        children: [
          TextField(
            key: widget.fieldKey,
            focusNode: _focus,
            controller: widget.controller,
            keyboardType: TextInputType.number,
            showCursor: false,
            enableInteractiveSelection: false,
            style: const TextStyle(color: Colors.transparent, fontSize: 1),
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(widget.length),
            ],
            decoration: const InputDecoration(
              border: InputBorder.none,
              counterText: '',
              contentPadding: EdgeInsets.zero,
            ),
          ),
          IgnorePointer(
            child: Row(
              mainAxisAlignment: widget.expand
                  ? MainAxisAlignment.start
                  : MainAxisAlignment.center,
              children: [
                for (var index = 0; index < widget.length; index++) ...[
                  if (index > 0) SizedBox(width: widget.expand ? 8 : widget.gap),
                  if (widget.expand)
                    Expanded(child: _box(index, code, cursorAt))
                  else
                    _box(index, code, cursorAt),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _box(int index, String code, int cursorAt) {
    final active = _focus.hasFocus && index == cursorAt;
    final filled = index < code.length;
    final showCursor = active && (index == code.length || code.length == widget.length);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      width: widget.expand ? null : widget.boxSize,
      height: widget.boxSize,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: active ? const Color(0xFFF4EEFF) : Colors.white,
        borderRadius: BorderRadius.circular(widget.boxSize * 0.22),
        border: Border.all(
          color: active ? _purple : const Color(0xFFD9D3EA),
          width: active ? 1.8 : 1.2,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x120E1B4D),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (filled)
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 140),
              transitionBuilder: (child, animation) {
                return _DigitPop(animation: animation, child: child);
              },
              child: Text(
                widget.obscure ? '•' : code[index],
                key: ValueKey('${widget.obscure}-$index-${code[index]}'),
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: widget.obscure
                      ? widget.boxSize * 0.42
                      : widget.boxSize * 0.34,
                  height: 1,
                  fontWeight: FontWeight.w600,
                  color: _ink,
                ),
              ),
            ),
          if (showCursor)
            Align(
              alignment: filled ? Alignment.centerRight : Alignment.center,
              child: Padding(
                padding: EdgeInsets.only(right: filled ? 8 : 0),
                child: Opacity(
                  opacity: _cursorOn ? 1 : 0,
                  child: Container(
                    width: 2,
                    height: widget.boxSize * 0.42,
                    color: _purple,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DigitPop extends StatefulWidget {
  const _DigitPop({required this.animation, required this.child});

  final Animation<double> animation;
  final Widget child;

  @override
  State<_DigitPop> createState() => _DigitPopState();
}

class _DigitPopState extends State<_DigitPop> {
  late CurvedAnimation _curved;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _bind(widget.animation);
  }

  @override
  void didUpdateWidget(_DigitPop oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animation != widget.animation) {
      _curved.dispose();
      _bind(widget.animation);
    }
  }

  void _bind(Animation<double> animation) {
    _curved = CurvedAnimation(parent: animation, curve: Curves.easeOutBack);
    _scale = Tween<double>(begin: 0.45, end: 1).animate(_curved);
  }

  @override
  void dispose() {
    _curved.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: widget.animation,
      child: ScaleTransition(scale: _scale, child: widget.child),
    );
  }
}

const _ink = Color(0xFF1C0E57);
const _purple = Color(0xFF651CE4);
