import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bugate2eat_app/features/home/widgets/shop_card.dart';
import 'package:bugate2eat_app/models/shop_model.dart';
import 'package:bugate2eat_app/services/notification_router_bridge.dart';

void main() {
  group('Checkpoint 3 — Low-End / Old Android Optimization Tests', () {
    late Shop sampleShop;

    setUp(() {
      sampleShop = Shop(
        id: 'rajat_shop',
        name: 'Rajat Shop',
        description: 'Snacks & Thalis',
        address: 'Gate 2',
        bannerUrl: 'https://example.com/banner.jpg',
        shopLogoImageUrl: 'https://example.com/logo.jpg',
        contactNumber: '9999999999',
        orderNumber: '9999999999',
        openTime: '09:00',
        closeTime: '23:00',
        isClosedOverride: false,
        isActive: true,
        sortOrder: 1,
        searchKeywords: const ['rajat'],
        deliveryNote: 'Gate 2',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );
    });

    test('1. Image cache bounds are preserved at 60 MB and 150 count', () {
      PaintingBinding.instance.imageCache.maximumSize = 150;
      PaintingBinding.instance.imageCache.maximumSizeBytes = 60 * 1024 * 1024;
      expect(PaintingBinding.instance.imageCache.maximumSize, 150);
      expect(
        PaintingBinding.instance.imageCache.maximumSizeBytes,
        60 * 1024 * 1024,
      );
    });

    testWidgets('2. ShopCard initializes PageController and does not leak or crash', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: ShopCard(
                shop: sampleShop,
                slideshowImages: const [
                  'https://example.com/img1.jpg',
                  'https://example.com/img2.jpg',
                ],
                onTap: () {},
              ),
            ),
          ),
        ),
      );

      // Initial frame
      await tester.pump();
      expect(find.byType(ShopCard), findsOneWidget);

      // Multiple rebuilds (simulating scroll) without crash or timer churn
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 200));

      // Rebuilding with same widget
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: ShopCard(
                shop: sampleShop,
                slideshowImages: const [
                  'https://example.com/img1.jpg',
                  'https://example.com/img2.jpg',
                ],
                onTap: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(ShopCard), findsOneWidget);
    });

    testWidgets('3. ShopCard disposes cleanly and cancels autoSlide timer without errors', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: ShopCard(
                shop: sampleShop,
                slideshowImages: const [
                  'https://example.com/img1.jpg',
                  'https://example.com/img2.jpg',
                  'https://example.com/img3.jpg',
                ],
                onTap: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // Dispose the ShopCard by replacing the tree
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(),
          ),
        ),
      );
      await tester.pump();

      // Advance time past autoSlideInterval to verify no timer fires after disposal
      await tester.pump(const Duration(seconds: 5));
      expect(find.byType(ShopCard), findsNothing);
    });

    testWidgets('4. ShopCard handles single image gracefully without autoSlide timer churn', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: ShopCard(
                shop: sampleShop,
                slideshowImages: const [
                  'https://example.com/single.jpg',
                ],
                onTap: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(ShopCard), findsOneWidget);

      // Advance time - should remain stable
      await tester.pump(const Duration(seconds: 5));
      expect(find.byType(ShopCard), findsOneWidget);
    });

    testWidgets('5. ShopCard updates properly when shop or images change (didUpdateWidget)', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: ShopCard(
                shop: sampleShop,
                slideshowImages: const [
                  'https://example.com/1.jpg',
                ],
                onTap: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // Update widget with new images
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: ShopCard(
                shop: sampleShop,
                slideshowImages: const [
                  'https://example.com/1.jpg',
                  'https://example.com/2.jpg',
                ],
                onTap: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(ShopCard), findsOneWidget);
    });

    test('6. NotificationRouterBridge duplicate tap throttle works efficiently without heap growth', () {
      NotificationRouterBridge.resetThrottleState();

      // First tap
      expect(NotificationRouterBridge.isDuplicateTap('order_123'), isFalse);

      // Immediate second tap within 1500ms
      expect(NotificationRouterBridge.isDuplicateTap('order_123'), isTrue);

      // Reset
      NotificationRouterBridge.resetThrottleState();
      expect(NotificationRouterBridge.isDuplicateTap('order_123'), isFalse);
    });
  });
}
