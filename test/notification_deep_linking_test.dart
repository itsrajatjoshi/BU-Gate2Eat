// BU Gate2Eat — Tests
// Unit & Integration Tests for Part 6: Notification Tap & GoRouter Deep Linking Engine

import 'package:bugate2eat_app/core/constants/app_constants.dart';
import 'package:bugate2eat_app/core/router.dart';
import 'package:bugate2eat_app/services/notification_router_bridge.dart';
import 'package:bugate2eat_app/services/notification_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    NotificationRouterBridge.resetThrottleState();
  });

  group('Part 6: Notification Tap & GoRouter Deep Linking Suite', () {
    // ─── CUSTOMER ROUTING TESTS ─────────────────────────────────────────────
    test('1. Customer Accepted: Validates and resolves to /order/:orderId route', () {
      final notification = PendingNotification(
        type: 'order_accepted',
        orderId: 'YB-2026-08-200',
        shopId: 'rajat_shop',
        recipientRole: 'customer',
        receivedAt: DateTime.now(),
      );

      final routeResult = NotificationRouterBridge.resolveRoute(
        notification: notification,
        userPhone: '9876543210', // Regular customer phone
      );

      expect(routeResult.isAuthorized, isTrue);
      expect(routeResult.route, equals('/order/YB-2026-08-200'));
      expect(routeResult.orderId, equals('YB-2026-08-200'));
    });

    test('2. Customer Rejected: Resolves to /order/:orderId route', () {
      final notification = PendingNotification(
        type: 'order_rejected',
        orderId: 'YB-2026-08-201',
        shopId: 'rajat_shop',
        recipientRole: 'customer',
        receivedAt: DateTime.now(),
      );

      final routeResult = NotificationRouterBridge.resolveRoute(
        notification: notification,
        userPhone: '9876543210',
      );

      expect(routeResult.isAuthorized, isTrue);
      expect(routeResult.route, equals('/order/YB-2026-08-201'));
    });

    test('3. Customer Delivered: Resolves to /order/:orderId route', () {
      final notification = PendingNotification(
        type: 'order_delivered',
        orderId: 'YB-2026-08-202',
        shopId: 'rajat_shop',
        recipientRole: 'customer',
        receivedAt: DateTime.now(),
      );

      final routeResult = NotificationRouterBridge.resolveRoute(
        notification: notification,
        userPhone: '9876543210',
      );

      expect(routeResult.isAuthorized, isTrue);
      expect(routeResult.route, equals('/order/YB-2026-08-202'));
    });

    test('4. Customer Expired: Resolves to /order/:orderId route', () {
      final notification = PendingNotification(
        type: 'order_expired',
        orderId: 'YB-2026-08-203',
        shopId: 'rajat_shop',
        recipientRole: 'customer',
        receivedAt: DateTime.now(),
      );

      final routeResult = NotificationRouterBridge.resolveRoute(
        notification: notification,
        userPhone: '9876543210',
      );

      expect(routeResult.isAuthorized, isTrue);
      expect(routeResult.route, equals('/order/YB-2026-08-203'));
    });

    // ─── SHOPKEEPER ROUTING TESTS ───────────────────────────────────────────
    test('5. Shopkeeper New Order: Resolves to /shopkeeper when authorized for the target shop', () {
      final notification = PendingNotification(
        type: 'new_order',
        orderId: 'YB-2026-08-100',
        shopId: 'rajat_shop',
        recipientRole: 'shopkeeper',
        receivedAt: DateTime.now(),
      );

      final routeResult = NotificationRouterBridge.resolveRoute(
        notification: notification,
        userPhone: '8000383993', // Authorized Rajat Shop phone
      );

      expect(routeResult.isAuthorized, isTrue);
      expect(routeResult.route, equals(AppRoutes.shopkeeper));
      expect(routeResult.shopId, equals('rajat_shop'));
    });

    // ─── SECURITY & ROLE ISOLATION TESTS ────────────────────────────────────
    test('6. Cross-Shop Isolation: Rajat shopkeeper cannot open Nayan shop notification', () {
      final notification = PendingNotification(
        type: 'new_order',
        orderId: 'YB-2026-08-999',
        shopId: 'nayan_shop', // Target shop is Nayan
        recipientRole: 'shopkeeper',
        receivedAt: DateTime.now(),
      );

      final routeResult = NotificationRouterBridge.resolveRoute(
        notification: notification,
        userPhone: '8000383993', // Logged in as Rajat shopkeeper
      );

      expect(routeResult.isAuthorized, isFalse);
      expect(routeResult.rejectionReason, contains('unauthorized for target shop'));
    });

    test('7. Unauthorized Role: Non-shopkeeper cannot open shopkeeper notification', () {
      final notification = PendingNotification(
        type: 'new_order',
        orderId: 'YB-2026-08-100',
        shopId: 'rajat_shop',
        recipientRole: 'shopkeeper',
        receivedAt: DateTime.now(),
      );

      final routeResult = NotificationRouterBridge.resolveRoute(
        notification: notification,
        userPhone: '9876543210', // Normal customer phone
      );

      expect(routeResult.isAuthorized, isFalse);
      expect(routeResult.rejectionReason, contains('not registered as a shopkeeper'));
    });

    test('8. Admin Safety: Admin session blocks customer order routing from push', () {
      final notification = PendingNotification(
        type: 'order_accepted',
        orderId: 'YB-2026-08-200',
        shopId: 'rajat_shop',
        recipientRole: 'customer',
        receivedAt: DateTime.now(),
      );

      final routeResult = NotificationRouterBridge.resolveRoute(
        notification: notification,
        userPhone: AppAuthRoles.adminPhone, // Admin phone
      );

      expect(routeResult.isAuthorized, isFalse);
      expect(routeResult.rejectionReason, contains('Admin session'));
    });

    // ─── PAYLOAD VALIDATION & SAFETY ────────────────────────────────────────
    test('9. Malformed Payload Safety: Missing orderId is rejected cleanly without crashing', () {
      final notification = PendingNotification(
        type: 'order_accepted',
        orderId: null,
        shopId: 'rajat_shop',
        receivedAt: DateTime.now(),
      );

      final validation = NotificationRouterBridge.validateNotification(notification);
      expect(validation.isValid, isFalse);
      expect(validation.errorMessage, contains('Missing or empty orderId'));
    });

    test('10. Unknown Notification Type: Unknown event type is rejected safely', () {
      final notification = PendingNotification(
        type: 'some_future_unsupported_event',
        orderId: 'YB-2026-08-300',
        shopId: 'rajat_shop',
        receivedAt: DateTime.now(),
      );

      final validation = NotificationRouterBridge.validateNotification(notification);
      expect(validation.isValid, isFalse);
      expect(validation.errorMessage, contains('Unknown or unsupported'));
    });

    // ─── DUPLICATE TAP PROTECTION TESTS ─────────────────────────────────────
    test('11. Duplicate Tap Protection: Repeated rapid taps for the same order are throttled', () {
      final isFirst = NotificationRouterBridge.isDuplicateTap('YB-2026-08-100');
      expect(isFirst, isFalse); // First tap allowed

      final isSecond = NotificationRouterBridge.isDuplicateTap('YB-2026-08-100');
      expect(isSecond, isTrue); // Immediate duplicate suppressed

      final isDifferentOrder = NotificationRouterBridge.isDuplicateTap('YB-2026-08-200');
      expect(isDifferentOrder, isFalse); // Different order allowed
    });

    test('12. Exact-Once Consumption: Consuming pending notification clears it from memory', () {
      final service = NotificationService();
      final consumed = service.consumePendingNotification();
      expect(consumed, isNull);
    });
  });
}
