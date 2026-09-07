// BU Gate2Eat — Checkpoint 4: Edge Cases + Full Bug Hunt Test Suite

import 'package:bugate2eat_app/core/constants/app_constants.dart';
import 'package:bugate2eat_app/core/providers.dart';
import 'package:bugate2eat_app/features/cart/cart_provider.dart';
import 'package:bugate2eat_app/features/orders/reorder_helper.dart';
import 'package:bugate2eat_app/models/cart_item_model.dart';
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
import 'package:shared_preferences/shared_preferences.dart';

class MockEdgeCaseFirestoreService implements FirestoreService {
  MockEdgeCaseFirestoreService({
    this.shopMap = const {},
    this.menuMap = const {},
    this.failOnShopId,
  });

  final Map<String, Shop?> shopMap;
  final Map<String, List<MenuItem>> menuMap;
  final String? failOnShopId;

  @override
  Future<Shop?> getShop(String shopId) async {
    if (shopId == failOnShopId) {
      throw Exception('Simulated network failure getting shop $shopId');
    }
    return shopMap[shopId];
  }

  @override
  Future<List<MenuItem>> getMenuItems(String shopId) async {
    if (shopId == failOnShopId) {
      throw Exception('Simulated network failure getting menu items for $shopId');
    }
    return menuMap[shopId] ?? [];
  }

  @override
  Future<List<Category>> getCategories(String shopId) async => [];

  @override
  Future<List<Shop>> getShops() async {
    return shopMap.values.whereType<Shop>().toList();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  // ══════════════════════════════════════════════════════════════════════════
  // GROUP 1: SHOP HOURS & MIDNIGHT-CROSSING EDGE CASES
  // ══════════════════════════════════════════════════════════════════════════
  group('Shop Hours & Midnight-Crossing Edge Cases', () {
    test('Standard daytime: 08:00 -> 20:00 boundary tests', () {
      const openTime = '08:00';
      const closeTime = '20:00';

      // Exactly at open time (08:00) -> Open
      expect(
        Shop.isShopOpenAt(
          openTime: openTime,
          closeTime: closeTime,
          time: DateTime(2026, 9, 7, 8, 0),
        ),
        isTrue,
      );

      // Midday (14:30) -> Open
      expect(
        Shop.isShopOpenAt(
          openTime: openTime,
          closeTime: closeTime,
          time: DateTime(2026, 9, 7, 14, 30),
        ),
        isTrue,
      );

      // 1 minute before close time (19:59) -> Open
      expect(
        Shop.isShopOpenAt(
          openTime: openTime,
          closeTime: closeTime,
          time: DateTime(2026, 9, 7, 19, 59),
        ),
        isTrue,
      );

      // Exactly at close time (20:00) -> Closed
      expect(
        Shop.isShopOpenAt(
          openTime: openTime,
          closeTime: closeTime,
          time: DateTime(2026, 9, 7, 20, 0),
        ),
        isFalse,
      );

      // 1 minute before open time (07:59) -> Closed
      expect(
        Shop.isShopOpenAt(
          openTime: openTime,
          closeTime: closeTime,
          time: DateTime(2026, 9, 7, 7, 59),
        ),
        isFalse,
      );
    });

    test('Midnight-crossing: 20:00 -> 02:00 tests', () {
      const openTime = '20:00';
      const closeTime = '02:00';

      // Exactly at open time (20:00) -> Open
      expect(
        Shop.isShopOpenAt(
          openTime: openTime,
          closeTime: closeTime,
          time: DateTime(2026, 9, 7, 20, 0),
        ),
        isTrue,
      );

      // Late night (23:59) -> Open
      expect(
        Shop.isShopOpenAt(
          openTime: openTime,
          closeTime: closeTime,
          time: DateTime(2026, 9, 7, 23, 59),
        ),
        isTrue,
      );

      // Midnight exactly (00:00) -> Open
      expect(
        Shop.isShopOpenAt(
          openTime: openTime,
          closeTime: closeTime,
          time: DateTime(2026, 9, 7, 0, 0),
        ),
        isTrue,
      );

      // Post-midnight early morning (01:59) -> Open
      expect(
        Shop.isShopOpenAt(
          openTime: openTime,
          closeTime: closeTime,
          time: DateTime(2026, 9, 7, 1, 59),
        ),
        isTrue,
      );

      // Exactly at close time (02:00) -> Closed
      expect(
        Shop.isShopOpenAt(
          openTime: openTime,
          closeTime: closeTime,
          time: DateTime(2026, 9, 7, 2, 0),
        ),
        isFalse,
      );

      // Daytime outside window (12:00) -> Closed
      expect(
        Shop.isShopOpenAt(
          openTime: openTime,
          closeTime: closeTime,
          time: DateTime(2026, 9, 7, 12, 0),
        ),
        isFalse,
      );
    });

    test('Full day: 00:00 -> 23:59 tests', () {
      const openTime = '00:00';
      const closeTime = '23:59';

      expect(
        Shop.isShopOpenAt(
          openTime: openTime,
          closeTime: closeTime,
          time: DateTime(2026, 9, 7, 0, 0),
        ),
        isTrue,
      );

      expect(
        Shop.isShopOpenAt(
          openTime: openTime,
          closeTime: closeTime,
          time: DateTime(2026, 9, 7, 12, 0),
        ),
        isTrue,
      );

      expect(
        Shop.isShopOpenAt(
          openTime: openTime,
          closeTime: closeTime,
          time: DateTime(2026, 9, 7, 23, 58),
        ),
        isTrue,
      );

      expect(
        Shop.isShopOpenAt(
          openTime: openTime,
          closeTime: closeTime,
          time: DateTime(2026, 9, 7, 23, 59),
        ),
        isFalse,
      );
    });

    test('Identical times (openTime == closeTime) returns false', () {
      expect(
        Shop.isShopOpenAt(
          openTime: '10:00',
          closeTime: '10:00',
          time: DateTime(2026, 9, 7, 10, 0),
        ),
        isFalse,
      );
    });

    test('isClosedOverride and isActive override timings', () {
      expect(
        Shop.isShopOpenAt(
          openTime: '08:00',
          closeTime: '22:00',
          time: DateTime(2026, 9, 7, 12, 0),
          isClosedOverride: true,
        ),
        isFalse,
      );

      expect(
        Shop.isShopOpenAt(
          openTime: '08:00',
          closeTime: '22:00',
          time: DateTime(2026, 9, 7, 12, 0),
          isActive: false,
        ),
        isFalse,
      );
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // GROUP 2: DATA INTEGRITY & MALFORMED DOCUMENT DESERIALIZATION
  // ══════════════════════════════════════════════════════════════════════════
  group('Data Integrity & Malformed Document Deserialization', () {
    test('OrderItem.fromMap handles corrupted selectedOptions array and clamps', () {
      final corruptedMap = {
        'itemId': 'item_1',
        'name': 'Test Item',
        'price': 1500000, // Exceeds 100,000 max bound
        'quantity': 500, // Exceeds 99 max bound
        'selectedOptions': [
          null, // Corrupted null entry
          'not_a_map', // Corrupted string entry
          123, // Corrupted int entry
          {
            'groupId': 'g1',
            'groupName': 'Size',
            'optionId': 'opt1',
            'optionName': 'Large',
            'pricingType': 'fixedPrice',
            'price': 120,
          },
        ],
      };

      final item = OrderItem.fromMap(corruptedMap);
      expect(item.menuItemId, equals('item_1'));
      expect(item.name, equals('Test Item'));
      expect(item.price, equals(100000)); // Clamped to 100,000
      expect(item.quantity, equals(99)); // Clamped to 99
      expect(item.selectedOptions.length, equals(1)); // Only the valid map parsed!
      expect(item.selectedOptions.first.optionName, equals('Large'));
    });

    test('AppOrder.fromMap handles corrupted items array and num types', () {
      final corruptedOrderMap = {
        'orderId': 'order_malformed_1',
        'shopId': 'shop_1',
        'shopName': 'Shop One',
        'customerName': 'Rajat',
        'customerPhone': '9876543210',
        'grandTotal': 250.5, // Double
        'deliveryCharges': 15.0, // Double
        'status': 'placed',
        'createdAt': 1757234567890, // Milliseconds timestamp
        'items': [
          null, // Corrupted null
          'invalid_item_entry',
          {
            'itemId': 'item_good',
            'name': 'Good Item',
            'price': 250,
            'quantity': 1,
          },
        ],
      };

      final order = AppOrder.fromMap(corruptedOrderMap);
      expect(order.orderId, equals('order_malformed_1'));
      expect(order.totalAmount, equals(250.5));
      expect(order.deliveryCharges, equals(15.0));
      expect(order.items.length, equals(1));
      expect(order.items.first.menuItemId, equals('item_good'));
      expect(order.createdAt.millisecondsSinceEpoch, equals(1757234567890));
    });

    test('Shop.fromMap handles double sortOrder and int/string dates', () {
      final map = {
        'name': 'Precision Shop',
        'sortOrder': 4.0, // Double from web console
        'minimumOrderAmount': 100.0,
        'deliveryCharges': 20.0,
        'createdAt': 1757234567000,
        'updatedAt': '2026-09-07T12:00:00.000Z',
      };

      final shop = Shop.fromMap(map, 'shop_prec');
      expect(shop.id, equals('shop_prec'));
      expect(shop.sortOrder, equals(4));
      expect(shop.minimumOrderAmount, equals(100));
      expect(shop.deliveryCharges, equals(20));
      expect(shop.createdAt.millisecondsSinceEpoch, equals(1757234567000));
      expect(shop.updatedAt.isUtc, isTrue);
    });

    test('CartItem price and quantity clamping', () {
      const menuItem = MenuItem(
        id: 'm1',
        name: 'Item',
        price: -50, // Corrupted negative price in catalog
        details: '',
        imageUrl: '',
        categoryId: 'c1',
        isVeg: true,
        isAvailable: true,
        isRecommended: false,
        sortOrder: 1,
      );

      final cartItem = CartItem(
        menuItem: menuItem,
        quantity: 150, // Exceeds 99
        shopId: 's1',
        shopName: 'Shop',
        unitPriceOverride: -10, // Negative unit price override
      );

      expect(cartItem.unitPrice, equals(0)); // Clamped to 0
      expect(cartItem.totalPrice, equals(0.0)); // Never negative
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // GROUP 3: CUSTOMER FLOW EDGE CASES
  // ══════════════════════════════════════════════════════════════════════════
  group('Customer Flow Edge Cases', () {
    testWidgets('Reorder previous order when target shop was deleted',
        (tester) async {
      final mockFirestore = MockEdgeCaseFirestoreService(
        shopMap: const <String, Shop?>{}, // Target shop is completely missing from Firestore
      );

      final container = ProviderContainer(
        overrides: [
          firestoreServiceProvider.overrideWithValue(mockFirestore),
          shopsProvider.overrideWith((ref) => Future.value(<Shop>[])),
        ],
      );
      addTearDown(container.dispose);

      final order = AppOrder(
        orderId: 'hist_101',
        shopId: 'deleted_shop_id',
        shopName: 'Ghost Shop',
        customerName: 'Customer',
        customerPhone: '9876543210',
        customerId: 'dummy_customer_1',
        totalAmount: 100,
        createdAt: DateTime.now(),
        items: const [
          OrderItem(menuItemId: 'i1', name: 'Item 1', price: 100, quantity: 1),
        ],
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) => ElevatedButton(
                  onPressed: () => ReorderHelper.handleReorder(
                    order: order,
                    context: context,
                    ref: ref,
                  ),
                  child: const Text('Reorder'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Reorder'));
      await tester.pumpAndSettle();

      // Verify explicit 'Ghost Shop is no longer available.' message is shown
      expect(find.text('Ghost Shop is no longer available.'), findsOneWidget);

      // Cart MUST remain completely empty
      final cart = container.read(cartProvider);
      expect(cart.isEmpty, isTrue);
    });

    test('Cart quantity cannot exceed 99 on rapid additions', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      const item = MenuItem(
        id: 'burger_1',
        name: 'Burger',
        price: 80,
        details: 'Tasty',
        imageUrl: '',
        categoryId: 'fast_food',
        isVeg: true,
        isAvailable: true,
        isRecommended: false,
        sortOrder: 1,
      );

      final notifier = container.read(cartProvider.notifier);

      // Add item initially
      notifier.addItem(item, 'shop_1', 'Burger Hub');
      expect(container.read(cartProvider).items.first.quantity, equals(1));

      // Force quantity to 98
      notifier.updateQuantity('burger_1', 98);
      expect(container.read(cartProvider).items.first.quantity, equals(98));

      // Add 1 more -> reaches 99
      final added99 = notifier.addItem(item, 'shop_1', 'Burger Hub');
      expect(added99, isTrue);
      expect(container.read(cartProvider).items.first.quantity, equals(99));

      // Rapid tap when already at 99 -> returns false, stays at 99
      final added100 = notifier.addItem(item, 'shop_1', 'Burger Hub');
      expect(added100, isFalse);
      expect(container.read(cartProvider).items.first.quantity, equals(99));

      // updateQuantity > 99 clamps to 99
      notifier.updateQuantity('burger_1', 500);
      expect(container.read(cartProvider).items.first.quantity, equals(99));

      // updateQuantity <= 0 deletes item
      notifier.updateQuantity('burger_1', 0);
      expect(container.read(cartProvider).isEmpty, isTrue);
    });

    test('Favorites cleans up legacy bare key on toggleFavorite', () async {
      final prefs = await SharedPreferences.getInstance();
      final storage = LocalStorageService(prefs);

      // Simulate legacy stored favorite: bare itemId 'item_chai'
      await storage.saveFavoriteItemIds(['item_chai']);

      final notifier = FavoriteNotifier(storage);
      expect(notifier.isFavorite('item_chai', 'shop_tea'), isTrue);

      // Un-favoriting with composite shopId must remove both composite and bare key
      await notifier.toggleFavorite('item_chai', 'shop_tea');
      expect(notifier.isFavorite('item_chai', 'shop_tea'), isFalse);
      expect(notifier.state.contains('item_chai'), isFalse);
      expect(notifier.state.contains('shop_tea:item_chai'), isFalse);
    });

    test('Favorites stream isolates single shop failure and deduplicates', () async {
      final goodShop = Shop(
        id: 'shop_good',
        name: 'Good Shop',
        description: '',
        address: '',
        bannerUrl: '',
        contactNumber: '',
        orderNumber: '',
        openTime: '08:00',
        closeTime: '22:00',
        isClosedOverride: false,
        isActive: true,
        sortOrder: 1,
        searchKeywords: [],
        deliveryNote: '',
        createdAt: DateTime(2026, 9, 7),
        updatedAt: DateTime(2026, 9, 7),
      );

      const favoriteItem = MenuItem(
        id: 'item_fave',
        name: 'Favorite Momos',
        price: 90,
        details: '',
        imageUrl: '',
        categoryId: 'momo',
        isVeg: true,
        isAvailable: true,
        isRecommended: true,
        sortOrder: 1,
      );

      final mockFirestore = MockEdgeCaseFirestoreService(
        shopMap: {'shop_good': goodShop, 'shop_dead': null},
        menuMap: {'shop_good': [favoriteItem]},
        failOnShopId: 'shop_dead', // Failing shop
      );

      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('favorite_item_ids', [
        'shop_good:item_fave',
        'item_fave', // Duplicate bare key
        'shop_dead:item_gone', // Belongs to failing shop
      ]);

      final container = ProviderContainer(
        overrides: [
          localStorageServiceProvider.overrideWithValue(LocalStorageService(prefs)),
          firestoreServiceProvider.overrideWithValue(mockFirestore),
          shopsProvider.overrideWith((ref) => Future.value([goodShop])),
          shopMenuItemsProvider('shop_good')
              .overrideWith((ref) => Future.value([favoriteItem])),
          shopMenuItemsProvider('shop_dead')
              .overrideWith((ref) => Future.error(Exception('Dead shop'))),
        ],
      );
      addTearDown(container.dispose);

      final favorites = await container.read(favoriteItemsProvider.future);

      // Successfully resolved favorites without crashing
      expect(favorites.length, equals(1)); // Deduplicated!
      expect(favorites.first.item.id, equals('item_fave'));
      expect(favorites.first.shop.id, equals('shop_good'));
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // GROUP 4: ORDER STATE MACHINE & CONCURRENCY
  // ══════════════════════════════════════════════════════════════════════════
  group('Order State Machine & Concurrency Rules', () {
    test('Allowed status transitions in OrderStatusRules', () {
      // PLACED allowed transitions
      expect(
        OrderStatusRules.isValidTransition(
          OrderStatusRules.statusPlaced,
          OrderStatusRules.statusAccepted,
        ),
        isTrue,
      );
      expect(
        OrderStatusRules.isValidTransition(
          OrderStatusRules.statusPlaced,
          OrderStatusRules.statusRejected,
        ),
        isTrue,
      );
      expect(
        OrderStatusRules.isValidTransition(
          OrderStatusRules.statusPlaced,
          OrderStatusRules.statusCancelled,
        ),
        isTrue,
      );

      // ACCEPTED allowed transitions
      expect(
        OrderStatusRules.isValidTransition(
          OrderStatusRules.statusAccepted,
          OrderStatusRules.statusDelivered,
        ),
        isTrue,
      );
      expect(
        OrderStatusRules.isValidTransition(
          OrderStatusRules.statusAccepted,
          OrderStatusRules.statusRejected,
        ),
        isTrue,
      );
      expect(
        OrderStatusRules.isValidTransition(
          OrderStatusRules.statusAccepted,
          OrderStatusRules.statusDeliveryExpired,
        ),
        isTrue,
      );

      // FORBIDDEN transitions
      // Placed directly to Delivered is strictly forbidden
      expect(
        OrderStatusRules.isValidTransition(
          OrderStatusRules.statusPlaced,
          OrderStatusRules.statusDelivered,
        ),
        isFalse,
      );

      // Terminal states cannot transition to anything
      expect(
        OrderStatusRules.isValidTransition(
          OrderStatusRules.statusDelivered,
          OrderStatusRules.statusAccepted,
        ),
        isFalse,
      );
      expect(
        OrderStatusRules.isValidTransition(
          OrderStatusRules.statusRejected,
          OrderStatusRules.statusPlaced,
        ),
        isFalse,
      );
      expect(
        OrderStatusRules.isValidTransition(
          OrderStatusRules.statusCancelled,
          OrderStatusRules.statusAccepted,
        ),
        isFalse,
      );

      // Idempotency: Same status transition is always valid no-op
      expect(
        OrderStatusRules.isValidTransition(
          OrderStatusRules.statusDelivered,
          OrderStatusRules.statusDelivered,
        ),
        isTrue,
      );
    });
  });
}
