// BU Gate2Eat — In-App Order Placement to Firestore Test Suite (Phase 3 — Part 3.2)

import 'package:bugate2eat_app/core/providers.dart';
import 'package:bugate2eat_app/features/cart/cart_provider.dart';
import 'package:bugate2eat_app/features/cart/cart_screen.dart';
import 'package:bugate2eat_app/models/menu_item_model.dart';
import 'package:bugate2eat_app/models/order_model.dart';
import 'package:bugate2eat_app/models/shop_model.dart';
import 'package:bugate2eat_app/services/firestore_service.dart';
import 'package:bugate2eat_app/services/local_storage_service.dart';
import 'package:bugate2eat_app/services/order_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeFirestoreService extends FirestoreService {
  @override
  Future<Shop?> getShop(String shopId) async {
    return Shop(
      id: 'rajat_shop',
      name: 'Rajat Shop',
      description: 'Chinese, Fast Food & Thalis',
      bannerUrl: '',
      contactNumber: '9876543210',
      orderNumber: '9876543210',
      openTime: '09:00',
      closeTime: '23:00',
      isClosedOverride: false,
      isActive: true,
      sortOrder: 1,
      searchKeywords: const ['chinese', 'momos'],
      deliveryNote: 'Bennett University • Gate No. 2',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  @override
  Future<List<MenuItem>> getMenuItems(String shopId) async => [];
}

class FakeOrderService extends OrderService {
  final List<AppOrder> createdOrders = [];
  bool shouldFail = false;

  @override
  Future<void> createOrder(AppOrder order) async {
    if (shouldFail) {
      throw const OrderServiceException('Network failure simulation');
    }
    createdOrders.add(order);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;
  late FakeOrderService fakeOrderService;
  late FakeFirestoreService fakeFirestoreService;
  late LocalStorageService localStorageService;

  const testMenuItem1 = MenuItem(
    id: 'item_momos_1',
    name: 'Veg Steamed Momos',
    details: 'Delicious momos',
    price: 80,
    imageUrl: 'https://example.com/momos.jpg',
    categoryId: 'momos',
    isVeg: true,
    isAvailable: true,
    isRecommended: true,
    sortOrder: 1,
  );

  const testMenuItem2 = MenuItem(
    id: 'item_chai_1',
    name: 'Masala Chai',
    details: 'Hot spiced tea',
    price: 25,
    imageUrl: 'https://example.com/chai.jpg',
    categoryId: 'beverages',
    isVeg: true,
    isAvailable: true,
    isRecommended: false,
    sortOrder: 2,
  );

  Widget createTestWidget() {
    final router = GoRouter(
      initialLocation: '/cart',
      routes: [
        GoRoute(
          path: '/cart',
          builder: (_, __) => const CartScreen(),
        ),
        GoRoute(
          path: '/order/:orderId',
          builder: (_, state) => Scaffold(
            body: Text('Order Confirmation: ${state.pathParameters['orderId']}'),
          ),
        ),
      ],
    );

    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        routerConfig: router,
      ),
    );
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'user_name': 'Aarav Sharma',
      'user_phone': '9876543210',
      'customer_id': 'cust_9876543210',
    });
    final prefs = await SharedPreferences.getInstance();
    localStorageService = LocalStorageService(prefs);
    fakeOrderService = FakeOrderService();
    fakeFirestoreService = FakeFirestoreService();

    container = ProviderContainer(
      overrides: [
        localStorageServiceProvider
            .overrideWithValue(localStorageService),
        firestoreServiceProvider
            .overrideWithValue(fakeFirestoreService),
        orderServiceProvider.overrideWithValue(fakeOrderService),
      ],
    );
  });

  tearDown(() {
    container.dispose();
  });

  group('Phase 3 — Part 3.2: In-App Order Placement Flow Tests', () {
    testWidgets(
        '1. Successful in-app order creation calls OrderService, saves snapshot, updates local bridge, and clears cart',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      // Set order method for shop to in-app
      container.read(shopOrderMethodProvider.notifier).setMethodForShop(
            'rajat_shop',
            ShopOrderMethod.app,
          );

      // Add items to cart
      final cartNotifier = container.read(cartProvider.notifier);
      cartNotifier.addItem(testMenuItem1, 'rajat_shop', 'Rajat Shop');
      cartNotifier.addItem(testMenuItem1, 'rajat_shop', 'Rajat Shop'); // qty 2 = 160
      cartNotifier.addItem(testMenuItem2, 'rajat_shop', 'Rajat Shop'); // qty 1 = 25 -> Total 185

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Your Cart'), findsOneWidget);
      expect(find.text('Total'), findsOneWidget);
      expect(find.text('₹185'), findsWidgets);

      // Tap Place Order
      final placeOrderBtn = find.widgetWithText(ElevatedButton, 'Place Order');
      expect(placeOrderBtn, findsOneWidget);
      await tester.tap(placeOrderBtn);
      await tester.pumpAndSettle();

      // Verify Confirm Order dialog appears
      expect(find.text('Confirm Order'), findsOneWidget);
      expect(
        find.text('Confirm order from Rajat Shop for ₹185?'),
        findsOneWidget,
      );

      // Tap Confirm
      await tester.tap(find.widgetWithText(ElevatedButton, 'Confirm'));
      await tester.pumpAndSettle();

      // 1. Verify OrderService.createOrder was called exactly once
      expect(fakeOrderService.createdOrders.length, equals(1));
      final createdOrder = fakeOrderService.createdOrders.first;

      expect(createdOrder.shopId, equals('rajat_shop'));
      expect(createdOrder.shopName, equals('Rajat Shop'));
      expect(createdOrder.customerId, equals('cust_9876543210'));
      expect(createdOrder.customerName, equals('Aarav Sharma'));
      expect(createdOrder.customerPhone, equals('9876543210'));
      expect(createdOrder.totalAmount, equals(185.0));
      expect(createdOrder.totalItemCount, equals(3));
      expect(createdOrder.status, equals('placed'));
      expect(createdOrder.items.length, equals(2));
      expect(createdOrder.items[0].name, equals('Veg Steamed Momos'));
      expect(createdOrder.items[0].quantity, equals(2));
      expect(createdOrder.items[0].price, equals(80));

      // 2. Verify temporary dummyOrdersProvider has the order
      final dummyOrders = container.read(dummyOrdersProvider);
      expect(dummyOrders.any((o) => o.orderId == createdOrder.orderId), isTrue);

      // 3. Verify cart is cleared
      final cartState = container.read(cartProvider);
      expect(cartState.items, isEmpty);

      // 4. Verify navigation to order confirmation screen
      expect(
        find.text('Order Confirmation: ${createdOrder.orderId}'),
        findsOneWidget,
      );
    });

    testWidgets(
        '2. Failed in-app order creation shows error snackbar and leaves cart intact for retry',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      // Simulate failure in OrderService
      fakeOrderService.shouldFail = true;

      container.read(shopOrderMethodProvider.notifier).setMethodForShop(
            'rajat_shop',
            ShopOrderMethod.app,
          );

      final cartNotifier = container.read(cartProvider.notifier);
      cartNotifier.addItem(testMenuItem1, 'rajat_shop', 'Rajat Shop');

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Tap Place Order
      await tester.tap(find.widgetWithText(ElevatedButton, 'Place Order'));
      await tester.pumpAndSettle();

      // Tap Confirm in dialog
      await tester.tap(find.widgetWithText(ElevatedButton, 'Confirm'));
      await tester.pumpAndSettle();

      // Verify Error SnackBar is displayed
      expect(
        find.text(
            'Failed to place order. Please check your connection and try again.'),
        findsOneWidget,
      );

      // Verify cart was NOT cleared
      final cartState = container.read(cartProvider);
      expect(cartState.items.length, equals(1));
      expect(cartState.items.first.menuItem.name, equals('Veg Steamed Momos'));
    });

    testWidgets(
        '3. Minimum order requirement blocks in-app order placement and does not call OrderService',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      // Set minimum order for shop to ₹200
      container.read(shopMinimumOrderProvider.notifier).setMinimumOrderForShop(
            'rajat_shop',
            200,
          );
      container.read(shopOrderMethodProvider.notifier).setMethodForShop(
            'rajat_shop',
            ShopOrderMethod.app,
          );

      // Add item of ₹80 (below ₹200)
      final cartNotifier = container.read(cartProvider.notifier);
      cartNotifier.addItem(testMenuItem1, 'rajat_shop', 'Rajat Shop');

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Tap Place Order
      await tester.tap(find.widgetWithText(ElevatedButton, 'Place Order'));
      await tester.pumpAndSettle();

      // Verify blocked with SnackBar
      expect(
        find.text(
            'Minimum order amount for Rajat Shop is ₹200. Add ₹120 more to order.'),
        findsOneWidget,
      );

      // Verify no dialog and no OrderService call
      expect(find.text('Confirm Order'), findsNothing);
      expect(fakeOrderService.createdOrders, isEmpty);
    });

    testWidgets(
        '4. WhatsApp order placement does NOT invoke OrderService.createOrder',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      container.read(shopOrderMethodProvider.notifier).setMethodForShop(
            'rajat_shop',
            ShopOrderMethod.whatsapp,
          );

      final cartNotifier = container.read(cartProvider.notifier);
      cartNotifier.addItem(testMenuItem1, 'rajat_shop', 'Rajat Shop');

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      final whatsappBtn =
          find.widgetWithText(ElevatedButton, 'Order via WhatsApp');
      expect(whatsappBtn, findsOneWidget);

      await tester.tap(whatsappBtn);
      await tester.pumpAndSettle();

      // Verify no Firestore order creation occurred
      expect(fakeOrderService.createdOrders, isEmpty);
    });
  });
}
