// BU Gate2Eat — Comprehensive Variant-Aware Cart Data Layer Test Suite
// Verifies variant-aware cart line separation, quantity increment, deterministic cartKey, and backward compatibility.

import 'package:bugate2eat_app/features/cart/cart_provider.dart';
import 'package:bugate2eat_app/models/cart_item_model.dart';
import 'package:bugate2eat_app/models/menu_item_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late CartNotifier cartNotifier;

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
    optionGroups: [
      MenuItemOptionGroup(
        id: 'grp_portion',
        name: 'Portion',
        required: true,
        options: [
          MenuItemOption(
            id: 'opt_half',
            name: 'Half',
            price: 80,
            pricingType: OptionPricingType.fixedPrice,
            isDefault: true,
          ),
          MenuItemOption(
            id: 'opt_full',
            name: 'Full',
            price: 140,
            pricingType: OptionPricingType.fixedPrice,
          ),
        ],
      ),
      MenuItemOptionGroup(
        id: 'grp_prep',
        name: 'Preparation',
        required: true,
        options: [
          MenuItemOption(
            id: 'opt_steamed',
            name: 'Steamed',
            price: 0,
            pricingType: OptionPricingType.priceAdjustment,
            isDefault: true,
          ),
          MenuItemOption(
            id: 'opt_fried',
            name: 'Fried',
            price: 20,
            pricingType: OptionPricingType.priceAdjustment,
          ),
        ],
      ),
    ],
  );

  const halfOpt = SelectedMenuItemOption(
    groupId: 'grp_portion',
    groupName: 'Portion',
    optionId: 'opt_half',
    optionName: 'Half',
    pricingType: OptionPricingType.fixedPrice,
    price: 80,
  );

  const fullOpt = SelectedMenuItemOption(
    groupId: 'grp_portion',
    groupName: 'Portion',
    optionId: 'opt_full',
    optionName: 'Full',
    pricingType: OptionPricingType.fixedPrice,
    price: 140,
  );

  const steamedOpt = SelectedMenuItemOption(
    groupId: 'grp_prep',
    groupName: 'Preparation',
    optionId: 'opt_steamed',
    optionName: 'Steamed',
    pricingType: OptionPricingType.priceAdjustment,
    price: 0,
  );

  const friedOpt = SelectedMenuItemOption(
    groupId: 'grp_prep',
    groupName: 'Preparation',
    optionId: 'opt_fried',
    optionName: 'Fried',
    pricingType: OptionPricingType.priceAdjustment,
    price: 20,
  );

  setUp(() {
    cartNotifier = CartNotifier();
  });

  group('Checkpoint 7 — Variant-Aware Cart Data Layer Tests', () {
    test('Case A: Normal item added twice creates 1 cart line with quantity = 2, total = ₹100', () {
      final res1 = cartNotifier.addItem(normalItem, 'shop_1', 'Rajat Shop');
      final res2 = cartNotifier.addItem(normalItem, 'shop_1', 'Rajat Shop');

      expect(res1, isTrue);
      expect(res2, isTrue);
      expect(cartNotifier.state.items.length, equals(1));
      expect(cartNotifier.state.items.first.quantity, equals(2));
      expect(cartNotifier.state.items.first.unitPrice, equals(50));
      expect(cartNotifier.state.items.first.totalPrice, equals(100.0));
      expect(cartNotifier.state.items.first.cartKey, equals('maggi_101'));
      expect(cartNotifier.state.items.first.hasSelectedOptions, isFalse);
      expect(cartNotifier.state.items.first.optionsDescription, isEmpty);
    });

    test('Case B: Adding different variants of same item creates 2 separate cart lines', () {
      // Add Half (₹80)
      cartNotifier.addItem(
        momosItem,
        'shop_1',
        'Rajat Shop',
        selectedOptions: [halfOpt],
        unitPrice: 80,
      );

      // Add Full (₹140)
      cartNotifier.addItem(
        momosItem,
        'shop_1',
        'Rajat Shop',
        selectedOptions: [fullOpt],
        unitPrice: 140,
      );

      expect(cartNotifier.state.items.length, equals(2));
      expect(cartNotifier.state.items[0].cartKey, equals('momos_202|grp_portion:opt_half'));
      expect(cartNotifier.state.items[0].unitPrice, equals(80));
      expect(cartNotifier.state.items[0].quantity, equals(1));

      expect(cartNotifier.state.items[1].cartKey, equals('momos_202|grp_portion:opt_full'));
      expect(cartNotifier.state.items[1].unitPrice, equals(140));
      expect(cartNotifier.state.items[1].quantity, equals(1));

      expect(cartNotifier.state.grandTotal, equals(220.0));
    });

    test('Case C: Adding same variant twice increments quantity on the same line', () {
      cartNotifier.addItem(
        momosItem,
        'shop_1',
        'Rajat Shop',
        selectedOptions: [halfOpt],
        unitPrice: 80,
      );

      cartNotifier.addItem(
        momosItem,
        'shop_1',
        'Rajat Shop',
        selectedOptions: [halfOpt],
        unitPrice: 80,
      );

      expect(cartNotifier.state.items.length, equals(1));
      expect(cartNotifier.state.items.first.quantity, equals(2));
      expect(cartNotifier.state.items.first.unitPrice, equals(80));
      expect(cartNotifier.state.items.first.totalPrice, equals(160.0));
      expect(cartNotifier.state.grandTotal, equals(160.0));
    });

    test('Case D: Multiple option groups create distinct separate variant lines', () {
      // Half + Fried = ₹100
      cartNotifier.addItem(
        momosItem,
        'shop_1',
        'Rajat Shop',
        selectedOptions: [halfOpt, friedOpt],
        unitPrice: 100,
      );

      // Full + Fried = ₹160
      cartNotifier.addItem(
        momosItem,
        'shop_1',
        'Rajat Shop',
        selectedOptions: [fullOpt, friedOpt],
        unitPrice: 160,
      );

      expect(cartNotifier.state.items.length, equals(2));
      expect(cartNotifier.state.items[0].optionsDescription, equals('Half · Fried'));
      expect(cartNotifier.state.items[0].totalPrice, equals(100.0));

      expect(cartNotifier.state.items[1].optionsDescription, equals('Full · Fried'));
      expect(cartNotifier.state.items[1].totalPrice, equals(160.0));

      // Half + Steamed = ₹80
      cartNotifier.addItem(
        momosItem,
        'shop_1',
        'Rajat Shop',
        selectedOptions: [halfOpt, steamedOpt],
        unitPrice: 80,
      );

      // Full + Steamed = ₹140
      cartNotifier.addItem(
        momosItem,
        'shop_1',
        'Rajat Shop',
        selectedOptions: [fullOpt, steamedOpt],
        unitPrice: 140,
      );

      expect(cartNotifier.state.items.length, equals(4));
      expect(cartNotifier.state.items[2].optionsDescription, equals('Half · Steamed'));
      expect(cartNotifier.state.items[2].totalPrice, equals(80.0));
      expect(cartNotifier.state.items[3].optionsDescription, equals('Full · Steamed'));
      expect(cartNotifier.state.items[3].totalPrice, equals(140.0));

      expect(cartNotifier.state.grandTotal, equals(480.0));
    });

    test('Case E: Deterministic cartKey identity ignores option list insertion order', () {
      final keyOrder1 = CartItem.buildCartKey('momos_202', [halfOpt, friedOpt]);
      final keyOrder2 = CartItem.buildCartKey('momos_202', [friedOpt, halfOpt]);

      expect(keyOrder1, equals(keyOrder2));
      expect(keyOrder1, equals('momos_202|grp_portion:opt_half|grp_prep:opt_fried'));
    });

    test('Case F: Single-shop invariant prevents adding variant to another shop', () {
      cartNotifier.addItem(
        momosItem,
        'shop_1',
        'Rajat Shop',
        selectedOptions: [halfOpt],
        unitPrice: 80,
      );

      // Try adding variant to another shop
      final conflict = cartNotifier.addItem(
        normalItem,
        'shop_2',
        'Nayan Food Court',
      );

      expect(conflict, isFalse);
      expect(cartNotifier.state.shopId, equals('shop_1'));
      expect(cartNotifier.state.items.length, equals(1));
    });

    test('Case G: Decrement and delete by cartKey work accurately without affecting sibling variants', () {
      // Add Half x 2 (₹80 each)
      cartNotifier.addItem(
        momosItem,
        'shop_1',
        'Rajat Shop',
        selectedOptions: [halfOpt],
        unitPrice: 80,
      );
      cartNotifier.addItem(
        momosItem,
        'shop_1',
        'Rajat Shop',
        selectedOptions: [halfOpt],
        unitPrice: 80,
      );

      // Add Full x 1 (₹140)
      cartNotifier.addItem(
        momosItem,
        'shop_1',
        'Rajat Shop',
        selectedOptions: [fullOpt],
        unitPrice: 140,
      );

      expect(cartNotifier.state.items.length, equals(2));

      // Decrement Half: 2 -> 1
      cartNotifier.removeItem('momos_202|grp_portion:opt_half');
      expect(cartNotifier.state.items[0].quantity, equals(1));
      expect(cartNotifier.state.items[1].quantity, equals(1));

      // Delete Full completely
      cartNotifier.deleteItem('momos_202|grp_portion:opt_full');
      expect(cartNotifier.state.items.length, equals(1));
      expect(cartNotifier.state.items.first.cartKey, equals('momos_202|grp_portion:opt_half'));
      expect(cartNotifier.state.grandTotal, equals(80.0));
    });
  });

  group('Checkpoint 8B — Cart Screen UI & Interaction Invariants', () {
    test('TEST A: Normal item Maggi ₹50 x 2 quantity and total price calculation', () {
      final maggiItem = CartItem(
        menuItem: normalItem,
        quantity: 2,
        shopId: 'shop_1',
        shopName: 'Rajat Shop',
      );

      expect(maggiItem.hasSelectedOptions, isFalse);
      expect(maggiItem.optionsDescription, isEmpty);
      expect(maggiItem.unitPrice, equals(50));
      expect(maggiItem.formattedUnitPrice, equals('₹50'));
      expect(maggiItem.totalPrice, equals(100.0));
      expect(maggiItem.formattedTotalPrice, equals('₹100'));
      expect(maggiItem.cartKey, equals('maggi_101'));
    });

    test('TEST B & C: Single variant & Two separate variants in cart', () {
      final halfItem = CartItem(
        menuItem: momosItem,
        quantity: 1,
        shopId: 'shop_1',
        shopName: 'Rajat Shop',
        selectedOptions: [halfOpt, friedOpt],
        unitPriceOverride: 100,
      );

      final fullItem = CartItem(
        menuItem: momosItem,
        quantity: 1,
        shopId: 'shop_1',
        shopName: 'Rajat Shop',
        selectedOptions: [fullOpt, friedOpt],
        unitPriceOverride: 160,
      );

      expect(halfItem.hasSelectedOptions, isTrue);
      expect(halfItem.optionsDescription, equals('Half · Fried'));
      expect(halfItem.formattedUnitPrice, equals('₹100'));
      expect(halfItem.formattedTotalPrice, equals('₹100'));

      expect(fullItem.hasSelectedOptions, isTrue);
      expect(fullItem.optionsDescription, equals('Full · Fried'));
      expect(fullItem.formattedUnitPrice, equals('₹160'));
      expect(fullItem.formattedTotalPrice, equals('₹160'));

      expect(halfItem.cartKey, isNot(equals(fullItem.cartKey)));
    });

    test('TEST D, E, F, G, H: Increment, Decrement, Delete targeting cartKey and Grand Total', () {
      // Maggi x 2 (₹100)
      cartNotifier.addItem(normalItem, 'shop_1', 'Rajat Shop');
      cartNotifier.addItem(normalItem, 'shop_1', 'Rajat Shop');

      // Half + Fried x 1 (₹100)
      cartNotifier.addItem(
        momosItem,
        'shop_1',
        'Rajat Shop',
        selectedOptions: [halfOpt, friedOpt],
        unitPrice: 100,
      );

      // Full + Fried x 1 (₹160)
      cartNotifier.addItem(
        momosItem,
        'shop_1',
        'Rajat Shop',
        selectedOptions: [fullOpt, friedOpt],
        unitPrice: 160,
      );

      expect(cartNotifier.state.items.length, equals(3));
      expect(cartNotifier.state.grandTotal, equals(360.0));

      // Increment Half + Fried: 1 -> 2
      final halfKey = CartItem.buildCartKey('momos_202', [halfOpt, friedOpt]);
      cartNotifier.addItem(
        momosItem,
        'shop_1',
        'Rajat Shop',
        selectedOptions: [halfOpt, friedOpt],
        unitPrice: 100,
      );

      final updatedHalf = cartNotifier.state.items.firstWhere((i) => i.cartKey == halfKey);
      expect(updatedHalf.quantity, equals(2));
      expect(updatedHalf.totalPrice, equals(200.0));

      // Grand Total is now 100 + 200 + 160 = ₹460
      expect(cartNotifier.state.grandTotal, equals(460.0));

      // Decrement Full + Fried: 1 -> 0 (removed)
      final fullKey = CartItem.buildCartKey('momos_202', [fullOpt, friedOpt]);
      cartNotifier.removeItem(fullKey, 'shop_1');

      expect(cartNotifier.state.items.length, equals(2));
      expect(cartNotifier.state.grandTotal, equals(300.0)); // Maggi ₹100 + Half ₹200

      // Delete Half + Fried
      cartNotifier.deleteItem(halfKey, 'shop_1');
      expect(cartNotifier.state.items.length, equals(1));
      expect(cartNotifier.state.items.first.cartKey, equals('maggi_101'));
      expect(cartNotifier.state.grandTotal, equals(100.0));
    });
  });
}
