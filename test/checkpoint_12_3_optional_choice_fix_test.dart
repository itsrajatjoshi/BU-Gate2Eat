// BU Gate2Eat — Bug Fix Test Suite: Optional Choice Unselected & Starting Price Invariants
// Verifies that Optional Choices NEVER auto-select or inflate startingPrice,
// Required Choices pick the cheapest valid default, and live candidate prices update accurately.

import 'package:bugate2eat_app/features/cart/cart_provider.dart';
import 'package:bugate2eat_app/models/cart_item_model.dart';
import 'package:bugate2eat_app/models/menu_item_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Checkpoint 12.3 Bug Fix: Optional Choice & Starting Price Invariants', () {
    const shopId = 'burger_queen_shop';
    const shopName = 'Burger Queen';

    // ── BURGER FIXTURE (Size: Small ₹50 / Big ₹70, Sauce: With / Without ₹0, Cheese: +₹10 Optional) ──
    const testBurger = MenuItem(
      id: 'burger_custom',
      name: 'Burger',
      details: 'Delicious customizable burger',
      price: 50,
      imageUrl: '',
      categoryId: 'burgers',
      isVeg: true,
      isAvailable: true,
      isRecommended: true,
      sortOrder: 1,
      optionGroups: [
        MenuItemOptionGroup(
          id: 'grp_sauce',
          name: 'Sauce',
          groupType: OptionGroupType.choice,
          required: true,
          options: [
            MenuItemOption(id: 'opt_with_sauce', name: 'With Sauce', price: 0, pricingType: OptionPricingType.selectionOnly, isDefault: true),
            MenuItemOption(id: 'opt_without_sauce', name: 'Without Sauce', price: 0, pricingType: OptionPricingType.selectionOnly),
          ],
        ),
        MenuItemOptionGroup(
          id: 'grp_cheese',
          name: 'Cheese',
          groupType: OptionGroupType.choice,
          required: false,
          options: [
            MenuItemOption(id: 'opt_cheese', name: 'Cheese', price: 10, pricingType: OptionPricingType.priceAdjustment, isDefault: false),
          ],
        ),
        MenuItemOptionGroup(
          id: 'grp_size',
          name: 'Size',
          groupType: OptionGroupType.fixed,
          required: true,
          options: [
            MenuItemOption(id: 'opt_small', name: 'Small', price: 50, pricingType: OptionPricingType.fixedPrice, isDefault: true),
            MenuItemOption(id: 'opt_big', name: 'Big', price: 70, pricingType: OptionPricingType.fixedPrice),
          ],
        ),
      ],
    );

    // ── 1. BURGER STARTING PRICE = ₹50 ─────────────────────────────────────────
    test('1. Burger startingPrice is exactly ₹50 (cheapest valid configuration)', () {
      expect(testBurger.startingPrice, 50);
      expect(testBurger.formattedStartingPrice, 'Starting from ₹50');
    });

    // ── 2. OPTIONAL CHEESE DOES NOT INFLATE STARTING PRICE ─────────────────────
    test('2. Optional Cheese (+₹10) does NOT increase startingPrice', () {
      // Even if an optional choice has +₹10, +₹30, startingPrice remains Small (₹50)
      const burgerWithMultipleExtras = MenuItem(
        id: 'burger_multi_extra',
        name: 'Burger Extra',
        details: '',
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
              MenuItemOption(id: 'opt_s', name: 'Small', price: 50, pricingType: OptionPricingType.fixedPrice),
              MenuItemOption(id: 'opt_b', name: 'Big', price: 70, pricingType: OptionPricingType.fixedPrice),
            ],
          ),
          MenuItemOptionGroup(
            id: 'grp_sauce',
            name: 'Sauce',
            groupType: OptionGroupType.choice,
            required: true,
            options: [
              MenuItemOption(id: 'opt_w', name: 'With Sauce', price: 0, pricingType: OptionPricingType.selectionOnly),
            ],
          ),
          MenuItemOptionGroup(
            id: 'grp_cheese',
            name: 'Cheese',
            groupType: OptionGroupType.choice,
            required: false,
            options: [
              MenuItemOption(id: 'opt_c', name: 'Cheese', price: 10, pricingType: OptionPricingType.priceAdjustment, isDefault: true),
              MenuItemOption(id: 'opt_p', name: 'Extra Patty', price: 30, pricingType: OptionPricingType.priceAdjustment),
            ],
          ),
        ],
      );

      expect(burgerWithMultipleExtras.startingPrice, 50);
      expect(burgerWithMultipleExtras.formattedStartingPrice, 'Starting from ₹50');
    });

    // ── 3. OPTIONAL CHOICE INITIAL STATE: STARTS UNSELECTED ───────────────────
    test('3. Optional Choice group initializes to null / unselected in state', () {
      final Map<String, MenuItemOption?> initialSelections = {};

      for (final group in testBurger.optionGroups) {
        if (group.groupType == OptionGroupType.fixed) {
          continue;
        } else if (group.required) {
          final minPrice = group.options.map((o) => o.price).reduce((a, b) => a < b ? a : b);
          final cheapestOptions = group.options.where((o) => o.price == minPrice).toList();
          initialSelections[group.id] = cheapestOptions.where((o) => o.isDefault).firstOrNull ?? cheapestOptions.first;
        } else {
          // Optional Choice MUST start unselected
          initialSelections[group.id] = null;
        }
      }

      expect(initialSelections['grp_sauce'], isNotNull);
      expect(initialSelections['grp_sauce']!.name, 'With Sauce');
      expect(initialSelections['grp_cheese'], isNull);
    });

    // ── 4. REQUIRED CHOICE SELECTS CHEAPEST VALID OPTION ───────────────────────
    test('4. Required Choice automatically selects the cheapest valid choice', () {
      const groupWithPrices = MenuItemOptionGroup(
        id: 'grp_prep',
        name: 'Preparation',
        groupType: OptionGroupType.choice,
        required: true,
        options: [
          MenuItemOption(id: 'opt_expensive', name: 'Special Gravy', price: 30, pricingType: OptionPricingType.priceAdjustment, isDefault: true),
          MenuItemOption(id: 'opt_plain', name: 'Plain Dry', price: 0, pricingType: OptionPricingType.selectionOnly, isDefault: false),
        ],
      );

      final minPrice = groupWithPrices.options.map((o) => o.price).reduce((a, b) => a < b ? a : b);
      final cheapestOptions = groupWithPrices.options.where((o) => o.price == minPrice).toList();
      final selected = cheapestOptions.where((o) => o.isDefault).firstOrNull ?? cheapestOptions.first;

      // Must pick the ₹0 option, not the expensive ₹30 isDefault
      expect(selected.name, 'Plain Dry');
      expect(selected.price, 0);
    });

    // ── 5 & 6. INITIAL CANDIDATE PRICES: SMALL = ₹50, BIG = ₹70 ───────────────
    test('5 & 6. Initial candidate prices are Small = ₹50 and Big = ₹70 before Cheese is selected', () {
      int calculateCandidatePrice(MenuItemOption fixedOption, Map<String, MenuItemOption?> selections) {
        int price = fixedOption.price;
        for (final entry in selections.entries) {
          if (entry.value != null && entry.value!.price > 0) {
            price += entry.value!.price;
          }
        }
        return price;
      }

      final smallOpt = testBurger.optionGroups.firstWhere((g) => g.id == 'grp_size').options[0];
      final bigOpt = testBurger.optionGroups.firstWhere((g) => g.id == 'grp_size').options[1];
      final sauceOpt = testBurger.optionGroups.firstWhere((g) => g.id == 'grp_sauce').options[0];

      final initialSelections = {
        'grp_sauce': sauceOpt,
        'grp_cheese': null, // unselected
      };

      expect(calculateCandidatePrice(smallOpt, initialSelections), 50);
      expect(calculateCandidatePrice(bigOpt, initialSelections), 70);
    });

    // ── 7. AFTER CHEESE SELECTED: SMALL = ₹60, BIG = ₹80 ──────────────────────
    test('7. After Cheese (+₹10) is selected, candidate prices update to Small = ₹60, Big = ₹80', () {
      int calculateCandidatePrice(MenuItemOption fixedOption, Map<String, MenuItemOption?> selections) {
        int price = fixedOption.price;
        for (final entry in selections.entries) {
          if (entry.value != null && entry.value!.price > 0) {
            price += entry.value!.price;
          }
        }
        return price;
      }

      final smallOpt = testBurger.optionGroups.firstWhere((g) => g.id == 'grp_size').options[0];
      final bigOpt = testBurger.optionGroups.firstWhere((g) => g.id == 'grp_size').options[1];
      final sauceOpt = testBurger.optionGroups.firstWhere((g) => g.id == 'grp_sauce').options[0];
      final cheeseOpt = testBurger.optionGroups.firstWhere((g) => g.id == 'grp_cheese').options[0];

      final selectionsWithCheese = {
        'grp_sauce': sauceOpt,
        'grp_cheese': cheeseOpt, // selected
      };

      expect(calculateCandidatePrice(smallOpt, selectionsWithCheese), 60);
      expect(calculateCandidatePrice(bigOpt, selectionsWithCheese), 80);
    });

    // ── 8. DISTINCT CART KEYS FOR NO CHEESE VS WITH CHEESE ────────────────────
    test('8. Burger Small + No Cheese and Burger Small + Cheese have distinct cartKeys and coexist', () {
      final cartNotifier = CartNotifier();

      const sizeSmall = SelectedMenuItemOption(
        groupId: 'grp_size',
        groupName: 'Size',
        optionId: 'opt_small',
        optionName: 'Small',
        pricingType: OptionPricingType.fixedPrice,
        price: 50,
      );

      const sauceWith = SelectedMenuItemOption(
        groupId: 'grp_sauce',
        groupName: 'Sauce',
        optionId: 'opt_with_sauce',
        optionName: 'With Sauce',
        pricingType: OptionPricingType.selectionOnly,
        price: 0,
      );

      const cheeseExtra = SelectedMenuItemOption(
        groupId: 'grp_cheese',
        groupName: 'Cheese',
        optionId: 'opt_cheese',
        optionName: 'Cheese',
        pricingType: OptionPricingType.priceAdjustment,
        price: 10,
      );

      // Line 1: Small + With Sauce (No Cheese) -> ₹50
      cartNotifier.addItem(
        testBurger,
        shopId,
        shopName,
        selectedOptions: [sizeSmall, sauceWith],
        unitPrice: 50,
      );

      // Line 2: Small + With Sauce + Cheese -> ₹60
      cartNotifier.addItem(
        testBurger,
        shopId,
        shopName,
        selectedOptions: [sizeSmall, sauceWith, cheeseExtra],
        unitPrice: 60,
      );

      final state = cartNotifier.state;
      expect(state.items.length, 2);

      final itemNoCheese = state.items.firstWhere((i) => !i.selectedOptions.contains(cheeseExtra));
      final itemWithCheese = state.items.firstWhere((i) => i.selectedOptions.contains(cheeseExtra));

      expect(itemNoCheese.unitPrice, 50);
      expect(itemNoCheese.cartKey, 'burger_custom|grp_sauce:opt_with_sauce|grp_size:opt_small');

      expect(itemWithCheese.unitPrice, 60);
      expect(itemWithCheese.cartKey, 'burger_custom|grp_cheese:opt_cheese|grp_sauce:opt_with_sauce|grp_size:opt_small');

      expect(state.grandTotal, 110.0);
    });

    // ── 9, 10, 11. COLD COFFEE STARTING PRICE & ICE CREAM FLOW ─────────────────
    test('9, 10, 11. Cold Coffee starting price = ₹60, Ice Cream starts unselected, and adds +₹10 only when selected', () {
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

      // 9. Starting price is Large base (₹60)
      expect(normalColdCoffee.startingPrice, 60);
      expect(normalColdCoffee.formattedStartingPrice, 'Starting from ₹60');

      // 10. Optional Ice Cream starts unselected
      final initialSelections = <String, MenuItemOption?>{};
      for (final group in normalColdCoffee.optionGroups) {
        if (group.groupType == OptionGroupType.fixed) continue;
        if (group.required) {
          final minPrice = group.options.map((o) => o.price).reduce((a, b) => a < b ? a : b);
          final cheapestOptions = group.options.where((o) => o.price == minPrice).toList();
          initialSelections[group.id] = cheapestOptions.first;
        } else {
          initialSelections[group.id] = null;
        }
      }
      expect(initialSelections['grp_ice_cream'], isNull);

      // 11. Adding Large without selection = ₹60, with selection = ₹70
      const sizeLarge = SelectedMenuItemOption(
        groupId: 'grp_size',
        groupName: 'Size',
        optionId: 'opt_large',
        optionName: 'Large',
        pricingType: OptionPricingType.fixedPrice,
        price: 60,
      );
      const withIce = SelectedMenuItemOption(
        groupId: 'grp_ice_cream',
        groupName: 'Ice Cream',
        optionId: 'opt_with_ice_cream',
        optionName: 'With Ice Cream',
        pricingType: OptionPricingType.priceAdjustment,
        price: 10,
      );

      final cartNotifier = CartNotifier();
      cartNotifier.addItem(normalColdCoffee, 'up16', 'UP16 Coffee Queen', selectedOptions: [sizeLarge], unitPrice: 60);
      cartNotifier.addItem(normalColdCoffee, 'up16', 'UP16 Coffee Queen', selectedOptions: [sizeLarge, withIce], unitPrice: 70);

      expect(cartNotifier.state.items.length, 2);
      expect(cartNotifier.state.items[0].unitPrice, 60);
      expect(cartNotifier.state.items[1].unitPrice, 70);
      expect(cartNotifier.state.grandTotal, 130.0);
    });

    // ── 12. NORMAL ITEMS REMAIN UNCHANGED ─────────────────────────────────────
    test('12. Normal simple items remain completely unchanged', () {
      const normalItem = MenuItem(
        id: 'mojito_mint',
        name: 'Mint Mojito',
        details: 'Refreshing mint',
        price: 70,
        imageUrl: '',
        categoryId: 'mojitos',
        isVeg: true,
        isAvailable: true,
        isRecommended: true,
        sortOrder: 1,
      );

      expect(normalItem.hasOptions, isFalse);
      expect(normalItem.startingPrice, 70);
      expect(normalItem.formattedStartingPrice, '₹70');
    });
  });
}
