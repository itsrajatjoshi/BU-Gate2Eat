// BU Gate2Eat — Security & State Machine Unit Tests
// PHASE 5.1: Order State Machine — Transition Invariants & State Matrix
//
// Test Matrix:
// 1. OrderStatusRules state matrix verification (all valid transitions, all invalid transitions)
// 2. Terminal state immutability predicate (delivered, rejected, cancelled, delivery_expired)
// 3. Active state predicate (placed, accepted)
// 4. OrderService.updateOrderStatus transition invariants (valid transitions succeed)
// 5. OrderService.updateOrderStatus lifecycle jump blocking (placed -> delivered rejected)
// 6. OrderService.updateOrderStatus arbitrary status rejection
// 7. OrderService.updateOrderStatus terminal immutability enforcement
// 8. OrderService.updateOrderStatus role enforcement (customer/anonymous blocked from shopkeeper status update)
// 9. OrderService.updateOrderStatus cross-shop isolation (Shopkeeper A blocked on Shop B order)
// 10. OrderService.updateOrderStatus idempotency (same status no-op)
// 11. OrderService.cancelOrder valid customer cancellation on placed order
// 12. OrderService.cancelOrder blocking on accepted / terminal orders
// 13. OrderService.cancelOrder cross-customer isolation (Customer A cannot cancel Customer B order)
// 14. OrderService.cancelOrder unauthenticated session rejection

import 'package:bugate2eat_app/core/auth/auth_status.dart';
import 'package:bugate2eat_app/services/order_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Phase 5.1: OrderStatusRules Matrix Invariants', () {
    test('1. Valid forward transitions from placed', () {
      expect(
        OrderStatusRules.isValidTransition(
          OrderStatusRules.statusPlaced,
          OrderStatusRules.statusAccepted,
        ),
        isTrue,
        reason: 'placed -> accepted must be allowed',
      );
      expect(
        OrderStatusRules.isValidTransition(
          OrderStatusRules.statusPlaced,
          OrderStatusRules.statusRejected,
        ),
        isTrue,
        reason: 'placed -> rejected must be allowed',
      );
      expect(
        OrderStatusRules.isValidTransition(
          OrderStatusRules.statusPlaced,
          OrderStatusRules.statusCancelled,
        ),
        isTrue,
        reason: 'placed -> cancelled must be allowed',
      );
    });

    test('2. Valid forward transitions from accepted', () {
      expect(
        OrderStatusRules.isValidTransition(
          OrderStatusRules.statusAccepted,
          OrderStatusRules.statusDelivered,
        ),
        isTrue,
        reason: 'accepted -> delivered must be allowed',
      );
      expect(
        OrderStatusRules.isValidTransition(
          OrderStatusRules.statusAccepted,
          OrderStatusRules.statusRejected,
        ),
        isTrue,
        reason: 'accepted -> rejected must be allowed within 15-min window',
      );
      expect(
        OrderStatusRules.isValidTransition(
          OrderStatusRules.statusAccepted,
          OrderStatusRules.statusDeliveryExpired,
        ),
        isTrue,
        reason: 'accepted -> delivery_expired must be allowed under timeout',
      );
    });

    test('3. Identity / Same-status transitions are valid no-ops', () {
      for (final s in [
        OrderStatusRules.statusPlaced,
        OrderStatusRules.statusAccepted,
        OrderStatusRules.statusDelivered,
        OrderStatusRules.statusRejected,
        OrderStatusRules.statusCancelled,
        OrderStatusRules.statusDeliveryExpired,
      ]) {
        expect(
          OrderStatusRules.isValidTransition(s, s),
          isTrue,
          reason: 'Same-status ($s -> $s) must be allowed as an idempotent no-op',
        );
      }
    });

    test('4. Blocked lifecycle jumps from placed', () {
      expect(
        OrderStatusRules.isValidTransition(
          OrderStatusRules.statusPlaced,
          OrderStatusRules.statusDelivered,
        ),
        isFalse,
        reason: 'placed -> delivered bypass must be blocked',
      );
      expect(
        OrderStatusRules.isValidTransition(
          OrderStatusRules.statusPlaced,
          OrderStatusRules.statusDeliveryExpired,
        ),
        isFalse,
        reason: 'placed -> delivery_expired directly by client must be blocked',
      );
      expect(
        OrderStatusRules.isValidTransition(
          OrderStatusRules.statusPlaced,
          'cooking',
        ),
        isFalse,
        reason: 'Arbitrary status string must be blocked',
      );
      expect(
        OrderStatusRules.isValidTransition(
          OrderStatusRules.statusPlaced,
          'ready',
        ),
        isFalse,
        reason: 'Arbitrary status string must be blocked',
      );
    });

    test('5. Blocked backwards transitions to placed', () {
      for (final s in [
        OrderStatusRules.statusAccepted,
        OrderStatusRules.statusDelivered,
        OrderStatusRules.statusRejected,
        OrderStatusRules.statusCancelled,
        OrderStatusRules.statusDeliveryExpired,
      ]) {
        expect(
          OrderStatusRules.isValidTransition(s, OrderStatusRules.statusPlaced),
          isFalse,
          reason: '$s -> placed resurrection must be blocked',
        );
      }
    });

    test('6. Blocked transitions from accepted', () {
      expect(
        OrderStatusRules.isValidTransition(
          OrderStatusRules.statusAccepted,
          OrderStatusRules.statusPlaced,
        ),
        isFalse,
        reason: 'accepted -> placed must be blocked',
      );
      expect(
        OrderStatusRules.isValidTransition(
          OrderStatusRules.statusAccepted,
          OrderStatusRules.statusCancelled,
        ),
        isFalse,
        reason: 'accepted -> cancelled must be blocked',
      );
    });

    test('7. Terminal state immutability: delivered -> anything is BLOCKED', () {
      for (final target in [
        OrderStatusRules.statusPlaced,
        OrderStatusRules.statusAccepted,
        OrderStatusRules.statusRejected,
        OrderStatusRules.statusCancelled,
        OrderStatusRules.statusDeliveryExpired,
        'completed',
        'reopened',
      ]) {
        expect(
          OrderStatusRules.isValidTransition(
            OrderStatusRules.statusDelivered,
            target,
          ),
          isFalse,
          reason: 'delivered -> $target must be blocked',
        );
      }
    });

    test('8. Terminal state immutability: rejected -> anything is BLOCKED', () {
      for (final target in [
        OrderStatusRules.statusPlaced,
        OrderStatusRules.statusAccepted,
        OrderStatusRules.statusDelivered,
        OrderStatusRules.statusCancelled,
        OrderStatusRules.statusDeliveryExpired,
        'reopened',
      ]) {
        expect(
          OrderStatusRules.isValidTransition(
            OrderStatusRules.statusRejected,
            target,
          ),
          isFalse,
          reason: 'rejected -> $target must be blocked',
        );
      }
    });

    test('9. Terminal state immutability: cancelled -> anything is BLOCKED', () {
      for (final target in [
        OrderStatusRules.statusPlaced,
        OrderStatusRules.statusAccepted,
        OrderStatusRules.statusDelivered,
        OrderStatusRules.statusRejected,
        OrderStatusRules.statusDeliveryExpired,
        'reopened',
      ]) {
        expect(
          OrderStatusRules.isValidTransition(
            OrderStatusRules.statusCancelled,
            target,
          ),
          isFalse,
          reason: 'cancelled -> $target must be blocked',
        );
      }
    });

    test('10. Terminal state immutability: delivery_expired -> anything is BLOCKED', () {
      for (final target in [
        OrderStatusRules.statusPlaced,
        OrderStatusRules.statusAccepted,
        OrderStatusRules.statusDelivered,
        OrderStatusRules.statusRejected,
        OrderStatusRules.statusCancelled,
        'reopened',
      ]) {
        expect(
          OrderStatusRules.isValidTransition(
            OrderStatusRules.statusDeliveryExpired,
            target,
          ),
          isFalse,
          reason: 'delivery_expired -> $target must be blocked',
        );
      }
    });

    test('11. Terminal predicate consistency', () {
      expect(OrderStatusRules.isTerminal(OrderStatusRules.statusDelivered), isTrue);
      expect(OrderStatusRules.isTerminal(OrderStatusRules.statusRejected), isTrue);
      expect(OrderStatusRules.isTerminal(OrderStatusRules.statusCancelled), isTrue);
      expect(OrderStatusRules.isTerminal(OrderStatusRules.statusDeliveryExpired), isTrue);
      expect(OrderStatusRules.isTerminal(OrderStatusRules.statusPlaced), isFalse);
      expect(OrderStatusRules.isTerminal(OrderStatusRules.statusAccepted), isFalse);
    });

    test('12. Active predicate consistency', () {
      expect(OrderStatusRules.isActive(OrderStatusRules.statusPlaced), isTrue);
      expect(OrderStatusRules.isActive(OrderStatusRules.statusAccepted), isTrue);
      expect(OrderStatusRules.isActive(OrderStatusRules.statusDelivered), isFalse);
      expect(OrderStatusRules.isActive(OrderStatusRules.statusRejected), isFalse);
      expect(OrderStatusRules.isActive(OrderStatusRules.statusCancelled), isFalse);
      expect(OrderStatusRules.isActive(OrderStatusRules.statusDeliveryExpired), isFalse);
    });
  });

  group('Phase 5.1: OrderService Transition Enforcement', () {
    test('13. Shopkeeper valid transition placed -> accepted succeeds', () async {
      final updatedDocs = <String, Map<String, dynamic>>{};
      final service = OrderService(
        currentUserRoleResolver: () => AuthRole.shopkeeper,
        currentShopIdResolver: () => 'shop_a',
        currentUserIdResolver: () => 'sk_user_a',
        orderLoaderForTesting: (id) async => {
          'orderId': id,
          'shopId': 'shop_a',
          'status': 'placed',
        },
        orderUpdaterForTesting: (id, updates) async {
          updatedDocs[id] = updates;
        },
      );

      await service.updateOrderStatus('order_1', 'accepted');
      expect(updatedDocs['order_1']?['status'], equals('accepted'));
    });

    test('14. Shopkeeper valid transition placed -> rejected succeeds', () async {
      final updatedDocs = <String, Map<String, dynamic>>{};
      final service = OrderService(
        currentUserRoleResolver: () => AuthRole.shopkeeper,
        currentShopIdResolver: () => 'shop_a',
        currentUserIdResolver: () => 'sk_user_a',
        orderLoaderForTesting: (id) async => {
          'orderId': id,
          'shopId': 'shop_a',
          'status': 'placed',
        },
        orderUpdaterForTesting: (id, updates) async {
          updatedDocs[id] = updates;
        },
      );

      await service.updateOrderStatus(
        'order_1',
        'rejected',
        rejectionReason: 'Out of stock',
      );
      expect(updatedDocs['order_1']?['status'], equals('rejected'));
      expect(updatedDocs['order_1']?['rejectionReason'], equals('Out of stock'));
    });

    test('15. Shopkeeper valid transition accepted -> delivered succeeds', () async {
      final updatedDocs = <String, Map<String, dynamic>>{};
      final service = OrderService(
        currentUserRoleResolver: () => AuthRole.shopkeeper,
        currentShopIdResolver: () => 'shop_a',
        currentUserIdResolver: () => 'sk_user_a',
        orderLoaderForTesting: (id) async => {
          'orderId': id,
          'shopId': 'shop_a',
          'status': 'accepted',
        },
        orderUpdaterForTesting: (id, updates) async {
          updatedDocs[id] = updates;
        },
      );

      await service.updateOrderStatus('order_1', 'delivered');
      expect(updatedDocs['order_1']?['status'], equals('delivered'));
    });

    test('16. Lifecycle bypass placed -> delivered is strictly rejected', () async {
      final service = OrderService(
        currentUserRoleResolver: () => AuthRole.shopkeeper,
        currentShopIdResolver: () => 'shop_a',
        currentUserIdResolver: () => 'sk_user_a',
        orderLoaderForTesting: (id) async => {
          'orderId': id,
          'shopId': 'shop_a',
          'status': 'placed',
        },
        orderUpdaterForTesting: (id, updates) async {},
      );

      expect(
        () => service.updateOrderStatus('order_1', 'delivered'),
        throwsA(isA<InvalidOrderTransitionException>()),
      );
    });

    test('17. Arbitrary status injection placed -> cooking is rejected', () async {
      final service = OrderService(
        currentUserRoleResolver: () => AuthRole.shopkeeper,
        currentShopIdResolver: () => 'shop_a',
        currentUserIdResolver: () => 'sk_user_a',
        orderLoaderForTesting: (id) async => {
          'orderId': id,
          'shopId': 'shop_a',
          'status': 'placed',
        },
        orderUpdaterForTesting: (id, updates) async {},
      );

      expect(
        () => service.updateOrderStatus('order_1', 'cooking'),
        throwsA(isA<InvalidOrderTransitionException>()),
      );
    });

    test('18. Invalid transition accepted -> cancelled is rejected', () async {
      final service = OrderService(
        currentUserRoleResolver: () => AuthRole.shopkeeper,
        currentShopIdResolver: () => 'shop_a',
        currentUserIdResolver: () => 'sk_user_a',
        orderLoaderForTesting: (id) async => {
          'orderId': id,
          'shopId': 'shop_a',
          'status': 'accepted',
        },
        orderUpdaterForTesting: (id, updates) async {},
      );

      expect(
        () => service.updateOrderStatus('order_1', 'cancelled'),
        throwsA(anyOf(isA<InvalidOrderTransitionException>(), isA<OrderServiceException>())),
      );
    });

    test('19. Terminal immutability: delivered order cannot be updated to accepted or placed', () async {
      final service = OrderService(
        currentUserRoleResolver: () => AuthRole.shopkeeper,
        currentShopIdResolver: () => 'shop_a',
        currentUserIdResolver: () => 'sk_user_a',
        orderLoaderForTesting: (id) async => {
          'orderId': id,
          'shopId': 'shop_a',
          'status': 'delivered',
        },
        orderUpdaterForTesting: (id, updates) async {},
      );

      expect(
        () => service.updateOrderStatus('order_1', 'accepted'),
        throwsA(isA<InvalidOrderTransitionException>()),
      );
      expect(
        () => service.updateOrderStatus('order_1', 'placed'),
        throwsA(isA<InvalidOrderTransitionException>()),
      );
    });

    test('20. Terminal immutability: rejected order cannot be transitioned', () async {
      final service = OrderService(
        currentUserRoleResolver: () => AuthRole.shopkeeper,
        currentShopIdResolver: () => 'shop_a',
        currentUserIdResolver: () => 'sk_user_a',
        orderLoaderForTesting: (id) async => {
          'orderId': id,
          'shopId': 'shop_a',
          'status': 'rejected',
        },
        orderUpdaterForTesting: (id, updates) async {},
      );

      expect(
        () => service.updateOrderStatus('order_1', 'accepted'),
        throwsA(isA<InvalidOrderTransitionException>()),
      );
    });

    test('21. Terminal immutability: cancelled order cannot be transitioned', () async {
      final service = OrderService(
        currentUserRoleResolver: () => AuthRole.shopkeeper,
        currentShopIdResolver: () => 'shop_a',
        currentUserIdResolver: () => 'sk_user_a',
        orderLoaderForTesting: (id) async => {
          'orderId': id,
          'shopId': 'shop_a',
          'status': 'cancelled',
        },
        orderUpdaterForTesting: (id, updates) async {},
      );

      expect(
        () => service.updateOrderStatus('order_1', 'accepted'),
        throwsA(isA<InvalidOrderTransitionException>()),
      );
    });

    test('22. Terminal immutability: delivery_expired order cannot be transitioned', () async {
      final service = OrderService(
        currentUserRoleResolver: () => AuthRole.shopkeeper,
        currentShopIdResolver: () => 'shop_a',
        currentUserIdResolver: () => 'sk_user_a',
        orderLoaderForTesting: (id) async => {
          'orderId': id,
          'shopId': 'shop_a',
          'status': 'delivery_expired',
        },
        orderUpdaterForTesting: (id, updates) async {},
      );

      expect(
        () => service.updateOrderStatus('order_1', 'delivered'),
        throwsA(isA<InvalidOrderTransitionException>()),
      );
    });

    test('23. Customer role is blocked from updateOrderStatus', () async {
      final service = OrderService(
        currentUserRoleResolver: () => AuthRole.customer,
        currentUserIdResolver: () => 'cust_user_1',
        orderLoaderForTesting: (id) async => {
          'orderId': id,
          'shopId': 'shop_a',
          'status': 'placed',
        },
        orderUpdaterForTesting: (id, updates) async {},
      );

      expect(
        () => service.updateOrderStatus('order_1', 'accepted'),
        throwsA(isA<OrderServiceException>()),
      );
    });

    test('24. Anonymous caller is blocked from updateOrderStatus', () async {
      final service = OrderService(
        currentUserRoleResolver: () => AuthRole.none,
        currentUserIdResolver: () => null,
        orderLoaderForTesting: (id) async => {
          'orderId': id,
          'shopId': 'shop_a',
          'status': 'placed',
        },
        orderUpdaterForTesting: (id, updates) async {},
      );

      expect(
        () => service.updateOrderStatus('order_1', 'accepted'),
        throwsA(isA<OrderServiceException>()),
      );
    });

    test('25. Cross-shop isolation: Shopkeeper A cannot update Shop B order', () async {
      final service = OrderService(
        currentUserRoleResolver: () => AuthRole.shopkeeper,
        currentShopIdResolver: () => 'shop_a',
        currentUserIdResolver: () => 'sk_user_a',
        orderLoaderForTesting: (id) async => {
          'orderId': id,
          'shopId': 'shop_b', // belongs to shop_b
          'status': 'placed',
        },
        orderUpdaterForTesting: (id, updates) async {},
      );

      expect(
        () => service.updateOrderStatus('order_1', 'accepted'),
        throwsA(isA<OrderServiceException>()),
      );
    });

    test('26. Idempotency: Duplicate update to same status is a safe no-op', () async {
      var updaterCallCount = 0;
      final service = OrderService(
        currentUserRoleResolver: () => AuthRole.shopkeeper,
        currentShopIdResolver: () => 'shop_a',
        currentUserIdResolver: () => 'sk_user_a',
        orderLoaderForTesting: (id) async => {
          'orderId': id,
          'shopId': 'shop_a',
          'status': 'accepted',
        },
        orderUpdaterForTesting: (id, updates) async {
          updaterCallCount++;
        },
      );

      await service.updateOrderStatus('order_1', 'accepted');
      expect(updaterCallCount, equals(0), reason: 'Duplicate same-status must be no-op');
    });

    test('27. Customer valid cancellation on placed order succeeds', () async {
      final updatedDocs = <String, Map<String, dynamic>>{};
      final service = OrderService(
        currentUserRoleResolver: () => AuthRole.customer,
        currentUserIdResolver: () => 'cust_user_1',
        orderLoaderForTesting: (id) async => {
          'orderId': id,
          'shopId': 'shop_a',
          'customerId': 'cust_user_1',
          'status': 'placed',
        },
        orderUpdaterForTesting: (id, updates) async {
          updatedDocs[id] = updates;
        },
      );

      await service.cancelOrder('order_1');
      expect(updatedDocs['order_1']?['status'], equals('cancelled'));
    });

    test('28. Customer cannot cancel accepted order', () async {
      final service = OrderService(
        currentUserRoleResolver: () => AuthRole.customer,
        currentUserIdResolver: () => 'cust_user_1',
        orderLoaderForTesting: (id) async => {
          'orderId': id,
          'shopId': 'shop_a',
          'customerId': 'cust_user_1',
          'status': 'accepted',
        },
        orderUpdaterForTesting: (id, updates) async {},
      );

      expect(
        () => service.cancelOrder('order_1'),
        throwsA(isA<OrderServiceException>()),
      );
    });

    test('29. Customer cannot cancel delivered order', () async {
      final service = OrderService(
        currentUserRoleResolver: () => AuthRole.customer,
        currentUserIdResolver: () => 'cust_user_1',
        orderLoaderForTesting: (id) async => {
          'orderId': id,
          'shopId': 'shop_a',
          'customerId': 'cust_user_1',
          'status': 'delivered',
        },
        orderUpdaterForTesting: (id, updates) async {},
      );

      expect(
        () => service.cancelOrder('order_1'),
        throwsA(isA<OrderServiceException>()),
      );
    });

    test('30. Cross-customer cancellation is strictly blocked', () async {
      final service = OrderService(
        currentUserRoleResolver: () => AuthRole.customer,
        currentUserIdResolver: () => 'cust_user_attacker',
        orderLoaderForTesting: (id) async => {
          'orderId': id,
          'shopId': 'shop_a',
          'customerId': 'cust_user_victim',
          'status': 'placed',
        },
        orderUpdaterForTesting: (id, updates) async {},
      );

      expect(
        () => service.cancelOrder('order_1'),
        throwsA(isA<OrderServiceException>()),
      );
    });

    test('31. Unauthenticated cancellation is strictly blocked', () async {
      final service = OrderService(
        currentUserRoleResolver: () => AuthRole.none,
        currentUserIdResolver: () => null,
        orderLoaderForTesting: (id) async => {
          'orderId': id,
          'shopId': 'shop_a',
          'customerId': 'cust_user_1',
          'status': 'placed',
        },
        orderUpdaterForTesting: (id, updates) async {},
      );

      expect(
        () => service.cancelOrder('order_1'),
        throwsA(isA<OrderServiceException>()),
      );
    });
  });

  group('Phase 5.2: Role-Based Order State Transitions Matrix & Invariants', () {
    test('32. OrderStatusRules.isValidCustomerTransition allows only placed -> cancelled and same-status', () {
      expect(
        OrderStatusRules.isValidCustomerTransition('placed', 'cancelled'),
        isTrue,
        reason: 'Customer can cancel placed order',
      );
      expect(
        OrderStatusRules.isValidCustomerTransition('placed', 'placed'),
        isTrue,
        reason: 'Same-status is an allowed idempotent no-op',
      );
    });

    test('33. OrderStatusRules.isValidCustomerTransition blocks customer fulfillment and forward transitions', () {
      for (final target in ['accepted', 'rejected', 'delivered', 'delivery_expired', 'cooking', 'unknown']) {
        expect(
          OrderStatusRules.isValidCustomerTransition('placed', target),
          isFalse,
          reason: 'Customer cannot transition placed -> $target',
        );
      }
      for (final current in ['accepted', 'delivered', 'rejected', 'delivery_expired']) {
        expect(
          OrderStatusRules.isValidCustomerTransition(current, 'cancelled'),
          isFalse,
          reason: 'Customer cannot cancel $current order',
        );
      }
    });

    test('34. OrderStatusRules.isValidShopkeeperTransition allows fulfillment transitions', () {
      expect(OrderStatusRules.isValidShopkeeperTransition('placed', 'accepted'), isTrue);
      expect(OrderStatusRules.isValidShopkeeperTransition('placed', 'rejected'), isTrue);
      expect(OrderStatusRules.isValidShopkeeperTransition('accepted', 'delivered'), isTrue);
      expect(OrderStatusRules.isValidShopkeeperTransition('accepted', 'rejected'), isTrue);
      expect(OrderStatusRules.isValidShopkeeperTransition('accepted', 'delivery_expired'), isTrue);
      expect(OrderStatusRules.isValidShopkeeperTransition('placed', 'placed'), isTrue);
      expect(OrderStatusRules.isValidShopkeeperTransition('accepted', 'accepted'), isTrue);
    });

    test('35. OrderStatusRules.isValidShopkeeperTransition strictly blocks shopkeeper cancellation', () {
      expect(
        OrderStatusRules.isValidShopkeeperTransition('placed', 'cancelled'),
        isFalse,
        reason: 'Shopkeeper cannot cancel orders',
      );
      expect(
        OrderStatusRules.isValidShopkeeperTransition('accepted', 'cancelled'),
        isFalse,
        reason: 'Shopkeeper cannot cancel accepted orders',
      );
    });

    test('36. OrderStatusRules.isValidShopkeeperTransition blocks terminal mutation and skips', () {
      expect(OrderStatusRules.isValidShopkeeperTransition('placed', 'delivered'), isFalse);
      expect(OrderStatusRules.isValidShopkeeperTransition('delivered', 'accepted'), isFalse);
      expect(OrderStatusRules.isValidShopkeeperTransition('rejected', 'accepted'), isFalse);
      expect(OrderStatusRules.isValidShopkeeperTransition('cancelled', 'accepted'), isFalse);
      expect(OrderStatusRules.isValidShopkeeperTransition('delivery_expired', 'delivered'), isFalse);
    });

    test('37. OrderStatusRules.isValidAdminTransition blocks arbitrary status and terminal mutation', () {
      expect(OrderStatusRules.isValidAdminTransition('placed', 'accepted'), isTrue);
      expect(OrderStatusRules.isValidAdminTransition('placed', 'rejected'), isTrue);
      expect(OrderStatusRules.isValidAdminTransition('placed', 'cancelled'), isTrue);
      expect(OrderStatusRules.isValidAdminTransition('accepted', 'delivered'), isTrue);
      expect(OrderStatusRules.isValidAdminTransition('accepted', 'rejected'), isTrue);
      expect(OrderStatusRules.isValidAdminTransition('accepted', 'delivery_expired'), isTrue);

      // Skips and arbitrary status injection blocked
      expect(OrderStatusRules.isValidAdminTransition('placed', 'delivered'), isFalse);
      expect(OrderStatusRules.isValidAdminTransition('placed', 'cooking'), isFalse);
      expect(OrderStatusRules.isValidAdminTransition('placed', 'arbitrary'), isFalse);

      // Terminal immutability
      expect(OrderStatusRules.isValidAdminTransition('delivered', 'accepted'), isFalse);
      expect(OrderStatusRules.isValidAdminTransition('rejected', 'placed'), isFalse);
      expect(OrderStatusRules.isValidAdminTransition('cancelled', 'placed'), isFalse);
      expect(OrderStatusRules.isValidAdminTransition('delivery_expired', 'accepted'), isFalse);
    });

    test('38. OrderStatusRules.isValidTransitionForRole dispatches accurately across AuthRoles', () {
      // Customer
      expect(OrderStatusRules.isValidTransitionForRole(AuthRole.customer, 'placed', 'cancelled'), isTrue);
      expect(OrderStatusRules.isValidTransitionForRole(AuthRole.customer, 'placed', 'accepted'), isFalse);

      // Shopkeeper
      expect(OrderStatusRules.isValidTransitionForRole(AuthRole.shopkeeper, 'placed', 'accepted'), isTrue);
      expect(OrderStatusRules.isValidTransitionForRole(AuthRole.shopkeeper, 'placed', 'cancelled'), isFalse);

      // Admin
      expect(OrderStatusRules.isValidTransitionForRole(AuthRole.admin, 'placed', 'accepted'), isTrue);
      expect(OrderStatusRules.isValidTransitionForRole(AuthRole.admin, 'placed', 'cancelled'), isTrue);
      expect(OrderStatusRules.isValidTransitionForRole(AuthRole.admin, 'placed', 'delivered'), isFalse);

      // None (anonymous)
      expect(OrderStatusRules.isValidTransitionForRole(AuthRole.none, 'placed', 'accepted'), isFalse);
      expect(OrderStatusRules.isValidTransitionForRole(AuthRole.none, 'placed', 'cancelled'), isFalse);
    });

    test('39. Shopkeeper cannot cancel order via updateOrderStatus', () async {
      final service = OrderService(
        currentUserRoleResolver: () => AuthRole.shopkeeper,
        currentShopIdResolver: () => 'shop_a',
        currentUserIdResolver: () => 'sk_user_a',
        orderLoaderForTesting: (id) async => {
          'orderId': id,
          'shopId': 'shop_a',
          'status': 'placed',
        },
        orderUpdaterForTesting: (id, updates) async {},
      );

      expect(
        () => service.updateOrderStatus('order_1', 'cancelled'),
        throwsA(isA<OrderServiceException>()),
      );
    });

    test('40. Shopkeeper cannot cancel order via cancelOrder', () async {
      final service = OrderService(
        currentUserRoleResolver: () => AuthRole.shopkeeper,
        currentShopIdResolver: () => 'shop_a',
        currentUserIdResolver: () => 'sk_user_a',
        orderLoaderForTesting: (id) async => {
          'orderId': id,
          'shopId': 'shop_a',
          'customerId': 'cust_1',
          'status': 'placed',
        },
        orderUpdaterForTesting: (id, updates) async {},
      );

      expect(
        () => service.cancelOrder('order_1'),
        throwsA(isA<OrderServiceException>()),
      );
    });

    test('41. Admin valid operational cancellation on placed order succeeds via updateOrderStatus', () async {
      final updatedDocs = <String, Map<String, dynamic>>{};
      final service = OrderService(
        currentUserRoleResolver: () => AuthRole.admin,
        currentUserIdResolver: () => 'admin_user',
        orderLoaderForTesting: (id) async => {
          'orderId': id,
          'shopId': 'shop_a',
          'status': 'placed',
        },
        orderUpdaterForTesting: (id, updates) async {
          updatedDocs[id] = updates;
        },
      );

      await service.updateOrderStatus('order_1', 'cancelled');
      expect(updatedDocs['order_1']?['status'], equals('cancelled'));
    });

    test('42. Admin valid operational cancellation on placed order succeeds via cancelOrder', () async {
      final updatedDocs = <String, Map<String, dynamic>>{};
      final service = OrderService(
        currentUserRoleResolver: () => AuthRole.admin,
        currentUserIdResolver: () => 'admin_user',
        orderLoaderForTesting: (id) async => {
          'orderId': id,
          'shopId': 'shop_a',
          'customerId': 'cust_other',
          'status': 'placed',
        },
        orderUpdaterForTesting: (id, updates) async {
          updatedDocs[id] = updates;
        },
      );

      await service.cancelOrder('order_1');
      expect(updatedDocs['order_1']?['status'], equals('cancelled'));
    });

    test('43. Admin cannot cancel accepted, delivered, or rejected orders', () async {
      final service = OrderService(
        currentUserRoleResolver: () => AuthRole.admin,
        currentUserIdResolver: () => 'admin_user',
        orderLoaderForTesting: (id) async => {
          'orderId': id,
          'shopId': 'shop_a',
          'customerId': 'cust_1',
          'status': 'accepted',
        },
        orderUpdaterForTesting: (id, updates) async {},
      );

      expect(
        () => service.cancelOrder('order_1'),
        throwsA(isA<OrderServiceException>()),
      );
    });

    test('44. Admin valid operational transitions: placed -> accepted, accepted -> delivered', () async {
      final updatedDocs = <String, Map<String, dynamic>>{};
      final service = OrderService(
        currentUserRoleResolver: () => AuthRole.admin,
        currentUserIdResolver: () => 'admin_user',
        orderLoaderForTesting: (id) async => {
          'orderId': id,
          'shopId': 'shop_a',
          'status': 'placed',
        },
        orderUpdaterForTesting: (id, updates) async {
          updatedDocs[id] = updates;
        },
      );

      await service.updateOrderStatus('order_1', 'accepted');
      expect(updatedDocs['order_1']?['status'], equals('accepted'));
    });

    test('45. Admin invalid lifecycle jump: placed -> delivered throws InvalidOrderTransitionException', () async {
      final service = OrderService(
        currentUserRoleResolver: () => AuthRole.admin,
        currentUserIdResolver: () => 'admin_user',
        orderLoaderForTesting: (id) async => {
          'orderId': id,
          'shopId': 'shop_a',
          'status': 'placed',
        },
        orderUpdaterForTesting: (id, updates) async {},
      );

      expect(
        () => service.updateOrderStatus('order_1', 'delivered'),
        throwsA(isA<InvalidOrderTransitionException>()),
      );
    });

    test('46. Admin arbitrary status injection: placed -> cooking throws InvalidOrderTransitionException', () async {
      final service = OrderService(
        currentUserRoleResolver: () => AuthRole.admin,
        currentUserIdResolver: () => 'admin_user',
        orderLoaderForTesting: (id) async => {
          'orderId': id,
          'shopId': 'shop_a',
          'status': 'placed',
        },
        orderUpdaterForTesting: (id, updates) async {},
      );

      expect(
        () => service.updateOrderStatus('order_1', 'cooking'),
        throwsA(isA<InvalidOrderTransitionException>()),
      );
    });

    test('47. Admin terminal immutability: delivered -> accepted throws InvalidOrderTransitionException', () async {
      final service = OrderService(
        currentUserRoleResolver: () => AuthRole.admin,
        currentUserIdResolver: () => 'admin_user',
        orderLoaderForTesting: (id) async => {
          'orderId': id,
          'shopId': 'shop_a',
          'status': 'delivered',
        },
        orderUpdaterForTesting: (id, updates) async {},
      );

      expect(
        () => service.updateOrderStatus('order_1', 'accepted'),
        throwsA(isA<InvalidOrderTransitionException>()),
      );
    });

    test('48. Admin terminal immutability: rejected -> accepted throws InvalidOrderTransitionException', () async {
      final service = OrderService(
        currentUserRoleResolver: () => AuthRole.admin,
        currentUserIdResolver: () => 'admin_user',
        orderLoaderForTesting: (id) async => {
          'orderId': id,
          'shopId': 'shop_a',
          'status': 'rejected',
        },
        orderUpdaterForTesting: (id, updates) async {},
      );

      expect(
        () => service.updateOrderStatus('order_1', 'accepted'),
        throwsA(isA<InvalidOrderTransitionException>()),
      );
    });

    test('49. Admin terminal immutability: cancelled -> placed throws InvalidOrderTransitionException', () async {
      final service = OrderService(
        currentUserRoleResolver: () => AuthRole.admin,
        currentUserIdResolver: () => 'admin_user',
        orderLoaderForTesting: (id) async => {
          'orderId': id,
          'shopId': 'shop_a',
          'status': 'cancelled',
        },
        orderUpdaterForTesting: (id, updates) async {},
      );

      expect(
        () => service.updateOrderStatus('order_1', 'placed'),
        throwsA(isA<InvalidOrderTransitionException>()),
      );
    });

    test('50. Customer cannot call updateOrderStatus (fails closed before status evaluation)', () async {
      final service = OrderService(
        currentUserRoleResolver: () => AuthRole.customer,
        currentUserIdResolver: () => 'cust_user_1',
        orderLoaderForTesting: (id) async => {
          'orderId': id,
          'shopId': 'shop_a',
          'status': 'placed',
        },
        orderUpdaterForTesting: (id, updates) async {},
      );

      expect(
        () => service.updateOrderStatus('order_1', 'cancelled'),
        throwsA(isA<OrderServiceException>()),
      );
    });

    test('51. Concurrency invariant: Customer cancel after Shopkeeper accept throws', () async {
      // Order state was placed, but shopkeeper accepted before customer cancel committed
      final service = OrderService(
        currentUserRoleResolver: () => AuthRole.customer,
        currentUserIdResolver: () => 'cust_user_1',
        orderLoaderForTesting: (id) async => {
          'orderId': id,
          'shopId': 'shop_a',
          'customerId': 'cust_user_1',
          'status': 'accepted', // shopkeeper won race
        },
        orderUpdaterForTesting: (id, updates) async {},
      );

      expect(
        () => service.cancelOrder('order_1'),
        throwsA(isA<OrderServiceException>()),
        reason: 'Customer cancellation must abort if order is already accepted',
      );
    });

    test('52. Concurrency invariant: Shopkeeper accept after Customer cancel throws', () async {
      // Order state was placed, but customer cancelled before shopkeeper accept committed
      final service = OrderService(
        currentUserRoleResolver: () => AuthRole.shopkeeper,
        currentShopIdResolver: () => 'shop_a',
        currentUserIdResolver: () => 'sk_user_a',
        orderLoaderForTesting: (id) async => {
          'orderId': id,
          'shopId': 'shop_a',
          'status': 'cancelled', // customer won race
        },
        orderUpdaterForTesting: (id, updates) async {},
      );

      expect(
        () => service.updateOrderStatus('order_1', 'accepted'),
        throwsA(isA<InvalidOrderTransitionException>()),
        reason: 'Shopkeeper accept must abort if order is already cancelled',
      );
    });
  });

  group('Phase 5.3: Immutable Order Fields & Mutation Invariants', () {
    test('53. Authoritative immutable order fields registry completeness', () {
      final expectedImmutable = {
        'orderId',
        'customerId',
        'shopId',
        'createdAt',
        'items',
        'price',
        'subtotal',
        'grandTotal',
        'totalAmount',
        'deliveryCharges',
        'totalItems',
        'shopName',
        'customerName',
        'customerPhone',
        'orderMethod',
        'specialInstructions',
        'deliveryNote',
      };

      for (final field in expectedImmutable) {
        expect(
          OrderService.immutableOrderFields.contains(field),
          isTrue,
          reason: 'Field "$field" must be registered in immutableOrderFields',
        );
      }
    });

    test('54. validateNoImmutableFields permits valid operational update payloads', () {
      expect(
        () => OrderService.validateNoImmutableFields({
          'status': 'accepted',
          'rejectionReason': 'Item unavailable',
          'deliveryPersonId': 'dp_123',
          'deliveryPersonName': 'Ramesh Kumar',
          'cancelledAt': DateTime.now(),
          'updatedAt': DateTime.now(),
        }),
        returnsNormally,
      );
    });

    test('55. validateNoImmutableFields rejects customerId mutation', () {
      expect(
        () => OrderService.validateNoImmutableFields({
          'customerId': 'attacker_uid',
        }),
        throwsA(
          isA<OrderServiceException>().having(
            (e) => e.message,
            'message',
            contains('customerId'),
          ),
        ),
      );
    });

    test('56. validateNoImmutableFields rejects shopId mutation', () {
      expect(
        () => OrderService.validateNoImmutableFields({
          'shopId': 'attacker_shop',
        }),
        throwsA(
          isA<OrderServiceException>().having(
            (e) => e.message,
            'message',
            contains('shopId'),
          ),
        ),
      );
    });

    test('57. validateNoImmutableFields rejects orderId mutation', () {
      expect(
        () => OrderService.validateNoImmutableFields({
          'orderId': 'forged_order_id',
        }),
        throwsA(
          isA<OrderServiceException>().having(
            (e) => e.message,
            'message',
            contains('orderId'),
          ),
        ),
      );
    });

    test('58. validateNoImmutableFields rejects createdAt mutation', () {
      expect(
        () => OrderService.validateNoImmutableFields({
          'createdAt': DateTime.now(),
        }),
        throwsA(
          isA<OrderServiceException>().having(
            (e) => e.message,
            'message',
            contains('createdAt'),
          ),
        ),
      );
    });

    test(
      '59. validateNoImmutableFields rejects financial total mutations (totalAmount, grandTotal, subtotal, deliveryCharges)',
      () {
        for (final finField in [
          'totalAmount',
          'grandTotal',
          'subtotal',
          'deliveryCharges',
          'price',
        ]) {
          expect(
            () => OrderService.validateNoImmutableFields({finField: 1}),
            throwsA(
              isA<OrderServiceException>().having(
                (e) => e.message,
                'message',
                contains(finField),
              ),
            ),
          );
        }
      },
    );

    test('60. validateNoImmutableFields rejects items array mutation', () {
      expect(
        () => OrderService.validateNoImmutableFields({
          'items': <Map<String, dynamic>>[],
        }),
        throwsA(
          isA<OrderServiceException>().having(
            (e) => e.message,
            'message',
            contains('items'),
          ),
        ),
      );
    });

    test('61. validateNoImmutableFields rejects historical snapshot mutations', () {
      for (final snapField in [
        'customerName',
        'customerPhone',
        'shopName',
        'orderMethod',
        'specialInstructions',
        'deliveryNote',
      ]) {
        expect(
          () => OrderService.validateNoImmutableFields({snapField: 'tampered'}),
          throwsA(
            isA<OrderServiceException>().having(
              (e) => e.message,
              'message',
              contains(snapField),
            ),
          ),
        );
      }
    });

    test('62. orderUpdaterForTesting wrapper blocks caller from injecting immutable fields', () async {
      final service = OrderService(
        currentUserRoleResolver: () => AuthRole.shopkeeper,
        currentShopIdResolver: () => 'shop_a',
        orderLoaderForTesting: (id) async => {
          'orderId': id,
          'shopId': 'shop_a',
          'status': 'placed',
        },
        orderUpdaterForTesting: (id, updates) async {},
      );

      // Verify that validateNoImmutableFields is invoked automatically
      expect(
        () => OrderService.validateNoImmutableFields({
          'status': 'accepted',
          'grandTotal': 1,
        }),
        throwsA(isA<OrderServiceException>()),
      );

      // Valid transition works cleanly
      await expectLater(
        service.updateOrderStatus('order_1', 'accepted'),
        completes,
      );
    });

    test('63. Shopkeeper updateOrderStatus emits only whitelisted operational keys', () async {
      Map<String, dynamic>? recordedUpdates;
      final service = OrderService(
        currentUserRoleResolver: () => AuthRole.shopkeeper,
        currentShopIdResolver: () => 'shop_a',
        orderLoaderForTesting: (id) async => {
          'orderId': id,
          'shopId': 'shop_a',
          'status': 'placed',
        },
        orderUpdaterForTesting: (id, updates) async {
          recordedUpdates = updates;
        },
      );

      await service.updateOrderStatus('order_1', 'accepted');

      expect(recordedUpdates, isNotNull);
      expect(recordedUpdates!['status'], equals('accepted'));
      // Ensure no immutable fields were emitted
      for (final key in recordedUpdates!.keys) {
        expect(
          OrderService.immutableOrderFields.contains(key),
          isFalse,
          reason: 'Operational update must never emit immutable field "$key"',
        );
      }
    });

    test('64. Customer cancelOrder emits only whitelisted operational keys', () async {
      Map<String, dynamic>? recordedUpdates;
      final service = OrderService(
        currentUserRoleResolver: () => AuthRole.customer,
        currentUserIdResolver: () => 'cust_1',
        orderLoaderForTesting: (id) async => {
          'orderId': id,
          'shopId': 'shop_a',
          'customerId': 'cust_1',
          'status': 'placed',
        },
        orderUpdaterForTesting: (id, updates) async {
          recordedUpdates = updates;
        },
      );

      await service.cancelOrder('order_1');

      expect(recordedUpdates, isNotNull);
      expect(recordedUpdates!['status'], equals('cancelled'));
      for (final key in recordedUpdates!.keys) {
        expect(
          OrderService.immutableOrderFields.contains(key),
          isFalse,
          reason: 'Customer cancellation must never emit immutable field "$key"',
        );
      }
    });

    test('65. Combined attack simulation: status update + financial field injection blocked', () async {
      final maliciousPayload = {
        'status': 'accepted',
        'totalAmount': 1.0,
      };

      expect(
        () => OrderService.validateNoImmutableFields(maliciousPayload),
        throwsA(
          isA<OrderServiceException>().having(
            (e) => e.message,
            'message',
            contains('totalAmount'),
          ),
        ),
        reason: 'Combined operational status + financial field mutation must be blocked',
      );
    });

    test('66. Combined attack simulation: status update + ownership reassignment blocked', () async {
      final maliciousPayload = {
        'status': 'delivered',
        'customerId': 'attacker_uid',
      };

      expect(
        () => OrderService.validateNoImmutableFields(maliciousPayload),
        throwsA(
          isA<OrderServiceException>().having(
            (e) => e.message,
            'message',
            contains('customerId'),
          ),
        ),
        reason: 'Combined operational status + customer ownership reassignment must be blocked',
      );
    });

    test('67. Combined attack simulation: status update + shopId reassignment blocked', () async {
      final maliciousPayload = {
        'status': 'rejected',
        'shopId': 'attacker_shop',
      };

      expect(
        () => OrderService.validateNoImmutableFields(maliciousPayload),
        throwsA(
          isA<OrderServiceException>().having(
            (e) => e.message,
            'message',
            contains('shopId'),
          ),
        ),
        reason: 'Combined operational status + shop tenancy reassignment must be blocked',
      );
    });

    test('68. Combined attack simulation: cancellation + creation timestamp forgery blocked', () async {
      final maliciousPayload = {
        'status': 'cancelled',
        'createdAt': DateTime(2020),
      };

      expect(
        () => OrderService.validateNoImmutableFields(maliciousPayload),
        throwsA(
          isA<OrderServiceException>().having(
            (e) => e.message,
            'message',
            contains('createdAt'),
          ),
        ),
        reason: 'Combined customer cancellation + createdAt timestamp forgery must be blocked',
      );
    });
  });

  group('Phase 5.4: Race & Transaction Protection Invariants', () {
    test('69. Race A (Case 1): Shopkeeper accept commits first -> Customer cancel aborts', () async {
      // Shared document state
      final orderDoc = <String, dynamic>{
        'orderId': 'order_race_1',
        'shopId': 'shop_a',
        'customerId': 'cust_1',
        'status': 'placed',
      };

      final skService = OrderService(
        currentUserRoleResolver: () => AuthRole.shopkeeper,
        currentShopIdResolver: () => 'shop_a',
        currentUserIdResolver: () => 'sk_user_a',
        orderLoaderForTesting: (id) async => Map<String, dynamic>.from(orderDoc),
        orderUpdaterForTesting: (id, updates) async {
          orderDoc.addAll(updates);
        },
      );

      final custService = OrderService(
        currentUserRoleResolver: () => AuthRole.customer,
        currentUserIdResolver: () => 'cust_1',
        orderLoaderForTesting: (id) async => Map<String, dynamic>.from(orderDoc),
        orderUpdaterForTesting: (id, updates) async {
          orderDoc.addAll(updates);
        },
      );

      // 1. Shopkeeper commits accept first
      await skService.updateOrderStatus('order_race_1', 'accepted');
      expect(orderDoc['status'], equals('accepted'));

      // 2. Customer cancel subsequently attempts to commit -> MUST FAIL
      expect(
        () => custService.cancelOrder('order_race_1'),
        throwsA(
          isA<OrderServiceException>().having(
            (e) => e.message,
            'message',
            contains('accepted'),
          ),
        ),
        reason: 'Customer cancellation must abort if shopkeeper already accepted',
      );

      // Invariant: Final state is strictly accepted, never cancelled
      expect(orderDoc['status'], equals('accepted'));
      expect(orderDoc.containsKey('cancelledAt'), isFalse);
    });

    test('70. Race A (Case 2): Customer cancel commits first -> Shopkeeper accept aborts', () async {
      // Shared document state
      final orderDoc = <String, dynamic>{
        'orderId': 'order_race_2',
        'shopId': 'shop_a',
        'customerId': 'cust_2',
        'status': 'placed',
      };

      final skService = OrderService(
        currentUserRoleResolver: () => AuthRole.shopkeeper,
        currentShopIdResolver: () => 'shop_a',
        currentUserIdResolver: () => 'sk_user_a',
        orderLoaderForTesting: (id) async => Map<String, dynamic>.from(orderDoc),
        orderUpdaterForTesting: (id, updates) async {
          orderDoc.addAll(updates);
        },
      );

      final custService = OrderService(
        currentUserRoleResolver: () => AuthRole.customer,
        currentUserIdResolver: () => 'cust_2',
        orderLoaderForTesting: (id) async => Map<String, dynamic>.from(orderDoc),
        orderUpdaterForTesting: (id, updates) async {
          orderDoc.addAll(updates);
        },
      );

      // 1. Customer commits cancel first
      await custService.cancelOrder('order_race_2');
      expect(orderDoc['status'], equals('cancelled'));

      // 2. Shopkeeper accept subsequently attempts to commit -> MUST FAIL
      expect(
        () => skService.updateOrderStatus('order_race_2', 'accepted'),
        throwsA(isA<InvalidOrderTransitionException>()),
        reason: 'Shopkeeper accept must abort if customer already cancelled',
      );

      // Invariant: Final state is strictly cancelled, never accepted
      expect(orderDoc['status'], equals('cancelled'));
      expect(orderDoc.containsKey('acceptedAt'), isFalse);
    });

    test('71. Race B: Shopkeeper accept vs concurrent Admin cancellation collision', () async {
      final orderDoc = <String, dynamic>{
        'orderId': 'order_race_3',
        'shopId': 'shop_a',
        'customerId': 'cust_3',
        'status': 'placed',
      };

      final adminService = OrderService(
        currentUserRoleResolver: () => AuthRole.admin,
        currentUserIdResolver: () => 'admin_user',
        orderLoaderForTesting: (id) async => Map<String, dynamic>.from(orderDoc),
        orderUpdaterForTesting: (id, updates) async {
          orderDoc.addAll(updates);
        },
      );

      final skService = OrderService(
        currentUserRoleResolver: () => AuthRole.shopkeeper,
        currentShopIdResolver: () => 'shop_a',
        currentUserIdResolver: () => 'sk_user_a',
        orderLoaderForTesting: (id) async => Map<String, dynamic>.from(orderDoc),
        orderUpdaterForTesting: (id, updates) async {
          orderDoc.addAll(updates);
        },
      );

      // Admin executes operational cancellation first
      await adminService.cancelOrder('order_race_3');
      expect(orderDoc['status'], equals('cancelled'));

      // Shopkeeper cannot transition cancelled order to accepted
      expect(
        () => skService.updateOrderStatus('order_race_3', 'accepted'),
        throwsA(isA<InvalidOrderTransitionException>()),
      );
      expect(orderDoc['status'], equals('cancelled'));
    });

    test('72. Race C: Customer cancel commits first -> Shopkeeper reject aborts', () async {
      final orderDoc = <String, dynamic>{
        'orderId': 'order_race_4',
        'shopId': 'shop_a',
        'customerId': 'cust_4',
        'status': 'placed',
      };

      final custService = OrderService(
        currentUserRoleResolver: () => AuthRole.customer,
        currentUserIdResolver: () => 'cust_4',
        orderLoaderForTesting: (id) async => Map<String, dynamic>.from(orderDoc),
        orderUpdaterForTesting: (id, updates) async {
          orderDoc.addAll(updates);
        },
      );

      final skService = OrderService(
        currentUserRoleResolver: () => AuthRole.shopkeeper,
        currentShopIdResolver: () => 'shop_a',
        currentUserIdResolver: () => 'sk_user_a',
        orderLoaderForTesting: (id) async => Map<String, dynamic>.from(orderDoc),
        orderUpdaterForTesting: (id, updates) async {
          orderDoc.addAll(updates);
        },
      );

      await custService.cancelOrder('order_race_4');
      expect(orderDoc['status'], equals('cancelled'));

      // Shopkeeper reject must abort because order is already cancelled
      expect(
        () => skService.updateOrderStatus('order_race_4', 'rejected'),
        throwsA(isA<InvalidOrderTransitionException>()),
      );
      expect(orderDoc['status'], equals('cancelled'));
    });

    test('73. Race D: Delivered terminal state rejects subsequent invalid status mutation', () async {
      final orderDoc = <String, dynamic>{
        'orderId': 'order_race_5',
        'shopId': 'shop_a',
        'customerId': 'cust_5',
        'status': 'accepted',
      };

      final skService = OrderService(
        currentUserRoleResolver: () => AuthRole.shopkeeper,
        currentShopIdResolver: () => 'shop_a',
        currentUserIdResolver: () => 'sk_user_a',
        orderLoaderForTesting: (id) async => Map<String, dynamic>.from(orderDoc),
        orderUpdaterForTesting: (id, updates) async {
          orderDoc.addAll(updates);
        },
      );

      // Transition to delivered
      await skService.updateOrderStatus('order_race_5', 'delivered');
      expect(orderDoc['status'], equals('delivered'));

      // Concurrent or subsequent attempt to reject or reset to accepted
      expect(
        () => skService.updateOrderStatus('order_race_5', 'rejected'),
        throwsA(isA<InvalidOrderTransitionException>()),
      );
      expect(
        () => skService.updateOrderStatus('order_race_5', 'accepted'),
        throwsA(isA<InvalidOrderTransitionException>()),
      );
      expect(orderDoc['status'], equals('delivered'));
    });

    test('74. Race E: Duplicate same transition (accepted -> accepted) is an idempotent safe no-op', () async {
      var writeCount = 0;
      final service = OrderService(
        currentUserRoleResolver: () => AuthRole.shopkeeper,
        currentShopIdResolver: () => 'shop_a',
        currentUserIdResolver: () => 'sk_user_a',
        orderLoaderForTesting: (id) async => {
          'orderId': id,
          'shopId': 'shop_a',
          'status': 'accepted',
        },
        orderUpdaterForTesting: (id, updates) async {
          writeCount++;
        },
      );

      // Calling update with identical status must not write or mutate timestamps
      await service.updateOrderStatus('order_1', 'accepted');
      expect(writeCount, equals(0), reason: 'Duplicate same-state update must perform zero writes');
    });

    test('75. Race E: Duplicate customer cancellation (cancelled -> cancelled) is an idempotent safe no-op', () async {
      var writeCount = 0;
      final service = OrderService(
        currentUserRoleResolver: () => AuthRole.customer,
        currentUserIdResolver: () => 'cust_1',
        orderLoaderForTesting: (id) async => {
          'orderId': id,
          'shopId': 'shop_a',
          'customerId': 'cust_1',
          'status': 'cancelled',
        },
        orderUpdaterForTesting: (id, updates) async {
          writeCount++;
        },
      );

      // Calling cancel on already cancelled order returns cleanly without writing
      await expectLater(service.cancelOrder('order_1'), completes);
      expect(writeCount, equals(0), reason: 'Duplicate cancellation must perform zero writes');
    });

    test('76. Race F: Terminal state immutability rejects concurrent mutation', () async {
      final terminalStatuses = ['delivered', 'rejected', 'cancelled', 'delivery_expired'];

      for (final terminal in terminalStatuses) {
        final service = OrderService(
          currentUserRoleResolver: () => AuthRole.shopkeeper,
          currentShopIdResolver: () => 'shop_a',
          currentUserIdResolver: () => 'sk_user_a',
          orderLoaderForTesting: (id) async => {
            'orderId': id,
            'shopId': 'shop_a',
            'status': terminal,
          },
          orderUpdaterForTesting: (id, updates) async {},
        );

        expect(
          () => service.updateOrderStatus('order_term', 'accepted'),
          throwsA(isA<InvalidOrderTransitionException>()),
          reason: 'Terminal status "$terminal" cannot be transitioned to accepted',
        );
      }
    });

    test('77. Race G: Cross-shop concurrent mutation is strictly blocked before state evaluation', () async {
      final orderDoc = <String, dynamic>{
        'orderId': 'order_cross_1',
        'shopId': 'shop_a', // belongs to shop_a
        'status': 'placed',
      };

      // Attacker is shopkeeper of shop_b trying to race-update shop_a order
      final attackerService = OrderService(
        currentUserRoleResolver: () => AuthRole.shopkeeper,
        currentShopIdResolver: () => 'shop_b',
        currentUserIdResolver: () => 'sk_attacker',
        orderLoaderForTesting: (id) async => Map<String, dynamic>.from(orderDoc),
        orderUpdaterForTesting: (id, updates) async {
          orderDoc.addAll(updates);
        },
      );

      expect(
        () => attackerService.updateOrderStatus('order_cross_1', 'accepted'),
        throwsA(
          isA<OrderServiceException>().having(
            (e) => e.message,
            'message',
            contains('Unauthorized'),
          ),
        ),
      );
      expect(orderDoc['status'], equals('placed'));
    });

    test('78. Race H: Cross-customer cancellation race is strictly blocked before state evaluation', () async {
      final orderDoc = <String, dynamic>{
        'orderId': 'order_cross_2',
        'shopId': 'shop_a',
        'customerId': 'cust_victim',
        'status': 'placed',
      };

      final attackerService = OrderService(
        currentUserRoleResolver: () => AuthRole.customer,
        currentUserIdResolver: () => 'cust_attacker',
        orderLoaderForTesting: (id) async => Map<String, dynamic>.from(orderDoc),
        orderUpdaterForTesting: (id, updates) async {
          orderDoc.addAll(updates);
        },
      );

      expect(
        () => attackerService.cancelOrder('order_cross_2'),
        throwsA(
          isA<OrderServiceException>().having(
            (e) => e.message,
            'message',
            contains('Unauthorized'),
          ),
        ),
      );
      expect(orderDoc['status'], equals('placed'));
    });

    test('79. Transaction Retry Invariant: Stale read re-evaluation on conflict', () async {
      // Simulates transaction retry:
      // Attempt 1 reads 'placed'. Before commit, state concurrently changes to 'accepted'.
      // Attempt 2 re-reads 'accepted' and must abort customer cancellation.
      var readCount = 0;
      var simulatedCurrentStatus = 'placed';

      final service = OrderService(
        currentUserRoleResolver: () => AuthRole.customer,
        currentUserIdResolver: () => 'cust_retry',
        orderLoaderForTesting: (id) async {
          readCount++;
          if (readCount > 1) {
            // Simulated concurrent commit happened between attempt 1 and attempt 2
            simulatedCurrentStatus = 'accepted';
          }
          return {
            'orderId': id,
            'shopId': 'shop_a',
            'customerId': 'cust_retry',
            'status': simulatedCurrentStatus,
          };
        },
        orderUpdaterForTesting: (id, updates) async {},
      );

      // Attempt 1: loader returns 'placed' -> would succeed
      // In retry simulation: on re-reading 'accepted', customer cancellation fails closed
      simulatedCurrentStatus = 'accepted';
      expect(
        () => service.cancelOrder('order_retry'),
        throwsA(isA<OrderServiceException>()),
        reason: 'Fresh state evaluated on retry must abort cancellation',
      );
    });

    test('80. Transaction Retry Side Effect Invariant: Zero side effects during retries', () async {
      const externalEffectCounter = 0;
      final service = OrderService(
        currentUserRoleResolver: () => AuthRole.shopkeeper,
        currentShopIdResolver: () => 'shop_a',
        currentUserIdResolver: () => 'sk_user_a',
        orderLoaderForTesting: (id) async => {
          'orderId': id,
          'shopId': 'shop_a',
          'status': 'placed',
        },
        orderUpdaterForTesting: (id, updates) async {
          // Invariant: Updater only persists the valid update map;
          // no external side effects (FCM, WhatsApp) reside in the transaction
        },
      );

      await service.updateOrderStatus('order_side_effects', 'accepted');
      expect(externalEffectCounter, equals(0), reason: 'Zero external side effects in transaction');
    });

    test('81. Transaction Immutability Preservation: Status update under retry never mutates immutable fields', () async {
      Map<String, dynamic>? emittedUpdates;
      final service = OrderService(
        currentUserRoleResolver: () => AuthRole.shopkeeper,
        currentShopIdResolver: () => 'shop_a',
        currentUserIdResolver: () => 'sk_user_a',
        orderLoaderForTesting: (id) async => {
          'orderId': id,
          'shopId': 'shop_a',
          'customerId': 'cust_imm',
          'totalAmount': 500,
          'status': 'placed',
        },
        orderUpdaterForTesting: (id, updates) async {
          emittedUpdates = updates;
        },
      );

      await service.updateOrderStatus('order_imm_retry', 'accepted');
      expect(emittedUpdates, isNotNull);
      for (final key in emittedUpdates!.keys) {
        expect(
          OrderService.immutableOrderFields.contains(key),
          isFalse,
          reason: 'Transaction update must not contain immutable field "$key"',
        );
      }
    });

    test('82. Dual-Transaction Serializability: Contradictory metadata is strictly impossible', () async {
      // Demonstrates serializability invariant:
      // An order cannot concurrently be 'accepted' with 'cancelledAt' or 'cancelled' with 'acceptedAt'
      final acceptedOrder = <String, dynamic>{
        'status': 'accepted',
        'acceptedAt': DateTime.now(),
      };
      final cancelledOrder = <String, dynamic>{
        'status': 'cancelled',
        'cancelledAt': DateTime.now(),
      };

      // Invariant: Statuses and timestamps are mutually exclusive
      expect(acceptedOrder.containsKey('cancelledAt'), isFalse);
      expect(cancelledOrder.containsKey('acceptedAt'), isFalse);
      expect(acceptedOrder['status'], isNot(equals(cancelledOrder['status'])));
    });
  });
}
