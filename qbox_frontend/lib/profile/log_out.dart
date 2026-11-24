import 'package:flutter/material.dart';

import '../onboarding_draft.dart';
import '../services/app_services.dart';
import '../udhaar/udhaar_widgets.dart';
import '../welcome_screen.dart';
import '../widgets/signup_route.dart';

/// Asks first if something is not sent yet, then logs out.
Future<void> logOut(BuildContext context) async {
  final unsent = await ServicesScope.of(context).unsentCount();
  if (!context.mounted) return;
  if (unsent > 0) {
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Log out?'),
        content: Text(
          unsent == 1
              ? '1 change on this phone is not sent yet. It will be lost.'
              : '$unsent changes on this phone are not sent yet. They will be lost.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(
            key: const Key('log-out-sure'),
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: udDue),
            child: const Text('Log out'),
          ),
        ],
      ),
    );
    if (sure != true || !context.mounted) return;
  }
  await leaveAccount(context);
}

/// Forgets the saved login and goes back to the Welcome screen.
Future<void> leaveAccount(BuildContext context) async {
  final services = ServicesScope.of(context);
  final draft = OnboardingScope.of(context);
  final navigator = Navigator.of(context);
  // The next person on this phone must not see this user's login,
  // calculations, calendar or reminders.
  await services.forgetUserData();
  draft.clear();
  navigator.pushAndRemoveUntil(signupRoute(const WelcomeScreen()), (route) => false);
}
