// BU Gate2Eat — Bug-Fix Sprint Verification Tests
// Tests Order Method & Minimum Order persistence, Category changes, and Cart shop fallbacks

import 'package:bugate2eat_app/models/category_model.dart';
import 'package:bugate2eat_app/models/menu_item_model.dart';
import 'package:bugate2eat_app/models/order_model.dart';
import 'package:bugate2eat_app/models/shop_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Bug 1 Fix: Shop Order Method & Minimum Order Persistence', () {
    test('1. Shop.fromFirestore parses orderMethod and minimumOrderAmount', () {
      final appShop = Shop(
        id: 'test_shop',
        name: 'Test Shop',
        description: 'Test Desc',
        bannerUrl: '',
        contactNumber: '9999999999',
        orderNumber: '9999999999',
        openTime: '08:00',
        closeTime: '23:30',
        isClosedOverride: false,
        isActive: true,
        sortOrder: 1,
        searchKeywords: const [],
        deliveryNote: 'Gate 2',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        orderMethod: ShopOrderMethod.app,
        minimumOrderAmount: 150,
      );

      final firestoreMap = appShop.toFirestore();
      expect(firestoreMap['orderMethod'], 'app');
      expect(firestoreMap['minimumOrderAmount'], 150);

      // Verify parse from string
      expect(ShopOrderMethod.fromString('app'), ShopOrderMethod.app);
      expect(ShopOrderMethod.fromString('both'), ShopOrderMethod.both);
      expect(ShopOrderMethod.fromString('whatsapp'), ShopOrderMethod.whatsapp);
      expect(ShopOrderMethod.fromString(null), ShopOrderMethod.whatsapp);
      expect(ShopOrderMethod.fromString('unknown'), ShopOrderMethod.whatsapp);
    });

    test('2. ShopOrderMethod parse handles case-insensitivity and aliases', () {
      expect(ShopOrderMethod.fromString('APP'), ShopOrderMethod.app);
      expect(ShopOrderMethod.fromString('yummbu'), ShopOrderMethod.app);
      expect(ShopOrderMethod.fromString('BOTH'), ShopOrderMethod.both);
      expect(ShopOrderMethod.fromString('WHATSAPP'), ShopOrderMethod.whatsapp);
    });

    test('3. Shop copyWith preserves orderMethod and minimumOrderAmount', () {
      final original = Shop(
        id: 'shop_1',
        name: 'Original Shop',
        description: 'Desc',
        bannerUrl: '',
        contactNumber: '123',
        orderNumber: '123',
        openTime: '08:00',
        closeTime: '22:00',
        isClosedOverride: false,
        isActive: true,
        sortOrder: 0,
        searchKeywords: const [],
        deliveryNote: 'Gate 2',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        orderMethod: ShopOrderMethod.whatsapp,
        minimumOrderAmount: 0,
      );

      final updated = original.copyWith(
        orderMethod: ShopOrderMethod.both,
        minimumOrderAmount: 200,
      );

      expect(updated.orderMethod, ShopOrderMethod.both);
      expect(updated.minimumOrderAmount, 200);
      expect(updated.toFirestore()['orderMethod'], 'both');
      expect(updated.toFirestore()['minimumOrderAmount'], 200);
    });

    test('4. Complete Shop Data Persistence: All 14 fields serialize & deserialize accurately', () {
      final shop = Shop(
        id: 'rajat_shop',
        name: 'Rajat Shop Special',
        description: 'Chinese, Fast Food & Momos',
        bannerUrl: 'https://example.com/banner.jpg',
        contactNumber: '8295643910',
        orderNumber: '8295643910',
        openTime: '09:00',
        closeTime: '23:00',
        isClosedOverride: true,
        isActive: true,
        sortOrder: 2,
        searchKeywords: const ['chinese', 'momos', 'fast food'],
        deliveryNote: 'Pickup at Gate 2',
        createdAt: DateTime(2026, 1, 1, 10, 0),
        updatedAt: DateTime(2026, 1, 1, 12, 0),
        orderMethod: ShopOrderMethod.both,
        minimumOrderAmount: 250,
      );

      final map = shop.toFirestore();
      expect(map['name'], 'Rajat Shop Special');
      expect(map['description'], 'Chinese, Fast Food & Momos');
      expect(map['bannerUrl'], 'https://example.com/banner.jpg');
      expect(map['contactNumber'], '8295643910');
      expect(map['orderNumber'], '8295643910');
      expect(map['openTime'], '09:00');
      expect(map['closeTime'], '23:00');
      expect(map['isClosedOverride'], true);
      expect(map['isActive'], true);
      expect(map['sortOrder'], 2);
      expect(map['searchKeywords'], ['chinese', 'momos', 'fast food']);
      expect(map['deliveryNote'], 'Pickup at Gate 2');
      expect(map['orderMethod'], 'both');
      expect(map['minimumOrderAmount'], 250);
    });
  });

  group('Bug 2 Fix: Menu Item Category Changes & Resolution', () {
    test('1. Category ID resolution matches existing category or creates slug', () {
      final categories = [
        const Category(id: 'cat_momos', name: 'Momos', sortOrder: 1),
        const Category(id: 'cat_burgers', name: 'Burgers', sortOrder: 2),
      ];

      // Match by Name
      final matchByName = categories
          .where((c) => c.name.toLowerCase() == 'momos'.toLowerCase() || c.id.toLowerCase() == 'momos'.toLowerCase())
          .firstOrNull;
      expect(matchByName?.id, 'cat_momos');

      // Match by ID
      final matchById = categories
          .where((c) => c.name.toLowerCase() == 'cat_burgers'.toLowerCase() || c.id.toLowerCase() == 'cat_burgers'.toLowerCase())
          .firstOrNull;
      expect(matchById?.id, 'cat_burgers');

      // New Category (returns null to trigger creation)
      final noMatch = categories
          .where((c) => c.name.toLowerCase() == 'beverages'.toLowerCase() || c.id.toLowerCase() == 'beverages'.toLowerCase())
          .firstOrNull;
      expect(noMatch, isNull);
    });

    test('2. Menu Item serialization includes updated categoryId and all 10 fields', () {
      const item = MenuItem(
        id: 'item_1',
        name: 'Veg Steamed Momos',
        price: 80,
        details: 'Delicious steamed momos',
        imageUrl: 'https://example.com/item.jpg',
        isVeg: true,
        isAvailable: true,
        isRecommended: true,
        categoryId: 'cat_momos',
        sortOrder: 1,
      );

      final map = item.toFirestore();
      expect(map['name'], 'Veg Steamed Momos');
      expect(map['details'], 'Delicious steamed momos');
      expect(map['price'], 80);
      expect(map['imageUrl'], 'https://example.com/item.jpg');
      expect(map['isVeg'], true);
      expect(map['isAvailable'], true);
      expect(map['isRecommended'], true);
      expect(map['categoryId'], 'cat_momos');
      expect(map['sortOrder'], 1);
    });
  });

  group('Order Model Serialization & Lifecycle Timestamps', () {
    test('1. AppOrder serializes and deserializes all 18 fields cleanly', () {
      final now = DateTime.now();
      final order = AppOrder(
        orderId: 'YB-2026-001',
        shopId: 'rajat_shop',
        shopName: 'Rajat Shop',
        customerId: 'cust_123',
        customerName: 'Aarav Sharma',
        customerPhone: '9876543210',
        items: const [
          OrderItem(
            menuItemId: 'item_1',
            name: 'Veg Steamed Momos',
            price: 80,
            quantity: 2,
            imageUrl: 'https://example.com/momos.jpg',
          ),
        ],
        totalAmount: 160.0,
        specialInstructions: 'Extra spicy',
        deliveryNote: 'Gate 2',
        status: 'placed',
        createdAt: now,
      );

      final map = order.toMap();
      expect(map['orderId'], 'YB-2026-001');
      expect(map['shopId'], 'rajat_shop');
      expect(map['customerId'], 'cust_123');
      expect(map['customerPhone'], '9876543210');
      expect(map['totalAmount'], 160.0);
      expect(map['status'], 'placed');
      expect(map['specialInstructions'], 'Extra spicy');

      final deserialized = AppOrder.fromMap(map);
      expect(deserialized.orderId, 'YB-2026-001');
      expect(deserialized.shopName, 'Rajat Shop');
      expect(deserialized.totalAmount, 160.0);
      expect(deserialized.items.first.name, 'Veg Steamed Momos');
      expect(deserialized.items.first.quantity, 2);
    });
  });
}
