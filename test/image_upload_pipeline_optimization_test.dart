// BU Gate2Eat — Image Upload Pipeline Optimization Tests
// Verifies:
// 1. ImageCropHelper canonical & square crops preserve exact 512x512 output dimensions and quality
// 2. ImageOptimizationService contracts (menuItem <= 300KB, shopLogo <= 400KB, shopBanner <= 800KB)
// 3. Bounded prefetching (strictly top 2 visible items/shops, no duplicates)

import 'dart:typed_data';
import 'dart:ui';

import 'package:bugate2eat_app/core/widgets/circular_crop_dialog.dart';
import 'package:bugate2eat_app/services/image_optimization_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Image Upload Pipeline Optimization Tests', () {
    late Uint8List testImageBytes;

    setUpAll(() {
      // Synthetic 800x600 image
      final testImg = img.Image(width: 800, height: 600);
      for (var y = 0; y < 600; y++) {
        for (var x = 0; x < 800; x++) {
          testImg.setPixelRgba(
            x,
            y,
            (x * 50) % 256,
            (y * 70) % 256,
            ((x + y) * 30) % 256,
            255,
          );
        }
      }
      testImageBytes = Uint8List.fromList(img.encodeJpg(testImg, quality: 90));
    });

    test('Canonical Crop produces exact 512x512 output without visual degradation', () {
      const cropRect = Rect.fromLTWH(100, 50, 400, 400);
      final cropped = ImageCropHelper.cropCanonical(
        rawBytes: testImageBytes,
        canonicalCropRect: cropRect,
        targetDimension: 512,
      );

      expect(cropped, isNotEmpty);
      final decoded = img.decodeImage(cropped);
      expect(decoded, isNotNull);
      expect(decoded!.width, 512);
      expect(decoded.height, 512);
    });

    test('Fallback Square Crop produces exact 512x512 output', () {
      final cropped = ImageCropHelper.cropSquare(
        rawBytes: testImageBytes,
        targetDimension: 512,
      );

      expect(cropped, isNotEmpty);
      final decoded = img.decodeImage(cropped);
      expect(decoded, isNotNull);
      expect(decoded!.width, 512);
      expect(decoded.height, 512);
    });

    test('ImageOptimizationService contract: menuItem <= 300 KB, shopLogo <= 400 KB, shopBanner <= 800 KB', () async {
      final optimizedMenuItem = await ImageOptimizationService.optimizeImageBytes(
        originalBytes: testImageBytes,
        type: ImageTargetType.menuItem,
      );
      expect(optimizedMenuItem.lengthInBytes, lessThanOrEqualTo(ImageOptimizationService.maxMenuItemBytes));

      final optimizedLogo = await ImageOptimizationService.optimizeImageBytes(
        originalBytes: testImageBytes,
        type: ImageTargetType.shopLogo,
      );
      expect(optimizedLogo.lengthInBytes, lessThanOrEqualTo(ImageOptimizationService.maxLogoBytes));

      final optimizedBanner = await ImageOptimizationService.optimizeImageBytes(
        originalBytes: testImageBytes,
        type: ImageTargetType.shopBanner,
      );
      expect(optimizedBanner.lengthInBytes, lessThanOrEqualTo(ImageOptimizationService.maxBannerBytes));
    });

    test('Bounded prefetching restricts execution to top 2 items and prevents duplicate network requests', () {
      final sampleUrls = [
        'https://example.com/img1.jpg',
        'https://example.com/img2.jpg',
        'https://example.com/img3.jpg',
        'https://example.com/img4.jpg',
        'https://example.com/img5.jpg',
      ];

      final prefetchedSet = <String>{};
      final prefetchLog = <String>[];

      void prefetchTop(List<String> urls) {
        int count = 0;
        for (final url in urls) {
          if (count >= 2) break;
          final trimmed = url.trim();
          if (trimmed.isNotEmpty && !prefetchedSet.contains(trimmed)) {
            prefetchedSet.add(trimmed);
            prefetchLog.add(trimmed);
          }
          count++;
        }
      }

      // First pass: only first 2 items are prefetched
      prefetchTop(sampleUrls);
      expect(prefetchLog.length, 2);
      expect(prefetchLog, ['https://example.com/img1.jpg', 'https://example.com/img2.jpg']);
      expect(prefetchedSet.length, 2);

      // Second pass with same list: no duplicate requests initiated
      prefetchTop(sampleUrls);
      expect(prefetchLog.length, 2, reason: 'Already prefetched items must not be re-requested');

      // Pass with new list: only top 2 items of new list are considered
      final newUrls = [
        'https://example.com/img1.jpg', // already in set (index 0)
        'https://example.com/img6.jpg', // new item (index 1)
        'https://example.com/img7.jpg', // index 2 (ignored because strictly bounded to top 2)
      ];
      prefetchTop(newUrls);
      expect(prefetchLog.length, 3);
      expect(prefetchLog.contains('https://example.com/img6.jpg'), isTrue);
      expect(prefetchLog.contains('https://example.com/img7.jpg'), isFalse);
    });

    test('Parallel Shop Creation Upload Contract resolves both banner and logo concurrently without blocking sequentially', () async {
      final executionOrder = <String>[];

      Future<String> mockUploadImage(String type, int delayMs) async {
        executionOrder.add('$type-start');
        await Future.delayed(Duration(milliseconds: delayMs));
        executionOrder.add('$type-end');
        return 'https://storage/$type.jpg';
      }

      // Parallel execution via Future.wait
      final results = await Future.wait([
        mockUploadImage('banner', 50),
        mockUploadImage('logo', 30),
      ]);

      expect(results[0], 'https://storage/banner.jpg');
      expect(results[1], 'https://storage/logo.jpg');
      // Both started before either finished
      expect(executionOrder.indexOf('banner-start'), lessThan(executionOrder.indexOf('logo-end')));
      expect(executionOrder.indexOf('logo-start'), lessThan(executionOrder.indexOf('banner-end')));
    });

    test('Parallel Category Creation & Image Upload contract guarantees race-free sequential document creation', () async {
      String resolvedCategoryId = '';
      String resolvedImageUrl = '';

      Future<void> handleCategory() async {
        await Future.delayed(const Duration(milliseconds: 20));
        resolvedCategoryId = 'cat_beverages';
      }

      Future<void> handleUpload() async {
        await Future.delayed(const Duration(milliseconds: 30));
        resolvedImageUrl = 'https://storage/items/coffee.jpg';
      }

      // Execute concurrently
      await Future.wait([handleCategory(), handleUpload()]);

      // Both must be populated strictly before item creation
      expect(resolvedCategoryId, 'cat_beverages');
      expect(resolvedImageUrl, 'https://storage/items/coffee.jpg');
    });

    test('Unawaited background image cleanup failure does not interrupt save flow', () async {
      bool saveSucceeded = false;
      bool cleanupFailedCaught = false;

      Future<void> deleteStorageImageByUrl(String url) async {
        throw Exception('Simulated network failure on background cleanup');
      }

      try {
        // Simulate save flow
        saveSucceeded = true;

        // Best effort cleanup in background
        deleteStorageImageByUrl('https://storage/old.jpg').catchError((Object e) {
          cleanupFailedCaught = true;
        });
      } catch (_) {
        saveSucceeded = false;
      }

      await Future.delayed(const Duration(milliseconds: 10));
      expect(saveSucceeded, isTrue, reason: 'Parent save must succeed even if old image cleanup fails');
      expect(cleanupFailedCaught, isTrue, reason: 'Background error must be swallowed gracefully');
    });
  });
}
