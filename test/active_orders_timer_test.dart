// BU Gate2Eat — Active Orders & Timer UI Tests
// Tests live countdown badges, rejection cutoff in modal, and delivery_expired state

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bugate2eat_app/core/providers.dart';
import 'package:bugate2eat_app/core/utils/order_timer_helper.dart';
import 'package:bugate2eat_app/features/orders/active_orders_screen.dart';
import 'package:bugate2eat_app/features/orders/order_detail_screen.dart';
import 'package:bugate2eat_app/models/order_model.dart';
import 'package:bugate2eat_app/panel/shopkeeper_panel/widgets/shopkeeper_order_details_modal.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final baseTime = DateTime(2026, 8, 26, 12, 0, 0);

  AppOrder createPlacedOrder({int elapsedMinutes = 5}) {
    final created = baseTime.subtract(Duration(minutes: elapsedMinutes));
    return AppOrder(
      orderId: 'ORD-PLACED-123',
      customerId: 'CUST-001',
      customerName: 'Kunal Sharma',
      customerPhone: '9876543210',
      shopId: 'shop_1',
      shopName: 'Rolls & Bowls',
      items: const [
        OrderItem(
          menuItemId: 'item_1',
          name: 'Paneer Roll',
          price: 120,
          quantity: 2,
        ),
      ],
      totalAmount: 240,
      status: 'placed',
      createdAt: created,
      acceptDeadline: created.add(const Duration(minutes: 20)),
    );
  }

  AppOrder createAcceptedOrder({int elapsedMinutes = 10}) {
    final accepted = baseTime.subtract(Duration(minutes: elapsedMinutes));
    return AppOrder(
      orderId: 'ORD-ACCEPTED-456',
      customerId: 'CUST-001',
      customerName: 'Kunal Sharma',
      customerPhone: '9876543210',
      shopId: 'shop_1',
      shopName: 'Rolls & Bowls',
      items: const [
        OrderItem(
          menuItemId: 'item_1',
          name: 'Paneer Roll',
          price: 120,
          quantity: 1,
        ),
      ],
      totalAmount: 120,
      status: 'accepted',
      createdAt: accepted.subtract(const Duration(minutes: 2)),
      acceptedAt: accepted,
      rejectDeadline: accepted.add(const Duration(minutes: 15)),
      deliveryDeadline: accepted.add(const Duration(minutes: 90)),
    );
  }

  group('Active Orders & Order Detail Screen UI & Timers', () {
    testWidgets('ActiveOrdersScreen displays live accept countdown for placed order', (tester) async {
      final order = createPlacedOrder(elapsedMinutes: 5); // 15:00 remaining

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

      // Should show shop name and countdown badge
      expect(find.text('Rolls & Bowls'), findsOneWidget);
      expect(find.text('PLACED'), findsOneWidget);
      expect(find.text('(15:00)'), findsOneWidget);
      expect(find.textContaining('Accept within 15:00'), findsOneWidget);
    });

    testWidgets('ActiveOrdersScreen displays live delivery countdown for accepted order', (tester) async {
      final order = createAcceptedOrder(elapsedMinutes: 10); // 80:00 remaining

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

      expect(find.text('Rolls & Bowls'), findsOneWidget);
      expect(find.text('ACCEPTED'), findsOneWidget);
      expect(find.text('(80:00)'), findsOneWidget);
      expect(find.textContaining('Delivery due in 80:00'), findsOneWidget);
    });

    testWidgets('OrderDetailScreen renders delivery_expired banner and badge cleanly', (tester) async {
      final expiredOrder = AppOrder(
        orderId: 'ORD-EXP-789',
        customerId: 'CUST-001',
        customerName: 'Kunal Sharma',
        customerPhone: '9876543210',
        shopId: 'shop_1',
        shopName: 'Rolls & Bowls',
        items: const [
          OrderItem(
            menuItemId: 'item_1',
            name: 'Paneer Roll',
            price: 120,
            quantity: 1,
          ),
        ],
        totalAmount: 120,
        status: 'delivery_expired',
        rejectionReason: 'Delivery window of 90 minutes expired.',
        createdAt: baseTime.subtract(const Duration(minutes: 95)),
        acceptedAt: baseTime.subtract(const Duration(minutes: 92)),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            singleOrderStreamProvider('ORD-EXP-789').overrideWith((ref) => Stream.value(expiredOrder)),
            orderReconciliationTickerProvider.overrideWith((ref) => Stream.value(baseTime)),
          ],
          child: const MaterialApp(
            home: OrderDetailScreen(orderId: 'ORD-EXP-789'),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Expired ⏱️'), findsOneWidget);
      expect(find.text('This order has expired.'), findsOneWidget);
      expect(find.text('Reason: Delivery window of 90 minutes expired.'), findsOneWidget);
    });

    testWidgets('ShopkeeperOrderDetailsModal shows Reject button when within 15 min of accept', (tester) async {
      final order = createAcceptedOrder(elapsedMinutes: 5); // 10:00 reject remaining

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            orderReconciliationTickerProvider.overrideWith((ref) => Stream.value(baseTime)),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: ShopkeeperOrderDetailsModal(order: order),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Reject button with countdown is visible
      expect(find.text('Reject Order'), findsOneWidget);
      expect(find.text('(10:00)'), findsOneWidget);
      expect(find.text('Mark as Delivered'), findsOneWidget);
    });

    testWidgets('ShopkeeperOrderDetailsModal hides Reject button when past 15 min of accept', (tester) async {
      final order = createAcceptedOrder(elapsedMinutes: 16); // 16 min elapsed > 15 min window

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            orderReconciliationTickerProvider.overrideWith((ref) => Stream.value(baseTime)),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: ShopkeeperOrderDetailsModal(order: order),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Reject button is completely absent; only full width Mark as Delivered is shown
      expect(find.textContaining('Reject'), findsNothing);
      expect(find.text('Mark as Delivered'), findsOneWidget);
    });
  });
}
