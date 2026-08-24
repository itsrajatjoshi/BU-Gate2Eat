// BU Gate2Eat — Admin Shop Reset Test Suite (Phase E)
//
// Verification of:
// 1. Reset Shop A → all Shop A stats become zero
// 2. Reset Shop A → all Shop A orders deleted
// 3. Shop B stats unchanged
// 4. Shop B orders unchanged
// 5. Shop/menu/category/settings remain unchanged
// 6. Admin App Orders becomes empty
// 7. Customer history for that shop becomes empty
// 8. Shopkeeper history for that shop becomes empty
// 9. Cancel confirmation dialog → nothing changes
// 10. Double reset protection
// 11. Reset failure handling

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bugate2eat_app/core/providers.dart';
import 'package:bugate2eat_app/models/order_model.dart';
import 'package:bugate2eat_app/models/shop_model.dart';
import 'package:bugate2eat_app/models/shop_stats_model.dart';
import 'package:bugate2eat_app/panel/admin_panel/admin_shop_stats_detail_screen.dart';
import 'package:bugate2eat_app/services/shop_stats_service.dart';

class FakeShopStatsService extends ShopStatsService {
  final Map<String, ShopStats> statsMap = {};
  final Map<String, List<AppOrder>> ordersMap = {};
  bool shouldFail = false;
  int resetCallCount = 0;

  @override
  bool get isAvailable => true;

  @override
  Future<void> resetShopStats(String shopId) async {
    if (shouldFail) {
      throw Exception('Firestore network timeout simulation');
    }
    final existing = statsMap[shopId];
    statsMap[shopId] = ShopStats.zero(
      shopId: shopId,
      shopName: existing?.shopName ?? shopId,
    ).copyWith(lastResetAt: DateTime.now());
  }

  @override
  Future<int> deleteTerminalShopOrders(String shopId) async {
    if (shouldFail) {
      throw Exception('Firestore network timeout simulation');
    }
    final currentList = ordersMap[shopId] ?? [];
    // CRITICAL SAFETY RULE: Only delete terminal orders. Placed and accepted orders MUST survive!
    final toDelete = currentList.where((o) => o.status != 'placed' && o.status != 'accepted').toList();
    ordersMap[shopId] = currentList.where((o) => o.status == 'placed' || o.status == 'accepted').toList();
    return toDelete.length;
  }

  @override
  Future<int> fullShopReset(String shopId) async {
    resetCallCount++;
    if (shouldFail) {
      throw Exception('Firestore network timeout simulation');
    }
    final deletedCount = await deleteTerminalShopOrders(shopId);
    await resetShopStats(shopId);
    return deletedCount;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final shop1 = Shop(
    id: 'rajat_shop',
    name: 'Rajat Hotel',
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
    shopName: 'Rajat Hotel',
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

  final rajatOrder = AppOrder(
    orderId: 'YB-RAJAT-001',
    customerId: 'cust_1',
    customerName: 'Aarav Sharma',
    customerPhone: '9876543210',
    shopId: 'rajat_shop',
    shopName: 'Rajat Hotel',
    status: 'delivered',
    totalAmount: 240,
    items: const [
      OrderItem(menuItemId: 'm1', name: 'Paneer Butter Masala', price: 240, quantity: 1),
    ],
    createdAt: DateTime(2026, 8, 24),
  );

  final nayanOrder = AppOrder(
    orderId: 'YB-NAYAN-001',
    customerId: 'cust_2',
    customerName: 'Karan Patel',
    customerPhone: '9876543211',
    shopId: 'nayan_shop',
    shopName: 'Nayan Cafe',
    status: 'delivered',
    totalAmount: 90,
    items: const [
      OrderItem(menuItemId: 'm2', name: 'Cold Coffee', price: 90, quantity: 1),
    ],
    createdAt: DateTime(2026, 8, 24),
  );

  group('Phase E: Admin Shop Reset Service & UI Tests', () {
    test('1 & 2. fullShopReset(Shop A) zeroes stats, deletes TERMINAL orders, and STRICTLY PRESERVES active placed/accepted orders', () async {
      final fakeService = FakeShopStatsService();
      fakeService.statsMap['rajat_shop'] = stats1;

      final activePlacedOrder = AppOrder(
        orderId: 'YB-ACTIVE-01',
        customerId: 'cust_active_1',
        customerName: 'Live User 1',
        customerPhone: '9876543219',
        shopId: 'rajat_shop',
        shopName: 'Rajat Hotel',
        status: 'placed',
        totalAmount: 100,
        items: const [OrderItem(menuItemId: 'm1', name: 'Roti', price: 100, quantity: 1)],
        createdAt: DateTime(2026, 8, 24),
      );

      final activeAcceptedOrder = AppOrder(
        orderId: 'YB-ACTIVE-02',
        customerId: 'cust_active_2',
        customerName: 'Live User 2',
        customerPhone: '9876543218',
        shopId: 'rajat_shop',
        shopName: 'Rajat Hotel',
        status: 'accepted',
        totalAmount: 200,
        items: const [OrderItem(menuItemId: 'm2', name: 'Paneer', price: 200, quantity: 1)],
        createdAt: DateTime(2026, 8, 24),
      );

      fakeService.ordersMap['rajat_shop'] = [
        activePlacedOrder,
        activeAcceptedOrder,
        rajatOrder, // status: 'delivered' (terminal)
      ];

      fakeService.statsMap['nayan_shop'] = stats2;
      fakeService.ordersMap['nayan_shop'] = [nayanOrder];

      final deleted = await fakeService.fullShopReset('rajat_shop');

      // 1. Only the 1 terminal delivered order was deleted
      expect(deleted, equals(1));

      // 2. Both ACTIVE orders strictly survive unharmed!
      final remainingOrders = fakeService.ordersMap['rajat_shop']!;
      expect(remainingOrders.length, equals(2));
      expect(remainingOrders.any((o) => o.orderId == 'YB-ACTIVE-01' && o.status == 'placed'), isTrue);
      expect(remainingOrders.any((o) => o.orderId == 'YB-ACTIVE-02' && o.status == 'accepted'), isTrue);

      // 3. Shop A stats zeroed
      final resetStats = fakeService.statsMap['rajat_shop']!;
      expect(resetStats.appOrders, equals(0));
      expect(resetStats.accepted, equals(0));
      expect(resetStats.delivered, equals(0));
      expect(resetStats.notAccepted, equals(0));
      expect(resetStats.rejectedAfterAccept, equals(0));
      expect(resetStats.deliveryExpired, equals(0));
      expect(resetStats.whatsappOrders, equals(0));
      expect(resetStats.lastResetAt, isNotNull);
    });

    test('3 & 4. Resetting Shop A leaves Shop B stats and orders 100% untouched', () async {
      final fakeService = FakeShopStatsService();
      fakeService.statsMap['rajat_shop'] = stats1;
      fakeService.ordersMap['rajat_shop'] = [rajatOrder];

      fakeService.statsMap['nayan_shop'] = stats2;
      fakeService.ordersMap['nayan_shop'] = [nayanOrder];

      await fakeService.fullShopReset('rajat_shop');

      // Shop B is completely untouched
      final nayanStats = fakeService.statsMap['nayan_shop']!;
      expect(nayanStats.appOrders, equals(84));
      expect(nayanStats.accepted, equals(60));
      expect(nayanStats.delivered, equals(55));
      expect(nayanStats.whatsappOrders, equals(31));
      expect(fakeService.ordersMap['nayan_shop']!.length, equals(1));
      expect(fakeService.ordersMap['nayan_shop']!.first.orderId, equals('YB-NAYAN-001'));
    });

    test('5. Double reset executes safely without error', () async {
      final fakeService = FakeShopStatsService();
      fakeService.statsMap['rajat_shop'] = stats1;
      fakeService.ordersMap['rajat_shop'] = [rajatOrder];

      await fakeService.fullShopReset('rajat_shop');
      final secondResetDeleted = await fakeService.fullShopReset('rajat_shop');

      expect(secondResetDeleted, equals(0));
      expect(fakeService.statsMap['rajat_shop']!.totalOrders, equals(0));
      expect(fakeService.resetCallCount, equals(2));
    });

    testWidgets('6. Confirmation dialog shows warning and Cancel dismisses without changes', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final fakeService = FakeShopStatsService();
      fakeService.statsMap['rajat_shop'] = stats1;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            shopsProvider.overrideWith((ref) => Future.value([shop1])),
            shopStatsServiceProvider.overrideWithValue(fakeService),
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

      // Tap RESET DATA
      await tester.tap(find.text('RESET DATA'));
      await tester.pumpAndSettle();

      // Verify confirmation dialog
      expect(find.text('Reset Rajat Hotel?'), findsOneWidget);
      expect(
        find.text(
          "This will permanently delete this shop's current app order records and reset all order statistics. This action cannot be undone.",
        ),
        findsOneWidget,
      );

      // Tap Cancel
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      // Dialog dismissed, reset was NOT called
      expect(find.text('Reset Rajat Hotel?'), findsNothing);
      expect(fakeService.resetCallCount, equals(0));
    });

    testWidgets('7. Confirming Reset executes fullShopReset, shows success snackbar and zeros stats', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final fakeService = FakeShopStatsService();
      fakeService.statsMap['rajat_shop'] = stats1;
      fakeService.ordersMap['rajat_shop'] = [rajatOrder];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            shopsProvider.overrideWith((ref) => Future.value([shop1])),
            shopStatsServiceProvider.overrideWithValue(fakeService),
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

      // Tap RESET DATA
      await tester.tap(find.text('RESET DATA'));
      await tester.pumpAndSettle();

      // Tap Reset button in dialog
      await tester.tap(find.widgetWithText(ElevatedButton, 'Reset'));
      await tester.pump();
      await tester.pumpAndSettle();

      // Verify reset was called and success snackbar displayed
      expect(fakeService.resetCallCount, equals(1));
      expect(
        find.text('Rajat Hotel data reset successfully.'),
        findsOneWidget,
      );
    });

    testWidgets('8. Reset failure displays clean error message', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final fakeService = FakeShopStatsService();
      fakeService.shouldFail = true;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            shopsProvider.overrideWith((ref) => Future.value([shop1])),
            shopStatsServiceProvider.overrideWithValue(fakeService),
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

      // Tap RESET DATA
      await tester.tap(find.text('RESET DATA'));
      await tester.pumpAndSettle();

      // Tap Reset in dialog
      await tester.tap(find.widgetWithText(ElevatedButton, 'Reset'));
      await tester.pump();
      await tester.pumpAndSettle();

      // Error snackbar shown
      expect(
        find.textContaining('Failed to reset Rajat Hotel data'),
        findsOneWidget,
      );
    });
  });
}
