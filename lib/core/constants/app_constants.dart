// BU Gate2Eat — Core Constants
// App-wide color palette, spacing, and configuration

import 'package:flutter/material.dart';

// ─── Brand Colors ──────────────────────────────────────────────
class AppColors {
  AppColors._();

  // Primary palette (Rich Food Orange & Warm Cream Tints)
  static const Color primary = Color(0xFFFF6B35);
  static const Color primaryLight = Color(0xFFFFF0EC);
  static const Color primaryDark = Color(0xFFD94E1B);

  // Secondary palette (Warm Gold Highlights)
  static const Color secondary = Color(0xFFFFC857);
  static const Color secondaryLight = Color(0xFFFFF3D6);

  // Accent
  static const Color accent = Color(0xFFFF6B35);

  // Neutrals (Warm Ivory background & Clean White surface)
  static const Color background = Color(0xFFFFF9F5);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceVariant = Color(0xFFF6F0EA);
  static const Color textPrimary = Color(0xFF1F1F1F);
  static const Color textSecondary = Color(0xFF6B6B6B);
  static const Color textHint = Color(0xFF9E9E9E);
  static const Color divider = Color(0xFFEFE8E1);

  // Dark mode (Polished deep charcoal food-app palette)
  static const Color darkBackground = Color(0xFF111113);
  static const Color darkSurface = Color(0xFF18181B);
  static const Color darkSurfaceVariant = Color(0xFF202024);
  static const Color darkTextPrimary = Color(0xFFF5F5F5);
  static const Color darkTextSecondary = Color(0xFFA1A1AA);
  static const Color darkTextHint = Color(0xFF71717A);
  static const Color darkDivider = Color(0xFF27272A);

  // Semantic
  static const Color success = Color(0xFF22A06B);
  static const Color warning = Color(0xFFFF9800);
  static const Color error = Color(0xFFE5484D);
  static const Color info = Color(0xFF3B82F6);

  // Food type indicators
  static const Color vegGreen = Color(0xFF22A06B);
  static const Color nonVegRed = Color(0xFFE5484D);
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

  static const String appName = 'YummBU';
  static const String appTagline = 'Everything around Bennett. One app. One tap.';
  static const String pickupLocation = 'Bennett Gate No. 2';
  static const String whatsappBranding = '~ Sent via YummBU';

  // Special instructions character limit
  static const int maxSpecialInstructionsLength = 200;

  // App version
  static const String appVersion = '1.0.4';
}
