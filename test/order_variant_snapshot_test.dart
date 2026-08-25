// BU Gate2Eat — Comprehensive Order Variant Snapshot & WhatsApp Formatting Test Suite
// Verifies OrderItem serialization with variant snapshots, WhatsApp formatting, and backward compatibility.

import 'package:bugate2eat_app/models/cart_item_model.dart';
import 'package:bugate2eat_app/models/menu_item_model.dart';
import 'package:bugate2eat_app/models/order_model.dart';
import 'package:bugate2eat_app/services/whatsapp_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const normalItem = MenuItem(
    id: 'maggi_101',
    name: 'Veg Maggi',
    price: 50,
    details: 'Hot spicy maggi',
    imageUrl: '',
    categoryId: 'fast_food',
    isVeg: true,
    isAvailable: true,
    isRecommended: false,
    sortOrder: 1,
  );

  const momosItem = MenuItem(
    id: 'momos_202',
    name: 'Chicken Momos',
    price: 80,
    details: 'Fresh steamed momos',
    imageUrl: '',
    categoryId: 'momos',
    isVeg: false,
    isAvailable: true,
    isRecommended: true,
    sortOrder: 2,
  );

  const halfOpt = SelectedMenuItemOption(
    groupId: 'grp_portion',
    groupName: 'Portion',
    optionId: 'opt_half',
    optionName: 'Half',
    pricingType: OptionPricingType.fixedPrice,
    price: 80,
  );

  const friedOpt = SelectedMenuItemOption(
    groupId: 'grp_prep',
    groupName: 'Preparation',
    optionId: 'opt_fried',
    optionName: 'Fried',
    pricingType: OptionPricingType.priceAdjustment,
    price: 20,
  );

  group('Checkpoint 9 — Order Snapshot & WhatsApp Formatting Tests', () {
    test('Case 9A: OrderItem model supports optionsDescription, selectedOptions, and cartKey', () {
      const orderItem = OrderItem(
        menuItemId: 'momos_202',
        name: 'Chicken Momos',
        price: 100,
        quantity: 2,
        optionsDescription: 'Half · Fried',
        selectedOptions: [halfOpt, friedOpt],
        cartKey: 'momos_202|grp_portion:opt_half|grp_prep:opt_fried',
      );

      expect(orderItem.hasOptions, isTrue);
      expect(orderItem.price, equals(100));
      expect(orderItem.quantity, equals(2));
      expect(orderItem.totalPrice, equals(200.0));
      expect(orderItem.optionsDescription, equals('Half · Fried'));
      expect(orderItem.selectedOptions.length, equals(2));
    });

    test('Case 9B: Normal OrderItem preserves backward compatibility without options', () {
      const normalOrderItem = OrderItem(
        menuItemId: 'maggi_101',
        name: 'Veg Maggi',
        price: 50,
        quantity: 1,
      );

      expect(normalOrderItem.hasOptions, isFalse);
      expect(normalOrderItem.optionsDescription, isEmpty);
      expect(normalOrderItem.selectedOptions, isEmpty);
      expect(normalOrderItem.totalPrice, equals(50.0));
    });

    test('Case 9C: OrderItem toMap and fromMap roundtrip preserves all variant data', () {
      const original = OrderItem(
        menuItemId: 'momos_202',
        name: 'Chicken Momos',
        price: 100,
        quantity: 2,
        optionsDescription: 'Half · Fried',
        selectedOptions: [halfOpt, friedOpt],
        cartKey: 'momos_202|grp_portion:opt_half|grp_prep:opt_fried',
      );

      final map = original.toMap();
      expect(map['menuItemId'], equals('momos_202'));
      expect(map['price'], equals(100));
      expect(map['quantity'], equals(2));
      expect(map['subtotal'], equals(200.0));
      expect(map['optionsDescription'], equals('Half · Fried'));
      expect(map['cartKey'], equals('momos_202|grp_portion:opt_half|grp_prep:opt_fried'));
      expect(map['selectedOptions'], isA<List>());

      final deserialized = OrderItem.fromMap(map);
      expect(deserialized.menuItemId, equals(original.menuItemId));
      expect(deserialized.name, equals(original.name));
      expect(deserialized.price, equals(original.price));
      expect(deserialized.quantity, equals(original.quantity));
      expect(deserialized.optionsDescription, equals(original.optionsDescription));
      expect(deserialized.hasOptions, isTrue);
      expect(deserialized.selectedOptions.length, equals(2));
      expect(deserialized.selectedOptions[0].optionName, equals('Half'));
      expect(deserialized.selectedOptions[1].optionName, equals('Fried'));
    });

    test('Case 9D: WhatsApp message formats variant items and normal items distinctly', () {
      final cartItems = [
        const CartItem(
          menuItem: momosItem,
          quantity: 2,
          shopId: 'shop_1',
          shopName: 'Rajat Shop',
          selectedOptions: [halfOpt, friedOpt],
          unitPriceOverride: 100,
        ),
        const CartItem(
          menuItem: normalItem,
          quantity: 1,
          shopId: 'shop_1',
          shopName: 'Rajat Shop',
        ),
      ];

      final message = WhatsAppService.generateOrderMessage(
        shopName: 'Rajat Shop',
        userName: 'Rajat Joshi',
        userPhone: '8078643910',
        cartItems: cartItems,
      );

      expect(message, contains('• 2 × Chicken Momos (Half · Fried) — ₹200'));
      expect(message, contains('• 1 × Veg Maggi — ₹50'));
      expect(message, contains('Total: ₹250'));
    });

    test('Case 9E: AppOrder toMap and fromMap serialization with mixed items', () {
      final order = AppOrder(
        orderId: 'ORD_999',
        shopId: 'shop_1',
        shopName: 'Rajat Shop',
        customerName: 'Rajat',
        customerPhone: '9876543210',
        items: const [
          OrderItem(
            menuItemId: 'momos_202',
            name: 'Chicken Momos',
            price: 100,
            quantity: 2,
            optionsDescription: 'Half · Fried',
            selectedOptions: [halfOpt, friedOpt],
          ),
          OrderItem(
            menuItemId: 'maggi_101',
            name: 'Veg Maggi',
            price: 50,
            quantity: 1,
          ),
        ],
        totalAmount: 250,
        createdAt: DateTime(2026, 8, 25, 12, 0),
      );

      final map = order.toMap();
      final restored = AppOrder.fromMap(map, 'ORD_999');

      expect(restored.orderId, equals('ORD_999'));
      expect(restored.totalAmount, equals(250.0));
      expect(restored.items.length, equals(2));
      expect(restored.items[0].name, equals('Chicken Momos'));
      expect(restored.items[0].optionsDescription, equals('Half · Fried'));
      expect(restored.items[0].price, equals(100));
      expect(restored.items[0].totalPrice, equals(200.0));
      expect(restored.items[1].name, equals('Veg Maggi'));
      expect(restored.items[1].optionsDescription, isEmpty);
      expect(restored.items[1].price, equals(50));
    });
  });
}
