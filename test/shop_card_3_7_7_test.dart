import 'package:bugate2eat_app/core/providers.dart';
import 'package:bugate2eat_app/features/home/widgets/shop_card.dart';
import 'package:bugate2eat_app/models/category_model.dart';
import 'package:bugate2eat_app/models/menu_item_model.dart';
import 'package:bugate2eat_app/models/shop_model.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Checkpoint 3.7.7 — Shop Card Slideshow First Image Tests', () {
    final shopA = Shop(
      id: 'shop_a',
      name: 'Raja Hotel',
      description: 'Meals',
      bannerUrl: 'https://cdn.yummbu.com/shops/raja_hotel_banner.jpg',
      contactNumber: '9191919191',
      orderNumber: '9191919191',
      openTime: '08:00',
      closeTime: '23:30',
      isClosedOverride: false,
      isActive: true,
      sortOrder: 1,
      searchKeywords: ['raja'],
      deliveryNote: '',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    final shopB = Shop(
      id: 'shop_b',
      name: 'UP16 Coffee Queen',
      description: 'Coffee & Snacks',
      bannerUrl: 'https://cdn.yummbu.com/shops/up16_banner.jpg',
      contactNumber: '9292929292',
      orderNumber: '9292929292',
      openTime: '09:00',
      closeTime: '22:00',
      isClosedOverride: false,
      isActive: true,
      sortOrder: 2,
      searchKeywords: ['coffee'],
      deliveryNote: '',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    final catA1 = const Category(
      id: 'cat_thali',
      name: 'Thali',
      sortOrder: 1,
      imageUrl: '',
      isActive: true,
    );

    final catA2 = const Category(
      id: 'cat_biryani',
      name: 'Biryani',
      sortOrder: 2,
      imageUrl: '',
      isActive: true,
    );

    final itemA1 = const MenuItem(
      id: 'item_veg_thali',
      name: 'Special Veg Thali',
      details: 'Full thali',
      price: 150,
      imageUrl: 'https://cdn.yummbu.com/images/veg_thali.jpg',
      categoryId: 'cat_thali',
      isVeg: true,
      isAvailable: true,
      isRecommended: true,
      sortOrder: 1,
    );

    final itemA2 = const MenuItem(
      id: 'item_dum_biryani',
      name: 'Hyderabadi Biryani',
      details: 'Spiced biryani',
      price: 180,
      imageUrl: 'https://cdn.yummbu.com/images/dum_biryani.jpg',
      categoryId: 'cat_biryani',
      isVeg: false,
      isAvailable: true,
      isRecommended: true,
      sortOrder: 1,
    );

    test('1. Shop banner is ALWAYS at index 0 in the slideshow list', () {
      final images = resolveShopSlideshowImages(
        shopBannerUrl: shopA.bannerUrl,
        categories: [catA1, catA2],
        menuItems: [itemA1, itemA2],
      );

      expect(images.isNotEmpty, isTrue);
      expect(images[0], equals(shopA.bannerUrl));
    });

    test('2. Category/food images remain after the banner in sorted order', () {
      final images = resolveShopSlideshowImages(
        shopBannerUrl: shopA.bannerUrl,
        categories: [catA2, catA1], // Unsorted input
        menuItems: [itemA2, itemA1],
      );

      expect(images.length, equals(3));
      expect(images[0], equals(shopA.bannerUrl));
      expect(images[1], equals('https://cdn.yummbu.com/images/veg_thali.jpg'));
      expect(images[2], equals('https://cdn.yummbu.com/images/dum_biryani.jpg'));
    });

    test('3. Banner changes correctly when shop bannerUrl changes', () {
      const updatedBanner = 'https://cdn.yummbu.com/shops/new_raja_banner.jpg';
      final images = resolveShopSlideshowImages(
        shopBannerUrl: updatedBanner,
        categories: [catA1],
        menuItems: [itemA1],
      );

      expect(images[0], equals(updatedBanner));
    });

    test('4. Missing/empty banner safely falls back to category/food images at index 0', () {
      final images = resolveShopSlideshowImages(
        shopBannerUrl: '',
        categories: [catA1, catA2],
        menuItems: [itemA1, itemA2],
      );

      expect(images.length, equals(2));
      expect(images[0], equals('https://cdn.yummbu.com/images/veg_thali.jpg'));
      expect(images[1], equals('https://cdn.yummbu.com/images/dum_biryani.jpg'));
    });

    test('5. Duplicate banner URL in menu items is not added twice', () {
      final duplicateItem = MenuItem(
        id: itemA1.id,
        name: itemA1.name,
        details: itemA1.details,
        price: itemA1.price,
        imageUrl: shopA.bannerUrl,
        categoryId: itemA1.categoryId,
        isVeg: itemA1.isVeg,
        isAvailable: itemA1.isAvailable,
        isRecommended: itemA1.isRecommended,
        sortOrder: itemA1.sortOrder,
      );
      final images = resolveShopSlideshowImages(
        shopBannerUrl: shopA.bannerUrl,
        categories: [catA1],
        menuItems: [duplicateItem],
      );

      expect(images.length, equals(1));
      expect(images[0], equals(shopA.bannerUrl));
    });

    test('6. Strict shop isolation: Shop A never receives Shop B banner or images', () {
      final imagesA = resolveShopSlideshowImages(
        shopBannerUrl: shopA.bannerUrl,
        categories: [catA1],
        menuItems: [itemA1],
      );

      final imagesB = resolveShopSlideshowImages(
        shopBannerUrl: shopB.bannerUrl,
        categories: [],
        menuItems: [],
      );

      expect(imagesA, contains(shopA.bannerUrl));
      expect(imagesA, isNot(contains(shopB.bannerUrl)));

      expect(imagesB, contains(shopB.bannerUrl));
      expect(imagesB, isNot(contains(shopA.bannerUrl)));
    });

    testWidgets('7. Widget level: Slideshow PageView starts on shop banner',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 360,
                child: ShopCard(
                  shop: shopA,
                  slideshowImages: [
                    shopA.bannerUrl,
                    'https://cdn.yummbu.com/images/veg_thali.jpg',
                  ],
                  onTap: () {},
                ),
              ),
            ),
          ),
        ),
      );

      final pageViewFinder = find.byKey(const ValueKey('shop_card_slideshow_pageview'));
      expect(pageViewFinder, findsOneWidget);

      final cachedImages = tester.widgetList<CachedNetworkImage>(find.byType(CachedNetworkImage));
      expect(cachedImages.any((img) => img.imageUrl == shopA.bannerUrl), isTrue);
    });
  });
}
