// BU Gate2Eat — Checkpoint 11.2 & 12.3 Universal Option Architecture Unit Tests
// Verifies Group-Level Option Types (Fixed, Choice), optional Choice, and backward-compatible deserialization.

import 'package:bugate2eat_app/models/cart_item_model.dart';
import 'package:bugate2eat_app/models/menu_item_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Checkpoint 11.2 & 12.3: Universal Option Architecture', () {
    // ── 1. FIXED GROUP ─────────────────────────────────────────────────────────
    test('1. Fixed group has groupType=fixed, required=true by default, and fixedPrice options', () {
      const sizeGroup = MenuItemOptionGroup(
        id: 'grp_size',
        name: 'Size',
        groupType: OptionGroupType.fixed,
        required: true,
        options: [
          MenuItemOption(id: 'opt_small', name: 'Small', price: 40, pricingType: OptionPricingType.fixedPrice, isDefault: true),
          MenuItemOption(id: 'opt_large', name: 'Large', price: 70, pricingType: OptionPricingType.fixedPrice),
        ],
      );

      expect(sizeGroup.groupType, OptionGroupType.fixed);
      expect(sizeGroup.required, isTrue);
      expect(sizeGroup.options.length, 2);
      expect(sizeGroup.options[0].price, 40);
      expect(sizeGroup.options[1].price, 70);
      expect(sizeGroup.options.every((o) => o.pricingType == OptionPricingType.fixedPrice), isTrue);
    });

    // ── 2. CHOICE GROUP (REQUIRED) ─────────────────────────────────────────────
    test('2. Choice group with required=true has zero or adjusted price options', () {
      const choiceGroup = MenuItemOptionGroup(
        id: 'grp_sauce',
        name: 'Sauce',
        groupType: OptionGroupType.choice,
        required: true,
        options: [
          MenuItemOption(id: 'opt_with', name: 'With Sauce', price: 0, pricingType: OptionPricingType.selectionOnly, isDefault: true),
          MenuItemOption(id: 'opt_without', name: 'Without Sauce', price: 0, pricingType: OptionPricingType.selectionOnly),
        ],
      );

      expect(choiceGroup.groupType, OptionGroupType.choice);
      expect(choiceGroup.required, isTrue);
      expect(choiceGroup.options.every((o) => o.price == 0), isTrue);
      expect(choiceGroup.options.every((o) => o.pricingType == OptionPricingType.selectionOnly), isTrue);
    });

    // ── 3. OPTIONAL CHOICE GROUP (REPLACING EXTRA) ─────────────────────────────
    test('3. Optional Choice group has groupType=choice, required=false, and surcharge options', () {
      const optionalGroup = MenuItemOptionGroup(
        id: 'grp_extras',
        name: 'Extras',
        groupType: OptionGroupType.choice,
        required: false,
        options: [
          MenuItemOption(id: 'opt_cheese', name: 'Cheese', price: 10, pricingType: OptionPricingType.priceAdjustment),
          MenuItemOption(id: 'opt_patty', name: 'Extra Patty', price: 30, pricingType: OptionPricingType.priceAdjustment),
        ],
      );

      expect(optionalGroup.groupType, OptionGroupType.choice);
      expect(optionalGroup.required, isFalse);
      expect(optionalGroup.options[0].price, 10);
      expect(optionalGroup.options[1].price, 30);
      expect(optionalGroup.options.every((o) => o.pricingType == OptionPricingType.priceAdjustment), isTrue);
    });

    // ── 4. LEGACY INFERENCE ───────────────────────────────────────────────────
    test('4. Legacy group inference correctly categorizes groups without explicit groupType', () {
      // Legacy fixed
      final legacyFixed = MenuItemOptionGroup.fromMap({
        'id': 'grp_1',
        'name': 'Portion',
        'options': [
          {'id': 'o1', 'name': 'Half', 'price': 80, 'pricingType': 'fixedPrice'},
          {'id': 'o2', 'name': 'Full', 'price': 140, 'pricingType': 'fixedPrice'},
        ],
      });
      expect(legacyFixed.groupType, OptionGroupType.fixed);
      expect(legacyFixed.required, isTrue);

      // Legacy extra parses as Choice
      final legacyExtra = MenuItemOptionGroup.fromMap({
        'id': 'grp_2',
        'name': 'Add-ons',
        'options': [
          {'id': 'o1', 'name': 'Extra Cheese', 'price': 20, 'pricingType': 'priceAdjustment'},
        ],
      });
      expect(legacyExtra.groupType, OptionGroupType.choice);

      // Legacy choice
      final legacyChoice = MenuItemOptionGroup.fromMap({
        'id': 'grp_3',
        'name': 'Preparation',
        'options': [
          {'id': 'o1', 'name': 'Dry', 'pricingType': 'selectionOnly'},
          {'id': 'o2', 'name': 'Gravy', 'pricingType': 'selectionOnly'},
        ],
      });
      expect(legacyChoice.groupType, OptionGroupType.choice);
      expect(legacyChoice.required, isTrue);
    });

    // ── 5. EXPLICIT GROUP TYPE DESERIALIZATION ────────────────────────────────
    test('5. Deserialization correctly parses explicit groupType and legacy "extra"', () {
      final group = MenuItemOptionGroup.fromMap({
        'id': 'grp_test',
        'name': 'Burger Extras',
        'groupType': 'extra',
        'required': false,
        'options': [
          {'id': 'opt_c', 'name': 'Cheese', 'price': 10, 'pricingType': 'priceAdjustment'},
        ],
      });

      expect(group.groupType, OptionGroupType.choice);
      expect(group.required, isFalse);
    });

    // ── 6. CART KEY DISTINCTION: OPTIONAL CHOICE SELECTED VS UNSELECTED ───────
    test('6. Burger with Cheese vs Burger without Cheese produce DISTINCT cart keys', () {
      const burgerId = 'burger_classic';

      final sizeLarge = SelectedMenuItemOption(
        groupId: 'grp_size',
        groupName: 'Size',
        optionId: 'opt_large',
        optionName: 'Large',
        pricingType: OptionPricingType.fixedPrice,
        price: 70,
      );

      final cheeseExtra = SelectedMenuItemOption(
        groupId: 'grp_extra',
        groupName: 'Extras',
        optionId: 'opt_cheese',
        optionName: 'Cheese',
        pricingType: OptionPricingType.priceAdjustment,
        price: 10,
      );

      final keyWithCheese = CartItem.buildCartKey(burgerId, [sizeLarge, cheeseExtra]);
      final keyWithoutCheese = CartItem.buildCartKey(burgerId, [sizeLarge]);

      expect(keyWithCheese, 'burger_classic|grp_extra:opt_cheese|grp_size:opt_large');
      expect(keyWithoutCheese, 'burger_classic|grp_size:opt_large');
      expect(keyWithCheese, isNot(equals(keyWithoutCheese)));
    });

    // ── 7. BURGER COEXISTENCE IN CART ─────────────────────────────────────────
    test('7. Burger Large + Cheese and Burger Large + No Cheese coexist as distinct lines', () {
      const burger = MenuItem(
        id: 'burger_classic',
        name: 'Burger',
        details: 'Tasty burger',
        price: 70,
        imageUrl: '',
        categoryId: 'burgers',
        isVeg: true,
        isAvailable: true,
        isRecommended: true,
        sortOrder: 1,
        optionGroups: [
          MenuItemOptionGroup(
            id: 'grp_size',
            name: 'Size',
            groupType: OptionGroupType.fixed,
            options: [
              MenuItemOption(id: 'opt_small', name: 'Small', price: 40, pricingType: OptionPricingType.fixedPrice),
              MenuItemOption(id: 'opt_large', name: 'Large', price: 70, pricingType: OptionPricingType.fixedPrice),
            ],
          ),
          MenuItemOptionGroup(
            id: 'grp_sauce',
            name: 'Sauce',
            groupType: OptionGroupType.choice,
            options: [
              MenuItemOption(id: 'opt_with', name: 'With Sauce', price: 0, pricingType: OptionPricingType.selectionOnly),
              MenuItemOption(id: 'opt_without', name: 'Without Sauce', price: 0, pricingType: OptionPricingType.selectionOnly),
            ],
          ),
          MenuItemOptionGroup(
            id: 'grp_extra',
            name: 'Extras',
            groupType: OptionGroupType.choice,
            required: false,
            options: [
              MenuItemOption(id: 'opt_cheese', name: 'Cheese', price: 10, pricingType: OptionPricingType.priceAdjustment),
            ],
          ),
        ],
      );

      final sizeLarge = SelectedMenuItemOption(
        groupId: 'grp_size',
        groupName: 'Size',
        optionId: 'opt_large',
        optionName: 'Large',
        pricingType: OptionPricingType.fixedPrice,
        price: 70,
      );

      final sauceWith = SelectedMenuItemOption(
        groupId: 'grp_sauce',
        groupName: 'Sauce',
        optionId: 'opt_with',
        optionName: 'With Sauce',
        pricingType: OptionPricingType.selectionOnly,
        price: 0,
      );

      final extraCheese = SelectedMenuItemOption(
        groupId: 'grp_extra',
        groupName: 'Extras',
        optionId: 'opt_cheese',
        optionName: 'Cheese',
        pricingType: OptionPricingType.priceAdjustment,
        price: 10,
      );

      // Cart line 1: Large + With Sauce + Cheese (unitPrice = 80, qty = 1)
      final itemWithCheese = CartItem(
        menuItem: burger,
        quantity: 1,
        shopId: 'shop_1',
        shopName: 'Burger Queen',
        selectedOptions: [sizeLarge, sauceWith, extraCheese],
        unitPriceOverride: 80,
      );

      // Cart line 2: Large + With Sauce + No Cheese (unitPrice = 70, qty = 1)
      final itemNoCheese = CartItem(
        menuItem: burger,
        quantity: 1,
        shopId: 'shop_1',
        shopName: 'Burger Queen',
        selectedOptions: [sizeLarge, sauceWith],
        unitPriceOverride: 70,
      );

      expect(itemWithCheese.unitPrice, 80);
      expect(itemWithCheese.totalPrice, 80.0);
      expect(itemWithCheese.optionsDescription, 'Large · With Sauce · Cheese');

      expect(itemNoCheese.unitPrice, 70);
      expect(itemNoCheese.totalPrice, 70.0);
      expect(itemNoCheese.optionsDescription, 'Large · With Sauce');

      expect(itemWithCheese.cartKey, isNot(equals(itemNoCheese.cartKey)));
    });

    // ── 8. PRICING & STARTING PRICE CALCULATION ───────────────────────────────
    test('8. Item starting price accurately calculates lowest configuration across fixed and choice', () {
      const burger = MenuItem(
        id: 'burger_1',
        name: 'Burger',
        details: 'Tasty burger',
        price: 0,
        imageUrl: '',
        categoryId: 'burgers',
        isVeg: true,
        isAvailable: true,
        isRecommended: false,
        sortOrder: 1,
        optionGroups: [
          MenuItemOptionGroup(
            id: 'grp_size',
            name: 'Size',
            groupType: OptionGroupType.fixed,
            options: [
              MenuItemOption(id: 'opt_s', name: 'Small', price: 40, pricingType: OptionPricingType.fixedPrice),
              MenuItemOption(id: 'opt_l', name: 'Large', price: 70, pricingType: OptionPricingType.fixedPrice),
            ],
          ),
          MenuItemOptionGroup(
            id: 'grp_sauce',
            name: 'Sauce',
            groupType: OptionGroupType.choice,
            options: [
              MenuItemOption(id: 'opt_w', name: 'With Sauce', price: 0, pricingType: OptionPricingType.selectionOnly),
            ],
          ),
          MenuItemOptionGroup(
            id: 'grp_extras',
            name: 'Extras',
            groupType: OptionGroupType.choice,
            required: false,
            options: [
              MenuItemOption(id: 'opt_c', name: 'Cheese', price: 10, pricingType: OptionPricingType.priceAdjustment),
            ],
          ),
        ],
      );

      // Starting price must be Small (₹40), since Sauce is ₹0 and Extras is optional (₹0)
      expect(burger.startingPrice, 40);
      expect(burger.formattedStartingPrice, '₹40');
    });

    // ── 9. NORMAL ITEMS REMAIN COMPLETELY UNCHANGED ───────────────────────────
    test('9. Normal simple items without option groups behave exactly as before', () {
      const normalItem = MenuItem(
        id: 'coke_can',
        name: 'Coca Cola Can',
        details: 'Chilled 300ml',
        price: 40,
        imageUrl: 'https://example.com/coke.jpg',
        categoryId: 'beverages',
        isVeg: true,
        isAvailable: true,
        isRecommended: true,
        sortOrder: 5,
      );

      expect(normalItem.hasOptions, isFalse);
      expect(normalItem.startingPrice, 40);
      expect(normalItem.formattedStartingPrice, '₹40');

      final cartItem = CartItem(
        menuItem: normalItem,
        quantity: 2,
        shopId: 'shop_1',
        shopName: 'Snack Bar',
      );

      expect(cartItem.cartKey, 'coke_can');
      expect(cartItem.unitPrice, 40);
      expect(cartItem.totalPrice, 80.0);
      expect(cartItem.hasSelectedOptions, isFalse);

      final firestoreMap = normalItem.toFirestore();
      expect(firestoreMap.containsKey('optionGroups'), isFalse);
    });

    // ── 10. SERIALIZATION ROUNDTRIP ───────────────────────────────────────────
    test('10. MenuItemOptionGroup serializes and deserializes cleanly with groupType', () {
      const originalGroup = MenuItemOptionGroup(
        id: 'grp_flavours',
        name: 'Flavour',
        groupType: OptionGroupType.choice,
        required: true,
        options: [
          MenuItemOption(id: 'opt_vanilla', name: 'Vanilla', price: 0, pricingType: OptionPricingType.selectionOnly),
          MenuItemOption(id: 'opt_chocolate', name: 'Chocolate', price: 0, pricingType: OptionPricingType.selectionOnly),
        ],
      );

      final map = originalGroup.toMap();
      expect(map['groupType'], 'choice');
      expect(map['required'], isTrue);

      final restoredGroup = MenuItemOptionGroup.fromMap(map);
      expect(restoredGroup.id, originalGroup.id);
      expect(restoredGroup.name, originalGroup.name);
      expect(restoredGroup.groupType, OptionGroupType.choice);
      expect(restoredGroup.required, isTrue);
      expect(restoredGroup.options.length, 2);
      expect(restoredGroup.options[0].name, 'Vanilla');
      expect(restoredGroup.options[1].name, 'Chocolate');
    });
  });
}
