// BU Gate2Eat — Active Orders & Order Details Unit & Widget Test Suite

import 'package:bugate2eat_app/core/providers.dart';
import 'package:bugate2eat_app/features/orders/active_orders_screen.dart';
import 'package:bugate2eat_app/features/orders/order_detail_screen.dart';
import 'package:bugate2eat_app/features/orders/order_history_screen.dart';
import 'package:bugate2eat_app/models/order_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Active Orders & Order History State Separation Tests', () {
    late DummyOrdersNotifier notifier;

    final orderPlaced = AppOrder(
      orderId: 'YB-1001',
      shopId: 'rajat_shop',
      shopName: 'Rajat Shop',
      customerName: 'Test Student',
      customerPhone: '9876543210',
      items: const [
        OrderItem(
          menuItemId: 'veg_steam_momos',
          name: 'Veg Steam Momos',
          price: 60,
          quantity: 2,
        ),
      ],
      totalAmount: 120,
      status: 'placed',
      createdAt: DateTime.now().subtract(const Duration(minutes: 10)),
    );

    final orderAccepted = AppOrder(
      orderId: 'YB-1002',
      shopId: 'nayan_shop',
      shopName: 'Nayan Shop',
      customerName: 'Test Student',
      customerPhone: '9876543210',
      items: const [
        OrderItem(
          menuItemId: 'paneer_roll',
          name: 'Paneer Roll',
          price: 90,
          quantity: 1,
        ),
      ],
      totalAmount: 90,
      status: 'accepted',
      createdAt: DateTime.now().subtract(const Duration(minutes: 5)),
    );

    final orderDelivered = AppOrder(
      orderId: 'YB-1003',
      shopId: 'rajat_shop',
      shopName: 'Rajat Shop',
      customerName: 'Test Student',
      customerPhone: '9876543210',
      items: const [
        OrderItem(
          menuItemId: 'chai',
          name: 'Chai',
          price: 20,
          quantity: 2,
        ),
      ],
      totalAmount: 40,
      status: 'delivered',
      createdAt: DateTime.now().subtract(const Duration(hours: 1)),
    );

    final orderCancelled = AppOrder(
      orderId: 'YB-1004',
      shopId: 'rajat_shop',
      shopName: 'Rajat Shop',
      customerName: 'Test Student',
      customerPhone: '9876543210',
      items: const [
        OrderItem(
          menuItemId: 'fries',
          name: 'Fries',
          price: 80,
          quantity: 1,
        ),
      ],
      totalAmount: 80,
      status: 'cancelled',
      createdAt: DateTime.now().subtract(const Duration(hours: 2)),
    );

    final orderRejected = AppOrder(
      orderId: 'YB-1005',
      shopId: 'nayan_shop',
      shopName: 'Nayan Shop',
      customerName: 'Test Student',
      customerPhone: '9876543210',
      items: const [
        OrderItem(
          menuItemId: 'burger',
          name: 'Burger',
          price: 150,
          quantity: 1,
        ),
      ],
      totalAmount: 150,
      status: 'rejected',
      rejectionReason: 'Shop is currently closing',
      createdAt: DateTime.now().subtract(const Duration(hours: 3)),
    );

    setUp(() {
      notifier = DummyOrdersNotifier();
    });

    test('Initial orders list is empty', () {
      expect(notifier.state.isEmpty, isTrue);
    });

    test('Active vs History orders are strictly separated with zero overlap', () {
      notifier.addOrder(orderPlaced);
      notifier.addOrder(orderAccepted);
      notifier.addOrder(orderDelivered);
      notifier.addOrder(orderCancelled);
      notifier.addOrder(orderRejected);

      expect(notifier.state.length, equals(5));

      final active = notifier.state
          .where((o) => o.status == 'placed' || o.status == 'accepted')
          .toList();
      final history = notifier.state
          .where((o) =>
              o.status == 'delivered' ||
              o.status == 'rejected' ||
              o.status == 'cancelled')
          .toList();

      expect(active.length, equals(2));
      expect(history.length, equals(3));

      // Check IDs in Active Orders
      final activeIds = active.map((o) => o.orderId).toSet();
      expect(activeIds, containsAll(['YB-1001', 'YB-1002']));
      expect(activeIds.contains('YB-1003'), isFalse);
      expect(activeIds.contains('YB-1004'), isFalse);
      expect(activeIds.contains('YB-1005'), isFalse);

      // Check IDs in History Orders
      final historyIds = history.map((o) => o.orderId).toSet();
      expect(historyIds, containsAll(['YB-1003', 'YB-1004', 'YB-1005']));
      expect(historyIds.contains('YB-1001'), isFalse);
      expect(historyIds.contains('YB-1002'), isFalse);
    });

    test('Cancelling a placed order immediately moves it to history', () {
      notifier.addOrder(orderPlaced);
      notifier.addOrder(orderAccepted);

      // Initially 2 active, 0 history
      expect(
        notifier.state
            .where((o) => o.status == 'placed' || o.status == 'accepted')
            .length,
        equals(2),
      );
      expect(
        notifier.state
            .where((o) =>
                o.status == 'delivered' ||
                o.status == 'rejected' ||
                o.status == 'cancelled')
            .length,
        equals(0),
      );

      // Cancel YB-1001
      notifier.cancelOrder('YB-1001');

      // Now 1 active, 1 history
      final active = notifier.state
          .where((o) => o.status == 'placed' || o.status == 'accepted')
          .toList();
      final history = notifier.state
          .where((o) =>
              o.status == 'delivered' ||
              o.status == 'rejected' ||
              o.status == 'cancelled')
          .toList();

      expect(active.length, equals(1));
      expect(active.first.orderId, equals('YB-1002'));
      expect(history.length, equals(1));
      expect(history.first.orderId, equals('YB-1001'));
      expect(history.first.status, equals('cancelled'));
    });
  });

  group('OrderHistoryScreen Widget Render Tests', () {
    testWidgets('Renders empty state when no terminal orders exist',
        (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: OrderHistoryScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Orders'), findsOneWidget);
      expect(find.text('No order history yet'), findsOneWidget);
      expect(
        find.text(
          'Your completed and rejected orders will appear here.',
        ),
        findsOneWidget,
      );
    });

    testWidgets(
        'Renders terminal orders (delivered, rejected, cancelled) with correct badges',
        (tester) async {
      final container = ProviderContainer();
      final now = DateTime.now();

      container.read(dummyOrdersProvider.notifier).addOrder(
            AppOrder(
              orderId: 'YB-1003',
              shopId: 'rajat_shop',
              shopName: 'Rajat Shop',
              customerName: 'Test Student',
              customerPhone: '9876543210',
              items: const [
                OrderItem(
                  menuItemId: 'chai',
                  name: 'Special Masala Chai',
                  price: 20,
                  quantity: 2,
                ),
              ],
              totalAmount: 40,
              status: 'delivered',
              createdAt: now.subtract(const Duration(minutes: 30)),
            ),
          );

      container.read(dummyOrdersProvider.notifier).addOrder(
            AppOrder(
              orderId: 'YB-1004',
              shopId: 'nayan_shop',
              shopName: 'Nayan Shop',
              customerName: 'Test Student',
              customerPhone: '9876543210',
              items: const [
                OrderItem(
                  menuItemId: 'burger',
                  name: 'Chicken Burger',
                  price: 150,
                  quantity: 1,
                ),
              ],
              totalAmount: 150,
              status: 'rejected',
              rejectionReason: 'Kitchen closed for dinner',
              createdAt: now.subtract(const Duration(minutes: 15)),
            ),
          );

      container.read(dummyOrdersProvider.notifier).addOrder(
            AppOrder(
              orderId: 'YB-1005',
              shopId: 'rajat_shop',
              shopName: 'Rajat Shop',
              customerName: 'Test Student',
              customerPhone: '9876543210',
              items: const [
                OrderItem(
                  menuItemId: 'fries',
                  name: 'Peri Peri Fries',
                  price: 80,
                  quantity: 1,
                ),
              ],
              totalAmount: 80,
              status: 'cancelled',
              createdAt: now,
            ),
          );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: OrderHistoryScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Check status badges
      expect(find.text('DELIVERED'), findsOneWidget);
      expect(find.text('REJECTED'), findsOneWidget);
      expect(find.text('CANCELLED'), findsOneWidget);

      // Check rejection reason
      expect(find.text('Reason: Kitchen closed for dinner'), findsOneWidget);

      // Check order totals and View Details absence
      expect(find.text('2 items • ₹40'), findsOneWidget);
      expect(find.text('1 item • ₹150'), findsOneWidget);
      expect(find.text('1 item • ₹80'), findsOneWidget);
      expect(find.text('View Details'), findsNothing);
    });
  });

  group('ActiveOrdersScreen Widget Render Tests', () {
    testWidgets('Renders empty state when no active orders exist',
        (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: ActiveOrdersScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Active Orders'), findsOneWidget);
      expect(find.text('No active orders'), findsOneWidget);
      expect(find.text('Browse Shops'), findsOneWidget);
    });

    testWidgets('Renders multiple active order cards with correct details',
        (tester) async {
      final container = ProviderContainer();
      final now = DateTime.now();

      container.read(dummyOrdersProvider.notifier).addOrder(
            AppOrder(
              orderId: 'YB-1001',
              shopId: 'rajat_shop',
              shopName: 'Rajat Shop',
              customerName: 'Test Student',
              customerPhone: '9876543210',
              items: const [
                OrderItem(
                  menuItemId: 'veg_steam_momos',
                  name: 'Veg Steam Momos',
                  price: 60,
                  quantity: 2,
                ),
              ],
              totalAmount: 120,
              status: 'placed',
              createdAt: now,
            ),
          );

      container.read(dummyOrdersProvider.notifier).addOrder(
            AppOrder(
              orderId: 'YB-1002',
              shopId: 'nayan_shop',
              shopName: 'Nayan Shop',
              customerName: 'Test Student',
              customerPhone: '9876543210',
              items: const [
                OrderItem(
                  menuItemId: 'paneer_roll',
                  name: 'Paneer Roll',
                  price: 90,
                  quantity: 1,
                ),
              ],
              totalAmount: 90,
              status: 'accepted',
              createdAt: now,
            ),
          );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: ActiveOrdersScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Check shop names
      expect(find.text('Rajat Shop'), findsOneWidget);
      expect(find.text('Nayan Shop'), findsOneWidget);

      // Check status pills
      expect(find.text('PLACED'), findsOneWidget);
      expect(find.text('ACCEPTED'), findsOneWidget);

      // Check order totals and View Details absence
      expect(find.text('2 items • ₹120'), findsOneWidget);
      expect(find.text('1 item • ₹90'), findsOneWidget);
      expect(find.text('View Details'), findsNothing);
    });
  });

  group('OrderDetailScreen Lifecycle & Multi-Order Render Tests', () {
    testWidgets('Placed order displays Cancel button and correct items',
        (tester) async {
      final now = DateTime.now();
      final order = AppOrder(
        orderId: 'YB-1001',
        shopId: 'rajat_shop',
        shopName: 'Rajat Shop',
        customerName: 'Rajat',
        customerPhone: '9876543210',
        items: const [
          OrderItem(
            menuItemId: 'veg_steam_momos',
            name: 'Veg Steam Momos',
            price: 60,
            quantity: 2,
          ),
        ],
        totalAmount: 120,
        specialInstructions: 'Extra spicy please',
        status: 'placed',
        createdAt: now,
      );

      final container = ProviderContainer();
      container.read(dummyOrdersProvider.notifier).addOrder(order);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: OrderDetailScreen(orderId: 'YB-1001'),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Order Details'), findsOneWidget);
      expect(find.text('Rajat Shop'), findsOneWidget);
      expect(find.text('Veg Steam Momos'), findsOneWidget);
      expect(find.text('Extra spicy please'), findsOneWidget);
      expect(find.text('Cancel Order'), findsOneWidget);
    });

    testWidgets('Accepted order hides Cancel button', (tester) async {
      final now = DateTime.now();
      final order = AppOrder(
        orderId: 'YB-1002',
        shopId: 'nayan_shop',
        shopName: 'Nayan Shop',
        customerName: 'Rajat',
        customerPhone: '9876543210',
        items: const [
          OrderItem(
            menuItemId: 'chicken_burger',
            name: 'Chicken Burger',
            price: 150,
            quantity: 1,
          ),
        ],
        totalAmount: 150,
        status: 'accepted',
        createdAt: now,
      );

      final container = ProviderContainer();
      container.read(dummyOrdersProvider.notifier).addOrder(order);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: OrderDetailScreen(orderId: 'YB-1002'),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Nayan Shop'), findsOneWidget);
      expect(find.text('Chicken Burger'), findsOneWidget);
      expect(find.text('Cancel Order'), findsNothing);
    });

    testWidgets('Delivered order renders correctly without Cancel button',
        (tester) async {
      final now = DateTime.now();
      final order = AppOrder(
        orderId: 'YB-1003',
        shopId: 'rajat_shop',
        shopName: 'Rajat Shop',
        customerName: 'Rajat',
        customerPhone: '9876543210',
        items: const [
          OrderItem(
            menuItemId: 'chai',
            name: 'Special Masala Chai',
            price: 20,
            quantity: 2,
          ),
        ],
        totalAmount: 40,
        status: 'delivered',
        createdAt: now,
      );

      final container = ProviderContainer();
      container.read(dummyOrdersProvider.notifier).addOrder(order);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: OrderDetailScreen(orderId: 'YB-1003'),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Delivered ✅'), findsOneWidget);
      expect(find.text('Cancel Order'), findsNothing);
    });

    testWidgets('Rejected order renders rejection banner and reason',
        (tester) async {
      final now = DateTime.now();
      final order = AppOrder(
        orderId: 'YB-1004',
        shopId: 'rajat_shop',
        shopName: 'Rajat Shop',
        customerName: 'Rajat',
        customerPhone: '9876543210',
        items: const [
          OrderItem(
            menuItemId: 'thali',
            name: 'Special Thali',
            price: 180,
            quantity: 1,
          ),
        ],
        totalAmount: 180,
        status: 'rejected',
        rejectionReason: 'Items out of stock for the day',
        createdAt: now,
      );

      final container = ProviderContainer();
      container.read(dummyOrdersProvider.notifier).addOrder(order);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: OrderDetailScreen(orderId: 'YB-1004'),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Rejected ❌'), findsOneWidget);
      expect(find.text('This order was rejected by shopkeeper.'), findsOneWidget);
      expect(find.text('Reason: Items out of stock for the day'), findsOneWidget);
      expect(find.text('Cancel Order'), findsNothing);
    });

    testWidgets('Cancelled order renders cancellation banner', (tester) async {
      final now = DateTime.now();
      final order = AppOrder(
        orderId: 'YB-1005',
        shopId: 'rajat_shop',
        shopName: 'Rajat Shop',
        customerName: 'Rajat',
        customerPhone: '9876543210',
        items: const [
          OrderItem(
            menuItemId: 'fries',
            name: 'Peri Peri Fries',
            price: 80,
            quantity: 1,
          ),
        ],
        totalAmount: 80,
        status: 'cancelled',
        createdAt: now,
      );

      final container = ProviderContainer();
      container.read(dummyOrdersProvider.notifier).addOrder(order);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: OrderDetailScreen(orderId: 'YB-1005'),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Cancelled ❌'), findsOneWidget);
      expect(find.text('This order was cancelled.'), findsOneWidget);
      expect(find.text('Cancel Order'), findsNothing);
    });
  });
}
