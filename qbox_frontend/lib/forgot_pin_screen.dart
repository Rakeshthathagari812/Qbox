import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'widgets/qbox_brand.dart';
import 'package:flutter/services.dart';

import 'services/app_services.dart';
import 'services/auth_api.dart';
import 'widgets/digit_boxes.dart';
import 'widgets/qbox_wave.dart';
import 'widgets/signup_column.dart';
import 'widgets/signup_motion.dart';
import 'widgets/signup_route.dart';
import 'widgets/test_otp_note.dart';

/// PIN reset: the backend sends an OTP to the registered mobile, checks it,
/// then saves the new PIN.
class ForgotPinScreen extends StatefulWidget {
  const ForgotPinScreen({super.key});

  @override
  State<ForgotPinScreen> createState() => _ForgotPinScreenState();
}

class _ForgotPinScreenState extends State<ForgotPinScreen> {
  final TextEditingController _phone = TextEditingController();
  final TextEditingController _otp = TextEditingController();
  Timer? _ticker;
  int _seconds = 0;
  bool _sent = false;
  bool _busy = false;
  String? _devOtp;
  String _sentTo = '';
  String? _error;

  @override
  void dispose() {
    _ticker?.cancel();
    _phone.dispose();
    _otp.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final current = ModalRoute.of(context)?.isCurrent ?? true;
    if (!current) {
      _ticker?.cancel();
      _ticker = null;
    } else if (_seconds > 0 && _ticker == null) {
      _startTicker();
    }
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_seconds <= 1) {
        timer.cancel();
        _ticker = null;
        setState(() => _seconds = 0);
        return;
      }
      setState(() => _seconds -= 1);
    });
  }

  Future<void> _send() async {
    if (_busy) return;
    final digits = _digits(_phone.text);
    if (!_isMobile(digits)) {
      setState(() => _error = 'Enter a 10-digit mobile number');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final sent = await ServicesScope.of(context)
          .auth
          .sendOtp(digits, OtpPurpose.resetPin);
      if (!mounted) return;
      _otp.clear();
      setState(() {
        _sent = true;
        _sentTo = digits;
        _devOtp = sent.devOtp;
        _seconds = sent.resendInSeconds;
      });
      _startTicker();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    if (_busy) return;
    final digits = _digits(_phone.text);
    if (!_isMobile(digits)) {
      setState(() => _error = 'Enter a 10-digit mobile number');
      return;
    }
    if (!_sent || digits != _sentTo) {
      setState(() => _error = 'Send the OTP first');
      return;
    }
    if (_otp.text.length != 6) {
      setState(() => _error = 'Enter the 6-digit OTP');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final token = await ServicesScope.of(context)
          .auth
          .verifyOtp(digits, OtpPurpose.resetPin, _otp.text);
      if (!mounted) return;
      Navigator.of(context).push(
        signupRoute(SetNewPinScreen(verificationToken: token)),
      );
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final clock = _seconds.toString().padLeft(2, '0');
    return Scaffold(
      backgroundColor: const Color(0xFFF7F4FF),
      body: Stack(
        children: [
          const Align(
            alignment: Alignment.bottomCenter,
            child: QboxWaveFooter(),
          ),
          SafeArea(
            bottom: false,
            child: SignupMotionHost(
              child: SignupColumn(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 108),
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _ResetHeader(),
                      const SizedBox(height: 8),
                      const RiseIn(
                        index: 1,
                        child: SizedBox(
                          height: 132,
                          child: Image(
                            image: AssetImage('assets/images/art_otp.png'),
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Forgot PIN?',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 26,
                          height: 1.2,
                          fontWeight: FontWeight.w700,
                          color: _ink,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Reset your 4-digit PIN using OTP\nsent to your registered mobile number.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 14,
                          height: 1.4,
                          fontWeight: FontWeight.w500,
                          color: _body,
                        ),
                      ),
                      const SizedBox(height: 22),
                      const _StepLabel(number: '1', label: 'Enter Mobile Number'),
                      const SizedBox(height: 10),
                      _PhoneField(controller: _phone),
                      const SizedBox(height: 10),
                      if (!_sent)
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            key: const Key('forgot-send'),
                            onPressed: _send,
                            style: TextButton.styleFrom(
                              foregroundColor: _purple,
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: const Text(
                              'Send OTP',
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: _purple,
                              ),
                            ),
                          ),
                        )
                      else
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE7F8EE),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.check_circle,
                                color: Color(0xFF16A34A),
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'OTP Sent to +91 ${_grouped(_sentTo)}',
                                  style: const TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF15803D),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 18),
                      const _StepLabel(number: '2', label: 'Enter 6-Digit OTP'),
                      const SizedBox(height: 12),
                      DigitBoxes(
                        controller: _otp,
                        length: 6,
                        fieldKey: const Key('forgot-otp'),
                        obscure: true,
                        expand: false,
                        boxSize: 42,
                        gap: 8,
                      ),
                      if (_sent) ...[
                        if (_devOtp != null) ...[
                          const SizedBox(height: 12),
                          Center(child: TestOtpNote(code: _devOtp!)),
                        ],
                        const SizedBox(height: 12),
                        Center(
                          child: _seconds > 0
                              ? Text(
                                  'Resend OTP in 00:$clock',
                                  style: const TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: _purple,
                                  ),
                                )
                              : TextButton(
                                  onPressed: _send,
                                  child: const Text(
                                    'Resend OTP',
                                    style: TextStyle(
                                      fontFamily: 'Poppins',
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: _purple,
                                    ),
                                  ),
                                ),
                        ),
                      ],
                      if (_error != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFFC2414B),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 20),
                  _PurpleButton(
                    label: _busy && _sent ? 'Verifying…' : 'Verify OTP',
                    buttonKey: const Key('forgot-verify'),
                    onPressed: _verify,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class SetNewPinScreen extends StatefulWidget {
  const SetNewPinScreen({required this.verificationToken, super.key});

  /// From the backend after the OTP check; allows exactly this PIN change.
  final String verificationToken;

  @override
  State<SetNewPinScreen> createState() => _SetNewPinScreenState();
}

class _SetNewPinScreenState extends State<SetNewPinScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _pin = TextEditingController();
  final TextEditingController _confirm = TextEditingController();
  late final AnimationController _shake;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _shake = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
  }

  @override
  void dispose() {
    _shake.dispose();
    _pin.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    if (_pin.text.length != 4) {
      setState(() => _error = 'Enter a 4-digit PIN');
      return;
    }
    if (_confirm.text.length != 4) {
      setState(() => _error = 'Confirm your 4-digit PIN');
      return;
    }
    if (_pin.text != _confirm.text) {
      setState(() => _error = 'PINs do not match');
      _shake.forward(from: 0);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ServicesScope.of(context)
          .auth
          .resetPin(widget.verificationToken, _pin.text);
      if (!mounted) return;
      Navigator.of(context).push(signupRoute(const PinResetSuccessScreen()));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F4FF),
      body: Stack(
        children: [
          const Align(
            alignment: Alignment.bottomCenter,
            child: QboxWaveFooter(),
          ),
          SafeArea(
            bottom: false,
            child: SignupMotionHost(
              child: SignupColumn(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 108),
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _ResetHeader(),
                      const SizedBox(height: 12),
                      const SizedBox(
                        height: 140,
                        child: Image(
                          image: AssetImage('assets/images/art_pin.png'),
                          fit: BoxFit.contain,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Set New PIN',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 26,
                          height: 1.2,
                          fontWeight: FontWeight.w700,
                          color: _ink,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Create a new 4-digit PIN\nfor your account.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 14,
                          height: 1.4,
                          fontWeight: FontWeight.w500,
                          color: _body,
                        ),
                      ),
                      const SizedBox(height: 28),
                      const Text(
                        'Enter 4-Digit PIN',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: _ink,
                        ),
                      ),
                      const SizedBox(height: 14),
                      DigitBoxes(
                        controller: _pin,
                        length: 4,
                        fieldKey: const Key('new-pin'),
                        obscure: true,
                        expand: false,
                        boxSize: 48,
                        gap: 14,
                      ),
                      const SizedBox(height: 28),
                      const Text(
                        'Confirm 4-Digit PIN',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: _ink,
                        ),
                      ),
                      const SizedBox(height: 14),
                      AnimatedBuilder(
                        animation: _shake,
                        builder: (context, child) {
                          final t = _shake.value;
                          final dx = math.sin(t * math.pi * 4) * (1 - t) * 10;
                          return Transform.translate(
                            offset: Offset(dx, 0),
                            child: child,
                          );
                        },
                        child: DigitBoxes(
                          controller: _confirm,
                          length: 4,
                          fieldKey: const Key('new-pin-confirm'),
                          obscure: true,
                          expand: false,
                          boxSize: 48,
                          gap: 14,
                        ),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFFC2414B),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 28),
                  _PurpleButton(
                    label: 'Save PIN',
                    buttonKey: const Key('save-new-pin'),
                    onPressed: _save,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class PinResetSuccessScreen extends StatelessWidget {
  const PinResetSuccessScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F4FF),
      body: Stack(
        children: [
          const Align(
            alignment: Alignment.bottomCenter,
            child: QboxWaveFooter(),
          ),
          SafeArea(
            bottom: false,
            child: SignupMotionHost(
              child: SignupColumn(
                center: true,
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 108),
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _ResetHeader(showBack: false),
                      const SizedBox(height: 28),
                      const SizedBox(
                        height: 150,
                        child: Image(
                          image: AssetImage('assets/images/art_success.png'),
                          fit: BoxFit.contain,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'PIN Reset\nSuccessfully!',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 26,
                          height: 1.25,
                          fontWeight: FontWeight.w700,
                          color: _ink,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Your new 4-digit PIN has been set.\nYou can now log in to your QBOX account.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 14,
                          height: 1.45,
                          fontWeight: FontWeight.w500,
                          color: _body,
                        ),
                      ),
                      const SizedBox(height: 28),
                      _PurpleButton(
                        label: 'Back to Login',
                        buttonKey: const Key('back-to-login'),
                        onPressed: () {
                          Navigator.of(context).popUntil(
                            (route) =>
                                route.settings.name == 'login' || route.isFirst,
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ResetHeader extends StatelessWidget {
  const _ResetHeader({this.showBack = true});

  final bool showBack;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (showBack)
          IconButton(
            tooltip: 'Back',
            onPressed: () => Navigator.of(context).pop(),
            style: IconButton.styleFrom(
              backgroundColor: const Color(0xFFF1EDF8),
              foregroundColor: _ink,
              fixedSize: const Size(42, 42),
            ),
            icon: const Icon(Icons.arrow_back, size: 20),
          )
        else
          const SizedBox(width: 42),
        const Expanded(
          child: QboxWordmark(fontSize: 28, letterSpacing: 0, textAlign: TextAlign.center),
        ),
        const SizedBox(width: 42),
      ],
    );
  }
}

class _StepLabel extends StatelessWidget {
  const _StepLabel({required this.number, required this.label});

  final String number;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: _purple,
            shape: BoxShape.circle,
          ),
          child: Text(
            number,
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            fontFamily: 'Poppins',
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: _ink,
          ),
        ),
      ],
    );
  }
}

class _PhoneField extends StatelessWidget {
  const _PhoneField({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x120E1B4D),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.phone_android_outlined, color: _purple, size: 20),
          const SizedBox(width: 8),
          const Text(
            '+91',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: _ink,
            ),
          ),
          const Icon(Icons.keyboard_arrow_down, color: _ink, size: 18),
          const SizedBox(width: 8),
          Container(width: 1, height: 20, color: const Color(0xFFE4DDF3)),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              key: const Key('forgot-phone'),
              controller: controller,
              keyboardType: TextInputType.phone,
              inputFormatters: const [_ResetMobileFormatter()],
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: _ink,
              ),
              decoration: const InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: 'Enter mobile number',
                hintStyle: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: _hint,
                ),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PurpleButton extends StatelessWidget {
  const _PurpleButton({
    required this.label,
    required this.buttonKey,
    required this.onPressed,
  });

  final String label;
  final Key buttonKey;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          colors: [Color(0xFF7C4DFF), Color(0xFF5B21E6)],
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: buttonKey,
          onTap: onPressed,
          borderRadius: BorderRadius.circular(28),
          child: SizedBox(
            height: 52,
            width: double.infinity,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.arrow_forward, color: Colors.white, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ResetMobileFormatter extends TextInputFormatter {
  const _ResetMobileFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final clipped = digits.length > 10 ? digits.substring(0, 10) : digits;
    final shown = _grouped(clipped);
    return TextEditingValue(
      text: shown,
      selection: TextSelection.collapsed(offset: shown.length),
    );
  }
}

String _digits(String value) => value.replaceAll(RegExp(r'\D'), '');

String _grouped(String digits) {
  if (digits.length <= 5) return digits;
  return '${digits.substring(0, 5)} ${digits.substring(5)}';
}

bool _isMobile(String digits) => RegExp(r'^[6-9]\d{9}$').hasMatch(digits);

const _ink = Color(0xFF1C0E57);
const _body = Color(0xFF5C5872);
const _hint = Color(0xFFA39EB8);
const _purple = Color(0xFF651CE4);
