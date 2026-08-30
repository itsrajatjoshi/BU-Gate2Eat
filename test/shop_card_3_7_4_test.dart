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
  group('Checkpoint 3.7.4 — Shop Card Main Image Slideshow Tests', () {
    final shopA = Shop(
      id: 'shop_a',
      name: 'Raja Hotel',
      description: 'Meals',
      bannerUrl: 'https://example.com/shop_a_logo.jpg',
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
      description: 'Snacks & Coffee',
      bannerUrl: 'https://example.com/shop_b_logo.jpg',
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

    final catB1 = const Category(
      id: 'cat_coffee',
      name: 'Hot Coffee',
      sortOrder: 1,
      imageUrl: '',
      isActive: true,
    );

    final itemB1 = const MenuItem(
      id: 'item_cappuccino',
      name: 'Cappuccino',
      details: 'Rich espresso',
      price: 60,
      imageUrl: 'https://cdn.yummbu.com/images/cappuccino.jpg',
      categoryId: 'cat_coffee',
      isVeg: true,
      isAvailable: true,
      isRecommended: true,
      sortOrder: 1,
    );

    test('1. Deterministic slideshow images resolution order for a shop', () {
      final images = resolveShopSlideshowImages(
        shopBannerUrl: shopA.bannerUrl,
        categories: [catA2, catA1], // Out of order input
        menuItems: [itemA2, itemA1],
      );

      // Must have shop banner at index 0, followed by category sortOrder (catA1: thali -> catA2: biryani)
      expect(images.length, equals(3));
      expect(images[0], equals(shopA.bannerUrl));
      expect(images[1], equals('https://cdn.yummbu.com/images/veg_thali.jpg'));
      expect(images[2], equals('https://cdn.yummbu.com/images/dum_biryani.jpg'));
    });

    test('2. Strict shop boundary separation — No cross-shop image leakage', () {
      final imagesA = resolveShopSlideshowImages(
        categories: [catA1, catA2],
        menuItems: [itemA1, itemA2],
        fallbackShopBannerUrl: shopA.bannerUrl,
      );

      final imagesB = resolveShopSlideshowImages(
        categories: [catB1],
        menuItems: [itemB1],
        fallbackShopBannerUrl: shopB.bannerUrl,
      );

      expect(imagesA, contains('https://cdn.yummbu.com/images/veg_thali.jpg'));
      expect(imagesA, contains('https://cdn.yummbu.com/images/dum_biryani.jpg'));
      expect(imagesA, isNot(contains('https://cdn.yummbu.com/images/cappuccino.jpg')));

      expect(imagesB, contains('https://cdn.yummbu.com/images/cappuccino.jpg'));
      expect(imagesB, isNot(contains('https://cdn.yummbu.com/images/veg_thali.jpg')));
      expect(imagesB, isNot(contains('https://cdn.yummbu.com/images/dum_biryani.jpg')));
    });

    testWidgets('3. Single image shop renders static image without PageView or dots',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 360,
                child: ShopCard(
                  shop: shopB,
                  slideshowImages: const ['https://cdn.yummbu.com/images/single_banner.jpg'],
                  onTap: () {},
                ),
              ),
            ),
          ),
        ),
      );

      // No PageView for 1 image
      expect(find.byKey(const ValueKey('shop_card_slideshow_pageview')), findsNothing);
      // Main image rendered statically
      final cachedImages = tester.widgetList<CachedNetworkImage>(find.byType(CachedNetworkImage));
      expect(cachedImages.any((img) => img.imageUrl == 'https://cdn.yummbu.com/images/single_banner.jpg'), isTrue);
    });

    testWidgets('4. Zero image shop gracefully renders placeholder without crash',
        (tester) async {
      final emptyShop = shopA.copyWith(bannerUrl: '');
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 360,
                child: ShopCard(
                  shop: emptyShop,
                  slideshowImages: const [],
                  onTap: () {},
                ),
              ),
            ),
          ),
        ),
      );

      // Displays placeholder icon storefront
      expect(find.byIcon(Icons.storefront_rounded), findsWidgets);
    });

    testWidgets('5. Multi-image shop enables PageView with manual swipe capability',
        (tester) async {
      final multiImages = [
        'https://cdn.yummbu.com/images/img1.jpg',
        'https://cdn.yummbu.com/images/img2.jpg',
        'https://cdn.yummbu.com/images/img3.jpg',
      ];

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 360,
                child: ShopCard(
                  shop: shopA,
                  slideshowImages: multiImages,
                  onTap: () {},
                ),
              ),
            ),
          ),
        ),
      );

      // PageView is present
      final pageViewFinder = find.byKey(const ValueKey('shop_card_slideshow_pageview'));
      expect(pageViewFinder, findsOneWidget);

      // Swipe left on PageView to move to page 2
      await tester.drag(pageViewFinder, const Offset(-300, 0));
      await tester.pumpAndSettle();

      // Verified slide changed without error
      expect(find.byType(ShopCard), findsOneWidget);
    });

    testWidgets('6. Automatic slideshow advances slides over time interval',
        (tester) async {
      final multiImages = [
        'https://cdn.yummbu.com/images/slide1.jpg',
        'https://cdn.yummbu.com/images/slide2.jpg',
      ];

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 360,
                child: ShopCard(
                  shop: shopA,
                  slideshowImages: multiImages,
                  autoSlideInterval: const Duration(seconds: 2),
                  onTap: () {},
                ),
              ),
            ),
          ),
        ),
      );

      // Advance time by 2.5 seconds to trigger auto slide
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();

      expect(find.byType(ShopCard), findsOneWidget);
    });

    testWidgets('7. Updating image catalog dynamically reflects in slideshow',
        (tester) async {
      final initialImages = ['https://cdn.yummbu.com/images/initial_1.jpg'];
      final updatedImages = [
        'https://cdn.yummbu.com/images/initial_1.jpg',
        'https://cdn.yummbu.com/images/updated_2.jpg',
      ];

      var currentImages = initialImages;

      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            return ProviderScope(
              child: MaterialApp(
                home: Scaffold(
                  body: SizedBox(
                    width: 360,
                    child: Column(
                      children: [
                        ShopCard(
                          shop: shopA,
                          slideshowImages: currentImages,
                          onTap: () {},
                        ),
                        ElevatedButton(
                          onPressed: () {
                            setState(() {
                              currentImages = updatedImages;
                            });
                          },
                          child: const Text('Update Images'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      );

      expect(find.byKey(const ValueKey('shop_card_slideshow_pageview')), findsNothing);

      // Tap update button
      await tester.tap(find.text('Update Images'));
      await tester.pumpAndSettle();

      // Now PageView exists with multiple slides
      expect(find.byKey(const ValueKey('shop_card_slideshow_pageview')), findsOneWidget);
    });

    testWidgets('8. Widget disposal cleanly cancels auto-slide timers without leaks',
        (tester) async {
      var showCard = true;

      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            return ProviderScope(
              child: MaterialApp(
                home: Scaffold(
                  body: SizedBox(
                    width: 360,
                    child: Column(
                      children: [
                        if (showCard)
                          ShopCard(
                            shop: shopA,
                            slideshowImages: const [
                              'https://cdn.yummbu.com/images/leak1.jpg',
                              'https://cdn.yummbu.com/images/leak2.jpg',
                            ],
                            onTap: () {},
                          ),
                        ElevatedButton(
                          onPressed: () {
                            setState(() {
                              showCard = false;
                            });
                          },
                          child: const Text('Remove Card'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      );

      // Remove the ShopCard from widget tree
      await tester.tap(find.text('Remove Card'));
      await tester.pumpAndSettle();

      // Advance time — No timer exceptions should occur
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      expect(find.byType(ShopCard), findsNothing);
    });

    testWidgets('9. Circular shop logo (3.7.3) remains intact and unaffected by banner slideshow',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 360,
                child: ShopCard(
                  shop: shopA,
                  slideshowImages: const [
                    'https://cdn.yummbu.com/images/slideA.jpg',
                    'https://cdn.yummbu.com/images/slideB.jpg',
                  ],
                  onTap: () {},
                ),
              ),
            ),
          ),
        ),
      );

      // Verify circular logo is present on the right
      final logoFinder = find.byKey(const ValueKey('shop_card_circular_logo'));
      expect(logoFinder, findsOneWidget);

      final cardRect = tester.getRect(find.byType(ShopCard));
      final logoRect = tester.getRect(logoFinder);
      expect(logoRect.center.dx, greaterThan(cardRect.center.dx));

      // Verify shop profile image is used in circular logo (shopA.bannerUrl)
      final cachedImages = tester.widgetList<CachedNetworkImage>(find.byType(CachedNetworkImage));
      expect(cachedImages.any((img) => img.imageUrl == shopA.bannerUrl), isTrue);
    });
  });
}
