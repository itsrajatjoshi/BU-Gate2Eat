// BU Gate2Eat — Test Suite
// Checkpoint 5: Shopkeeper Identity & Data Isolation Test Suite
// Rigorous verification of Shopkeeper A -> B -> C -> D session isolation,
// widget state clearing, provider purging, cross-shop order protection, and recovery.

import 'package:bugate2eat_app/core/constants/app_constants.dart';
import 'package:bugate2eat_app/core/providers.dart';
import 'package:bugate2eat_app/core/router.dart';
import 'package:bugate2eat_app/features/orders/order_detail_screen.dart';
import 'package:bugate2eat_app/models/category_model.dart';
import 'package:bugate2eat_app/models/menu_item_model.dart';
import 'package:bugate2eat_app/models/order_model.dart';
import 'package:bugate2eat_app/models/shop_model.dart';
import 'package:bugate2eat_app/panel/shopkeeper_panel/shopkeeper_main_shell.dart';
import 'package:bugate2eat_app/services/local_storage_service.dart';
import 'package:bugate2eat_app/services/notification_router_bridge.dart';
import 'package:bugate2eat_app/services/notification_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final nowTime = DateTime(2025, 9, 5, 12, 0);

  final shopA = Shop(
    id: 'rajat_shop',
    name: 'Rajat Shop',
    description: 'Food & Rolls',
    bannerUrl: '',
    contactNumber: '8000383993',
    orderNumber: '8000383993',
    openTime: '08:00',
    closeTime: '23:00',
    isClosedOverride: false,
    isActive: true,
    sortOrder: 1,
    searchKeywords: const ['rajat'],
    deliveryNote: 'Gate 3',
    createdAt: DateTime(2025),
    updatedAt: DateTime(2025),
  );

  final shopB = Shop(
    id: 'nayan_shop',
    name: 'Nayan Shop',
    description: 'Quick Bites',
    bannerUrl: '',
    contactNumber: '8295643910',
    orderNumber: '8295643910',
    openTime: '09:00',
    closeTime: '22:00',
    isClosedOverride: false,
    isActive: true,
    sortOrder: 2,
    searchKeywords: const ['nayan'],
    deliveryNote: 'Gate 3',
    createdAt: DateTime(2025),
    updatedAt: DateTime(2025),
  );

  final shopC = Shop(
    id: 'kivisha_shop',
    name: 'Kivisha Shop',
    description: 'Juices & Shakes',
    bannerUrl: '',
    contactNumber: '8875344034',
    orderNumber: '8875344034',
    openTime: '10:00',
    closeTime: '21:00',
    isClosedOverride: false,
    isActive: true,
    sortOrder: 3,
    searchKeywords: const ['kivisha'],
    deliveryNote: 'Gate 3',
    createdAt: DateTime(2025),
    updatedAt: DateTime(2025),
  );

  final shopD = Shop(
    id: 'up16_coffee_queen',
    name: 'UP16 Coffee Queen',
    description: 'Coffee & Snacks',
    bannerUrl: '',
    contactNumber: '9999922222',
    orderNumber: '9999922222',
    openTime: '08:00',
    closeTime: '23:30',
    isClosedOverride: false,
    isActive: true,
    sortOrder: 4,
    searchKeywords: const ['queens'],
    deliveryNote: 'Gate 3',
    createdAt: DateTime(2025),
    updatedAt: DateTime(2025),
  );

  final orderA = AppOrder(
    orderId: 'ORD_A_101',
    customerId: 'cust_9876543210',
    customerName: 'Rahul Student',
    customerPhone: '9876543210',
    shopId: 'rajat_shop',
    shopName: 'Rajat Shop',
    items: const [
      OrderItem(
        menuItemId: 'item_a1',
        name: 'Veg Roll',
        price: 80,
        quantity: 1,
      ),
    ],
    totalAmount: 80.0,
    status: 'placed',
    deliveryNote: 'Gate 3',
    orderMethod: 'in_app',
    createdAt: nowTime,
    updatedAt: nowTime,
  );

  final orderB = AppOrder(
    orderId: 'ORD_B_202',
    customerId: 'cust_9111122222',
    customerName: 'Sneha Student',
    customerPhone: '9111122222',
    shopId: 'nayan_shop',
    shopName: 'Nayan Shop',
    items: const [
      OrderItem(
        menuItemId: 'item_b1',
        name: 'Cold Coffee',
        price: 60,
        quantity: 1,
      ),
    ],
    totalAmount: 60.0,
    status: 'placed',
    deliveryNote: 'Gate 3',
    orderMethod: 'in_app',
    createdAt: nowTime,
    updatedAt: nowTime,
  );

  group('Checkpoint 5 — Sequential Shopkeeper Identity & Mapping Resolution', () {
    test('1. Authoritative resolution for A, B, C, D and aliases', () {
      expect(AppAuthRoles.getShopIdForPhone('8000383993'), 'rajat_shop');
      expect(AppAuthRoles.getShopIdForPhone('8295643910'), 'nayan_shop');
      expect(AppAuthRoles.getShopIdForPhone('8875344034'), 'kivisha_shop');
      expect(AppAuthRoles.getShopIdForPhone('9999922222'), 'up16_coffee_queen');
      expect(AppAuthRoles.canonicalShopId('up16_queens'), 'up16_coffee_queen');
      expect(AppAuthRoles.canonicalShopId('up16_coffee_queen'), 'up16_coffee_queen');
    });

    test('2. Sequential Login Provider Lifecycle: A -> B -> A -> C -> D -> A', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final localStorage = LocalStorageService(prefs);

      final container = ProviderContainer(
        overrides: [
          localStorageServiceProvider.overrideWithValue(localStorage),
        ],
      );

      // --- Shopkeeper A Login ---
      await localStorage.saveUserProfile(phone: '8000383993', name: 'Rajat');
      container.read(customerIdentityProvider.notifier).refresh();
      expect(container.read(currentShopkeeperShopIdProvider), 'rajat_shop');

      // Add dummy order to test memory state
      container.read(dummyOrdersProvider.notifier).setOrders([orderA]);
      expect(container.read(dummyOrdersProvider).length, 1);

      // --- Logout A ---
      await clearCustomerSession(container);
      expect(container.read(currentShopkeeperShopIdProvider), isNull);
      expect(container.read(dummyOrdersProvider), isEmpty);
      expect(container.read(customerIdentityProvider).phone, isEmpty);

      // --- Shopkeeper B Login (A -> B) ---
      await localStorage.saveUserProfile(phone: '8295643910', name: 'Nayan');
      container.read(customerIdentityProvider.notifier).refresh();
      expect(container.read(currentShopkeeperShopIdProvider), 'nayan_shop');
      expect(container.read(dummyOrdersProvider), isEmpty);

      // --- Logout B & Shopkeeper A Login (B -> A) ---
      await clearCustomerSession(container);
      await localStorage.saveUserProfile(phone: '8000383993', name: 'Rajat');
      container.read(customerIdentityProvider.notifier).refresh();
      expect(container.read(currentShopkeeperShopIdProvider), 'rajat_shop');

      // --- Logout A & Shopkeeper C Login (A -> C) ---
      await clearCustomerSession(container);
      await localStorage.saveUserProfile(phone: '8875344034', name: 'Kivisha');
      container.read(customerIdentityProvider.notifier).refresh();
      expect(container.read(currentShopkeeperShopIdProvider), 'kivisha_shop');

      // --- Logout C & Shopkeeper D Login (C -> D) ---
      await clearCustomerSession(container);
      await localStorage.saveUserProfile(phone: '9999922222', name: 'UP16 Queens');
      container.read(customerIdentityProvider.notifier).refresh();
      expect(container.read(currentShopkeeperShopIdProvider), 'up16_coffee_queen');

      // --- Logout D & Shopkeeper A Login (D -> A) ---
      await clearCustomerSession(container);
      await localStorage.saveUserProfile(phone: '8000383993', name: 'Rajat');
      container.read(customerIdentityProvider.notifier).refresh();
      expect(container.read(currentShopkeeperShopIdProvider), 'rajat_shop');
    });
  });

  group('Checkpoint 5 — B-02: Widget & State Isolation in ShopkeeperMainShell', () {
    testWidgets('1. Switching Shopkeeper A -> B completely purges search, category and tab state', (tester) async {
      SharedPreferences.setMockInitialValues({
        'user_phone': '8000383993',
        'user_name': 'Rajat Shopkeeper',
      });
      final prefs = await SharedPreferences.getInstance();
      final localStorage = LocalStorageService(prefs);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localStorageServiceProvider.overrideWithValue(localStorage),
            shopsProvider.overrideWith((ref) async => [shopA, shopB]),
            shopCategoriesProvider.overrideWith((ref, shopId) async => [
                  Category(
                    id: 'cat_rolls',
                    name: 'Rolls',
                    sortOrder: 1,
                    shopId: shopId,
                  ),
                ]),
            shopMenuItemsProvider.overrideWith((ref, shopId) async => [
                  MenuItem(
                    id: 'item_1',
                    name: 'Special Roll',
                    details: 'Delicious Roll',
                    price: 90,
                    imageUrl: '',
                    categoryId: 'cat_rolls',
                    isVeg: true,
                    isAvailable: true,
                    isRecommended: false,
                    sortOrder: 1,
                  ),
                ]),
            shopActiveOrdersStreamProvider.overrideWith((ref, shopId) {
              if (shopId == 'rajat_shop') return Stream.value([orderA]);
              if (shopId == 'nayan_shop') return Stream.value([orderB]);
              return Stream.value(<AppOrder>[]);
            }),
            shopOrderHistoryStreamProvider.overrideWith((ref, shopId) => Stream.value(<AppOrder>[])),
          ],
          child: const MaterialApp(
            home: ShopkeeperMainShell(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify Initial Shopkeeper A (Orders Tab active)
      expect(find.text('Orders'), findsWidgets);
      expect(find.text('Active Orders'), findsOneWidget);
      expect(find.textContaining('ORD_A_101'), findsOneWidget);

      // Shopkeeper A navigates to Tab 2: "Shop"
      await tester.tap(find.text('Shop'));
      await tester.pumpAndSettle();

      // Enter search query in ShopkeeperHomeScreen
      final searchField = find.byType(TextField);
      expect(searchField, findsOneWidget);
      await tester.enterText(searchField, 'Special Roll');
      await tester.pumpAndSettle();
      expect(find.text('Special Roll'), findsWidgets);

      // Simulate Logout & Shopkeeper B Login
      await localStorage.saveUserProfile(
        phone: '8295643910',
        name: 'Nayan Shopkeeper',
      );
      final element = tester.element(find.byType(ShopkeeperMainShell));
      final container = ProviderScope.containerOf(element);
      container.read(customerIdentityProvider.notifier).refresh();
      await tester.pumpAndSettle();

      // VERIFY B-02 ISOLATION:
      // 1. Tab index reset to Tab 0 ('Orders'), NOT remaining on Tab 2
      expect(find.text('Active Orders'), findsOneWidget);

      // 2. Order A is completely gone, only Order B is visible
      expect(find.textContaining('ORD_A_101'), findsNothing);
      expect(find.textContaining('ORD_B_202'), findsOneWidget);

      // 3. Switch to Tab 2 for Shopkeeper B and verify search field is CLEAN
      await tester.tap(find.text('Shop'));
      await tester.pumpAndSettle();

      // Search controller text from Shopkeeper A MUST NOT persist
      final searchWidget = tester.widget<TextField>(find.byType(TextField));
      expect(searchWidget.controller?.text, '');
      expect(find.text('Nayan Shop'), findsWidgets);
    });

    testWidgets('2. Unauthorized / Unmapped number shows safe view and recovers on login', (tester) async {
      SharedPreferences.setMockInitialValues({
        'user_phone': '9123456780', // Unmapped customer phone
        'user_name': 'Unknown User',
      });
      final prefs = await SharedPreferences.getInstance();
      final localStorage = LocalStorageService(prefs);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localStorageServiceProvider.overrideWithValue(localStorage),
            shopsProvider.overrideWith((ref) async => [shopA]),
            shopActiveOrdersStreamProvider.overrideWith((ref, shopId) => Stream.value(<AppOrder>[])),
            shopOrderHistoryStreamProvider.overrideWith((ref, shopId) => Stream.value(<AppOrder>[])),
          ],
          child: const MaterialApp(
            home: ShopkeeperMainShell(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify safe unauthorized banner
      expect(find.text('No Shop Assigned'), findsOneWidget);
      expect(find.text('Return to Login'), findsOneWidget);

      // User switches to valid Shopkeeper C
      await localStorage.saveUserProfile(phone: '8875344034', name: 'Kivisha');
      final element = tester.element(find.byType(ShopkeeperMainShell));
      final container = ProviderScope.containerOf(element);
      container.read(customerIdentityProvider.notifier).refresh();
      await tester.pumpAndSettle();

      // Verify recovery
      expect(find.text('No Shop Assigned'), findsNothing);
      expect(find.text('No active orders'), findsOneWidget);
    });
  });

  group('Checkpoint 5 — B-03: Order Authorization in OrderDetailScreen', () {
    testWidgets('1. Shopkeeper A is BLOCKED from viewing Order of Shop B', (tester) async {
      SharedPreferences.setMockInitialValues({
        'user_phone': '8000383993', // Shopkeeper A (rajat_shop)
        'user_name': 'Rajat Shopkeeper',
      });
      final prefs = await SharedPreferences.getInstance();
      final localStorage = LocalStorageService(prefs);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localStorageServiceProvider.overrideWithValue(localStorage),
            singleOrderStreamProvider('ORD_B_202').overrideWith((ref) => Stream.value(orderB)),
          ],
          child: const MaterialApp(
            home: OrderDetailScreen(
              orderId: 'ORD_B_202',
              initialOrder: null,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Authorization guard MUST reject and display Order not found screen
      expect(find.text('Order not found'), findsOneWidget);
      expect(find.text('Cold Coffee'), findsNothing);
      expect(find.text('Sneha Student'), findsNothing);
    });

    testWidgets('2. Shopkeeper A is AUTHORIZED to view Order of Shop A', (tester) async {
      SharedPreferences.setMockInitialValues({
        'user_phone': '8000383993', // Shopkeeper A (rajat_shop)
        'user_name': 'Rajat Shopkeeper',
      });
      final prefs = await SharedPreferences.getInstance();
      final localStorage = LocalStorageService(prefs);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localStorageServiceProvider.overrideWithValue(localStorage),
            singleOrderStreamProvider('ORD_A_101').overrideWith((ref) => Stream.value(orderA)),
          ],
          child: MaterialApp(
            home: OrderDetailScreen(
              orderId: 'ORD_A_101',
              initialOrder: orderA,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Must be authorized to view own shop order
      expect(find.text('Order not found'), findsNothing);
      expect(find.text('Veg Roll'), findsWidgets);
      expect(find.textContaining('ORD_A_101'), findsWidgets);
    });
  });

  group('Checkpoint 5 — B-04: Cross-Shop Notification Authorization in NotificationRouterBridge', () {
    test('1. Shopkeeper A tapping notification for Shop B is BLOCKED', () {
      final notification = PendingNotification(
        type: 'new_order',
        orderId: 'ORD_B_202',
        shopId: 'nayan_shop',
        recipientRole: 'shopkeeper',
        receivedAt: DateTime.now(),
      );

      final route = NotificationRouterBridge.resolveRoute(
        notification: notification,
        userPhone: '8000383993', // Shopkeeper A
      );

      expect(route.isAuthorized, isFalse);
      expect(route.rejectionReason, contains('Shopkeeper unauthorized for target shop: nayan_shop'));
    });

    test('2. Shopkeeper A tapping customer-role notification for Shop B is also BLOCKED', () {
      final notification = PendingNotification(
        type: 'order_accepted',
        orderId: 'ORD_B_202',
        shopId: 'nayan_shop',
        recipientRole: 'customer',
        receivedAt: DateTime.now(),
      );

      final route = NotificationRouterBridge.resolveRoute(
        notification: notification,
        userPhone: '8000383993', // Shopkeeper A
      );

      expect(route.isAuthorized, isFalse);
      expect(route.rejectionReason, contains('Shopkeeper unauthorized for target shop: nayan_shop'));
    });

    test('3. Shopkeeper A tapping notification for Shop A is AUTHORIZED', () {
      final notification = PendingNotification(
        type: 'new_order',
        orderId: 'ORD_A_101',
        shopId: 'rajat_shop',
        recipientRole: 'shopkeeper',
        receivedAt: DateTime.now(),
      );

      final route = NotificationRouterBridge.resolveRoute(
        notification: notification,
        userPhone: '8000383993', // Shopkeeper A
      );

      expect(route.isAuthorized, isTrue);
      expect(route.shopId, 'rajat_shop');
      expect(route.route, AppRoutes.shopkeeper);
    });
  });
}
