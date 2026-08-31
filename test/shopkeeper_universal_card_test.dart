// BU Gate2Eat — Tests
// Checkpoint 3.9.4 — Shopkeeper Panel UniversalOrderCard Integration Tests

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bugate2eat_app/core/providers.dart';
import 'package:bugate2eat_app/features/orders/widgets/universal_order_card.dart';
import 'package:bugate2eat_app/models/order_model.dart';
import 'package:bugate2eat_app/panel/shopkeeper_panel/shopkeeper_order_history_screen.dart';
import 'package:bugate2eat_app/panel/shopkeeper_panel/shopkeeper_orders_screen.dart';
import 'package:bugate2eat_app/panel/shopkeeper_panel/widgets/shopkeeper_order_details_modal.dart';

void main() {
  final baseTime = DateTime(2026, 8, 31, 14, 0, 0);

  final sampleItems = [
    const OrderItem(
      menuItemId: 'roll_1',
      name: 'Paneer Roll',
      price: 90,
      quantity: 2,
    ),
  ];

  AppOrder createShopkeeperOrder({
    required String orderId,
    required String customerName,
    required String status,
    required DateTime createdAt,
    DateTime? acceptDeadline,
    DateTime? deliveryDeadline,
    String? rejectionReason,
  }) {
    return AppOrder(
      orderId: orderId,
      shopId: 'rajat_shop',
      shopName: 'Rajat Shop',
      customerId: 'user_cust_1',
      customerName: customerName,
      customerPhone: '9876543210',
      items: sampleItems,
      totalAmount: 180.0,
      status: status,
      createdAt: createdAt,
      acceptDeadline: acceptDeadline,
      deliveryDeadline: deliveryDeadline,
      rejectionReason: rejectionReason ?? '',
    );
  }

  group('Checkpoint 3.9.4 — Shopkeeper Active Orders UniversalOrderCard Integration', () {
    testWidgets('1. Active Placed Order renders with Customer Name, person icon, and accept countdown', (tester) async {
      final order = createShopkeeperOrder(
        orderId: 'YB-SK-101',
        customerName: 'Aarav Sharma',
        status: 'placed',
        createdAt: baseTime.subtract(const Duration(minutes: 5)),
        acceptDeadline: baseTime.add(const Duration(minutes: 15)),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            shopActiveOrdersStreamProvider('rajat_shop').overrideWith((ref) => Stream.value([order])),
            currentShopkeeperShopIdProvider.overrideWith((ref) => 'rajat_shop'),
            orderReconciliationTickerProvider.overrideWith((ref) => Stream.value(baseTime)),
          ],
          child: const MaterialApp(
            home: ShopkeeperOrdersScreen(shopId: 'rajat_shop'),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // UniversalOrderCard rendered
      expect(find.byType(UniversalOrderCard), findsOneWidget);

      // Customer identity & status badge with countdown
      expect(find.text('Aarav Sharma'), findsOneWidget);
      expect(find.byIcon(Icons.person_rounded), findsWidgets);
      expect(find.text('PLACED'), findsOneWidget);
      expect(find.text('(15:00)'), findsOneWidget);

      // Monospace ID & Summary
      expect(find.text('Order #YB-SK-101'), findsOneWidget);
      expect(find.text('2 items • ₹180'), findsOneWidget);
      expect(find.text('View Details'), findsNothing);

      // Redundant items preview should not be on the card
      expect(find.text('Paneer Roll (x2)'), findsNothing);
    });

    testWidgets('2. Active Accepted Order renders with Customer Name and delivery countdown', (tester) async {
      final order = createShopkeeperOrder(
        orderId: 'YB-SK-102',
        customerName: 'Priya Singh',
        status: 'accepted',
        createdAt: baseTime.subtract(const Duration(minutes: 10)),
        deliveryDeadline: baseTime.add(const Duration(minutes: 80)),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            shopActiveOrdersStreamProvider('rajat_shop').overrideWith((ref) => Stream.value([order])),
            currentShopkeeperShopIdProvider.overrideWith((ref) => 'rajat_shop'),
            orderReconciliationTickerProvider.overrideWith((ref) => Stream.value(baseTime)),
          ],
          child: const MaterialApp(
            home: ShopkeeperOrdersScreen(shopId: 'rajat_shop'),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.byType(UniversalOrderCard), findsOneWidget);
      expect(find.text('Priya Singh'), findsOneWidget);
      expect(find.text('ACCEPTED'), findsOneWidget);
      expect(find.text('(80:00)'), findsOneWidget);
      expect(find.text('2 items • ₹180'), findsOneWidget);
    });

    testWidgets('3. Card Tap opens ShopkeeperOrderDetailsModal', (tester) async {
      final order = createShopkeeperOrder(
        orderId: 'YB-SK-103',
        customerName: 'Rohan Gupta',
        status: 'placed',
        createdAt: baseTime,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            shopActiveOrdersStreamProvider('rajat_shop').overrideWith((ref) => Stream.value([order])),
            currentShopkeeperShopIdProvider.overrideWith((ref) => 'rajat_shop'),
            orderReconciliationTickerProvider.overrideWith((ref) => Stream.value(baseTime)),
          ],
          child: const MaterialApp(
            home: ShopkeeperOrdersScreen(shopId: 'rajat_shop'),
          ),
        ),
      );

      await tester.pumpAndSettle();

      await tester.tap(find.byType(UniversalOrderCard));
      await tester.pumpAndSettle();

      expect(find.byType(ShopkeeperOrderDetailsModal), findsOneWidget);
    });
  });

  group('Checkpoint 3.9.4 — Shopkeeper Order History UniversalOrderCard Integration', () {
    testWidgets('4. History Delivered Order renders with Customer Name without reason row', (tester) async {
      final order = createShopkeeperOrder(
        orderId: 'YB-SK-DEL-201',
        customerName: 'Ananya Verma',
        status: 'delivered',
        createdAt: baseTime.subtract(const Duration(hours: 3)),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            shopOrderHistoryStreamProvider('rajat_shop').overrideWith((ref) => Stream.value([order])),
            currentShopkeeperShopIdProvider.overrideWith((ref) => 'rajat_shop'),
          ],
          child: const MaterialApp(
            home: ShopkeeperOrderHistoryScreen(shopId: 'rajat_shop'),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.byType(UniversalOrderCard), findsOneWidget);
      expect(find.text('Ananya Verma'), findsOneWidget);
      expect(find.text('DELIVERED'), findsOneWidget);
      expect(find.text('Order #YB-SK-DEL-201'), findsOneWidget);
      expect(find.text('2 items • ₹180'), findsOneWidget);
      expect(find.textContaining('Reason:'), findsNothing);
    });

    testWidgets('5. History Rejected Order renders with Customer Name and reason', (tester) async {
      final order = createShopkeeperOrder(
        orderId: 'YB-SK-REJ-202',
        customerName: 'Vikram Joshi',
        status: 'rejected',
        rejectionReason: 'Shop is closing early today',
        createdAt: baseTime.subtract(const Duration(hours: 4)),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            shopOrderHistoryStreamProvider('rajat_shop').overrideWith((ref) => Stream.value([order])),
            currentShopkeeperShopIdProvider.overrideWith((ref) => 'rajat_shop'),
          ],
          child: const MaterialApp(
            home: ShopkeeperOrderHistoryScreen(shopId: 'rajat_shop'),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.byType(UniversalOrderCard), findsOneWidget);
      expect(find.text('Vikram Joshi'), findsOneWidget);
      expect(find.text('REJECTED'), findsOneWidget);
      expect(find.text('Reason: Shop is closing early today'), findsOneWidget);
    });
  });
}
