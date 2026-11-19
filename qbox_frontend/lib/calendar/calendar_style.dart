import 'package:flutter/material.dart';

import 'calendar_models.dart';

const calInk = Color(0xFF1C0E57);
const calBody = Color(0xFF5C5872);
const calPurple = Color(0xFF651CE4);
const calSoft = Color(0xFFF3EEFF);
const calBackground = Color(0xFFF7F4FF);
const calRed = Color(0xFFD93B4A);
const festivalColor = Color(0xFFE67700);

/// Each category's colour and icon, used for dots, chips and cards.
Color categoryColor(EventCategory c) => switch (c) {
  EventCategory.shop => calPurple,
  EventCategory.supplier => const Color(0xFF0C8599),
  EventCategory.payment => const Color(0xFFE8590C),
  EventCategory.personal => const Color(0xFFD6336C),
  EventCategory.other => const Color(0xFF4263EB),
};

IconData categoryIcon(EventCategory c) => switch (c) {
  EventCategory.shop => Icons.storefront_rounded,
  EventCategory.supplier => Icons.local_shipping_rounded,
  EventCategory.payment => Icons.currency_rupee_rounded,
  EventCategory.personal => Icons.person_rounded,
  EventCategory.other => Icons.event_note_rounded,
};

const calTitleStyle = TextStyle(
  fontFamily: 'Poppins',
  fontSize: 20,
  fontWeight: FontWeight.w700,
  color: calInk,
);
