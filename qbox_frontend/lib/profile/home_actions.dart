import 'dart:async';

import 'package:flutter/material.dart';

import '../onboarding_draft.dart';
import '../services/api_client.dart';
import '../services/app_services.dart';
import 'notices_screen.dart';
import 'photos.dart';
import 'profile_screen.dart';

/// The bell (with how many are unread) and the profile photo at the top of a
/// home screen. The count is read when the home is shown, when the app comes
/// back, and once a minute meanwhile.
class HomeActions extends StatefulWidget {
  const HomeActions({required this.role, super.key});

  final QboxRole role;

  @override
  State<HomeActions> createState() => _HomeActionsState();
}

class _HomeActionsState extends State<HomeActions> with WidgetsBindingObserver {
  int _unread = 0;
  bool _shown = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => _count());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Runs again when another screen is opened over the home, or closed.
    final shown = ModalRoute.of(context)?.isCurrent ?? true;
    if (shown && !_shown) {
      _shown = true;
      _count();
    }
    _shown = shown;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _count();
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _count() async {
    if (!_shown || !mounted) return;
    try {
      final unread = await ServicesScope.of(context).notices.unread(widget.role);
      if (mounted && unread != _unread) setState(() => _unread = unread);
    } on ApiException {
      // The last count stays.
    }
  }

  void _open(Widget screen) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));

  @override
  Widget build(BuildContext context) {
    final user = OnboardingScope.of(context).user;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          button: true,
          label: _unread == 0 ? 'Notifications' : 'Notifications, $_unread new',
          child: InkWell(
            key: const Key('home-bell'),
            customBorder: const CircleBorder(),
            onTap: () => _open(NoticesScreen(role: widget.role)),
            child: SizedBox(
              width: 40,
              height: 40,
              child: Stack(
                children: [
                  const Center(child: Icon(Icons.notifications_none, color: Color(0xFF1C0E57), size: 27)),
                  if (_unread > 0)
                    Positioned(
                      top: 1,
                      right: 0,
                      child: Container(
                        constraints: const BoxConstraints(minWidth: 18),
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE11D48),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          _unread > 9 ? '9+' : '$_unread',
                          key: const Key('home-unread'),
                          textAlign: TextAlign.center,
                          textScaler: TextScaler.noScaling,
                          style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        Semantics(
          button: true,
          label: 'Profile',
          child: InkWell(
            key: const Key('home-profile'),
            customBorder: const CircleBorder(),
            onTap: () => _open(ProfileScreen(role: widget.role)),
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: QboxPhoto(photo: user?.photoFor(widget.role), icon: roleIcon(widget.role), size: 36),
            ),
          ),
        ),
      ],
    );
  }
}
