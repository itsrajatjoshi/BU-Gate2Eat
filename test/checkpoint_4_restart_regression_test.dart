// BU Gate2Eat — Checkpoint 4 Restart Regression Suite
// Comprehensive performance, stability, memory, navigation, slideshow, logo, and crop verification

import 'dart:typed_data';
import 'package:bugate2eat_app/core/constants/app_constants.dart';
import 'package:bugate2eat_app/core/providers.dart';
import 'package:bugate2eat_app/core/widgets/circular_crop_dialog.dart';
import 'package:bugate2eat_app/features/cart/cart_screen.dart';
import 'package:bugate2eat_app/features/favourites/favourites_screen.dart';
import 'package:bugate2eat_app/features/home/home_screen.dart';
import 'package:bugate2eat_app/features/home/widgets/shop_card.dart';
import 'package:bugate2eat_app/features/orders/order_history_screen.dart';
import 'package:bugate2eat_app/features/profile/profile_screen.dart';
import 'package:bugate2eat_app/features/shop/shop_detail_screen.dart';
import 'package:bugate2eat_app/models/category_model.dart';
import 'package:bugate2eat_app/models/menu_item_model.dart';
import 'package:bugate2eat_app/models/shop_model.dart';
import 'package:bugate2eat_app/services/image_optimization_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final testShop = Shop(
    id: 'test_shop_1',
    name: 'Rajat Food Corner',
    description: 'Fresh Fast Food',
    bannerUrl: 'https://cdn.yummbu.com/images/banner_corner.jpg',
    shopLogoImageUrl: 'https://cdn.yummbu.com/images/logo_corner.jpg',
    contactNumber: '918295643910',
    orderNumber: '918295643910',
    openTime: '08:00',
    closeTime: '23:00',
    isClosedOverride: false,
    isActive: true,
    sortOrder: 1,
    searchKeywords: ['food', 'corner'],
    deliveryNote: 'Hostel Gate 2',
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );

  const testCategory1 = Category(
    id: 'cat_burgers',
    name: 'Burgers',
    sortOrder: 1,
    imageUrl: 'https://cdn.yummbu.com/images/cat_burger.jpg',
    isActive: true,
  );

  const testCategory2 = Category(
    id: 'cat_beverages',
    name: 'Beverages',
    sortOrder: 2,
    imageUrl: 'https://cdn.yummbu.com/images/cat_beverage.jpg',
    isActive: true,
  );

  const testItem1 = MenuItem(
    id: 'item_veg_burger',
    name: 'Crispy Veg Burger',
    details: 'Fresh patty with lettuce',
    price: 80,
    imageUrl: 'https://cdn.yummbu.com/images/item_crispy_burger.jpg',
    categoryId: 'cat_burgers',
    isVeg: true,
    isAvailable: true,
    isRecommended: true,
    sortOrder: 1,
  );

  const testItem2 = MenuItem(
    id: 'item_cold_coffee',
    name: 'Cold Coffee Frappe',
    details: 'Blended cold coffee',
    price: 90,
    imageUrl: 'https://cdn.yummbu.com/images/item_cold_coffee.jpg',
    categoryId: 'cat_beverages',
    isVeg: true,
    isAvailable: true,
    isRecommended: true,
    sortOrder: 1,
  );

  // =========================================================================
  // CHANGE 1 — BACK BUTTON BEHAVIOR & NAVIGATION INTEGRITY
  // =========================================================================
  group('Checkpoint 4.1: Back Button & System Pop Navigation', () {
    testWidgets('1.1. Tab Navigation: Favourites -> Back -> Home (no loop/recreation)', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: HomeScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Navigate to Favourites tab (index 1)
      await tester.tap(find.text('Favourites'));
      await tester.pumpAndSettle();

      var navBar = tester.widget<BottomNavigationBar>(find.byType(BottomNavigationBar));
      expect(navBar.currentIndex, equals(1));

      // Simulate system Android back
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      // Should return to Home tab (index 0)
      navBar = tester.widget<BottomNavigationBar>(find.byType(BottomNavigationBar));
      expect(navBar.currentIndex, equals(0));
    });

    testWidgets('1.2. Tab Navigation: Cart -> Back -> Home', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: HomeScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Navigate to Cart tab (index 2)
      await tester.tap(find.text('Cart'));
      await tester.pumpAndSettle();

      var navBar = tester.widget<BottomNavigationBar>(find.byType(BottomNavigationBar));
      expect(navBar.currentIndex, equals(2));

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      navBar = tester.widget<BottomNavigationBar>(find.byType(BottomNavigationBar));
      expect(navBar.currentIndex, equals(0));
    });

    testWidgets('1.3. Tab Navigation: Orders -> Back -> Home', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: HomeScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Navigate to Orders tab (index 3)
      await tester.tap(find.text('Orders'));
      await tester.pumpAndSettle();

      var navBar = tester.widget<BottomNavigationBar>(find.byType(BottomNavigationBar));
      expect(navBar.currentIndex, equals(3));

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      navBar = tester.widget<BottomNavigationBar>(find.byType(BottomNavigationBar));
      expect(navBar.currentIndex, equals(0));
    });

    testWidgets('1.4. Home Tab: Back button allows normal app exit (canPop is true)', (tester) async {
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

    testWidgets('1.5. Repeated Tab Switching & Back does not crash or recreate Home state', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: HomeScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      for (int i = 0; i < 5; i++) {
        await tester.tap(find.text('Favourites'));
        await tester.pumpAndSettle();
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();

        await tester.tap(find.text('Cart'));
        await tester.pumpAndSettle();
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
      }

      final navBar = tester.widget<BottomNavigationBar>(find.byType(BottomNavigationBar));
      expect(navBar.currentIndex, equals(0));
    });
  });

  // =========================================================================
  // CHANGE 2 — SHOP CARD SLIDESHOW ISOLATION & RULES
  // =========================================================================
  group('Checkpoint 4.2: Shop Card Slideshow Isolation & Performance', () {
    test('2.1. Slide #1 is strictly bannerUrl and remaining are category first items', () {
      final images = resolveShopSlideshowImages(
        shopBannerUrl: testShop.bannerUrl,
        categories: [testCategory1, testCategory2],
        menuItems: [testItem1, testItem2],
      );

      // Slide 1: Banner
      expect(images[0], equals(testShop.bannerUrl));
      // Slide 2: 'All' category item (testItem1)
      expect(images[1], equals(testItem1.imageUrl));
      // Slide 3: Cat 1 item (testItem1)
      expect(images[2], equals(testItem1.imageUrl));
      // Slide 4: Cat 2 item (testItem2)
      expect(images[3], equals(testItem2.imageUrl));
    });

    test('2.2. NEVER includes shopLogoImageUrl in slideshow list', () {
      final images = resolveShopSlideshowImages(
        shopBannerUrl: testShop.bannerUrl,
        categories: [testCategory1, testCategory2],
        menuItems: [testItem1, testItem2],
      );

      expect(images, isNot(contains(testShop.shopLogoImageUrl)));
    });

    test('2.3. Shop with 0 categories has exactly 1 image (Banner only)', () {
      final images = resolveShopSlideshowImages(
        shopBannerUrl: testShop.bannerUrl,
        categories: [],
        menuItems: [testItem1, testItem2],
      );

      expect(images.length, equals(1));
      expect(images.first, equals(testShop.bannerUrl));
    });

    testWidgets('2.4. ShopCard renders CachedNetworkImage with memCacheWidth: 800 for banner', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: ShopCard(
                shop: testShop,
                onTap: () {},
                slideshowImages: [testShop.bannerUrl],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final cachedImages = tester.widgetList<CachedNetworkImage>(find.byType(CachedNetworkImage));
      final bannerImage = cachedImages.firstWhere(
        (img) => img.imageUrl == testShop.bannerUrl,
      );
      expect(bannerImage.memCacheWidth, equals(800));
    });
  });

  // =========================================================================
  // CHANGE 3 — INDEPENDENT SHOP CIRCLE PHOTO (shopLogoImageUrl)
  // =========================================================================
  group('Checkpoint 4.3: Independent Shop Circle Photo Architecture', () {
    test('3.1. Shop model serializes shopLogoImageUrl independently from bannerUrl', () {
      final firestoreMap = testShop.toFirestore();
      expect(firestoreMap['shopLogoImageUrl'], equals('https://cdn.yummbu.com/images/logo_corner.jpg'));
      expect(firestoreMap['bannerUrl'], equals('https://cdn.yummbu.com/images/banner_corner.jpg'));

      final copy = testShop.copyWith(shopLogoImageUrl: 'https://cdn.yummbu.com/images/new_logo.jpg');
      expect(copy.shopLogoImageUrl, equals('https://cdn.yummbu.com/images/new_logo.jpg'));
      expect(copy.bannerUrl, equals(testShop.bannerUrl)); // Banner unaffected
    });

    testWidgets('3.2. ShopCard circular avatar renders shopLogoImageUrl with memCache 160x160', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: ShopCard(
                shop: testShop,
                onTap: () {},
                slideshowImages: [testShop.bannerUrl],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final circularLogoFinder = find.byKey(const ValueKey('shop_card_circular_logo'));
      expect(circularLogoFinder, findsOneWidget);

      final cachedImages = tester.widgetList<CachedNetworkImage>(
        find.descendant(of: circularLogoFinder, matching: find.byType(CachedNetworkImage)),
      );
      expect(cachedImages.length, equals(1));
      expect(cachedImages.first.imageUrl, equals(testShop.shopLogoImageUrl));
      expect(cachedImages.first.memCacheWidth, equals(160));
      expect(cachedImages.first.memCacheHeight, equals(160));
    });
  });

  // =========================================================================
  // CHANGE 4 — CIRCLE PHOTO FALLBACK FIX (NEVER USE BANNER)
  // =========================================================================
  group('Checkpoint 4.4: Circle Photo Fallback & Offline Invariants', () {
    testWidgets('4.1. Empty shopLogoImageUrl displays default placeholder icon and NEVER bannerUrl', (tester) async {
      final shopWithoutLogo = testShop.copyWith(shopLogoImageUrl: '');

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: ShopCard(
                shop: shopWithoutLogo,
                onTap: () {},
                slideshowImages: [shopWithoutLogo.bannerUrl],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final circularLogoFinder = find.byKey(const ValueKey('shop_card_circular_logo'));
      expect(circularLogoFinder, findsOneWidget);

      // Verify NO CachedNetworkImage inside circular logo
      final cachedImagesInCircle = find.descendant(
        of: circularLogoFinder,
        matching: find.byType(CachedNetworkImage),
      );
      expect(cachedImagesInCircle, findsNothing);

      // Verify storefront icon placeholder renders immediately
      final iconFinder = find.descendant(
        of: circularLogoFinder,
        matching: find.byIcon(Icons.storefront_rounded),
      );
      expect(iconFinder, findsOneWidget);
    });
  });

  // =========================================================================
  // CHANGE 5 — CROP ACCURACY & PERFORMANCE VERIFICATION
  // =========================================================================
  group('Checkpoint 4.5: Circular Crop Accuracy & Resource Lifecycle', () {
    test('5.1. Crop output is always strictly square 512x512', () {
      final image = img.Image(width: 800, height: 1600);
      img.fill(image, color: img.ColorRgb8(0, 150, 255));
      final rawBytes = Uint8List.fromList(img.encodeJpg(image, quality: 90));

      final croppedBytes = ImageCropHelper.cropSquare(
        rawBytes: rawBytes,
        targetDimension: 512,
      );

      final decoded = img.decodeImage(croppedBytes)!;
      expect(decoded.width, equals(512));
      expect(decoded.height, equals(512));
    });

    test('5.2. ImageOptimizationService enforces shopLogo <= 300KB limit', () async {
      final image = img.Image(width: 512, height: 512);
      img.fill(image, color: img.ColorRgb8(255, 87, 34));
      final rawBytes = Uint8List.fromList(img.encodeJpg(image, quality: 95));

      final optimized = await ImageOptimizationService.optimizeImageBytes(
        originalBytes: rawBytes,
        type: ImageTargetType.shopLogo,
      );

      expect(optimized.lengthInBytes, lessThanOrEqualTo(300 * 1024));
    });

    test('5.3. Inverted Viewport Transform accurately maps crop coordinates without distortion', () {
      // 1000x1000 square image with 4 color quadrants
      final image = img.Image(width: 1000, height: 1000);
      for (int y = 0; y < 1000; y++) {
        for (int x = 0; x < 1000; x++) {
          if (x < 500 && y < 500) {
            image.setPixel(x, y, img.ColorRgb8(255, 0, 0)); // Top-Left Red
          } else if (x >= 500 && y < 500) {
            image.setPixel(x, y, img.ColorRgb8(0, 255, 0)); // Top-Right Green
          } else if (x < 500 && y >= 500) {
            image.setPixel(x, y, img.ColorRgb8(0, 0, 255)); // Bottom-Left Blue
          } else {
            image.setPixel(x, y, img.ColorRgb8(255, 255, 0)); // Bottom-Right Yellow
          }
        }
      }
      final rawBytes = Uint8List.fromList(img.encodeJpg(image, quality: 90));

      // Centered transform matrix (s=1.0, tx=0, ty=0)
      final matrix = Matrix4.identity();
      const childSize = Size(280, 280);
      const viewportSize = Size(280, 280);

      final croppedBytes = ImageCropHelper.cropFromViewportTransform(
        rawBytes: rawBytes,
        transformMatrix: matrix,
        viewportSize: viewportSize,
        circleDiameter: 240,
        childImageSize: childSize,
        targetDimension: 512,
      );

      final cropped = img.decodeImage(croppedBytes)!;
      expect(cropped.width, equals(512));
      expect(cropped.height, equals(512));

      // Check that all 4 quadrants are preserved symmetrically
      final tlPixel = cropped.getPixel(100, 100);
      final trPixel = cropped.getPixel(400, 100);
      final blPixel = cropped.getPixel(100, 400);
      final brPixel = cropped.getPixel(400, 400);

      expect(tlPixel.r, greaterThan(200)); // Red
      expect(trPixel.g, greaterThan(200)); // Green
      expect(blPixel.b, greaterThan(200)); // Blue
      expect(brPixel.r, greaterThan(200)); // Yellow
      expect(brPixel.g, greaterThan(200)); // Yellow
    });
  });
}
