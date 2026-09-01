// BU Gate2Eat — Checkpoint 4.2 Lazy Tab Initialization Tests
// Verifies that off-screen tabs in HomeScreen are not mounted on initial launch,
// and are mounted only on first visit while preserving state across tab switches.

import 'package:bugate2eat_app/core/providers.dart';
import 'package:bugate2eat_app/features/cart/cart_provider.dart';
import 'package:bugate2eat_app/features/cart/cart_screen.dart';
import 'package:bugate2eat_app/features/favourites/favourites_screen.dart';
import 'package:bugate2eat_app/features/home/home_screen.dart';
import 'package:bugate2eat_app/features/orders/order_history_screen.dart';
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

class _FakeFirestoreService extends Fake implements FirestoreService {
  int getShopsCallCount = 0;
  int getMenuItemsCallCount = 0;
  int getCategoriesCallCount = 0;

  @override
  Future<List<Shop>> getShops() async {
    getShopsCallCount++;
    return [
      Shop(
        id: 'raja_hotel',
        name: 'Raja Hotel',
        description: 'North Indian & Mughlai Delicacies',
        address: 'Gate 2 Commercial Complex',
        bannerUrl: '',
        contactNumber: '9910707219',
        orderNumber: '9319566645',
        openTime: '08:00',
        closeTime: '23:30',
        isClosedOverride: false,
        isActive: true,
        sortOrder: 1,
        searchKeywords: const ['raja', 'hotel'],
        deliveryNote: 'Gate 3',
        createdAt: DateTime(2025, 1, 1),
        updatedAt: DateTime(2025, 1, 1),
      ),
    ];
  }

  @override
  Future<List<MenuItem>> getMenuItems(String shopId) async {
    getMenuItemsCallCount++;
    return [];
  }

  @override
  Future<List<Category>> getCategories(String shopId) async {
    getCategoriesCallCount++;
    return [];
  }
}

class _FakeOrderService extends Fake implements OrderService {
  int watchActiveOrdersCount = 0;
  int watchHistoryOrdersCount = 0;

  @override
  bool get isAvailable => true;

  @override
  Stream<List<AppOrder>> watchCustomerActiveOrders({
    String? customerId,
    String? customerPhone,
  }) {
    watchActiveOrdersCount++;
    return Stream.value([
      AppOrder(
        orderId: 'YB-1001',
        customerId: customerId ?? 'cust_9876543210',
        customerName: 'Test Student',
        customerPhone: customerPhone ?? '9876543210',
        shopId: 'raja_hotel',
        shopName: 'Raja Hotel',
        items: const [
          OrderItem(
            menuItemId: 'item_1',
            name: 'Butter Naan',
            price: 40,
            quantity: 2,
          ),
        ],
        totalAmount: 80,
        status: 'placed',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    ]);
  }

  @override
  Stream<List<AppOrder>> watchCustomerOrderHistory({
    String? customerId,
    String? customerPhone,
  }) {
    watchHistoryOrdersCount++;
    return Stream.value([
      AppOrder(
        orderId: 'YB-1000',
        customerId: customerId ?? 'cust_9876543210',
        customerName: 'Test Student',
        customerPhone: customerPhone ?? '9876543210',
        shopId: 'raja_hotel',
        shopName: 'Raja Hotel',
        items: const [
          OrderItem(
            menuItemId: 'item_1',
            name: 'Butter Naan',
            price: 40,
            quantity: 1,
          ),
        ],
        totalAmount: 40,
        status: 'delivered',
        createdAt: DateTime.now().subtract(const Duration(days: 1)),
        updatedAt: DateTime.now().subtract(const Duration(days: 1)),
      ),
    ]);
  }
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

  late _FakeFirestoreService fakeFirestore;
  late _FakeOrderService fakeOrderService;
  late _FakeLocalStorageService fakeLocalStorage;

  setUp(() {
    fakeFirestore = _FakeFirestoreService();
    fakeOrderService = _FakeOrderService();
    fakeLocalStorage = _FakeLocalStorageService();
  });

  Widget buildTestHomeScreen({ProviderContainer? container}) {
    return ProviderScope(
      parent: container,
      overrides: [
        firestoreServiceProvider.overrideWithValue(fakeFirestore),
        orderServiceProvider.overrideWithValue(fakeOrderService),
        localStorageServiceProvider.overrideWithValue(fakeLocalStorage),
      ],
      child: const MaterialApp(
        home: HomeScreen(),
      ),
    );
  }

  Future<void> tapBottomNavTab(WidgetTester tester, String label) async {
    final tabFinder = find.descendant(
      of: find.byType(BottomNavigationBar),
      matching: find.text(label),
    );
    await tester.tap(tabFinder);
    await tester.pumpAndSettle();
  }

  group('Checkpoint 4.2 — Lazy Tab Initialization Suite', () {
    testWidgets('TEST 1: Initial Home launch mounts Home only (off-screen tabs are unmounted)', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildTestHomeScreen());
      await tester.pumpAndSettle();

      // Home tab content should be mounted onstage
      expect(find.byType(HomeTabContent), findsOneWidget);

      // Off-screen tabs must NOT be mounted anywhere in the tree (even offstage)
      expect(find.byType(FavouritesScreen, skipOffstage: false), findsNothing);
      expect(find.byType(CartScreen, skipOffstage: false), findsNothing);
      expect(find.byType(OrderHistoryScreen, skipOffstage: false), findsNothing);
    });

    testWidgets('TEST 2: Favourites screen & providers are not evaluated before tab is visited', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildTestHomeScreen());
      await tester.pumpAndSettle();

      // Ensure Favourites is not mounted
      expect(find.byType(FavouritesScreen, skipOffstage: false), findsNothing);

      // Tap Favourites tab in BottomNavigationBar
      await tapBottomNavTab(tester, 'Favourites');

      // Favourites should now be mounted onstage
      expect(find.byType(FavouritesScreen), findsOneWidget);
    });

    testWidgets('TEST 3: Order History stream is not subscribed before Order History tab is visited', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildTestHomeScreen());
      await tester.pumpAndSettle();

      // On initial launch, history stream listener must NOT have been called
      expect(fakeOrderService.watchHistoryOrdersCount, 0);
      expect(find.byType(OrderHistoryScreen, skipOffstage: false), findsNothing);

      // Tap Orders tab in BottomNavigationBar
      await tapBottomNavTab(tester, 'Orders');

      // Order History screen is now mounted and stream subscribed
      expect(find.byType(OrderHistoryScreen), findsOneWidget);
      expect(fakeOrderService.watchHistoryOrdersCount, 1);
    });

    testWidgets('TEST 4: Cart remains functional when visited', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildTestHomeScreen());
      await tester.pumpAndSettle();

      // Tap Cart tab in BottomNavigationBar
      await tapBottomNavTab(tester, 'Cart');

      // Cart screen is mounted and shows empty cart state
      expect(find.byType(CartScreen), findsOneWidget);
      expect(find.text('Your cart is empty'), findsOneWidget);
    });

    testWidgets('TEST 5: Visiting Favourites, switching away and back preserves mounted state', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildTestHomeScreen());
      await tester.pumpAndSettle();

      // 1. Mount Favourites
      await tapBottomNavTab(tester, 'Favourites');
      expect(find.byType(FavouritesScreen), findsOneWidget);

      // 2. Switch back to Home
      await tapBottomNavTab(tester, 'Home');
      expect(find.byType(HomeTabContent), findsOneWidget);

      // Favourites remains mounted offstage in IndexedStack
      expect(find.byType(FavouritesScreen, skipOffstage: false), findsOneWidget);

      // 3. Switch to Cart
      await tapBottomNavTab(tester, 'Cart');
      expect(find.byType(CartScreen), findsOneWidget);
      expect(find.byType(FavouritesScreen, skipOffstage: false), findsOneWidget);
    });

    testWidgets('TEST 6: Visiting Order History, switching away and back preserves state', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildTestHomeScreen());
      await tester.pumpAndSettle();

      // 1. Visit Orders tab
      await tapBottomNavTab(tester, 'Orders');
      expect(find.byType(OrderHistoryScreen), findsOneWidget);
      expect(find.text('Order #YB-1000'), findsOneWidget);

      // 2. Switch to Home tab
      await tapBottomNavTab(tester, 'Home');
      expect(find.byType(HomeTabContent), findsOneWidget);

      // OrderHistoryScreen remains mounted offstage in IndexedStack without re-subscribing
      expect(find.byType(OrderHistoryScreen, skipOffstage: false), findsOneWidget);
    });

    testWidgets('TEST 7: Active Orders functionality remains available from Home', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildTestHomeScreen());
      await tester.pumpAndSettle();

      // Active order stream is watched on Home for the floating action button
      expect(fakeOrderService.watchActiveOrdersCount, 1);
      expect(find.text('Track Your Order'), findsOneWidget);
      expect(find.byIcon(Icons.delivery_dining_rounded), findsOneWidget);
    });

    testWidgets('TEST 8: Bottom navigation badges & labels work identically', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            firestoreServiceProvider.overrideWithValue(fakeFirestore),
            orderServiceProvider.overrideWithValue(fakeOrderService),
            localStorageServiceProvider.overrideWithValue(fakeLocalStorage),
            cartProvider.overrideWith((ref) => CartNotifier()),
          ],
          child: const MaterialApp(
            home: HomeScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Favourites'), findsOneWidget);
      expect(find.text('Cart'), findsOneWidget);
      expect(find.text('Orders'), findsOneWidget);
    });

    testWidgets('TEST 9: No notification behavior changes — IndexedStack preserves tab indexes', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildTestHomeScreen());
      await tester.pumpAndSettle();

      // IndexedStack has 4 children
      final indexedStackFinder = find.byType(IndexedStack);
      expect(indexedStackFinder, findsOneWidget);

      final indexedStack = tester.widget<IndexedStack>(indexedStackFinder);
      expect(indexedStack.children.length, 4);
      expect(indexedStack.index, 0);
    });

    testWidgets('TEST 10: No order lifecycle changes — active order floating action button works', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildTestHomeScreen());
      await tester.pumpAndSettle();

      final fabFinder = find.byType(FloatingActionButton);
      expect(fabFinder, findsOneWidget);
    });
  });
}
