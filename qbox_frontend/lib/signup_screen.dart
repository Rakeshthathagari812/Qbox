import 'package:flutter/material.dart';

import 'widgets/qbox_brand.dart';

import 'onboarding_draft.dart';
import 'registration_screen.dart';
import 'widgets/signup_route.dart';
import 'widgets/qbox_wave.dart';
import 'widgets/signup_column.dart';
import 'widgets/signup_motion.dart';

/// Page 2. The user picks one or more roles, then continues.
class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  OnboardingDraft? _draft;

  static const _ink = Color(0xFF1C0E57);
  static const _body = Color(0xFF5C5872);
  static const _purple = Color(0xFF651CE4);
  static const _selectedFill = Color(0xFFF4EEFF);

  OnboardingDraft get _roles => _draft!;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _draft ??= OnboardingScope.of(context);
  }

  void _toggle(QboxRole role) {
    setState(() {
      if (!_roles.roles.add(role)) {
        _roles.roles.remove(role);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasRole = _roles.roles.isNotEmpty;

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
              spread: true,
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
              children: [
                RiseIn(
                  index: 0,
                  child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                          const _PageHeader(),
                          const SizedBox(height: 8),
                          const _HeaderScene(),
                          const SizedBox(height: 18),
                          const Text(
                            'How will you use QBOX?',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 22,
                              height: 1.2,
                              fontWeight: FontWeight.w700,
                              color: _ink,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Select all that apply.\nYou can add more later.',
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
                          RiseIn(
                            index: 1,
                            child: _RoleCard(
                            asset: 'assets/images/role_business.png',
                            title: 'Business / Shop',
                            description:
                                'I own or run a shop or business (Merchant)',
                            selected: _roles.roles.contains(QboxRole.business),
                            onTap: () => _toggle(QboxRole.business),
                          ),
                          ),
                          RiseIn(
                            index: 2,
                            child: _RoleCard(
                            asset: 'assets/images/role_customer.png',
                            title: 'Customer',
                            description:
                                'I buy products (keep track of my purchases and Udhaar)',
                            selected: _roles.roles.contains(QboxRole.customer),
                            onTap: () => _toggle(QboxRole.customer),
                          ),
                          ),
                          RiseIn(
                            index: 3,
                            child: _RoleCard(
                            asset: 'assets/images/role_supplier.png',
                            title: 'Supplier',
                            description:
                                'I supply products to shops and businesses',
                            selected: _roles.roles.contains(QboxRole.supplier),
                            onTap: () => _toggle(QboxRole.supplier),
                          ),
                          ),
                RiseIn(
                  index: 4,
                  child: _ContinueButton(
                  enabled: hasRole,
                  onPressed: hasRole
                      ? () {
                          final steps = _roles.orderedRoles();
                          if (_roles.formIndex >= steps.length) {
                            _roles.formIndex = 0;
                          }
                          Navigator.of(context).push(
                            signupRoute(const RegistrationScreen()),
                          );
                        }
                      : null,
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

class _PageHeader extends StatelessWidget {
  const _PageHeader();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          tooltip: 'Back',
          onPressed: () => Navigator.of(context).pop(),
          style: IconButton.styleFrom(
            backgroundColor: const Color(0xFFF1EDF8),
            foregroundColor: _SignupScreenState._ink,
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

class _HeaderScene extends StatelessWidget {
  const _HeaderScene();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 96,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _ArtPerson(),
          SizedBox(width: 8),
          _ArtShop(),
          SizedBox(width: 12),
          _ArtTruck(),
        ],
      ),
    );
  }
}

class _ArtPerson extends StatelessWidget {
  const _ArtPerson();

  @override
  Widget build(BuildContext context) {
    return const Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        CircleAvatar(radius: 11, backgroundColor: Color(0xFF5B4BDB)),
        SizedBox(height: 2),
        DecoratedBox(
          decoration: BoxDecoration(
            color: Color(0xFF6C4DFF),
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: SizedBox(width: 34, height: 28),
        ),
      ],
    );
  }
}

class _ArtShop extends StatelessWidget {
  const _ArtShop();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Row(
          children: List.generate(4, (index) {
            return Container(
              width: 14,
              height: 12,
              decoration: BoxDecoration(
                color: index.isEven
                    ? const Color(0xFF5B3FD4)
                    : const Color(0xFFE6DEFF),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(3),
                ),
              ),
            );
          }),
        ),
        Container(
          width: 56,
          height: 40,
          decoration: const BoxDecoration(
            color: Color(0xFF7C5CFF),
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(6)),
          ),
          alignment: Alignment.bottomCenter,
          child: Container(
            width: 16,
            height: 22,
            margin: const EdgeInsets.only(bottom: 0),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(3)),
            ),
          ),
        ),
      ],
    );
  }
}

class _ArtTruck extends StatelessWidget {
  const _ArtTruck();

  @override
  Widget build(BuildContext context) {
    return const Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: Color(0xFFC4B6FF),
                borderRadius: BorderRadius.all(Radius.circular(4)),
              ),
              child: SizedBox(width: 28, height: 22),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                color: Color(0xFF8B74F0),
                borderRadius: BorderRadius.only(
                  topRight: Radius.circular(6),
                  bottomRight: Radius.circular(3),
                ),
              ),
              child: SizedBox(width: 14, height: 16),
            ),
          ],
        ),
        SizedBox(height: 2),
        Row(
          children: [
            _Wheel(),
            SizedBox(width: 16),
            _Wheel(),
          ],
        ),
      ],
    );
  }
}

class _Wheel extends StatelessWidget {
  const _Wheel();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: const BoxDecoration(
        color: Color(0xFF3D2E86),
        shape: BoxShape.circle,
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.asset,
    required this.title,
    required this.description,
    required this.selected,
    required this.onTap,
  });

  final String asset;
  final String title;
  final String description;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      constraints: const BoxConstraints(minHeight: 96),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: selected ? _SignupScreenState._selectedFill : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: selected ? const Color(0xFFE3D4FF) : const Color(0xFFE7E4F0),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(
            children: [
              Image.asset(asset, width: 48, height: 48, fit: BoxFit.contain),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: _SignupScreenState._ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      description,
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 12.5,
                        height: 1.3,
                        fontWeight: FontWeight.w500,
                        color: _SignupScreenState._body,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _CheckBox(selected: selected),
            ],
          ),
        ),
      ),
      ),
    );
  }
}

class _CheckBox extends StatelessWidget {
  const _CheckBox({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        color: selected ? _SignupScreenState._purple : Colors.white,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(
          color: selected
              ? _SignupScreenState._purple
              : const Color(0xFFD5D2DE),
          width: 1.6,
        ),
      ),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        switchInCurve: Curves.easeOutBack,
        switchOutCurve: Curves.easeIn,
        transitionBuilder: (child, animation) {
          return ScaleTransition(
            scale: animation,
            child: FadeTransition(opacity: animation, child: child),
          );
        },
        child: selected
            ? const Icon(
                Icons.check,
                key: ValueKey('on'),
                size: 18,
                color: Colors.white,
              )
            : const SizedBox(key: ValueKey('off'), width: 18, height: 18),
      ),
    );
  }
}

class _ContinueButton extends StatelessWidget {
  const _ContinueButton({required this.enabled, required this.onPressed});

  final bool enabled;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: enabled
            ? const LinearGradient(
                colors: [Color(0xFF7C4DFF), Color(0xFF5B21E6)],
              )
            : null,
        color: enabled ? null : const Color(0xFFD9CCF5),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: const Key('continue-button'),
          onTap: onPressed,
          borderRadius: BorderRadius.circular(28),
          child: const SizedBox(
            height: 52,
            width: double.infinity,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Continue',
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
    );
  }
}
