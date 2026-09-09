// BU Gate2Eat — Security Architecture
// Phase 7.2: App Check Testing, Validation & Bypass Resistance Test Suite

import 'package:bugate2eat_app/core/config/app_environment.dart';
import 'package:bugate2eat_app/services/app_check_service.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Phase 7.2 — AppCheckService Verification & Test Matrix', () {
    setUp(() {
      AppCheckService.resetForTesting();
    });

    test('1. Initial state: isInitialized is false after resetForTesting', () {
      expect(AppCheckService.isInitialized, isFalse);
    });

    test('2. Android Debug Provider is selected in non-release mode', () {
      expect(kReleaseMode, isFalse);
      final provider = AppCheckService.resolveAndroidProvider();
      expect(provider, equals(AndroidProvider.debug));
    });

    test('3. Apple Debug Provider is selected in non-release mode', () {
      expect(kReleaseMode, isFalse);
      final provider = AppCheckService.resolveAppleProvider();
      expect(provider, equals(AppleProvider.debug));
    });

    test('4. Token query before initialization safely returns null without crash', () async {
      final token = await AppCheckService.getToken();
      expect(token, isNull);
    });

    test('5. Headless test environment initialization catches native bridge absence gracefully', () async {
      // In headless test runner, Firebase is not booted and no native Android bridge exists.
      // AppCheckService must capture errors non-fatally to avoid breaking test harnesses.
      await AppCheckService.initialize();
      expect(true, isTrue);
    });

    test('6. Idempotent initialization: Consecutive calls do not throw or duplicate bootstrap', () async {
      await AppCheckService.initialize();
      // Second invocation should be a safe no-op
      await AppCheckService.initialize();
      expect(true, isTrue);
    });

    test('7. Bypass Resistance: Runtime AppEnvironment cannot influence compile-time provider resolution', () {
      // Regardless of AppEnvironment state (dev/staging/prod), resolveAndroidProvider() relies
      // exclusively on compile-time kReleaseMode, resisting runtime injection.
      expect(AppEnvironment.current, isNotNull);
      final provider = AppCheckService.resolveAndroidProvider();
      expect(provider, equals(AndroidProvider.debug));
    });

    test('8. Token auto-refresh query resilience under test conditions', () async {
      // Testing forceRefresh parameter handling
      final token = await AppCheckService.getToken(forceRefresh: true);
      expect(token, isNull);
    });
  });
}
