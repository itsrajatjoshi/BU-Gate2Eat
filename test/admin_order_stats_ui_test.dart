// BU Gate2Eat — Admin Order Statistics UI Widget Test Suite (Phase C)
//
// Tests:
// 1. AdminOrderStatsScreen renders shop cards with isolated counters
// 2. Empty stats show 0 (never crash or fake data)
// 3. Shop A stats stay separate from Shop B
// 4. AdminShopStatsDetailScreen renders full breakdown correctly
// 5. AdminShopStatsDetailScreen renders placeholder buttons (View App Orders & Reset Data)
// 6. Navigation to detail screen passes correct shopId

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bugate2eat_app/core/providers.dart';
import 'package:bugate2eat_app/models/shop_model.dart';
import 'package:bugate2eat_app/models/shop_stats_model.dart';
import 'package:bugate2eat_app/panel/admin_panel/admin_order_stats_screen.dart';
import 'package:bugate2eat_app/panel/admin_panel/admin_shop_stats_detail_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final shop1 = Shop(
    id: 'rajat_shop',
    name: 'Rajat Shop',
    description: 'Fresh & Fast',
    bannerUrl: '',
    contactNumber: '8295643910',
    orderNumber: '8295643910',
    openTime: '09:00',
    closeTime: '23:00',
    isClosedOverride: false,
    isActive: true,
    sortOrder: 1,
    searchKeywords: const [],
    deliveryNote: 'Gate 2 Delivery Point',
    createdAt: DateTime(2026, 8, 24),
    updatedAt: DateTime(2026, 8, 24),
  );

  final shop2 = Shop(
    id: 'nayan_shop',
    name: 'Nayan Cafe',
    description: 'Best Coffee & Snacks',
    bannerUrl: '',
    contactNumber: '8875344034',
    orderNumber: '8875344034',
    openTime: '09:00',
    closeTime: '23:00',
    isClosedOverride: false,
    isActive: true,
    sortOrder: 2,
    searchKeywords: const [],
    deliveryNote: 'Bennett University',
    createdAt: DateTime(2026, 8, 24),
    updatedAt: DateTime(2026, 8, 24),
  );

  const stats1 = ShopStats(
    shopId: 'rajat_shop',
    shopName: 'Rajat Shop',
    appOrders: 125,
    accepted: 90,
    delivered: 75,
    notAccepted: 25,
    rejectedAfterAccept: 10,
    deliveryExpired: 5,
    whatsappOrders: 73,
  );

  const stats2 = ShopStats(
    shopId: 'nayan_shop',
    shopName: 'Nayan Cafe',
    appOrders: 84,
    accepted: 60,
    delivered: 55,
    notAccepted: 15,
    rejectedAfterAccept: 5,
    deliveryExpired: 4,
    whatsappOrders: 31,
  );

  group('Phase C: Admin Order Statistics UI Tests', () {
    testWidgets('1. AdminOrderStatsScreen renders shop cards with isolated counters', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            shopsProvider.overrideWith((ref) => Future.value([shop1, shop2])),
            allShopStatsStreamProvider.overrideWith(
              (ref) => Stream.value([stats1, stats2]),
            ),
          ],
          child: const MaterialApp(
            home: AdminOrderStatsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify Screen Header
      expect(find.text('Order Statistics'), findsOneWidget);

      // Verify both shops render separately
      expect(find.text('Rajat Shop'), findsOneWidget);
      expect(find.text('Nayan Cafe'), findsOneWidget);

      // Verify Shop 1 isolated metrics
      expect(find.text('125'), findsOneWidget); // Rajat app orders
      expect(find.text('73'), findsOneWidget); // Rajat whatsapp orders

      // Verify Shop 2 isolated metrics
      expect(find.text('84'), findsOneWidget); // Nayan app orders
      expect(find.text('31'), findsOneWidget); // Nayan whatsapp orders

      // Verify "View Details" buttons exist for each card
      expect(find.text('View Details'), findsNWidgets(2));
    });

    testWidgets('2. Empty stats show 0 safely without fake demo data', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            shopsProvider.overrideWith((ref) => Future.value([shop1])),
            allShopStatsStreamProvider.overrideWith(
              (ref) => Stream.value([]), // Empty stats in Firestore
            ),
          ],
          child: const MaterialApp(
            home: AdminOrderStatsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Rajat Shop'), findsOneWidget);
      // Counters should safely be 0
      expect(find.text('0'), findsNWidgets(2)); // appOrders: 0, whatsappOrders: 0
    });

    testWidgets('3. AdminShopStatsDetailScreen renders full breakdown for selected shop', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            shopsProvider.overrideWith((ref) => Future.value([shop1])),
            shopStatsStreamProvider('rajat_shop').overrideWith(
              (ref) => Stream.value(stats1),
            ),
          ],
          child: const MaterialApp(
            home: AdminShopStatsDetailScreen(shopId: 'rajat_shop'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Header summary
      expect(find.text('Rajat Shop'), findsNWidgets(2)); // AppBar + Header
      expect(find.text('Shop ID: rajat_shop'), findsOneWidget);
      expect(find.text('198'), findsOneWidget); // Total orders: 125 + 73

      // App Orders breakdown
      expect(find.text('APP ORDERS BREAKDOWN'), findsOneWidget);
      expect(find.text('125'), findsNWidgets(2)); // Header + Breakdown
      expect(find.text('90'), findsOneWidget); // Accepted
      expect(find.text('75'), findsOneWidget); // Delivered
      expect(find.text('25'), findsOneWidget); // Not Accepted
      expect(find.text('10'), findsOneWidget); // Rejected After Accept
      expect(find.text('5'), findsOneWidget); // Delivery Expired

      // WhatsApp section
      expect(find.text('WHATSAPP ORDERS'), findsOneWidget);
      expect(find.text('73'), findsNWidgets(2)); // Header + Breakdown

      // Placeholder action buttons
      expect(find.text('VIEW APP ORDERS'), findsOneWidget);
      expect(find.text('RESET DATA'), findsOneWidget);
    });

    testWidgets('4. Tapping RESET DATA button opens confirmation dialog', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            shopsProvider.overrideWith((ref) => Future.value([shop1])),
            shopStatsStreamProvider('rajat_shop').overrideWith(
              (ref) => Stream.value(stats1),
            ),
          ],
          child: const MaterialApp(
            home: AdminShopStatsDetailScreen(shopId: 'rajat_shop'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify buttons are present
      expect(find.text('VIEW APP ORDERS'), findsOneWidget);
      expect(find.text('RESET DATA'), findsOneWidget);

      // Tap RESET DATA
      await tester.tap(find.text('RESET DATA'));
      await tester.pumpAndSettle();

      // Verify confirmation dialog
      expect(find.text('Reset Rajat Shop?'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.widgetWithText(ElevatedButton, 'Reset'), findsOneWidget);
    });
  });
}
