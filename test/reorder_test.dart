// BU Gate2Eat — Reorder Feature Unit & Widget Test Suite

import 'package:bugate2eat_app/core/providers.dart';
import 'package:bugate2eat_app/core/router.dart';
import 'package:bugate2eat_app/features/cart/cart_provider.dart';
import 'package:bugate2eat_app/features/orders/order_detail_screen.dart';
import 'package:bugate2eat_app/features/orders/order_history_screen.dart';
import 'package:bugate2eat_app/features/orders/reorder_helper.dart';
import 'package:bugate2eat_app/models/cart_item_model.dart';
import 'package:bugate2eat_app/models/category_model.dart';
import 'package:bugate2eat_app/models/menu_item_model.dart';
import 'package:bugate2eat_app/models/order_model.dart';
import 'package:bugate2eat_app/models/shop_model.dart';
import 'package:bugate2eat_app/services/firestore_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class MockFirestoreService implements FirestoreService {
  MockFirestoreService({required this.menuItemsMap});

  final Map<String, List<MenuItem>> menuItemsMap;

  @override
  Future<List<MenuItem>> getMenuItems(String shopId) async {
    return menuItemsMap[shopId] ?? [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Reorder Logic & Cart Resolution Tests', () {
    const shopId = 'rajat_shop';
    const shopName = 'Rajat Shop';

    final deliveredOrder = AppOrder(
      orderId: 'YB-20260822-9001',
      shopId: shopId,
      shopName: shopName,
      customerName: 'Student',
      customerPhone: '9999999999',
      items: const [
        OrderItem(
          menuItemId: 'item_momos',
          name: 'Old Veg Momos',
          price: 60, // Old price
          quantity: 2,
        ),
        OrderItem(
          menuItemId: 'item_chai',
          name: 'Old Chai',
          price: 15, // Old price
          quantity: 3,
        ),
      ],
      totalAmount: 165,
      status: 'delivered',
      createdAt: DateTime.now().subtract(const Duration(days: 1)),
    );

    testWidgets(
        'Reorder populates cart with CURRENT menu prices (not old prices)',
        (tester) async {
      final container = ProviderContainer(
        overrides: [
          firestoreServiceProvider.overrideWithValue(
            MockFirestoreService(
              menuItemsMap: {
                shopId: [
                  const MenuItem(
                    id: 'item_momos',
                    name: 'Current Veg Momos',
                    price: 80, // Current updated price
                    details: 'Fresh momos',
                    imageUrl: '',
                    isVeg: true,
                    isAvailable: true,
                    isRecommended: false,
                    categoryId: 'snacks',
                    sortOrder: 1,
                  ),
                  const MenuItem(
                    id: 'item_chai',
                    name: 'Current Chai',
                    price: 25, // Current updated price
                    details: 'Hot tea',
                    imageUrl: '',
                    isVeg: true,
                    isAvailable: true,
                    isRecommended: false,
                    categoryId: 'beverages',
                    sortOrder: 2,
                  ),
                ],
              },
            ),
          ),
        ],
      );

      late BuildContext testContext;
      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) {
              testContext = context;
              return const Scaffold(body: SizedBox());
            },
          ),
          GoRoute(
            path: '/cart',
            builder: (context, state) => const Scaffold(body: Text('Cart Screen')),
          ),
        ],
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.runAsync(() async {
        await ReorderHelper.handleReorder(
          context: testContext,
          ref: _MockWidgetRef(container),
          order: deliveredOrder,
        );
      });

      final cartState = container.read(cartProvider);

      expect(cartState.items.length, equals(2));
      expect(cartState.shopId, equals(shopId));

      final momosItem =
          cartState.items.firstWhere((i) => i.menuItem.id == 'item_momos');
      expect(momosItem.quantity, equals(2));
      expect(momosItem.menuItem.price, equals(80)); // Current price 80, not 60

      final chaiItem =
          cartState.items.firstWhere((i) => i.menuItem.id == 'item_chai');
      expect(chaiItem.quantity, equals(3));
      expect(chaiItem.menuItem.price, equals(25)); // Current price 25, not 15

      expect(
        cartState.grandTotal,
        equals((80 * 2) + (25 * 3)),
      ); // 160 + 75 = 235
    });

    testWidgets('Reorder skips unavailable / out-of-stock items',
        (tester) async {
      final container = ProviderContainer(
        overrides: [
          firestoreServiceProvider.overrideWithValue(
            MockFirestoreService(
              menuItemsMap: {
                shopId: [
                  const MenuItem(
                    id: 'item_momos',
                    name: 'Current Veg Momos',
                    price: 80,
                    details: 'Fresh momos',
                    imageUrl: '',
                    isVeg: true,
                    isAvailable: true, // Available
                    isRecommended: false,
                    categoryId: 'snacks',
                    sortOrder: 1,
                  ),
                  const MenuItem(
                    id: 'item_chai',
                    name: 'Current Chai',
                    price: 25,
                    details: 'Hot tea',
                    imageUrl: '',
                    isVeg: true,
                    isAvailable: false, // OUT OF STOCK
                    isRecommended: false,
                    categoryId: 'beverages',
                    sortOrder: 2,
                  ),
                ],
              },
            ),
          ),
        ],
      );

      late BuildContext testContext;
      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) {
              testContext = context;
              return const Scaffold(body: SizedBox());
            },
          ),
          GoRoute(
            path: '/cart',
            builder: (context, state) => const Scaffold(body: Text('Cart Screen')),
          ),
        ],
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.runAsync(() async {
        await ReorderHelper.handleReorder(
          context: testContext,
          ref: _MockWidgetRef(container),
          order: deliveredOrder,
        );
      });

      final cartState = container.read(cartProvider);

      // Only Momos added; Chai skipped
      expect(cartState.items.length, equals(1));
      expect(cartState.items.first.menuItem.id, equals('item_momos'));
      expect(cartState.items.first.quantity, equals(2));
    });

    testWidgets('Reorder does nothing if all items are deleted or out of stock',
        (tester) async {
      final container = ProviderContainer(
        overrides: [
          firestoreServiceProvider.overrideWithValue(
            MockFirestoreService(
              menuItemsMap: {
                shopId: [], // Empty menu
              },
            ),
          ),
        ],
      );

      late BuildContext testContext;
      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) {
              testContext = context;
              return const Scaffold(body: SizedBox());
            },
          ),
          GoRoute(
            path: '/cart',
            builder: (context, state) => const Scaffold(body: Text('Cart Screen')),
          ),
        ],
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.runAsync(() async {
        await ReorderHelper.handleReorder(
          context: testContext,
          ref: _MockWidgetRef(container),
          order: deliveredOrder,
        );
      });

      final cartState = container.read(cartProvider);
      expect(cartState.items.isEmpty, isTrue);
    });

    testWidgets('Reorder merges quantities if cart already has same-shop items',
        (tester) async {
      final container = ProviderContainer(
        overrides: [
          firestoreServiceProvider.overrideWithValue(
            MockFirestoreService(
              menuItemsMap: {
                shopId: [
                  const MenuItem(
                    id: 'item_momos',
                    name: 'Current Veg Momos',
                    price: 80,
                    details: 'Fresh momos',
                    imageUrl: '',
                    isVeg: true,
                    isAvailable: true,
                    isRecommended: false,
                    categoryId: 'snacks',
                    sortOrder: 1,
                  ),
                ],
              },
            ),
          ),
        ],
      );

      // Pre-populate cart with 1 Momos
      container.read(cartProvider.notifier).addItem(
            const MenuItem(
              id: 'item_momos',
              name: 'Current Veg Momos',
              price: 80,
              details: 'Fresh momos',
              imageUrl: '',
              isVeg: true,
              isAvailable: true,
              isRecommended: false,
              categoryId: 'snacks',
              sortOrder: 1,
            ),
            shopId,
            shopName,
          );

      late BuildContext testContext;
      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) {
              testContext = context;
              return const Scaffold(body: SizedBox());
            },
          ),
          GoRoute(
            path: '/cart',
            builder: (context, state) => const Scaffold(body: Text('Cart Screen')),
          ),
        ],
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Reorder 2 more Momos
      await tester.runAsync(() async {
        await ReorderHelper.handleReorder(
          context: testContext,
          ref: _MockWidgetRef(container),
          order: AppOrder(
            orderId: 'YB-20260822-9002',
            shopId: shopId,
            shopName: shopName,
            customerName: 'Student',
            customerPhone: '9999999999',
            items: const [
              OrderItem(
                menuItemId: 'item_momos',
                name: 'Old Veg Momos',
                price: 60,
                quantity: 2,
              ),
            ],
            totalAmount: 120,
            status: 'delivered',
            createdAt: DateTime.now(),
          ),
        );
      });

      final cartState = container.read(cartProvider);

      // Total quantity is 1 + 2 = 3
      expect(cartState.items.length, equals(1));
      expect(cartState.items.first.quantity, equals(3));
    });

    testWidgets(
        'Reorder preserves variant options and resolves with live option prices',
        (tester) async {
      const burgerItem = MenuItem(
        id: 'item_burger',
        name: 'Burger',
        price: 50,
        details: 'Tasty burger',
        imageUrl: '',
        isVeg: true,
        isAvailable: true,
        isRecommended: false,
        categoryId: 'burgers',
        sortOrder: 1,
        optionGroups: [
          MenuItemOptionGroup(
            id: 'grp_size',
            name: 'Size',
            groupType: OptionGroupType.fixed,
            options: [
              MenuItemOption(id: 'opt_small', name: 'Small', price: 55, pricingType: OptionPricingType.fixedPrice),
              MenuItemOption(id: 'opt_large', name: 'Large', price: 75, pricingType: OptionPricingType.fixedPrice),
            ],
          ),
          MenuItemOptionGroup(
            id: 'grp_cheese',
            name: 'Cheese',
            groupType: OptionGroupType.choice,
            required: false,
            options: [
              MenuItemOption(id: 'opt_cheese', name: 'Cheese', price: 15, pricingType: OptionPricingType.priceAdjustment),
            ],
          ),
        ],
      );

      final container = ProviderContainer(
        overrides: [
          firestoreServiceProvider.overrideWithValue(
            MockFirestoreService(
              menuItemsMap: {
                shopId: [burgerItem],
              },
            ),
          ),
        ],
      );

      late BuildContext testContext;
      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) {
              testContext = context;
              return const Scaffold(body: SizedBox());
            },
          ),
          GoRoute(
            path: '/cart',
            builder: (context, state) => const Scaffold(body: Text('Cart Screen')),
          ),
        ],
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      const oldLarge = SelectedMenuItemOption(
        groupId: 'grp_size',
        groupName: 'Size',
        optionId: 'opt_large',
        optionName: 'Large',
        pricingType: OptionPricingType.fixedPrice,
        price: 70, // Old price
      );
      const oldCheese = SelectedMenuItemOption(
        groupId: 'grp_cheese',
        groupName: 'Cheese',
        optionId: 'opt_cheese',
        optionName: 'Cheese',
        pricingType: OptionPricingType.priceAdjustment,
        price: 10, // Old price
      );

      await tester.runAsync(() async {
        await ReorderHelper.handleReorder(
          context: testContext,
          ref: _MockWidgetRef(container),
          order: AppOrder(
            orderId: 'YB-20260822-9003',
            shopId: shopId,
            shopName: shopName,
            customerName: 'Student',
            customerPhone: '9999999999',
            items: const [
              OrderItem(
                menuItemId: 'item_burger',
                name: 'Burger',
                price: 80, // Old total price (70 + 10)
                quantity: 2,
                optionsDescription: 'Large · Cheese',
                selectedOptions: [oldLarge, oldCheese],
                cartKey: 'item_burger|grp_cheese:opt_cheese|grp_size:opt_large',
              ),
            ],
            totalAmount: 160,
            status: 'delivered',
            createdAt: DateTime.now(),
          ),
        );
      });

      final cartState = container.read(cartProvider);
      expect(cartState.items.length, equals(1));
      final cartItem = cartState.items.first;

      // Current live price: Large (75) + Cheese (15) = 90
      expect(cartItem.unitPrice, equals(90));
      expect(cartItem.quantity, equals(2));
      expect(cartItem.optionsDescription, equals('Large · Cheese'));
      expect(cartItem.selectedOptions.length, equals(2));
      expect(cartItem.cartKey, equals('item_burger|grp_cheese:opt_cheese|grp_size:opt_large'));
    });
  });

  group('Reorder Button Visibility Widget Tests', () {
    testWidgets('Delivered order renders Reorder button on OrderHistoryScreen',
        (tester) async {
      final container = ProviderContainer();
      container.read(dummyOrdersProvider.notifier).addOrder(
            AppOrder(
              orderId: 'YB-DEL-01',
              shopId: 'rajat_shop',
              shopName: 'Rajat Shop',
              customerName: 'Student',
              customerPhone: '9999999999',
              items: const [
                OrderItem(
                  menuItemId: 'momos',
                  name: 'Veg Momos',
                  price: 80,
                  quantity: 1,
                ),
              ],
              totalAmount: 80,
              status: 'delivered',
              createdAt: DateTime.now(),
            ),
          );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: OrderHistoryScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Reorder'), findsOneWidget);
    });

    testWidgets('Cancelled order does NOT render Reorder button',
        (tester) async {
      final container = ProviderContainer();
      container.read(dummyOrdersProvider.notifier).addOrder(
            AppOrder(
              orderId: 'YB-CAN-01',
              shopId: 'rajat_shop',
              shopName: 'Rajat Shop',
              customerName: 'Student',
              customerPhone: '9999999999',
              items: const [
                OrderItem(
                  menuItemId: 'momos',
                  name: 'Veg Momos',
                  price: 80,
                  quantity: 1,
                ),
              ],
              totalAmount: 80,
              status: 'cancelled',
              createdAt: DateTime.now(),
            ),
          );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: OrderHistoryScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Reorder'), findsNothing);
    });

    testWidgets('Rejected order does NOT render Reorder button',
        (tester) async {
      final container = ProviderContainer();
      container.read(dummyOrdersProvider.notifier).addOrder(
            AppOrder(
              orderId: 'YB-REJ-01',
              shopId: 'rajat_shop',
              shopName: 'Rajat Shop',
              customerName: 'Student',
              customerPhone: '9999999999',
              items: const [
                OrderItem(
                  menuItemId: 'momos',
                  name: 'Veg Momos',
                  price: 80,
                  quantity: 1,
                ),
              ],
              totalAmount: 80,
              status: 'rejected',
              createdAt: DateTime.now(),
            ),
          );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: OrderHistoryScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Reorder'), findsNothing);
    });

    testWidgets('Delivered order renders Reorder button on OrderDetailScreen',
        (tester) async {
      final container = ProviderContainer();
      final order = AppOrder(
        orderId: 'YB-DEL-02',
        shopId: 'rajat_shop',
        shopName: 'Rajat Shop',
        customerName: 'Student',
        customerPhone: '9999999999',
        items: const [
          OrderItem(
            menuItemId: 'momos',
            name: 'Veg Momos',
            price: 80,
            quantity: 1,
          ),
        ],
        totalAmount: 80,
        status: 'delivered',
        createdAt: DateTime.now(),
      );

      container.read(dummyOrdersProvider.notifier).addOrder(order);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: OrderDetailScreen(orderId: 'YB-DEL-02'),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Reorder'), findsOneWidget);
    });
  });
}

class _MockWidgetRef implements WidgetRef {
  _MockWidgetRef(this.container);
  final ProviderContainer container;

  @override
  T read<T>(ProviderListenable<T> provider) => container.read(provider);

  @override
  T watch<T>(ProviderListenable<T> provider) => container.read(provider);

  @override
  BuildContext get context => throw UnimplementedError();

  @override
  bool exists(ProviderBase<Object?> provider) => true;

  @override
  void invalidate(ProviderOrFamily provider) {}

  @override
  void listen<T>(
    ProviderListenable<T> provider,
    void Function(T? previous, T next) listener, {
    void Function(Object error, StackTrace stackTrace)? onError,
  }) {}

  @override
  ProviderSubscription<T> listenManual<T>(
    ProviderListenable<T> provider,
    void Function(T? previous, T next) listener, {
    bool fireImmediately = false,
    void Function(Object error, StackTrace stackTrace)? onError,
  }) =>
      throw UnimplementedError();

  @override
  T refresh<T>(Refreshable<T> provider) => container.refresh(provider);
}
