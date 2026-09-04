// BU Gate2Eat — Automated Test Suite
// Delivery Charges: Shop, Order Snapshot, Calculations & UI Verification

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bugate2eat_app/core/providers.dart';
import 'package:bugate2eat_app/features/cart/cart_provider.dart';
import 'package:bugate2eat_app/features/cart/cart_screen.dart';
import 'package:bugate2eat_app/models/cart_item_model.dart';
import 'package:bugate2eat_app/models/menu_item_model.dart';
import 'package:bugate2eat_app/models/order_model.dart';
import 'package:bugate2eat_app/models/shop_model.dart';
import 'package:bugate2eat_app/services/firestore_service.dart';
import 'package:bugate2eat_app/services/order_service.dart';
import 'package:bugate2eat_app/services/whatsapp_service.dart';

class _FakeOrderService extends OrderService {
  AppOrder? capturedOrder;

  @override
  Future<void> createOrder(AppOrder order, {DateTime? customNow}) async {
    capturedOrder = order;
  }
}

class _FakeFirestoreService extends FirestoreService {
  _FakeFirestoreService(this.shop);

  Shop shop;

  @override
  Future<Shop?> getShop(String shopId) async => shop;

  @override
  Stream<List<Shop>> watchShops() => Stream.value([shop]);
}

void main() {
  group('1. Shop Model — Delivery Charges Deserialization & Clamping', () {
    test('missing deliveryCharges defaults to 0', () {
      final map = {
        'name': 'Raja Hotel',
        'openTime': '08:00',
        'closeTime': '23:30',
      };
      final shop = Shop.fromMap(map, 'test_shop');
      expect(shop.deliveryCharges, equals(0));
    });

    test('positive deliveryCharges (5) parses accurately', () {
      final map = {
        'name': 'Raja Hotel',
        'deliveryCharges': 5,
      };
      final shop = Shop.fromMap(map, 'test_shop');
      expect(shop.deliveryCharges, equals(5));
    });

    test('negative deliveryCharges (-10) is clamped to 0', () {
      final map = {
        'name': 'Raja Hotel',
        'deliveryCharges': -10,
      };
      final shop = Shop.fromMap(map, 'test_shop');
      expect(shop.deliveryCharges, equals(0));
    });

    test('accepts fallback legacy field names deliveryCharge and deliveryFee', () {
      final mapWithCharge = {
        'name': 'Raja Hotel',
        'deliveryCharge': 15,
      };
      expect(Shop.fromMap(mapWithCharge, 'test_shop').deliveryCharges, equals(15));

      final mapWithFee = {
        'name': 'Raja Hotel',
        'deliveryFee': 20,
      };
      expect(Shop.fromMap(mapWithFee, 'test_shop').deliveryCharges, equals(20));
    });

    test('toFirestore serializes deliveryCharges field', () {
      final shop = Shop(
        id: 'shop_1',
        name: 'Test Shop',
        description: '',
        bannerUrl: '',
        contactNumber: '9999999999',
        orderNumber: '9999999999',
        openTime: '08:00',
        closeTime: '23:00',
        isClosedOverride: false,
        isActive: true,
        sortOrder: 1,
        searchKeywords: const [],
        deliveryNote: 'Gate 3',
        deliveryCharges: 7,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final map = shop.toFirestore();
      expect(map['deliveryCharges'], equals(7));
    });
  });

  group('2. AppOrder Model — Subtotal, Delivery Charges & Snapshot Preservation', () {
    test('missing deliveryCharges in map defaults to 0.0', () {
      final map = {
        'orderId': 'ord_123',
        'shopId': 'shop_1',
        'shopName': 'Raja Hotel',
        'customerName': 'Rajat',
        'customerPhone': '9876543210',
        'items': [
          {
            'menuItemId': 'momos',
            'name': 'Veg Momos',
            'price': 70,
            'quantity': 1,
          }
        ],
        'totalAmount': 70.0,
      };

      final order = AppOrder.fromMap(map);
      expect(order.subtotal, equals(70.0));
      expect(order.deliveryCharges, equals(0.0));
      expect(order.totalAmount, equals(70.0));
      expect(order.formattedTotal, equals('₹70'));
    });

    test('Example 1: 1 plate Momos (₹70) + ₹5 Delivery = ₹75 Total', () {
      final map = {
        'orderId': 'ord_ex1',
        'shopId': 'shop_1',
        'shopName': 'Raja Hotel',
        'customerName': 'Student',
        'customerPhone': '9876543210',
        'items': [
          {
            'menuItemId': 'momos',
            'name': 'Veg Momos',
            'price': 70,
            'quantity': 1,
          }
        ],
        'deliveryCharges': 5.0,
        'totalAmount': 75.0,
      };

      final order = AppOrder.fromMap(map);
      expect(order.subtotal, equals(70.0));
      expect(order.deliveryCharges, equals(5.0));
      expect(order.totalAmount, equals(75.0));
      expect(order.formattedTotal, equals('₹75'));

      final outMap = order.toMap();
      expect(outMap['subtotal'], equals(70.0));
      expect(outMap['deliveryCharges'], equals(5.0));
      expect(outMap['totalAmount'], equals(75.0));
    });

    test('Example 2: 2× Momos (₹140) + 3× Biryani (₹297) = ₹437 + ₹5 Delivery = ₹442 Total', () {
      final items = [
        const OrderItem(
          menuItemId: 'momos',
          name: 'Veg Momos',
          price: 70,
          quantity: 2,
        ),
        const OrderItem(
          menuItemId: 'biryani',
          name: 'Chicken Biryani',
          price: 99,
          quantity: 3,
        ),
      ];

      final subtotal = items.fold<double>(0.0, (acc, i) => acc + i.totalPrice);
      expect(subtotal, equals(437.0));

      const deliveryCharges = 5.0;
      final grandTotal = subtotal + deliveryCharges;
      expect(grandTotal, equals(442.0));

      final order = AppOrder(
        orderId: 'ord_ex2',
        shopId: 'shop_1',
        shopName: 'Raja Hotel',
        customerName: 'Student',
        customerPhone: '9876543210',
        items: items,
        deliveryCharges: deliveryCharges,
        totalAmount: grandTotal,
        createdAt: DateTime.now(),
      );

      expect(order.subtotal, equals(437.0));
      expect(order.deliveryCharges, equals(5.0));
      expect(order.totalAmount, equals(442.0));
      expect(order.formattedTotal, equals('₹442'));
    });

    test('Order Snapshot Immutability: Shop delivery charge change does NOT mutate existing order', () {
      var shop = Shop(
        id: 'shop_1',
        name: 'Raja Hotel',
        description: '',
        bannerUrl: '',
        contactNumber: '9999999999',
        orderNumber: '9999999999',
        openTime: '08:00',
        closeTime: '23:00',
        isClosedOverride: false,
        isActive: true,
        sortOrder: 1,
        searchKeywords: const [],
        deliveryNote: 'Gate 3',
        deliveryCharges: 5,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      // Customer creates order under ₹5 delivery charge
      final order = AppOrder(
        orderId: 'ord_snap_test',
        shopId: shop.id,
        shopName: shop.name,
        customerName: 'Student',
        customerPhone: '9876543210',
        items: const [
          OrderItem(
            menuItemId: 'momos',
            name: 'Veg Momos',
            price: 70,
            quantity: 1,
          ),
        ],
        deliveryCharges: shop.deliveryCharges.toDouble(),
        totalAmount: 70.0 + shop.deliveryCharges.toDouble(),
        createdAt: DateTime.now(),
      );

      expect(order.deliveryCharges, equals(5.0));
      expect(order.totalAmount, equals(75.0));

      // Shopkeeper subsequently raises delivery charges to ₹15
      shop = shop.copyWith(deliveryCharges: 15);
      expect(shop.deliveryCharges, equals(15));

      // Existing order remains 100% frozen with original ₹5 snapshot
      expect(order.deliveryCharges, equals(5.0));
      expect(order.totalAmount, equals(75.0));
      expect(order.formattedTotal, equals('₹75'));
    });
  });

  group('3. WhatsApp Order Message Formatting with Delivery Charges', () {
    const momoItem = MenuItem(
      id: 'momos',
      name: 'Veg Momos',
      details: 'Hot steamed',
      price: 70,
      imageUrl: '',
      categoryId: 'snacks',
      isVeg: true,
      isAvailable: true,
      isRecommended: true,
      sortOrder: 1,
    );

    const biryaniItem = MenuItem(
      id: 'biryani',
      name: 'Chicken Biryani',
      details: 'Spicy dum biryani',
      price: 99,
      imageUrl: '',
      categoryId: 'main',
      isVeg: false,
      isAvailable: true,
      isRecommended: true,
      sortOrder: 2,
    );

    test('deliveryCharges = 0 keeps classic Total format without separate breakdown', () {
      final cartItems = [
        const CartItem(
          menuItem: momoItem,
          quantity: 1,
          shopId: 'shop_1',
          shopName: 'Raja Hotel',
        ),
      ];

      final message = WhatsAppService.generateOrderMessage(
        shopName: 'Raja Hotel',
        userName: 'Rajat',
        userPhone: '9876543210',
        cartItems: cartItems,
      );

      expect(message, contains('Total: ₹70'));
      expect(message, isNot(contains('Delivery Charges')));
    });

    test('deliveryCharges = 5 generates Subtotal, Delivery Charges, and Total lines', () {
      final cartItems = [
        const CartItem(
          menuItem: momoItem,
          quantity: 2, // 140
          shopId: 'shop_1',
          shopName: 'Raja Hotel',
        ),
        const CartItem(
          menuItem: biryaniItem,
          quantity: 3, // 297
          shopId: 'shop_1',
          shopName: 'Raja Hotel',
        ),
      ];

      final message = WhatsAppService.generateOrderMessage(
        shopName: 'Raja Hotel',
        userName: 'Rajat',
        userPhone: '9876543210',
        cartItems: cartItems,
        deliveryCharges: 5,
      );

      expect(message, contains('Subtotal: ₹437'));
      expect(message, contains('Delivery Charges: ₹5'));
      expect(message, contains('Total: ₹442'));
    });
  });

  group('4. Cart Screen UI & Calculation Integration', () {
    testWidgets('Cart displays Subtotal ₹437, Delivery Charges ₹5, and Total ₹442', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final shop = Shop(
        id: 'shop_raja',
        name: 'Raja Hotel',
        description: 'Authentic food',
        bannerUrl: '',
        contactNumber: '8888822222',
        orderNumber: '8888822222',
        openTime: '08:00',
        closeTime: '23:30',
        isClosedOverride: false,
        isActive: true,
        sortOrder: 1,
        searchKeywords: const [],
        deliveryNote: 'Gate 3',
        deliveryCharges: 5,
        orderMethod: ShopOrderMethod.both,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      const momoItem = MenuItem(
        id: 'momos',
        name: 'Veg Momos',
        details: 'Hot',
        price: 70,
        imageUrl: '',
        categoryId: 'snacks',
        isVeg: true,
        isAvailable: true,
        isRecommended: true,
        sortOrder: 1,
      );

      const biryaniItem = MenuItem(
        id: 'biryani',
        name: 'Chicken Biryani',
        details: 'Spicy',
        price: 99,
        imageUrl: '',
        categoryId: 'main',
        isVeg: false,
        isAvailable: true,
        isRecommended: true,
        sortOrder: 2,
      );

      final fakeOrderService = _FakeOrderService();
      final fakeFirestoreService = _FakeFirestoreService(shop);

      final container = ProviderContainer(
        overrides: [
          orderServiceProvider.overrideWithValue(fakeOrderService),
          firestoreServiceProvider.overrideWithValue(fakeFirestoreService),
          shopsProvider.overrideWith((ref) async => [shop]),
        ],
      );
      addTearDown(container.dispose);

      // Populate cart with 2× Momos (140) + 3× Biryani (297) = 437
      final notifier = container.read(cartProvider.notifier);
      notifier.addItem(momoItem, 'shop_raja', 'Raja Hotel');
      notifier.addItem(momoItem, 'shop_raja', 'Raja Hotel');
      notifier.addItem(biryaniItem, 'shop_raja', 'Raja Hotel');
      notifier.addItem(biryaniItem, 'shop_raja', 'Raja Hotel');
      notifier.addItem(biryaniItem, 'shop_raja', 'Raja Hotel');

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: CartScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify Bill breakdown rows
      expect(find.text('Subtotal'), findsOneWidget);
      expect(find.text('₹437'), findsOneWidget);

      expect(find.text('Delivery Charges'), findsOneWidget);
      expect(find.text('₹5'), findsOneWidget);

      expect(find.text('Total'), findsOneWidget);
      expect(find.text('₹442'), findsOneWidget);
    });
  });
}
