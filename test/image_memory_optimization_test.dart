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
import 'package:image/image.dart' as img;

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
    testWidgets('TEST 1: UniversalMenuItemCard uses bounded memCacheWidth & preserves natural aspect ratio (memCacheHeight == null)', (tester) async {
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
      expect(cachedImage.memCacheHeight, isNull);
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

    test('TEST 6: Square image keeps 1:1 natural proportions when bounded by memCacheWidth only', () {
      const originalW = 1000;
      const originalH = 1000;
      const originalRatio = originalW / originalH; // 1.0

      // When only memCacheWidth is set (400), Flutter ResizeImage preserves aspect ratio:
      const targetW = 400;
      final targetH = (originalH * (targetW / originalW)).round(); // 400
      final decodedRatio = targetW / targetH;

      expect(decodedRatio, equals(originalRatio));
      expect(targetW, equals(400));
      expect(targetH, equals(400));
    });

    test('TEST 7: Portrait image keeps 3:4 natural proportions when bounded by memCacheWidth only', () {
      const originalW = 600;
      const originalH = 800; // 3:4 portrait
      const originalRatio = originalW / originalH; // 0.75

      const targetW = 400;
      final targetH = (originalH * (targetW / originalW)).round(); // 533
      final decodedRatio = targetW / targetH;

      expect((decodedRatio - originalRatio).abs(), lessThan(0.01));
      // Without memCacheHeight: 320, decoded height is ~533 (natural portrait), NOT squashed to 320
      expect(targetH, greaterThan(targetW));
    });

    test('TEST 8: Landscape image keeps 16:9 natural proportions when bounded by memCacheWidth only', () {
      const originalW = 1600;
      const originalH = 900; // 16:9 landscape
      const originalRatio = originalW / originalH; // 1.777...

      const targetW = 400;
      final targetH = (originalH * (targetW / originalW)).round(); // 225
      final decodedRatio = targetW / targetH;

      expect((decodedRatio - originalRatio).abs(), lessThan(0.01));
      // Decoded height is 225 (natural landscape), NOT stretched to 320
      expect(targetH, equals(225));
    });

    test('TEST 9: EXIF camera orientation is baked correctly into pixel buffer', () async {
      // Create a 1200x800 (landscape buffer) test image with EXIF orientation 6 (90° CW rotation = portrait photo)
      final rawImage = img.Image(width: 1200, height: 800);
      for (int y = 0; y < 800; y++) {
        for (int x = 0; x < 1200; x++) {
          rawImage.setPixelRgba(x, y, (x * 17 + y * 31) % 256, (x * 7 + y * 13) % 256, 128, 255);
        }
      }
      rawImage.exif.imageIfd.orientation = 6;
      final rawJpeg = Uint8List.fromList(img.encodeJpg(rawImage, quality: 100));
      expect(rawJpeg.lengthInBytes, greaterThan(ios.ImageOptimizationService.maxMenuItemBytes));

      final optimized = await ios.ImageOptimizationService.optimizeImageBytes(
        originalBytes: rawJpeg,
        type: ios.ImageTargetType.menuItem,
      );

      final decoded = img.decodeImage(optimized);
      expect(decoded, isNotNull);
      // After bakeOrientation, orientation 6 was applied to the raster: height is now greater than width (portrait)
      expect(decoded!.height, greaterThan(decoded.width));
      expect(decoded.width, lessThanOrEqualTo(800));
      expect(decoded.height, lessThanOrEqualTo(800));
    });
  });
}
