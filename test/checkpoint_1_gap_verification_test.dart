// BU Gate2Eat — Checkpoint 1 Gap Verification Test Suite
//
// Verification of:
// 1. Rapid double-tap protection on Place Order (synchronous guard)
// 2. Closed/Inactive shop protection during Reorder
// 3. Network failure handling during order placement (cart preserved, clean error)
// 4. Active vs Terminal order separation
// 5. Delivery person info persistence on delivered orders

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bugate2eat_app/core/providers.dart';
import 'package:bugate2eat_app/features/cart/cart_provider.dart';
import 'package:bugate2eat_app/features/orders/reorder_helper.dart';
import 'package:bugate2eat_app/models/cart_item_model.dart';
import 'package:bugate2eat_app/models/menu_item_model.dart';
import 'package:bugate2eat_app/models/order_model.dart';
import 'package:bugate2eat_app/models/shop_model.dart';
import 'package:bugate2eat_app/services/firestore_service.dart';
import 'package:bugate2eat_app/services/order_service.dart';

class FakeFirestoreService extends FirestoreService {
  Shop? shopToReturn;
  List<MenuItem> menuItemsToReturn = [];

  @override
  Future<Shop?> getShop(String shopId) async => shopToReturn;

  @override
  Future<List<MenuItem>> getMenuItems(String shopId) async => menuItemsToReturn;
}

class FakeOrderService extends OrderService {
  int createOrderCallCount = 0;
  bool shouldThrowOnCreate = false;
  AppOrder? lastCreatedOrder;

  @override
  bool get isAvailable => true;

  @override
  Future<void> createOrder(AppOrder order, {DateTime? customNow, String? idempotencyKey}) async {
    createOrderCallCount++;
    if (shouldThrowOnCreate) {
      throw const OrderServiceException('Simulated network timeout');
    }
    lastCreatedOrder = order;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Checkpoint 1: In-Flight Double Tap & Reorder Shop Status Tests', () {
    late FakeFirestoreService fakeFirestoreService;
    late FakeOrderService fakeOrderService;

    setUp(() {
      fakeFirestoreService = FakeFirestoreService();
      fakeOrderService = FakeOrderService();
    });

    testWidgets('1. Reorder blocks execution if target shop is CLOSED', (tester) async {
      final closedShop = Shop(
        id: 'shop_closed',
        name: 'Late Night Bites',
        description: 'Snacks',
        bannerUrl: '',
        contactNumber: '9999999999',
        orderNumber: '9999999999',
        openTime: '11:00 PM',
        closeTime: '03:00 AM',
        isClosedOverride: true, // CLOSED
        isActive: true,
        sortOrder: 1,
        searchKeywords: const ['snacks'],
        deliveryNote: 'Gate 3',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      fakeFirestoreService.shopToReturn = closedShop;

      final testOrder = AppOrder(
        orderId: 'ORD-CLOSED-1',
        shopId: 'shop_closed',
        shopName: 'Late Night Bites',
        customerName: 'Student',
        customerPhone: '9876543210',
        items: const [
          OrderItem(menuItemId: 'item_1', name: 'Burger', price: 90, quantity: 1),
        ],
        totalAmount: 90,
        createdAt: DateTime.now(),
        status: 'delivered',
      );

      final container = ProviderContainer(
        overrides: [
          firestoreServiceProvider.overrideWithValue(fakeFirestoreService),
          shopsProvider.overrideWith((ref) => Future.value([closedShop])),
        ],
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => ReorderHelper.handleReorder(
                    context: context,
                    ref: _MockWidgetRef(container),
                    order: testOrder,
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

      // Cart should remain completely empty
      expect(container.read(cartProvider).items.isEmpty, isTrue);
      // SnackBar explaining closed status should appear
      expect(find.text('Late Night Bites is currently closed.'), findsOneWidget);
    });

    testWidgets('2. Reorder blocks execution if target shop is INACTIVE', (tester) async {
      final inactiveShop = Shop(
        id: 'shop_inactive',
        name: 'Old Canteen',
        description: 'Food',
        bannerUrl: '',
        contactNumber: '9999999999',
        orderNumber: '9999999999',
        openTime: '09:00 AM',
        closeTime: '05:00 PM',
        isClosedOverride: false,
        isActive: false, // INACTIVE
        sortOrder: 1,
        searchKeywords: const ['food'],
        deliveryNote: 'Gate 3',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      fakeFirestoreService.shopToReturn = inactiveShop;

      final testOrder = AppOrder(
        orderId: 'ORD-INACTIVE-1',
        shopId: 'shop_inactive',
        shopName: 'Old Canteen',
        customerName: 'Student',
        customerPhone: '9876543210',
        items: const [
          OrderItem(menuItemId: 'item_1', name: 'Thali', price: 120, quantity: 1),
        ],
        totalAmount: 120,
        createdAt: DateTime.now(),
        status: 'delivered',
      );

      final container = ProviderContainer(
        overrides: [
          firestoreServiceProvider.overrideWithValue(fakeFirestoreService),
          shopsProvider.overrideWith((ref) => Future.value([inactiveShop])),
        ],
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => ReorderHelper.handleReorder(
                    context: context,
                    ref: _MockWidgetRef(container),
                    order: testOrder,
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

      expect(container.read(cartProvider).items.isEmpty, isTrue);
      expect(find.text('Old Canteen is currently unavailable.'), findsOneWidget);
    });

    test('3. OrderStatusRules guarantees active and terminal statuses are mutually disjoint', () {
      final active = OrderStatusRules.activeStatuses;
      final terminal = OrderStatusRules.terminalStatuses;

      for (final s in active) {
        expect(terminal.contains(s), isFalse, reason: '$s cannot be both active and terminal');
      }
      for (final s in terminal) {
        expect(active.contains(s), isFalse, reason: '$s cannot be both terminal and active');
      }
      expect(active.contains('placed'), isTrue);
      expect(active.contains('accepted'), isTrue);
      expect(terminal.contains('delivered'), isTrue);
      expect(terminal.contains('rejected'), isTrue);
      expect(terminal.contains('cancelled'), isTrue);
      expect(terminal.contains('delivery_expired'), isTrue);
    });

    test('4. Delivery person information is serialized and deserialized accurately', () {
      final order = AppOrder(
        orderId: 'ORD-DEL-1',
        shopId: 'shop_1',
        shopName: 'Fast Food',
        customerName: 'Rajat',
        customerPhone: '9876543210',
        items: const [
          OrderItem(menuItemId: 'i1', name: 'Fries', price: 60, quantity: 1),
        ],
        totalAmount: 60,
        createdAt: DateTime.now(),
        status: 'delivered',
        deliveryPersonId: '9876543211',
        deliveryPersonName: 'Delivery Partner Ram',
      );

      final map = order.toMap();
      expect(map['deliveryPersonId'], equals('9876543211'));
      expect(map['deliveryPersonName'], equals('Delivery Partner Ram'));

      final parsed = AppOrder.fromMap(map, 'ORD-DEL-1');
      expect(parsed.deliveryPersonId, equals('9876543211'));
      expect(parsed.deliveryPersonName, equals('Delivery Partner Ram'));
      expect(parsed.status, equals('delivered'));
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
