// BU Gate2Eat — Back Navigation & Shop Card Slideshow QA Regression Tests
// Tests Android Back Button routing & Exact Slideshow Image Resolution Rules

import 'package:bugate2eat_app/core/constants/app_constants.dart';
import 'package:bugate2eat_app/core/providers.dart';
import 'package:bugate2eat_app/features/cart/cart_provider.dart';
import 'package:bugate2eat_app/features/cart/cart_screen.dart';
import 'package:bugate2eat_app/features/favourites/favourites_screen.dart';
import 'package:bugate2eat_app/features/home/home_screen.dart';
import 'package:bugate2eat_app/features/orders/order_history_screen.dart';
import 'package:bugate2eat_app/models/category_model.dart';
import 'package:bugate2eat_app/models/menu_item_model.dart';
import 'package:bugate2eat_app/models/shop_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('QA Bug 1: Android Back Navigation Tests', () {
    testWidgets('1. Android back from Favourites tab returns to Home tab',
        (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: HomeScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap Favourites tab (index 1)
      await tester.tap(find.text('Favourites'));
      await tester.pumpAndSettle();

      // Verify we are on Favourites tab
      final navBar = tester.widget<BottomNavigationBar>(find.byType(BottomNavigationBar));
      expect(navBar.currentIndex, equals(1));

      // Simulate Android back button invocation
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      // Must now be on Home tab (index 0)
      final navBarAfterBack = tester.widget<BottomNavigationBar>(find.byType(BottomNavigationBar));
      expect(navBarAfterBack.currentIndex, equals(0));
    });

    testWidgets('2. Android back from Cart tab returns to Home tab',
        (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: HomeScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap Cart tab (index 2)
      await tester.tap(find.text('Cart'));
      await tester.pumpAndSettle();

      final navBar = tester.widget<BottomNavigationBar>(find.byType(BottomNavigationBar));
      expect(navBar.currentIndex, equals(2));

      // Simulate Android back button
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      final navBarAfterBack = tester.widget<BottomNavigationBar>(find.byType(BottomNavigationBar));
      expect(navBarAfterBack.currentIndex, equals(0));
    });

    testWidgets('3. Android back from Orders tab returns to Home tab',
        (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: HomeScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap Orders tab (index 3)
      await tester.tap(find.text('Orders'));
      await tester.pumpAndSettle();

      final navBar = tester.widget<BottomNavigationBar>(find.byType(BottomNavigationBar));
      expect(navBar.currentIndex, equals(3));

      // Simulate Android back button
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      final navBarAfterBack = tester.widget<BottomNavigationBar>(find.byType(BottomNavigationBar));
      expect(navBarAfterBack.currentIndex, equals(0));
    });

    testWidgets('4. Android back on Home tab preserves default canPop = true exit behavior',
        (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: HomeScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final popScopeFinder = find.byWidgetPredicate((w) => w is PopScope);
      expect(popScopeFinder, findsWidgets);

      final popScope = tester.widgetList(popScopeFinder).firstWhere((w) => w is PopScope) as PopScope;
      expect(popScope.canPop, isTrue);
    });
  });

  group('QA Bug 2: Shop Card Slideshow Image Count & Rule Tests', () {
    final testShop = Shop(
      id: 'up16_coffee',
      name: 'UP16 Coffee Queen',
      description: 'Coffee & Snacks',
      bannerUrl: 'https://cdn.yummbu.com/images/up16_banner.jpg',
      contactNumber: '919999999999',
      orderNumber: '919999999999',
      openTime: '08:00',
      closeTime: '23:00',
      isClosedOverride: false,
      isActive: true,
      sortOrder: 1,
      searchKeywords: ['coffee'],
      deliveryNote: '',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    const cat1 = Category(
      id: 'cat_coffee',
      name: 'Coffee',
      sortOrder: 1,
      imageUrl: '',
      isActive: true,
    );

    const cat2 = Category(
      id: 'cat_shakes',
      name: 'Shakes',
      sortOrder: 2,
      imageUrl: '',
      isActive: true,
    );

    const cat3 = Category(
      id: 'cat_snacks',
      name: 'Snacks',
      sortOrder: 3,
      imageUrl: '',
      isActive: true,
    );

    const cat4 = Category(
      id: 'cat_dessert',
      name: 'Desserts',
      sortOrder: 4,
      imageUrl: '',
      isActive: true,
    );

    const item1 = MenuItem(
      id: 'coffee_1',
      name: 'Cold Coffee',
      details: 'Chilled coffee',
      price: 60,
      imageUrl: 'https://cdn.yummbu.com/images/cold_coffee.jpg',
      categoryId: 'cat_coffee',
      isVeg: true,
      isAvailable: true,
      isRecommended: true,
      sortOrder: 1,
    );

    const item1Extra = MenuItem(
      id: 'coffee_2',
      name: 'Hot Coffee',
      details: 'Hot espresso',
      price: 50,
      imageUrl: 'https://cdn.yummbu.com/images/hot_coffee.jpg',
      categoryId: 'cat_coffee',
      isVeg: true,
      isAvailable: true,
      isRecommended: false,
      sortOrder: 2,
    );

    const item2 = MenuItem(
      id: 'shake_1',
      name: 'Oreo Shake',
      details: 'Thick shake',
      price: 90,
      imageUrl: 'https://cdn.yummbu.com/images/oreo_shake.jpg',
      categoryId: 'cat_shakes',
      isVeg: true,
      isAvailable: true,
      isRecommended: true,
      sortOrder: 1,
    );

    const item3 = MenuItem(
      id: 'snack_1',
      name: 'French Fries',
      details: 'Crispy fries',
      price: 70,
      imageUrl: 'https://cdn.yummbu.com/images/fries.jpg',
      categoryId: 'cat_snacks',
      isVeg: true,
      isAvailable: true,
      isRecommended: true,
      sortOrder: 1,
    );

    const item4 = MenuItem(
      id: 'dessert_1',
      name: 'Brownie',
      details: 'Choco brownie',
      price: 80,
      imageUrl: 'https://cdn.yummbu.com/images/brownie.jpg',
      categoryId: 'cat_dessert',
      isVeg: true,
      isAvailable: true,
      isRecommended: true,
      sortOrder: 1,
    );

    test('5. Shop with 0 categories -> Exactly 1 image (Banner only)', () {
      final images = resolveShopSlideshowImages(
        shopBannerUrl: testShop.bannerUrl,
        categories: [],
        menuItems: [item1, item2, item3],
      );

      expect(images.length, equals(1));
      expect(images[0], equals(testShop.bannerUrl));
    });

    test('6. Shop with 1 category -> Exactly 3 images (Banner + All + Cat 1)', () {
      final images = resolveShopSlideshowImages(
        shopBannerUrl: testShop.bannerUrl,
        categories: [cat1],
        menuItems: [item1, item1Extra], // item1Extra must NOT be added separately
      );

      expect(images.length, equals(3));
      expect(images[0], equals(testShop.bannerUrl));
      expect(images[1], equals(item1.imageUrl)); // All category
      expect(images[2], equals(item1.imageUrl)); // Cat 1
    });

    test('7. Shop with 3 categories (UP16 Coffee Queen) -> Exactly 5 images (Banner + All + 3 Cats)', () {
      final images = resolveShopSlideshowImages(
        shopBannerUrl: testShop.bannerUrl,
        categories: [cat1, cat2, cat3],
        menuItems: [item1, item1Extra, item2, item3],
      );

      expect(images.length, equals(5));
      expect(images[0], equals(testShop.bannerUrl));
      expect(images[1], equals(item1.imageUrl)); // All
      expect(images[2], equals(item1.imageUrl)); // Cat 1: Coffee
      expect(images[3], equals(item2.imageUrl)); // Cat 2: Shakes
      expect(images[4], equals(item3.imageUrl)); // Cat 3: Snacks
    });

    test('8. Shop with 4 categories -> Exactly 6 images (Banner + All + 4 Cats)', () {
      final images = resolveShopSlideshowImages(
        shopBannerUrl: testShop.bannerUrl,
        categories: [cat1, cat2, cat3, cat4],
        menuItems: [item1, item1Extra, item2, item3, item4],
      );

      expect(images.length, equals(6));
      expect(images[0], equals(testShop.bannerUrl));
      expect(images[1], equals(item1.imageUrl)); // All
      expect(images[2], equals(item1.imageUrl)); // Cat 1
      expect(images[3], equals(item2.imageUrl)); // Cat 2
      expect(images[4], equals(item3.imageUrl)); // Cat 3
      expect(images[5], equals(item4.imageUrl)); // Cat 4
    });

    test('9. Category image strictly uses FIRST item image in that category', () {
      final images = resolveShopSlideshowImages(
        shopBannerUrl: testShop.bannerUrl,
        categories: [cat1],
        menuItems: [item1, item1Extra],
      );

      // cat1 must use item1 ('cold_coffee.jpg'), not item1Extra ('hot_coffee.jpg')
      expect(images[2], equals(item1.imageUrl));
      expect(images, isNot(contains(item1Extra.imageUrl)));
    });

    test('10. Menu items are NOT individually or flatly dumped into slideshow', () {
      // 1 shop with 20 items in 1 category
      final twentyItems = List.generate(
        20,
        (i) => MenuItem(
          id: 'item_$i',
          name: 'Item $i',
          details: 'Details $i',
          price: 50 + i,
          imageUrl: 'https://cdn.yummbu.com/images/item_$i.jpg',
          categoryId: 'cat_coffee',
          isVeg: true,
          isAvailable: true,
          isRecommended: false,
          sortOrder: i + 1,
        ),
      );

      final images = resolveShopSlideshowImages(
        shopBannerUrl: testShop.bannerUrl,
        categories: [cat1],
        menuItems: twentyItems,
      );

      // Must NOT be 21 or 22 images! Must be exactly 3 (Banner + All + Cat 1)
      expect(images.length, equals(3));
      expect(images[0], equals(testShop.bannerUrl));
      expect(images[1], equals(twentyItems[0].imageUrl));
      expect(images[2], equals(twentyItems[0].imageUrl));
    });
  });
}
