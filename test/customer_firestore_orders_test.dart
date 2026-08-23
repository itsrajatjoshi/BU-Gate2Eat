// BU Gate2Eat — Customer Firestore Orders & Live Streams Test Suite (Phase 3 — Part 3.3)

import 'dart:async';

import 'package:bugate2eat_app/core/providers.dart';
import 'package:bugate2eat_app/features/orders/active_orders_screen.dart';
import 'package:bugate2eat_app/features/orders/order_detail_screen.dart';
import 'package:bugate2eat_app/features/orders/order_history_screen.dart';
import 'package:bugate2eat_app/models/order_model.dart';
import 'package:bugate2eat_app/services/local_storage_service.dart';
import 'package:bugate2eat_app/services/order_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockOrderService extends OrderService {
  final List<AppOrder> _orders = [];
  final StreamController<List<AppOrder>> activeOrdersController =
      StreamController<List<AppOrder>>.broadcast(sync: true);
  final StreamController<List<AppOrder>> historyOrdersController =
      StreamController<List<AppOrder>>.broadcast(sync: true);
  final Map<String, StreamController<AppOrder?>> singleOrderControllers = {};

  bool failStreams = false;
  String? lastCancelledOrderId;

  @override
  bool get isAvailable => true;

  void seedOrder(AppOrder order) {
    _orders.removeWhere((o) => o.orderId == order.orderId);
    _orders.add(order);
  }

  @override
  Stream<List<AppOrder>> watchCustomerActiveOrders({
    String? customerId,
    String? customerPhone,
  }) {
    if (failStreams) {
      return Stream.error(Exception('Firestore stream error'));
    }
    final active = _orders
        .where((o) => o.status == 'placed' || o.status == 'accepted')
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return Stream<List<AppOrder>>.multi((controller) {
      controller.add(active);
      final sub = activeOrdersController.stream.listen(
        controller.add,
        onError: controller.addError,
      );
      controller.onCancel = sub.cancel;
    });
  }

  @override
  Stream<List<AppOrder>> watchCustomerOrderHistory({
    String? customerId,
    String? customerPhone,
  }) {
    if (failStreams) {
      return Stream.error(Exception('Firestore stream error'));
    }
    final history = _orders
        .where((o) =>
            o.status == 'delivered' ||
            o.status == 'rejected' ||
            o.status == 'cancelled')
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return Stream<List<AppOrder>>.multi((controller) {
      controller.add(history);
      final sub = historyOrdersController.stream.listen(
        controller.add,
        onError: controller.addError,
      );
      controller.onCancel = sub.cancel;
    });
  }

  @override
  Stream<AppOrder?> watchOrder(String orderId) {
    if (failStreams) {
      return Stream.error(Exception('Firestore stream error'));
    }
    AppOrder? found;
    try {
      found = _orders.firstWhere((o) => o.orderId == orderId);
    } catch (_) {
      found = null;
    }

    final singleController = singleOrderControllers.putIfAbsent(
      orderId,
      () => StreamController<AppOrder?>.broadcast(sync: true),
    );

    return Stream<AppOrder?>.multi((controller) {
      controller.add(found);
      final sub = singleController.stream.listen(
        controller.add,
        onError: controller.addError,
      );
      controller.onCancel = sub.cancel;
    });
  }

  @override
  Future<void> cancelOrder(String orderId) async {
    lastCancelledOrderId = orderId;
    final index = _orders.indexWhere((o) => o.orderId == orderId);
    if (index != -1) {
      final updated = _orders[index].copyWith(
        status: 'cancelled',
        cancelledAt: DateTime.now(),
      );
      _orders[index] = updated;

      final active = _orders
          .where((o) => o.status == 'placed' || o.status == 'accepted')
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      final history = _orders
          .where((o) =>
              o.status == 'delivered' ||
              o.status == 'rejected' ||
              o.status == 'cancelled')
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

      activeOrdersController.add(active);
      historyOrdersController.add(history);
      singleOrderControllers[orderId]?.add(updated);
    }
  }

  @override
  Future<void> updateOrderStatus(
    String orderId,
    String newStatus, {
    String? rejectionReason,
  }) async {
    final index = _orders.indexWhere((o) => o.orderId == orderId);
    if (index != -1) {
      final updated = _orders[index].copyWith(
        status: newStatus,
        rejectionReason: rejectionReason,
        acceptedAt: newStatus == 'accepted' ? DateTime.now() : null,
        deliveredAt: newStatus == 'delivered' ? DateTime.now() : null,
        rejectedAt: newStatus == 'rejected' ? DateTime.now() : null,
      );
      _orders[index] = updated;

      final active = _orders
          .where((o) => o.status == 'placed' || o.status == 'accepted')
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      final history = _orders
          .where((o) =>
              o.status == 'delivered' ||
              o.status == 'rejected' ||
              o.status == 'cancelled')
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

      activeOrdersController.add(active);
      historyOrdersController.add(history);
      singleOrderControllers[orderId]?.add(updated);
    }
  }

  void dispose() {
    activeOrdersController.close();
    historyOrdersController.close();
    for (final s in singleOrderControllers.values) {
      s.close();
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;
  late MockOrderService mockOrderService;
  late LocalStorageService localStorageService;

  final now = DateTime.now();

  final orderPlaced = AppOrder(
    orderId: 'YB-TEST-001',
    shopId: 'rajat_shop',
    shopName: 'Rajat Shop',
    customerId: 'cust_9876543210',
    customerName: 'Aarav Sharma',
    customerPhone: '9876543210',
    items: const [
      OrderItem(
        menuItemId: 'item_1',
        name: 'Veg Steamed Momos',
        price: 80,
        quantity: 2,
      ),
    ],
    totalAmount: 160,
    status: 'placed',
    createdAt: now.subtract(const Duration(minutes: 10)),
  );

  final orderAccepted = AppOrder(
    orderId: 'YB-TEST-002',
    shopId: 'rajat_shop',
    shopName: 'Rajat Shop',
    customerId: 'cust_9876543210',
    customerName: 'Aarav Sharma',
    customerPhone: '9876543210',
    items: const [
      OrderItem(
        menuItemId: 'item_2',
        name: 'Masala Chai',
        price: 25,
        quantity: 2,
      ),
    ],
    totalAmount: 50,
    status: 'accepted',
    createdAt: now.subtract(const Duration(minutes: 5)),
  );

  final orderDelivered = AppOrder(
    orderId: 'YB-TEST-003',
    shopId: 'rajat_shop',
    shopName: 'Rajat Shop',
    customerId: 'cust_9876543210',
    customerName: 'Aarav Sharma',
    customerPhone: '9876543210',
    items: const [
      OrderItem(
        menuItemId: 'item_1',
        name: 'Veg Steamed Momos',
        price: 80,
        quantity: 1,
      ),
    ],
    totalAmount: 80,
    status: 'delivered',
    createdAt: now.subtract(const Duration(hours: 2)),
  );

  final orderRejected = AppOrder(
    orderId: 'YB-TEST-004',
    shopId: 'rajat_shop',
    shopName: 'Rajat Shop',
    customerId: 'cust_9876543210',
    customerName: 'Aarav Sharma',
    customerPhone: '9876543210',
    items: const [
      OrderItem(
        menuItemId: 'item_3',
        name: 'Paneer Roll',
        price: 100,
        quantity: 1,
      ),
    ],
    totalAmount: 100,
    status: 'rejected',
    rejectionReason: 'Item out of stock',
    createdAt: now.subtract(const Duration(hours: 3)),
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'user_name': 'Aarav Sharma',
      'user_phone': '9876543210',
      'customer_id': 'cust_9876543210',
    });
    final prefs = await SharedPreferences.getInstance();
    localStorageService = LocalStorageService(prefs);
    mockOrderService = MockOrderService();

    container = ProviderContainer(
      overrides: [
        localStorageServiceProvider.overrideWithValue(localStorageService),
        orderServiceProvider.overrideWithValue(mockOrderService),
      ],
    );
  });

  tearDown(() {
    mockOrderService.dispose();
    container.dispose();
  });

  group('Phase 3 — Part 3.3: Customer Active Orders & History Streams', () {
    testWidgets('1. Active Orders screen displays ONLY placed and accepted orders',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      // Seed placed, accepted, delivered, and rejected orders
      mockOrderService.seedOrder(orderPlaced);
      mockOrderService.seedOrder(orderAccepted);
      mockOrderService.seedOrder(orderDelivered);
      mockOrderService.seedOrder(orderRejected);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: ActiveOrdersScreen(),
          ),
        ),
      );
      await container.read(customerActiveOrdersStreamProvider.future);
      await tester.pump();

      // Active orders must be shown
      expect(find.textContaining('YB-TEST-001'), findsOneWidget);
      expect(find.textContaining('YB-TEST-002'), findsOneWidget);
      expect(find.textContaining('PLACED'), findsOneWidget);
      expect(find.textContaining('ACCEPTED'), findsOneWidget);

      // Terminal orders must NOT be shown in Active Orders
      expect(find.textContaining('YB-TEST-003'), findsNothing);
      expect(find.textContaining('YB-TEST-004'), findsNothing);
    });

    testWidgets(
        '2. Active Orders screen updates in real-time when order transitions from placed to accepted to delivered',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      mockOrderService.seedOrder(orderPlaced);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: ActiveOrdersScreen(),
          ),
        ),
      );
      await container.read(customerActiveOrdersStreamProvider.future);
      await tester.pump();

      expect(find.textContaining('YB-TEST-001'), findsOneWidget);
      expect(find.textContaining('PLACED'), findsOneWidget);

      // Transition placed -> accepted in Firestore
      await mockOrderService.updateOrderStatus('YB-TEST-001', 'accepted');
      await tester.pump();

      // UI automatically reflects accepted without restart
      expect(find.textContaining('YB-TEST-001'), findsOneWidget);
      expect(find.textContaining('ACCEPTED'), findsOneWidget);

      // Transition accepted -> delivered in Firestore
      await mockOrderService.updateOrderStatus('YB-TEST-001', 'delivered');
      await tester.pump();

      // Automatically removed from active orders screen
      expect(find.textContaining('YB-TEST-001'), findsNothing);
      expect(find.text('No active orders'), findsOneWidget);
    });

    testWidgets('3. Order History screen displays ONLY terminal orders (delivered, rejected, cancelled)',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      mockOrderService.seedOrder(orderPlaced);
      mockOrderService.seedOrder(orderAccepted);
      mockOrderService.seedOrder(orderDelivered);
      mockOrderService.seedOrder(orderRejected);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: OrderHistoryScreen(),
          ),
        ),
      );
      await container.read(customerOrderHistoryStreamProvider.future);
      await tester.pump();

      // Terminal orders must be shown in History
      expect(find.textContaining('YB-TEST-003'), findsOneWidget);
      expect(find.textContaining('YB-TEST-004'), findsOneWidget);
      expect(find.textContaining('DELIVERED'), findsOneWidget);
      expect(find.textContaining('REJECTED'), findsOneWidget);

      // Active orders must NOT be shown in History
      expect(find.textContaining('YB-TEST-001'), findsNothing);
      expect(find.textContaining('YB-TEST-002'), findsNothing);
    });

    testWidgets('4. Order Detail Screen: real-time watch, cancel button visibility, and real Firestore cancellation',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      mockOrderService.seedOrder(orderPlaced);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: OrderDetailScreen(orderId: 'YB-TEST-001'),
          ),
        ),
      );
      await container.read(singleOrderStreamProvider('YB-TEST-001').future);
      await tester.pump();

      // 1. In PLACED state: Cancel button is visible
      expect(find.textContaining('YB-TEST-001'), findsWidgets);
      expect(find.textContaining('Placed'), findsWidgets);
      final cancelBtn = find.widgetWithText(OutlinedButton, 'Cancel Order');
      expect(cancelBtn, findsOneWidget);

      // 2. Perform Customer Cancellation
      await tester.tap(cancelBtn);
      await tester.pump();

      // Verify confirmation dialog
      expect(find.text('Cancel Order?'), findsOneWidget);
      await tester.tap(find.widgetWithText(ElevatedButton, 'Yes, Cancel'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Verify orderService.cancelOrder was called
      expect(mockOrderService.lastCancelledOrderId, equals('YB-TEST-001'));

      // 3. Verify screen updates to CANCELLED state and cancel button is gone
      expect(find.textContaining('Cancelled'), findsWidgets);
      expect(find.text('This order was cancelled.'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Cancel Order'), findsNothing);
    });

    testWidgets('5. Order Detail Screen: Accepted state automatically hides Cancel Order button',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      mockOrderService.seedOrder(orderAccepted);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: OrderDetailScreen(orderId: 'YB-TEST-002'),
          ),
        ),
      );
      await container.read(singleOrderStreamProvider('YB-TEST-002').future);
      await tester.pump();

      expect(find.textContaining('Accepted'), findsWidgets);
      expect(find.text('Cancel Order'), findsNothing);
    });

    testWidgets('6. Order Detail Screen: Rejected state shows rejection reason banner',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      mockOrderService.seedOrder(orderRejected);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: OrderDetailScreen(orderId: 'YB-TEST-004'),
          ),
        ),
      );
      await container.read(singleOrderStreamProvider('YB-TEST-004').future);
      await tester.pump();

      expect(find.textContaining('Rejected'), findsWidgets);
      expect(find.textContaining('Item out of stock'), findsOneWidget);
    });

    testWidgets('7. Order Detail Screen: Unknown order ID shows clean Not Found screen',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: OrderDetailScreen(orderId: 'YB-NONEXISTENT-999'),
          ),
        ),
      );
      await container.read(singleOrderStreamProvider('YB-NONEXISTENT-999').future);
      await tester.pump();

      expect(find.text('Order not found'), findsOneWidget);
      expect(find.text('Go Back'), findsOneWidget);
    });
  });
}
