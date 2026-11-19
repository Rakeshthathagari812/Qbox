import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'choose_role_screen.dart';
import 'forgot_pin_screen.dart';
import 'onboarding_draft.dart';
import 'otp_screen.dart';
import 'services/app_services.dart';
import 'services/auth_api.dart';
import 'widgets/qbox_wave.dart';
import 'widgets/signup_route.dart';
import 'widgets/signup_column.dart';
import 'widgets/signup_motion.dart';

/// Mobile + PIN login, checked by the backend. On success the login token
/// is saved on the phone and the user goes to Choose Role.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _phone = TextEditingController();
  final TextEditingController _pin = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _phone.dispose();
    _pin.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final digits = _phone.text.replaceAll(RegExp(r'\D'), '');
    if (!RegExp(r'^[6-9]\d{9}$').hasMatch(digits)) {
      setState(() => _error = 'Enter a 10-digit mobile number');
      return;
    }
    if (_pin.text.length != 4) {
      setState(() => _error = 'Enter a 4-digit PIN');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final services = ServicesScope.of(context);
      final draft = OnboardingScope.of(context);
      final result = await services.auth.login(digits, _pin.text);
      await services.session.saveToken(result.accessToken);
      if (!mounted) return;
      draft.applyUser(result.user);
      _pin.clear();
      // Logged in: Back must not lead to the login or welcome pages again.
      Navigator.of(context).pushAndRemoveUntil(
        signupRoute(const ChooseRoleScreen()),
        (route) => false,
      );
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
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 108),
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      RiseIn(
                        index: 0,
                        child: Row(
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
                              child: Text(
                                'QBOX',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 34,
                                  height: 1,
                                  letterSpacing: 0.6,
                                  fontWeight: FontWeight.w800,
                                  color: _ink,
                                ),
                              ),
                            ),
                            const SizedBox(width: 42),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      const RiseIn(
                        index: 1,
                        child: SizedBox(
                          height: 168,
                          child: Image(
                            image: AssetImage('assets/images/art_shop.png'),
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
                              'Welcome Back!',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 26,
                                height: 1.2,
                                fontWeight: FontWeight.w700,
                                color: _ink,
                              ),
                            ),
                            SizedBox(height: 8),
                            Text(
                              'Login to your QBOX account',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 15,
                                height: 1.4,
                                fontWeight: FontWeight.w500,
                                color: _body,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 28),
                      RiseIn(
                        index: 3,
                        child: _FieldShell(
                          child: Row(
                            children: [
                              const Icon(
                                Icons.phone_android_outlined,
                                color: _purple,
                                size: 22,
                              ),
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
                              const Icon(
                                Icons.keyboard_arrow_down,
                                color: _ink,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Container(
                                width: 1,
                                height: 22,
                                color: const Color(0xFFE4DDF3),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: TextField(
                                  key: const Key('login-phone'),
                                  controller: _phone,
                                  keyboardType: TextInputType.phone,
                                  inputFormatters: const [_LoginMobileFormatter()],
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
                      const SizedBox(height: 14),
                      RiseIn(
                        index: 4,
                        child: _FieldShell(
                          child: Row(
                            children: [
                              const Icon(
                                Icons.lock_outline,
                                color: _purple,
                                size: 22,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: TextField(
                                  key: const Key('login-pin'),
                                  controller: _pin,
                                  obscureText: _obscure,
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                    LengthLimitingTextInputFormatter(4),
                                  ],
                                  style: const TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: _ink,
                                  ),
                                  decoration: const InputDecoration(
                                    isDense: true,
                                    border: InputBorder.none,
                                    hintText: 'Enter 4-digit PIN',
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
                              IconButton(
                                key: const Key('login-pin-visibility'),
                                onPressed: () {
                                  setState(() => _obscure = !_obscure);
                                },
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                  minWidth: 36,
                                  minHeight: 36,
                                ),
                                icon: Icon(
                                  _obscure
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                  color: _purple,
                                  size: 22,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          key: const Key('forgot-pin'),
                          onPressed: () {
                            Navigator.of(context).push(
                              signupRoute(const ForgotPinScreen()),
                            );
                          },
                          style: TextButton.styleFrom(
                            foregroundColor: _purple,
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text(
                            'Forgot PIN?',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: _purple,
                            ),
                          ),
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
                  const SizedBox(height: 28),
                  RiseIn(
                    index: 5,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(28),
                        gradient: const LinearGradient(
                          colors: [Color(0xFF7C4DFF), Color(0xFF5B21E6)],
                        ),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          key: const Key('login-submit'),
                          onTap: _submit,
                          borderRadius: BorderRadius.circular(28),
                          child: SizedBox(
                            height: 52,
                            width: double.infinity,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  _busy ? 'Logging in…' : 'Log In',
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                                SizedBox(width: 8),
                                Icon(
                                  Icons.arrow_forward,
                                  color: Colors.white,
                                  size: 18,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  const RiseIn(index: 6, child: _NewToQbox()),
                  const SizedBox(height: 16),
                  RiseIn(
                    index: 7,
                    child: OutlinedButton(
                      key: const Key('login-create-account'),
                      onPressed: () {
                        Navigator.of(context).push(
                          signupRoute(const OtpScreen()),
                        );
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _purple,
                        backgroundColor: Colors.white,
                        side: const BorderSide(color: _purple, width: 1.4),
                        minimumSize: const Size.fromHeight(52),
                        shape: const StadiumBorder(),
                        textStyle: const TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      child: const Text('Create Account'),
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

class _NewToQbox extends StatelessWidget {
  const _NewToQbox();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Expanded(child: Divider(color: Color(0xFFD9D3EA), thickness: 1)),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            'New to QBOX?',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: _body,
            ),
          ),
        ),
        Expanded(child: Divider(color: Color(0xFFD9D3EA), thickness: 1)),
      ],
    );
  }
}

class _FieldShell extends StatelessWidget {
  const _FieldShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      padding: const EdgeInsets.only(left: 16, right: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
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

class _LoginMobileFormatter extends TextInputFormatter {
  const _LoginMobileFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final clipped = digits.length > 10 ? digits.substring(0, 10) : digits;
    final shown = clipped.length <= 5
        ? clipped
        : '${clipped.substring(0, 5)} ${clipped.substring(5)}';
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
