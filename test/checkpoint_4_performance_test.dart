// BU Gate2Eat — Tests
// Checkpoint 4: Low-End / Old Android Optimization Tests

import 'dart:async';

import 'package:bugate2eat_app/core/providers.dart';
import 'package:bugate2eat_app/features/cart/cart_provider.dart';
import 'package:bugate2eat_app/features/home/home_screen.dart';
import 'package:bugate2eat_app/features/home/widgets/shop_card.dart';
import 'package:bugate2eat_app/features/orders/widgets/universal_order_card.dart';
import 'package:bugate2eat_app/features/shop/shop_detail_screen.dart';
import 'package:bugate2eat_app/models/cart_item_model.dart';
import 'package:bugate2eat_app/models/cart_state_model.dart';
import 'package:bugate2eat_app/models/menu_item_model.dart';
import 'package:bugate2eat_app/models/order_model.dart';
import 'package:bugate2eat_app/models/shop_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final testShop = Shop(
    id: 'shop_1',
    name: 'Raja Hotel',
    description: 'Delicious food',
    bannerUrl: '',
    contactNumber: '9191919191',
    orderNumber: '9191919191',
    openTime: '08:00',
    closeTime: '23:30',
    isClosedOverride: false,
    isActive: true,
    sortOrder: 1,
    searchKeywords: ['raja', 'hotel'],
    deliveryNote: 'Pickup from Gate 3',
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );

  AppOrder createTestOrder({
    required String orderId,
    required String status,
  }) {
    return AppOrder(
      orderId: orderId,
      shopId: 'shop_1',
      shopName: 'Raja Hotel',
      customerId: 'user_123',
      customerName: 'Test Customer',
      customerPhone: '9876543210',
      items: const [
        OrderItem(
          menuItemId: 'item_1',
          name: 'Burger',
          price: 99,
          quantity: 1,
        ),
      ],
      totalAmount: 99.0,
      createdAt: DateTime.now(),
      status: status,
    );
  }

  group('Checkpoint 4: RepaintBoundary Isolation Tests', () {
    testWidgets('ShopCard wraps content in RepaintBoundary to isolate PageView slideshow repaints', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: ShopCard(
                shop: testShop,
                onTap: () {},
              ),
            ),
          ),
        ),
      );

      // Verify ShopCard renders
      expect(find.byType(ShopCard), findsOneWidget);

      // Verify RepaintBoundary is directly inside ShopCard
      final repaintBoundaryFinder = find.descendant(
        of: find.byType(ShopCard),
        matching: find.byType(RepaintBoundary),
      );
      expect(repaintBoundaryFinder, findsWidgets);
    });

    testWidgets('UniversalOrderCard wraps content in RepaintBoundary to isolate 1s ticker repaints', (tester) async {
      final order = createTestOrder(orderId: 'YB-TEST-001', status: 'placed');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: UniversalOrderCard(
              order: order,
            ),
          ),
        ),
      );

      // Verify UniversalOrderCard renders
      expect(find.byType(UniversalOrderCard), findsOneWidget);

      // Verify RepaintBoundary is directly inside UniversalOrderCard
      final repaintBoundaryFinder = find.descendant(
        of: find.byType(UniversalOrderCard),
        matching: find.byType(RepaintBoundary),
      );
      expect(repaintBoundaryFinder, findsWidgets);
    });
  });

  group('Checkpoint 4: HomeScreen Selective Rebuild & FAB Isolation Tests', () {
    testWidgets('HomeScreen FAB is absent when there are no active orders', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            shopsProvider.overrideWith((ref) async => [testShop]),
            customerActiveOrdersStreamProvider.overrideWith((ref) => Stream.value([])),
          ],
          child: const MaterialApp(
            home: HomeScreen(),
          ),
        ),
      );

      await tester.pump();

      // Verify no floating action button or Track Your Order text
      expect(find.text('Track Your Order'), findsNothing);
      expect(find.byIcon(Icons.delivery_dining_rounded), findsNothing);
    });

    testWidgets('HomeScreen FAB renders "Track Your Order" when exactly 1 active order exists', (tester) async {
      final order1 = createTestOrder(orderId: 'YB-TEST-001', status: 'placed');

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            shopsProvider.overrideWith((ref) async => [testShop]),
            customerActiveOrdersStreamProvider.overrideWith((ref) => Stream.value([order1])),
          ],
          child: const MaterialApp(
            home: HomeScreen(),
          ),
        ),
      );

      await tester.pump();

      // Verify FAB appears with "Track Your Order"
      expect(find.text('Track Your Order'), findsOneWidget);
      expect(find.byIcon(Icons.delivery_dining_rounded), findsOneWidget);
    });

    testWidgets('HomeScreen FAB renders "Active Orders (2)" when multiple active orders exist', (tester) async {
      final order1 = createTestOrder(orderId: 'YB-TEST-001', status: 'placed');
      final order2 = createTestOrder(orderId: 'YB-TEST-002', status: 'accepted');

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            shopsProvider.overrideWith((ref) async => [testShop]),
            customerActiveOrdersStreamProvider.overrideWith((ref) => Stream.value([order1, order2])),
          ],
          child: const MaterialApp(
            home: HomeScreen(),
          ),
        ),
      );

      await tester.pump();

      // Verify FAB appears with count
      expect(find.text('Active Orders (2)'), findsOneWidget);
      expect(find.byIcon(Icons.delivery_dining_rounded), findsOneWidget);
    });

    testWidgets('HomeScreen cart tab reflects cart totalItemCount via select', (tester) async {
      const cartItem = CartItem(
        menuItem: MenuItem(
          id: 'item_1',
          name: 'Burger',
          price: 99,
          details: 'Juicy Burger',
          imageUrl: '',
          isVeg: true,
          isAvailable: true,
          isRecommended: false,
          categoryId: 'cat_1',
          sortOrder: 1,
        ),
        shopId: 'shop_1',
        shopName: 'Raja Hotel',
        quantity: 3,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            cartProvider.overrideWith((ref) {
              final notifier = CartNotifier();
              notifier.state = const CartState(items: [cartItem], shopId: 'shop_1');
              return notifier;
            }),
            shopsProvider.overrideWith((ref) async => [testShop]),
            customerActiveOrdersStreamProvider.overrideWith((ref) => Stream.value([])),
          ],
          child: const MaterialApp(
            home: HomeScreen(),
          ),
        ),
      );

      await tester.pump();

      // Verify cart badge displays item count (3)
      expect(find.text('3'), findsOneWidget);
    });
  });

  group('Checkpoint 4: GPU Shader / ImageFiltered Bypass Tests', () {
    testWidgets('ShopDetailScreen does not mount ImageFiltered when banner is expanded (rest state)', (tester) async {
      final bannerShop = testShop.copyWith(bannerUrl: 'https://example.com/banner.jpg');
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            shopsProvider.overrideWith((ref) async => [bannerShop]),
            shopMenuItemsProvider(bannerShop.id).overrideWith((ref) async => []),
            shopCategoriesProvider(bannerShop.id).overrideWith((ref) async => []),
          ],
          child: MaterialApp(
            home: ShopDetailScreen(shopId: bannerShop.id),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // At rest (uncollapsed), blurSigma is 0.0, so ImageFiltered should NOT be mounted
      expect(find.byType(ImageFiltered), findsNothing);
    });
  });
}

