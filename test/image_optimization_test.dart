// BU Gate2Eat — Image Optimization Unit & Regression Suite

import 'dart:typed_data';

import 'package:bugate2eat_app/services/image_optimization_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BU Gate2Eat — Image Optimization Pipeline', () {
    late Uint8List largeTestImageBytes;

    setUp(() {
      // Generate a synthetic high-resolution test image (2000 x 2000 pixels)
      final testImg = img.Image(width: 2000, height: 2000);
      for (var y = 0; y < 2000; y++) {
        for (var x = 0; x < 2000; x++) {
          testImg.setPixelRgba(x, y, (x * 255) ~/ 2000, (y * 255) ~/ 2000, 128, 255);
        }
      }
      largeTestImageBytes = Uint8List.fromList(img.encodeJpg(testImg, quality: 100));
    });

    test('CASE 1: Large image optimized for Menu Item is strictly <= 300 KB', () async {
      final optimized = await ImageOptimizationService.optimizeImageBytes(
        originalBytes: largeTestImageBytes,
        type: ImageTargetType.menuItem,
      );

      expect(optimized.lengthInBytes, lessThanOrEqualTo(ImageOptimizationService.maxMenuItemBytes));
      expect(optimized.lengthInBytes, lessThanOrEqualTo(300 * 1024));

      final decoded = img.decodeImage(optimized);
      expect(decoded, isNotNull);
      expect(decoded!.width, lessThanOrEqualTo(800));
      expect(decoded.height, lessThanOrEqualTo(800));
    });

    test('CASE 2: Large image optimized for Shop Banner is strictly <= 800 KB', () async {
      final optimized = await ImageOptimizationService.optimizeImageBytes(
        originalBytes: largeTestImageBytes,
        type: ImageTargetType.shopBanner,
      );

      expect(optimized.lengthInBytes, lessThanOrEqualTo(ImageOptimizationService.maxBannerBytes));
      expect(optimized.lengthInBytes, lessThanOrEqualTo(800 * 1024));

      final decoded = img.decodeImage(optimized);
      expect(decoded, isNotNull);
      expect(decoded!.width, lessThanOrEqualTo(1400));
      expect(decoded.height, lessThanOrEqualTo(1400));
    });

    test('CASE 3: Already small image passes through without corruption', () async {
      final smallImg = img.Image(width: 100, height: 100);
      final smallBytes = Uint8List.fromList(img.encodeJpg(smallImg, quality: 80));

      final optimized = await ImageOptimizationService.optimizeImageBytes(
        originalBytes: smallBytes,
        type: ImageTargetType.menuItem,
      );

      expect(optimized.lengthInBytes, lessThanOrEqualTo(ImageOptimizationService.maxMenuItemBytes));
      final decoded = img.decodeImage(optimized);
      expect(decoded, isNotNull);
      expect(decoded!.width, 100);
      expect(decoded.height, 100);
    });
  });
}
