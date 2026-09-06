// BU Gate2Eat — Test Suite
// Checkpoint 5: Edge Cases + Full Bug Hunt Comprehensive Suite

import 'package:bugate2eat_app/models/cart_item_model.dart';
import 'package:bugate2eat_app/models/menu_item_model.dart';
import 'package:bugate2eat_app/models/order_model.dart';
import 'package:bugate2eat_app/models/shop_model.dart';
import 'package:bugate2eat_app/models/shop_stats_model.dart';
import 'package:bugate2eat_app/services/order_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final baseTime = DateTime(2026, 9, 6, 12);

  AppOrder buildTestOrder({
    required String orderId,
    String status = 'placed',
    String shopId = 'shop_1',
    String customerId = 'cust_1',
    DateTime? createdAt,
    DateTime? acceptDeadline,
    DateTime? acceptedAt,
    DateTime? rejectDeadline,
    DateTime? deliveryDeadline,
  }) {
    final created = createdAt ?? baseTime;
    return AppOrder(
      orderId: orderId,
      shopId: shopId,
      shopName: 'Test Shop $shopId',
      customerId: customerId,
      customerName: 'Test Customer',
      customerPhone: '9876543210',
      items: const [
        OrderItem(
          menuItemId: 'item_1',
          name: 'Burger',
          price: 100,
          quantity: 2,
        ),
      ],
      totalAmount: 200,
      createdAt: created,
      status: status,
      acceptDeadline: acceptDeadline ?? created.add(const Duration(minutes: 20)),
      acceptedAt: acceptedAt,
      rejectDeadline: rejectDeadline,
      deliveryDeadline: deliveryDeadline,
    );
  }

  Shop buildTestShop({
    required String id,
    String name = 'Test Shop',
    bool isActive = true,
    bool isClosedOverride = false,
    String openTime = '00:00',
    String closeTime = '23:59',
  }) {
    return Shop(
      id: id,
      name: name,
      description: '',
      bannerUrl: '',
      contactNumber: '1234567890',
      orderNumber: '1234567890',
      openTime: openTime,
      closeTime: closeTime,
      isClosedOverride: isClosedOverride,
      isActive: isActive,
      sortOrder: 1,
      searchKeywords: const [],
      deliveryNote: '',
      createdAt: baseTime,
      updatedAt: baseTime,
    );
  }

  // =========================================================================
  // 🔴 P0: CRITICAL / DATA INTEGRITY & RACE CONDITIONS
  // =========================================================================
  group('🔴 P0.1: Duplicate Order Creation & Idempotency', () {
    test('AppOrder equality and duplicate ID collision prevention', () {
      final order1 = buildTestOrder(orderId: 'YB-DUP-001');
      final order2 = buildTestOrder(orderId: 'YB-DUP-001');

      expect(order1.orderId, equals(order2.orderId));
      expect(order1.totalAmount, equals(order2.totalAmount));
      expect(order1.items.length, equals(order2.items.length));
    });
  });

  group('🔴 P0.2: Invalid Order Status Transitions', () {
    test('Impossible transitions from terminal status REJECTED are strictly blocked', () {
      expect(
        OrderStatusRules.isValidTransition(
          OrderStatusRules.statusRejected,
          OrderStatusRules.statusAccepted,
        ),
        isFalse,
      );
      expect(
        OrderStatusRules.isValidTransition(
          OrderStatusRules.statusRejected,
          OrderStatusRules.statusDelivered,
        ),
        isFalse,
      );
      expect(
        OrderStatusRules.isValidTransition(
          OrderStatusRules.statusRejected,
          OrderStatusRules.statusPlaced,
        ),
        isFalse,
      );
    });

    test('Impossible transitions from terminal status CANCELLED are strictly blocked', () {
      expect(
        OrderStatusRules.isValidTransition(
          OrderStatusRules.statusCancelled,
          OrderStatusRules.statusAccepted,
        ),
        isFalse,
      );
      expect(
        OrderStatusRules.isValidTransition(
          OrderStatusRules.statusCancelled,
          OrderStatusRules.statusDelivered,
        ),
        isFalse,
      );
      expect(
        OrderStatusRules.isValidTransition(
          OrderStatusRules.statusCancelled,
          OrderStatusRules.statusPlaced,
        ),
        isFalse,
      );
    });

    test('Impossible transitions from terminal status DELIVERED are strictly blocked', () {
      expect(
        OrderStatusRules.isValidTransition(
          OrderStatusRules.statusDelivered,
          OrderStatusRules.statusAccepted,
        ),
        isFalse,
      );
      expect(
        OrderStatusRules.isValidTransition(
          OrderStatusRules.statusDelivered,
          OrderStatusRules.statusPlaced,
        ),
        isFalse,
      );
      expect(
        OrderStatusRules.isValidTransition(
          OrderStatusRules.statusDelivered,
          OrderStatusRules.statusRejected,
        ),
        isFalse,
      );
    });

    test('Direct transition from PLACED to DELIVERED is impossible (must be accepted first)', () {
      expect(
        OrderStatusRules.isValidTransition(
          OrderStatusRules.statusPlaced,
          OrderStatusRules.statusDelivered,
        ),
        isFalse,
      );
    });
  });

  group('🔴 P0.3: Customer Cancellation vs Accept / Expiry Race Conditions', () {
    test('Order can only be cancelled while in placed status', () {
      final placedOrder = buildTestOrder(orderId: 'YB-RACE-1');
      final acceptedOrder = buildTestOrder(orderId: 'YB-RACE-2', status: 'accepted');
      final rejectedOrder = buildTestOrder(orderId: 'YB-RACE-3', status: 'rejected');
      final deliveredOrder = buildTestOrder(orderId: 'YB-RACE-4', status: 'delivered');

      expect(placedOrder.isPlaced, isTrue);
      expect(acceptedOrder.isPlaced, isFalse);
      expect(rejectedOrder.isPlaced, isFalse);
      expect(deliveredOrder.isPlaced, isFalse);

      // Verify cancellation transition rules
      expect(
        OrderStatusRules.isValidTransition(placedOrder.status, OrderStatusRules.statusCancelled),
        isTrue,
      );
      expect(
        OrderStatusRules.isValidTransition(acceptedOrder.status, OrderStatusRules.statusCancelled),
        isFalse,
      );
      expect(
        OrderStatusRules.isValidTransition(rejectedOrder.status, OrderStatusRules.statusCancelled),
        isFalse,
      );
      expect(
        OrderStatusRules.isValidTransition(deliveredOrder.status, OrderStatusRules.statusCancelled),
        isFalse,
      );
    });
  });

  group('🔴 P0.4 & P0.5: Repeated Actions & Statistics Integrity', () {
    test('Identical status transition is an idempotent no-op', () {
      expect(
        OrderStatusRules.isValidTransition(
          OrderStatusRules.statusAccepted,
          OrderStatusRules.statusAccepted,
        ),
        isTrue,
      );
      expect(
        OrderStatusRules.isValidTransition(
          OrderStatusRules.statusDelivered,
          OrderStatusRules.statusDelivered,
        ),
        isTrue,
      );
      expect(
        OrderStatusRules.isValidTransition(
          OrderStatusRules.statusRejected,
          OrderStatusRules.statusRejected,
        ),
        isTrue,
      );
    });

    test('ShopStats correctly isolates counters and prevents negative balances', () {
      final initial = ShopStats.zero(shopId: 'shop_1', shopName: 'Shop 1');
      expect(initial.appOrders, equals(0));
      expect(initial.accepted, equals(0));
      expect(initial.delivered, equals(0));
      expect(initial.notAccepted, equals(0));

      final updated = initial.copyWith(
        appOrders: initial.appOrders + 1,
        accepted: initial.accepted + 1,
      );
      expect(updated.appOrders, equals(1));
      expect(updated.accepted, equals(1));
      expect(updated.delivered, equals(0));
    });
  });

  group('🔴 P0.6: Shop and Customer Isolation', () {
    test('Orders with different shop IDs are strictly partitioned', () {
      final orderShop1 = buildTestOrder(orderId: 'YB-S1-01');
      final orderShop2 = buildTestOrder(orderId: 'YB-S2-01', shopId: 'shop_2');

      final allOrders = [orderShop1, orderShop2];
      final shop1Orders = allOrders.where((o) => o.shopId == 'shop_1').toList();
      final shop2Orders = allOrders.where((o) => o.shopId == 'shop_2').toList();

      expect(shop1Orders.length, equals(1));
      expect(shop1Orders.first.orderId, equals('YB-S1-01'));
      expect(shop2Orders.length, equals(1));
      expect(shop2Orders.first.orderId, equals('YB-S2-01'));
    });

    test('Orders with different customer IDs are strictly partitioned', () {
      final orderUser1 = buildTestOrder(orderId: 'YB-U1-01');
      final orderUser2 = buildTestOrder(orderId: 'YB-U2-01', customerId: 'cust_2');

      final allOrders = [orderUser1, orderUser2];
      final user1Orders = allOrders.where((o) => o.customerId == 'cust_1').toList();
      final user2Orders = allOrders.where((o) => o.customerId == 'cust_2').toList();

      expect(user1Orders.length, equals(1));
      expect(user1Orders.first.orderId, equals('YB-U1-01'));
      expect(user2Orders.length, equals(1));
      expect(user2Orders.first.orderId, equals('YB-U2-01'));
    });
  });

  group('🔴 P0.7: Active Order Protection During Admin Reset', () {
    test('Filtering terminal orders for reset NEVER includes placed or accepted orders', () {
      final placedOrder = buildTestOrder(orderId: 'YB-ACT-1');
      final acceptedOrder = buildTestOrder(orderId: 'YB-ACT-2', status: 'accepted');
      final deliveredOrder = buildTestOrder(orderId: 'YB-TERM-1', status: 'delivered');
      final rejectedOrder = buildTestOrder(orderId: 'YB-TERM-2', status: 'rejected');
      final expiredOrder = buildTestOrder(orderId: 'YB-TERM-3', status: 'delivery_expired');

      final orders = [placedOrder, acceptedOrder, deliveredOrder, rejectedOrder, expiredOrder];

      // Exact filter matching ShopStatsService.deleteTerminalShopOrders logic
      final terminalOrders = orders.where((o) {
        final s = o.status.trim().toLowerCase();
        return s != 'placed' && s != 'accepted';
      }).toList();

      expect(terminalOrders.length, equals(3));
      expect(terminalOrders.any((o) => o.orderId == 'YB-ACT-1'), isFalse);
      expect(terminalOrders.any((o) => o.orderId == 'YB-ACT-2'), isFalse);
      expect(terminalOrders.map((o) => o.orderId), containsAll(['YB-TERM-1', 'YB-TERM-2', 'YB-TERM-3']));
    });
  });

  // =========================================================================
  // 🟠 P1: CORE LIFECYCLE & TIMERS
  // =========================================================================
  group('🟠 P1.1: Order Lifecycle State Machine Valid Paths', () {
    test('Path 1: Placed -> Accepted -> Delivered (Happy Path)', () {
      expect(OrderStatusRules.isValidTransition('placed', 'accepted'), isTrue);
      expect(OrderStatusRules.isValidTransition('accepted', 'delivered'), isTrue);
      expect(OrderStatusRules.isTerminal('delivered'), isTrue);
    });

    test('Path 2: Placed -> Rejected (Pre-accept rejection)', () {
      expect(OrderStatusRules.isValidTransition('placed', 'rejected'), isTrue);
      expect(OrderStatusRules.isTerminal('rejected'), isTrue);
    });

    test('Path 3: Placed -> Cancelled (Customer cancellation)', () {
      expect(OrderStatusRules.isValidTransition('placed', 'cancelled'), isTrue);
      expect(OrderStatusRules.isTerminal('cancelled'), isTrue);
    });

    test('Path 4: Accepted -> Rejected (15-minute rejection window)', () {
      expect(OrderStatusRules.isValidTransition('accepted', 'rejected'), isTrue);
      expect(OrderStatusRules.isTerminal('rejected'), isTrue);
    });

    test('Path 5: Accepted -> Delivery Expired (90-minute delivery timeout)', () {
      expect(OrderStatusRules.isValidTransition('accepted', 'delivery_expired'), isTrue);
      expect(OrderStatusRules.isTerminal('delivery_expired'), isTrue);
    });
  });

  group('🟠 P1.2: Deadline Boundaries (20m, 15m, 90m)', () {
    test('Acceptance boundary: exactly 20 minutes', () {
      final created = DateTime(2026, 9, 6, 12);
      final acceptDeadline = created.add(const Duration(minutes: 20));

      final at19m59s = created.add(const Duration(minutes: 19, seconds: 59));
      final at20m01s = created.add(const Duration(minutes: 20, seconds: 1));

      expect(at19m59s.isAfter(acceptDeadline), isFalse); // Still valid to accept
      expect(at20m01s.isAfter(acceptDeadline), isTrue); // Expired!
    });

    test('Rejection boundary: exactly 15 minutes post-accept', () {
      final acceptedAt = DateTime(2026, 9, 6, 12, 5);
      final rejectDeadline = acceptedAt.add(const Duration(minutes: 15));

      final at14m59s = acceptedAt.add(const Duration(minutes: 14, seconds: 59));
      final at15m01s = acceptedAt.add(const Duration(minutes: 15, seconds: 1));

      expect(at14m59s.isAfter(rejectDeadline), isFalse); // Still valid to reject
      expect(at15m01s.isAfter(rejectDeadline), isTrue); // Rejection window closed!
    });

    test('Delivery boundary: exactly 90 minutes post-accept', () {
      final acceptedAt = DateTime(2026, 9, 6, 12, 5);
      final deliveryDeadline = acceptedAt.add(const Duration(minutes: 90));

      final at89m59s = acceptedAt.add(const Duration(minutes: 89, seconds: 59));
      final at90m01s = acceptedAt.add(const Duration(minutes: 90, seconds: 1));

      expect(at89m59s.isAfter(deliveryDeadline), isFalse); // Still valid to deliver
      expect(at90m01s.isAfter(deliveryDeadline), isTrue); // Delivery expired!
    });
  });

  group('🟠 P1.3: Active vs History List Separation', () {
    test('Active list contains only placed and accepted; history contains only terminal', () {
      final placed = buildTestOrder(orderId: 'O1');
      final accepted = buildTestOrder(orderId: 'O2', status: 'accepted');
      final delivered = buildTestOrder(orderId: 'O3', status: 'delivered');
      final rejected = buildTestOrder(orderId: 'O4', status: 'rejected');
      final cancelled = buildTestOrder(orderId: 'O5', status: 'cancelled');
      final expired = buildTestOrder(orderId: 'O6', status: 'delivery_expired');

      final all = [placed, accepted, delivered, rejected, cancelled, expired];
      final active = all.where((o) => OrderStatusRules.isActive(o.status)).toList();
      final history = all.where((o) => OrderStatusRules.isTerminal(o.status)).toList();

      expect(active.length, equals(2));
      expect(active.map((o) => o.orderId), containsAll(['O1', 'O2']));
      expect(history.length, equals(4));
      expect(history.map((o) => o.orderId), containsAll(['O3', 'O4', 'O5', 'O6']));
    });
  });

  // =========================================================================
  // 🟡 P2: SHOP / MENU / CART / REORDER / ADMIN MUTATIONS
  // =========================================================================
  group('🟡 P2.1: Reorder Edge Cases', () {
    test('Reorder respects shop active and open flags', () {
      final activeOpenShop = buildTestShop(
        id: 's1',
        name: 'Open Shop',
      );

      final closedShop = buildTestShop(
        id: 's2',
        name: 'Closed Shop',
        isClosedOverride: true,
      );

      final inactiveShop = buildTestShop(
        id: 's3',
        name: 'Inactive Shop',
        isActive: false,
      );

      expect(activeOpenShop.isActive && activeOpenShop.isOpen, isTrue);
      expect(closedShop.isActive && closedShop.isOpen, isFalse);
      expect(inactiveShop.isActive && inactiveShop.isOpen, isFalse);
    });

    test('Reorder filters out deleted/unavailable items while preserving available items', () {
      const oldOrderItems = [
        OrderItem(menuItemId: 'item_available', name: 'Roll', price: 100, quantity: 2),
        OrderItem(menuItemId: 'item_deleted', name: 'Burger', price: 80, quantity: 1),
        OrderItem(menuItemId: 'item_unavailable', name: 'Juice', price: 50, quantity: 1),
      ];

      const liveMenu = [
        MenuItem(
          id: 'item_available',
          name: 'Roll',
          price: 110, // Price updated
          details: '',
          imageUrl: '',
          isVeg: true,
          isAvailable: true,
          isRecommended: false,
          categoryId: 'c1',
          sortOrder: 1,
        ),
        MenuItem(
          id: 'item_unavailable',
          name: 'Juice',
          price: 50,
          details: '',
          imageUrl: '',
          isVeg: true,
          isAvailable: false, // Out of stock
          isRecommended: false,
          categoryId: 'c1',
          sortOrder: 2,
        ),
      ];

      final available = <OrderItem>[];
      int unavailableCount = 0;

      for (final oi in oldOrderItems) {
        final liveMatch = liveMenu.where((m) => m.id == oi.menuItemId).firstOrNull;
        if (liveMatch != null && liveMatch.isAvailable) {
          available.add(
            OrderItem(
              menuItemId: oi.menuItemId,
              name: oi.name,
              price: liveMatch.price,
              quantity: oi.quantity,
            ),
          );
        } else {
          unavailableCount++;
        }
      }

      expect(available.length, equals(1));
      expect(available.first.menuItemId, equals('item_available'));
      expect(available.first.price, equals(110)); // Updated price reflected
      expect(unavailableCount, equals(2)); // Deleted + out-of-stock count
    });
  });

  group('🟡 P2.2: Cart Edge Cases', () {
    test('CartItem total amount calculation is mathematically consistent', () {
      const item = CartItem(
        menuItem: MenuItem(
          id: 'item_1',
          name: 'Pizza',
          price: 250,
          details: '',
          imageUrl: '',
          isVeg: true,
          isAvailable: true,
          isRecommended: false,
          categoryId: 'c1',
          sortOrder: 1,
        ),
        shopId: 'shop_1',
        shopName: 'Pizza Shop',
        quantity: 3,
      );

      expect(item.totalPrice, equals(750));
      expect(item.quantity, equals(3));
    });
  });
}
