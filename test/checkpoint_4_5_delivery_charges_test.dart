// BU Gate2Eat — Checkpoint 4.5
// Automated Test Suite for Custom Delivery Charges Feature

import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:bugate2eat_app/models/shop_model.dart';
import 'package:bugate2eat_app/models/order_model.dart';
import 'package:bugate2eat_app/models/menu_item_model.dart';
import 'package:bugate2eat_app/models/cart_item_model.dart';
import 'package:bugate2eat_app/services/whatsapp_service.dart';

void main() {
  group('Checkpoint 4.5 — Custom Delivery Charges Suite', () {
    // ── 1. Shop Model Tests ──────────────────────────────────────────────────
    group('1. Shop Model — deliveryCharges Field & Invariants', () {
      test('Shop constructor assigns deliveryCharges with default 0', () {
        final shop = Shop(
          id: 'shop_1',
          name: 'Raja Dhaba',
          description: 'Authentic food',
          bannerUrl: 'https://example.com/banner.jpg',
          contactNumber: '9876543210',
          orderNumber: '9876543210',
          openTime: '08:00',
          closeTime: '23:30',
          isClosedOverride: false,
          isActive: true,
          sortOrder: 1,
          searchKeywords: const ['raja', 'dhaba'],
          deliveryNote: 'Gate 3',
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
        );

        expect(shop.deliveryCharges, equals(0));
      });

      test('Shop constructor assigns custom deliveryCharges (e.g. ₹5)', () {
        final shop = Shop(
          id: 'shop_1',
          name: 'Raja Dhaba',
          description: 'Authentic food',
          bannerUrl: 'https://example.com/banner.jpg',
          contactNumber: '9876543210',
          orderNumber: '9876543210',
          openTime: '08:00',
          closeTime: '23:30',
          isClosedOverride: false,
          isActive: true,
          sortOrder: 1,
          searchKeywords: const ['raja', 'dhaba'],
          deliveryNote: 'Gate 3',
          deliveryCharges: 5,
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
        );

        expect(shop.deliveryCharges, equals(5));
      });

      test('Shop.fromMap fallback — missing field defaults to 0', () {
        final map = <String, dynamic>{
          'name': 'Test Shop',
          'description': 'Desc',
          'openTime': '08:00',
          'closeTime': '23:30',
          // No deliveryCharges, deliveryCharge, or deliveryFee
        };

        final shop = Shop.fromMap(map, 'test_shop_id');
        expect(shop.deliveryCharges, equals(0));
      });

      test('Shop.fromMap parses deliveryCharges, deliveryCharge, and deliveryFee aliases', () {
        final map1 = {'name': 'Shop 1', 'deliveryCharges': 15};
        final map2 = {'name': 'Shop 2', 'deliveryCharge': 20};
        final map3 = {'name': 'Shop 3', 'deliveryFee': 25};

        expect(Shop.fromMap(map1).deliveryCharges, equals(15));
        expect(Shop.fromMap(map2).deliveryCharges, equals(20));
        expect(Shop.fromMap(map3).deliveryCharges, equals(25));
      });

      test('Shop.fromMap clamps negative delivery charges to 0', () {
        final map = {'name': 'Shop Negative', 'deliveryCharges': -50};
        final shop = Shop.fromMap(map);
        expect(shop.deliveryCharges, equals(0));
      });

      test('Shop.toFirestore includes deliveryCharges', () {
        final shop = Shop(
          id: 'shop_1',
          name: 'Dhaba',
          description: '',
          bannerUrl: '',
          contactNumber: '9876543210',
          orderNumber: '9876543210',
          openTime: '08:00',
          closeTime: '23:30',
          isClosedOverride: false,
          isActive: true,
          sortOrder: 1,
          searchKeywords: const [],
          deliveryNote: 'Gate 3',
          deliveryCharges: 10,
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
        );

        final firestoreMap = shop.toFirestore();
        expect(firestoreMap['deliveryCharges'], equals(10));
      });

      test('Shop.copyWith updates or preserves deliveryCharges', () {
        final shop = Shop(
          id: 'shop_1',
          name: 'Dhaba',
          description: '',
          bannerUrl: '',
          contactNumber: '9876543210',
          orderNumber: '9876543210',
          openTime: '08:00',
          closeTime: '23:30',
          isClosedOverride: false,
          isActive: true,
          sortOrder: 1,
          searchKeywords: const [],
          deliveryNote: 'Gate 3',
          deliveryCharges: 5,
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
        );

        final updated = shop.copyWith(deliveryCharges: 15);
        expect(updated.deliveryCharges, equals(15));

        final preserved = updated.copyWith(name: 'Updated Name');
        expect(preserved.deliveryCharges, equals(15));
      });
    });

    // ── 2. Order Model & Snapshot Preservation ──────────────────────────────
    group('2. AppOrder Model — deliveryCharges Snapshot & Invariants', () {
      test('AppOrder constructor defaults deliveryCharges to 0.0', () {
        final order = AppOrder(
          orderId: 'YB-101',
          shopId: 'shop_1',
          shopName: 'Raja Dhaba',
          customerName: 'Rajat',
          customerPhone: '9876543210',
          items: const [
            OrderItem(menuItemId: 'm1', name: 'Momos', price: 70, quantity: 1),
          ],
          totalAmount: 70.0,
          createdAt: DateTime(2026, 9, 2),
        );

        expect(order.deliveryCharges, equals(0.0));
        expect(order.subtotal, equals(70.0));
        expect(order.totalAmount, equals(70.0));
      });

      test('AppOrder fromMap reads deliveryCharges and falls back to 0.0', () {
        final mapWithCharge = <String, dynamic>{
          'orderId': 'YB-102',
          'shopId': 'shop_1',
          'totalAmount': 75.0,
          'deliveryCharges': 5.0,
          'items': [
            {'menuItemId': 'm1', 'name': 'Momos', 'price': 70, 'quantity': 1},
          ],
          'createdAt': Timestamp.now(),
        };

        final orderWithCharge = AppOrder.fromMap(mapWithCharge);
        expect(orderWithCharge.deliveryCharges, equals(5.0));
        expect(orderWithCharge.subtotal, equals(70.0));
        expect(orderWithCharge.totalAmount, equals(75.0));

        final legacyMap = <String, dynamic>{
          'orderId': 'YB-103',
          'shopId': 'shop_1',
          'totalAmount': 70.0,
          // No deliveryCharges field
          'items': [
            {'menuItemId': 'm1', 'name': 'Momos', 'price': 70, 'quantity': 1},
          ],
          'createdAt': Timestamp.now(),
        };

        final legacyOrder = AppOrder.fromMap(legacyMap);
        expect(legacyOrder.deliveryCharges, equals(0.0));
      });

      test('AppOrder toMap writes subtotal, deliveryCharges, and totalAmount', () {
        final order = AppOrder(
          orderId: 'YB-104',
          shopId: 'shop_1',
          shopName: 'Raja Dhaba',
          customerName: 'Rajat',
          customerPhone: '9876543210',
          items: const [
            OrderItem(menuItemId: 'm1', name: 'Momos', price: 70, quantity: 2), // 140
            OrderItem(menuItemId: 'm2', name: 'Biryani', price: 99, quantity: 3), // 297
          ],
          deliveryCharges: 5.0,
          totalAmount: 442.0, // 140 + 297 = 437 + 5 = 442
          createdAt: DateTime(2026, 9, 2),
        );

        final map = order.toMap();
        expect(map['subtotal'], equals(437.0));
        expect(map['deliveryCharges'], equals(5.0));
        expect(map['totalAmount'], equals(442.0));
        expect(map['grandTotal'], equals(442.0));
      });

      test('Order snapshot preservation — changing shop deliveryCharges later does NOT alter existing order', () {
        // Step 1: Shop has ₹5 delivery charge
        var shop = Shop(
          id: 'shop_1',
          name: 'Raja Dhaba',
          description: '',
          bannerUrl: '',
          contactNumber: '9876543210',
          orderNumber: '9876543210',
          openTime: '08:00',
          closeTime: '23:30',
          isClosedOverride: false,
          isActive: true,
          sortOrder: 1,
          searchKeywords: const [],
          deliveryNote: 'Gate 3',
          deliveryCharges: 5,
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
        );

        // Step 2: Customer places order
        final placedOrder = AppOrder(
          orderId: 'YB-ORDER-1',
          shopId: shop.id,
          shopName: shop.name,
          customerName: 'Rajat',
          customerPhone: '9876543210',
          items: const [
            OrderItem(menuItemId: 'm1', name: 'Momos', price: 70, quantity: 1),
          ],
          deliveryCharges: shop.deliveryCharges.toDouble(),
          totalAmount: 70.0 + shop.deliveryCharges,
          createdAt: DateTime.now(),
        );

        expect(placedOrder.deliveryCharges, equals(5.0));
        expect(placedOrder.totalAmount, equals(75.0));

        // Step 3: Shopkeeper later updates delivery charge to ₹15
        shop = shop.copyWith(deliveryCharges: 15);
        expect(shop.deliveryCharges, equals(15));

        // Step 4: Verify existing order is completely untouched
        expect(placedOrder.deliveryCharges, equals(5.0));
        expect(placedOrder.totalAmount, equals(75.0));
        expect(placedOrder.formattedTotal, equals('₹75'));
      });
    });

    // ── 3. Exact Calculation Examples ─────────────────────────────────────────
    group('3. Calculation Invariants & User Examples', () {
      test('Example 1: 1 plate momos ₹70 + delivery ₹5 = Final Total ₹75', () {
        const subtotal = 70.0;
        const deliveryCharge = 5.0;
        final finalTotal = subtotal + deliveryCharge;

        expect(finalTotal, equals(75.0));
      });

      test('Example 2: 2 plate momos (₹140) + 3 plate biryani (₹297) = Subtotal ₹437 + delivery ₹5 = Final Total ₹442', () {
        const momosPrice = 70;
        const momosQty = 2;
        const biryaniPrice = 99;
        const biryaniQty = 3;

        final subtotal = (momosPrice * momosQty) + (biryaniPrice * biryaniQty);
        expect(subtotal, equals(437));

        const deliveryCharge = 5.0;
        final finalTotal = subtotal + deliveryCharge;
        expect(finalTotal, equals(442.0));
      });

      test('Example 3: Subtotal ₹437 + delivery ₹0 = Final Total ₹437 (Free Delivery)', () {
        const subtotal = 437.0;
        const deliveryCharge = 0.0;
        final finalTotal = subtotal + deliveryCharge;

        expect(finalTotal, equals(437.0));
      });
    });

    // ── 4. WhatsApp Service Formatting ───────────────────────────────────────
    group('4. WhatsApp Order Message Formatting with Delivery Charges', () {
      final momosItem = MenuItem(
        id: 'm1',
        name: 'Veg Momos',
        details: 'Steamed',
        price: 70,
        imageUrl: '',
        categoryId: 'cat_1',
        isVeg: true,
        isAvailable: true,
        isRecommended: false,
        sortOrder: 1,
      );

      final biryaniItem = MenuItem(
        id: 'm2',
        name: 'Chicken Biryani',
        details: 'Spicy',
        price: 99,
        imageUrl: '',
        categoryId: 'cat_1',
        isVeg: false,
        isAvailable: true,
        isRecommended: false,
        sortOrder: 2,
      );

      test('WhatsApp message includes Subtotal, Delivery Charges, and Total when deliveryCharges > 0', () {
        final cartItems = [
          CartItem(menuItem: momosItem, quantity: 2, shopId: 'shop_1', shopName: 'Raja Dhaba'),
          CartItem(menuItem: biryaniItem, quantity: 3, shopId: 'shop_1', shopName: 'Raja Dhaba'),
        ];

        final message = WhatsAppService.generateOrderMessage(
          shopName: 'Raja Dhaba',
          userName: 'Rajat Joshi',
          userPhone: '9876543210',
          cartItems: cartItems,
          deliveryCharges: 5.0,
        );

        expect(message, contains('Subtotal: ₹437'));
        expect(message, contains('Delivery Charges: ₹5'));
        expect(message, contains('Total: ₹442'));
      });

      test('WhatsApp message omits Delivery Charges breakdown when deliveryCharges == 0', () {
        final cartItems = [
          CartItem(menuItem: momosItem, quantity: 1, shopId: 'shop_1', shopName: 'Raja Dhaba'),
        ];

        final message = WhatsAppService.generateOrderMessage(
          shopName: 'Raja Dhaba',
          userName: 'Rajat Joshi',
          userPhone: '9876543210',
          cartItems: cartItems,
          deliveryCharges: 0.0,
        );

        expect(message, isNot(contains('Delivery Charges:')));
        expect(message, contains('Total: ₹70'));
      });
    });
  });
}
