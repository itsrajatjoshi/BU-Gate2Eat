// BU Gate2Eat — Cart Special Instructions & Notes Lifecycle Tests
// Verifies that cart-level and item-level notes/instructions never leak across items,
// variants, empty-cart states, clear-cart operations, or subsequent sessions.

import 'package:bugate2eat_app/features/cart/cart_provider.dart';
import 'package:bugate2eat_app/models/cart_item_model.dart';
import 'package:bugate2eat_app/models/cart_state_model.dart';
import 'package:bugate2eat_app/models/menu_item_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const dummyItemA = MenuItem(
    id: 'item_a',
    name: 'Veg Burger',
    price: 50,
    categoryId: 'cat_burger',
    imageUrl: 'https://example.com/burger.jpg',
    isVeg: true,
    isAvailable: true,
    isRecommended: false,
    sortOrder: 1,
    details: 'Delicious crispy burger',
  );

  const dummyItemB = MenuItem(
    id: 'item_b',
    name: 'French Fries',
    price: 60,
    categoryId: 'cat_sides',
    imageUrl: 'https://example.com/fries.jpg',
    isVeg: true,
    isAvailable: true,
    isRecommended: false,
    sortOrder: 2,
    details: 'Golden crispy fries',
  );

  const dummyItemC = MenuItem(
    id: 'item_c',
    name: 'Cold Coffee',
    price: 70,
    categoryId: 'cat_drinks',
    imageUrl: 'https://example.com/coffee.jpg',
    isVeg: true,
    isAvailable: true,
    isRecommended: false,
    sortOrder: 3,
    details: 'Refreshing cold coffee',
  );

  const cheeseOption = SelectedMenuItemOption(
    groupId: 'grp_cheese',
    groupName: 'Cheese',
    optionId: 'opt_cheese',
    optionName: 'Extra Cheese',
    pricingType: OptionPricingType.priceAdjustment,
    price: 10,
  );

  group('Cart Special Instructions Lifecycle & Stale State Elimination', () {
    late CartNotifier notifier;

    setUp(() {
      notifier = CartNotifier();
    });

    test('TEST FLOW A: Add A -> Note A -> Remove A -> Add B => Note is EMPTY', () {
      // 1. Add Item A
      notifier.addItem(dummyItemA, 'shop_1', 'Rajat Shop');
      expect(notifier.state.items.length, 1);

      // 2. Set description/note
      notifier.setSpecialInstructions('NOTE-A: Extra spicy, no onion');
      expect(notifier.state.specialInstructions, 'NOTE-A: Extra spicy, no onion');

      // 3. Remove Item A (Cart becomes empty)
      notifier.removeItem(dummyItemA.id, 'shop_1');
      expect(notifier.state.isEmpty, true);
      expect(notifier.state.specialInstructions, '');

      // 4. Add Item B
      notifier.addItem(dummyItemB, 'shop_1', 'Rajat Shop');
      expect(notifier.state.items.length, 1);
      expect(notifier.state.items.first.menuItem.id, 'item_b');

      // 5. Check description: MUST BE EMPTY
      expect(notifier.state.specialInstructions, '');
    });

    test('TEST FLOW B: Add A -> Note A -> Remove A -> Add B -> Remove B -> Add C => Note is EMPTY', () {
      // 1. Add A
      notifier.addItem(dummyItemA, 'shop_1', 'Rajat Shop');
      notifier.setSpecialInstructions('NOTE-A');

      // 2. Remove A
      notifier.removeItem(dummyItemA.id, 'shop_1');
      expect(notifier.state.specialInstructions, '');

      // 3. Add B
      notifier.addItem(dummyItemB, 'shop_1', 'Rajat Shop');
      expect(notifier.state.specialInstructions, '');

      // 4. Remove B
      notifier.removeItem(dummyItemB.id, 'shop_1');
      expect(notifier.state.specialInstructions, '');

      // 5. Add C
      notifier.addItem(dummyItemC, 'shop_1', 'Rajat Shop');
      expect(notifier.state.specialInstructions, '');
    });

    test('TEST FLOW C: Add A -> Note A -> Clear Entire Cart -> Add B => Note is EMPTY', () {
      // 1. Add A
      notifier.addItem(dummyItemA, 'shop_1', 'Rajat Shop');
      notifier.setSpecialInstructions('NOTE-A: Less oil');
      expect(notifier.state.specialInstructions, 'NOTE-A: Less oil');

      // 2. Clear entire cart
      notifier.clearCart();
      expect(notifier.state.isEmpty, true);
      expect(notifier.state.specialInstructions, '');

      // 3. Add B
      notifier.addItem(dummyItemB, 'shop_1', 'Rajat Shop');
      expect(notifier.state.specialInstructions, '');
    });

    test('TEST FLOW D: Add A -> Note A -> Remove A -> Add B -> Note B -> Remove B -> Add C => Note is EMPTY', () {
      // 1. Add A & Note A
      notifier.addItem(dummyItemA, 'shop_1', 'Rajat Shop');
      notifier.setSpecialInstructions('NOTE-A');

      // 2. Remove A
      notifier.deleteItem(dummyItemA.id, 'shop_1');
      expect(notifier.state.specialInstructions, '');

      // 3. Add B & Note B
      notifier.addItem(dummyItemB, 'shop_1', 'Rajat Shop');
      notifier.setSpecialInstructions('NOTE-B');
      expect(notifier.state.specialInstructions, 'NOTE-B');

      // 4. Remove B
      notifier.deleteItem(dummyItemB.id, 'shop_1');
      expect(notifier.state.specialInstructions, '');

      // 5. Add C
      notifier.addItem(dummyItemC, 'shop_1', 'Rajat Shop');
      expect(notifier.state.specialInstructions, '');
    });

    test('TEST FLOW E: Add A -> Note A -> Add B -> Remove A => Note is cleared, B does not inherit Note A', () {
      // 1. Add A & Note A
      notifier.addItem(dummyItemA, 'shop_1', 'Rajat Shop');
      notifier.setSpecialInstructions('NOTE-A: Make the burger spicy');

      // 2. Add B (cart now has A and B)
      notifier.addItem(dummyItemB, 'shop_1', 'Rajat Shop');
      expect(notifier.state.items.length, 2);

      // 3. Remove Item A
      notifier.deleteItem(dummyItemA.id, 'shop_1');
      expect(notifier.state.items.length, 1);
      expect(notifier.state.items.first.menuItem.id, 'item_b');

      // 4. B must NOT inherit NOTE-A
      expect(notifier.state.specialInstructions, '');
    });

    test('TEST FLOW F: Variant A (with Cheese) -> Note A -> Remove -> Variant B (No Cheese) => Note is EMPTY', () {
      // 1. Add Burger with Cheese
      notifier.addItem(
        dummyItemA,
        'shop_1',
        'Rajat Shop',
        selectedOptions: [cheeseOption],
        unitPrice: 60,
      );
      notifier.setSpecialInstructions('NOTE-A: Extra crispy cheese');
      expect(notifier.state.specialInstructions, 'NOTE-A: Extra crispy cheese');

      // 2. Delete Burger with Cheese
      final variantKey = CartItem.buildCartKey(dummyItemA.id, [cheeseOption]);
      notifier.deleteItem(variantKey, 'shop_1');
      expect(notifier.state.isEmpty, true);
      expect(notifier.state.specialInstructions, '');

      // 3. Add Burger with No Cheese
      notifier.addItem(
        dummyItemA,
        'shop_1',
        'Rajat Shop',
        selectedOptions: [],
        unitPrice: 50,
      );
      expect(notifier.state.items.length, 1);

      // 4. Note must be empty
      expect(notifier.state.specialInstructions, '');
    });

    test('TEST FLOW G: Permanent MenuItem.details is untouched while cart note is cleared', () {
      // 1. Add Item A
      notifier.addItem(dummyItemA, 'shop_1', 'Rajat Shop');
      notifier.setSpecialInstructions('Custom user note');

      // 2. MenuItem.details is permanent and immutable
      expect(notifier.state.items.first.menuItem.details, 'Delicious crispy burger');

      // 3. Clear cart
      notifier.clearCart();
      expect(notifier.state.specialInstructions, '');

      // 4. Re-add Item A
      notifier.addItem(dummyItemA, 'shop_1', 'Rajat Shop');
      // Permanent description still exists on MenuItem
      expect(notifier.state.items.first.menuItem.details, 'Delicious crispy burger');
      // But temporary user note is fresh & empty
      expect(notifier.state.specialInstructions, '');
    });

    test('TEST FLOW H: Cross-shop replacement clears special instructions', () {
      // 1. Shop 1 in cart with note
      notifier.addItem(dummyItemA, 'shop_1', 'Rajat Shop');
      notifier.setSpecialInstructions('Shop 1 instructions');

      // 2. Replace with Shop 2 item
      const dummyShop2Item = MenuItem(
        id: 'item_x',
        name: 'UP16 Roll',
        price: 80,
        categoryId: 'cat_rolls',
        imageUrl: 'https://example.com/roll.jpg',
        isVeg: true,
        isAvailable: true,
        isRecommended: false,
        sortOrder: 1,
        details: 'Tasty roll',
      );

      notifier.clearAndAddItem(dummyShop2Item, 'shop_2', 'UP16');
      expect(notifier.state.shopId, 'shop_2');
      expect(notifier.state.specialInstructions, '');
    });
  });
}
