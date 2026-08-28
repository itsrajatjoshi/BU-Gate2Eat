// BU Gate2Eat — Tests
// Unit Tests for Part 5: Customer Order Lifecycle Notifications & Targeting Engine

import 'package:bugate2eat_app/models/order_model.dart';
import 'package:bugate2eat_app/services/customer_notification_dispatcher.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Part 5: Customer Order Lifecycle Notification & Targeting Engine Suite', () {
    final sampleCustomerOrder = AppOrder(
      orderId: 'YB-2026-08-200',
      customerId: 'cust_9876543210',
      customerName: 'Aarav Sharma',
      customerPhone: '9876543210',
      shopId: 'rajat_shop',
      shopName: 'Rajat Shop',
      items: const [
        OrderItem(
          menuItemId: 'item_1',
          name: 'Cheese Burger',
          price: 120,
          quantity: 1,
        ),
      ],
      totalAmount: 120,
      status: 'placed',
      deliveryNote: 'Gate 3',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    final mockDeviceTokens = <Map<String, dynamic>>[
      // Customer A (Aarav) devices
      {
        'token': 'fcm_token_customer_a_phone1',
        'role': 'customer',
        'customerId': 'cust_9876543210',
        'phone': '9876543210',
      },
      {
        'token': 'fcm_token_customer_a_tablet2',
        'role': 'customer',
        'customerId': 'cust_9876543210',
        'phone': '9876543210',
      },
      {
        'token': 'fcm_token_customer_a_phone3',
        'role': 'customer',
        'customerId': 'cust_9876543210',
        'phone': '9876543210',
      },
      // Customer B (Different user) device
      {
        'token': 'fcm_token_customer_b',
        'role': 'customer',
        'customerId': 'cust_9999911111',
        'phone': '9999911111',
      },
      // Shopkeeper device (Rajat Shop)
      {
        'token': 'fcm_token_shopkeeper_rajat',
        'role': 'shopkeeper',
        'shopId': 'rajat_shop',
        'phone': '8000383993',
      },
      // Admin device
      {
        'token': 'fcm_token_admin',
        'role': 'admin',
        'phone': '8078643910',
      },
      // Stale / empty token
      {
        'token': '',
        'role': 'customer',
        'customerId': 'cust_9876543210',
        'phone': '9876543210',
      },
    ];

    test('1. Acceptance (placed -> accepted): Customer receives Order Accepted notification', () {
      final payload = CustomerNotificationTargetingLogic.buildCustomerLifecyclePayload(
        oldStatus: 'placed',
        newStatus: 'accepted',
        order: sampleCustomerOrder,
      );

      expect(payload, isNotNull);
      expect(payload!['notification']['title'], equals('✅ Order Accepted'));
      expect(payload['notification']['body'], equals('Your order from Rajat Shop has been accepted.'));
      expect(payload['data']['type'], equals('order_accepted'));
      expect(payload['data']['orderId'], equals('YB-2026-08-200'));
      expect(payload['data']['recipientRole'], equals('customer'));
    });

    test('2. Rejection Before Acceptance (placed -> rejected): Customer receives Order Not Accepted with reason', () {
      final payload = CustomerNotificationTargetingLogic.buildCustomerLifecyclePayload(
        oldStatus: 'placed',
        newStatus: 'rejected',
        order: sampleCustomerOrder,
        rejectionReason: 'Items out of stock',
      );

      expect(payload, isNotNull);
      expect(payload!['notification']['title'], equals('❌ Order Not Accepted'));
      expect(payload['notification']['body'], equals('Your order from Rajat Shop could not be accepted (Items out of stock).'));
      expect(payload['data']['type'], equals('order_rejected'));
      expect(payload['data']['recipientRole'], equals('customer'));
    });

    test('3. Auto-Rejection / Acceptance Timeout (placed -> delivery_expired): Customer receives Order Expired notification', () {
      final payload = CustomerNotificationTargetingLogic.buildCustomerLifecyclePayload(
        oldStatus: 'placed',
        newStatus: 'delivery_expired',
        order: sampleCustomerOrder,
      );

      expect(payload, isNotNull);
      expect(payload!['notification']['title'], equals('⌛ Order Expired'));
      expect(payload['notification']['body'], equals('Your order from Rajat Shop was not accepted in time.'));
      expect(payload['data']['type'], equals('order_expired'));
    });

    test('4. Rejection After Acceptance (accepted -> rejected): Customer receives Order Update notification', () {
      final payload = CustomerNotificationTargetingLogic.buildCustomerLifecyclePayload(
        oldStatus: 'accepted',
        newStatus: 'rejected',
        order: sampleCustomerOrder,
        rejectionReason: 'Kitchen equipment breakdown',
      );

      expect(payload, isNotNull);
      expect(payload!['notification']['title'], equals('❌ Order Update'));
      expect(payload['notification']['body'], equals('Your order from Rajat Shop could not be completed (Kitchen equipment breakdown).'));
      expect(payload['data']['type'], equals('order_rejected'));
    });

    test('5. Delivered (accepted -> delivered): Customer receives Order Delivered notification', () {
      final payload = CustomerNotificationTargetingLogic.buildCustomerLifecyclePayload(
        oldStatus: 'accepted',
        newStatus: 'delivered',
        order: sampleCustomerOrder,
      );

      expect(payload, isNotNull);
      expect(payload!['notification']['title'], equals('🎉 Order Delivered'));
      expect(payload['notification']['body'], equals('Your order from Rajat Shop has been delivered successfully.'));
      expect(payload['data']['type'], equals('order_delivered'));
    });

    test('6. Delivery Expiry (accepted -> delivery_expired): Customer receives Order Update (expired) notification', () {
      final payload = CustomerNotificationTargetingLogic.buildCustomerLifecyclePayload(
        oldStatus: 'accepted',
        newStatus: 'delivery_expired',
        order: sampleCustomerOrder,
      );

      expect(payload, isNotNull);
      expect(payload!['notification']['title'], equals('⚠️ Order Update'));
      expect(payload['notification']['body'], equals('Your order from Rajat Shop has expired.'));
      expect(payload['data']['type'], equals('order_expired'));
    });

    test('7. Pre-Accept Deletion / Cancelled: Produces zero customer push notification', () {
      final isNotifiable = CustomerNotificationTargetingLogic.isNotifiableTransition('placed', 'cancelled');
      expect(isNotifiable, isFalse);

      final payload = CustomerNotificationTargetingLogic.buildCustomerLifecyclePayload(
        oldStatus: 'placed',
        newStatus: 'cancelled',
        order: sampleCustomerOrder,
      );
      expect(payload, isNull);
    });

    test('8. Wrong Recipient Isolation: Only Customer A receives Customer A order notifications', () {
      final targetTokens = CustomerNotificationTargetingLogic.resolveCustomerTargetTokens(
        customerId: 'cust_9876543210',
        customerPhone: '9876543210',
        registeredTokens: mockDeviceTokens,
      );

      // Must strictly contain Customer A's 3 devices
      expect(targetTokens.length, equals(3));
      expect(targetTokens, contains('fcm_token_customer_a_phone1'));
      expect(targetTokens, contains('fcm_token_customer_a_tablet2'));
      expect(targetTokens, contains('fcm_token_customer_a_phone3'));

      // Must strictly exclude Customer B, Shopkeeper, and Admin
      expect(targetTokens.contains('fcm_token_customer_b'), isFalse);
      expect(targetTokens.contains('fcm_token_shopkeeper_rajat'), isFalse);
      expect(targetTokens.contains('fcm_token_admin'), isFalse);
    });

    test('9. Multi-Device Customer Support: All valid registered devices for Customer A are targeted', () {
      final targetTokens = CustomerNotificationTargetingLogic.resolveCustomerTargetTokens(
        customerId: 'cust_9876543210',
        customerPhone: '9876543210',
        registeredTokens: mockDeviceTokens,
      );

      expect(targetTokens, equals([
        'fcm_token_customer_a_phone1',
        'fcm_token_customer_a_tablet2',
        'fcm_token_customer_a_phone3',
      ]));
    });

    test('10. Duplicate Transition / Idempotency: Processing same token list does not create duplicate targets', () {
      final duplicateList = [
        ...mockDeviceTokens,
        ...mockDeviceTokens,
      ];

      final targetTokens = CustomerNotificationTargetingLogic.resolveCustomerTargetTokens(
        customerId: 'cust_9876543210',
        customerPhone: '9876543210',
        registeredTokens: duplicateList,
      );

      expect(targetTokens.length, equals(3));
      expect(targetTokens.toSet().length, equals(3));
    });

    test('11. Unrelated Update: Unchanged status or metadata edits produce NO notification', () {
      expect(CustomerNotificationTargetingLogic.isNotifiableTransition('accepted', 'accepted'), isFalse);
      expect(CustomerNotificationTargetingLogic.isNotifiableTransition('placed', 'placed'), isFalse);
      expect(CustomerNotificationTargetingLogic.isNotifiableTransition('delivered', 'delivered'), isFalse);

      final payload = CustomerNotificationTargetingLogic.buildCustomerLifecyclePayload(
        oldStatus: 'accepted',
        newStatus: 'accepted',
        order: sampleCustomerOrder,
      );
      expect(payload, isNull);
    });

    test('12. Empty Customer Credentials Safety: Returns empty token list safely without errors', () {
      final targetTokens = CustomerNotificationTargetingLogic.resolveCustomerTargetTokens(
        customerId: null,
        customerPhone: null,
        registeredTokens: mockDeviceTokens,
      );

      expect(targetTokens, isEmpty);
    });
  });
}
