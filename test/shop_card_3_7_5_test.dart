import 'package:bugate2eat_app/features/home/widgets/shop_card.dart';
import 'package:bugate2eat_app/models/shop_model.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Checkpoint 3.7.5 — Shop Card Typography & Hierarchy Tests', () {
    final shopA = Shop(
      id: 'shop_a',
      name: 'Raja Hotel',
      description: 'Meals',
      bannerUrl: 'https://example.com/shop_a_logo.jpg',
      shopLogoImageUrl: 'https://example.com/shop_a_circle.jpg',
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

    testWidgets('1. Shop name renders with bold header typography hierarchy',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 360,
                child: ShopCard(
                  shop: shopA,
                  onTap: () {},
                ),
              ),
            ),
          ),
        ),
      );

      final nameFinder = find.text('Raja Hotel');
      expect(nameFinder, findsOneWidget);

      final textWidget = tester.widget<Text>(nameFinder);
      expect(textWidget.style?.fontWeight, equals(FontWeight.w800));
      expect(textWidget.maxLines, equals(1));
      expect(textWidget.overflow, equals(TextOverflow.ellipsis));
    });

    testWidgets('2. Timing renders with supporting medium typography hierarchy',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 360,
                child: ShopCard(
                  shop: shopA,
                  onTap: () {},
                ),
              ),
            ),
          ),
        ),
      );

      final timingFinder = find.text('8:00 AM – 11:30 PM');
      expect(timingFinder, findsOneWidget);

      final textWidget = tester.widget<Text>(timingFinder);
      expect(textWidget.style?.fontWeight, equals(FontWeight.w500));
    });

    testWidgets('3. Phone number renders with semi-bold chip typography hierarchy',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 360,
                child: ShopCard(
                  shop: shopA,
                  onTap: () {},
                ),
              ),
            ),
          ),
        ),
      );

      final phoneFinder = find.text('9191919191');
      expect(phoneFinder, findsOneWidget);

      final textWidget = tester.widget<Text>(phoneFinder);
      expect(textWidget.style?.fontWeight, equals(FontWeight.w600));
    });

    testWidgets('4. Status badge renders with heavy punchy typography',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 360,
                child: ShopCard(
                  shop: shopA,
                  onTap: () {},
                ),
              ),
            ),
          ),
        ),
      );

      final openFinder = find.text('OPEN');
      expect(openFinder, findsOneWidget);

      final openWidget = tester.widget<Text>(openFinder);
      expect(openWidget.style?.fontWeight, equals(FontWeight.w800));

      final tillFinder = find.text('Till 11:30 PM');
      expect(tillFinder, findsOneWidget);

      final tillWidget = tester.widget<Text>(tillFinder);
      expect(tillWidget.style?.fontWeight, equals(FontWeight.w500));
    });

    testWidgets('5. Long shop names gracefully truncate with ellipsis without card overflow',
        (tester) async {
      final longNameShop = shopA.copyWith(
        name: 'The Ultra Royal Gourmet Continental And Indian Express Dine In & Takeaway Restaurant',
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 360,
                child: ShopCard(
                  shop: longNameShop,
                  onTap: () {},
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.byType(ShopCard), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('6. Circular shop logo (3.7.3) and Slideshow (3.7.4) remain intact',
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
                    'https://cdn.yummbu.com/images/s1.jpg',
                    'https://cdn.yummbu.com/images/s2.jpg',
                  ],
                  onTap: () {},
                ),
              ),
            ),
          ),
        ),
      );

      // Circular logo on the right
      final logoFinder = find.byKey(const ValueKey('shop_card_circular_logo'));
      expect(logoFinder, findsOneWidget);

      // Slideshow PageView present
      final pageViewFinder = find.byKey(const ValueKey('shop_card_slideshow_pageview'));
      expect(pageViewFinder, findsOneWidget);

      // Circular logo uses shopA.shopLogoImageUrl
      final cachedImages = tester.widgetList<CachedNetworkImage>(find.byType(CachedNetworkImage));
      expect(cachedImages.any((img) => img.imageUrl == shopA.shopLogoImageUrl), isTrue);
    });
  });
}
