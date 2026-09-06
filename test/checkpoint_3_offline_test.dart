// BU Gate2Eat — Checkpoint 3: Offline / Weak Internet Test Suite
// Verifies connectivity providers, offline indicators, order placement protection,
// cart safety, shopkeeper transaction failure isolation, and error message sanitization.

import 'dart:async';

import 'package:bugate2eat_app/core/providers.dart';
import 'package:bugate2eat_app/core/utils/network_error_helper.dart';
import 'package:bugate2eat_app/core/widgets/offline_indicator_wrapper.dart';
import 'package:bugate2eat_app/features/cart/cart_provider.dart';
import 'package:bugate2eat_app/features/cart/cart_screen.dart';
import 'package:bugate2eat_app/models/menu_item_model.dart';
import 'package:bugate2eat_app/models/order_model.dart';
import 'package:bugate2eat_app/models/shop_model.dart';
import 'package:bugate2eat_app/panel/shopkeeper_panel/widgets/shopkeeper_order_details_modal.dart';
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
      : _current = initial ?? [ConnectivityResult.wifi] {
    _controller = StreamController<List<ConnectivityResult>>.broadcast();
  }

  List<ConnectivityResult> _current;
  late final StreamController<List<ConnectivityResult>> _controller;

  void emit(List<ConnectivityResult> results) {
    _current = results;
    _controller.add(results);
  }

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => _current;

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged => _controller.stream;
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
  Future<List<MenuItem>> getMenuItems(String shopId) async => [];
}

class FakeOrderService extends OrderService {
  final List<AppOrder> createdOrders = [];
  bool failNextCreate = false;
  bool failNextStatusUpdate = false;
  final Map<String, String> orderStatuses = {};

  @override
  Future<void> createOrder(AppOrder order, {DateTime? customNow}) async {
    if (failNextCreate) {
      throw const OrderServiceException(
        'Network error: [cloud_firestore/unavailable] The service is currently unavailable.',
      );
    }
    createdOrders.add(order);
    orderStatuses[order.orderId] = order.status;
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
        'Network failure: [cloud_firestore/unavailable] The client is offline.',
      );
    }
    orderStatuses[orderId] = newStatus;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const testItem = MenuItem(
    id: 'item_burger_1',
    name: 'Classic Veg Burger',
    details: 'Fresh lettuce and patty',
    price: 99,
    imageUrl: '',
    categoryId: 'burgers',
    isVeg: true,
    isAvailable: true,
    isRecommended: true,
    sortOrder: 1,
  );

  group('Checkpoint 3: NetworkErrorHelper Tests', () {
    test('Identifies network and unavailable error strings correctly', () {
      expect(NetworkErrorHelper.isNetworkOrUnavailableError('cloud_firestore/unavailable'), isTrue);
      expect(NetworkErrorHelper.isNetworkOrUnavailableError('Client is offline'), isTrue);
      expect(NetworkErrorHelper.isNetworkOrUnavailableError('SocketException: failed host lookup'), isTrue);
      expect(NetworkErrorHelper.isNetworkOrUnavailableError('Connection timed out'), isTrue);
      expect(NetworkErrorHelper.isNetworkOrUnavailableError('Order not found'), isFalse);
    });

    test('Sanitizes technical network exceptions into concise YummBU feedback', () {
      final msg = NetworkErrorHelper.toUserFriendlyMessage(
        'FirebaseException: [cloud_firestore/unavailable] The service is currently unavailable.',
        defaultPrefix: "Couldn't update order",
      );
      expect(msg, equals("Couldn't update order. Please check your connection and try again."));
    });

    test('Preserves domain validation messages without technical prefixes', () {
      final msg = NetworkErrorHelper.toUserFriendlyMessage(
        'OrderServiceException: Order has already been accepted.',
        defaultPrefix: "Couldn't update order",
      );
      expect(msg, equals("Couldn't update order: Order has already been accepted."));
    });
  });

  group('Checkpoint 3: Connectivity Providers & Stream Tests', () {
    test('isOnlineProvider evaluates ConnectivityResult list correctly', () async {
      final fakeConn = FakeConnectivity(initial: [ConnectivityResult.wifi]);
      final container = ProviderContainer(
        overrides: [
          connectivityProvider.overrideWithValue(fakeConn),
        ],
      );
      addTearDown(container.dispose);

      // Initially online (wifi)
      expect(container.read(isOnlineProvider), isTrue);

      // Check checkHasInternet imperative helper
      final checkInternet = container.read(checkHasInternetProvider);
      expect(await checkInternet(), isTrue);

      // Transition to offline (none)
      fakeConn.emit([ConnectivityResult.none]);
      await Future<void>.delayed(Duration.zero);

      // Stream updates isOnlineProvider
      expect(container.read(isOnlineProvider), isFalse);
      expect(await checkInternet(), isFalse);

      // Transition back to mobile data
      fakeConn.emit([ConnectivityResult.mobile]);
      await Future<void>.delayed(Duration.zero);

      expect(container.read(isOnlineProvider), isTrue);
      expect(await checkInternet(), isTrue);
    });
  });

  group('Checkpoint 3: OfflineIndicatorWrapper Widget Tests', () {
    testWidgets('Is completely hidden (height 0) when online', (tester) async {
      final fakeConn = FakeConnectivity(initial: [ConnectivityResult.wifi]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            connectivityProvider.overrideWithValue(fakeConn),
          ],
          child: const MaterialApp(
            home: OfflineIndicatorWrapper(
              child: Scaffold(
                body: Text('Main Content Screen'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify main content is visible
      expect(find.text('Main Content Screen'), findsOneWidget);

      // Verify no offline text is visible
      expect(find.text('No Internet connection'), findsNothing);
    });

    testWidgets('Displays slim banner when connection is lost', (tester) async {
      final fakeConn = FakeConnectivity(initial: [ConnectivityResult.wifi]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            connectivityProvider.overrideWithValue(fakeConn),
          ],
          child: const MaterialApp(
            home: OfflineIndicatorWrapper(
              child: Scaffold(
                body: Text('Main Content Screen'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Emit offline state
      fakeConn.emit([ConnectivityResult.none]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300)); // finish animation

      // Verify banner appears
      expect(find.text('No Internet connection'), findsOneWidget);
      expect(find.byIcon(Icons.wifi_off_rounded), findsOneWidget);

      // Content remains fully intact below banner
      expect(find.text('Main Content Screen'), findsOneWidget);

      // Reconnect
      fakeConn.emit([ConnectivityResult.wifi]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Banner collapses away
      expect(find.text('No Internet connection'), findsNothing);
    });
  });

  group('Checkpoint 3: Order Placement Offline & Failure Protection', () {
    late FakeConnectivity fakeConnectivity;
    late FakeOrderService fakeOrderService;
    late FakeFirestoreService fakeFirestoreService;
    late LocalStorageService localStorageService;

    setUp(() async {
      SharedPreferences.setMockInitialValues({
        'user_phone': '9876543210',
        'user_name': 'Aarav Sharma',
        'is_onboarded': true,
      });
      final prefs = await SharedPreferences.getInstance();
      localStorageService = LocalStorageService(prefs);
      fakeConnectivity = FakeConnectivity(initial: [ConnectivityResult.wifi]);
      fakeOrderService = FakeOrderService();
      fakeFirestoreService = FakeFirestoreService();
    });

    Widget createTestApp(ProviderContainer container) {
      final router = GoRouter(
        initialLocation: '/cart',
        routes: [
          GoRoute(
            path: '/cart',
            builder: (ctx, state) => const CartScreen(),
          ),
          GoRoute(
            path: '/order/:id',
            builder: (ctx, state) => Scaffold(
              body: Text('Order Confirmation: ${state.pathParameters['id']}'),
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

    testWidgets(
      'Order placement is blocked when offline: cart remains intact, no fake order placed',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        // Device is offline
        fakeConnectivity = FakeConnectivity(initial: [ConnectivityResult.none]);

        final container = ProviderContainer(
          overrides: [
            connectivityProvider.overrideWithValue(fakeConnectivity),
            localStorageServiceProvider.overrideWithValue(localStorageService),
            orderServiceProvider.overrideWithValue(fakeOrderService),
            firestoreServiceProvider.overrideWithValue(fakeFirestoreService),
          ],
        );
        addTearDown(container.dispose);

        // Add item to cart
        final cart = container.read(cartProvider.notifier);
        cart.addItem(testItem, 'test_shop_1', 'Test Gourmet Shop');

        await tester.pumpWidget(createTestApp(container));
        await tester.pumpAndSettle();

        // Tap Place Order
        await tester.tap(find.widgetWithText(ElevatedButton, 'Place Order'));
        await tester.pumpAndSettle();

        // Tap Confirm Order in dialog
        await tester.tap(find.widgetWithText(ElevatedButton, 'Confirm'));
        await tester.pumpAndSettle();

        // Verify offline error SnackBar is shown
        expect(
          find.text('No internet connection. Please check your connection and try again.'),
          findsOneWidget,
        );

        // Verify NO order was created in order service
        expect(fakeOrderService.createdOrders, isEmpty);

        // Verify Cart is 100% intact
        expect(container.read(cartProvider).items.length, equals(1));
        expect(container.read(cartProvider).items.first.menuItem.name, equals('Classic Veg Burger'));
      },
    );

    testWidgets(
      'Backend write failure preserves cart and shows connection error SnackBar without fake success',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        // Connected to network, but backend write will fail
        fakeOrderService.failNextCreate = true;

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

        // Verify error feedback
        expect(
          find.text('Failed to place order. Please check your connection and try again.'),
          findsOneWidget,
        );

        // Verify NO navigation to order confirmation screen (NO fake success)
        expect(find.textContaining('Order Confirmation:'), findsNothing);

        // Verify Cart is preserved for retry
        expect(container.read(cartProvider).items.length, equals(1));

        // User retries after connection is restored
        fakeOrderService.failNextCreate = false;
        await tester.tap(find.widgetWithText(ElevatedButton, 'Place Order'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(ElevatedButton, 'Confirm'));
        await tester.pumpAndSettle();

        // Successful retry clears cart and navigates
        expect(fakeOrderService.createdOrders.length, equals(1));
        expect(container.read(cartProvider).items, isEmpty);
        expect(find.textContaining('Order Confirmation:'), findsOneWidget);
      },
    );
  });

  group('Checkpoint 3: Shopkeeper Status Action Offline / Failure Tests', () {
    late FakeOrderService fakeOrderService;
    late LocalStorageService localStorageService;

    final testPlacedOrder = AppOrder(
      orderId: 'ORD-SK-101',
      shopId: 'rajat_shop',
      shopName: 'Rajat Shop',
      customerId: 'cust_9876543210',
      customerName: 'Aarav Sharma',
      customerPhone: '9876543210',
      items: const [
        OrderItem(
          menuItemId: 'item_burger_1',
          name: 'Classic Veg Burger',
          price: 99,
          quantity: 1,
        ),
      ],
      totalAmount: 99,
      status: 'placed',
      createdAt: DateTime.now(),
      acceptDeadline: DateTime.now().add(const Duration(minutes: 20)),
    );

    setUp(() async {
      SharedPreferences.setMockInitialValues({
        'user_phone': '8000383993', // rajat_shop shopkeeper
        'user_name': 'Rajat Vendor',
        'is_onboarded': true,
      });
      final prefs = await SharedPreferences.getInstance();
      localStorageService = LocalStorageService(prefs);
      fakeOrderService = FakeOrderService();
    });

    testWidgets('Failed Accept action shows user-friendly error and does NOT update status or close modal', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      fakeOrderService.failNextStatusUpdate = true;

      final container = ProviderContainer(
        overrides: [
          localStorageServiceProvider.overrideWithValue(localStorageService),
          orderServiceProvider.overrideWithValue(fakeOrderService),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (ctx) => ElevatedButton(
                  onPressed: () => ShopkeeperOrderDetailsModal.show(ctx, order: testPlacedOrder),
                  child: const Text('Open Modal'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open Modal
      await tester.tap(find.text('Open Modal'));
      await tester.pumpAndSettle();

      // Tap Accept Order
      await tester.tap(find.text('Accept Order'));
      await tester.pumpAndSettle();

      // Confirm in dialog (use .last because both modal and dialog have 'Accept Order')
      await tester.tap(find.widgetWithText(ElevatedButton, 'Accept Order').last);
      await tester.pumpAndSettle();

      // Verify concise sanitized error message is shown (no raw bracketed dump)
      expect(
        find.text("Couldn't accept order. Please check your connection and try again."),
        findsOneWidget,
      );

      // Modal is still open (NOT closed on failure)
      expect(find.text('Order #ORD-SK-101'), findsOneWidget);

      // Local dummy orders were NOT updated to accepted
      final dummyOrders = container.read(dummyOrdersProvider);
      final dummyOrder = dummyOrders.where((o) => o.orderId == 'ORD-SK-101').firstOrNull;
      expect(dummyOrder?.status != 'accepted', isTrue);
    });

    testWidgets('Failed Reject action shows user-friendly error and does NOT update status or close modal', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      fakeOrderService.failNextStatusUpdate = true;

      final container = ProviderContainer(
        overrides: [
          localStorageServiceProvider.overrideWithValue(localStorageService),
          orderServiceProvider.overrideWithValue(fakeOrderService),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (ctx) => ElevatedButton(
                  onPressed: () => ShopkeeperOrderDetailsModal.show(ctx, order: testPlacedOrder),
                  child: const Text('Open Modal'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open Modal
      await tester.tap(find.text('Open Modal'));
      await tester.pumpAndSettle();

      // Tap Reject Order button
      await tester.tap(find.text('Reject'));
      await tester.pumpAndSettle();

      // Confirm in RejectOrderDialog
      await tester.tap(find.widgetWithText(ElevatedButton, 'Reject Order'));
      await tester.pumpAndSettle();

      // Verify concise sanitized error message is shown
      expect(
        find.text("Couldn't reject order. Please check your connection and try again."),
        findsOneWidget,
      );

      // Modal is still open
      expect(find.text('Order #ORD-SK-101'), findsOneWidget);

      // Local dummy orders were NOT updated to rejected
      final dummyOrders = container.read(dummyOrdersProvider);
      final dummyOrder = dummyOrders.where((o) => o.orderId == 'ORD-SK-101').firstOrNull;
      expect(dummyOrder?.status != 'rejected', isTrue);
    });

    testWidgets('Failed Deliver action shows user-friendly error and does NOT update status or close modal', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final acceptedOrder = testPlacedOrder.copyWith(
        status: 'accepted',
        acceptedAt: DateTime.now(),
      );

      fakeOrderService.failNextStatusUpdate = true;

      final container = ProviderContainer(
        overrides: [
          localStorageServiceProvider.overrideWithValue(localStorageService),
          orderServiceProvider.overrideWithValue(fakeOrderService),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (ctx) => ElevatedButton(
                  onPressed: () => ShopkeeperOrderDetailsModal.show(ctx, order: acceptedOrder),
                  child: const Text('Open Modal'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open Modal
      await tester.tap(find.text('Open Modal'));
      await tester.pumpAndSettle();

      // Tap Mark as Delivered button on modal
      await tester.tap(find.text('Mark as Delivered').first);
      await tester.pumpAndSettle();

      // Confirm in MarkDeliveredDialog
      await tester.tap(find.widgetWithText(ElevatedButton, 'Mark as Delivered').last);
      await tester.pumpAndSettle();

      // Verify concise sanitized error message is shown
      expect(
        find.text("Couldn't mark order as delivered. Please check your connection and try again."),
        findsOneWidget,
      );

      // Modal is still open
      expect(find.text('Order #ORD-SK-101'), findsOneWidget);

      // Local dummy orders were NOT updated to delivered
      final dummyOrders = container.read(dummyOrdersProvider);
      final dummyOrder = dummyOrders.where((o) => o.orderId == 'ORD-SK-101').firstOrNull;
      expect(dummyOrder?.status != 'delivered', isTrue);
    });
  });
}
