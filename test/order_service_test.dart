// BU Gate2Eat — Order Model, Serialization & Lifecycle Transition Test Suite (Phase 3 — Part 3.1)

import 'package:bugate2eat_app/models/order_model.dart';
import 'package:bugate2eat_app/services/order_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Phase 3 — Part 3.1: Order Model & Serialization Tests', () {
    final fixedTime = DateTime(2026, 8, 23, 14, 30, 0);

    final testOrder = AppOrder(
      orderId: 'YB-TEST-101',
      shopId: 'rajat_shop',
      shopName: 'Rajat Shop',
      customerId: 'cust_bennett_123',
      customerName: 'Rohit Verma',
      customerPhone: '9876543210',
      items: const [
        OrderItem(
          menuItemId: 'item_1',
          name: 'Crispy Veg Burger',
          price: 90,
          quantity: 2,
          imageUrl: 'https://example.com/burger.jpg',
        ),
        OrderItem(
          menuItemId: 'item_2',
          name: 'Cold Coffee',
          price: 50,
          quantity: 1,
        ),
      ],
      totalAmount: 230,
      specialInstructions: 'Extra napkins please',
      deliveryNote: 'Gate 2 Delivery Point',
      status: 'placed',
      rejectionReason: '',
      createdAt: fixedTime,
      updatedAt: fixedTime,
    );

    test('OrderItem correctly computes totalPrice and serializes to/from map',
        () {
      const item = OrderItem(
        menuItemId: 'item_1',
        name: 'Veg Roll',
        price: 80,
        quantity: 3,
        imageUrl: 'https://example.com/roll.jpg',
      );

      expect(item.totalPrice, equals(240.0));

      final map = item.toMap();
      expect(map['itemId'], equals('item_1'));
      expect(map['menuItemId'], equals('item_1'));
      expect(map['name'], equals('Veg Roll'));
      expect(map['price'], equals(80));
      expect(map['quantity'], equals(3));
      expect(map['subtotal'], equals(240.0));
      expect(map['imageUrl'], equals('https://example.com/roll.jpg'));

      final parsed = OrderItem.fromMap(map);
      expect(parsed.menuItemId, equals('item_1'));
      expect(parsed.name, equals('Veg Roll'));
      expect(parsed.price, equals(80));
      expect(parsed.quantity, equals(3));
      expect(parsed.totalPrice, equals(240.0));
      expect(parsed.imageUrl, equals('https://example.com/roll.jpg'));
    });

    test('AppOrder serializes to Firestore map with Timestamps and structure',
        () {
      final map = testOrder.toFirestore();

      expect(map['orderId'], equals('YB-TEST-101'));
      expect(map['shopId'], equals('rajat_shop'));
      expect(map['shopName'], equals('Rajat Shop'));
      expect(map['customerId'], equals('cust_bennett_123'));
      expect(map['customerName'], equals('Rohit Verma'));
      expect(map['customerPhone'], equals('9876543210'));
      expect(map['grandTotal'], equals(230.0));
      expect(map['totalAmount'], equals(230.0));
      expect(map['totalItems'], equals(3));
      expect(map['specialInstructions'], equals('Extra napkins please'));
      expect(map['deliveryNote'], equals('Gate 2 Delivery Point'));
      expect(map['status'], equals('placed'));
      expect(map['rejectionReason'], equals(''));

      expect(map['createdAt'], isA<Timestamp>());
      expect((map['createdAt'] as Timestamp).toDate(), equals(fixedTime));
      expect(map['updatedAt'], isA<Timestamp>());

      final items = map['items'] as List<dynamic>;
      expect(items.length, equals(2));
      expect(items[0]['name'], equals('Crispy Veg Burger'));
      expect(items[0]['quantity'], equals(2));
    });

    test('AppOrder deserializes from Map with Firestore Timestamps correctly',
        () {
      final map = testOrder.toFirestore();
      final parsed = AppOrder.fromMap(map);

      expect(parsed.orderId, equals('YB-TEST-101'));
      expect(parsed.shopId, equals('rajat_shop'));
      expect(parsed.shopName, equals('Rajat Shop'));
      expect(parsed.customerId, equals('cust_bennett_123'));
      expect(parsed.customerName, equals('Rohit Verma'));
      expect(parsed.customerPhone, equals('9876543210'));
      expect(parsed.totalAmount, equals(230.0));
      expect(parsed.totalItemCount, equals(3));
      expect(parsed.subtotal, equals(230.0));
      expect(parsed.specialInstructions, equals('Extra napkins please'));
      expect(parsed.deliveryNote, equals('Gate 2 Delivery Point'));
      expect(parsed.status, equals('placed'));
      expect(parsed.rejectionReason, equals(''));
      expect(parsed.createdAt, equals(fixedTime));
      expect(parsed.items.length, equals(2));
    });

    test(
        'AppOrder handles missing / null optional fields and ISO8601 string dates gracefully without crashing',
        () {
      final minimalMap = {
        'orderId': 'YB-MIN-01',
        'shopId': 'nayan_shop',
        'shopName': 'Nayan Shop',
        'customerName': 'Aman',
        'totalAmount': 100,
        'createdAt': '2026-08-23T10:00:00.000Z',
      };

      final parsed = AppOrder.fromMap(minimalMap);

      expect(parsed.orderId, equals('YB-MIN-01'));
      expect(parsed.shopId, equals('nayan_shop'));
      expect(parsed.shopName, equals('Nayan Shop'));
      expect(parsed.customerId, equals(''));
      expect(parsed.customerPhone, equals(''));
      expect(parsed.items, isEmpty);
      expect(parsed.totalItemCount, equals(0));
      expect(parsed.totalAmount, equals(100.0));
      expect(parsed.specialInstructions, equals(''));
      expect(parsed.deliveryNote, equals('Bennett University'));
      expect(parsed.status, equals('placed'));
      expect(parsed.rejectionReason, equals(''));
      expect(parsed.createdAt, equals(DateTime.utc(2026, 8, 23, 10, 0, 0)));
      expect(parsed.acceptedAt, isNull);
      expect(parsed.deliveredAt, isNull);
      expect(parsed.rejectedAt, isNull);
    });

    test('AppOrder copyWith works cleanly and immutably', () {
      final updated = testOrder.copyWith(
        status: 'accepted',
        acceptedAt: fixedTime.add(const Duration(minutes: 2)),
      );

      expect(updated.status, equals('accepted'));
      expect(updated.acceptedAt,
          equals(fixedTime.add(const Duration(minutes: 2))));
      expect(updated.orderId, equals(testOrder.orderId));
      expect(testOrder.status, equals('placed')); // Original unchanged
    });
  });

  group('Phase 3 — Part 3.1: Order Status Lifecycle & Transition Rules', () {
    test('PLACED order valid transitions', () {
      // placed -> accepted ✅
      expect(
        OrderStatusRules.isValidTransition(
          OrderStatusRules.statusPlaced,
          OrderStatusRules.statusAccepted,
        ),
        isTrue,
      );

      // placed -> rejected ✅
      expect(
        OrderStatusRules.isValidTransition(
          OrderStatusRules.statusPlaced,
          OrderStatusRules.statusRejected,
        ),
        isTrue,
      );

      // placed -> cancelled ✅
      expect(
        OrderStatusRules.isValidTransition(
          OrderStatusRules.statusPlaced,
          OrderStatusRules.statusCancelled,
        ),
        isTrue,
      );

      // placed -> delivered ❌ (Must be accepted first)
      expect(
        OrderStatusRules.isValidTransition(
          OrderStatusRules.statusPlaced,
          OrderStatusRules.statusDelivered,
        ),
        isFalse,
      );
    });

    test('ACCEPTED order valid transitions', () {
      // accepted -> delivered ✅
      expect(
        OrderStatusRules.isValidTransition(
          OrderStatusRules.statusAccepted,
          OrderStatusRules.statusDelivered,
        ),
        isTrue,
      );

      // accepted -> rejected ✅
      expect(
        OrderStatusRules.isValidTransition(
          OrderStatusRules.statusAccepted,
          OrderStatusRules.statusRejected,
        ),
        isTrue,
      );

      // accepted -> cancelled ❌ (Customer cannot cancel accepted order)
      expect(
        OrderStatusRules.isValidTransition(
          OrderStatusRules.statusAccepted,
          OrderStatusRules.statusCancelled,
        ),
        isFalse,
      );

      // accepted -> placed ❌ (Cannot revert to placed)
      expect(
        OrderStatusRules.isValidTransition(
          OrderStatusRules.statusAccepted,
          OrderStatusRules.statusPlaced,
        ),
        isFalse,
      );
    });

    test('DELIVERED terminal state cannot transition anywhere', () {
      expect(
        OrderStatusRules.isValidTransition(
          OrderStatusRules.statusDelivered,
          OrderStatusRules.statusAccepted,
        ),
        isFalse,
      );

      expect(
        OrderStatusRules.isValidTransition(
          OrderStatusRules.statusDelivered,
          OrderStatusRules.statusPlaced,
        ),
        isFalse,
      );

      expect(
        OrderStatusRules.isValidTransition(
          OrderStatusRules.statusDelivered,
          OrderStatusRules.statusCancelled,
        ),
        isFalse,
      );

      expect(
        OrderStatusRules.isTerminal(OrderStatusRules.statusDelivered),
        isTrue,
      );
      expect(
        OrderStatusRules.isActive(OrderStatusRules.statusDelivered),
        isFalse,
      );
    });

    test('REJECTED terminal state cannot transition anywhere', () {
      expect(
        OrderStatusRules.isValidTransition(
          OrderStatusRules.statusRejected,
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
        OrderStatusRules.isTerminal(OrderStatusRules.statusRejected),
        isTrue,
      );
    });

    test('CANCELLED terminal state cannot transition anywhere', () {
      expect(
        OrderStatusRules.isValidTransition(
          OrderStatusRules.statusCancelled,
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

      expect(
        OrderStatusRules.isTerminal(OrderStatusRules.statusCancelled),
        isTrue,
      );
    });
  });
}
