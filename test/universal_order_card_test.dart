// BU Gate2Eat — Tests
// Checkpoint 3.9.1 — Universal Order Card Base Component Tests

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bugate2eat_app/core/constants/app_constants.dart';
import 'package:bugate2eat_app/features/orders/widgets/universal_order_card.dart';
import 'package:bugate2eat_app/models/order_model.dart';

void main() {
  final testCreatedAt = DateTime(2026, 8, 31, 13, 48, 0);

  final sampleItems = [
    const OrderItem(
      menuItemId: 'item_1',
      name: 'Butter Naan',
      price: 35,
      quantity: 1,
    ),
    const OrderItem(
      menuItemId: 'item_2',
      name: 'Paneer Butter Masala',
      price: 150,
      quantity: 2,
    ),
  ];

  AppOrder createTestOrder({
    String status = 'placed',
    String rejectionReason = '',
    DateTime? createdAt,
    DateTime? acceptDeadline,
    DateTime? deliveryDeadline,
  }) {
    return AppOrder(
      orderId: 'YB-20260831-134821-924',
      shopId: 'shop_raja',
      shopName: 'Raja Hotel',
      customerId: 'user_123',
      customerName: 'Rajat Joshi',
      customerPhone: '9876543210',
      items: sampleItems,
      totalAmount: 335.0,
      createdAt: createdAt ?? testCreatedAt,
      status: status,
      rejectionReason: rejectionReason,
      acceptDeadline: acceptDeadline,
      deliveryDeadline: deliveryDeadline,
    );
  }

  Widget buildTestWidget(Widget child) {
    return MaterialApp(
      theme: ThemeData.light(),
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: child,
        ),
      ),
    );
  }

  group('Checkpoint 3.9.1 — UniversalOrderCard Base Tests', () {
    testWidgets('1. Placed Order renders shop name, status, order ID, time, total, and countdown', (tester) async {
      final order = createTestOrder(status: 'placed');
      final testNow = testCreatedAt.add(const Duration(minutes: 5)); // 15:00 remaining out of 20 min

      await tester.pumpWidget(
        buildTestWidget(
          UniversalOrderCard(
            order: order,
            customNow: testNow,
            perspective: OrderCardPerspective.customer,
          ),
        ),
      );

      // Identity & Status
      expect(find.text('Raja Hotel'), findsOneWidget);
      expect(find.text('PLACED'), findsOneWidget);
      expect(find.text('(15:00)'), findsOneWidget);

      // Order ID & Time
      expect(find.text('Order #YB-20260831-134821-924'), findsOneWidget);
      expect(find.text('5 mins ago'), findsOneWidget);

      // Summary: 3 items (1 + 2) • ₹335
      expect(find.text('3 items • ₹335'), findsOneWidget);
      expect(find.text('View Details'), findsNothing);

      // Verify NO item preview or duplicate status subtext
      expect(find.text('Butter Naan (x1)'), findsNothing);
      expect(find.textContaining('Accept within'), findsNothing);
      expect(find.textContaining('Delivery due'), findsNothing);
    });

    testWidgets('2. Accepted Order renders green status and delivery countdown', (tester) async {
      final order = createTestOrder(
        status: 'accepted',
        deliveryDeadline: testCreatedAt.add(const Duration(minutes: 90)),
      );
      final testNow = testCreatedAt.add(const Duration(minutes: 10)); // 80:00 remaining

      await tester.pumpWidget(
        buildTestWidget(
          UniversalOrderCard(
            order: order,
            customNow: testNow,
            perspective: OrderCardPerspective.customer,
          ),
        ),
      );

      expect(find.text('Raja Hotel'), findsOneWidget);
      expect(find.text('ACCEPTED'), findsOneWidget);
      expect(find.text('(80:00)'), findsOneWidget);
      expect(find.text('3 items • ₹335'), findsOneWidget);
    });

    testWidgets('3. Delivered Order renders DELIVERED badge without countdown', (tester) async {
      final order = createTestOrder(status: 'delivered');

      await tester.pumpWidget(
        buildTestWidget(
          UniversalOrderCard(
            order: order,
            perspective: OrderCardPerspective.customer,
          ),
        ),
      );

      expect(find.text('DELIVERED'), findsOneWidget);
      expect(find.text('Raja Hotel'), findsOneWidget);
      expect(find.text('3 items • ₹335'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_outline_rounded), findsOneWidget);
    });

    testWidgets('4. Rejected Order renders reason only when rejected', (tester) async {
      final orderWithReason = createTestOrder(
        status: 'rejected',
        rejectionReason: 'Items not available',
      );

      await tester.pumpWidget(
        buildTestWidget(
          UniversalOrderCard(
            order: orderWithReason,
            perspective: OrderCardPerspective.customer,
          ),
        ),
      );

      expect(find.text('REJECTED'), findsOneWidget);
      expect(find.text('Reason: Items not available'), findsOneWidget);
      expect(find.byIcon(Icons.cancel_outlined), findsOneWidget);
    });

    testWidgets('5. Cancelled Order renders CANCELLED badge', (tester) async {
      final cancelledOrder = createTestOrder(
        status: 'cancelled',
        rejectionReason: 'Customer requested cancellation',
      );

      await tester.pumpWidget(
        buildTestWidget(
          UniversalOrderCard(
            order: cancelledOrder,
            perspective: OrderCardPerspective.customer,
          ),
        ),
      );

      expect(find.text('CANCELLED'), findsOneWidget);
      expect(find.text('Reason: Customer requested cancellation'), findsOneWidget);
      expect(find.byIcon(Icons.block_rounded), findsOneWidget);
    });

    testWidgets('6. Shopkeeper Perspective renders Customer Name and person icon', (tester) async {
      final order = createTestOrder(status: 'delivered');

      await tester.pumpWidget(
        buildTestWidget(
          UniversalOrderCard(
            order: order,
            perspective: OrderCardPerspective.shopkeeper,
          ),
        ),
      );

      expect(find.text('Rajat Joshi'), findsOneWidget);
      expect(find.byIcon(Icons.person_rounded), findsOneWidget);
      expect(find.text('DELIVERED'), findsOneWidget);
    });

    testWidgets('7. Tap on UniversalOrderCard triggers onTap callback', (tester) async {
      bool tapped = false;
      final order = createTestOrder(status: 'placed');

      await tester.pumpWidget(
        buildTestWidget(
          UniversalOrderCard(
            order: order,
            onTap: () => tapped = true,
          ),
        ),
      );

      await tester.tap(find.byType(UniversalOrderCard));
      await tester.pumpAndSettle();

      expect(tapped, isTrue);
    });
  });
}
