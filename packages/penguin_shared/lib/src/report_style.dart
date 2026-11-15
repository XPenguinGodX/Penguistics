import 'package:flutter/material.dart';

import 'penguin_theme.dart';
import 'penguin_widgets.dart';

/// Every report status, in the order a report moves through them:
/// the model checks it, then the city works on it.
const reportStatuses = [
  'PENDING',
  'CONFIRMED',
  'ACTIVE',
  'COMPLETED',
  'REJECTED',
  'DISMISSED',
];

/// How each report status looks: pin color, the symbol drawn on the pin and its
/// color, the wording, and the banner tone for the details sheet.
({Color pin, IconData symbol, Color icon, String label, PenguinTone tone})
reportStyle(String status) => switch (status) {
  'CONFIRMED' => (
    pin: PenguinColors.yellow,
    symbol: Icons.report_rounded,
    icon: PenguinColors.black,
    label: 'Confirmed',
    tone: PenguinTone.success,
  ),
  // The city is working on it
  'ACTIVE' => (
    pin: PenguinColors.blue,
    symbol: Icons.construction_rounded,
    icon: PenguinColors.white,
    label: 'Being repaired',
    tone: PenguinTone.info,
  ),
  'COMPLETED' => (
    pin: PenguinColors.white,
    symbol: Icons.check_rounded,
    icon: PenguinColors.black,
    label: 'Fixed',
    tone: PenguinTone.success,
  ),
  // The model decided the photo isn't road damage
  'REJECTED' => (
    pin: PenguinColors.charcoalHigh,
    symbol: Icons.close_rounded,
    icon: PenguinColors.muted,
    label: 'Not confirmed',
    tone: PenguinTone.info,
  ),
  // The city closed it without a repair (a duplicate, not the city's road, ...).
  // Same gray as REJECTED, since neither will be fixed; the symbol tells them apart.
  'DISMISSED' => (
    pin: PenguinColors.charcoalHigh,
    symbol: Icons.block_rounded,
    icon: PenguinColors.muted,
    label: 'Closed by the city',
    tone: PenguinTone.info,
  ),
  // PENDING: the model hasn't scored the photo yet.
  // Any status added to the backend later also lands here until it gets its own case.
  _ => (
    pin: PenguinColors.orange,
    symbol: Icons.hourglass_top_rounded,
    icon: PenguinColors.black,
    label: 'Checking',
    tone: PenguinTone.warning,
  ),
};
