// BU Gate2Eat — Phase 3 / Part 3.4 Tests
// Shopkeeper Panel Real Firestore Orders & Lifecycle Verification Suite

import 'dart:async';

import 'package:bugate2eat_app/core/providers.dart';
import 'package:bugate2eat_app/models/order_model.dart';
import 'package:bugate2eat_app/panel/shopkeeper_panel/shopkeeper_order_history_screen.dart';
import 'package:bugate2eat_app/panel/shopkeeper_panel/shopkeeper_orders_screen.dart';
import 'package:bugate2eat_app/panel/shopkeeper_panel/widgets/shopkeeper_order_details_modal.dart';
import 'package:bugate2eat_app/services/order_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class MockShopkeeperOrderService extends OrderService {
  MockShopkeeperOrderService([List<AppOrder>? initialOrders])
      : _orders = List.from(initialOrders ?? []);

  final List<AppOrder> _orders;
  final Map<String, StreamController<List<AppOrder>>> _activeControllers = {};
  final Map<String, StreamController<List<AppOrder>>> _historyControllers = {};

  @override
  bool get isAvailable => true;

  void seedOrder(AppOrder order) {
    _orders.removeWhere((o) => o.orderId == order.orderId);
    _orders.add(order);
    _notifyStreams(order.shopId);
  }

  void _notifyStreams(String shopId) {
    final active = _orders
        .where((o) =>
            o.shopId == shopId &&
            (o.status == 'placed' || o.status == 'accepted'))
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    final history = _orders
        .where((o) =>
            o.shopId == shopId &&
            (o.status == 'delivered' ||
                o.status == 'rejected' ||
                o.status == 'cancelled'))
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    _activeControllers[shopId]?.add(active);
    _historyControllers[shopId]?.add(history);
  }

  @override
  Stream<List<AppOrder>> watchShopActiveOrders(String shopId) {
    final controller = _activeControllers.putIfAbsent(
      shopId,
      () => StreamController<List<AppOrder>>.broadcast(),
    );

    final active = _orders
        .where((o) =>
            o.shopId == shopId &&
            (o.status == 'placed' || o.status == 'accepted'))
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return Stream<List<AppOrder>>.multi((multiController) {
      multiController.add(active);
      final sub = controller.stream.listen(
        multiController.add,
        onError: multiController.addError,
      );
      multiController.onCancel = sub.cancel;
    });
  }

  @override
  Stream<List<AppOrder>> watchShopOrderHistory(String shopId) {
    final controller = _historyControllers.putIfAbsent(
      shopId,
      () => StreamController<List<AppOrder>>.broadcast(),
    );

    final history = _orders
        .where((o) =>
            o.shopId == shopId &&
            (o.status == 'delivered' ||
                o.status == 'rejected' ||
                o.status == 'cancelled'))
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return Stream<List<AppOrder>>.multi((multiController) {
      multiController.add(history);
      final sub = controller.stream.listen(
        multiController.add,
        onError: multiController.addError,
      );
      multiController.onCancel = sub.cancel;
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
    final index = _orders.indexWhere((o) => o.orderId == orderId);
    if (index != -1) {
      final current = _orders[index];
      if (!OrderStatusRules.isValidTransition(current.status, newStatus)) {
        throw InvalidOrderTransitionException(
          currentStatus: current.status,
          targetStatus: newStatus,
        );
      }
      final updated = current.copyWith(
        status: newStatus,
        rejectionReason: rejectionReason ?? '',
        deliveryPersonId: deliveryPersonId,
        deliveryPersonName: deliveryPersonName,
        acceptedAt: newStatus == 'accepted' ? DateTime.now() : null,
        deliveredAt: newStatus == 'delivered' ? DateTime.now() : null,
        rejectedAt: newStatus == 'rejected' ? DateTime.now() : null,
        cancelledAt: newStatus == 'cancelled' ? DateTime.now() : null,
      );
      _orders[index] = updated;
      _notifyStreams(updated.shopId);
    } else {
      throw OrderNotFoundException(orderId);
    }
  }

  @override
  Future<void> cancelOrder(String orderId) async {
    await updateOrderStatus(orderId, OrderStatusRules.statusCancelled);
  }

  @override
  Future<void> createOrder(AppOrder order, {DateTime? customNow}) async {
    seedOrder(order);
  }

  @override
  Stream<AppOrder?> watchOrder(String orderId) {
    return Stream.value(
      _orders.cast<AppOrder?>().firstWhere(
            (o) => o?.orderId == orderId,
            orElse: () => null,
          ),
    );
  }

  @override
  Stream<List<AppOrder>> watchCustomerActiveOrders({
    String? customerId,
    String? customerPhone,
  }) {
    final active = _orders
        .where((o) => o.status == 'placed' || o.status == 'accepted')
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return Stream.value(active);
  }

  @override
  Stream<List<AppOrder>> watchCustomerOrderHistory({
    String? customerId,
    String? customerPhone,
  }) {
    final history = _orders
        .where((o) =>
            o.status == 'delivered' ||
            o.status == 'rejected' ||
            o.status == 'cancelled')
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return Stream.value(history);
  }

  @override
  Future<AppOrder?> getOrder(String orderId) async {
    return _orders.cast<AppOrder?>().firstWhere(
          (o) => o?.orderId == orderId,
          orElse: () => null,
        );
  }

  void dispose() {
    for (final c in _activeControllers.values) {
      c.close();
    }
    for (final c in _historyControllers.values) {
      c.close();
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final fixedTime = DateTime(2026, 8, 23, 12, 0, 0);

  AppOrder createTestOrder({
    required String orderId,
    required String shopId,
    required String shopName,
    required String status,
    String customerName = 'Rahul Sharma',
    String customerPhone = '9876543210',
    String? rejectionReason,
    DateTime? createdAt,
  }) {
    return AppOrder(
      orderId: orderId,
      shopId: shopId,
      shopName: shopName,
      customerId: 'cust_123',
      customerName: customerName,
      customerPhone: customerPhone,
      items: [
        const OrderItem(
          menuItemId: 'item_1',
          name: 'Butter Naan',
          price: 40,
          quantity: 2,
        ),
        const OrderItem(
          menuItemId: 'item_2',
          name: 'Paneer Butter Masala',
          price: 180,
          quantity: 1,
        ),
      ],
      totalAmount: 260,
      specialInstructions: 'Less spicy please',
      status: status,
      rejectionReason: rejectionReason ?? '',
      createdAt: createdAt ?? fixedTime,
    );
  }

  Widget createTestWidget({
    required Widget child,
    required MockShopkeeperOrderService mockService,
    String currentShopId = 'shop_maggi_hotspot',
  }) {
    return ProviderScope(
      overrides: [
        orderServiceProvider.overrideWithValue(mockService),
        currentShopkeeperShopIdProvider.overrideWith((ref) => currentShopId),
      ],
      child: MaterialApp(
        home: child,
      ),
    );
  }

  group('Phase 3 — Part 3.4: Shopkeeper Firestore Order Streams & Mutations', () {
    late MockShopkeeperOrderService mockService;

    setUp(() {
      mockService = MockShopkeeperOrderService();
    });

    tearDown(() {
      mockService.dispose();
    });

    testWidgets('1. Shopkeeper Active Orders shows ONLY placed and accepted orders',
        (tester) async {
      mockService.seedOrder(createTestOrder(
        orderId: 'ORD_PLACED_1',
        shopId: 'shop_maggi_hotspot',
        shopName: 'Maggi Hotspot',
        status: 'placed',
        customerName: 'Rahul Placed',
        createdAt: fixedTime.subtract(const Duration(minutes: 5)),
      ));
      mockService.seedOrder(createTestOrder(
        orderId: 'ORD_ACCEPTED_1',
        shopId: 'shop_maggi_hotspot',
        shopName: 'Maggi Hotspot',
        status: 'accepted',
        customerName: 'Rahul Accepted',
        createdAt: fixedTime.subtract(const Duration(minutes: 3)),
      ));
      mockService.seedOrder(createTestOrder(
        orderId: 'ORD_DELIVERED_1',
        shopId: 'shop_maggi_hotspot',
        shopName: 'Maggi Hotspot',
        status: 'delivered',
        customerName: 'Rahul Delivered',
        createdAt: fixedTime.subtract(const Duration(minutes: 20)),
      ));
      mockService.seedOrder(createTestOrder(
        orderId: 'ORD_REJECTED_1',
        shopId: 'shop_maggi_hotspot',
        shopName: 'Maggi Hotspot',
        status: 'rejected',
        customerName: 'Rahul Rejected',
        createdAt: fixedTime.subtract(const Duration(minutes: 15)),
      ));
      mockService.seedOrder(createTestOrder(
        orderId: 'ORD_CANCELLED_1',
        shopId: 'shop_maggi_hotspot',
        shopName: 'Maggi Hotspot',
        status: 'cancelled',
        customerName: 'Rahul Cancelled',
        createdAt: fixedTime.subtract(const Duration(minutes: 10)),
      ));

      await tester.pumpWidget(
        createTestWidget(
          child: const ShopkeeperOrdersScreen(shopId: 'shop_maggi_hotspot'),
          mockService: mockService,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Active orders: Placed and Accepted appear
      expect(find.text('Rahul Placed'), findsOneWidget);
      expect(find.text('Rahul Accepted'), findsOneWidget);
      expect(find.text('PLACED'), findsOneWidget);
      expect(find.text('ACCEPTED'), findsOneWidget);

      // Terminal orders: Delivered, Rejected, Cancelled do NOT appear
      expect(find.text('Rahul Delivered'), findsNothing);
      expect(find.text('Rahul Rejected'), findsNothing);
      expect(find.text('Rahul Cancelled'), findsNothing);
    });

    testWidgets('2. Strict Shop Isolation: Shop A orders are never visible to Shop B',
        (tester) async {
      mockService.seedOrder(createTestOrder(
        orderId: 'ORD_SHOP_A_1',
        shopId: 'shop_A',
        shopName: 'Shop A',
        status: 'placed',
        customerName: 'Customer For Shop A',
      ));
      mockService.seedOrder(createTestOrder(
        orderId: 'ORD_SHOP_B_1',
        shopId: 'shop_B',
        shopName: 'Shop B',
        status: 'placed',
        customerName: 'Customer For Shop B',
      ));

      // Render for Shop A
      await tester.pumpWidget(
        createTestWidget(
          child: const ShopkeeperOrdersScreen(shopId: 'shop_A'),
          mockService: mockService,
          currentShopId: 'shop_A',
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Customer For Shop A'), findsOneWidget);
      expect(find.text('Customer For Shop B'), findsNothing);
    });

    testWidgets('3. Shopkeeper Order History shows ONLY terminal orders (delivered, rejected, cancelled)',
        (tester) async {
      mockService.seedOrder(createTestOrder(
        orderId: 'ORD_HIST_DELIVERED',
        shopId: 'shop_maggi_hotspot',
        shopName: 'Maggi Hotspot',
        status: 'delivered',
        customerName: 'Delivered Customer',
        createdAt: fixedTime.subtract(const Duration(minutes: 30)),
      ));
      mockService.seedOrder(createTestOrder(
        orderId: 'ORD_HIST_REJECTED',
        shopId: 'shop_maggi_hotspot',
        shopName: 'Maggi Hotspot',
        status: 'rejected',
        rejectionReason: 'Items not available',
        customerName: 'Rejected Customer',
        createdAt: fixedTime.subtract(const Duration(minutes: 20)),
      ));
      mockService.seedOrder(createTestOrder(
        orderId: 'ORD_HIST_CANCELLED',
        shopId: 'shop_maggi_hotspot',
        shopName: 'Maggi Hotspot',
        status: 'cancelled',
        customerName: 'Cancelled Customer',
        createdAt: fixedTime.subtract(const Duration(minutes: 10)),
      ));
      mockService.seedOrder(createTestOrder(
        orderId: 'ORD_ACTIVE_PLACED',
        shopId: 'shop_maggi_hotspot',
        shopName: 'Maggi Hotspot',
        status: 'placed',
        customerName: 'Active Customer',
        createdAt: fixedTime,
      ));

      await tester.pumpWidget(
        createTestWidget(
          child: const ShopkeeperOrderHistoryScreen(shopId: 'shop_maggi_hotspot'),
          mockService: mockService,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Terminal orders appear
      expect(find.text('Delivered Customer'), findsOneWidget);
      expect(find.text('Rejected Customer'), findsOneWidget);
      expect(find.text('Cancelled Customer'), findsOneWidget);
      expect(find.text('DELIVERED'), findsOneWidget);
      expect(find.text('REJECTED'), findsOneWidget);
      expect(find.text('CANCELLED'), findsOneWidget);
      expect(find.text('Reason: Items not available'), findsOneWidget);

      // Active order does NOT appear in history
      expect(find.text('Active Customer'), findsNothing);
    });

    testWidgets('4. Accept Flow: Placed order modal displays Accept & Reject, updates status on accept',
        (tester) async {
      final placedOrder = createTestOrder(
        orderId: 'ORD_PLACED_ACCEPT_TEST',
        shopId: 'shop_maggi_hotspot',
        shopName: 'Maggi Hotspot',
        status: 'placed',
      );
      mockService.seedOrder(placedOrder);

      await tester.pumpWidget(
        createTestWidget(
          child: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () => ShopkeeperOrderDetailsModal.show(
                  context,
                  order: placedOrder,
                ),
                child: const Text('Open Modal'),
              ),
            ),
          ),
          mockService: mockService,
        ),
      );
      await tester.pumpAndSettle();

      // Open Modal
      await tester.tap(find.text('Open Modal'));
      await tester.pumpAndSettle();

      expect(find.text('Accept Order'), findsOneWidget);
      expect(find.text('Reject'), findsOneWidget);

      // Tap Accept Order
      await tester.tap(find.text('Accept Order'));
      await tester.pumpAndSettle();

      // Accept Confirmation Dialog appears
      expect(find.text('Accept Order?'), findsOneWidget);

      // Confirm Accept (button in dialog is 'Accept Order')
      await tester.tap(find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(ElevatedButton, 'Accept Order'),
      ));
      await tester.pumpAndSettle();

      // Modal closes and success snackbar appears
      expect(find.text('Order #ORD_PLACED_ACCEPT_TEST accepted successfully'),
          findsOneWidget);
    });

    testWidgets('5. Reject Flow: Order modal displays rejection dialog and saves rejection reason',
        (tester) async {
      final placedOrder = createTestOrder(
        orderId: 'ORD_PLACED_REJECT_TEST',
        shopId: 'shop_maggi_hotspot',
        shopName: 'Maggi Hotspot',
        status: 'placed',
      );
      mockService.seedOrder(placedOrder);

      await tester.pumpWidget(
        createTestWidget(
          child: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () => ShopkeeperOrderDetailsModal.show(
                  context,
                  order: placedOrder,
                ),
                child: const Text('Open Modal'),
              ),
            ),
          ),
          mockService: mockService,
        ),
      );
      await tester.pumpAndSettle();

      // Open Modal
      await tester.tap(find.text('Open Modal'));
      await tester.pumpAndSettle();

      // Tap Reject
      await tester.tap(find.text('Reject'));
      await tester.pumpAndSettle();

      // Reject Dialog appears with reasons
      expect(find.text('Reject Order?'), findsOneWidget);
      expect(find.text('Items not available'), findsOneWidget);

      // Confirm Reject (button in dialog is 'Reject Order')
      await tester.tap(find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(ElevatedButton, 'Reject Order'),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Order #ORD_PLACED_REJECT_TEST rejected'), findsOneWidget);
    });

    testWidgets('6. Mark Delivered Flow: Accepted order modal displays Mark as Delivered, completes order',
        (tester) async {
      final acceptedOrder = createTestOrder(
        orderId: 'ORD_ACCEPTED_DELIVER_TEST',
        shopId: 'shop_maggi_hotspot',
        shopName: 'Maggi Hotspot',
        status: 'accepted',
      );
      mockService.seedOrder(acceptedOrder);

      await tester.pumpWidget(
        createTestWidget(
          child: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () => ShopkeeperOrderDetailsModal.show(
                  context,
                  order: acceptedOrder,
                ),
                child: const Text('Open Modal'),
              ),
            ),
          ),
          mockService: mockService,
        ),
      );
      await tester.pumpAndSettle();

      // Open Modal
      await tester.tap(find.text('Open Modal'));
      await tester.pumpAndSettle();

      expect(find.text('Mark as Delivered'), findsOneWidget);
      expect(find.text('Reject Order'), findsOneWidget);

      // Tap Mark as Delivered
      await tester.tap(find.text('Mark as Delivered'));
      await tester.pumpAndSettle();

      // Mark Delivered Confirmation Dialog appears
      expect(find.text('Mark as Delivered?'), findsOneWidget);

      // Confirm (button in dialog is 'Mark as Delivered')
      await tester.tap(find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(ElevatedButton, 'Mark as Delivered'),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Order #ORD_ACCEPTED_DELIVER_TEST marked as delivered'),
          findsOneWidget);
    });

    testWidgets('7. Terminal Orders Modal is Read-Only (no action buttons for delivered, rejected, cancelled)',
        (tester) async {
      final deliveredOrder = createTestOrder(
        orderId: 'ORD_TERMINAL_TEST',
        shopId: 'shop_maggi_hotspot',
        shopName: 'Maggi Hotspot',
        status: 'delivered',
      );
      mockService.seedOrder(deliveredOrder);

      await tester.pumpWidget(
        createTestWidget(
          child: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () => ShopkeeperOrderDetailsModal.show(
                  context,
                  order: deliveredOrder,
                ),
                child: const Text('Open Modal'),
              ),
            ),
          ),
          mockService: mockService,
        ),
      );
      await tester.pumpAndSettle();

      // Open Modal
      await tester.tap(find.text('Open Modal'));
      await tester.pumpAndSettle();

      // Read only: no action buttons
      expect(find.text('Accept Order'), findsNothing);
      expect(find.text('Mark as Delivered'), findsNothing);
      expect(find.text('Reject'), findsNothing);
      expect(find.text('Reject Order'), findsNothing);
      expect(find.text('DELIVERED'), findsOneWidget);
    });

    testWidgets('8. OrderStatusRules: Enforces valid transitions and rejects invalid ones',
        (tester) async {
      // Valid transitions
      expect(OrderStatusRules.isValidTransition('placed', 'accepted'), isTrue);
      expect(OrderStatusRules.isValidTransition('placed', 'rejected'), isTrue);
      expect(OrderStatusRules.isValidTransition('placed', 'cancelled'), isTrue);
      expect(OrderStatusRules.isValidTransition('accepted', 'delivered'), isTrue);
      expect(OrderStatusRules.isValidTransition('accepted', 'rejected'), isTrue);

      // Invalid transitions
      expect(OrderStatusRules.isValidTransition('delivered', 'accepted'), isFalse);
      expect(OrderStatusRules.isValidTransition('delivered', 'placed'), isFalse);
      expect(OrderStatusRules.isValidTransition('cancelled', 'accepted'), isFalse);
      expect(OrderStatusRules.isValidTransition('cancelled', 'delivered'), isFalse);
      expect(OrderStatusRules.isValidTransition('rejected', 'delivered'), isFalse);
      expect(OrderStatusRules.isValidTransition('rejected', 'accepted'), isFalse);
    });
  });
}
