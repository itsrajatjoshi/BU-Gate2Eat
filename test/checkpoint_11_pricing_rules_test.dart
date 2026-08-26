// BU Gate2Eat — Checkpoint 11 Test Suite
// Verifies universal OptionPricingType.selectionOnly, startingPrice semantics, serialization, and Add/Edit rules.

import 'package:bugate2eat_app/models/menu_item_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Checkpoint 11: Final Option Pricing Types & startingPrice Rules', () {
    test('1. Normal item (no optionGroups) uses base price as startingPrice', () {
      const normalItem = MenuItem(
        id: 'maggi_1',
        name: 'Veg Maggi',
        details: 'Plain hot maggi',
        price: 50,
        imageUrl: '',
        categoryId: 'fast_food',
        isVeg: true,
        isAvailable: true,
        isRecommended: false,
        sortOrder: 1,
      );

      expect(normalItem.hasOptions, isFalse);
      expect(normalItem.startingPrice, equals(50));
      expect(normalItem.formattedStartingPrice, equals('₹50'));
    });

    test('2. Fixed-price option group uses minimum fixed price as startingPrice', () {
      const fixedGroup = MenuItemOptionGroup(
        id: 'grp_portion',
        name: 'Portion',
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
      );

      const momosItem = MenuItem(
        id: 'momos_1',
        name: 'Chicken Momos',
        details: 'Hot momos',
        price: 0,
        imageUrl: '',
        categoryId: 'momos',
        isVeg: false,
        isAvailable: true,
        isRecommended: true,
        sortOrder: 1,
        optionGroups: [fixedGroup],
      );

      expect(momosItem.hasOptions, isTrue);
      expect(momosItem.startingPrice, equals(80));
      expect(momosItem.formattedStartingPrice, equals('₹80'));
    });

    test('3. SelectionOnly option group contributes ₹0 to price and stores 0 internally', () {
      const selectionGroup = MenuItemOptionGroup(
        id: 'grp_prep',
        name: 'Preparation',
        options: [
          MenuItemOption(
            id: 'opt_dry',
            name: 'Dry',
            price: 0,
            pricingType: OptionPricingType.selectionOnly,
          ),
          MenuItemOption(
            id: 'opt_gravy',
            name: 'Gravy',
            price: 0,
            pricingType: OptionPricingType.selectionOnly,
          ),
        ],
      );

      final dryMap = selectionGroup.options[0].toMap();
      expect(dryMap['pricingType'], equals('selectionOnly'));
      expect(dryMap['price'], equals(0));
      expect(dryMap['name'], equals('Dry'));

      final restored = MenuItemOption.fromMap(dryMap);
      expect(restored.pricingType, equals(OptionPricingType.selectionOnly));
      expect(restored.price, equals(0));
      expect(restored.name, equals('Dry'));
    });

    test('4. Fixed + SelectionOnly (Momos: Portion Half ₹80/Full ₹140 + Prep Dry/Gravy) = ₹80', () {
      const portionGroup = MenuItemOptionGroup(
        id: 'grp_portion',
        name: 'Portion',
        options: [
          MenuItemOption(
            id: 'opt_half',
            name: 'Half (6 Pcs)',
            price: 80,
            pricingType: OptionPricingType.fixedPrice,
          ),
          MenuItemOption(
            id: 'opt_full',
            name: 'Full (12 Pcs)',
            price: 140,
            pricingType: OptionPricingType.fixedPrice,
          ),
        ],
      );

      const prepGroup = MenuItemOptionGroup(
        id: 'grp_prep',
        name: 'Preparation',
        options: [
          MenuItemOption(
            id: 'opt_dry',
            name: 'Dry',
            price: 0,
            pricingType: OptionPricingType.selectionOnly,
          ),
          MenuItemOption(
            id: 'opt_gravy',
            name: 'Gravy',
            price: 0,
            pricingType: OptionPricingType.selectionOnly,
          ),
        ],
      );

      const momosItem = MenuItem(
        id: 'momos_1',
        name: 'Chicken Momos',
        details: 'Served with sauce',
        price: 0,
        imageUrl: '',
        categoryId: 'momos',
        isVeg: false,
        isAvailable: true,
        isRecommended: true,
        sortOrder: 1,
        optionGroups: [portionGroup, prepGroup],
      );

      expect(momosItem.startingPrice, equals(80));
      expect(momosItem.formattedStartingPrice, equals('₹80'));
    });

    test('5. Fixed + PriceAdjustment (Coffee: Size Large ₹60/XL ₹80 + Ice Cream +₹0/+₹10) = ₹60', () {
      const sizeGroup = MenuItemOptionGroup(
        id: 'grp_size',
        name: 'Size',
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
          MenuItemOption(
            id: 'opt_xxl',
            name: 'Double XL',
            price: 100,
            pricingType: OptionPricingType.fixedPrice,
          ),
        ],
      );

      const iceCreamGroup = MenuItemOptionGroup(
        id: 'grp_addon',
        name: 'Ice Cream',
        options: [
          MenuItemOption(
            id: 'opt_none',
            name: 'No Ice Cream',
            price: 0,
            pricingType: OptionPricingType.priceAdjustment,
          ),
          MenuItemOption(
            id: 'opt_with',
            name: 'With Ice Cream',
            price: 10,
            pricingType: OptionPricingType.priceAdjustment,
          ),
        ],
      );

      const coffeeItem = MenuItem(
        id: 'coffee_1',
        name: 'Cold Coffee',
        details: 'Rich blend',
        price: 0,
        imageUrl: '',
        categoryId: 'beverages',
        isVeg: true,
        isAvailable: true,
        isRecommended: true,
        sortOrder: 1,
        optionGroups: [sizeGroup, iceCreamGroup],
      );

      expect(coffeeItem.startingPrice, equals(60));
      expect(coffeeItem.formattedStartingPrice, equals('₹60'));
    });

    test('6. Base Price + Adjustment-only (Pizza Base ₹150 + Cheese +₹20) uses base price as startingPrice', () {
      const cheeseGroup = MenuItemOptionGroup(
        id: 'grp_cheese',
        name: 'Add Cheese',
        options: [
          MenuItemOption(
            id: 'opt_regular',
            name: 'Regular Cheese',
            price: 0,
            pricingType: OptionPricingType.priceAdjustment,
          ),
          MenuItemOption(
            id: 'opt_extra',
            name: 'Extra Cheese',
            price: 20,
            pricingType: OptionPricingType.priceAdjustment,
          ),
        ],
      );

      const pizzaItem = MenuItem(
        id: 'pizza_1',
        name: 'Margherita Pizza',
        details: 'Cheesy crust',
        price: 150,
        imageUrl: '',
        categoryId: 'pizza',
        isVeg: true,
        isAvailable: true,
        isRecommended: false,
        sortOrder: 1,
        optionGroups: [cheeseGroup],
      );

      expect(pizzaItem.startingPrice, equals(150));
      expect(pizzaItem.formattedStartingPrice, equals('₹150'));
    });

    test('7. Base Price + SelectionOnly (Base ₹140 + Prep Dry/Gravy) = ₹140', () {
      const prepGroup = MenuItemOptionGroup(
        id: 'grp_prep',
        name: 'Preparation',
        options: [
          MenuItemOption(
            id: 'opt_dry',
            name: 'Dry',
            price: 0,
            pricingType: OptionPricingType.selectionOnly,
          ),
          MenuItemOption(
            id: 'opt_gravy',
            name: 'Gravy',
            price: 0,
            pricingType: OptionPricingType.selectionOnly,
          ),
        ],
      );

      const item = MenuItem(
        id: 'manchurian_1',
        name: 'Veg Manchurian',
        details: 'Spicy balls',
        price: 140,
        imageUrl: '',
        categoryId: 'chinese',
        isVeg: true,
        isAvailable: true,
        isRecommended: false,
        sortOrder: 1,
        optionGroups: [prepGroup],
      );

      expect(item.startingPrice, equals(140));
      expect(item.formattedStartingPrice, equals('₹140'));
    });

    test('8. MenuItemOption toMap & fromMap preserves selectionOnly', () {
      const opt = MenuItemOption(
        id: 'opt_gravy',
        name: 'Gravy',
        price: 50, // Should be normalized to 0 on toMap
        pricingType: OptionPricingType.selectionOnly,
      );

      final map = opt.toMap();
      expect(map['pricingType'], equals('selectionOnly'));
      expect(map['price'], equals(0));

      final restored = MenuItemOption.fromMap(map);
      expect(restored.pricingType, equals(OptionPricingType.selectionOnly));
      expect(restored.price, equals(0));
    });

    test('9. MenuItem toFirestore preserves all optionGroups structure with selectionOnly', () {
      const item = MenuItem(
        id: 'momos_1',
        name: 'Momos',
        details: 'Tasty',
        price: 0,
        imageUrl: '',
        categoryId: 'momos',
        isVeg: true,
        isAvailable: true,
        isRecommended: false,
        sortOrder: 1,
        optionGroups: [
          MenuItemOptionGroup(
            id: 'grp_prep',
            name: 'Preparation',
            options: [
              MenuItemOption(
                id: 'opt_dry',
                name: 'Dry',
                pricingType: OptionPricingType.selectionOnly,
              ),
            ],
          ),
        ],
      );

      final map = item.toFirestore();
      expect(map['optionGroups'], isA<List>());
      final groups = map['optionGroups'] as List;
      expect(groups.length, equals(1));
      expect(groups[0]['options'][0]['pricingType'], equals('selectionOnly'));
      expect(groups[0]['options'][0]['price'], equals(0));
    });
  });
}
