import 'package:bugate2eat_app/features/home/widgets/shop_card.dart';
import 'package:bugate2eat_app/models/shop_model.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Checkpoint 3.7.6 — Shop Card Size, Proportions & Premium Typography Tests', () {
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
      deliveryNote: 'Gate 3',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    testWidgets('1. Main banner uses dominant 1.85:1 restaurant-card aspect ratio',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 370,
                child: ShopCard(
                  shop: shopA,
                  onTap: () {},
                ),
              ),
            ),
          ),
        ),
      );

      final aspectRatioFinder = find.byWidgetPredicate(
        (widget) => widget is AspectRatio && (widget.aspectRatio - 1.85).abs() < 0.01,
      );
      expect(aspectRatioFinder, findsOneWidget);
    });

    testWidgets('2. Shop Name is bolder and larger with ExtraBold 800 typography',
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
      expect(textWidget.style?.fontSize, greaterThanOrEqualTo(17.5));
    });

    testWidgets('3. Information hierarchy: Name < Timing < Phone in unified cohesive block',
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

      final nameTop = tester.getTopLeft(find.text('Raja Hotel')).dy;
      final timingTop = tester.getTopLeft(find.text('8:00 AM – 11:30 PM')).dy;
      final phoneTop = tester.getTopLeft(find.text('9191919191')).dy;

      expect(nameTop < timingTop, isTrue);
      expect(timingTop < phoneTop, isTrue);

      // Excludes description & pickup note
      expect(find.text('Meals'), findsNothing);
      expect(find.text('Gate 3'), findsNothing);
    });

    testWidgets('4. Circular shop logo (3.7.3) remains 50/50 aligned at the new boundary',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 370,
                child: ShopCard(
                  shop: shopA,
                  onTap: () {},
                ),
              ),
            ),
          ),
        ),
      );

      final cardRect = tester.getRect(find.byType(ShopCard));
      final logoRect = tester.getRect(find.byKey(const ValueKey('shop_card_circular_logo')));

      final bannerHeight = 370 / 1.85;
      final expectedCircleTop = cardRect.top + bannerHeight - (logoRect.height / 2);
      expect((logoRect.top - expectedCircleTop).abs(), lessThan(2.0));
    });

    testWidgets('5. Slideshow (3.7.4) works seamlessly in 1.85:1 proportion',
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

      expect(find.byKey(const ValueKey('shop_card_slideshow_pageview')), findsOneWidget);
    });

    testWidgets('6. Zero layout overflow on narrow screens',
        (tester) async {
      final longShop = shopA.copyWith(
        name: 'The Royal Heritage Spice Garden & Sweets',
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 320, // Narrow screen
                child: ShopCard(
                  shop: longShop,
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
  });
}
