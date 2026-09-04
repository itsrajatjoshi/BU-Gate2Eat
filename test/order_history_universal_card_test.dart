// BU Gate2Eat — Tests
// Checkpoint 3.9.3 — Customer Order History Screen UniversalOrderCard Integration Tests

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bugate2eat_app/core/providers.dart';
import 'package:bugate2eat_app/features/orders/order_history_screen.dart';
import 'package:bugate2eat_app/features/orders/widgets/universal_order_card.dart';
import 'package:bugate2eat_app/models/order_model.dart';

void main() {
  final baseTime = DateTime(2026, 8, 31, 14, 0, 0);

  final sampleItems = [
    const OrderItem(
      menuItemId: 'chaap_1',
      name: 'Soya Chaap Curry',
      price: 160,
      quantity: 1,
    ),
    const OrderItem(
      menuItemId: 'roti_1',
      name: 'Tandoori Roti',
      price: 15,
      quantity: 2,
    ),
  ];

  AppOrder createHistoryOrder({
    required String orderId,
    required String shopName,
    required String status,
    required DateTime createdAt,
    String? rejectionReason,
  }) {
    return AppOrder(
      orderId: orderId,
      shopId: 'shop_$shopName',
      shopName: shopName,
      customerId: 'user_test',
      customerName: 'Test Student',
      customerPhone: '9876543210',
      items: sampleItems,
      totalAmount: 190.0,
      status: status,
      createdAt: createdAt,
      rejectionReason: rejectionReason ?? '',
    );
  }

  group('Checkpoint 3.9.3 — Customer Order History UniversalOrderCard Integration', () {
    testWidgets('1. Delivered Order renders through UniversalOrderCard without reason row', (tester) async {
      final order = createHistoryOrder(
        orderId: 'YB-20260831-DEL-101',
        shopName: 'Raja Hotel',
        status: 'delivered',
        createdAt: baseTime.subtract(const Duration(hours: 2)),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            customerOrderHistoryStreamProvider.overrideWith((ref) => Stream.value([order])),
          ],
          child: const MaterialApp(
            home: OrderHistoryScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // UniversalOrderCard presence
      expect(find.byType(UniversalOrderCard), findsOneWidget);

      // Identity & Status
      expect(find.text('Raja Hotel'), findsOneWidget);
      expect(find.text('DELIVERED'), findsOneWidget);

      // Order ID & Summary
      expect(find.text('Order #YB-20260831-DEL-101'), findsOneWidget);
      expect(find.text('3 items • ₹190'), findsOneWidget);
      expect(find.text('View Details'), findsNothing);

      // Verify no reason row or item previews
      expect(find.textContaining('Reason:'), findsNothing);
      expect(find.text('Soya Chaap Curry (x1)'), findsNothing);
    });

    testWidgets('2. Rejected Order renders reason row only when non-empty', (tester) async {
      final order = createHistoryOrder(
        orderId: 'YB-20260831-REJ-202',
        shopName: 'Rolls & Bowls',
        status: 'rejected',
        rejectionReason: 'Items out of stock',
        createdAt: baseTime.subtract(const Duration(hours: 3)),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            customerOrderHistoryStreamProvider.overrideWith((ref) => Stream.value([order])),
          ],
          child: const MaterialApp(
            home: OrderHistoryScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.byType(UniversalOrderCard), findsOneWidget);
      expect(find.text('Rolls & Bowls'), findsOneWidget);
      expect(find.text('REJECTED'), findsOneWidget);
      expect(find.text('Reason: Items out of stock'), findsOneWidget);
    });

    testWidgets('3. Cancelled Order renders CANCELLED badge and reason if provided', (tester) async {
      final order = createHistoryOrder(
        orderId: 'YB-20260831-CAN-303',
        shopName: 'Maggi Hotspot',
        status: 'cancelled',
        rejectionReason: 'Ordered by mistake',
        createdAt: baseTime.subtract(const Duration(hours: 4)),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            customerOrderHistoryStreamProvider.overrideWith((ref) => Stream.value([order])),
          ],
          child: const MaterialApp(
            home: OrderHistoryScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.byType(UniversalOrderCard), findsOneWidget);
      expect(find.text('Maggi Hotspot'), findsOneWidget);
      expect(find.text('CANCELLED'), findsOneWidget);
      expect(find.text('Reason: Ordered by mistake'), findsOneWidget);
    });

    testWidgets('4. Delivery-Expired Order renders DELIVERY EXPIRED status badge', (tester) async {
      final order = createHistoryOrder(
        orderId: 'YB-20260831-EXP-404',
        shopName: 'Nescafe',
        status: 'delivery_expired',
        createdAt: baseTime.subtract(const Duration(hours: 5)),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            customerOrderHistoryStreamProvider.overrideWith((ref) => Stream.value([order])),
          ],
          child: const MaterialApp(
            home: OrderHistoryScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.byType(UniversalOrderCard), findsOneWidget);
      expect(find.text('Nescafe'), findsOneWidget);
      expect(find.text('EXPIRED'), findsOneWidget);
    });

    testWidgets('5. Multiple historical orders render sorted newest-first', (tester) async {
      final olderOrder = createHistoryOrder(
        orderId: 'YB-OLD-01',
        shopName: 'Old Shop',
        status: 'delivered',
        createdAt: baseTime.subtract(const Duration(days: 2)),
      );
      final newerOrder = createHistoryOrder(
        orderId: 'YB-NEW-02',
        shopName: 'New Shop',
        status: 'delivered',
        createdAt: baseTime.subtract(const Duration(hours: 1)),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            customerOrderHistoryStreamProvider.overrideWith((ref) => Stream.value([olderOrder, newerOrder])),
          ],
          child: const MaterialApp(
            home: OrderHistoryScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.byType(UniversalOrderCard), findsNWidgets(2));

      // Check order in widget tree: New Shop should appear before Old Shop
      final firstCard = tester.widget<UniversalOrderCard>(find.byType(UniversalOrderCard).first);
      expect(firstCard.order.shopName, equals('New Shop'));
    });

    testWidgets('6. Empty State renders when no historical orders exist', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            customerOrderHistoryStreamProvider.overrideWith((ref) => Stream.value([])),
          ],
          child: const MaterialApp(
            home: OrderHistoryScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.byType(UniversalOrderCard), findsNothing);
      expect(find.text('No order history yet'), findsOneWidget);
      expect(find.text('Your completed, and rejected orders will appear here.'), findsOneWidget);
    });
  });
}
