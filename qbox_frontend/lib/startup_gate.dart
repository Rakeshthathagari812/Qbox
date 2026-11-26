import 'dart:async';

import 'package:flutter/material.dart';

import 'choose_role_screen.dart';
import 'onboarding_draft.dart';
import 'services/app_services.dart';
import 'services/auth_api.dart';
import 'splash_screen.dart';
import 'update_screen.dart';
import 'welcome_screen.dart';

enum _Startup { checking, loggedIn, loggedOut, offline }

/// First thing the app shows. If a login token is saved on the phone,
/// it asks the backend who the user is and goes straight to Choose Role.
/// Otherwise it shows the Welcome screen. If the server cannot be reached,
/// it opens with the account details saved at the last login (offline mode);
/// only if there are none does it show a Try again button.
class StartupGate extends StatefulWidget {
  const StartupGate({super.key});

  @override
  State<StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<StartupGate> {
  static const _ink = Color(0xFF1C0E57);
  static const _purple = Color(0xFF5B21E6);

  _Startup _state = _Startup.checking;
  String _offlineMessage = '';
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    unawaited(_checkVersion());
    _restore();
  }

  /// Meanwhile, so it never makes starting slower.
  Future<void> _checkVersion() async {
    final navigator = Navigator.of(context);
    final url = await updateNeeded(ServicesScope.of(context));
    if (url == null || !mounted) return;
    unawaited(
      navigator.pushAndRemoveUntil<void>(MaterialPageRoute(builder: (_) => UpdateScreen(url: url)), (_) => false),
    );
  }

  Future<void> _restore() async {
    final services = ServicesScope.of(context);
    final draft = OnboardingScope.of(context);
    if (_state != _Startup.checking) setState(() => _state = _Startup.checking);

    var next = _Startup.loggedOut;
    var openedOffline = false;
    final token = await services.session.readToken();
    if (token != null && token.isNotEmpty) {
      try {
        final user = await services.auth.me(token);
        draft.applyUser(user);
        await services.session.saveUser(user); // fresh copy for offline use
        next = _Startup.loggedIn;
      } on ApiException catch (e) {
        if (e.isUnauthorized) {
          // Expired, or ended by a PIN reset: log in again.
          await services.forgetUserData();
        } else {
          // Server unreachable: open with the saved account details, so
          // offline features (like the calculator) still work.
          final saved = await services.session.readUser();
          if (saved != null) {
            draft.applyUser(saved);
            next = _Startup.loggedIn;
            openedOffline = true;
          } else {
            next = _Startup.offline;
            _offlineMessage = e.message;
          }
        }
      }
    }
    if (!mounted) return;
    setState(() => _state = next);
    if (openedOffline) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            key: Key('offline-note'),
            content: Text('You are offline. The calculator works; other features need internet.'),
            duration: Duration(seconds: 4),
            behavior: SnackBarBehavior.floating,
          ),
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return switch (_state) {
      _Startup.loggedIn => const ChooseRoleScreen(),
      _Startup.loggedOut => const WelcomeScreen(),
      // Usually hidden under the opening animation; no text, so nothing flashes.
      _Startup.checking => const Scaffold(
          backgroundColor: Color(0xFFEFF8FD),
          body: SizedBox.shrink(),
        ),
      _Startup.offline => Scaffold(
          backgroundColor: const Color(0xFFF4F0FD),
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const _Logo(),
                    const SizedBox(height: 24),
                    const Icon(Icons.wifi_off_rounded, size: 40, color: _purple),
                    const SizedBox(height: 12),
                    Text(
                      _offlineMessage,
                      key: const Key('startup-offline'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 15,
                        height: 1.4,
                        color: _ink,
                      ),
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      key: const Key('startup-retry'),
                      onPressed: _restore,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Try again'),
                      style: FilledButton.styleFrom(
                        backgroundColor: _purple,
                        minimumSize: const Size(180, 48),
                        textStyle: const TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
    };
  }
}

class _Logo extends StatelessWidget {
  const _Logo();

  @override
  Widget build(BuildContext context) => const QboxSymbol(size: 110);
}
