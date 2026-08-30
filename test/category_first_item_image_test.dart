// BU Gate2Eat — Checkpoint 3.6 Category First Item Image Tests
// Verifies that Category Thumbnails ALWAYS dynamically resolve their image
// from the FIRST menu item belonging to that category in that shop's menu.

import 'package:bugate2eat_app/features/shop/shop_detail_screen.dart';
import 'package:bugate2eat_app/models/category_model.dart';
import 'package:bugate2eat_app/models/menu_item_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const momosCat = Category(
    id: 'momos',
    name: 'Momos',
    sortOrder: 1,
    imageUrl: 'https://placeholder.com/momos_category_old.jpg',
    isActive: true,
  );

  const burgersCat = Category(
    id: 'burgers',
    name: 'Burgers',
    sortOrder: 2,
    imageUrl: 'https://placeholder.com/burgers_category_old.jpg',
    isActive: true,
  );

  const momoItem1 = MenuItem(
    id: 'momo_veg_steam',
    name: 'Veg Steam Momos',
    details: 'Fresh steamed momos',
    price: 80,
    imageUrl: 'https://cdn.yummbu.com/images/veg_steam_momos.jpg',
    categoryId: 'momos',
    isVeg: true,
    isAvailable: true,
    isRecommended: true,
    sortOrder: 1,
  );

  const momoItem2 = MenuItem(
    id: 'momo_paneer_fried',
    name: 'Paneer Fried Momos',
    details: 'Crispy fried momos',
    price: 120,
    imageUrl: 'https://cdn.yummbu.com/images/paneer_fried_momos.jpg',
    categoryId: 'momos',
    isVeg: true,
    isAvailable: true,
    isRecommended: false,
    sortOrder: 2,
  );

  const burgerItem1 = MenuItem(
    id: 'burger_crispy_veg',
    name: 'Crispy Veg Burger',
    details: 'Loaded with lettuce and sauces',
    price: 90,
    imageUrl: 'https://cdn.yummbu.com/images/crispy_veg_burger.jpg',
    categoryId: 'burgers',
    isVeg: true,
    isAvailable: true,
    isRecommended: true,
    sortOrder: 1,
  );

  const burgerItem2 = MenuItem(
    id: 'burger_cheese_burst',
    name: 'Cheese Burst Burger',
    details: 'Double cheese slice',
    price: 130,
    imageUrl: 'https://cdn.yummbu.com/images/cheese_burst_burger.jpg',
    categoryId: 'burgers',
    isVeg: true,
    isAvailable: true,
    isRecommended: false,
    sortOrder: 2,
  );

  group('Checkpoint 3.6 — Category Thumbnail = First Item Image Tests', () {
    test('1. Category uses the FIRST item image belonging to that category', () {
      final List<MenuItem> menuItems = [momoItem1, momoItem2, burgerItem1, burgerItem2];
      final List<Category> categories = [momosCat, burgersCat];

      // Call ShopDetailScreen's effective categories helper
      final effectiveCats = ShopDetailScreenTestHelper.getEffectiveCategories(
        'shop_1',
        categories,
        menuItems,
      );

      final resolvedMomosCat = effectiveCats.firstWhere((c) => c.id == 'momos');
      final resolvedBurgersCat = effectiveCats.firstWhere((c) => c.id == 'burgers');

      // Momos thumbnail must be momoItem1's image (Veg Steam Momos), NOT momoItem2 or placeholder
      expect(resolvedMomosCat.imageUrl, equals('https://cdn.yummbu.com/images/veg_steam_momos.jpg'));
      expect(resolvedMomosCat.imageUrl, isNot(equals('https://cdn.yummbu.com/images/paneer_fried_momos.jpg')));
      expect(resolvedMomosCat.imageUrl, isNot(equals('https://placeholder.com/momos_category_old.jpg')));

      // Burgers thumbnail must be burgerItem1's image (Crispy Veg Burger)
      expect(resolvedBurgersCat.imageUrl, equals('https://cdn.yummbu.com/images/crispy_veg_burger.jpg'));
      expect(resolvedBurgersCat.imageUrl, isNot(equals('https://cdn.yummbu.com/images/cheese_burst_burger.jpg')));
    });

    test('2. Changing the first item image dynamically updates category thumbnail', () {
      // Simulate shopkeeper updating Veg Steam Momos image
      const updatedMomoItem1 = MenuItem(
        id: 'momo_veg_steam',
        name: 'Veg Steam Momos',
        details: 'Fresh steamed momos',
        price: 80,
        imageUrl: 'https://cdn.yummbu.com/images/veg_steam_momos_NEW_PHOTO.jpg',
        categoryId: 'momos',
        isVeg: true,
        isAvailable: true,
        isRecommended: true,
        sortOrder: 1,
      );

      final List<MenuItem> menuItems = [updatedMomoItem1, momoItem2, burgerItem1];
      final List<Category> categories = [momosCat, burgersCat];

      final effectiveCats = ShopDetailScreenTestHelper.getEffectiveCategories(
        'shop_1',
        categories,
        menuItems,
      );

      final resolvedMomosCat = effectiveCats.firstWhere((c) => c.id == 'momos');
      expect(resolvedMomosCat.imageUrl, equals('https://cdn.yummbu.com/images/veg_steam_momos_NEW_PHOTO.jpg'));
    });

    test('3. Deleting first item causes second item to become first and updates category thumbnail', () {
      // Veg Steam Momos was deleted, so Paneer Fried Momos is now first
      final List<MenuItem> menuItems = [momoItem2, burgerItem1];
      final List<Category> categories = [momosCat, burgersCat];

      final effectiveCats = ShopDetailScreenTestHelper.getEffectiveCategories(
        'shop_1',
        categories,
        menuItems,
      );

      final resolvedMomosCat = effectiveCats.firstWhere((c) => c.id == 'momos');
      // Must automatically become Paneer Fried Momos image
      expect(resolvedMomosCat.imageUrl, equals('https://cdn.yummbu.com/images/paneer_fried_momos.jpg'));
    });

    test('4. Shop isolation: Same category in Shop A and Shop B resolve images independently', () {
      const shopAMomoItem = MenuItem(
        id: 'shop_a_momo',
        name: 'Shop A Special Momos',
        details: '',
        price: 90,
        imageUrl: 'https://cdn.yummbu.com/images/shop_a_momos.jpg',
        categoryId: 'momos',
        isVeg: true,
        isAvailable: true,
        isRecommended: false,
        sortOrder: 1,
      );

      const shopBMomoItem = MenuItem(
        id: 'shop_b_momo',
        name: 'Shop B Royal Momos',
        details: '',
        price: 110,
        imageUrl: 'https://cdn.yummbu.com/images/shop_b_momos.jpg',
        categoryId: 'momos',
        isVeg: true,
        isAvailable: true,
        isRecommended: false,
        sortOrder: 1,
      );

      final shopACats = ShopDetailScreenTestHelper.getEffectiveCategories(
        'shop_A',
        [momosCat],
        [shopAMomoItem],
      );

      final shopBCats = ShopDetailScreenTestHelper.getEffectiveCategories(
        'shop_B',
        [momosCat],
        [shopBMomoItem],
      );

      expect(shopACats.firstWhere((c) => c.id == 'momos').imageUrl, equals('https://cdn.yummbu.com/images/shop_a_momos.jpg'));
      expect(shopBCats.firstWhere((c) => c.id == 'momos').imageUrl, equals('https://cdn.yummbu.com/images/shop_b_momos.jpg'));
    });

    test('5. Empty category with no available items is omitted from customer tab without crashing', () {
      final List<MenuItem> menuItems = [burgerItem1];
      final List<Category> categories = [momosCat, burgersCat]; // momos has no items in menuItems

      final effectiveCats = ShopDetailScreenTestHelper.getEffectiveCategories(
        'shop_1',
        categories,
        menuItems,
      );

      // Momos should not be in effective categories
      expect(effectiveCats.any((c) => c.id == 'momos'), isFalse);
      // Burgers is present
      expect(effectiveCats.any((c) => c.id == 'burgers'), isTrue);
    });

    test('6. "All" category thumbnail uses first item of the shop menu', () {
      final List<MenuItem> menuItems = [momoItem1, burgerItem1];
      final List<Category> categories = [momosCat, burgersCat];

      final effectiveCats = ShopDetailScreenTestHelper.getEffectiveCategories(
        'shop_1',
        categories,
        menuItems,
      );

      final allCat = effectiveCats.firstWhere((c) => c.id == 'all');
      expect(allCat.imageUrl, equals(momoItem1.imageUrl));
    });
  });
}
