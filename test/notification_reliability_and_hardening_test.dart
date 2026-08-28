// BU Gate2Eat — Tests
// Unit & Integration Tests for Part 7: Notification Reliability, Multi-Device & Edge-Case Hardening

import 'package:bugate2eat_app/models/order_model.dart';
import 'package:bugate2eat_app/services/customer_notification_dispatcher.dart';
import 'package:bugate2eat_app/services/notification_service.dart';
import 'package:bugate2eat_app/services/shopkeeper_notification_dispatcher.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Part 7: Notification Reliability, Multi-Device & Edge-Case Hardening Suite', () {
    final sampleOrder = AppOrder(
      orderId: 'YB-2026-08-300',
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
          quantity: 2,
        ),
      ],
      totalAmount: 240,
      status: 'placed',
      deliveryNote: 'Gate 3',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    // ─── 1. MULTI-DEVICE TARGETING TESTS ────────────────────────────────────
    test('1. Multi-Device Customer: All 3 active customer devices receive push', () {
      final mockTokens = <Map<String, dynamic>>[
        {'token': 'cust_token_phone1', 'role': 'customer', 'customerId': 'cust_9876543210', 'phone': '9876543210'},
        {'token': 'cust_token_phone2', 'role': 'customer', 'customerId': 'cust_9876543210', 'phone': '9876543210'},
        {'token': 'cust_token_tablet3', 'role': 'customer', 'customerId': 'cust_9876543210', 'phone': '9876543210'},
        {'token': 'cust_token_other', 'role': 'customer', 'customerId': 'cust_different', 'phone': '9999911111'},
      ];

      final targets = CustomerNotificationTargetingLogic.resolveCustomerTargetTokens(
        customerId: 'cust_9876543210',
        customerPhone: '9876543210',
        registeredTokens: mockTokens,
      );

      expect(targets.length, equals(3));
      expect(targets, contains('cust_token_phone1'));
      expect(targets, contains('cust_token_phone2'));
      expect(targets, contains('cust_token_tablet3'));
      expect(targets.contains('cust_token_other'), isFalse);
    });

    test('2. Multi-Device Shopkeeper: All 3 active shopkeeper devices for rajat_shop receive push', () {
      final mockTokens = <Map<String, dynamic>>[
        {'token': 'shop_token_phone1', 'role': 'shopkeeper', 'shopId': 'rajat_shop', 'phone': '8000383993'},
        {'token': 'shop_token_pos_tab', 'role': 'shopkeeper', 'shopId': 'rajat_shop', 'phone': '8000383993'},
        {'token': 'shop_token_phone2', 'role': 'shopkeeper', 'shopId': 'rajat_shop', 'phone': '8000383993'},
        {'token': 'shop_token_nayan', 'role': 'shopkeeper', 'shopId': 'nayan_shop', 'phone': '8295643910'},
      ];

      final targets = ShopkeeperNotificationTargetingLogic.resolveTargetTokens(
        targetShopId: 'rajat_shop',
        registeredTokens: mockTokens,
      );

      expect(targets.length, equals(3));
      expect(targets, contains('shop_token_phone1'));
      expect(targets, contains('shop_token_pos_tab'));
      expect(targets, contains('shop_token_phone2'));
      expect(targets.contains('shop_token_nayan'), isFalse);
    });

    // ─── 2. RECIPIENT & ROLE ISOLATION TESTS ────────────────────────────────
    test('3. Strict Cross-Shop & Role Isolation: Customer and Admin never targeted for shopkeeper pushes', () {
      final mixedTokens = <Map<String, dynamic>>[
        {'token': 'cust_token_1', 'role': 'customer', 'shopId': 'rajat_shop', 'phone': '9876543210'},
        {'token': 'admin_token_1', 'role': 'admin', 'shopId': null, 'phone': '8078643910'},
        {'token': 'shop_token_rajat', 'role': 'shopkeeper', 'shopId': 'rajat_shop', 'phone': '8000383993'},
      ];

      final targets = ShopkeeperNotificationTargetingLogic.resolveTargetTokens(
        targetShopId: 'rajat_shop',
        registeredTokens: mixedTokens,
      );

      expect(targets.length, equals(1));
      expect(targets.first, equals('shop_token_rajat'));
    });

    test('4. Cross-Customer Isolation: Customer B never receives Customer A notifications', () {
      final mixedTokens = <Map<String, dynamic>>[
        {'token': 'cust_a_token', 'role': 'customer', 'customerId': 'cust_A', 'phone': '9876543210'},
        {'token': 'cust_b_token', 'role': 'customer', 'customerId': 'cust_B', 'phone': '9123456789'},
      ];

      final targets = CustomerNotificationTargetingLogic.resolveCustomerTargetTokens(
        customerId: 'cust_A',
        customerPhone: '9876543210',
        registeredTokens: mixedTokens,
      );

      expect(targets.length, equals(1));
      expect(targets.first, equals('cust_a_token'));
      expect(targets.contains('cust_b_token'), isFalse);
    });

    // ─── 3. PARTIAL FAILURE & STALE TOKEN RESILIENCE ────────────────────────
    test('5. Stale / Empty Token Safety: Empty or malformed token strings are skipped cleanly', () {
      final mixedTokens = <Map<String, dynamic>>[
        {'token': '', 'role': 'customer', 'customerId': 'cust_A', 'phone': '9876543210'},
        {'token': null, 'role': 'customer', 'customerId': 'cust_A', 'phone': '9876543210'},
        {'token': 'valid_token_A', 'role': 'customer', 'customerId': 'cust_A', 'phone': '9876543210'},
      ];

      final targets = CustomerNotificationTargetingLogic.resolveCustomerTargetTokens(
        customerId: 'cust_A',
        customerPhone: '9876543210',
        registeredTokens: mixedTokens,
      );

      expect(targets.length, equals(1));
      expect(targets.first, equals('valid_token_A'));
    });

    test('6. Partial Delivery Resilience: Valid token list resolves even when duplicate entries exist', () {
      final duplicateTokens = <Map<String, dynamic>>[
        {'token': 'valid_token_1', 'role': 'shopkeeper', 'shopId': 'rajat_shop'},
        {'token': 'valid_token_1', 'role': 'shopkeeper', 'shopId': 'rajat_shop'}, // Duplicate
        {'token': 'valid_token_2', 'role': 'shopkeeper', 'shopId': 'rajat_shop'},
      ];

      final targets = ShopkeeperNotificationTargetingLogic.resolveTargetTokens(
        targetShopId: 'rajat_shop',
        registeredTokens: duplicateTokens,
      );

      expect(targets.length, equals(2));
      expect(targets, contains('valid_token_1'));
      expect(targets, contains('valid_token_2'));
    });

    // ─── 4. IDEMPOTENCY & STATUS UPDATE GATES ───────────────────────────────
    test('7. Unchanged Status Idempotency: Metadata or heartbeat update produces zero notifications', () {
      expect(CustomerNotificationTargetingLogic.isNotifiableTransition('placed', 'placed'), isFalse);
      expect(CustomerNotificationTargetingLogic.isNotifiableTransition('accepted', 'accepted'), isFalse);
      expect(CustomerNotificationTargetingLogic.isNotifiableTransition('delivered', 'delivered'), isFalse);

      final payload = CustomerNotificationTargetingLogic.buildCustomerLifecyclePayload(
        oldStatus: 'accepted',
        newStatus: 'accepted',
        order: sampleOrder,
      );
      expect(payload, isNull);
    });

    test('8. Valid Transition Idempotency: Same transition generates deterministic payload structure', () {
      final payload1 = CustomerNotificationTargetingLogic.buildCustomerLifecyclePayload(
        oldStatus: 'placed',
        newStatus: 'accepted',
        order: sampleOrder,
      );
      final payload2 = CustomerNotificationTargetingLogic.buildCustomerLifecyclePayload(
        oldStatus: 'placed',
        newStatus: 'accepted',
        order: sampleOrder,
      );

      expect(payload1, isNotNull);
      expect(payload2, isNotNull);
      expect(payload1!['data']['type'], equals(payload2!['data']['type']));
      expect(payload1['data']['orderId'], equals(payload2['data']['orderId']));
      expect(payload1['notification']['title'], equals(payload2['notification']['title']));
    });

    // ─── 5. ORDER STATE INDEPENDENCE ────────────────────────────────────────
    test('9. Order State Independence: Payload construction does not mutate original order object', () {
      final originalStatus = sampleOrder.status;
      final originalTotal = sampleOrder.totalAmount;

      CustomerNotificationTargetingLogic.buildCustomerLifecyclePayload(
        oldStatus: 'placed',
        newStatus: 'accepted',
        order: sampleOrder,
      );

      expect(sampleOrder.status, equals(originalStatus));
      expect(sampleOrder.totalAmount, equals(originalTotal));
    });

    // ─── 6. TOKEN MASKING & LOGGING SAFETY ──────────────────────────────────
    test('10. Safe Token Masking: maskToken hides sensitive characters for safe logging', () {
      expect(NotificationService.maskToken(null), equals('<null>'));
      expect(NotificationService.maskToken(''), equals('<null>'));
      expect(NotificationService.maskToken('short123'), equals('***'));
      final longToken = 'fcm_token_abcdef1234567890_xyz';
      final masked = NotificationService.maskToken(longToken);
      expect(masked.contains('...'), isTrue);
      expect(masked.startsWith('fcm_to'), isTrue);
      expect(masked.endsWith('(30 chars)'), isTrue);
    });
  });
}
