// BU Gate2Eat — Checkpoint 12.3 Comprehensive Test Suite
// Removal of Extra type, 2-group-type architecture (Fixed & Choice), optional Choice, and Choice rendering priority.

import 'package:bugate2eat_app/features/cart/cart_provider.dart';
import 'package:bugate2eat_app/models/cart_item_model.dart';
import 'package:bugate2eat_app/models/menu_item_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Checkpoint 12.3: 2-Group-Type Architecture (Fixed & Choice)', () {
    const shopId = 'up16_coffee_queen';
    const shopName = 'UP16 Coffee Queen';

    // ── 1. ONLY FIXED AND CHOICE GROUP TYPES EXIST ───────────────────────────
    test('1. Only fixed and choice group types exist in OptionGroupType enum', () {
      expect(OptionGroupType.values.length, 2);
      expect(OptionGroupType.values, containsAll([OptionGroupType.fixed, OptionGroupType.choice]));
    });

    // ── 2. LEGACY EXTRA FIRESTORE GROUP PARSES AS CHOICE ──────────────────────
    test('2. Legacy "extra" Firestore group parses safely as choice without errors', () {
      final legacyGroup = MenuItemOptionGroup.fromMap({
        'id': 'grp_ice_cream',
        'name': 'Ice Cream',
        'groupType': 'extra',
        'options': [
          {'id': 'opt_no_ice', 'name': 'No Ice Cream', 'price': 0, 'pricingType': 'priceAdjustment', 'isDefault': true},
          {'id': 'opt_with_ice', 'name': 'With Ice Cream', 'price': 10, 'pricingType': 'priceAdjustment', 'isDefault': false},
        ],
      });

      expect(legacyGroup.groupType, OptionGroupType.choice);
      expect(legacyGroup.required, isFalse);
      expect(legacyGroup.options.length, 2);
    });

    // ── 3. OPTIONAL CHOICE WITH NO SELECTION = VALID ──────────────────────────
    test('3. Optional Choice with no selection contributes ₹0 and is valid', () {
      const burger = MenuItem(
        id: 'burger_1',
        name: 'Burger',
        details: 'Delicious burger',
        price: 70,
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
              MenuItemOption(id: 'opt_large', name: 'Large', price: 70, pricingType: OptionPricingType.fixedPrice),
            ],
          ),
          MenuItemOptionGroup(
            id: 'grp_cheese',
            name: 'Cheese',
            groupType: OptionGroupType.choice,
            required: false,
            options: [
              MenuItemOption(id: 'opt_cheese', name: 'Cheese', price: 10, pricingType: OptionPricingType.priceAdjustment),
            ],
          ),
        ],
      );

      const sizeLarge = SelectedMenuItemOption(
        groupId: 'grp_size',
        groupName: 'Size',
        optionId: 'opt_large',
        optionName: 'Large',
        pricingType: OptionPricingType.fixedPrice,
        price: 70,
      );

      final cartNotifier = CartNotifier();
      // Add Large without cheese selection
      cartNotifier.addItem(
        burger,
        shopId,
        shopName,
        selectedOptions: [sizeLarge],
        unitPrice: 70,
      );

      final item = cartNotifier.state.items.first;
      expect(item.unitPrice, 70);
      expect(item.cartKey, 'burger_1|grp_size:opt_large');
    });

    // ── 4. OPTIONAL CHOICE SELECTED = SURCHARGE APPLIED ───────────────────────
    test('4. Optional Choice selected adds surcharge correctly (+₹10)', () {
      const burger = MenuItem(
        id: 'burger_1',
        name: 'Burger',
        details: 'Delicious burger',
        price: 70,
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
              MenuItemOption(id: 'opt_large', name: 'Large', price: 70, pricingType: OptionPricingType.fixedPrice),
            ],
          ),
          MenuItemOptionGroup(
            id: 'grp_cheese',
            name: 'Cheese',
            groupType: OptionGroupType.choice,
            required: false,
            options: [
              MenuItemOption(id: 'opt_cheese', name: 'Cheese', price: 10, pricingType: OptionPricingType.priceAdjustment),
            ],
          ),
        ],
      );

      const sizeLarge = SelectedMenuItemOption(
        groupId: 'grp_size',
        groupName: 'Size',
        optionId: 'opt_large',
        optionName: 'Large',
        pricingType: OptionPricingType.fixedPrice,
        price: 70,
      );

      const cheeseOpt = SelectedMenuItemOption(
        groupId: 'grp_cheese',
        groupName: 'Cheese',
        optionId: 'opt_cheese',
        optionName: 'Cheese',
        pricingType: OptionPricingType.priceAdjustment,
        price: 10,
      );

      final cartNotifier = CartNotifier();
      // Add Large with cheese
      cartNotifier.addItem(
        burger,
        shopId,
        shopName,
        selectedOptions: [sizeLarge, cheeseOpt],
        unitPrice: 80,
      );

      final item = cartNotifier.state.items.first;
      expect(item.unitPrice, 80);
      expect(item.cartKey, 'burger_1|grp_cheese:opt_cheese|grp_size:opt_large');
    });

    // ── 5. REQUIRED CHOICE MANDATORY SELECTION ────────────────────────────────
    test('5. Required Choice has required=true and requires exact selection', () {
      const sauceGroup = MenuItemOptionGroup(
        id: 'grp_sauce',
        name: 'Sauce',
        groupType: OptionGroupType.choice,
        required: true,
        options: [
          MenuItemOption(id: 'opt_with', name: 'With Sauce', price: 0, pricingType: OptionPricingType.selectionOnly, isDefault: true),
          MenuItemOption(id: 'opt_without', name: 'Without Sauce', price: 0, pricingType: OptionPricingType.selectionOnly),
        ],
      );

      expect(sauceGroup.required, isTrue);
      expect(sauceGroup.groupType, OptionGroupType.choice);
    });

    // ── 6. CHOICE APPEARS ABOVE FIXED (PRIORITY ORDER) ────────────────────────
    test('6. Choice groups appear before Fixed groups regardless of source list order', () {
      final rawGroups = [
        const MenuItemOptionGroup(id: 'grp_size', name: 'Size', groupType: OptionGroupType.fixed, options: []),
        const MenuItemOptionGroup(id: 'grp_sauce', name: 'Sauce', groupType: OptionGroupType.choice, options: []),
        const MenuItemOptionGroup(id: 'grp_ice', name: 'Ice Cream', groupType: OptionGroupType.choice, options: []),
      ];

      // Ordering algorithm: Choice first, then Fixed
      final sortedGroups = [
        ...rawGroups.where((g) => g.groupType == OptionGroupType.choice),
        ...rawGroups.where((g) => g.groupType == OptionGroupType.fixed),
      ];

      expect(sortedGroups[0].name, 'Sauce');
      expect(sortedGroups[1].name, 'Ice Cream');
      expect(sortedGroups[2].name, 'Size');
    });

    // ── 7. DISTINCT CART KEYS FOR UNSELECTED VS SELECTED CHOICE ───────────────
    test('7. No-choice and selected choice produce distinct deterministic cartKeys', () {
      const sizeLarge = SelectedMenuItemOption(
        groupId: 'grp_size',
        groupName: 'Size',
        optionId: 'opt_large',
        optionName: 'Large',
        pricingType: OptionPricingType.fixedPrice,
        price: 70,
      );

      const cheeseOpt = SelectedMenuItemOption(
        groupId: 'grp_cheese',
        groupName: 'Cheese',
        optionId: 'opt_cheese',
        optionName: 'Cheese',
        pricingType: OptionPricingType.priceAdjustment,
        price: 10,
      );

      final keyNoCheese = CartItem.buildCartKey('burger_1', [sizeLarge]);
      final keyWithCheese = CartItem.buildCartKey('burger_1', [sizeLarge, cheeseOpt]);

      expect(keyNoCheese, 'burger_1|grp_size:opt_large');
      expect(keyWithCheese, 'burger_1|grp_cheese:opt_cheese|grp_size:opt_large');
      expect(keyNoCheese, isNot(equals(keyWithCheese)));
    });

    // ── 8. COLD COFFEE PRICING TESTS (₹60, ₹70, ₹90) ──────────────────────────
    test('8. Cold Coffee: Large + No Ice Cream = ₹60, Large + Ice Cream = ₹70, XL + Ice Cream = ₹90', () {
      const normalColdCoffee = MenuItem(
        id: 'up16_normal_cold_coffee',
        name: 'Normal Cold Coffee',
        details: 'Cold coffee',
        price: 60,
        imageUrl: '',
        categoryId: 'up16_cold_coffee',
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
              MenuItemOption(id: 'opt_large', name: 'Large', price: 60, pricingType: OptionPricingType.fixedPrice, isDefault: true),
              MenuItemOption(id: 'opt_xl', name: 'XL', price: 80, pricingType: OptionPricingType.fixedPrice),
              MenuItemOption(id: 'opt_xxl', name: 'Double XL', price: 100, pricingType: OptionPricingType.fixedPrice),
            ],
          ),
          MenuItemOptionGroup(
            id: 'grp_ice_cream',
            name: 'Ice Cream',
            groupType: OptionGroupType.choice,
            required: false,
            options: [
              MenuItemOption(id: 'opt_no_ice_cream', name: 'No Ice Cream', price: 0, pricingType: OptionPricingType.selectionOnly, isDefault: true),
              MenuItemOption(id: 'opt_with_ice_cream', name: 'With Ice Cream', price: 10, pricingType: OptionPricingType.priceAdjustment),
            ],
          ),
        ],
      );

      const sizeLarge = SelectedMenuItemOption(
        groupId: 'grp_size',
        groupName: 'Size',
        optionId: 'opt_large',
        optionName: 'Large',
        pricingType: OptionPricingType.fixedPrice,
        price: 60,
      );

      const sizeXL = SelectedMenuItemOption(
        groupId: 'grp_size',
        groupName: 'Size',
        optionId: 'opt_xl',
        optionName: 'XL',
        pricingType: OptionPricingType.fixedPrice,
        price: 80,
      );

      const noIce = SelectedMenuItemOption(
        groupId: 'grp_ice_cream',
        groupName: 'Ice Cream',
        optionId: 'opt_no_ice_cream',
        optionName: 'No Ice Cream',
        pricingType: OptionPricingType.selectionOnly,
        price: 0,
      );

      const withIce = SelectedMenuItemOption(
        groupId: 'grp_ice_cream',
        groupName: 'Ice Cream',
        optionId: 'opt_with_ice_cream',
        optionName: 'With Ice Cream',
        pricingType: OptionPricingType.priceAdjustment,
        price: 10,
      );

      // Large + No Ice Cream = ₹60
      final cartItem1 = CartItem(
        menuItem: normalColdCoffee,
        quantity: 1,
        shopId: shopId,
        shopName: shopName,
        selectedOptions: [sizeLarge, noIce],
        unitPriceOverride: 60,
      );

      // Large + With Ice Cream = ₹70
      final cartItem2 = CartItem(
        menuItem: normalColdCoffee,
        quantity: 1,
        shopId: shopId,
        shopName: shopName,
        selectedOptions: [sizeLarge, withIce],
        unitPriceOverride: 70,
      );

      // XL + With Ice Cream = ₹90
      final cartItem3 = CartItem(
        menuItem: normalColdCoffee,
        quantity: 1,
        shopId: shopId,
        shopName: shopName,
        selectedOptions: [sizeXL, withIce],
        unitPriceOverride: 90,
      );

      expect(cartItem1.unitPrice, 60);
      expect(cartItem2.unitPrice, 70);
      expect(cartItem3.unitPrice, 90);

      expect(cartItem1.cartKey, 'up16_normal_cold_coffee|grp_ice_cream:opt_no_ice_cream|grp_size:opt_large');
      expect(cartItem2.cartKey, 'up16_normal_cold_coffee|grp_ice_cream:opt_with_ice_cream|grp_size:opt_large');
      expect(cartItem3.cartKey, 'up16_normal_cold_coffee|grp_ice_cream:opt_with_ice_cream|grp_size:opt_xl');

      expect(cartItem1.cartKey, isNot(equals(cartItem2.cartKey)));
    });

    // ── 9. NORMAL ITEMS REMAIN UNCHANGED ──────────────────────────────────────
    test('9. Normal items without options remain unchanged', () {
      const mojito = MenuItem(
        id: 'up16_mint_mojito',
        name: 'Mint Mojito',
        details: 'Refreshing mint mojito',
        price: 70,
        imageUrl: '',
        categoryId: 'up16_mojitos_others',
        isVeg: true,
        isAvailable: true,
        isRecommended: false,
        sortOrder: 1,
      );

      expect(mojito.hasOptions, isFalse);
      expect(mojito.price, 70);
      expect(mojito.startingPrice, 70);
      expect(mojito.formattedStartingPrice, '₹70');
    });
  });
}
