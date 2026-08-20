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
      // Generate a synthetic high-resolution test image (2000 x 2000 pixels with variation)
      final testImg = img.Image(width: 2000, height: 2000);
      for (var y = 0; y < 2000; y++) {
        for (var x = 0; x < 2000; x++) {
          testImg.setPixelRgba(
            x,
            y,
            (x * 73 + y * 151) % 256,
            (x * 199 + y * 37) % 256,
            (x * 31 + y * 89) % 256,
            255,
          );
        }
      }
      largeTestImageBytes =
          Uint8List.fromList(img.encodeJpg(testImg, quality: 100));
    });

    test('CASE 1: Large image (>300KB) for Menu Item is compressed <= 300 KB',
        () async {
      expect(largeTestImageBytes.lengthInBytes, greaterThan(300 * 1024));

      final optimized = await ImageOptimizationService.optimizeImageBytes(
        originalBytes: largeTestImageBytes,
        type: ImageTargetType.menuItem,
      );

      expect(optimized.lengthInBytes,
          lessThanOrEqualTo(ImageOptimizationService.maxMenuItemBytes));
      expect(optimized.lengthInBytes, lessThanOrEqualTo(300 * 1024));

      final decoded = img.decodeImage(optimized);
      expect(decoded, isNotNull);
      expect(decoded!.width, lessThanOrEqualTo(800));
      expect(decoded.height, lessThanOrEqualTo(800));
    });

    test('CASE 2: Large image (>800KB) for Shop Banner is compressed <= 800 KB',
        () async {
      expect(largeTestImageBytes.lengthInBytes, greaterThan(800 * 1024));

      final optimized = await ImageOptimizationService.optimizeImageBytes(
        originalBytes: largeTestImageBytes,
        type: ImageTargetType.shopBanner,
      );

      expect(optimized.lengthInBytes,
          lessThanOrEqualTo(ImageOptimizationService.maxBannerBytes));
      expect(optimized.lengthInBytes, lessThanOrEqualTo(800 * 1024));

      final decoded = img.decodeImage(optimized);
      expect(decoded, isNotNull);
      expect(decoded!.width, lessThanOrEqualTo(1400));
      expect(decoded.height, lessThanOrEqualTo(1400));
    });

    test(
        'CASE 3: Image already <= 300 KB is NOT compressed or altered (exact bytes preserved)',
        () async {
      final smallImg = img.Image(width: 200, height: 200);
      final smallPngBytes = Uint8List.fromList(img.encodePng(smallImg));
      expect(smallPngBytes.lengthInBytes, lessThanOrEqualTo(300 * 1024));

      final result = await ImageOptimizationService.optimizeImageBytes(
        originalBytes: smallPngBytes,
        type: ImageTargetType.menuItem,
      );

      // Exact bytes and format preserved
      expect(result.lengthInBytes, equals(smallPngBytes.lengthInBytes));
      expect(result, equals(smallPngBytes));
      expect(
          ImageOptimizationService.detectContentType(result), 'image/png');
    });

    test(
        'CASE 4: Banner already <= 800 KB is NOT compressed or altered (exact bytes preserved)',
        () async {
      final bannerImg = img.Image(width: 800, height: 400);
      final bannerBytes =
          Uint8List.fromList(img.encodeJpg(bannerImg, quality: 85));
      expect(bannerBytes.lengthInBytes, lessThanOrEqualTo(800 * 1024));

      final result = await ImageOptimizationService.optimizeImageBytes(
        originalBytes: bannerBytes,
        type: ImageTargetType.shopBanner,
      );

      expect(result.lengthInBytes, equals(bannerBytes.lengthInBytes));
      expect(result, equals(bannerBytes));
    });

    test('CASE 5: MIME type detection accurately identifies PNG, WebP, JPEG',
        () {
      final pngBytes = Uint8List.fromList([
        0x89,
        0x50,
        0x4E,
        0x47,
        0x0D,
        0x0A,
        0x1A,
        0x0A,
      ]);
      final webpBytes = Uint8List.fromList([
        0x52,
        0x49,
        0x46,
        0x46,
        0x00,
        0x00,
        0x00,
        0x00,
        0x57,
        0x45,
        0x42,
        0x50,
      ]);
      final jpegBytes = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0]);

      expect(
          ImageOptimizationService.detectContentType(pngBytes), 'image/png');
      expect(
          ImageOptimizationService.detectContentType(webpBytes), 'image/webp');
      expect(ImageOptimizationService.detectContentType(jpegBytes),
          'image/jpeg');
    });
  });
}
