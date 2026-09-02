// BU Gate2Eat — Checkpoint 4.6 Image Loading & Memory Optimization Test Suite
// Verifies that CachedNetworkImage widgets decode at bounded memory dimensions (memCacheWidth / memCacheHeight)
// while leaving rendered UI layouts, aspect ratios, and upload compression pipeline 100% intact.

import 'dart:typed_data';

import 'package:bugate2eat_app/core/providers.dart';
import 'package:bugate2eat_app/features/home/widgets/shop_card.dart';
import 'package:bugate2eat_app/features/shop/widgets/universal_menu_item_card.dart';
import 'package:bugate2eat_app/models/menu_item_model.dart';
import 'package:bugate2eat_app/models/shop_model.dart';
import 'package:bugate2eat_app/services/image_optimization_service.dart' as ios;
import 'package:bugate2eat_app/services/local_storage_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeLocalStorageService extends Fake implements LocalStorageService {
  @override
  bool get isOnboarded => true;
  @override
  String get userPhone => '9876543210';
  @override
  String get userName => 'Test Student';
  @override
  String get customerId => 'cust_9876543210';
  @override
  List<String> get favoriteItemIds => [];
  @override
  String get themeMode => 'light';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeLocalStorageService fakeStorage;

  setUp(() {
    fakeStorage = _FakeLocalStorageService();
  });

  final testShop = Shop(
    id: 'shop_test_1',
    name: 'Raja Hotel',
    description: 'Delicious food',
    address: 'Gate 2 Commercial Complex',
    bannerUrl: 'https://example.com/banner.jpg',
    shopLogoImageUrl: 'https://example.com/logo.jpg',
    contactNumber: '9910707219',
    orderNumber: '9319566645',
    openTime: '08:00',
    closeTime: '23:30',
    isClosedOverride: false,
    isActive: true,
    sortOrder: 1,
    searchKeywords: const ['raja', 'hotel'],
    deliveryNote: 'Gate 2',
    createdAt: DateTime(2025, 1, 1),
    updatedAt: DateTime(2025, 1, 1),
  );

  const testItem = MenuItem(
    id: 'item_test_1',
    name: 'Paneer Butter Masala',
    details: 'Rich and creamy paneer curry',
    price: 180,
    imageUrl: 'https://example.com/item.jpg',
    categoryId: 'cat_gravy',
    isVeg: true,
    isAvailable: true,
    isRecommended: true,
    sortOrder: 1,
  );

  group('Checkpoint 4.6 — Image Loading & Memory Optimization Suite', () {
    testWidgets('TEST 1: UniversalMenuItemCard uses bounded memCacheWidth & memCacheHeight', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localStorageServiceProvider.overrideWithValue(fakeStorage),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 180,
                  height: 260,
                  child: UniversalMenuItemCard(
                    item: testItem,
                    shop: testShop,
                    perspective: ItemCardPerspective.customer,
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      final imageFinder = find.byType(CachedNetworkImage);
      expect(imageFinder, findsOneWidget);

      final cachedImage = tester.widget<CachedNetworkImage>(imageFinder);
      expect(cachedImage.memCacheWidth, 400);
      expect(cachedImage.memCacheHeight, 320);
      expect(cachedImage.fit, BoxFit.cover);
    });

    testWidgets('TEST 2: ShopCard uses bounded memCacheWidth for banner and logo', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localStorageServiceProvider.overrideWithValue(fakeStorage),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: ShopCard(
                shop: testShop,
                onTap: () {},
                slideshowImages: const ['https://example.com/banner.jpg'],
              ),
            ),
          ),
        ),
      );

      final imageWidgets = tester.widgetList<CachedNetworkImage>(find.byType(CachedNetworkImage)).toList();
      expect(imageWidgets.isNotEmpty, isTrue);

      // Banner slideshow image
      final bannerImage = imageWidgets.first;
      expect(bannerImage.memCacheWidth, 800);
      expect(bannerImage.fit, BoxFit.cover);

      // Circular shop logo
      final logoImage = imageWidgets.last;
      expect(logoImage.memCacheWidth, 160);
      expect(logoImage.memCacheHeight, 160);
      expect(logoImage.fit, BoxFit.cover);
    });

    test('TEST 3: Upload-side ImageOptimizationService limits remain untouched', () {
      // 300 KB for item, 800 KB for banner
      expect(ios.ImageOptimizationService.maxMenuItemBytes, 300 * 1024);
      expect(ios.ImageOptimizationService.maxBannerBytes, 800 * 1024);
    });

    test('TEST 4: Content type detection remains fully functional', () {
      final pngHeader = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
      expect(ios.ImageOptimizationService.detectContentType(Uint8List.fromList(pngHeader)), 'image/png');

      final webpHeader = [
        0x52, 0x49, 0x46, 0x46, 0x00, 0x00, 0x00, 0x00, 0x57, 0x45, 0x42, 0x50
      ];
      expect(ios.ImageOptimizationService.detectContentType(Uint8List.fromList(webpHeader)), 'image/webp');
    });

    test('TEST 5: Small images under size limit are preserved without re-encoding', () async {
      final smallBytes = Uint8List.fromList([1, 2, 3, 4, 5]);
      final result = await ios.ImageOptimizationService.optimizeImageBytes(
        originalBytes: smallBytes,
        type: ios.ImageTargetType.menuItem,
      );
      expect(result, equals(smallBytes));
    });
  });
}
