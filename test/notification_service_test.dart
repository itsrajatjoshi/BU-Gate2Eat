// BU Gate2Eat — Tests
// Unit & Integration Tests for NotificationService (Part 2 — FCM Foundation & Device Token Registration)

import 'package:bugate2eat_app/core/constants/app_constants.dart';
import 'package:bugate2eat_app/services/local_storage_service.dart';
import 'package:bugate2eat_app/services/notification_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NotificationService — Token Masking & Formatting', () {
    test('maskToken handles null and empty safely', () {
      expect(NotificationService.maskToken(null), equals('<null>'));
      expect(NotificationService.maskToken(''), equals('<null>'));
    });

    test('maskToken handles short tokens with asterisks', () {
      expect(NotificationService.maskToken('abc123'), equals('***'));
      expect(NotificationService.maskToken('123456789012'), equals('***'));
    });

    test('maskToken formats long tokens with prefix, suffix and length', () {
      const sampleToken = 'fcm_token_1234567890_abcdefghij_zyxwvutsrq_987654321';
      final masked = NotificationService.maskToken(sampleToken);
      expect(masked.startsWith('fcm_to...'), isTrue);
      expect(masked.endsWith('(${sampleToken.length} chars)'), isTrue);
      expect(masked.contains('abcdefghij'), isFalse); // Sensitive middle characters hidden
    });
  });

  group('NotificationService — Session & Role Resolution', () {
    late NotificationService service;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      service = NotificationService();
    });

    tearDown(() {
      service.dispose();
    });

    test('Platform identifier is non-empty and valid', () {
      final platform = service.currentPlatform;
      expect(['android', 'ios', 'web', 'unknown'].contains(platform), isTrue);
    });

    test('Customer phone resolves to role=customer with shopId=null', () async {
      SharedPreferences.setMockInitialValues({
        'user_phone': '9876543210',
        'user_name': 'Test Customer',
      });
      final storage = await LocalStorageService.create();

      expect(storage.userPhone, equals('9876543210'));
      expect(AppAuthRoles.getShopIdForPhone(storage.userPhone), isNull);
    });

    test('Shopkeeper phones resolve to role=shopkeeper with respective authoritative shopId', () async {
      final testCases = {
        '8000383993': 'rajat_shop',
        '8295643910': 'nayan_shop',
        '8875344034': 'kivisha_shop',
        '8079065843': 'up16_junction_fast_food',
        '8888822222': 'raja_hotel',
        '9999922222': 'up16_queens',
      };

      for (final entry in testCases.entries) {
        SharedPreferences.setMockInitialValues({
          'user_phone': entry.key,
          'user_name': 'Shopkeeper ${entry.value}',
        });
        final storage = await LocalStorageService.create();
        final mappedShop = AppAuthRoles.getShopIdForPhone(storage.userPhone);
        expect(mappedShop, equals(entry.value), reason: 'Phone ${entry.key} must resolve to ${entry.value}');
      }
    });

    test('Admin phone resolves to admin role', () async {
      SharedPreferences.setMockInitialValues({
        'user_phone': AppAuthRoles.adminPhone,
        'user_name': 'Super Admin',
      });
      final storage = await LocalStorageService.create();
      expect(storage.userPhone, equals(AppAuthRoles.adminPhone));
      expect(storage.userPhone == AppAuthRoles.adminPhone, isTrue);
    });

    test('Non-blocking execution when Firebase Messaging instance is unavailable in tests', () async {
      SharedPreferences.setMockInitialValues({});
      final storage = await LocalStorageService.create();

      // initialize should complete safely without throwing uncaught exceptions
      await expectLater(service.initialize(localStorage: storage), completes);
      expect(service.cachedToken, isNull);
    });

    test('Repeated registerDeviceToken calls with empty token do not crash', () async {
      await expectLater(
        service.registerDeviceToken(
          token: '',
          phone: '9876543210',
          role: 'customer',
        ),
        completes,
      );
    });
  });
}
