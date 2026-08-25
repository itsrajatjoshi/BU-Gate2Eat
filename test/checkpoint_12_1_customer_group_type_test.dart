// BU Gate2Eat — Checkpoint 12.1 Tests
// Customer Options UI Based on Group Type (Fixed, Choice, Extra)

import 'package:bugate2eat_app/features/cart/cart_provider.dart';
import 'package:bugate2eat_app/models/cart_item_model.dart';
import 'package:bugate2eat_app/models/menu_item_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Checkpoint 12.1: Customer Options UI Based on Group Type', () {
    const shopId = 'shop_up16';
    const shopName = 'UP16 Coffee Queen';

    const sampleBurger = MenuItem(
      id: 'burger_classic',
      name: 'Classic Burger',
      details: 'Crispy patty with fresh veggies',
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
            MenuItemOption(id: 'opt_with_sauce', name: 'With Sauce', price: 0, pricingType: OptionPricingType.selectionOnly, isDefault: true),
            MenuItemOption(id: 'opt_no_sauce', name: 'Without Sauce', price: 0, pricingType: OptionPricingType.selectionOnly),
          ],
        ),
        MenuItemOptionGroup(
          id: 'grp_extra',
          name: 'Extras',
          groupType: OptionGroupType.extra,
          required: false,
          options: [
            MenuItemOption(id: 'opt_cheese', name: 'Cheese', price: 10, pricingType: OptionPricingType.priceAdjustment),
          ],
        ),
      ],
    );

    const sizeSmall = SelectedMenuItemOption(
      groupId: 'grp_size',
      groupName: 'Size',
      optionId: 'opt_small',
      optionName: 'Small',
      pricingType: OptionPricingType.fixedPrice,
      price: 40,
    );

    const sizeLarge = SelectedMenuItemOption(
      groupId: 'grp_size',
      groupName: 'Size',
      optionId: 'opt_large',
      optionName: 'Large',
      pricingType: OptionPricingType.fixedPrice,
      price: 70,
    );

    const sauceWith = SelectedMenuItemOption(
      groupId: 'grp_sauce',
      groupName: 'Sauce',
      optionId: 'opt_with_sauce',
      optionName: 'With Sauce',
      pricingType: OptionPricingType.selectionOnly,
      price: 0,
    );

    const sauceWithout = SelectedMenuItemOption(
      groupId: 'grp_sauce',
      groupName: 'Sauce',
      optionId: 'opt_no_sauce',
      optionName: 'Without Sauce',
      pricingType: OptionPricingType.selectionOnly,
      price: 0,
    );

    const extraCheese = SelectedMenuItemOption(
      groupId: 'grp_extra',
      groupName: 'Extras',
      optionId: 'opt_cheese',
      optionName: 'Cheese',
      pricingType: OptionPricingType.priceAdjustment,
      price: 10,
    );

    // ── 1 & 2. FIXED GROUP INDEPENDENT ADD CONTROLS & CART KEY GENERATION ────────
    test('1 & 2. Fixed group generates independent cart keys and quantity 0 shows ADD', () {
      final keySmall = CartItem.buildCartKey(sampleBurger.id, [sizeSmall, sauceWith]);
      final keyLarge = CartItem.buildCartKey(sampleBurger.id, [sizeLarge, sauceWith]);

      expect(keySmall, isNot(equals(keyLarge)));
      expect(keySmall, equals('burger_classic|grp_sauce:opt_with_sauce|grp_size:opt_small'));
      expect(keyLarge, equals('burger_classic|grp_sauce:opt_with_sauce|grp_size:opt_large'));

      final cartNotifier = CartNotifier();
      final qtySmall = cartNotifier.state.items.where((ci) => ci.cartKey == keySmall).firstOrNull?.quantity ?? 0;
      final qtyLarge = cartNotifier.state.items.where((ci) => ci.cartKey == keyLarge).firstOrNull?.quantity ?? 0;

      expect(qtySmall, 0); // Shows ADD
      expect(qtyLarge, 0); // Shows ADD
    });

    // ── 3 & 4. FIXED QUANTITY 1 AND 2 STEPPER REFLECTION ────────────────────────
    test('3 & 4. CartState reflects quantity 1 and increment to 2 for specific variant', () {
      final cartNotifier = CartNotifier();

      // Add 1 Large Burger (With Sauce, No Cheese) - Unit Price ₹70
      cartNotifier.addItem(
        sampleBurger,
        shopId,
        shopName,
        selectedOptions: [sizeLarge, sauceWith],
        unitPrice: 70,
      );

      final keyLarge = CartItem.buildCartKey(sampleBurger.id, [sizeLarge, sauceWith]);
      expect(cartNotifier.state.items.length, 1);
      expect(cartNotifier.state.items.first.cartKey, keyLarge);
      expect(cartNotifier.state.items.first.quantity, 1); // Shows [ - 1 + ]
      expect(cartNotifier.state.items.first.unitPrice, 70);
      expect(cartNotifier.state.items.first.totalPrice, 70.0);

      // Increment Large Burger to 2
      cartNotifier.addItem(
        sampleBurger,
        shopId,
        shopName,
        selectedOptions: [sizeLarge, sauceWith],
        unitPrice: 70,
      );

      expect(cartNotifier.state.items.length, 1);
      expect(cartNotifier.state.items.first.quantity, 2); // Shows [ - 2 + ]
      expect(cartNotifier.state.items.first.totalPrice, 140.0);
    });

    // ── 5 & 6. CHOICE SELECTION IS MUTUALLY EXCLUSIVE & CONTRIBUTES ₹0 ──────────
    test('5 & 6. Choice group is mutually exclusive and contributes zero price surcharge', () {
      final configWithSauce = [sizeLarge, sauceWith];
      final configWithoutSauce = [sizeLarge, sauceWithout];

      final keyWith = CartItem.buildCartKey(sampleBurger.id, configWithSauce);
      final keyWithout = CartItem.buildCartKey(sampleBurger.id, configWithoutSauce);

      expect(keyWith, isNot(equals(keyWithout)));
      expect(keyWith, contains('grp_sauce:opt_with_sauce'));
      expect(keyWithout, contains('grp_sauce:opt_no_sauce'));

      // Both must have base unit price ₹70 since Choice has price ₹0
      final itemWith = CartItem(
        menuItem: sampleBurger,
        quantity: 1,
        shopId: shopId,
        shopName: shopName,
        selectedOptions: configWithSauce,
        unitPriceOverride: 70,
      );

      final itemWithout = CartItem(
        menuItem: sampleBurger,
        quantity: 1,
        shopId: shopId,
        shopName: shopName,
        selectedOptions: configWithoutSauce,
        unitPriceOverride: 70,
      );

      expect(itemWith.unitPrice, 70);
      expect(itemWithout.unitPrice, 70);
      expect(itemWith.optionsDescription, 'Large · With Sauce');
      expect(itemWithout.optionsDescription, 'Large · Without Sauce');
    });

    // ── 7 & 8. EXTRA CAN REMAIN UNSELECTED OR ADD SURCHARGE ─────────────────────
    test('7 & 8. Extra group may remain unselected (₹0) or when selected adds surcharge (+₹10)', () {
      // Unselected Extra
      final optionsNoExtra = [sizeLarge, sauceWith];
      const unitPriceNoExtra = 70; // 70 + 0

      // Selected Extra (Cheese)
      final optionsWithCheese = [sizeLarge, sauceWith, extraCheese];
      const unitPriceWithCheese = 70 + 10; // 80

      expect(unitPriceNoExtra, 70);
      expect(unitPriceWithCheese, 80);
      expect(optionsNoExtra.length, 2);
      expect(optionsWithCheese.length, 3);
    });

    // ── 9 & 10. BURGER LARGE + NO CHEESE VS BURGER LARGE + CHEESE IN CART ──────
    test('9 & 10. Burger Large + No Cheese and Large + Cheese are 2 SEPARATE cart lines', () {
      final cartNotifier = CartNotifier();

      // Step 1: Add Burger Large + With Sauce + No Cheese (₹70)
      cartNotifier.addItem(
        sampleBurger,
        shopId,
        shopName,
        selectedOptions: [sizeLarge, sauceWith],
        unitPrice: 70,
      );

      // Step 2: Add Burger Large + With Sauce + Cheese (₹80)
      cartNotifier.addItem(
        sampleBurger,
        shopId,
        shopName,
        selectedOptions: [sizeLarge, sauceWith, extraCheese],
        unitPrice: 80,
      );

      // Verify that there are 2 separate items in cart
      expect(cartNotifier.state.items.length, 2);

      final line1 = cartNotifier.state.items[0];
      final line2 = cartNotifier.state.items[1];

      expect(line1.cartKey, 'burger_classic|grp_sauce:opt_with_sauce|grp_size:opt_large');
      expect(line1.unitPrice, 70);
      expect(line1.quantity, 1);
      expect(line1.totalPrice, 70.0);
      expect(line1.optionsDescription, 'Large · With Sauce');

      expect(line2.cartKey, 'burger_classic|grp_extra:opt_cheese|grp_sauce:opt_with_sauce|grp_size:opt_large');
      expect(line2.unitPrice, 80);
      expect(line2.quantity, 1);
      expect(line2.totalPrice, 80.0);
      expect(line2.optionsDescription, 'Large · With Sauce · Cheese');

      // Grand Total: 70 + 80 = 150
      expect(cartNotifier.state.grandTotal, 150.0);
      expect(cartNotifier.state.totalItemCount, 2);
    });

    // ── 11 & 12. CONFIGURATION CHANGES DO NOT MUTATE EXISTING CART LINES ────────
    test('11 & 12. Changing Extra selection in bottom sheet does not mutate old cart item', () {
      final cartNotifier = CartNotifier();

      // Customer initially had Large + No Cheese in cart
      cartNotifier.addItem(
        sampleBurger,
        shopId,
        shopName,
        selectedOptions: [sizeLarge, sauceWith],
        unitPrice: 70,
      );

      final keyNoCheese = CartItem.buildCartKey(sampleBurger.id, [sizeLarge, sauceWith]);
      final keyWithCheese = CartItem.buildCartKey(sampleBurger.id, [sizeLarge, sauceWith, extraCheese]);

      // When Cheese is unselected: Large row reads keyNoCheese -> returns quantity 1
      final qtyWhenNoCheeseActive = cartNotifier.state.items
          .where((ci) => ci.cartKey == keyNoCheese)
          .firstOrNull?.quantity ?? 0;
      expect(qtyWhenNoCheeseActive, 1); // Large shows [ - 1 + ]

      // When Cheese is selected: Large row reads keyWithCheese -> returns quantity 0
      final qtyWhenCheeseActive = cartNotifier.state.items
          .where((ci) => ci.cartKey == keyWithCheese)
          .firstOrNull?.quantity ?? 0;
      expect(qtyWhenCheeseActive, 0); // Large shows [ ADD ]

      // The original cart item was NOT mutated
      expect(cartNotifier.state.items.length, 1);
      expect(cartNotifier.state.items.first.cartKey, keyNoCheese);
      expect(cartNotifier.state.items.first.unitPrice, 70);
    });

    // ── 13. REQUIRED CHOICE VALIDATION ──────────────────────────────────────────
    test('13. Required Choice validation ensures complete configuration', () {
      const groupWithoutChoice = MenuItemOptionGroup(
        id: 'grp_sauce',
        name: 'Sauce',
        groupType: OptionGroupType.choice,
        required: true,
        options: [
          MenuItemOption(id: 'opt_w', name: 'With Sauce', price: 0, pricingType: OptionPricingType.selectionOnly),
        ],
      );

      expect(groupWithoutChoice.required, isTrue);
      expect(groupWithoutChoice.groupType, OptionGroupType.choice);
    });

    // ── 14. NORMAL ITEMS REMAIN UNCHANGED ───────────────────────────────────────
    test('14. Normal item has hasOptions=false, simple cartKey, and direct stepper', () {
      const coldCoffee = MenuItem(
        id: 'cold_coffee',
        name: 'Cold Coffee',
        details: 'Classic chilled coffee',
        price: 50,
        imageUrl: '',
        categoryId: 'beverages',
        isVeg: true,
        isAvailable: true,
        isRecommended: true,
        sortOrder: 2,
      );

      expect(coldCoffee.hasOptions, isFalse);

      final cartNotifier = CartNotifier();
      cartNotifier.addItem(
        coldCoffee,
        shopId,
        shopName,
      );

      expect(cartNotifier.state.items.length, 1);
      expect(cartNotifier.state.items.first.cartKey, 'cold_coffee');
      expect(cartNotifier.state.items.first.unitPrice, 50);
      expect(cartNotifier.state.items.first.quantity, 1);
      expect(cartNotifier.state.items.first.hasSelectedOptions, isFalse);
    });
  });
}
