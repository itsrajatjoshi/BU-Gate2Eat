// BU Gate2Eat — Checkpoint 12.1 Tests
// Customer Options UI Based on Group Type (Fixed, Choice with optionality)

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
          groupType: OptionGroupType.choice,
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

    // ── 1. FIXED GROUP STEPPERS ────────────────────────────────────────────────
    test('1. Adding Small & Large creates two distinct rows with independent counters', () {
      final cartNotifier = CartNotifier();

      // Add Small (₹40)
      cartNotifier.addItem(
        sampleBurger,
        shopId,
        shopName,
        selectedOptions: [sizeSmall, sauceWith],
        unitPrice: 40,
      );

      // Add Large (₹70)
      cartNotifier.addItem(
        sampleBurger,
        shopId,
        shopName,
        selectedOptions: [sizeLarge, sauceWith],
        unitPrice: 70,
      );

      final state = cartNotifier.state;
      expect(state.items.length, 2);

      final smallItem = state.items.firstWhere((i) => i.selectedOptions.contains(sizeSmall));
      final largeItem = state.items.firstWhere((i) => i.selectedOptions.contains(sizeLarge));

      expect(smallItem.quantity, 1);
      expect(smallItem.unitPrice, 40);
      expect(smallItem.cartKey, 'burger_classic|grp_sauce:opt_with_sauce|grp_size:opt_small');

      expect(largeItem.quantity, 1);
      expect(largeItem.unitPrice, 70);
      expect(largeItem.cartKey, 'burger_classic|grp_sauce:opt_with_sauce|grp_size:opt_large');

      expect(state.grandTotal, 110.0);
    });

    // ── 2. CHOICE GROUP MUTUAL EXCLUSIVITY ─────────────────────────────────────
    test('2. Changing Choice option switches configuration without mutating existing cart items', () {
      final cartNotifier = CartNotifier();

      // Customer adds: Large + With Sauce (₹70)
      cartNotifier.addItem(
        sampleBurger,
        shopId,
        shopName,
        selectedOptions: [sizeLarge, sauceWith],
        unitPrice: 70,
      );

      // Customer switches pill to "Without Sauce" and adds Large again
      cartNotifier.addItem(
        sampleBurger,
        shopId,
        shopName,
        selectedOptions: [sizeLarge, sauceWithout],
        unitPrice: 70,
      );

      final state = cartNotifier.state;
      expect(state.items.length, 2);

      final withSauceItem = state.items.firstWhere((i) => i.selectedOptions.contains(sauceWith));
      final noSauceItem = state.items.firstWhere((i) => i.selectedOptions.contains(sauceWithout));

      expect(withSauceItem.cartKey, 'burger_classic|grp_sauce:opt_with_sauce|grp_size:opt_large');
      expect(noSauceItem.cartKey, 'burger_classic|grp_sauce:opt_no_sauce|grp_size:opt_large');
      expect(state.grandTotal, 140.0);
    });

    // ── 3. OPTIONAL CHOICE TOGGLE & SURCHARGE ──────────────────────────────────
    test('3. Optional Choice adds surcharge (+₹10) and is omitted when unselected', () {
      final cartNotifier = CartNotifier();

      // Customer adds: Large + With Sauce + Cheese (₹80)
      cartNotifier.addItem(
        sampleBurger,
        shopId,
        shopName,
        selectedOptions: [sizeLarge, sauceWith, extraCheese],
        unitPrice: 80,
      );

      // Customer adds: Large + With Sauce (No Cheese) (₹70)
      cartNotifier.addItem(
        sampleBurger,
        shopId,
        shopName,
        selectedOptions: [sizeLarge, sauceWith],
        unitPrice: 70,
      );

      final state = cartNotifier.state;
      expect(state.items.length, 2);

      final withCheese = state.items.firstWhere((i) => i.selectedOptions.contains(extraCheese));
      final withoutCheese = state.items.firstWhere((i) => !i.selectedOptions.contains(extraCheese));

      expect(withCheese.unitPrice, 80);
      expect(withCheese.cartKey, 'burger_classic|grp_extra:opt_cheese|grp_sauce:opt_with_sauce|grp_size:opt_large');

      expect(withoutCheese.unitPrice, 70);
      expect(withoutCheese.cartKey, 'burger_classic|grp_sauce:opt_with_sauce|grp_size:opt_large');

      expect(state.grandTotal, 150.0);
    });

    // ── 4. COEXISTENCE OF LARGE + NO CHEESE AND LARGE + CHEESE ────────────────
    test('4. Large + No Cheese and Large + Cheese coexist with independent increment/decrement', () {
      final cartNotifier = CartNotifier();

      // Add Large + No Cheese
      cartNotifier.addItem(
        sampleBurger,
        shopId,
        shopName,
        selectedOptions: [sizeLarge, sauceWith],
        unitPrice: 70,
      );

      // Add Large + Cheese twice
      cartNotifier.addItem(
        sampleBurger,
        shopId,
        shopName,
        selectedOptions: [sizeLarge, sauceWith, extraCheese],
        unitPrice: 80,
      );
      cartNotifier.addItem(
        sampleBurger,
        shopId,
        shopName,
        selectedOptions: [sizeLarge, sauceWith, extraCheese],
        unitPrice: 80,
      );

      final state = cartNotifier.state;
      expect(state.items.length, 2);

      final noCheeseItem = state.items.firstWhere((i) => !i.selectedOptions.contains(extraCheese));
      final cheeseItem = state.items.firstWhere((i) => i.selectedOptions.contains(extraCheese));

      expect(noCheeseItem.quantity, 1);
      expect(noCheeseItem.totalPrice, 70.0);

      expect(cheeseItem.quantity, 2);
      expect(cheeseItem.totalPrice, 160.0);

      expect(state.grandTotal, 230.0);

      // Decrement cheese item by 1
      cartNotifier.removeItem(cheeseItem.cartKey);
      final updatedState = cartNotifier.state;
      final updatedCheeseItem = updatedState.items.firstWhere((i) => i.selectedOptions.contains(extraCheese));
      expect(updatedCheeseItem.quantity, 1);
      expect(updatedState.grandTotal, 150.0);
    });

    // ── 5. CLEAN CHOICE LABELS (NO PRICE SUFFIX FOR ₹0) ────────────────────────
    test('5. Zero-price choices have price=0 and no price surcharge', () {
      expect(sauceWith.price, 0);
      expect(sauceWithout.price, 0);
      expect(extraCheese.price, 10);
    });
  });
}
