import 'package:bugate2eat_app/features/home/widgets/shop_card.dart';
import 'package:bugate2eat_app/models/shop_model.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Checkpoint 3.7.3 — Shop Card Circular Shop Image Tests', () {
    testWidgets('1. Displays large circular shop logo with 50/50 boundary overlap on the right',
        (tester) async {
      final shop = Shop(
        id: 'shop_eatclub_1',
        name: 'Raja Hotel',
        description: 'Quality meals.',
        bannerUrl: 'https://example.com/raja_hotel.jpg',
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

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 360,
                child: ShopCard(
                  shop: shop,
                  onTap: () {},
                ),
              ),
            ),
          ),
        ),
      );

      // Verify circular logo widget is found
      final circularLogoFinder = find.byKey(const ValueKey('shop_card_circular_logo'));
      expect(circularLogoFinder, findsOneWidget);

      // Verify it's on the right side of the card
      final cardRect = tester.getRect(find.byType(ShopCard));
      final logoRect = tester.getRect(circularLogoFinder);

      expect(logoRect.right, lessThanOrEqualTo(cardRect.right));
      expect(logoRect.center.dx, greaterThan(cardRect.center.dx),
          reason: 'Circular logo must be on the right side');

      // Verify 50/50 boundary overlap:
      final bannerHeight = 360 / 1.85;
      final expectedCircleTop = cardRect.top + bannerHeight - (logoRect.height / 2);
      expect((logoRect.top - expectedCircleTop).abs(), lessThan(2.0),
          reason: 'Circle center must align at banner boundary (50% upper, 50% lower)');
    });

    testWidgets('2. Dynamic shop image updates when shop bannerUrl updates',
        (tester) async {
      final initialShop = Shop(
        id: 'shop_dynamic',
        name: 'UP16 Coffee Queen',
        description: 'Coffee and snacks',
        bannerUrl: 'https://example.com/initial_coffee.jpg',
        contactNumber: '8295643910',
        orderNumber: '8295643910',
        openTime: '08:00',
        closeTime: '01:30',
        isClosedOverride: false,
        isActive: true,
        sortOrder: 2,
        searchKeywords: ['coffee'],
        deliveryNote: 'Gate 3',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final updatedShop = initialShop.copyWith(
        bannerUrl: 'https://example.com/updated_coffee.jpg',
      );

      // Pump initial state
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 360,
                child: ShopCard(
                  shop: initialShop,
                  onTap: () {},
                ),
              ),
            ),
          ),
        ),
      );

      var cachedImageFinder = find.descendant(
        of: find.byKey(const ValueKey('shop_card_circular_logo')),
        matching: find.byType(CachedNetworkImage),
      );
      expect(cachedImageFinder, findsOneWidget);
      var imageWidget = tester.widget<CachedNetworkImage>(cachedImageFinder);
      expect(imageWidget.imageUrl, 'https://example.com/initial_coffee.jpg');

      // Update widget with new shop state
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 360,
                child: ShopCard(
                  shop: updatedShop,
                  onTap: () {},
                ),
              ),
            ),
          ),
        ),
      );

      cachedImageFinder = find.descendant(
        of: find.byKey(const ValueKey('shop_card_circular_logo')),
        matching: find.byType(CachedNetworkImage),
      );
      imageWidget = tester.widget<CachedNetworkImage>(cachedImageFinder);
      expect(imageWidget.imageUrl, 'https://example.com/updated_coffee.jpg');
    });

    testWidgets('3. Two distinct shops render their own distinct circular logos',
        (tester) async {
      final shopA = Shop(
        id: 'shop_a',
        name: 'Raja Hotel',
        description: '',
        bannerUrl: 'https://example.com/shop_a_logo.jpg',
        contactNumber: '111',
        orderNumber: '111',
        openTime: '08:00',
        closeTime: '23:30',
        isClosedOverride: false,
        isActive: true,
        sortOrder: 1,
        searchKeywords: [],
        deliveryNote: '',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final shopB = Shop(
        id: 'shop_b',
        name: 'Zulus Pizza',
        description: '',
        bannerUrl: 'https://example.com/shop_b_logo.jpg',
        contactNumber: '222',
        orderNumber: '222',
        openTime: '10:00',
        closeTime: '22:00',
        isClosedOverride: false,
        isActive: true,
        sortOrder: 2,
        searchKeywords: [],
        deliveryNote: '',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: ListView(
                children: [
                  ShopCard(shop: shopA, onTap: () {}),
                  ShopCard(shop: shopB, onTap: () {}),
                ],
              ),
            ),
          ),
        ),
      );

      final logos = find.byKey(const ValueKey('shop_card_circular_logo'));
      expect(logos, findsNWidgets(2));

      final firstLogoImage = tester.widget<CachedNetworkImage>(
        find.descendant(of: logos.first, matching: find.byType(CachedNetworkImage)),
      );
      final secondLogoImage = tester.widget<CachedNetworkImage>(
        find.descendant(of: logos.last, matching: find.byType(CachedNetworkImage)),
      );

      expect(firstLogoImage.imageUrl, 'https://example.com/shop_a_logo.jpg');
      expect(secondLogoImage.imageUrl, 'https://example.com/shop_b_logo.jpg');
      expect(firstLogoImage.imageUrl != secondLogoImage.imageUrl, isTrue);
    });

    testWidgets('4. Missing/empty bannerUrl gracefully renders placeholder without crash',
        (tester) async {
      final emptyShop = Shop(
        id: 'shop_empty',
        name: 'No Image Cafe',
        description: '',
        bannerUrl: '',
        contactNumber: '333',
        orderNumber: '333',
        openTime: '08:00',
        closeTime: '20:00',
        isClosedOverride: false,
        isActive: true,
        sortOrder: 3,
        searchKeywords: [],
        deliveryNote: '',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 360,
                child: ShopCard(shop: emptyShop, onTap: () {}),
              ),
            ),
          ),
        ),
      );

      final logoFinder = find.byKey(const ValueKey('shop_card_circular_logo'));
      expect(logoFinder, findsOneWidget);

      // Verify storefront fallback icon is rendered
      expect(
        find.descendant(of: logoFinder, matching: find.byIcon(Icons.storefront_rounded)),
        findsOneWidget,
      );
    });

    testWidgets('5. Text content (Name, Timing, Phone) and Status Badge remain present and functional',
        (tester) async {
      var tapped = false;
      final shop = Shop(
        id: 'shop_full',
        name: 'Bennett Food Court',
        description: '',
        bannerUrl: 'https://example.com/bfc.jpg',
        contactNumber: '9876543210',
        orderNumber: '9876543210',
        openTime: '08:00',
        closeTime: '23:30',
        isClosedOverride: false,
        isActive: true,
        sortOrder: 1,
        searchKeywords: [],
        deliveryNote: '',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 360,
                child: ShopCard(
                  shop: shop,
                  onTap: () {
                    tapped = true;
                  },
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.text('Bennett Food Court'), findsOneWidget);
      expect(find.text('8:00 AM – 11:30 PM'), findsOneWidget);
      expect(find.text('9876543210'), findsOneWidget);
      expect(find.text('OPEN'), findsOneWidget);

      await tester.tap(find.byType(ShopCard));
      expect(tapped, isTrue);
    });
  });
}
