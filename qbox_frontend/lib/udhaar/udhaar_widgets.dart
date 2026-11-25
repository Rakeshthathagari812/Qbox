import 'package:flutter/material.dart';

import '../onboarding_draft.dart';
import 'udhaar_models.dart';

const udInk = Color(0xFF1C0E57);
const udBody = Color(0xFF5C5872);
const udPurple = Color(0xFF651CE4);
const udSoft = Color(0xFFF3EEFF);
const udBackground = Color(0xFFF7F4FF);

/// Money the customer owes (and "udhaar given") is red; payments are green.
const udDue = Color(0xFFD93B4A);
const udPaid = Color(0xFF2B8A3E);
const udWarn = Color(0xFFE67700);

TextStyle udText(
  double size, {
  FontWeight weight = FontWeight.w500,
  Color color = udInk,
  TextDecoration? decoration,
}) => TextStyle(
  fontFamily: 'Poppins',
  fontSize: size,
  fontWeight: weight,
  color: color,
  decoration: decoration,
);

Color balanceColor(int paise) =>
    paise > 0 ? udDue : (paise < 0 ? udPaid : udBody);

/// "₹350 due", "₹50 advance", "Settled".
String balanceLabel(int paise) => paise > 0
    ? '${rupees(paise)} due'
    : (paise < 0 ? '${rupees(paise)} advance' : 'Settled');

/// The shop name from sign-up (empty if not known).
String shopNameOf(BuildContext context) {
  final scope = context.dependOnInheritedWidgetOfExactType<OnboardingScope>();
  return scope?.draft.shop.shopName.trim() ?? '';
}

/// Short messages float just above the bottom buttons, never over them.
void udNotify(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 90),
      ),
    );
}

class UdHeader extends StatelessWidget {
  const UdHeader({
    required this.title,
    this.subtitle,
    this.busy = false,
    this.actions = const [],
    super.key,
  });

  final String title;
  final String? subtitle;
  final bool busy;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        children: [
          Material(
            color: Colors.white,
            shape: const CircleBorder(),
            child: InkWell(
              key: const Key('udhaar-back'),
              customBorder: const CircleBorder(),
              onTap: () => Navigator.of(context).maybePop(),
              child: const SizedBox(
                width: 44,
                height: 44,
                child: Icon(Icons.arrow_back, color: udPurple),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: udText(20, weight: FontWeight.w700),
                ),
                if (subtitle != null)
                  Text(subtitle!, style: udText(12, color: udBody)),
              ],
            ),
          ),
          if (busy)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: udPurple),
              ),
            ),
          ...actions,
        ],
      ),
    );
  }
}

/// A coloured strip with a message (offline, waiting to sync, warnings).
class UdBanner extends StatelessWidget {
  const UdBanner({
    required this.icon,
    required this.text,
    this.color = udWarn,
    this.background = const Color(0xFFFFF4E6),
    this.actionLabel,
    this.onAction,
    super.key,
  });

  final IconData icon;
  final String text;
  final Color color;
  final Color background;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
      constraints: const BoxConstraints(minHeight: 40),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: udText(12))),
          if (actionLabel != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(foregroundColor: color),
              child: Text(actionLabel!, style: udText(12, weight: FontWeight.w700, color: color)),
            ),
        ],
      ),
    );
  }
}

/// White rounded card with a soft shadow.
class UdCard extends StatelessWidget {
  const UdCard({required this.child, this.padding = const EdgeInsets.all(16), super.key});

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(color: Color(0x120E1B4D), blurRadius: 12, offset: Offset(0, 4)),
        ],
      ),
      child: child,
    );
  }
}

/// A circle with the person's initials.
class UdAvatar extends StatelessWidget {
  const UdAvatar({required this.name, this.size = 44, super.key});

  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final initials = words.isEmpty
        ? '?'
        : words.take(2).map((w) => w[0].toUpperCase()).join();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(color: udSoft, shape: BoxShape.circle),
      child: Text(initials, style: udText(size * 0.36, weight: FontWeight.w700, color: udPurple)),
    );
  }
}

/// A small coloured label ("45 days", "Over limit").
class UdBadge extends StatelessWidget {
  const UdBadge(this.text, {this.color = udDue, super.key});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text, style: udText(11, weight: FontWeight.w600, color: color)),
    );
  }
}

/// One line of history. [forCustomer] words it from the customer's side.
class EntryTile extends StatelessWidget {
  const EntryTile({
    required this.entry,
    required this.balanceAfter,
    required this.now,
    this.forCustomer = false,
    this.onTap,
    super.key,
  });

  final UdhaarEntry entry;
  final int balanceAfter;
  final DateTime now;
  final bool forCustomer;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final credit = entry.kind == EntryKind.credit;
    final color = entry.deleted ? udBody : (credit ? udDue : udPaid);
    final strike = entry.deleted ? TextDecoration.lineThrough : null;
    final title = forCustomer
        ? (credit ? 'You took udhaar' : 'You paid')
        : entry.kind.label;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: entry.deleted ? const Color(0xFFF4F3F7) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Row(
              children: [
                Icon(
                  // Out of the reader's hands: the shop gave udhaar, or the customer paid.
                  credit != forCustomer ? Icons.north_east_rounded : Icons.south_west_rounded,
                  color: color,
                  size: 22,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: udText(14, weight: FontWeight.w700, decoration: strike)),
                      if ((entry.note ?? '').isNotEmpty)
                        Text(
                          entry.note!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: udText(13, color: udBody, decoration: strike),
                        ),
                      Text(whenLabel(entry.entryAt, now), style: udText(11, color: udBody)),
                      if (entry.deleted)
                        Text(
                          'Deleted: ${entry.deleteReason ?? ''}',
                          style: udText(11, weight: FontWeight.w600, color: udDue),
                        ),
                      if (entry.pending)
                        Text(
                          '⏳ Waiting for internet to sync',
                          style: udText(11, weight: FontWeight.w600, color: udWarn),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${credit ? '+' : '−'} ${rupees(entry.amountPaise)}',
                      style: udText(16, weight: FontWeight.w700, color: color, decoration: strike),
                    ),
                    if (!entry.deleted)
                      Text(
                        'Bal ${rupees(balanceAfter)}${balanceAfter < 0 ? ' adv' : ''}',
                        style: udText(11, color: udBody),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The two big buttons at the bottom of a screen.
class UdBottomButtons extends StatelessWidget {
  const UdBottomButtons({
    required this.leftKey,
    required this.leftIcon,
    required this.leftLabel,
    required this.onLeft,
    required this.rightKey,
    required this.rightIcon,
    required this.rightLabel,
    required this.onRight,
    this.leftColor = udPurple,
    this.rightColor = udPurple,
    this.leftFilled = false,
    super.key,
  });

  final Key leftKey;
  final IconData leftIcon;
  final String leftLabel;
  final VoidCallback? onLeft;
  final Color leftColor;
  final bool leftFilled;
  final Key rightKey;
  final IconData rightIcon;
  final String rightLabel;
  final VoidCallback? onRight;
  final Color rightColor;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(16));
    final label = udText(16, weight: FontWeight.w700);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      color: udBackground,
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 54,
              child: leftFilled
                  ? FilledButton.icon(
                      key: leftKey,
                      onPressed: onLeft,
                      icon: Icon(leftIcon),
                      label: FittedBox(fit: BoxFit.scaleDown, child: Text(leftLabel, maxLines: 1)),
                      style: FilledButton.styleFrom(
                        backgroundColor: leftColor,
                        shape: shape,
                        textStyle: label,
                      ),
                    )
                  : OutlinedButton.icon(
                      key: leftKey,
                      onPressed: onLeft,
                      icon: Icon(leftIcon),
                      label: FittedBox(fit: BoxFit.scaleDown, child: Text(leftLabel, maxLines: 1)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: leftColor,
                        backgroundColor: leftColor.withValues(alpha: 0.08),
                        side: BorderSide(color: leftColor, width: 2),
                        shape: shape,
                        textStyle: label,
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: SizedBox(
              height: 54,
              child: FilledButton.icon(
                key: rightKey,
                onPressed: onRight,
                icon: Icon(rightIcon),
                label: FittedBox(fit: BoxFit.scaleDown, child: Text(rightLabel, maxLines: 1)),
                style: FilledButton.styleFrom(
                  backgroundColor: rightColor,
                  shape: shape,
                  textStyle: label,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
