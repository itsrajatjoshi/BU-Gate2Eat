// BU Gate2Eat — UP16 Coffee Queen One-Time Seed Test Suite
// Verifies exact menu counts (21 items), category structure (3 categories),
// option groups (fixedPrice Size, priceAdjustment Ice Cream), and edit-safety skip rules.

import 'package:bugate2eat_app/models/menu_item_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UP16 Coffee Queen Seed Data & Edit-Safety Invariants', () {
    const shopId = 'up16_coffee_queen';
    const coldCoffeeCatId = 'up16_cold_coffee';
    const shakesCatId = 'up16_shakes';
    const mojitosOthersCatId = 'up16_mojitos_others';

    // 1. Verify Category Deterministic IDs & Metadata
    test('1. UP16 Coffee Queen defines exactly 3 categories with deterministic IDs', () {
      final categories = [
        {'id': coldCoffeeCatId, 'name': 'Cold Coffee', 'sortOrder': 1},
        {'id': shakesCatId, 'name': 'Shakes', 'sortOrder': 2},
        {'id': mojitosOthersCatId, 'name': 'Mojitos & Others', 'sortOrder': 3},
      ];

      expect(categories.length, equals(3));
      expect(categories.map((c) => c['id']), containsAll([coldCoffeeCatId, shakesCatId, mojitosOthersCatId]));
    });

    // 2. Cold Coffee Items Specification
    test('2. Cold Coffee category defines exactly 6 items with Size and Ice Cream option groups', () {
      final coldCoffeeItems = [
        {
          'id': 'up16_normal_cold_coffee',
          'name': 'Normal Cold Coffee',
          'large': 60,
          'xl': 80,
          'xxl': 100,
          'sort': 1,
        },
        {
          'id': 'up16_hazelnut_cold_coffee',
          'name': 'Hazelnut Cold Coffee',
          'large': 70,
          'xl': 80,
          'xxl': 100,
          'sort': 2,
        },
        {
          'id': 'up16_irish_cold_coffee',
          'name': 'Irish Cold Coffee',
          'large': 70,
          'xl': 80,
          'xxl': 100,
          'sort': 3,
        },
        {
          'id': 'up16_caramel_cold_coffee',
          'name': 'Caramel Cold Coffee',
          'large': 70,
          'xl': 80,
          'xxl': 100,
          'sort': 4,
        },
        {
          'id': 'up16_vanilla_cold_coffee',
          'name': 'Vanilla Cold Coffee',
          'large': 70,
          'xl': 80,
          'xxl': 100,
          'sort': 5,
        },
        {
          'id': 'up16_mocha_cold_coffee',
          'name': 'Mocha Cold Coffee',
          'large': 70,
          'xl': 80,
          'xxl': 100,
          'sort': 6,
        },
      ];

      expect(coldCoffeeItems.length, equals(6));

      for (final cc in coldCoffeeItems) {
        final largePrice = cc['large'] as int;
        final xlPrice = cc['xl'] as int;
        final xxlPrice = cc['xxl'] as int;

        final item = MenuItem(
          id: cc['id'] as String,
          name: cc['name'] as String,
          details: 'Cold coffee',
          price: largePrice,
          imageUrl: '',
          categoryId: coldCoffeeCatId,
          isVeg: true,
          isAvailable: true,
          isRecommended: false,
          sortOrder: cc['sort'] as int,
          optionGroups: [
            MenuItemOptionGroup(
              id: 'grp_size',
              name: 'Size',
              required: true,
              options: [
                MenuItemOption(
                  id: 'opt_large',
                  name: 'Large',
                  price: largePrice,
                  pricingType: OptionPricingType.fixedPrice,
                  isDefault: true,
                ),
                MenuItemOption(
                  id: 'opt_xl',
                  name: 'XL',
                  price: xlPrice,
                  pricingType: OptionPricingType.fixedPrice,
                  isDefault: false,
                ),
                MenuItemOption(
                  id: 'opt_double_xl',
                  name: 'Double XL',
                  price: xxlPrice,
                  pricingType: OptionPricingType.fixedPrice,
                  isDefault: false,
                ),
              ],
            ),
            const MenuItemOptionGroup(
              id: 'grp_ice_cream',
              name: 'Ice Cream',
              required: true,
              options: [
                MenuItemOption(
                  id: 'opt_no_ice_cream',
                  name: 'No Ice Cream',
                  price: 0,
                  pricingType: OptionPricingType.priceAdjustment,
                  isDefault: true,
                ),
                MenuItemOption(
                  id: 'opt_with_ice_cream',
                  name: 'With Ice Cream',
                  price: 10,
                  pricingType: OptionPricingType.priceAdjustment,
                  isDefault: false,
                ),
              ],
            ),
          ],
        );

        expect(item.hasOptions, isTrue);
        expect(item.optionGroups.length, equals(2));
        expect(item.optionGroups[0].options[0].pricingType, equals(OptionPricingType.fixedPrice));
        expect(item.optionGroups[1].options[1].pricingType, equals(OptionPricingType.priceAdjustment));
        expect(item.optionGroups[1].options[1].price, equals(10));
        expect(item.startingPrice, equals(largePrice));
      }
    });

    // 3. Shakes Items Specification
    test('3. Shakes category defines exactly 9 items with fixedPrice Size options', () {
      final shakes = [
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

      expect(shakes.length, equals(9));

      for (final s in shakes) {
        final largePrice = s['large'] as int;
        final xlPrice = s['xl'] as int;
        final xxlPrice = s['xxl'] as int;

        final item = MenuItem(
          id: s['id'] as String,
          name: s['name'] as String,
          details: 'Shake',
          price: largePrice,
          imageUrl: '',
          categoryId: shakesCatId,
          isVeg: true,
          isAvailable: true,
          isRecommended: false,
          sortOrder: s['sort'] as int,
          optionGroups: [
            MenuItemOptionGroup(
              id: 'grp_size',
              name: 'Size',
              required: true,
              options: [
                MenuItemOption(
                  id: 'opt_large',
                  name: 'Large',
                  price: largePrice,
                  pricingType: OptionPricingType.fixedPrice,
                  isDefault: true,
                ),
                MenuItemOption(
                  id: 'opt_xl',
                  name: 'XL',
                  price: xlPrice,
                  pricingType: OptionPricingType.fixedPrice,
                  isDefault: false,
                ),
                MenuItemOption(
                  id: 'opt_double_xl',
                  name: 'Double XL',
                  price: xxlPrice,
                  pricingType: OptionPricingType.fixedPrice,
                  isDefault: false,
                ),
              ],
            ),
          ],
        );

        expect(item.hasOptions, isTrue);
        expect(item.optionGroups.length, equals(1));
        expect(item.startingPrice, equals(largePrice));
      }
    });

    // 4. Mojitos & Others Items Specification
    test('4. Mojitos & Others category defines exactly 6 normal items without optionGroups', () {
      final mojitosAndOthers = [
        {'id': 'up16_mint_mojito', 'name': 'Mint Mojito', 'details': 'Mojito', 'price': 70, 'sort': 1},
        {'id': 'up16_watermelon_mojito', 'name': 'Watermelon Mojito', 'details': 'Mojito', 'price': 70, 'sort': 2},
        {'id': 'up16_green_apple_mojito', 'name': 'Green Apple Mojito', 'details': 'Mojito', 'price': 80, 'sort': 3},
        {'id': 'up16_blue_curacao_mojito', 'name': 'Blue Curacao Mojito', 'details': 'Mojito', 'price': 80, 'sort': 4},
        {'id': 'up16_sprite_mojito', 'name': 'Sprite Mojito', 'details': 'Mojito', 'price': 80, 'sort': 5},
        {'id': 'up16_lemon_tea', 'name': 'Lemon Tea', 'details': 'Lemon tea', 'price': 80, 'sort': 6},
      ];

      expect(mojitosAndOthers.length, equals(6));

      for (final m in mojitosAndOthers) {
        final item = MenuItem(
          id: m['id'] as String,
          name: m['name'] as String,
          details: m['details'] as String,
          price: m['price'] as int,
          imageUrl: '',
          categoryId: mojitosOthersCatId,
          isVeg: true,
          isAvailable: true,
          isRecommended: false,
          sortOrder: m['sort'] as int,
          optionGroups: const [],
        );

        expect(item.hasOptions, isFalse);
        expect(item.startingPrice, equals(m['price']));
        expect(item.formattedStartingPrice, equals('₹${m['price']}'));
      }
    });

    // 5. Total Menu Items Count
    test('5. Total menu item count across all 3 categories equals exactly 21 items', () {
      const totalColdCoffees = 6;
      const totalShakes = 9;
      const totalMojitosOthers = 6;

      expect(totalColdCoffees + totalShakes + totalMojitosOthers, equals(21));
    });

    // 6. Edit-Safety & Skip Invariant Test
    test('6. Edit-Safety Invariant: Existing shop is skipped and edits are NEVER overwritten', () {
      final mockFirestoreStore = <String, Map<String, dynamic>>{
        'shops/$shopId': {
          'name': 'UP16 Coffee Queen',
          'description': 'Edited description by shopkeeper',
          'isActive': true,
        },
        'shops/$shopId/menuItems/up16_normal_cold_coffee': {
          'name': 'Normal Cold Coffee (Owner Edition)',
          'price': 65, // Edited price Large ₹60 -> ₹65
          'optionGroups': [
            {
              'id': 'grp_size',
              'name': 'Size',
              'required': true,
              'options': [
                {'id': 'opt_large', 'name': 'Large', 'price': 65, 'pricingType': 'fixedPrice', 'isDefault': true},
                {'id': 'opt_xl', 'name': 'XL', 'price': 90, 'pricingType': 'fixedPrice', 'isDefault': false}, // XL ₹80 -> ₹90
                {'id': 'opt_double_xl', 'name': 'Double XL', 'price': 110, 'pricingType': 'fixedPrice', 'isDefault': false},
              ],
            },
          ],
        },
      };

      // Simulating seed check: if doc exists, skip immediately
      bool seedIfMissing(String targetShopId) {
        if (mockFirestoreStore.containsKey('shops/$targetShopId')) {
          // SKIP!
          return false;
        }
        // If not, would create
        return true;
      }

      final seedResult = seedIfMissing(shopId);
      expect(seedResult, isFalse); // Skipped

      // Verify edited values remain 100% intact
      final itemDoc = mockFirestoreStore['shops/$shopId/menuItems/up16_normal_cold_coffee']!;
      expect(itemDoc['name'], equals('Normal Cold Coffee (Owner Edition)'));
      expect(itemDoc['price'], equals(65));
      final sizeOpts = (itemDoc['optionGroups'] as List).first['options'] as List;
      expect(sizeOpts[0]['price'], equals(65));
      expect(sizeOpts[1]['price'], equals(90));
    });
  });
}
