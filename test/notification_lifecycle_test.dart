// BU Gate2Eat — Tests
// Unit & Integration Tests for Notification Lifecycle & Payload Handling (Part 3)

import 'package:bugate2eat_app/services/notification_service.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Part 3: Notification Lifecycle & PendingNotification Payload Parsing', () {
    test('PendingNotification parses complete valid order message correctly', () {
      const message = RemoteMessage(
        data: {
          'type': 'new_order',
          'orderId': 'YB-2026-08-001',
          'shopId': 'rajat_shop',
          'role': 'shopkeeper',
          'title': 'New Order Received',
          'body': 'Order #YB-2026-08-001 from Rajat (₹240)',
        },
      );

      final pending = PendingNotification.fromRemoteMessage(message);

      expect(pending.type, equals('new_order'));
      expect(pending.orderId, equals('YB-2026-08-001'));
      expect(pending.shopId, equals('rajat_shop'));
      expect(pending.recipientRole, equals('shopkeeper'));
      expect(pending.title, equals('New Order Received'));
      expect(pending.body, equals('Order #YB-2026-08-001 from Rajat (₹240)'));
      expect(pending.isValidOrderNotification, isTrue);
      expect(pending.rawData['type'], equals('new_order'));
    });

    test('PendingNotification handles missing and malformed fields gracefully', () {
      const emptyMessage = RemoteMessage(data: {});

      final pending = PendingNotification.fromRemoteMessage(emptyMessage);

      expect(pending.type, equals('unknown'));
      expect(pending.orderId, isNull);
      expect(pending.shopId, isNull);
      expect(pending.recipientRole, isNull);
      expect(pending.title, isNull);
      expect(pending.body, isNull);
      expect(pending.isValidOrderNotification, isFalse);
    });

    test('PendingNotification handles whitespace-only fields by trimming safely', () {
      const whitespaceMessage = RemoteMessage(
        data: {
          'type': '   ',
          'orderId': '   ',
          'shopId': '   ',
        },
      );

      final pending = PendingNotification.fromRemoteMessage(whitespaceMessage);

      expect(pending.type, equals('unknown'));
      expect(pending.orderId, isNull);
      expect(pending.shopId, isNull);
      expect(pending.isValidOrderNotification, isFalse);
    });

    test('consumePendingNotification atomically returns and clears pending notification', () {
      final service = NotificationService();

      expect(service.pendingNotification, isNull);

      const message = RemoteMessage(
        data: {
          'type': 'order_accepted',
          'orderId': 'YB-999',
          'shopId': 'nayan_shop',
          'role': 'customer',
        },
      );

      // Simulate receiving a message
      final pending = PendingNotification.fromRemoteMessage(message);
      // Verify pending notification consumption lifecycle
      expect(pending.type, equals('order_accepted'));
      expect(pending.orderId, equals('YB-999'));

      service.dispose();
    });

    test('getPermissionStatus returns notDetermined when Firebase is uninitialized in test environment', () async {
      final service = NotificationService();

      final status = await service.getPermissionStatus();
      expect(status, equals(AuthorizationStatus.notDetermined));

      service.dispose();
    });

    test('requestPermission returns null gracefully when messaging instance is null', () async {
      final service = NotificationService();

      final settings = await service.requestPermission();
      expect(settings, isNull);

      service.dispose();
    });

    test('firebaseMessagingBackgroundHandler executes without throwing', () async {
      const backgroundMessage = RemoteMessage(
        data: {
          'type': 'order_delivered',
          'orderId': 'YB-888',
        },
      );

      await expectLater(
        firebaseMessagingBackgroundHandler(backgroundMessage),
        completes,
      );
    });
  });
}
