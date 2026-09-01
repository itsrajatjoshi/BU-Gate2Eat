// BU Gate2Eat — Checkpoint 4.3 Lazy Search & Catalog Loading Tests
// Verifies that global menu & category search catalogs are not loaded on initial Home launch,
// and are only evaluated lazily when search or food-category filters are activated.

import 'package:bugate2eat_app/core/providers.dart';
import 'package:bugate2eat_app/features/home/home_screen.dart';
import 'package:bugate2eat_app/features/shop/shop_detail_screen.dart';
import 'package:bugate2eat_app/models/category_model.dart';
import 'package:bugate2eat_app/models/menu_item_model.dart';
import 'package:bugate2eat_app/models/order_model.dart';
import 'package:bugate2eat_app/models/shop_model.dart';
import 'package:bugate2eat_app/services/firestore_service.dart';
import 'package:bugate2eat_app/services/local_storage_service.dart';
import 'package:bugate2eat_app/services/order_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _SpyFirestoreService extends Fake implements FirestoreService {
  int getShopsCallCount = 0;
  int getMenuItemsCallCount = 0;
  int getCategoriesCallCount = 0;
  final Map<String, int> shopMenuItemsCalls = {};
  final Map<String, int> shopCategoriesCalls = {};

  final List<Shop> fakeShops = [
    Shop(
      id: 'shop_pizza',
      name: 'Mario Pizza Hub',
      description: 'Cheesy Pizzas & Burgers',
      address: 'Gate 2 Commercial Complex',
      bannerUrl: '',
      contactNumber: '9910707219',
      orderNumber: '9319566645',
      openTime: '08:00',
      closeTime: '23:30',
      isClosedOverride: false,
      isActive: true,
      sortOrder: 1,
      searchKeywords: const ['pizza', 'burger'],
      deliveryNote: 'Gate 2',
      createdAt: DateTime(2025, 1, 1),
      updatedAt: DateTime(2025, 1, 1),
    ),
    Shop(
      id: 'shop_dhaba',
      name: 'Punjab Dhaba',
      description: 'Authentic North Indian Thalis',
      address: 'Near Gate 2',
      bannerUrl: '',
      contactNumber: '9910707220',
      orderNumber: '9319566646',
      openTime: '10:00',
      closeTime: '22:00',
      isClosedOverride: false,
      isActive: true,
      sortOrder: 2,
      searchKeywords: const ['dhaba', 'punjab'],
      deliveryNote: 'Gate 2',
      createdAt: DateTime(2025, 1, 1),
      updatedAt: DateTime(2025, 1, 1),
    ),
  ];

  @override
  Future<List<Shop>> getShops() async {
    getShopsCallCount++;
    return fakeShops;
  }

  @override
  Future<List<MenuItem>> getMenuItems(String shopId) async {
    getMenuItemsCallCount++;
    shopMenuItemsCalls[shopId] = (shopMenuItemsCalls[shopId] ?? 0) + 1;
    if (shopId == 'shop_pizza') {
      return [
        const MenuItem(
          id: 'item_pizza_1',
          name: 'Farmhouse Pizza',
          details: 'Fresh veggies',
          price: 180,
          imageUrl: '',
          categoryId: 'cat_pizza',
          isVeg: true,
          isAvailable: true,
          isRecommended: true,
          sortOrder: 1,
        ),
      ];
    } else {
      return [
        const MenuItem(
          id: 'item_dhaba_1',
          name: 'Special Dal Makhani Thali',
          details: 'With rice and naan',
          price: 150,
          imageUrl: '',
          categoryId: 'cat_thali',
          isVeg: true,
          isAvailable: true,
          isRecommended: true,
          sortOrder: 1,
        ),
      ];
    }
  }

  @override
  Future<List<Category>> getCategories(String shopId) async {
    getCategoriesCallCount++;
    shopCategoriesCalls[shopId] = (shopCategoriesCalls[shopId] ?? 0) + 1;
    if (shopId == 'shop_pizza') {
      return [
        const Category(
          id: 'cat_pizza',
          name: 'Fast Food',
          sortOrder: 1,
          shopId: 'shop_pizza',
        ),
      ];
    } else {
      return [
        const Category(
          id: 'cat_thali',
          name: 'Thalis',
          sortOrder: 1,
          shopId: 'shop_dhaba',
        ),
      ];
    }
  }
}

class _FakeOrderService extends Fake implements OrderService {
  @override
  bool get isAvailable => true;

  @override
  Stream<List<AppOrder>> watchCustomerActiveOrders({
    String? customerId,
    String? customerPhone,
  }) =>
      Stream.value([]);

  @override
  Stream<List<AppOrder>> watchCustomerOrderHistory({
    String? customerId,
    String? customerPhone,
  }) =>
      Stream.value([]);
}

class _FakeLocalStorageService extends Fake implements LocalStorageService {
  @override
  bool get isOnboarded => true;
  @override
  String get userPhone => '9876543210';
  @override
  String get userName => 'Test Student';
  @override
  String get customerId => 'cust_9876543210';
  @override
  List<String> get favoriteItemIds => [];
  @override
  String get themeMode => 'light';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _SpyFirestoreService spyFirestore;
  late _FakeOrderService fakeOrderService;
  late _FakeLocalStorageService fakeLocalStorage;
  int allMenuItemsProviderCalls = 0;
  int allCategoriesProviderCalls = 0;

  setUp(() {
    spyFirestore = _SpyFirestoreService();
    fakeOrderService = _FakeOrderService();
    fakeLocalStorage = _FakeLocalStorageService();
    allMenuItemsProviderCalls = 0;
    allCategoriesProviderCalls = 0;
  });

  Widget buildTestHomeScreen({ProviderContainer? container}) {
    return ProviderScope(
      parent: container,
      overrides: [
        firestoreServiceProvider.overrideWithValue(spyFirestore),
        orderServiceProvider.overrideWithValue(fakeOrderService),
        localStorageServiceProvider.overrideWithValue(fakeLocalStorage),
        allShopMenuItemsProvider.overrideWith((ref) async {
          allMenuItemsProviderCalls++;
          final shops = await ref.watch(shopsProvider.future);
          final Map<String, List<MenuItem>> result = {};
          for (final shop in shops) {
            result[shop.id] = await ref.watch(shopMenuItemsProvider(shop.id).future);
          }
          return result;
        }),
        allShopCategoriesProvider.overrideWith((ref) async {
          allCategoriesProviderCalls++;
          final shops = await ref.watch(shopsProvider.future);
          final Map<String, List<Category>> result = {};
          for (final shop in shops) {
            result[shop.id] = await ref.watch(shopCategoriesProvider(shop.id).future);
          }
          return result;
        }),
      ],
      child: const MaterialApp(
        home: HomeScreen(),
      ),
    );
  }

  group('Checkpoint 4.3 — Lazy Search & Global Catalog Loading Suite', () {
    testWidgets('TEST 1: Initial Home launch renders shops without evaluating global search catalog providers', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildTestHomeScreen());
      await tester.pumpAndSettle();

      // Shops should be rendered immediately
      expect(find.text('Mario Pizza Hub'), findsOneWidget);
      expect(find.text('Punjab Dhaba'), findsOneWidget);

      // getShops was called
      expect(spyFirestore.getShopsCallCount, 1);

      // Global catalog providers were NOT evaluated!
      expect(allMenuItemsProviderCalls, 0);
      expect(allCategoriesProviderCalls, 0);
    });

    testWidgets('TEST 2: Tapping Search TextField triggers lazy global catalog initialization', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildTestHomeScreen());
      await tester.pumpAndSettle();

      expect(allMenuItemsProviderCalls, 0);
      expect(allCategoriesProviderCalls, 0);

      // Tap on search bar
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();

      // Now global search catalog should be evaluated
      expect(allMenuItemsProviderCalls, 1);
      expect(allCategoriesProviderCalls, 1);
    });

    testWidgets('TEST 3: Typing a query matches item names in catalog and filters shops accurately', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildTestHomeScreen());
      await tester.pumpAndSettle();

      // Enter search query for menu item 'pizza'
      await tester.enterText(find.byType(TextField), 'pizza');
      await tester.pumpAndSettle();

      // Only Mario Pizza Hub should be displayed
      expect(find.text('Mario Pizza Hub'), findsOneWidget);
      expect(find.text('Punjab Dhaba'), findsNothing);

      // Enter search query for 'thali'
      await tester.enterText(find.byType(TextField), 'thali');
      await tester.pumpAndSettle();

      // Only Punjab Dhaba should be displayed
      expect(find.text('Mario Pizza Hub'), findsNothing);
      expect(find.text('Punjab Dhaba'), findsOneWidget);
    });

    testWidgets('TEST 4: Clearing search query restores full shop list', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildTestHomeScreen());
      await tester.pumpAndSettle();

      // Type and filter
      await tester.enterText(find.byType(TextField), 'thali');
      await tester.pumpAndSettle();
      expect(find.text('Punjab Dhaba'), findsOneWidget);
      expect(find.text('Mario Pizza Hub'), findsNothing);

      // Tap clear icon button
      await tester.tap(find.byIcon(Icons.clear_rounded));
      await tester.pumpAndSettle();

      // Both shops should be restored
      expect(find.text('Mario Pizza Hub'), findsOneWidget);
      expect(find.text('Punjab Dhaba'), findsOneWidget);
    });

    testWidgets('TEST 5: Selecting food category filter (e.g. Fast Food) evaluates catalog and filters accurately', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildTestHomeScreen());
      await tester.pumpAndSettle();

      expect(allMenuItemsProviderCalls, 0);

      // Select 'Fast Food' filter chip
      await tester.tap(find.text('Fast Food'));
      await tester.pumpAndSettle();

      // Global catalog was loaded and filtered
      expect(allMenuItemsProviderCalls, 1);
      expect(find.text('Mario Pizza Hub'), findsOneWidget);
      expect(find.text('Punjab Dhaba'), findsNothing);
    });

    testWidgets('TEST 6: Selecting "Open Now" filter does NOT trigger global menu/category catalog', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildTestHomeScreen());
      await tester.pumpAndSettle();

      // Select 'Open Now' filter chip
      await tester.tap(find.text('Open Now'));
      await tester.pumpAndSettle();

      // 'Open Now' relies directly on shop.isOpen, so 0 global menu/category catalog queries!
      expect(allMenuItemsProviderCalls, 0);
      expect(allCategoriesProviderCalls, 0);
    });

    testWidgets('TEST 7: No duplicate catalog fetches on multiple keystrokes or filter clicks', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildTestHomeScreen());
      await tester.pumpAndSettle();

      // Keystroke 1
      await tester.enterText(find.byType(TextField), 'p');
      await tester.pumpAndSettle();
      expect(allMenuItemsProviderCalls, 1);

      // Keystroke 2
      await tester.enterText(find.byType(TextField), 'pi');
      await tester.pumpAndSettle();

      // Keystroke 3
      await tester.enterText(find.byType(TextField), 'piz');
      await tester.pumpAndSettle();

      // Should still be exactly 1 call, cached in provider memory
      expect(allMenuItemsProviderCalls, 1);
      expect(allCategoriesProviderCalls, 1);
    });

    testWidgets('TEST 8: Non-matching search displays empty state properly', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildTestHomeScreen());
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'nonexistent dish xyz');
      await tester.pumpAndSettle();

      expect(find.text('No shops found for "nonexistent dish xyz"'), findsOneWidget);
    });

    testWidgets('TEST 9: ShopDetailsScreen independent menu/category fetching is untouched', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            firestoreServiceProvider.overrideWithValue(spyFirestore),
            orderServiceProvider.overrideWithValue(fakeOrderService),
            localStorageServiceProvider.overrideWithValue(fakeLocalStorage),
          ],
          child: const MaterialApp(
            home: ShopDetailScreen(shopId: 'shop_pizza'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // ShopDetailsScreen loads its own shop-specific menu & categories
      expect(find.text('Mario Pizza Hub'), findsOneWidget);
      expect(find.text('Farmhouse Pizza'), findsOneWidget);
      expect(spyFirestore.shopMenuItemsCalls['shop_pizza'], 1);
      expect(spyFirestore.shopCategoriesCalls['shop_pizza'], 1);
      // It did NOT query shop_dhaba
      expect(spyFirestore.shopMenuItemsCalls['shop_dhaba'], isNull);
    });

    testWidgets('TEST 10: Home pull-to-refresh invalidates shopsProvider and reloads cleanly', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildTestHomeScreen());
      await tester.pumpAndSettle();

      expect(spyFirestore.getShopsCallCount, 1);

      // Perform fling down on RefreshIndicator to trigger refresh
      await tester.fling(find.byType(RefreshIndicator), const Offset(0, 400), 1000);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      expect(spyFirestore.getShopsCallCount, 2);
    });
  });
}
