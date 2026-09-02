// BU Gate2Eat — Comprehensive QA Test Suite
// Verification of Separate Shop Circle Photo (shopLogoImageUrl) & Circular Crop Pipeline

import 'dart:typed_data';

import 'package:bugate2eat_app/core/constants/app_constants.dart';
import 'package:bugate2eat_app/core/providers.dart';
import 'package:bugate2eat_app/core/widgets/circular_crop_dialog.dart';
import 'package:bugate2eat_app/features/home/widgets/shop_card.dart';
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

/// Generates a test image with given width and height.
Uint8List createTestImageBytes(int width, int height, {int colorRgb = 0xFF0000}) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8((colorRgb >> 16) & 0xFF, (colorRgb >> 8) & 0xFF, colorRgb & 0xFF));
  return Uint8List.fromList(img.encodeJpg(image, quality: 80));
}

void main() {
  group('1. Shop Model — shopLogoImageUrl Field Serialization & Defaults', () {
    test('A1: Shop constructor assigns shopLogoImageUrl correctly', () {
      final shop = Shop(
        id: 'shop_test',
        name: 'Test Shop',
        description: 'Desc',
        address: 'Gate 3',
        bannerUrl: 'https://cdn.yummbu.com/banner.jpg',
        shopLogoImageUrl: 'https://cdn.yummbu.com/circle_logo.jpg',
        contactNumber: '9999999999',
        orderNumber: '9999999999',
        openTime: '8:00 AM',
        closeTime: '11:30 PM',
        isClosedOverride: false,
        isActive: true,
        sortOrder: 1,
        searchKeywords: ['test'],
        deliveryNote: 'Pickup',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );

      expect(shop.bannerUrl, equals('https://cdn.yummbu.com/banner.jpg'));
      expect(shop.shopLogoImageUrl, equals('https://cdn.yummbu.com/circle_logo.jpg'));
    });

    test('A2: Shop.toFirestore includes shopLogoImageUrl', () {
      final shop = Shop(
        id: 'shop_test',
        name: 'Test Shop',
        description: 'Desc',
        address: 'Gate 3',
        bannerUrl: 'https://cdn.yummbu.com/banner.jpg',
        shopLogoImageUrl: 'https://cdn.yummbu.com/circle_logo.jpg',
        contactNumber: '9999999999',
        orderNumber: '9999999999',
        openTime: '8:00 AM',
        closeTime: '11:30 PM',
        isClosedOverride: false,
        isActive: true,
        sortOrder: 1,
        searchKeywords: ['test'],
        deliveryNote: 'Pickup',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );

      final map = shop.toFirestore();
      expect(map['bannerUrl'], equals('https://cdn.yummbu.com/banner.jpg'));
      expect(map['shopLogoImageUrl'], equals('https://cdn.yummbu.com/circle_logo.jpg'));
    });

    test('A3: Shop.copyWith preserves or updates shopLogoImageUrl independently', () {
      final shop = Shop(
        id: 'shop_test',
        name: 'Test Shop',
        description: 'Desc',
        bannerUrl: 'https://cdn.yummbu.com/banner.jpg',
        shopLogoImageUrl: 'https://cdn.yummbu.com/circle_logo.jpg',
        contactNumber: '9999999999',
        orderNumber: '9999999999',
        openTime: '8:00 AM',
        closeTime: '11:30 PM',
        isClosedOverride: false,
        isActive: true,
        sortOrder: 1,
        searchKeywords: ['test'],
        deliveryNote: 'Pickup',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );

      final updatedLogo = shop.copyWith(shopLogoImageUrl: 'https://cdn.yummbu.com/new_logo.jpg');
      expect(updatedLogo.bannerUrl, equals('https://cdn.yummbu.com/banner.jpg'));
      expect(updatedLogo.shopLogoImageUrl, equals('https://cdn.yummbu.com/new_logo.jpg'));

      final updatedBanner = shop.copyWith(bannerUrl: 'https://cdn.yummbu.com/new_banner.jpg');
      expect(updatedBanner.bannerUrl, equals('https://cdn.yummbu.com/new_banner.jpg'));
      expect(updatedBanner.shopLogoImageUrl, equals('https://cdn.yummbu.com/circle_logo.jpg'));
    });

    test('F1: Backward Compatibility — shop without shopLogoImageUrl defaults to empty string', () {
      final shop = Shop(
        id: 'shop_legacy',
        name: 'Legacy Shop',
        description: 'Desc',
        bannerUrl: 'https://cdn.yummbu.com/banner.jpg',
        contactNumber: '9999999999',
        orderNumber: '9999999999',
        openTime: '8:00 AM',
        closeTime: '11:30 PM',
        isClosedOverride: false,
        isActive: true,
        sortOrder: 1,
        searchKeywords: ['legacy'],
        deliveryNote: 'Pickup',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );

      expect(shop.shopLogoImageUrl, equals(''));
      expect(shop.bannerUrl, equals('https://cdn.yummbu.com/banner.jpg'));
    });
  });

  group('2. Crop Utilities & Aspect Ratio Handling', () {
    test('G: Crop output is square (512x512)', () {
      final rawSquare = createTestImageBytes(400, 400);
      final cropped = ImageCropHelper.cropSquare(rawBytes: rawSquare, targetDimension: 512);

      final decoded = img.decodeImage(cropped);
      expect(decoded, isNotNull);
      expect(decoded!.width, equals(512));
      expect(decoded.height, equals(512));
    });

    test('H: Portrait image crop (e.g. 600x1200) produces square output (512x512)', () {
      final portraitBytes = createTestImageBytes(600, 1200);
      final cropped = ImageCropHelper.cropSquare(
        rawBytes: portraitBytes,
        normalizedX: 0.0,
        normalizedY: 0.2,
        normalizedSize: 0.8,
        targetDimension: 512,
      );

      final decoded = img.decodeImage(cropped);
      expect(decoded, isNotNull);
      expect(decoded!.width, equals(512));
      expect(decoded.height, equals(512));
    });

    test('I: Landscape image crop (e.g. 1600x900) produces square output (512x512)', () {
      final landscapeBytes = createTestImageBytes(1600, 900);
      final cropped = ImageCropHelper.cropSquare(
        rawBytes: landscapeBytes,
        normalizedX: 0.2,
        normalizedY: 0.0,
        normalizedSize: 0.8,
        targetDimension: 512,
      );

      final decoded = img.decodeImage(cropped);
      expect(decoded, isNotNull);
      expect(decoded!.width, equals(512));
      expect(decoded.height, equals(512));
    });

    test('J: User viewport pan and zoom transformation computes correct square bounds', () {
      final imageBytes = createTestImageBytes(800, 800);

      // Simulate a zoom scale of 2.0x centered in viewport
      final matrix = Matrix4.identity()
        ..translate(140.0, 140.0)
        ..scale(2.0)
        ..translate(-140.0, -140.0);

      final cropped = ImageCropHelper.cropFromViewportTransform(
        rawBytes: imageBytes,
        transformMatrix: matrix,
        viewportSize: const Size(280, 280),
        circleDiameter: 240,
        childImageSize: const Size(280, 280),
        targetDimension: 512,
      );

      final decoded = img.decodeImage(cropped);
      expect(decoded, isNotNull);
      expect(decoded!.width, equals(512));
      expect(decoded.height, equals(512));
    });

    test('ImageOptimizationService: shopLogo type enforces 300KB limit', () {
      expect(ImageOptimizationService.maxLogoBytes, equals(300 * 1024));
    });
  });

  group('3. Customer UI — Shop Card Circular Photo vs Banner Independence', () {
    final testShopWithLogo = Shop(
      id: 'shop_logo_test',
      name: 'Coffee Queen',
      description: 'Hot and Cold Brews',
      bannerUrl: 'https://cdn.yummbu.com/banner_coffee.jpg',
      shopLogoImageUrl: 'https://cdn.yummbu.com/circle_logo_coffee.jpg',
      contactNumber: '9999999999',
      orderNumber: '9999999999',
      openTime: '8:00 AM',
      closeTime: '11:30 PM',
      isClosedOverride: false,
      isActive: true,
      sortOrder: 1,
      searchKeywords: ['coffee'],
      deliveryNote: 'Gate 3',
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

    final testShopWithoutLogo = Shop(
      id: 'shop_no_logo_test',
      name: 'Burger Hub',
      description: 'Burgers and Fries',
      bannerUrl: 'https://cdn.yummbu.com/banner_burger.jpg',
      shopLogoImageUrl: '',
      contactNumber: '9999999999',
      orderNumber: '9999999999',
      openTime: '8:00 AM',
      closeTime: '11:30 PM',
      isClosedOverride: false,
      isActive: true,
      sortOrder: 2,
      searchKeywords: ['burger'],
      deliveryNote: 'Gate 3',
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

    testWidgets('B & C: ShopCard uses shopLogoImageUrl for circular photo and NOT bannerUrl when logo exists', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 360,
                child: ShopCard(
                  shop: testShopWithLogo,
                  slideshowImages: const ['https://cdn.yummbu.com/banner_coffee.jpg'],
                  onTap: () {},
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pump();

      // Find the circular logo widget container
      final circularLogoFinder = find.byKey(const ValueKey('shop_card_circular_logo'));
      expect(circularLogoFinder, findsOneWidget);

      // Verify CachedNetworkImage within circular logo uses shopLogoImageUrl
      final logoImageFinder = find.descendant(
        of: circularLogoFinder,
        matching: find.byType(CachedNetworkImage),
      );
      expect(logoImageFinder, findsOneWidget);

      final cachedImg = tester.widget<CachedNetworkImage>(logoImageFinder);
      expect(cachedImg.imageUrl, equals('https://cdn.yummbu.com/circle_logo_coffee.jpg'));
      expect(cachedImg.imageUrl, isNot(equals(testShopWithLogo.bannerUrl)));
    });

    testWidgets('F: ShopCard renders default shop placeholder icon and NEVER uses bannerUrl when shopLogoImageUrl is empty', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 360,
                child: ShopCard(
                  shop: testShopWithoutLogo,
                  slideshowImages: const ['https://cdn.yummbu.com/banner_burger.jpg'],
                  onTap: () {},
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pump();

      final circularLogoFinder = find.byKey(const ValueKey('shop_card_circular_logo'));
      expect(circularLogoFinder, findsOneWidget);

      // Verify CachedNetworkImage is NOT rendered inside circular logo
      final logoImageFinder = find.descendant(
        of: circularLogoFinder,
        matching: find.byType(CachedNetworkImage),
      );
      expect(logoImageFinder, findsNothing);

      // Verify default storefront placeholder icon IS rendered inside circular logo
      final placeholderIconFinder = find.descendant(
        of: circularLogoFinder,
        matching: find.byIcon(Icons.storefront_rounded),
      );
      expect(placeholderIconFinder, findsOneWidget);
    });

    test('D & K: Slideshow invariant — resolveShopSlideshowImages uses bannerUrl and NEVER shopLogoImageUrl', () {
      final cat = Category(id: 'cat_coffee', name: 'Coffee', isActive: true, sortOrder: 1);
      final item = MenuItem(
        id: 'item_cold_brew',
        name: 'Cold Brew',
        details: 'Brew',
        price: 99,
        categoryId: 'cat_coffee',
        imageUrl: 'https://cdn.yummbu.com/cold_brew.jpg',
        isVeg: true,
        isAvailable: true,
        isRecommended: false,
        sortOrder: 1,
      );

      final slideshowImages = resolveShopSlideshowImages(
        categories: [cat],
        menuItems: [item],
        shopBannerUrl: testShopWithLogo.bannerUrl,
      );

      // Banner at index 0 must be shopBannerUrl
      expect(slideshowImages[0], equals('https://cdn.yummbu.com/banner_coffee.jpg'));

      // shopLogoImageUrl must NEVER be in slideshow
      expect(slideshowImages, isNot(contains(testShopWithLogo.shopLogoImageUrl)));
    });
  });
}
