// BU Gate2Eat — Tests
// Checkpoint 3.9.2 — Customer Active Orders Screen UniversalOrderCard Integration Tests

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bugate2eat_app/core/providers.dart';
import 'package:bugate2eat_app/features/orders/active_orders_screen.dart';
import 'package:bugate2eat_app/features/orders/widgets/universal_order_card.dart';
import 'package:bugate2eat_app/models/order_model.dart';

void main() {
  final baseTime = DateTime(2026, 8, 31, 14, 0, 0);

  final sampleItems = [
    const OrderItem(
      menuItemId: 'naan_1',
      name: 'Butter Naan',
      price: 35,
      quantity: 1,
    ),
    const OrderItem(
      menuItemId: 'paneer_1',
      name: 'Paneer Masala',
      price: 180,
      quantity: 1,
    ),
  ];

  AppOrder createActiveOrder({
    required String orderId,
    required String shopName,
    required String status,
    required DateTime createdAt,
    DateTime? acceptDeadline,
    DateTime? deliveryDeadline,
  }) {
    return AppOrder(
      orderId: orderId,
      shopId: 'shop_$shopName',
      shopName: shopName,
      customerId: 'user_test',
      customerName: 'Test Student',
      customerPhone: '9876543210',
      items: sampleItems,
      totalAmount: 215.0,
      status: status,
      createdAt: createdAt,
      acceptDeadline: acceptDeadline,
      deliveryDeadline: deliveryDeadline,
    );
  }

  group('Checkpoint 3.9.2 — Customer Active Orders UniversalOrderCard Integration', () {
    testWidgets('1. Active Placed Order renders through UniversalOrderCard with live countdown', (tester) async {
      final order = createActiveOrder(
        orderId: 'YB-20260831-134821-924',
        shopName: 'Raja Hotel',
        status: 'placed',
        createdAt: baseTime.subtract(const Duration(minutes: 5)),
        acceptDeadline: baseTime.add(const Duration(minutes: 15)), // 15:00 remaining
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            customerActiveOrdersStreamProvider.overrideWith((ref) => Stream.value([order])),
            orderReconciliationTickerProvider.overrideWith((ref) => Stream.value(baseTime)),
          ],
          child: const MaterialApp(
            home: ActiveOrdersScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Confirms UniversalOrderCard is rendered
      expect(find.byType(UniversalOrderCard), findsOneWidget);

      // Identity & Status
      expect(find.text('Raja Hotel'), findsOneWidget);
      expect(find.text('PLACED'), findsOneWidget);
      expect(find.text('(15:00)'), findsOneWidget);

      // Order ID & Summary
      expect(find.text('Order #YB-20260831-134821-924'), findsOneWidget);
      expect(find.text('2 items • ₹215'), findsOneWidget);
      expect(find.text('View Details'), findsNothing);

      // Verify old redundant content is ABSENT
      expect(find.text('Butter Naan (x1)'), findsNothing);
      expect(find.textContaining('Accept within'), findsNothing);
    });

    testWidgets('2. Active Accepted Order renders with delivery countdown', (tester) async {
      final order = createActiveOrder(
        orderId: 'YB-20260831-134821-925',
        shopName: 'Rolls & Bowls',
        status: 'accepted',
        createdAt: baseTime.subtract(const Duration(minutes: 10)),
        deliveryDeadline: baseTime.add(const Duration(minutes: 80)), // 80:00 remaining
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            customerActiveOrdersStreamProvider.overrideWith((ref) => Stream.value([order])),
            orderReconciliationTickerProvider.overrideWith((ref) => Stream.value(baseTime)),
          ],
          child: const MaterialApp(
            home: ActiveOrdersScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.byType(UniversalOrderCard), findsOneWidget);
      expect(find.text('Rolls & Bowls'), findsOneWidget);
      expect(find.text('ACCEPTED'), findsOneWidget);
      expect(find.text('(80:00)'), findsOneWidget);
      expect(find.text('2 items • ₹215'), findsOneWidget);
      expect(find.textContaining('Delivery due in'), findsNothing);
    });

    testWidgets('3. Multiple Active Orders render independently as UniversalOrderCards', (tester) async {
      final order1 = createActiveOrder(
        orderId: 'YB-1001',
        shopName: 'Rajat Shop',
        status: 'placed',
        createdAt: baseTime,
      );
      final order2 = createActiveOrder(
        orderId: 'YB-1002',
        shopName: 'Nayan Shop',
        status: 'accepted',
        createdAt: baseTime,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            customerActiveOrdersStreamProvider.overrideWith((ref) => Stream.value([order1, order2])),
            orderReconciliationTickerProvider.overrideWith((ref) => Stream.value(baseTime)),
          ],
          child: const MaterialApp(
            home: ActiveOrdersScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.byType(UniversalOrderCard), findsNWidgets(2));
      expect(find.text('Rajat Shop'), findsOneWidget);
      expect(find.text('Nayan Shop'), findsOneWidget);
      expect(find.text('PLACED'), findsOneWidget);
      expect(find.text('ACCEPTED'), findsOneWidget);
    });

    testWidgets('4. Empty State is preserved when active orders list is empty', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            customerActiveOrdersStreamProvider.overrideWith((ref) => Stream.value([])),
          ],
          child: const MaterialApp(
            home: ActiveOrdersScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.byType(UniversalOrderCard), findsNothing);
      expect(find.text('No active orders'), findsOneWidget);
      expect(find.text('Browse Shops'), findsOneWidget);
    });
  });
}
