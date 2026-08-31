// BU Gate2Eat — Tests
// Checkpoint 3.9.5 — Admin Panel UniversalOrderCard Integration Tests

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bugate2eat_app/core/providers.dart';
import 'package:bugate2eat_app/features/orders/widgets/universal_order_card.dart';
import 'package:bugate2eat_app/models/order_model.dart';
import 'package:bugate2eat_app/models/shop_model.dart';
import 'package:bugate2eat_app/models/shop_stats_model.dart';
import 'package:bugate2eat_app/panel/admin_panel/admin_monthly_reports_screen.dart';
import 'package:bugate2eat_app/panel/admin_panel/admin_shop_orders_screen.dart';
import 'package:bugate2eat_app/panel/admin_panel/widgets/admin_order_details_modal.dart';
import 'package:bugate2eat_app/services/report_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final baseTime = DateTime(2026, 8, 31, 14, 0, 0);

  final testShop = Shop(
    id: 'test_shop_1',
    name: 'Burger Club',
    description: 'Best Burgers',
    bannerUrl: '',
    contactNumber: '9876543210',
    orderNumber: '9876543210',
    openTime: '09:00',
    closeTime: '23:00',
    isClosedOverride: false,
    isActive: true,
    sortOrder: 1,
    searchKeywords: const [],
    deliveryNote: 'Gate 2',
    createdAt: baseTime,
    updatedAt: baseTime,
  );

  final sampleOrderDelivered = AppOrder(
    orderId: 'ADM-DEL-01',
    customerId: 'cust_adm_1',
    customerName: 'Rohit Sharma',
    customerPhone: '9876543210',
    shopId: 'test_shop_1',
    shopName: 'Burger Club',
    status: 'delivered',
    totalAmount: 260.0,
    items: const [
      OrderItem(menuItemId: 'b1', name: 'Zesty Burger', price: 130, quantity: 2),
    ],
    createdAt: baseTime.subtract(const Duration(hours: 2)),
    acceptedAt: baseTime.subtract(const Duration(hours: 2, minutes: -5)),
    deliveredAt: baseTime.subtract(const Duration(hours: 1)),
  );

  final sampleOrderRejected = AppOrder(
    orderId: 'ADM-REJ-02',
    customerId: 'cust_adm_2',
    customerName: 'Sneha Patel',
    customerPhone: '9876543211',
    shopId: 'test_shop_1',
    shopName: 'Burger Club',
    status: 'rejected',
    rejectionReason: 'Kitchen closed for deep cleaning',
    totalAmount: 180.0,
    items: const [
      OrderItem(menuItemId: 'b2', name: 'Cheese Fries', price: 180, quantity: 1),
    ],
    createdAt: baseTime.subtract(const Duration(hours: 3)),
  );

  group('Checkpoint 3.9.5 — Admin Shop Orders UniversalOrderCard Integration', () {
    testWidgets('1. Shop Orders screen renders UniversalOrderCard for delivered and rejected orders', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            shopsProvider.overrideWith((ref) => Future.value([testShop])),
            shopOrdersStreamProvider('test_shop_1').overrideWith(
              (ref) => Stream.value([sampleOrderDelivered, sampleOrderRejected]),
            ),
          ],
          child: const MaterialApp(
            home: AdminShopOrdersScreen(shopId: 'test_shop_1'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify UniversalOrderCard widgets
      expect(find.byType(UniversalOrderCard), findsNWidgets(2));

      // Customer identity
      expect(find.text('Rohit Sharma'), findsOneWidget);
      expect(find.text('Sneha Patel'), findsOneWidget);

      // Status badges
      expect(find.text('DELIVERED'), findsOneWidget);
      expect(find.text('REJECTED'), findsOneWidget);

      // Monospace Order IDs
      expect(find.text('Order #ADM-DEL-01'), findsOneWidget);
      expect(find.text('Order #ADM-REJ-02'), findsOneWidget);

      // Summaries
      expect(find.text('2 items • ₹260'), findsOneWidget);
      expect(find.text('1 item • ₹180'), findsOneWidget);

      // Rejection Reason visible
      expect(find.text('Reason: Kitchen closed for deep cleaning'), findsOneWidget);

      // No obsolete item preview text in cards
      expect(find.text('Zesty Burger (x2)'), findsNothing);
    });

    testWidgets('2. Tapping UniversalOrderCard opens AdminOrderDetailsModal', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            shopsProvider.overrideWith((ref) => Future.value([testShop])),
            shopOrdersStreamProvider('test_shop_1').overrideWith(
              (ref) => Stream.value([sampleOrderDelivered]),
            ),
          ],
          child: const MaterialApp(
            home: AdminShopOrdersScreen(shopId: 'test_shop_1'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(UniversalOrderCard));
      await tester.pumpAndSettle();

      expect(find.byType(AdminOrderDetailsModal), findsOneWidget);
    });
  });

  group('Checkpoint 3.9.5 — Admin Monthly Reports UniversalOrderCard Integration', () {
    testWidgets('3. Monthly Reports breakdown renders UniversalOrderCard with read-only details tap', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final reportData = MonthlyReportData(
        shopId: 'test_shop_1',
        shopName: 'Burger Club',
        startDateTime: baseTime.subtract(const Duration(days: 30)),
        endDateTime: baseTime,
        orders: [sampleOrderDelivered, sampleOrderRejected],
        generatedAt: baseTime,
        explicitWhatsappOrdersCount: 0,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            shopsProvider.overrideWith((ref) => Future.value([testShop])),
            shopStatsStreamProvider('test_shop_1').overrideWith(
              (ref) => Stream.value(ShopStats.zero(shopId: 'test_shop_1', shopName: 'Burger Club')),
            ),
            shopStatementDataProvider.overrideWith((ref, _) => Future.value(reportData)),
          ],
          child: const MaterialApp(
            home: AdminMonthlyReportsScreen(initialShopId: 'test_shop_1'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify UniversalOrderCard widgets in breakdown
      expect(find.byType(UniversalOrderCard), findsNWidgets(2));
      expect(find.text('Rohit Sharma'), findsOneWidget);
      expect(find.text('Sneha Patel'), findsOneWidget);
      expect(find.text('DELIVERED'), findsOneWidget);
      expect(find.text('REJECTED'), findsOneWidget);

      // Tap card in Monthly Reports to open details modal
      await tester.tap(find.text('Order #ADM-DEL-01'));
      await tester.pumpAndSettle();

      expect(find.byType(AdminOrderDetailsModal), findsOneWidget);
    });
  });
}
