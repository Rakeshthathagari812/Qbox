import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'onboarding_draft.dart';
import 'services/app_services.dart';
import 'services/auth_api.dart';
import 'signup_success_screen.dart';
import 'widgets/digit_boxes.dart';
import 'widgets/qbox_wave.dart';
import 'widgets/signup_column.dart';
import 'widgets/signup_motion.dart';
import 'widgets/signup_route.dart';

/// Shown after the selected role forms. Saving the PIN creates the account
/// on the backend with everything typed during sign-up.
class PinScreen extends StatefulWidget {
  const PinScreen({super.key});

  @override
  State<PinScreen> createState() => _PinScreenState();
}

class _PinScreenState extends State<PinScreen>
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
      final draft = OnboardingScope.of(context);
      await ServicesScope.of(context)
          .auth
          .register(registrationBody(draft, _pin.text));
      if (!mounted) return;
      // The account now lives on the server; sign-up details are no longer needed.
      draft.clear();
      Navigator.of(context).push(signupRoute(const SignupSuccessScreen()));
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
              child: Center(
              child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: SignupColumn(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 108),
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                const RiseIn(
                  index: 0,
                  child: SizedBox(
                    height: 168,
                    child: Image(
                      image: AssetImage('assets/images/art_pin.png'),
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const RiseIn(
                  index: 1,
                  child: Column(
                    children: [
                      Text(
                        'Set Your Login PIN',
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
                        'Create a 4-digit PIN to securely\nlog in to your account.',
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
                const SizedBox(height: 36),
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
                const SizedBox(height: 18),
                RiseIn(
                  index: 2,
                  child: _PinBoxes(
                    controller: _pin,
                    fieldKey: const Key('pin-input'),
                  ),
                ),
                const SizedBox(height: 36),
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
                const SizedBox(height: 18),
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
                  child: _PinBoxes(
                    controller: _confirm,
                    fieldKey: const Key('pin-confirm'),
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
                const SizedBox(height: 48),
                RiseIn(
                  index: 3,
                  child: _SaveButton(busy: _busy, onPressed: _save),
                ),
              ],
            ),
            ),
            ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Four equal PIN boxes, kept smaller than the button and centered under it.
class _PinBoxes extends StatelessWidget {
  const _PinBoxes({required this.controller, required this.fieldKey});

  final TextEditingController controller;
  final Key fieldKey;

  @override
  Widget build(BuildContext context) {
    return DigitBoxes(
      controller: controller,
      length: 4,
      fieldKey: fieldKey,
      obscure: true,
      expand: false,
      boxSize: 48,
      gap: 14,
    );
  }
}

class _SaveButton extends StatelessWidget {
  const _SaveButton({required this.busy, required this.onPressed});

  final bool busy;
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
          key: const Key('save-pin'),
          onTap: onPressed,
          borderRadius: BorderRadius.circular(28),
          child: SizedBox(
            height: 52,
            width: double.infinity,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    busy ? 'Creating account…' : 'Save PIN & Continue',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(width: 8),
                  Icon(Icons.arrow_forward, color: Colors.white, size: 18),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

const _ink = Color(0xFF1C0E57);
const _body = Color(0xFF5C5872);
