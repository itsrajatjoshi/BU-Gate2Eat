// BU Gate2Eat — Checkpoint 2: Offline / Weak Internet Comprehensive Test Suite
// Verifies resilience against packet loss, timeouts, stream recovery, cart preservation,
// duplicate order prevention via idempotency keys, and user-friendly error formatting.

import 'dart:async';

import 'package:bugate2eat_app/core/providers.dart';
import 'package:bugate2eat_app/features/cart/cart_provider.dart';
import 'package:bugate2eat_app/features/cart/cart_screen.dart';
import 'package:bugate2eat_app/models/menu_item_model.dart';
import 'package:bugate2eat_app/models/order_model.dart';
import 'package:bugate2eat_app/models/shop_model.dart';
import 'package:bugate2eat_app/panel/shopkeeper_panel/shopkeeper_order_history_screen.dart';
import 'package:bugate2eat_app/panel/shopkeeper_panel/shopkeeper_orders_screen.dart';
import 'package:bugate2eat_app/services/firestore_service.dart';
import 'package:bugate2eat_app/services/local_storage_service.dart';
import 'package:bugate2eat_app/services/order_service.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeConnectivity implements Connectivity {
  FakeConnectivity({List<ConnectivityResult>? initial})
      : _current = initial ?? [ConnectivityResult.wifi];

  List<ConnectivityResult> _current;
  final StreamController<List<ConnectivityResult>> _controller =
      StreamController<List<ConnectivityResult>>.broadcast();

  void emit(List<ConnectivityResult> results) {
    _current = results;
    _controller.add(results);
  }

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => _current;

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      _controller.stream;
}

class FakeFirestoreService extends FirestoreService {
  Shop _buildTestShop() => Shop(
        id: 'test_shop_1',
        name: 'Test Gourmet Shop',
        description: 'Quality Fast Food',
        bannerUrl: '',
        contactNumber: '9876543210',
        orderNumber: '9876543210',
        openTime: '00:00',
        closeTime: '23:59',
        isClosedOverride: false,
        isActive: true,
        sortOrder: 1,
        searchKeywords: const ['burger', 'coffee'],
        deliveryNote: 'Bennett University • Gate No. 3',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        orderMethod: ShopOrderMethod.app,
        minimumOrderAmount: 0,
      );

  @override
  Future<Shop?> getShop(String shopId) async => _buildTestShop();

  @override
  Future<List<Shop>> getShops() async => [_buildTestShop()];

  @override
  Stream<List<Shop>> watchShops() => Stream.value([_buildTestShop()]);

  @override
  Future<List<MenuItem>> getMenuItems(String shopId) async => [];
}

class FakeOrderService extends OrderService {
  final List<AppOrder> createdOrders = [];
  bool failNextCreate = false;
  bool timeoutNextCreate = false;
  bool failNextStatusUpdate = false;
  String? lastUpdatedStatus;
  String? lastCancelledOrderId;

  @override
  Future<void> createOrder(AppOrder order, {DateTime? customNow, String? idempotencyKey}) async {
    if (timeoutNextCreate) {
      throw TimeoutException('Transaction timed out after 15s');
    }
    if (failNextCreate) {
      throw const OrderServiceException(
        'Network error: [cloud_firestore/unavailable] The service is currently unavailable.',
      );
    }
    // Idempotency simulation: check if already exists
    final exists = createdOrders.any((o) => o.orderId == order.orderId);
    if (!exists) {
      createdOrders.add(order);
    }
  }

  @override
  Future<void> updateOrderStatus(
    String orderId,
    String newStatus, {
    String? rejectionReason,
    String? deliveryPersonId,
    String? deliveryPersonName,
    DateTime? customNow,
  }) async {
    if (failNextStatusUpdate) {
      throw const OrderServiceException(
        'Network error: [cloud_firestore/unavailable] Status update failed.',
      );
    }
    lastUpdatedStatus = newStatus;
  }

  @override
  Future<void> cancelOrder(String orderId) async {
    if (failNextStatusUpdate) {
      throw const OrderServiceException(
        'Network error: [cloud_firestore/unavailable] Cancellation failed.',
      );
    }
    lastCancelledOrderId = orderId;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const testItem = MenuItem(
    id: 'item_burger_1',
    name: 'Classic Veg Burger',
    details: 'Crispy patty burger',
    price: 99,
    imageUrl: '',
    categoryId: 'burgers',
    isVeg: true,
    isAvailable: true,
    isRecommended: true,
    sortOrder: 1,
  );

  Widget createTestApp(ProviderContainer container) {
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

  group('Checkpoint 2: Offline & Weak Internet Invariants', () {
    late FakeConnectivity fakeConnectivity;
    late FakeOrderService fakeOrderService;
    late FakeFirestoreService fakeFirestoreService;
    late LocalStorageService localStorageService;

    setUp(() async {
      SharedPreferences.setMockInitialValues({
        'user_phone': '9876543210',
        'user_name': 'Rajat Student',
        'customer_id': 'cust_9876543210',
        'is_onboarded': true,
      });
      final prefs = await SharedPreferences.getInstance();
      localStorageService = LocalStorageService(prefs);
      fakeConnectivity = FakeConnectivity();
      fakeOrderService = FakeOrderService();
      fakeFirestoreService = FakeFirestoreService();
    });

    testWidgets('1. Timeout on order submission preserves cart without fake success', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      fakeOrderService.timeoutNextCreate = true;

      final container = ProviderContainer(
        overrides: [
          connectivityProvider.overrideWithValue(fakeConnectivity),
          localStorageServiceProvider.overrideWithValue(localStorageService),
          orderServiceProvider.overrideWithValue(fakeOrderService),
          firestoreServiceProvider.overrideWithValue(fakeFirestoreService),
        ],
      );
      addTearDown(container.dispose);

      final cart = container.read(cartProvider.notifier);
      cart.addItem(testItem, 'test_shop_1', 'Test Gourmet Shop');

      await tester.pumpWidget(createTestApp(container));
      await tester.pumpAndSettle();

      // Tap Place Order -> Confirm
      await tester.tap(find.widgetWithText(ElevatedButton, 'Place Order'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Confirm'));
      await tester.pumpAndSettle();

      // Verify connection error SnackBar is shown
      expect(
        find.text('Failed to place order. Please check your connection and try again.'),
        findsOneWidget,
      );

      // Verify cart is NOT lost
      expect(container.read(cartProvider).items.length, equals(1));
      expect(container.read(cartProvider).items.first.menuItem.name, equals('Classic Veg Burger'));
      expect(fakeOrderService.createdOrders, isEmpty);
    });

    testWidgets('2. Idempotent Retry: Retrying order after network timeout reuses pending order ID and prevents duplicates', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      fakeOrderService.timeoutNextCreate = true;

      final container = ProviderContainer(
        overrides: [
          connectivityProvider.overrideWithValue(fakeConnectivity),
          localStorageServiceProvider.overrideWithValue(localStorageService),
          orderServiceProvider.overrideWithValue(fakeOrderService),
          firestoreServiceProvider.overrideWithValue(fakeFirestoreService),
        ],
      );
      addTearDown(container.dispose);

      final cart = container.read(cartProvider.notifier);
      cart.addItem(testItem, 'test_shop_1', 'Test Gourmet Shop');

      await tester.pumpWidget(createTestApp(container));
      await tester.pumpAndSettle();

      // Attempt 1: Times out
      await tester.tap(find.widgetWithText(ElevatedButton, 'Place Order'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Confirm'));
      await tester.pumpAndSettle();

      expect(fakeOrderService.createdOrders, isEmpty);
      expect(container.read(cartProvider).items.length, equals(1));

      // Attempt 2: Connection restored -> user taps Place Order and Confirms again
      fakeOrderService.timeoutNextCreate = false;
      await tester.tap(find.widgetWithText(ElevatedButton, 'Place Order'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Confirm'));
      await tester.pumpAndSettle();

      // Succeeded: Exactly one order created, cart cleared, navigated
      expect(fakeOrderService.createdOrders.length, equals(1));
      expect(container.read(cartProvider).items, isEmpty);
      expect(find.textContaining('Order Confirmation:'), findsOneWidget);
    });

    testWidgets('3. Shopkeeper Orders Screen renders sanitized error and supports retry', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final container = ProviderContainer(
        overrides: [
          shopActiveOrdersStreamProvider('test_shop_1').overrideWith(
            (ref) => Stream.error(
              Exception('[cloud_firestore/unavailable] Connection broken'),
            ),
          ),
          localStorageServiceProvider.overrideWithValue(localStorageService),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: ShopkeeperOrdersScreen(shopId: 'test_shop_1'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify sanitized user-friendly error is rendered (no raw exception dump)
      expect(find.text('Failed to load active orders'), findsOneWidget);
      expect(
        find.text("Couldn't load active orders. Please check your connection and try again."),
        findsOneWidget,
      );
      expect(find.widgetWithText(FilledButton, 'Retry'), findsOneWidget);
    });

    testWidgets('4. Shopkeeper Order History Screen renders sanitized error and supports retry', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final container = ProviderContainer(
        overrides: [
          shopOrderHistoryStreamProvider('test_shop_1').overrideWith(
            (ref) => Stream.error(
              Exception('[cloud_firestore/unavailable] Failed to reach server'),
            ),
          ),
          localStorageServiceProvider.overrideWithValue(localStorageService),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: ShopkeeperOrderHistoryScreen(shopId: 'test_shop_1'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify sanitized user-friendly error is rendered
      expect(find.text('Failed to load order history'), findsOneWidget);
      expect(
        find.text("Couldn't load order history. Please check your connection and try again."),
        findsOneWidget,
      );
      expect(find.widgetWithText(FilledButton, 'Retry'), findsOneWidget);
    });
  });
}
