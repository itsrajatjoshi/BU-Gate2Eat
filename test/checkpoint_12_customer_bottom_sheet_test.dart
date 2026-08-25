import 'package:bugate2eat_app/features/cart/cart_provider.dart';
import 'package:bugate2eat_app/models/cart_item_model.dart';
import 'package:bugate2eat_app/models/menu_item_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Checkpoint 12: Customer Bottom Sheet Variant Cart & Pricing Invariants', () {
    late CartNotifier cartNotifier;

    setUp(() {
      cartNotifier = CartNotifier();
    });

    const momosItem = MenuItem(
      id: 'momos_1',
      name: 'Chicken Momos',
      details: 'Fresh steamed or fried momos',
      price: 0,
      imageUrl: '',
      categoryId: 'momos',
      isVeg: false,
      isAvailable: true,
      isRecommended: true,
      sortOrder: 1,
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
              id: 'opt_dry',
              name: 'Dry',
              price: 0,
              pricingType: OptionPricingType.selectionOnly,
              isDefault: true,
            ),
            MenuItemOption(
              id: 'opt_gravy',
              name: 'Gravy',
              price: 0,
              pricingType: OptionPricingType.selectionOnly,
            ),
          ],
        ),
      ],
    );

    const coffeeItem = MenuItem(
      id: 'coffee_1',
      name: 'Cold Coffee',
      details: 'Refreshing cold coffee',
      price: 0,
      imageUrl: '',
      categoryId: 'beverages',
      isVeg: true,
      isAvailable: true,
      isRecommended: true,
      sortOrder: 1,
      optionGroups: [
        MenuItemOptionGroup(
          id: 'grp_size',
          name: 'Size',
          required: true,
          options: [
            MenuItemOption(
              id: 'opt_large',
              name: 'Large',
              price: 60,
              pricingType: OptionPricingType.fixedPrice,
            ),
            MenuItemOption(
              id: 'opt_xl',
              name: 'XL',
              price: 80,
              pricingType: OptionPricingType.fixedPrice,
            ),
          ],
        ),
        MenuItemOptionGroup(
          id: 'grp_icecream',
          name: 'Ice Cream',
          required: true,
          options: [
            MenuItemOption(
              id: 'opt_no_icecream',
              name: 'No Ice Cream',
              price: 0,
              pricingType: OptionPricingType.priceAdjustment,
              isDefault: true,
            ),
            MenuItemOption(
              id: 'opt_with_icecream',
              name: 'With Ice Cream',
              price: 10,
              pricingType: OptionPricingType.priceAdjustment,
            ),
          ],
        ),
      ],
    );

    const normalItem = MenuItem(
      id: 'maggi_1',
      name: 'Veg Maggi',
      details: 'Hot classic maggi',
      price: 50,
      imageUrl: '',
      categoryId: 'maggi',
      isVeg: true,
      isAvailable: true,
      isRecommended: false,
      sortOrder: 1,
    );

    test('1. FixedPrice option with no cart quantity reflects quantity 0 (shows ADD)', () {
      final selectedHalfDry = [
        const SelectedMenuItemOption(
          groupId: 'grp_portion',
          groupName: 'Portion',
          optionId: 'opt_half',
          optionName: 'Half',
          pricingType: OptionPricingType.fixedPrice,
          price: 80,
        ),
        const SelectedMenuItemOption(
          groupId: 'grp_prep',
          groupName: 'Preparation',
          optionId: 'opt_dry',
          optionName: 'Dry',
          pricingType: OptionPricingType.selectionOnly,
          price: 0,
        ),
      ];

      final key = CartItem.buildCartKey(momosItem.id, selectedHalfDry);
      final item = cartNotifier.state.items.where((ci) => ci.cartKey == key).firstOrNull;
      expect(item?.quantity ?? 0, equals(0));
    });

    test('2 & 3. FixedPrice option quantity changes from 0 -> 1 -> 2 on ADD', () {
      final selectedHalfDry = [
        const SelectedMenuItemOption(
          groupId: 'grp_portion',
          groupName: 'Portion',
          optionId: 'opt_half',
          optionName: 'Half',
          pricingType: OptionPricingType.fixedPrice,
          price: 80,
        ),
        const SelectedMenuItemOption(
          groupId: 'grp_prep',
          groupName: 'Preparation',
          optionId: 'opt_dry',
          optionName: 'Dry',
          pricingType: OptionPricingType.selectionOnly,
          price: 0,
        ),
      ];

      final key = CartItem.buildCartKey(momosItem.id, selectedHalfDry);

      // Add first time
      cartNotifier.addItem(
        momosItem,
        'shop_1',
        'BU Canteen',
        selectedOptions: selectedHalfDry,
        unitPrice: 80,
      );

      var cartItem = cartNotifier.state.items.where((ci) => ci.cartKey == key).firstOrNull;
      expect(cartItem?.quantity, equals(1));
      expect(cartItem?.totalPrice, equals(80));

      // Add second time (stepper +)
      cartNotifier.addItem(
        momosItem,
        'shop_1',
        'BU Canteen',
        selectedOptions: selectedHalfDry,
        unitPrice: 80,
      );

      cartItem = cartNotifier.state.items.where((ci) => ci.cartKey == key).firstOrNull;
      expect(cartItem?.quantity, equals(2));
      expect(cartItem?.totalPrice, equals(160));
    });

    test('4. Two different fixedPrice variants coexist independently (Half and Full)', () {
      final halfVariant = [
        const SelectedMenuItemOption(
          groupId: 'grp_portion',
          groupName: 'Portion',
          optionId: 'opt_half',
          optionName: 'Half',
          pricingType: OptionPricingType.fixedPrice,
          price: 80,
        ),
        const SelectedMenuItemOption(
          groupId: 'grp_prep',
          groupName: 'Preparation',
          optionId: 'opt_dry',
          optionName: 'Dry',
          pricingType: OptionPricingType.selectionOnly,
          price: 0,
        ),
      ];

      final fullVariant = [
        const SelectedMenuItemOption(
          groupId: 'grp_portion',
          groupName: 'Portion',
          optionId: 'opt_full',
          optionName: 'Full',
          pricingType: OptionPricingType.fixedPrice,
          price: 140,
        ),
        const SelectedMenuItemOption(
          groupId: 'grp_prep',
          groupName: 'Preparation',
          optionId: 'opt_dry',
          optionName: 'Dry',
          pricingType: OptionPricingType.selectionOnly,
          price: 0,
        ),
      ];

      cartNotifier.addItem(
        momosItem,
        'shop_1',
        'BU Canteen',
        selectedOptions: halfVariant,
        unitPrice: 80,
      );

      cartNotifier.addItem(
        momosItem,
        'shop_1',
        'BU Canteen',
        selectedOptions: fullVariant,
        unitPrice: 140,
      );

      expect(cartNotifier.state.items.length, equals(2));
      expect(cartNotifier.state.getQuantityForShop('shop_1', momosItem.id), equals(2));
      expect(cartNotifier.state.grandTotal, equals(220));
    });

    test('5. Same variant increments in place while sibling is unaffected', () {
      final halfVariant = [
        const SelectedMenuItemOption(
          groupId: 'grp_portion',
          groupName: 'Portion',
          optionId: 'opt_half',
          optionName: 'Half',
          pricingType: OptionPricingType.fixedPrice,
          price: 80,
        ),
        const SelectedMenuItemOption(
          groupId: 'grp_prep',
          groupName: 'Preparation',
          optionId: 'opt_dry',
          optionName: 'Dry',
          pricingType: OptionPricingType.selectionOnly,
          price: 0,
        ),
      ];

      final fullVariant = [
        const SelectedMenuItemOption(
          groupId: 'grp_portion',
          groupName: 'Portion',
          optionId: 'opt_full',
          optionName: 'Full',
          pricingType: OptionPricingType.fixedPrice,
          price: 140,
        ),
        const SelectedMenuItemOption(
          groupId: 'grp_prep',
          groupName: 'Preparation',
          optionId: 'opt_dry',
          optionName: 'Dry',
          pricingType: OptionPricingType.selectionOnly,
          price: 0,
        ),
      ];

      cartNotifier.addItem(momosItem, 'shop_1', 'BU Canteen', selectedOptions: halfVariant, unitPrice: 80);
      cartNotifier.addItem(momosItem, 'shop_1', 'BU Canteen', selectedOptions: fullVariant, unitPrice: 140);
      cartNotifier.addItem(momosItem, 'shop_1', 'BU Canteen', selectedOptions: halfVariant, unitPrice: 80);

      final halfKey = CartItem.buildCartKey(momosItem.id, halfVariant);
      final fullKey = CartItem.buildCartKey(momosItem.id, fullVariant);

      expect(cartNotifier.state.items.firstWhere((ci) => ci.cartKey == halfKey).quantity, equals(2));
      expect(cartNotifier.state.items.firstWhere((ci) => ci.cartKey == fullKey).quantity, equals(1));
      expect(cartNotifier.state.grandTotal, equals(300));
    });

    test('6 & 8. FixedPrice + SelectionOnly does not affect price (Half ₹80 + Dry/Gravy = ₹80)', () {
      final halfDry = [
        const SelectedMenuItemOption(
          groupId: 'grp_portion',
          groupName: 'Portion',
          optionId: 'opt_half',
          optionName: 'Half',
          pricingType: OptionPricingType.fixedPrice,
          price: 80,
        ),
        const SelectedMenuItemOption(
          groupId: 'grp_prep',
          groupName: 'Preparation',
          optionId: 'opt_dry',
          optionName: 'Dry',
          pricingType: OptionPricingType.selectionOnly,
          price: 0,
        ),
      ];

      final halfGravy = [
        const SelectedMenuItemOption(
          groupId: 'grp_portion',
          groupName: 'Portion',
          optionId: 'opt_half',
          optionName: 'Half',
          pricingType: OptionPricingType.fixedPrice,
          price: 80,
        ),
        const SelectedMenuItemOption(
          groupId: 'grp_prep',
          groupName: 'Preparation',
          optionId: 'opt_gravy',
          optionName: 'Gravy',
          pricingType: OptionPricingType.selectionOnly,
          price: 0,
        ),
      ];

      cartNotifier.addItem(momosItem, 'shop_1', 'BU Canteen', selectedOptions: halfDry, unitPrice: 80);
      cartNotifier.addItem(momosItem, 'shop_1', 'BU Canteen', selectedOptions: halfGravy, unitPrice: 80);

      expect(cartNotifier.state.items[0].unitPrice, equals(80));
      expect(cartNotifier.state.items[1].unitPrice, equals(80));
      expect(cartNotifier.state.grandTotal, equals(160));
    });

    test('7 & 9. FixedPrice + PriceAdjustment modifies unit price (Large ₹60 + Ice Cream +₹10 = ₹70)', () {
      final largeWithIceCream = [
        const SelectedMenuItemOption(
          groupId: 'grp_size',
          groupName: 'Size',
          optionId: 'opt_large',
          optionName: 'Large',
          pricingType: OptionPricingType.fixedPrice,
          price: 60,
        ),
        const SelectedMenuItemOption(
          groupId: 'grp_icecream',
          groupName: 'Ice Cream',
          optionId: 'opt_with_icecream',
          optionName: 'With Ice Cream',
          pricingType: OptionPricingType.priceAdjustment,
          price: 10,
        ),
      ];

      cartNotifier.addItem(coffeeItem, 'shop_1', 'BU Canteen', selectedOptions: largeWithIceCream, unitPrice: 70);

      expect(cartNotifier.state.items.first.unitPrice, equals(70));
      expect(cartNotifier.state.items.first.totalPrice, equals(70));
    });

    test('10. Dry vs Gravy produce separate cart keys', () {
      final halfDry = [
        const SelectedMenuItemOption(
          groupId: 'grp_portion',
          groupName: 'Portion',
          optionId: 'opt_half',
          optionName: 'Half',
          pricingType: OptionPricingType.fixedPrice,
          price: 80,
        ),
        const SelectedMenuItemOption(
          groupId: 'grp_prep',
          groupName: 'Preparation',
          optionId: 'opt_dry',
          optionName: 'Dry',
          pricingType: OptionPricingType.selectionOnly,
          price: 0,
        ),
      ];

      final halfGravy = [
        const SelectedMenuItemOption(
          groupId: 'grp_portion',
          groupName: 'Portion',
          optionId: 'opt_half',
          optionName: 'Half',
          pricingType: OptionPricingType.fixedPrice,
          price: 80,
        ),
        const SelectedMenuItemOption(
          groupId: 'grp_prep',
          groupName: 'Preparation',
          optionId: 'opt_gravy',
          optionName: 'Gravy',
          pricingType: OptionPricingType.selectionOnly,
          price: 0,
        ),
      ];

      final key1 = CartItem.buildCartKey(momosItem.id, halfDry);
      final key2 = CartItem.buildCartKey(momosItem.id, halfGravy);

      expect(key1, isNot(equals(key2)));
      expect(key1, contains('opt_dry'));
      expect(key2, contains('opt_gravy'));
    });

    test('11. Normal item remains completely unchanged in cart flow', () {
      cartNotifier.addItem(normalItem, 'shop_1', 'BU Canteen');
      cartNotifier.addItem(normalItem, 'shop_1', 'BU Canteen');

      expect(cartNotifier.state.items.length, equals(1));
      expect(cartNotifier.state.items.first.hasSelectedOptions, isFalse);
      expect(cartNotifier.state.items.first.cartKey, equals(normalItem.id));
      expect(cartNotifier.state.items.first.quantity, equals(2));
      expect(cartNotifier.state.grandTotal, equals(100));
    });

    test('12 & 13. Decrementing a variant to 0 removes it and updates cart quantity accurately', () {
      final halfDry = [
        const SelectedMenuItemOption(
          groupId: 'grp_portion',
          groupName: 'Portion',
          optionId: 'opt_half',
          optionName: 'Half',
          pricingType: OptionPricingType.fixedPrice,
          price: 80,
        ),
        const SelectedMenuItemOption(
          groupId: 'grp_prep',
          groupName: 'Preparation',
          optionId: 'opt_dry',
          optionName: 'Dry',
          pricingType: OptionPricingType.selectionOnly,
          price: 0,
        ),
      ];

      final key = CartItem.buildCartKey(momosItem.id, halfDry);
      cartNotifier.addItem(momosItem, 'shop_1', 'BU Canteen', selectedOptions: halfDry, unitPrice: 80);
      expect(cartNotifier.state.items.where((ci) => ci.cartKey == key).first.quantity, equals(1));

      cartNotifier.removeItem(key);
      expect(cartNotifier.state.items.where((ci) => ci.cartKey == key).isEmpty, isTrue);
    });
  });
}
