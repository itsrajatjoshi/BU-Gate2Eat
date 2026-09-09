// BU Gate2Eat — Security Architecture
// Phase 7.1: Firebase App Check Service & Platform Attestation Coordinator

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart';

import '../core/config/app_environment.dart';

/// Centralized coordinator for Firebase App Check device attestation.
///
/// Scope & Platform Status:
/// - Android: Primary supported mobile target. Play Integrity in production release;
///   Debug provider in local development / emulators.
/// - Web: NOT IMPLEMENTED in Phase 7.1 (requires reCAPTCHA Enterprise/v3 provider configuration).
/// - iOS/macOS: Prepared with App Attest/DeviceCheck fallback if Apple credentials are provisioned.
/// - Desktop (Windows/Linux): Skipped cleanly via platform guard.
///
/// Mandates:
/// 1. Enforces compile-time environment-deterministic provider selection via `kReleaseMode`:
///    - Production Release (Android): `AndroidProvider.playIntegrity`.
///    - Local Development / Debug / Emulators: `AndroidProvider.debug`.
/// 2. Strictly forbids Debug Provider execution in release builds (`kReleaseMode`),
///    backed by compile-time logic and runtime StateError validation.
/// 3. Zero hardcoded secrets: Debug tokens are NOT hardcoded, committed, or logged.
/// 4. Non-fatal initialization: Startup errors in unsupported/headless test environments
///    are caught and logged without crashing the Flutter application.
/// 5. Separates App Check (client authenticity) from Authentication (user identity/RBAC).
class AppCheckService {
  AppCheckService._();

  static bool _isInitialized = false;

  /// Returns whether App Check has been initialized in the current runtime.
  static bool get isInitialized => _isInitialized;

  /// For unit testing isolation: resets the initialization state.
  @visibleForTesting
  static void resetForTesting() {
    _isInitialized = false;
  }

  /// Determines the appropriate AndroidProvider based on build mode and environment.
  /// Compile-time protection: Release builds ALWAYS resolve to Play Integrity.
  /// Debug builds resolve to Debug provider.
  static AndroidProvider resolveAndroidProvider() {
    if (kReleaseMode) {
      return AndroidProvider.playIntegrity;
    }
    return AndroidProvider.debug;
  }

  /// Determines the appropriate AppleProvider based on build mode and environment.
  static AppleProvider resolveAppleProvider() {
    if (kReleaseMode) {
      return AppleProvider.appAttestWithDeviceCheckFallback;
    }
    return AppleProvider.debug;
  }

  /// Initializes App Check with the appropriate platform attestation provider.
  /// Must be invoked AFTER `Firebase.initializeApp()` and BEFORE any Firebase service calls.
  static Future<void> initialize({
    FirebaseAppCheck? appCheckInstance,
  }) async {
    if (_isInitialized) {
      debugPrint('ℹ️ [AppCheck] App Check is already initialized.');
      return;
    }

    // Defense-in-depth safety check: Not relying on stripped asserts
    if (kReleaseMode && resolveAndroidProvider() == AndroidProvider.debug) {
      throw StateError(
        'SECURITY VIOLATION: Debug Provider must never be used in release builds.',
      );
    }

    try {
      // Platform check: Web App Check requires reCAPTCHA Enterprise/v3 which is not yet provisioned.
      if (kIsWeb) {
        debugPrint(
          'ℹ️ [AppCheck] Web platform detected: Web App Check is NOT IMPLEMENTED (future scope). Skipping.',
        );
        _isInitialized = true;
        return;
      }

      // Platform check: Desktop OS targets (Windows/Linux) do not support mobile attestation.
      if (defaultTargetPlatform != TargetPlatform.android &&
          defaultTargetPlatform != TargetPlatform.iOS &&
          defaultTargetPlatform != TargetPlatform.macOS) {
        debugPrint(
          'ℹ️ [AppCheck] Platform $defaultTargetPlatform does not require mobile attestation. Skipping.',
        );
        _isInitialized = true;
        return;
      }

      final appCheck = appCheckInstance ?? FirebaseAppCheck.instance;
      final androidProvider = resolveAndroidProvider();
      final appleProvider = resolveAppleProvider();

      await appCheck.activate(
        androidProvider: androidProvider,
        appleProvider: appleProvider,
      );

      // Set token auto-refresh to maintain valid attestation tokens
      await appCheck.setTokenAutoRefreshEnabled(true);

      _isInitialized = true;

      if (!kReleaseMode) {
        debugPrint(
          '🛡️ [AppCheck] Activated successfully. Environment: ${AppEnvironment.name} '
          '(AndroidProvider: $androidProvider, AppleProvider: $appleProvider)',
        );
      }
    } catch (e, stack) {
      // In local dev/emulator or headless unit tests, App Check might not have native bridge.
      // Log the warning without crashing the app startup.
      debugPrint('⚠️ [AppCheck] Initialization note (non-fatal): $e\n$stack');
    }
  }

  /// Manually retrieves the current App Check token, if needed for diagnostics.
  /// Returns null if attestation is unavailable or fails.
  static Future<String?> getToken({bool forceRefresh = false}) async {
    if (!_isInitialized) return null;
    try {
      final token = await FirebaseAppCheck.instance.getToken(forceRefresh);
      return token;
    } catch (e) {
      debugPrint('⚠️ [AppCheck] Failed to retrieve token: $e');
      return null;
    }
  }
}
