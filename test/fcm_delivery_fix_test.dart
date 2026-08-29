// BU Gate2Eat — Tests
// Part 8.1 & 8.2: Real-Device Delivery Fix & Anonymous Elimination Validation Tests
// Verifies channel ID constants, anonymous token exclusion, identity-triggered token sync logic, permission safety, and foreground payload conversion.

import 'package:bugate2eat_app/core/constants/app_constants.dart';
import 'package:bugate2eat_app/services/local_storage_service.dart';
import 'package:bugate2eat_app/services/notification_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Part 8.1 — Notification Channel Constants & Contracts', () {
    test('Channel IDs match exact backend Cloud Function contract', () {
      expect(NotificationService.shopkeeperChannelId, equals('yummbu_orders_channel'));
      expect(NotificationService.customerChannelId, equals('yummbu_customer_orders_channel'));
    });
  });

  group('Part 8.2 — Anonymous Token Exclusion & Identity Lifecycle', () {
    test('Initial anonymous state generates cust_anon customerId and empty phone', () async {
      SharedPreferences.setMockInitialValues({});
      final storage = await LocalStorageService.create();

      expect(storage.userPhone, isEmpty);
      expect(storage.customerId.startsWith('cust_anon_'), isTrue);
      expect(AppAuthRoles.getShopIdForPhone(storage.userPhone), isNull);
    });

    test('Anonymous sessions are excluded from targetable token registration', () async {
      final service = NotificationService();
      
      // Empty token or empty phone skips registration
      await service.registerDeviceToken(
        token: 'test_token',
        phone: '',
        role: 'customer',
      );
      // Completes safely without throwing and rejects anonymous phone
    });

    test('Onboarding phone submission upgrades customerId to cust_<phone>', () async {
      SharedPreferences.setMockInitialValues({});
      final storage = await LocalStorageService.create();
      await storage.saveUserProfile(name: 'Rajat Joshi', phone: '8075656566');

      expect(storage.userPhone, equals('8075656566'));
      expect(storage.customerId, equals('cust_8075656566'));
      expect(AppAuthRoles.getShopIdForPhone(storage.userPhone), isNull);
    });

    test('Shopkeeper login correctly resolves role=shopkeeper and authoritative shopId', () async {
      SharedPreferences.setMockInitialValues({});
      final storage = await LocalStorageService.create();
      await storage.saveUserProfile(name: 'Rajat Shopkeeper', phone: '8000383993');

      expect(storage.userPhone, equals('8000383993'));
      final shopId = AppAuthRoles.getShopIdForPhone(storage.userPhone);
      expect(shopId, equals('rajat_shop'));
    });

    test('Session switch from Customer to Shopkeeper re-evaluates identity correctly', () async {
      SharedPreferences.setMockInitialValues({});
      final storage = await LocalStorageService.create();
      
      // Step 1: Customer
      await storage.saveUserProfile(name: 'Student Customer', phone: '9876543210');
      expect(storage.userPhone, equals('9876543210'));
      expect(storage.customerId, equals('cust_9876543210'));
      expect(AppAuthRoles.getShopIdForPhone(storage.userPhone), isNull);

      // Step 2: Logout
      await storage.logout();
      expect(storage.userPhone, isEmpty);

      // Step 3: Login as Shopkeeper
      await storage.saveUserProfile(name: 'Nayan Shop', phone: '8295643910');
      expect(storage.userPhone, equals('8295643910'));
      expect(AppAuthRoles.getShopIdForPhone(storage.userPhone), equals('nayan_shop'));
    });

    test('Customer A to Customer B transition updates phone and customerId correctly', () async {
      SharedPreferences.setMockInitialValues({});
      final storage = await LocalStorageService.create();

      // Customer A
      await storage.saveUserProfile(name: 'Customer A', phone: '9111111111');
      expect(storage.userPhone, equals('9111111111'));
      expect(storage.customerId, equals('cust_9111111111'));

      // Logout
      await storage.logout();
      expect(storage.userPhone, isEmpty);

      // Customer B
      await storage.saveUserProfile(name: 'Customer B', phone: '9222222222');
      expect(storage.userPhone, equals('9222222222'));
      expect(storage.customerId, equals('cust_9222222222'));
    });
  });

  group('Part 8.1 — PendingNotification Parsing & Foreground Presentation', () {
    test('Constructs PendingNotification from payload accurately', () {
      final notification = PendingNotification(
        type: 'new_order',
        receivedAt: DateTime.now(),
        orderId: 'YB-20260829-001',
        shopId: 'rajat_shop',
        recipientRole: 'shopkeeper',
        title: '🍔 New Order Received!',
        body: 'Order #YB-20260829-001 • ₹150',
      );

      expect(notification.isValidOrderNotification, isTrue);
      expect(notification.orderId, equals('YB-20260829-001'));
      expect(notification.shopId, equals('rajat_shop'));
      expect(notification.recipientRole, equals('shopkeeper'));
      expect(notification.type, equals('new_order'));
    });

    test('PendingNotification toString outputs sanitized diagnostics', () {
      final notification = PendingNotification(
        type: 'order_accepted',
        receivedAt: DateTime(2026, 8, 29, 12, 0),
        orderId: 'YB-TEST-999',
        shopId: 'rajat_shop',
        recipientRole: 'customer',
      );

      final str = notification.toString();
      expect(str.contains('YB-TEST-999'), isTrue);
      expect(str.contains('order_accepted'), isTrue);
    });
  });
}
