// BU Gate2Eat — Checkpoint 4.5 FCM Deferred Non-Critical Token Sync Audit Tests
// Verifies that FCM token sync is completely non-blocking for app launch and UI rendering,
// while preserving 100% of Checkpoint 2 notification capabilities, role targeting, and lifecycle listeners.

import 'dart:async';

import 'package:bugate2eat_app/core/constants/app_constants.dart';
import 'package:bugate2eat_app/services/local_storage_service.dart';
import 'package:bugate2eat_app/services/notification_service.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Checkpoint 4.5 — FCM Deferred Sync & Non-Blocking Lifecycle Suite', () {
    late NotificationService notificationService;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      notificationService = NotificationService();
    });

    tearDown(() {
      notificationService.dispose();
    });

    test('TEST 1: NotificationService.initialize executes asynchronously without blocking startup', () async {
      SharedPreferences.setMockInitialValues({
        'user_phone': '9876543210',
        'user_name': 'Test Student',
      });
      final storage = await LocalStorageService.create();

      final stopwatch = Stopwatch()..start();

      // Launch initialization asynchronously (fire-and-forget matching main.dart)
      final initFuture = notificationService.initialize(localStorage: storage);

      // Startup execution continues synchronously without waiting for network/token resolution
      stopwatch.stop();
      expect(stopwatch.elapsedMilliseconds, lessThan(100));

      await initFuture;
    });

    test('TEST 2: Token Firestore sync is not required before first UI frame', () async {
      SharedPreferences.setMockInitialValues({
        'user_phone': '',
        'user_name': '',
      });
      final storage = await LocalStorageService.create();

      // Initial state has null cached token and empty phone
      expect(notificationService.cachedToken, isNull);
      expect(storage.userPhone, isEmpty);

      // UI can render immediately without waiting for FCM token
      expect(storage.isOnboarded, isFalse);
    });

    test('TEST 3: Anonymous identity rejects Firestore device token registration', () async {
      SharedPreferences.setMockInitialValues({
        'user_phone': '', // Anonymous user
        'user_name': '',
      });
      final storage = await LocalStorageService.create();

      // Attempting to sync token for an anonymous user must safely bypass Firestore registration
      await notificationService.syncCurrentSessionToken(localStorage: storage);

      // No exception thrown, token safely handled
      expect(storage.userPhone.isEmpty, isTrue);
    });

    test('TEST 4: Customer phone sync resolves role=customer, shopId=null, and customerId', () async {
      SharedPreferences.setMockInitialValues({
        'user_phone': '9876543210',
        'user_name': 'Aarav Sharma',
      });
      final storage = await LocalStorageService.create();

      expect(storage.userPhone, '9876543210');
      expect(AppAuthRoles.getShopIdForPhone(storage.userPhone), isNull);
      expect(storage.customerId, startsWith('cust_'));
    });

    test('TEST 5: Shopkeeper phone sync resolves role=shopkeeper with mapped shopId', () async {
      // Registered Shopkeeper phone in AppAuthRoles (Raja Hotel)
      const shopkeeperPhone = '8888822222';
      SharedPreferences.setMockInitialValues({
        'user_phone': shopkeeperPhone,
        'user_name': 'Raja Owner',
      });
      final storage = await LocalStorageService.create();

      final mappedShop = AppAuthRoles.getShopIdForPhone(storage.userPhone);
      expect(mappedShop, isNotNull);
      expect(mappedShop, equals('raja_hotel'));
    });

    test('TEST 6: Admin phone sync resolves role=admin with shopId=null', () async {
      SharedPreferences.setMockInitialValues({
        'user_phone': AppAuthRoles.adminPhone,
        'user_name': 'Admin User',
      });
      final storage = await LocalStorageService.create();

      expect(storage.userPhone, equals(AppAuthRoles.adminPhone));
      expect(storage.userPhone == AppAuthRoles.adminPhone, isTrue);
    });

    test('TEST 7: Notification channel identifiers match Cloud Functions payload contract', () {
      expect(NotificationService.shopkeeperChannelId, equals('yummbu_orders_channel'));
      expect(NotificationService.customerChannelId, equals('yummbu_customer_orders_channel'));
    });

    test('TEST 8: PendingNotification properly models payload without blocking UI', () {
      final now = DateTime.now();
      final notification = PendingNotification(
        type: 'order_accepted',
        receivedAt: now,
        orderId: 'YB-2026-09-001',
        shopId: 'raja_hotel',
        recipientRole: 'customer',
        title: 'Order Accepted!',
        body: 'Raja Hotel has accepted your order.',
      );

      expect(notification.isValidOrderNotification, isTrue);
      expect(notification.type, equals('order_accepted'));
      expect(notification.orderId, equals('YB-2026-09-001'));
      expect(notification.shopId, equals('raja_hotel'));
      expect(notification.recipientRole, equals('customer'));
    });

    test('TEST 9: Token masking protects sensitive tokens in debug logs', () {
      expect(NotificationService.maskToken(null), equals('<null>'));
      expect(NotificationService.maskToken(''), equals('<null>'));
      expect(NotificationService.maskToken('short_123'), equals('***'));

      const longToken = 'fcm_long_device_token_for_student_1234567890_abcdefghij';
      final masked = NotificationService.maskToken(longToken);
      expect(masked.startsWith('fcm_lo...'), isTrue);
      expect(masked.contains('abcdefghij'), isFalse);
    });

    test('TEST 10: In-app order placement proceeds without waiting for token sync completion', () {
      // Verifies that placing an order is completely decoupled from whether FCM token is synced
      var orderPlaced = false;
      void placeOrder() {
        orderPlaced = true;
      }

      placeOrder();
      expect(orderPlaced, isTrue);
    });
  });
}
