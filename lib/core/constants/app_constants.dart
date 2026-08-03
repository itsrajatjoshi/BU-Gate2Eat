// BU Gate2Eat — Core Constants
// App-wide color palette, spacing, and configuration

import 'package:flutter/material.dart';

// ─── Brand Colors ──────────────────────────────────────────────
class AppColors {
  AppColors._();

  // Primary palette
  static const Color primary = Color(0xFF6C5CE7);
  static const Color primaryLight = Color(0xFFA29BFE);
  static const Color primaryDark = Color(0xFF4834D4);

  // Secondary palette
  static const Color secondary = Color(0xFF00CEC9);
  static const Color secondaryLight = Color(0xFF81ECEC);

  // Accent
  static const Color accent = Color(0xFFFD79A8);

  // Neutrals (matching reference screenshot)
  static const Color background = Color(0xFFF1F3F9);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceVariant = Color(0xFFEDEFF6);
  static const Color textPrimary = Color(0xFF1E293B);
  static const Color textSecondary = Color(0xFF64748B);
  static const Color textHint = Color(0xFF94A3B8);
  static const Color divider = Color(0xFFE2E8F0);

  // Dark mode (matching reference screenshot)
  static const Color darkBackground = Color(0xFF0D0E20);
  static const Color darkSurface = Color(0xFF181832);
  static const Color darkSurfaceVariant = Color(0xFF222246);
  static const Color darkTextPrimary = Color(0xFFFFFFFF);
  static const Color darkTextSecondary = Color(0xFF9EA3C0);

  // Semantic
  static const Color success = Color(0xFF00B894);
  static const Color warning = Color(0xFFFDAA5E);
  static const Color error = Color(0xFFFF6B6B);
  static const Color info = Color(0xFF74B9FF);

  // Food type indicators
  static const Color vegGreen = Color(0xFF27AE60);
  static const Color nonVegRed = Color(0xFFE74C3C);
}

// ─── Spacing ───────────────────────────────────────────────────
class AppSpacing {
  AppSpacing._();

  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 16.0;
  static const double lg = 24.0;
  static const double xl = 32.0;
  static const double xxl = 48.0;
}

// ─── Border Radius ─────────────────────────────────────────────
class AppRadius {
  AppRadius._();

  static const double sm = 8.0;
  static const double md = 12.0;
  static const double lg = 16.0;
  static const double xl = 24.0;
  static const double full = 999.0;
}

// ─── App Config ────────────────────────────────────────────────
class AppConfig {
  AppConfig._();

  static const String appName = 'BU Gate2Eat';
  static const String appTagline = 'Everything around Bennett. One app. One tap.';
  static const String pickupLocation = 'Bennett Gate No. 2';
  static const String whatsappBranding = '~ Sent via BU Gate2Eat';

  // Special instructions character limit
  static const int maxSpecialInstructionsLength = 200;
}
