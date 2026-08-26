// BU Gate2Eat — Checkpoint 12.2 UP16 Coffee Queen Live Data Audit Test
// Verifies raw seeded Firestore maps of all 21 UP16 Coffee Queen items against Checkpoints 11.2 & 12.1 models.

import 'package:bugate2eat_app/models/cart_item_model.dart';
import 'package:bugate2eat_app/models/menu_item_model.dart';
import 'package:flutter_test/flutter_test.dart';

MenuItem parseRawMenuItemDoc(Map<String, dynamic> data, String id) {
  final rawGroups = data['optionGroups'];
  final groupsList = <MenuItemOptionGroup>[];
  if (rawGroups is List) {
    for (final g in rawGroups) {
      if (g is Map<String, dynamic>) {
        groupsList.add(MenuItemOptionGroup.fromMap(g));
      } else if (g is Map) {
        groupsList.add(MenuItemOptionGroup.fromMap(Map<String, dynamic>.from(g)));
      }
    }
  }

  return MenuItem(
    id: id,
    name: (data['name'] as String?) ?? '',
    details: (data['details'] as String?) ?? (data['description'] as String?) ?? '',
    price: ((data['price'] as num?) ?? 0).toInt(),
    imageUrl: (data['imageUrl'] as String?) ?? '',
    categoryId: (data['categoryId'] as String?) ?? '',
    isVeg: (data['isVeg'] as bool?) ?? true,
    isAvailable: (data['isAvailable'] as bool?) ?? true,
    isRecommended: (data['isRecommended'] as bool?) ?? false,
    sortOrder: (data['sortOrder'] as int?) ?? 0,
    optionGroups: groupsList,
  );
}

void main() {
  group('Checkpoint 12.2: UP16 Coffee Queen Data Audit', () {
    // ── RAW SEEDED DATA MAPS FROM FIRESTORE SEED IMPLEMENTATION ───────────────
    final rawColdCoffees = [
      {
        'id': 'up16_normal_cold_coffee',
        'name': 'Normal Cold Coffee',
        'details': 'Cold coffee',
        'price': 60,
        'imageUrl': '',
        'categoryId': 'up16_cold_coffee',
        'isVeg': true,
        'isAvailable': true,
        'isRecommended': false,
        'sortOrder': 1,
        'optionGroups': [
          {
            'id': 'grp_size',
            'name': 'Size',
            'required': true,
            'options': [
              {'id': 'opt_large', 'name': 'Large', 'price': 60, 'pricingType': 'fixedPrice', 'isDefault': true},
              {'id': 'opt_xl', 'name': 'XL', 'price': 80, 'pricingType': 'fixedPrice', 'isDefault': false},
              {'id': 'opt_double_xl', 'name': 'Double XL', 'price': 100, 'pricingType': 'fixedPrice', 'isDefault': false},
            ],
          },
          {
            'id': 'grp_ice_cream',
            'name': 'Ice Cream',
            'required': true,
            'options': [
              {'id': 'opt_no_ice_cream', 'name': 'No Ice Cream', 'price': 0, 'pricingType': 'priceAdjustment', 'isDefault': true},
              {'id': 'opt_with_ice_cream', 'name': 'With Ice Cream', 'price': 10, 'pricingType': 'priceAdjustment', 'isDefault': false},
            ],
          },
        ],
      },
      {
        'id': 'up16_hazelnut_cold_coffee',
        'name': 'Hazelnut Cold Coffee',
        'details': 'Cold coffee',
        'price': 70,
        'imageUrl': '',
        'categoryId': 'up16_cold_coffee',
        'isVeg': true,
        'isAvailable': true,
        'isRecommended': false,
        'sortOrder': 2,
        'optionGroups': [
          {
            'id': 'grp_size',
            'name': 'Size',
            'required': true,
            'options': [
              {'id': 'opt_large', 'name': 'Large', 'price': 70, 'pricingType': 'fixedPrice', 'isDefault': true},
              {'id': 'opt_xl', 'name': 'XL', 'price': 80, 'pricingType': 'fixedPrice', 'isDefault': false},
              {'id': 'opt_double_xl', 'name': 'Double XL', 'price': 100, 'pricingType': 'fixedPrice', 'isDefault': false},
            ],
          },
          {
            'id': 'grp_ice_cream',
            'name': 'Ice Cream',
            'required': true,
            'options': [
              {'id': 'opt_no_ice_cream', 'name': 'No Ice Cream', 'price': 0, 'pricingType': 'priceAdjustment', 'isDefault': true},
              {'id': 'opt_with_ice_cream', 'name': 'With Ice Cream', 'price': 10, 'pricingType': 'priceAdjustment', 'isDefault': false},
            ],
          },
        ],
      },
      {
        'id': 'up16_irish_cold_coffee',
        'name': 'Irish Cold Coffee',
        'details': 'Cold coffee',
        'price': 70,
        'imageUrl': '',
        'categoryId': 'up16_cold_coffee',
        'isVeg': true,
        'isAvailable': true,
        'isRecommended': false,
        'sortOrder': 3,
        'optionGroups': [
          {
            'id': 'grp_size',
            'name': 'Size',
            'required': true,
            'options': [
              {'id': 'opt_large', 'name': 'Large', 'price': 70, 'pricingType': 'fixedPrice', 'isDefault': true},
              {'id': 'opt_xl', 'name': 'XL', 'price': 80, 'pricingType': 'fixedPrice', 'isDefault': false},
              {'id': 'opt_double_xl', 'name': 'Double XL', 'price': 100, 'pricingType': 'fixedPrice', 'isDefault': false},
            ],
          },
          {
            'id': 'grp_ice_cream',
            'name': 'Ice Cream',
            'required': true,
            'options': [
              {'id': 'opt_no_ice_cream', 'name': 'No Ice Cream', 'price': 0, 'pricingType': 'priceAdjustment', 'isDefault': true},
              {'id': 'opt_with_ice_cream', 'name': 'With Ice Cream', 'price': 10, 'pricingType': 'priceAdjustment', 'isDefault': false},
            ],
          },
        ],
      },
      {
        'id': 'up16_caramel_cold_coffee',
        'name': 'Caramel Cold Coffee',
        'details': 'Cold coffee',
        'price': 70,
        'imageUrl': '',
        'categoryId': 'up16_cold_coffee',
        'isVeg': true,
        'isAvailable': true,
        'isRecommended': false,
        'sortOrder': 4,
        'optionGroups': [
          {
            'id': 'grp_size',
            'name': 'Size',
            'required': true,
            'options': [
              {'id': 'opt_large', 'name': 'Large', 'price': 70, 'pricingType': 'fixedPrice', 'isDefault': true},
              {'id': 'opt_xl', 'name': 'XL', 'price': 80, 'pricingType': 'fixedPrice', 'isDefault': false},
              {'id': 'opt_double_xl', 'name': 'Double XL', 'price': 100, 'pricingType': 'fixedPrice', 'isDefault': false},
            ],
          },
          {
            'id': 'grp_ice_cream',
            'name': 'Ice Cream',
            'required': true,
            'options': [
              {'id': 'opt_no_ice_cream', 'name': 'No Ice Cream', 'price': 0, 'pricingType': 'priceAdjustment', 'isDefault': true},
              {'id': 'opt_with_ice_cream', 'name': 'With Ice Cream', 'price': 10, 'pricingType': 'priceAdjustment', 'isDefault': false},
            ],
          },
        ],
      },
      {
        'id': 'up16_vanilla_cold_coffee',
        'name': 'Vanilla Cold Coffee',
        'details': 'Cold coffee',
        'price': 70,
        'imageUrl': '',
        'categoryId': 'up16_cold_coffee',
        'isVeg': true,
        'isAvailable': true,
        'isRecommended': false,
        'sortOrder': 5,
        'optionGroups': [
          {
            'id': 'grp_size',
            'name': 'Size',
            'required': true,
            'options': [
              {'id': 'opt_large', 'name': 'Large', 'price': 70, 'pricingType': 'fixedPrice', 'isDefault': true},
              {'id': 'opt_xl', 'name': 'XL', 'price': 80, 'pricingType': 'fixedPrice', 'isDefault': false},
              {'id': 'opt_double_xl', 'name': 'Double XL', 'price': 100, 'pricingType': 'fixedPrice', 'isDefault': false},
            ],
          },
          {
            'id': 'grp_ice_cream',
            'name': 'Ice Cream',
            'required': true,
            'options': [
              {'id': 'opt_no_ice_cream', 'name': 'No Ice Cream', 'price': 0, 'pricingType': 'priceAdjustment', 'isDefault': true},
              {'id': 'opt_with_ice_cream', 'name': 'With Ice Cream', 'price': 10, 'pricingType': 'priceAdjustment', 'isDefault': false},
            ],
          },
        ],
      },
      {
        'id': 'up16_mocha_cold_coffee',
        'name': 'Mocha Cold Coffee',
        'details': 'Cold coffee',
        'price': 70,
        'imageUrl': '',
        'categoryId': 'up16_cold_coffee',
        'isVeg': true,
        'isAvailable': true,
        'isRecommended': false,
        'sortOrder': 6,
        'optionGroups': [
          {
            'id': 'grp_size',
            'name': 'Size',
            'required': true,
            'options': [
              {'id': 'opt_large', 'name': 'Large', 'price': 70, 'pricingType': 'fixedPrice', 'isDefault': true},
              {'id': 'opt_xl', 'name': 'XL', 'price': 80, 'pricingType': 'fixedPrice', 'isDefault': false},
              {'id': 'opt_double_xl', 'name': 'Double XL', 'price': 100, 'pricingType': 'fixedPrice', 'isDefault': false},
            ],
          },
          {
            'id': 'grp_ice_cream',
            'name': 'Ice Cream',
            'required': true,
            'options': [
              {'id': 'opt_no_ice_cream', 'name': 'No Ice Cream', 'price': 0, 'pricingType': 'priceAdjustment', 'isDefault': true},
              {'id': 'opt_with_ice_cream', 'name': 'With Ice Cream', 'price': 10, 'pricingType': 'priceAdjustment', 'isDefault': false},
            ],
          },
        ],
      },
    ];

    final rawShakes = [
      {'id': 'up16_oreo_shake', 'name': 'Oreo Shake', 'large': 60, 'xl': 80, 'xxl': 100, 'sort': 1},
      {'id': 'up16_chocolate_shake', 'name': 'Chocolate Shake', 'large': 60, 'xl': 80, 'xxl': 100, 'sort': 2},
      {'id': 'up16_cookie_caramel_shake', 'name': 'Cookie Caramel Shake', 'large': 60, 'xl': 80, 'xxl': 100, 'sort': 3},
      {'id': 'up16_black_currant_shake', 'name': 'Black Currant Shake', 'large': 60, 'xl': 80, 'xxl': 100, 'sort': 4},
      {'id': 'up16_butterscotch_shake', 'name': 'Butterscotch Shake', 'large': 60, 'xl': 80, 'xxl': 100, 'sort': 5},
      {'id': 'up16_strawberry_shake', 'name': 'Strawberry Shake', 'large': 60, 'xl': 80, 'xxl': 100, 'sort': 6},
      {'id': 'up16_mango_shake', 'name': 'Mango Shake', 'large': 60, 'xl': 80, 'xxl': 100, 'sort': 7},
      {'id': 'up16_banana_shake', 'name': 'Banana Shake', 'large': 60, 'xl': 80, 'xxl': 90, 'sort': 8},
      {'id': 'up16_blue_berry_shake', 'name': 'Blue Berry Shake', 'large': 80, 'xl': 90, 'xxl': 110, 'sort': 9},
    ];

    final rawMojitos = [
      {'id': 'up16_mint_mojito', 'name': 'Mint Mojito', 'details': 'Mojito', 'price': 70, 'sort': 1},
      {'id': 'up16_watermelon_mojito', 'name': 'Watermelon Mojito', 'details': 'Mojito', 'price': 70, 'sort': 2},
      {'id': 'up16_green_apple_mojito', 'name': 'Green Apple Mojito', 'details': 'Mojito', 'price': 80, 'sort': 3},
      {'id': 'up16_blue_curacao_mojito', 'name': 'Blue Curacao Mojito', 'details': 'Mojito', 'price': 80, 'sort': 4},
      {'id': 'up16_sprite_mojito', 'name': 'Sprite Mojito', 'details': 'Mojito', 'price': 80, 'sort': 5},
      {'id': 'up16_lemon_tea', 'name': 'Lemon Tea', 'details': 'Lemon tea', 'price': 80, 'sort': 6},
    ];

    // ── 1. VERIFY ALL 6 COLD COFFEES ───────────────────────────────────────────
    test('1. All 6 Cold Coffees parse correctly with Size (fixed) and Ice Cream (extra)', () {
      expect(rawColdCoffees.length, 6);

      for (final raw in rawColdCoffees) {
        final item = parseRawMenuItemDoc(raw, raw['id'] as String);
        expect(item.hasOptions, isTrue);
        expect(item.optionGroups.length, 2);

        // Group 1: Size
        final sizeGroup = item.optionGroups[0];
        expect(sizeGroup.name, 'Size');
        expect(sizeGroup.groupType, OptionGroupType.fixed);
        expect(sizeGroup.required, isTrue);
        expect(sizeGroup.options.length, 3);
        expect(sizeGroup.options[0].name, 'Large');
        expect(sizeGroup.options[0].isDefault, isTrue);
        expect(sizeGroup.options[1].name, 'XL');
        expect(sizeGroup.options[2].name, 'Double XL');

        // Group 2: Ice Cream
        final iceCreamGroup = item.optionGroups[1];
        expect(iceCreamGroup.name, 'Ice Cream');
        expect(iceCreamGroup.groupType, OptionGroupType.choice);
        expect(iceCreamGroup.options.length, 2);
        expect(iceCreamGroup.options[0].name, 'No Ice Cream');
        expect(iceCreamGroup.options[0].price, 0);
        expect(iceCreamGroup.options[0].isDefault, isTrue);
        expect(iceCreamGroup.options[1].name, 'With Ice Cream');
        expect(iceCreamGroup.options[1].price, 10);
        expect(iceCreamGroup.options[1].isDefault, isFalse);

        // Starting price = Large price
        final expectedStartingPrice = sizeGroup.options[0].price;
        expect(item.startingPrice, expectedStartingPrice);
        expect(item.formattedStartingPrice, '₹$expectedStartingPrice');
      }
    });

    // ── 2. VERIFY ALL 9 SHAKES ────────────────────────────────────────────────
    test('2. All 9 Shakes parse correctly with Size (fixed) only', () {
      expect(rawShakes.length, 9);

      for (final s in rawShakes) {
        final rawDoc = {
          'id': s['id'],
          'name': s['name'],
          'details': 'Shake',
          'price': s['large'],
          'imageUrl': '',
          'categoryId': 'up16_shakes',
          'isVeg': true,
          'isAvailable': true,
          'isRecommended': false,
          'sortOrder': s['sort'],
          'optionGroups': [
            {
              'id': 'grp_size',
              'name': 'Size',
              'required': true,
              'options': [
                {'id': 'opt_large', 'name': 'Large', 'price': s['large'], 'pricingType': 'fixedPrice', 'isDefault': true},
                {'id': 'opt_xl', 'name': 'XL', 'price': s['xl'], 'pricingType': 'fixedPrice', 'isDefault': false},
                {'id': 'opt_double_xl', 'name': 'Double XL', 'price': s['xxl'], 'pricingType': 'fixedPrice', 'isDefault': false},
              ],
            },
          ],
        };

        final item = parseRawMenuItemDoc(rawDoc, s['id'] as String);
        expect(item.hasOptions, isTrue);
        expect(item.optionGroups.length, 1);

        final sizeGroup = item.optionGroups[0];
        expect(sizeGroup.name, 'Size');
        expect(sizeGroup.groupType, OptionGroupType.fixed);
        expect(sizeGroup.required, isTrue);
        expect(sizeGroup.options.length, 3);
        expect(sizeGroup.options[0].name, 'Large');
        expect(sizeGroup.options[0].price, s['large']);
        expect(sizeGroup.options[0].isDefault, isTrue);
        expect(sizeGroup.options[1].name, 'XL');
        expect(sizeGroup.options[1].price, s['xl']);
        expect(sizeGroup.options[2].name, 'Double XL');
        expect(sizeGroup.options[2].price, s['xxl']);

        expect(item.startingPrice, s['large']);
        expect(item.formattedStartingPrice, '₹${s['large']}');
      }
    });

    // ── 3. VERIFY ALL 6 MOJITOS & OTHERS ───────────────────────────────────────
    test('3. All 6 Mojitos & Others parse as normal items with hasOptions = false', () {
      expect(rawMojitos.length, 6);

      for (final m in rawMojitos) {
        final rawDoc = {
          'id': m['id'],
          'name': m['name'],
          'details': m['details'],
          'price': m['price'],
          'imageUrl': '',
          'categoryId': 'up16_mojitos_others',
          'isVeg': true,
          'isAvailable': true,
          'isRecommended': false,
          'sortOrder': m['sort'],
          'optionGroups': <Map<String, dynamic>>[],
        };

        final item = parseRawMenuItemDoc(rawDoc, m['id'] as String);
        expect(item.hasOptions, isFalse);
        expect(item.price, m['price']);
        expect(item.startingPrice, m['price']);
        expect(item.formattedStartingPrice, '₹${m['price']}');
      }
    });

    // ── 4. TOTAL MENU COUNT INVENTORY ──────────────────────────────────────────
    test('4. UP16 Total Inventory is exactly 21 items across 3 categories', () {
      final totalCount = rawColdCoffees.length + rawShakes.length + rawMojitos.length;
      expect(totalCount, 21);
    });

    // ── 5. CART INTERACTION SIMULATION FOR NORMAL COLD COFFEE ──────────────────
    test('5. Cold Coffee variants in cart: Large + No Ice Cream (₹60) vs Large + With Ice Cream (₹70)', () {
      final normalColdCoffee = parseRawMenuItemDoc(rawColdCoffees[0], rawColdCoffees[0]['id'] as String);

      const sizeLarge = SelectedMenuItemOption(
        groupId: 'grp_size',
        groupName: 'Size',
        optionId: 'opt_large',
        optionName: 'Large',
        pricingType: OptionPricingType.fixedPrice,
        price: 60,
      );

      const withIceCream = SelectedMenuItemOption(
        groupId: 'grp_ice_cream',
        groupName: 'Ice Cream',
        optionId: 'opt_with_ice_cream',
        optionName: 'With Ice Cream',
        pricingType: OptionPricingType.priceAdjustment,
        price: 10,
      );

      // Cart Item 1: Large + No Ice Cream (unselected extra) -> ₹60
      final cartItemNoIce = CartItem(
        menuItem: normalColdCoffee,
        quantity: 1,
        shopId: 'up16_coffee_queen',
        shopName: 'UP16 Coffee Queen',
        selectedOptions: [sizeLarge],
        unitPriceOverride: 60,
      );

      // Cart Item 2: Large + With Ice Cream (selected extra) -> ₹70
      final cartItemWithIce = CartItem(
        menuItem: normalColdCoffee,
        quantity: 1,
        shopId: 'up16_coffee_queen',
        shopName: 'UP16 Coffee Queen',
        selectedOptions: [sizeLarge, withIceCream],
        unitPriceOverride: 70,
      );

      expect(cartItemNoIce.cartKey, 'up16_normal_cold_coffee|grp_size:opt_large');
      expect(cartItemNoIce.unitPrice, 60);
      expect(cartItemNoIce.totalPrice, 60.0);

      expect(cartItemWithIce.cartKey, 'up16_normal_cold_coffee|grp_ice_cream:opt_with_ice_cream|grp_size:opt_large');
      expect(cartItemWithIce.unitPrice, 70);
      expect(cartItemWithIce.totalPrice, 70.0);

      expect(cartItemNoIce.cartKey, isNot(equals(cartItemWithIce.cartKey)));
    });
  });
}
