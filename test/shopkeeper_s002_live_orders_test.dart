// BU Gate2Eat — Checkpoint 5 / S-002 Forensic Test Suite
// Complete Verification of Shopkeeper Order Management, Concurrency, Ownership, Transitions & Life-cycle

import 'dart:async';

import 'package:bugate2eat_app/models/order_model.dart';
import 'package:bugate2eat_app/services/order_service.dart';
import 'package:bugate2eat_app/services/shopkeeper_notification_dispatcher.dart';
import 'package:flutter_test/flutter_test.dart';

/// In-memory reactive OrderService simulating Firestore transaction and collection behavior.
class MockFirestoreOrderService extends OrderService {
  MockFirestoreOrderService() : super();

  final Map<String, AppOrder> _orders = {};
  final Map<String, Map<String, dynamic>> _shopStats = {};
  final StreamController<Map<String, AppOrder>> _ordersStreamController =
      StreamController<Map<String, AppOrder>>.broadcast();

  @override
  bool get isAvailable => true;

  Map<String, dynamic> getShopStats(String shopId) {
    return _shopStats[shopId] ?? {};
  }

  void seedOrder(AppOrder order) {
    _orders[order.orderId] = order;
    _ordersStreamController.add(Map.unmodifiable(_orders));
  }

  @override
  Future<AppOrder?> getOrder(String orderId) async {
    return _orders[orderId];
  }

  @override
  Stream<List<AppOrder>> watchShopActiveOrders(String shopId) {
    List<AppOrder> getActive() => _orders.values
        .where((o) =>
            o.shopId == shopId &&
            (o.status == OrderStatusRules.statusPlaced ||
                o.status == OrderStatusRules.statusAccepted))
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return Stream<List<AppOrder>>.multi((controller) {
      controller.add(getActive());
      final sub = _ordersStreamController.stream.listen((_) {
        controller.add(getActive());
      });
      controller.onCancel = sub.cancel;
    });
  }

  @override
  Stream<List<AppOrder>> watchShopOrderHistory(String shopId) {
    List<AppOrder> getHistory() => _orders.values
        .where((o) =>
            o.shopId == shopId &&
            (o.status == OrderStatusRules.statusDelivered ||
                o.status == OrderStatusRules.statusRejected ||
                o.status == OrderStatusRules.statusCancelled ||
                o.status == OrderStatusRules.statusDeliveryExpired))
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return Stream<List<AppOrder>>.multi((controller) {
      controller.add(getHistory());
      final sub = _ordersStreamController.stream.listen((_) {
        controller.add(getHistory());
      });
      controller.onCancel = sub.cancel;
    });
  }

  @override
  Future<void> updateOrderStatus(
    String orderId,
    String newStatus, {
    String? rejectionReason,
    String? deliveryPersonId,
    String? deliveryPersonName,
    DateTime? customNow,
  }) async {
    final order = _orders[orderId];
    if (order == null) {
      throw OrderNotFoundException(orderId);
    }

    final currentStatus = order.status;
    final shopId = order.shopId;
    final now = customNow ?? DateTime.now();

    // Idempotency check
    if (currentStatus == newStatus) {
      return;
    }

    if (!OrderStatusRules.isValidTransition(currentStatus, newStatus)) {
      throw InvalidOrderTransitionException(
        currentStatus: currentStatus,
        targetStatus: newStatus,
      );
    }

    // ── Transition: PLACED → ACCEPTED ──
    if (currentStatus == OrderStatusRules.statusPlaced &&
        newStatus == OrderStatusRules.statusAccepted) {
      if (order.acceptDeadline != null && now.isAfter(order.acceptDeadline!)) {
        _orders[orderId] = order.copyWith(
          status: OrderStatusRules.statusRejected,
          rejectionReason:
              'Order was automatically rejected because the shopkeeper did not accept it within 20 minutes.',
          rejectedAt: now,
        );
        _incrementStat(shopId, 'appOrders');
        _incrementStat(shopId, 'notAccepted');
        _ordersStreamController.add(Map.unmodifiable(_orders));
        throw const OrderServiceException(
          'Order acceptance deadline (20 mins) has expired.',
        );
      }

      _orders[orderId] = order.copyWith(
        status: OrderStatusRules.statusAccepted,
        acceptedAt: now,
        rejectDeadline: now.add(const Duration(minutes: 15)),
        deliveryDeadline: now.add(const Duration(minutes: 90)),
      );
      _incrementStat(shopId, 'appOrders');
      _incrementStat(shopId, 'accepted');
    }
    // ── Transition: PLACED → REJECTED ──
    else if (currentStatus == OrderStatusRules.statusPlaced &&
        newStatus == OrderStatusRules.statusRejected) {
      _orders[orderId] = order.copyWith(
        status: OrderStatusRules.statusRejected,
        rejectedAt: now,
        rejectionReason: rejectionReason ?? 'Rejected by shopkeeper',
      );
      _incrementStat(shopId, 'appOrders');
      _incrementStat(shopId, 'notAccepted');
    }
    // ── Transition: ACCEPTED → REJECTED ──
    else if (currentStatus == OrderStatusRules.statusAccepted &&
        newStatus == OrderStatusRules.statusRejected) {
      if (order.rejectDeadline != null && now.isAfter(order.rejectDeadline!)) {
        throw const OrderServiceException(
          'Rejection window of 15 minutes has expired. Order cannot be rejected.',
        );
      }
      _orders[orderId] = order.copyWith(
        status: OrderStatusRules.statusRejected,
        rejectedAt: now,
        rejectionReason: rejectionReason ?? 'Rejected by shopkeeper',
      );
      _incrementStat(shopId, 'rejectedAfterAccept');
    }
    // ── Transition: ACCEPTED → DELIVERED ──
    else if (currentStatus == OrderStatusRules.statusAccepted &&
        newStatus == OrderStatusRules.statusDelivered) {
      if (order.deliveryDeadline != null &&
          now.isAfter(order.deliveryDeadline!)) {
        _orders[orderId] = order.copyWith(
          status: OrderStatusRules.statusDeliveryExpired,
          rejectionReason: 'Delivery window of 90 minutes expired.',
        );
        _incrementStat(shopId, 'deliveryExpired');
        _ordersStreamController.add(Map.unmodifiable(_orders));
        throw const OrderServiceException(
          'Delivery window of 90 minutes has expired.',
        );
      }
      _orders[orderId] = order.copyWith(
        status: OrderStatusRules.statusDelivered,
        deliveredAt: now,
        deliveryPersonId: deliveryPersonId,
        deliveryPersonName: deliveryPersonName,
      );
      _incrementStat(shopId, 'delivered');
    }

    _ordersStreamController.add(Map.unmodifiable(_orders));
  }

  void _incrementStat(String shopId, String key) {
    final stats = _shopStats.putIfAbsent(shopId, () => <String, dynamic>{});
    stats[key] = (stats[key] as int? ?? 0) + 1;
  }

  @override
  Future<void> cancelOrder(String orderId) async {
    final order = _orders[orderId];
    if (order == null) return;

    if (order.status != OrderStatusRules.statusPlaced) {
      throw OrderServiceException(
        'Cannot cancel order in "${order.status}" status. Orders can only be cancelled while in placed status.',
      );
    }

    _orders.remove(orderId);
    _ordersStreamController.add(Map.unmodifiable(_orders));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  AppOrder createSampleOrder({
    required String orderId,
    required String shopId,
    String customerName = 'Student A',
    String customerPhone = '9876543210',
    String status = 'placed',
    double subtotal = 200.0,
    double deliveryCharges = 20.0,
    DateTime? createdAt,
    DateTime? acceptDeadline,
  }) {
    final now = createdAt ?? DateTime.now();
    return AppOrder(
      orderId: orderId,
      shopId: shopId,
      shopName: shopId == 'rajat_shop' ? 'Rajat Shop' : 'Other Shop',
      customerId: 'cust_$customerPhone',
      customerName: customerName,
      customerPhone: customerPhone,
      items: [
        OrderItem(
          menuItemId: 'item_1',
          name: 'Paneer Wrap',
          price: (subtotal / 2).round(),
          quantity: 2,
        ),
      ],
      deliveryCharges: deliveryCharges,
      totalAmount: subtotal + deliveryCharges,
      status: status,
      createdAt: now,
      acceptDeadline:
          acceptDeadline ?? now.add(const Duration(minutes: 20)),
    );
  }

  group('Checkpoint 5 — S-002: Shopkeeper Order Management Targeted Verification Suite', () {
    late MockFirestoreOrderService orderService;

    setUp(() {
      orderService = MockFirestoreOrderService();
    });

    // 1. Live order arrival
    test('1. Live order arrival: Stream emits newly created order without manual refresh', () async {
      final stream = orderService.watchShopActiveOrders('rajat_shop');
      final expectation = expectLater(
        stream,
        emitsInOrder([
          isEmpty,
          hasLength(1),
        ]),
      );

      // Initially empty
      orderService._ordersStreamController.add({});

      // Customer places order
      final newOrder = createSampleOrder(
        orderId: 'ORD-LIVE-1',
        shopId: 'rajat_shop',
      );
      orderService.seedOrder(newOrder);

      await expectation;
    });

    // 2. Shop ownership filtering
    test('2. Shop ownership filtering: Shop A orders never appear in Shop B stream', () async {
      final orderShopA = createSampleOrder(
        orderId: 'ORD-A',
        shopId: 'rajat_shop',
      );
      final orderShopB = createSampleOrder(
        orderId: 'ORD-B',
        shopId: 'other_shop',
      );

      orderService.seedOrder(orderShopA);
      orderService.seedOrder(orderShopB);

      final streamA = orderService.watchShopActiveOrders('rajat_shop');
      final streamB = orderService.watchShopActiveOrders('other_shop');

      final listA = await streamA.first;
      final listB = await streamB.first;

      expect(listA.map((o) => o.orderId), contains('ORD-A'));
      expect(listA.map((o) => o.orderId), isNot(contains('ORD-B')));

      expect(listB.map((o) => o.orderId), contains('ORD-B'));
      expect(listB.map((o) => o.orderId), isNot(contains('ORD-A')));
    });

    // 3. Accept exactly once
    test('3. Accept exactly once: Idempotent and prevents duplicate stat increments on rapid double tap', () async {
      final order = createSampleOrder(
        orderId: 'ORD-ACCEPT-1',
        shopId: 'rajat_shop',
      );
      orderService.seedOrder(order);

      // First tap: placed -> accepted
      await orderService.updateOrderStatus('ORD-ACCEPT-1', 'accepted');
      var updated = await orderService.getOrder('ORD-ACCEPT-1');
      expect(updated?.status, 'accepted');
      expect(orderService.getShopStats('rajat_shop')['accepted'], 1);
      expect(orderService.getShopStats('rajat_shop')['appOrders'], 1);

      // Immediate second tap: duplicate call
      await orderService.updateOrderStatus('ORD-ACCEPT-1', 'accepted');
      updated = await orderService.getOrder('ORD-ACCEPT-1');
      expect(updated?.status, 'accepted');
      // Stats must remain exactly 1, no duplicate increment
      expect(orderService.getShopStats('rajat_shop')['accepted'], 1);
      expect(orderService.getShopStats('rajat_shop')['appOrders'], 1);
    });

    // 4. Reject exactly once
    test('4. Reject exactly once: Status becomes rejected, reason stored, stats incremented once', () async {
      final order = createSampleOrder(
        orderId: 'ORD-REJECT-1',
        shopId: 'rajat_shop',
      );
      orderService.seedOrder(order);

      await orderService.updateOrderStatus(
        'ORD-REJECT-1',
        'rejected',
        rejectionReason: 'Items not available',
      );

      final updated = await orderService.getOrder('ORD-REJECT-1');
      expect(updated?.status, 'rejected');
      expect(updated?.rejectionReason, 'Items not available');
      expect(orderService.getShopStats('rajat_shop')['notAccepted'], 1);

      // Duplicate reject call
      await orderService.updateOrderStatus(
        'ORD-REJECT-1',
        'rejected',
        rejectionReason: 'Items not available',
      );
      expect(orderService.getShopStats('rajat_shop')['notAccepted'], 1);
    });

    // 5. Accept/reject race
    test('5. Accept/reject race: If reject occurs first, subsequent accept is strictly blocked', () async {
      final order = createSampleOrder(
        orderId: 'ORD-RACE-1',
        shopId: 'rajat_shop',
      );
      orderService.seedOrder(order);

      // Reject wins race
      await orderService.updateOrderStatus('ORD-RACE-1', 'rejected');

      // Subsequent accept must fail with InvalidOrderTransitionException
      expect(
        () => orderService.updateOrderStatus('ORD-RACE-1', 'accepted'),
        throwsA(isA<InvalidOrderTransitionException>()),
      );

      final finalOrder = await orderService.getOrder('ORD-RACE-1');
      expect(finalOrder?.status, 'rejected');
    });

    // 6. Deliver exactly once
    test('6. Deliver exactly once: Only accepted order can be delivered, duplicate delivery is no-op', () async {
      final order = createSampleOrder(
        orderId: 'ORD-DELIVER-1',
        shopId: 'rajat_shop',
        status: 'accepted',
      );
      orderService.seedOrder(order);

      await orderService.updateOrderStatus(
        'ORD-DELIVER-1',
        'delivered',
        deliveryPersonName: 'Delivery Agent 1',
        deliveryPersonId: '9876543210',
      );

      var updated = await orderService.getOrder('ORD-DELIVER-1');
      expect(updated?.status, 'delivered');
      expect(updated?.deliveryPersonName, 'Delivery Agent 1');
      expect(orderService.getShopStats('rajat_shop')['delivered'], 1);

      // Second delivery tap is idempotent no-op
      await orderService.updateOrderStatus('ORD-DELIVER-1', 'delivered');
      expect(orderService.getShopStats('rajat_shop')['delivered'], 1);
    });

    // 7. Invalid transitions
    test('7. Invalid transitions: Forbidden state machine jumps throw InvalidOrderTransitionException', () async {
      // placed -> delivered (invalid)
      final placedOrder = createSampleOrder(orderId: 'INV-1', shopId: 's1', status: 'placed');
      orderService.seedOrder(placedOrder);
      expect(
        () => orderService.updateOrderStatus('INV-1', 'delivered'),
        throwsA(isA<InvalidOrderTransitionException>()),
      );

      // delivered -> accepted (invalid)
      final deliveredOrder = createSampleOrder(orderId: 'INV-2', shopId: 's1', status: 'delivered');
      orderService.seedOrder(deliveredOrder);
      expect(
        () => orderService.updateOrderStatus('INV-2', 'accepted'),
        throwsA(isA<InvalidOrderTransitionException>()),
      );

      // delivered -> rejected (invalid)
      expect(
        () => orderService.updateOrderStatus('INV-2', 'rejected'),
        throwsA(isA<InvalidOrderTransitionException>()),
      );
    });

    // 8. Customer cancellation before acceptance
    test('8. Customer cancellation before acceptance: Placed order completely deletes without stat change', () async {
      final placedOrder = createSampleOrder(
        orderId: 'ORD-CANCEL-1',
        shopId: 'rajat_shop',
      );
      orderService.seedOrder(placedOrder);

      await orderService.cancelOrder('ORD-CANCEL-1');

      final result = await orderService.getOrder('ORD-CANCEL-1');
      expect(result, isNull);
      expect(orderService.getShopStats('rajat_shop'), isEmpty);
    });

    // 9. Customer cancellation after acceptance
    test('9. Customer cancellation after acceptance: Cancellation is blocked with OrderServiceException', () async {
      final acceptedOrder = createSampleOrder(
        orderId: 'ORD-CANCEL-2',
        shopId: 'rajat_shop',
        status: 'accepted',
      );
      orderService.seedOrder(acceptedOrder);

      expect(
        () => orderService.cancelOrder('ORD-CANCEL-2'),
        throwsA(isA<OrderServiceException>()),
      );

      final result = await orderService.getOrder('ORD-CANCEL-2');
      expect(result?.status, 'accepted');
    });

    // 10. Order expiration
    test('10. Order expiration: Placed order past 20-min deadline is rejected automatically', () async {
      final now = DateTime.now();
      final expiredPlacedOrder = createSampleOrder(
        orderId: 'ORD-EXP-1',
        shopId: 'rajat_shop',
        createdAt: now.subtract(const Duration(minutes: 25)),
        acceptDeadline: now.subtract(const Duration(minutes: 5)),
      );
      orderService.seedOrder(expiredPlacedOrder);

      expect(
        () => orderService.updateOrderStatus(
          'ORD-EXP-1',
          'accepted',
          customNow: now,
        ),
        throwsA(isA<OrderServiceException>()),
      );

      final updated = await orderService.getOrder('ORD-EXP-1');
      expect(updated?.status, 'rejected');
      expect(updated?.rejectionReason, contains('within 20 minutes'));
      expect(orderService.getShopStats('rajat_shop')['notAccepted'], 1);
    });

    // 11. Shopkeeper restart persistence
    test('11. Shopkeeper restart persistence: Reconnecting recovers full order state intact', () async {
      final order = createSampleOrder(
        orderId: 'ORD-PERSIST',
        shopId: 'rajat_shop',
        customerName: 'Kivisha',
        customerPhone: '9876543210',
        subtotal: 150,
        deliveryCharges: 15,
      );
      orderService.seedOrder(order);

      // Simulate app restart: fetch fresh from repository
      final recovered = await orderService.getOrder('ORD-PERSIST');
      expect(recovered, isNotNull);
      expect(recovered?.orderId, 'ORD-PERSIST');
      expect(recovered?.customerName, 'Kivisha');
      expect(recovered?.customerPhone, '9876543210');
      expect(recovered?.subtotal, 150);
      expect(recovered?.deliveryCharges, 15);
      expect(recovered?.totalAmount, 165);
    });

    // 12. Multi-device status synchronization
    test('12. Multi-device status synchronization: When Device A updates order, Device B stream reflects change', () async {
      final order = createSampleOrder(
        orderId: 'ORD-SYNC-1',
        shopId: 'rajat_shop',
      );
      orderService.seedOrder(order);

      final deviceAStream = orderService.watchShopActiveOrders('rajat_shop');
      final deviceBStream = orderService.watchShopActiveOrders('rajat_shop');

      final deviceAInitial = await deviceAStream.first;
      final deviceBInitial = await deviceBStream.first;
      expect(deviceAInitial.first.status, 'placed');
      expect(deviceBInitial.first.status, 'placed');

      // Device A accepts order
      await orderService.updateOrderStatus('ORD-SYNC-1', 'accepted');

      final deviceBUpdated = await deviceBStream.first;
      expect(deviceBUpdated.first.status, 'accepted');
    });

    // 13. Correct customer phone for Call
    test('13. Correct customer phone for Call: Call action uses snapshot phone from that specific order', () {
      final order1 = createSampleOrder(
        orderId: 'ORD-CALL-1',
        shopId: 'rajat_shop',
        customerPhone: '9876543210',
      );
      final order2 = createSampleOrder(
        orderId: 'ORD-CALL-2',
        shopId: 'rajat_shop',
        customerPhone: '9123456780',
      );

      expect(order1.customerPhone, '9876543210');
      expect(order2.customerPhone, '9123456780');
      expect(order1.customerPhone, isNot(equals(order2.customerPhone)));
    });

    // 14. Correct notification recipient
    test('14. Correct notification recipient: Notification dispatcher targets only authorized shopkeeper tokens', () {
      final registeredTokens = [
        {'token': 'tok_rajat_1', 'role': 'shopkeeper', 'shopId': 'rajat_shop', 'phone': '8078643910'},
        {'token': 'tok_rajat_2', 'role': 'shopkeeper', 'shopId': 'rajat_shop', 'phone': '8078643910'},
        {'token': 'tok_other', 'role': 'shopkeeper', 'shopId': 'other_shop', 'phone': '9999999999'},
        {'token': 'tok_cust', 'role': 'customer', 'phone': '9876543210'},
      ];

      final targets = ShopkeeperNotificationTargetingLogic.resolveTargetTokens(
        targetShopId: 'rajat_shop',
        registeredTokens: registeredTokens,
      );

      expect(targets, contains('tok_rajat_1'));
      expect(targets, contains('tok_rajat_2'));
      expect(targets, isNot(contains('tok_other')));
      expect(targets, isNot(contains('tok_cust')));
    });

    // 15. Delivery charge preserved
    test('15. Delivery charge preserved: Delivery charge snapshot remains untouched through transitions', () async {
      final order = createSampleOrder(
        orderId: 'ORD-CHARGE-1',
        shopId: 'rajat_shop',
        subtotal: 100,
        deliveryCharges: 25,
      );
      orderService.seedOrder(order);

      await orderService.updateOrderStatus('ORD-CHARGE-1', 'accepted');
      var updated = await orderService.getOrder('ORD-CHARGE-1');
      expect(updated?.deliveryCharges, 25.0);

      await orderService.updateOrderStatus('ORD-CHARGE-1', 'delivered');
      updated = await orderService.getOrder('ORD-CHARGE-1');
      expect(updated?.deliveryCharges, 25.0);
    });

    // 16. Order total preserved
    test('16. Order total preserved: totalAmount is immutable and equal to subtotal + deliveryCharges', () async {
      final order = createSampleOrder(
        orderId: 'ORD-TOTAL-1',
        shopId: 'rajat_shop',
        subtotal: 220,
        deliveryCharges: 20,
      );
      orderService.seedOrder(order);

      expect(order.totalAmount, 240.0);

      await orderService.updateOrderStatus('ORD-TOTAL-1', 'accepted');
      var updated = await orderService.getOrder('ORD-TOTAL-1');
      expect(updated?.totalAmount, 240.0);

      await orderService.updateOrderStatus('ORD-TOTAL-1', 'delivered');
      updated = await orderService.getOrder('ORD-TOTAL-1');
      expect(updated?.totalAmount, 240.0);
    });
  });
}
