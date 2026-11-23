import 'dart:async';

import 'package:flutter/material.dart';

import 'widgets/qbox_brand.dart';
import 'package:flutter/services.dart';

import 'onboarding_draft.dart';
import 'services/app_services.dart';
import 'services/auth_api.dart';
import 'signup_screen.dart';
import 'widgets/digit_boxes.dart';
import 'widgets/qbox_wave.dart';
import 'widgets/signup_column.dart';
import 'widgets/signup_motion.dart';
import 'widgets/signup_route.dart';
import 'widgets/test_otp_note.dart';

/// Mobile check shown after Sign up, before the role page.
/// The backend sends the OTP. Until an SMS provider is connected it runs in
/// test mode and returns the code, which is shown under the OTP boxes.
class OtpScreen extends StatefulWidget {
  const OtpScreen({super.key});

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  OnboardingDraft? _draft;
  late final TextEditingController _phone;
  late final TextEditingController _otp;
  Timer? _ticker;
  int _seconds = 0;
  bool _sent = false;
  bool _busy = false;
  String? _devOtp;
  String _sentTo = '';
  String? _error;

  OnboardingDraft get _onboarding => _draft!;

  @override
  void initState() {
    super.initState();
    _phone = TextEditingController();
    _otp = TextEditingController();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final draft = OnboardingScope.of(context);
    if (_draft == null) {
      _draft = draft;
      _phone.text = _grouped(draft.mobileNumber);
    }
  }

  @override
  void activate() {
    super.activate();
    if (_seconds > 0) _startTicker();
  }

  @override
  void deactivate() {
    _ticker?.cancel();
    _ticker = null;
    super.deactivate();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _phone.dispose();
    _otp.dispose();
    super.dispose();
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
          .sendOtp(digits, OtpPurpose.signup);
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
          .verifyOtp(digits, OtpPurpose.signup, _otp.text);
      if (!mounted) return;
      final previous = _onboarding.mobileNumber;
      _onboarding.useVerifiedMobile(digits, previous: previous);
      _onboarding.verificationToken = token;
      Navigator.of(context).push(signupRoute(const SignupScreen()));
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
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 108),
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                const RiseIn(index: 0, child: _OtpHeader()),
                const SizedBox(height: 8),
                const RiseIn(
                  index: 1,
                  child: SizedBox(
                    height: 168,
                    child: Image(
                      image: AssetImage('assets/images/art_otp.png'),
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const RiseIn(
                  index: 2,
                  child: Column(
                    children: [
                      Text(
                        'Verify Your Mobile Number',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 24,
                          height: 1.2,
                          fontWeight: FontWeight.w700,
                          color: _ink,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Enter your mobile number and\nverify with OTP to continue.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 14,
                          height: 1.4,
                          fontWeight: FontWeight.w500,
                          color: _body,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                RiseIn(
                  index: 3,
                  child: Row(
                  children: [
                    const _CountryChip(),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _WhiteField(
                        child: Row(
                          children: [
                            const Icon(Icons.phone_outlined, color: _ink, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                key: const Key('otp-phone'),
                                controller: _phone,
                                keyboardType: TextInputType.phone,
                                inputFormatters: const [_MobileFormatter()],
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
                      ),
                    ),
                  ],
                ),
                ),
                const SizedBox(height: 16),
                RiseIn(
                  index: 4,
                  child: _PurpleButton(
                  label: _busy && !_sent ? 'Sending…' : 'Send OTP',
                  icon: Icons.near_me,
                  buttonKey: const Key('send-otp'),
                  onPressed: _send,
                ),
                ),
                const SizedBox(height: 22),
                const Row(
                  children: [
                    Expanded(child: Divider(color: Color(0xFFE4DDF3))),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        'Enter 6-digit OTP',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: _body,
                        ),
                      ),
                    ),
                    Expanded(child: Divider(color: Color(0xFFE4DDF3))),
                  ],
                ),
                const SizedBox(height: 14),
                RiseIn(
                  index: 5,
                  child: DigitBoxes(
                  controller: _otp,
                  length: 6,
                  fieldKey: const Key('otp-input'),
                ),
                ),
                if (_sent)
                  TweenAnimationBuilder<double>(
                    tween: Tween<double>(begin: 0, end: 1),
                    duration: const Duration(milliseconds: 320),
                    builder: (context, value, child) {
                      return Opacity(
                        opacity: value,
                        child: Transform.translate(
                          offset: Offset(0, (1 - value) * 8),
                          child: child,
                        ),
                      );
                    },
                    child: Column(
                      children: [
                  const SizedBox(height: 14),
                  Text(
                    'OTP sent to +91 ${_grouped(_sentTo)}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: _body,
                    ),
                  ),
                  if (_devOtp != null) ...[
                    const SizedBox(height: 6),
                    Center(child: TestOtpNote(code: _devOtp!)),
                  ],
                  const SizedBox(height: 6),
                  Center(
                    child: _seconds > 0
                        ? Text(
                            'Resend OTP in 00:$clock',
                            style: const TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: _purple,
                              decoration: TextDecoration.underline,
                              decorationColor: _purple,
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
                                decoration: TextDecoration.underline,
                                decorationColor: _purple,
                              ),
                            ),
                          ),
                  ),
                      ],
                    ),
                  ),
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
                const SizedBox(height: 16),
                RiseIn(
                  index: 6,
                  child: _PurpleButton(
                  label: _busy && _sent ? 'Verifying…' : 'Verify & Continue',
                  icon: Icons.arrow_forward,
                  buttonKey: const Key('verify-otp'),
                  onPressed: _verify,
                ),
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

class _OtpHeader extends StatelessWidget {
  const _OtpHeader();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          tooltip: 'Back',
          onPressed: () => Navigator.of(context).pop(),
          style: IconButton.styleFrom(
            backgroundColor: const Color(0xFFF1EDF8),
            foregroundColor: _ink,
            fixedSize: const Size(42, 42),
          ),
          icon: const Icon(Icons.arrow_back, size: 20),
        ),
        const Expanded(
          child: QboxWordmark(fontSize: 28, letterSpacing: 0, textAlign: TextAlign.center),
        ),
        const SizedBox(width: 42),
      ],
    );
  }
}

class _CountryChip extends StatelessWidget {
  const _CountryChip();

  @override
  Widget build(BuildContext context) {
    return const _WhiteField(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _IndiaFlag(),
          SizedBox(width: 8),
          Text(
            '+91',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: _ink,
            ),
          ),
          Icon(Icons.keyboard_arrow_down, color: _ink, size: 18),
        ],
      ),
    );
  }
}

class _IndiaFlag extends StatelessWidget {
  const _IndiaFlag();

  @override
  Widget build(BuildContext context) {
    return const CustomPaint(
      size: Size(28, 18),
      painter: _IndiaFlagPainter(),
    );
  }
}

class _IndiaFlagPainter extends CustomPainter {
  const _IndiaFlagPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final band = size.height / 3;
    final radius = Radius.circular(2);
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(Offset.zero & size, radius));
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, band),
      Paint()..color = const Color(0xFFFF9933),
    );
    canvas.drawRect(
      Rect.fromLTWH(0, band, size.width, band),
      Paint()..color = Colors.white,
    );
    canvas.drawRect(
      Rect.fromLTWH(0, band * 2, size.width, band),
      Paint()..color = const Color(0xFF138808),
    );
    canvas.drawCircle(
      Offset(size.width / 2, size.height / 2),
      band * 0.38,
      Paint()..color = const Color(0xFF000080),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _WhiteField extends StatelessWidget {
  const _WhiteField({required this.child});

  final Widget child;

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
      alignment: Alignment.center,
      child: child,
    );
  }
}

class _PurpleButton extends StatelessWidget {
  const _PurpleButton({
    required this.label,
    required this.icon,
    required this.buttonKey,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
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
                Icon(icon, color: Colors.white, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MobileFormatter extends TextInputFormatter {
  const _MobileFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = _digits(newValue.text);
    final clipped = digits.length > 10 ? digits.substring(0, 10) : digits;
    final shown = _grouped(clipped);
    return TextEditingValue(
      text: shown,
      selection: TextSelection.collapsed(offset: shown.length),
    );
  }
}

const _ink = Color(0xFF1C0E57);
const _body = Color(0xFF5C5872);
const _hint = Color(0xFFA39EB8);
const _purple = Color(0xFF651CE4);

String _digits(String value) => value.replaceAll(RegExp(r'\D'), '');

String _grouped(String digits) {
  if (digits.length <= 5) return digits;
  return '${digits.substring(0, 5)} ${digits.substring(5)}';
}

bool _isMobile(String digits) => RegExp(r'^[6-9]\d{9}$').hasMatch(digits);
