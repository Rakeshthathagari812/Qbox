import 'package:flutter/material.dart';

import '../models/qbox_user.dart';
import '../onboarding_draft.dart';
import '../services/app_services.dart';
import '../udhaar/udhaar_widgets.dart';
import 'edit_profile_screen.dart';
import 'profile_screen.dart' show roleIcon;

String roleName(QboxRole role) => switch (role) {
  QboxRole.business => 'Business / Shop',
  QboxRole.customer => 'Customer',
  QboxRole.supplier => 'Supplier',
};

String _about(QboxRole role) => switch (role) {
  QboxRole.business => 'Sales, stock, udhaar and payments of your shop',
  QboxRole.customer => 'Your udhaar, payments and expenses',
  QboxRole.supplier => 'Orders and payments from shops',
};

/// Whether there is a role they can add now.
bool canAddRole(QboxUser user) => QboxRole.values.any((r) => !user.roles.contains(r));

/// Lets the user add one more role to the same account.
Future<void> addRole(BuildContext context) async {
  final session = ServicesScope.of(context).session;
  final draft = OnboardingScope.read(context);
  final added = await Navigator.of(
    context,
  ).push<(QboxRole, QboxUser)>(MaterialPageRoute(builder: (_) => const AddRoleScreen()));
  if (added == null) return;
  final (role, user) = added;
  draft.applyUser(user);
  await session.saveUser(user);
  if (context.mounted) udNotify(context, '${roleName(role)} added. Use Switch role to open it.');
}

/// The roles they do not have. Closes with the one added.
class AddRoleScreen extends StatelessWidget {
  const AddRoleScreen({super.key});

  Future<void> _add(BuildContext context, QboxUser user, QboxRole role) async {
    final navigator = Navigator.of(context);
    final changed = await navigator.push<QboxUser>(
      MaterialPageRoute(
        builder: (_) => EditProfileScreen(user: user, role: role, adding: true),
      ),
    );
    if (changed != null && context.mounted) navigator.pop((role, changed));
  }

  @override
  Widget build(BuildContext context) {
    final user = OnboardingScope.of(context).user;
    return Scaffold(
      backgroundColor: udBackground,
      body: SafeArea(
        child: Column(
          children: [
            const UdHeader(title: 'Add a role', subtitle: 'Same number, same PIN'),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (user != null)
                    for (final role in QboxRole.values)
                      if (!user.roles.contains(role)) _card(context, user, role),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _card(BuildContext context, QboxUser user, QboxRole role) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          key: Key('add-${role.name}'),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: Icon(roleIcon(role), color: udPurple, size: 30),
          title: Text(
            roleName(role),
            style: udText(16, weight: FontWeight.w700, color: udInk),
          ),
          subtitle: Text(_about(role), style: udText(13, color: udBody)),
          trailing: const Icon(Icons.chevron_right_rounded, color: udPurple),
          onTap: () => _add(context, user, role),
        ),
      ),
    );
  }
}
