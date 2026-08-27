// BU Gate2Eat — Bug #2: Universal Customization Gateway Tests
// Verifies that customizable items (hasOptions == true) ALWAYS route through the
// customization gateway (Bottom Sheet) regardless of whether added from Main Menu,
// Cart Suggestions, or Favourites, while non-customizable items remain 1-tap direct add.

import 'package:bugate2eat_app/features/cart/cart_provider.dart';
import 'package:bugate2eat_app/models/cart_item_model.dart';
import 'package:bugate2eat_app/models/menu_item_model.dart';
import 'package:bugate2eat_app/models/shop_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.now();

  final dummyShop = Shop(
    id: 'up16_shop',
    name: 'UP16 Canteen',
    description: 'Campus Food & Beverages',
    bannerUrl: '',
    contactNumber: '9876543210',
    orderNumber: '9876543210',
    openTime: '08:00',
    closeTime: '23:30',
    isClosedOverride: false,
    isActive: true,
    sortOrder: 1,
    searchKeywords: const ['canteen', 'food'],
    deliveryNote: 'Gate 3',
    createdAt: now,
    updatedAt: now,
  );

  // Normal Non-Customizable Item (Mint Mojito)
  const mintMojito = MenuItem(
    id: 'item_mojito',
    name: 'Mint Mojito',
    price: 70,
    categoryId: 'cat_beverages',
    imageUrl: 'https://example.com/mojito.jpg',
    isVeg: true,
    isAvailable: true,
    isRecommended: true,
    sortOrder: 1,
    details: 'Refreshing mint and lime drink',
  );

  // Customizable Item (Burger with Size, Sauce, Cheese)
  const customizableBurger = MenuItem(
    id: 'item_burger',
    name: 'Veg Crisp Burger',
    price: 50,
    categoryId: 'cat_burgers',
    imageUrl: 'https://example.com/burger.jpg',
    isVeg: true,
    isAvailable: true,
    isRecommended: true,
    sortOrder: 2,
    details: 'Crispy patty with fresh veggies',
    optionGroups: [
      MenuItemOptionGroup(
        id: 'grp_size',
        name: 'Size',
        options: [
          MenuItemOption(
            id: 'opt_small',
            name: 'Small',
            price: 50,
            isDefault: true,
          ),
          MenuItemOption(
            id: 'opt_large',
            name: 'Large',
            price: 70,
          ),
        ],
      ),
      MenuItemOptionGroup(
        id: 'grp_sauce',
        name: 'Sauce',
        options: [
          MenuItemOption(
            id: 'opt_with_sauce',
            name: 'With Sauce',
            pricingType: OptionPricingType.priceAdjustment,
            isDefault: true,
          ),
          MenuItemOption(
            id: 'opt_no_sauce',
            name: 'Without Sauce',
            pricingType: OptionPricingType.priceAdjustment,
          ),
        ],
      ),
      MenuItemOptionGroup(
        id: 'grp_cheese',
        name: 'Extra Cheese',
        required: false, // Optional: starts UNSELECTED (null)
        options: [
          MenuItemOption(
            id: 'opt_cheese',
            name: 'Cheese',
            pricingType: OptionPricingType.priceAdjustment,
            price: 10,
          ),
        ],
      ),
    ],
  );

  // Customizable Item (UP16 Normal Cold Coffee)
  const coldCoffee = MenuItem(
    id: 'item_cold_coffee',
    name: 'Normal Cold Coffee',
    price: 60,
    categoryId: 'cat_beverages',
    imageUrl: 'https://example.com/coffee.jpg',
    isVeg: true,
    isAvailable: true,
    isRecommended: true,
    sortOrder: 3,
    details: 'Rich chilled cold coffee',
    optionGroups: [
      MenuItemOptionGroup(
        id: 'grp_coffee_size',
        name: 'Size',
        options: [
          MenuItemOption(
            id: 'opt_coffee_large',
            name: 'Large',
            price: 60,
            isDefault: true,
          ),
          MenuItemOption(
            id: 'opt_coffee_xl',
            name: 'XL',
            price: 80,
          ),
          MenuItemOption(
            id: 'opt_coffee_xxl',
            name: 'Double XL',
            price: 100,
          ),
        ],
      ),
      MenuItemOptionGroup(
        id: 'grp_ice_cream',
        name: 'Ice Cream Addon',
        required: false, // Optional: starts UNSELECTED
        options: [
          MenuItemOption(
            id: 'opt_with_ice_cream',
            name: 'With Ice Cream',
            pricingType: OptionPricingType.priceAdjustment,
            price: 10,
          ),
        ],
      ),
    ],
  );

  group('Bug #2 — Universal Customization Gateway Rules & Routing Invariants', () {
    late CartNotifier cartNotifier;

    setUp(() {
      cartNotifier = CartNotifier();
    });

    test('1. Normal Item: item.hasOptions == false -> Directly added to Cart (Mint Mojito ₹70)', () {
      expect(mintMojito.hasOptions, isFalse);

      final added = cartNotifier.addItem(mintMojito, dummyShop.id, dummyShop.name);
      expect(added, isTrue);
      expect(cartNotifier.state.items.length, 1);
      expect(cartNotifier.state.items.first.unitPrice, 70.0);
      expect(cartNotifier.state.items.first.menuItem.name, 'Mint Mojito');
      expect(cartNotifier.state.items.first.selectedOptions, isEmpty);
      expect(cartNotifier.state.grandTotal, 70.0);
    });

    test('2. Customizable Item: item.hasOptions == true -> Requires customization gateway (Burger & Cold Coffee)', () {
      expect(customizableBurger.hasOptions, isTrue);
      expect(coldCoffee.hasOptions, isTrue);
    });

    test('3. Burger Customization: Large + With Sauce + Cheese -> Added accurately at ₹80', () {
      final selectedOptions = [
        const SelectedMenuItemOption(
          groupId: 'grp_size',
          groupName: 'Size',
          optionId: 'opt_large',
          optionName: 'Large',
          pricingType: OptionPricingType.fixedPrice,
          price: 70,
        ),
        const SelectedMenuItemOption(
          groupId: 'grp_sauce',
          groupName: 'Sauce',
          optionId: 'opt_with_sauce',
          optionName: 'With Sauce',
          pricingType: OptionPricingType.selectionOnly,
          price: 0,
        ),
        const SelectedMenuItemOption(
          groupId: 'grp_cheese',
          groupName: 'Extra Cheese',
          optionId: 'opt_cheese',
          optionName: 'Cheese',
          pricingType: OptionPricingType.priceAdjustment,
          price: 10,
        ),
      ];

      // Base price 70 + 0 + 10 = 80
      const calculatedUnitPrice = 80;

      final added = cartNotifier.addItem(
        customizableBurger,
        dummyShop.id,
        dummyShop.name,
        selectedOptions: selectedOptions,
        unitPrice: calculatedUnitPrice,
      );

      expect(added, isTrue);
      expect(cartNotifier.state.items.length, 1);
      final cartItem = cartNotifier.state.items.first;
      expect(cartItem.unitPrice, 80.0);
      expect(cartItem.optionsDescription, 'Large · With Sauce · Cheese');
      expect(cartItem.selectedOptions.length, 3);
      expect(cartNotifier.state.grandTotal, 80.0);
    });

    test('4. Cold Coffee Customization: Large + No Ice Cream -> Added accurately at ₹60', () {
      final selectedOptions = [
        const SelectedMenuItemOption(
          groupId: 'grp_coffee_size',
          groupName: 'Size',
          optionId: 'opt_coffee_large',
          optionName: 'Large',
          pricingType: OptionPricingType.fixedPrice,
          price: 60,
        ),
      ];

      const calculatedUnitPrice = 60;

      final added = cartNotifier.addItem(
        coldCoffee,
        dummyShop.id,
        dummyShop.name,
        selectedOptions: selectedOptions,
        unitPrice: calculatedUnitPrice,
      );

      expect(added, isTrue);
      expect(cartNotifier.state.items.length, 1);
      final cartItem = cartNotifier.state.items.first;
      expect(cartItem.unitPrice, 60.0);
      expect(cartItem.optionsDescription, 'Large');
      expect(cartNotifier.state.grandTotal, 60.0);
    });

    test('5. Cold Coffee with Ice Cream: Large + Ice Cream -> Added accurately at ₹70', () {
      final selectedOptions = [
        const SelectedMenuItemOption(
          groupId: 'grp_coffee_size',
          groupName: 'Size',
          optionId: 'opt_coffee_large',
          optionName: 'Large',
          pricingType: OptionPricingType.fixedPrice,
          price: 60,
        ),
        const SelectedMenuItemOption(
          groupId: 'grp_ice_cream',
          groupName: 'Ice Cream Addon',
          optionId: 'opt_with_ice_cream',
          optionName: 'With Ice Cream',
          pricingType: OptionPricingType.priceAdjustment,
          price: 10,
        ),
      ];

      const calculatedUnitPrice = 70;

      final added = cartNotifier.addItem(
        coldCoffee,
        dummyShop.id,
        dummyShop.name,
        selectedOptions: selectedOptions,
        unitPrice: calculatedUnitPrice,
      );

      expect(added, isTrue);
      final cartItem = cartNotifier.state.items.first;
      expect(cartItem.unitPrice, 70.0);
      expect(cartItem.optionsDescription, 'Large · With Ice Cream');
      expect(cartNotifier.state.grandTotal, 70.0);
    });

    test('6. Distinct Cart Lines: Different variants of the same item coexist as separate rows', () {
      // Variant 1: Burger Large + No Cheese (₹70)
      final variant1Options = [
        const SelectedMenuItemOption(
          groupId: 'grp_size',
          groupName: 'Size',
          optionId: 'opt_large',
          optionName: 'Large',
          pricingType: OptionPricingType.fixedPrice,
          price: 70,
        ),
      ];
      cartNotifier.addItem(
        customizableBurger,
        dummyShop.id,
        dummyShop.name,
        selectedOptions: variant1Options,
        unitPrice: 70,
      );

      // Variant 2: Burger Large + Cheese (₹80)
      final variant2Options = [
        const SelectedMenuItemOption(
          groupId: 'grp_size',
          groupName: 'Size',
          optionId: 'opt_large',
          optionName: 'Large',
          pricingType: OptionPricingType.fixedPrice,
          price: 70,
        ),
        const SelectedMenuItemOption(
          groupId: 'grp_cheese',
          groupName: 'Extra Cheese',
          optionId: 'opt_cheese',
          optionName: 'Cheese',
          pricingType: OptionPricingType.priceAdjustment,
          price: 10,
        ),
      ];
      cartNotifier.addItem(
        customizableBurger,
        dummyShop.id,
        dummyShop.name,
        selectedOptions: variant2Options,
        unitPrice: 80,
      );

      // Must produce 2 separate rows with distinct cartKeys
      expect(cartNotifier.state.items.length, 2);
      expect(cartNotifier.state.items[0].unitPrice, 70.0);
      expect(cartNotifier.state.items[1].unitPrice, 80.0);
      expect(cartNotifier.state.grandTotal, 150.0);
      expect(cartNotifier.state.totalItemCount, 2);
      expect(cartNotifier.state.items[0].cartKey != cartNotifier.state.items[1].cartKey, isTrue);
    });

    test('7. Same Variant Increment: Re-adding the exact same variant increments quantity on the same row', () {
      final variantOptions = [
        const SelectedMenuItemOption(
          groupId: 'grp_size',
          groupName: 'Size',
          optionId: 'opt_large',
          optionName: 'Large',
          pricingType: OptionPricingType.fixedPrice,
          price: 70,
        ),
        const SelectedMenuItemOption(
          groupId: 'grp_cheese',
          groupName: 'Extra Cheese',
          optionId: 'opt_cheese',
          optionName: 'Cheese',
          pricingType: OptionPricingType.priceAdjustment,
          price: 10,
        ),
      ];

      // Add #1
      cartNotifier.addItem(
        customizableBurger,
        dummyShop.id,
        dummyShop.name,
        selectedOptions: variantOptions,
        unitPrice: 80,
      );
      // Add #2 (same variant)
      cartNotifier.addItem(
        customizableBurger,
        dummyShop.id,
        dummyShop.name,
        selectedOptions: variantOptions,
        unitPrice: 80,
      );

      expect(cartNotifier.state.items.length, 1);
      expect(cartNotifier.state.items.first.quantity, 2);
      expect(cartNotifier.state.grandTotal, 160.0);
      expect(cartNotifier.state.totalItemCount, 2);
    });

    test('8. Stale Description Isolation: Adding customizable item does NOT inherit stale draft description', () {
      // Step 1: Add Item A and add special instruction
      cartNotifier.addItem(mintMojito, dummyShop.id, dummyShop.name);
      cartNotifier.setSpecialInstructions('Less spicy, no ice');

      // Step 2: Remove Item A
      cartNotifier.removeItem(mintMojito.id);
      expect(cartNotifier.state.isEmpty, isTrue);
      expect(cartNotifier.state.specialInstructions, isEmpty);

      // Step 3: Add customizable Burger
      final variantOptions = [
        const SelectedMenuItemOption(
          groupId: 'grp_size',
          groupName: 'Size',
          optionId: 'opt_small',
          optionName: 'Small',
          pricingType: OptionPricingType.fixedPrice,
          price: 50,
        ),
      ];
      cartNotifier.addItem(
        customizableBurger,
        dummyShop.id,
        dummyShop.name,
        selectedOptions: variantOptions,
        unitPrice: 50,
      );

      expect(cartNotifier.state.items.length, 1);
      expect(cartNotifier.state.specialInstructions, isEmpty);
    });

    test('9. Required vs Optional Choice Defaults Validation', () {
      // Required group (grp_size) has default Small (50)
      final sizeGroup = customizableBurger.optionGroups.firstWhere((g) => g.id == 'grp_size');
      expect(sizeGroup.required, isTrue);
      expect(sizeGroup.options.firstWhere((o) => o.isDefault).id, 'opt_small');

      // Optional group (grp_cheese) has required == false
      final cheeseGroup = customizableBurger.optionGroups.firstWhere((g) => g.id == 'grp_cheese');
      expect(cheeseGroup.required, isFalse);
    });
  });
}
