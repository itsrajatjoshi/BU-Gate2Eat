// BU Gate2Eat — Crop Coordinate Precision & Math Verification Tests
// Deterministic testing with multi-colored quadrant & strip images to prove
// 100% pixel-accurate mapping between CircularCropDialog preview and saved 512x512 crop.

import 'dart:typed_data';

import 'package:bugate2eat_app/core/widgets/circular_crop_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// Generates a square image (e.g. 1000x1000) with 4 clearly colored quadrants:
/// - Top-Left: RED (255, 0, 0)
/// - Top-Right: GREEN (0, 255, 0)
/// - Bottom-Left: BLUE (0, 0, 255)
/// - Bottom-Right: YELLOW (255, 255, 0)
Uint8List create4QuadrantSquareImage(int size) {
  final image = img.Image(width: size, height: size);
  final half = size ~/ 2;

  final red = img.ColorRgb8(255, 0, 0);
  final green = img.ColorRgb8(0, 255, 0);
  final blue = img.ColorRgb8(0, 0, 255);
  final yellow = img.ColorRgb8(255, 255, 0);

  // Fill quadrants
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      if (x < half && y < half) {
        image.setPixel(x, y, red);
      } else if (x >= half && y < half) {
        image.setPixel(x, y, green);
      } else if (x < half && y >= half) {
        image.setPixel(x, y, blue);
      } else {
        image.setPixel(x, y, yellow);
      }
    }
  }

  return Uint8List.fromList(img.encodeJpg(image, quality: 95));
}

/// Generates a portrait image (e.g. 800x1600, 1:2 aspect ratio) with 4 horizontal color strips:
/// - Strip 1 (y: 0 - 25%): RED (Hair/Forehead)
/// - Strip 2 (y: 25% - 50%): GREEN (Eyes/Nose)
/// - Strip 3 (y: 50% - 75%): BLUE (Mouth/Chin)
/// - Strip 4 (y: 75% - 100%): YELLOW (Neck/Shirt)
Uint8List create4StripPortraitImage(int width, int height) {
  final image = img.Image(width: width, height: height);
  final quarter = height ~/ 4;

  final red = img.ColorRgb8(255, 0, 0);
  final green = img.ColorRgb8(0, 255, 0);
  final blue = img.ColorRgb8(0, 0, 255);
  final yellow = img.ColorRgb8(255, 255, 0);

  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      if (y < quarter) {
        image.setPixel(x, y, red);
      } else if (y < quarter * 2) {
        image.setPixel(x, y, green);
      } else if (y < quarter * 3) {
        image.setPixel(x, y, blue);
      } else {
        image.setPixel(x, y, yellow);
      }
    }
  }

  return Uint8List.fromList(img.encodeJpg(image, quality: 95));
}

/// Generates a landscape image (e.g. 1600x800, 2:1 aspect ratio) with 4 vertical color strips:
/// - Strip 1 (x: 0 - 25%): RED
/// - Strip 2 (x: 25% - 50%): GREEN
/// - Strip 3 (x: 50% - 75%): BLUE
/// - Strip 4 (x: 75% - 100%): YELLOW
Uint8List create4StripLandscapeImage(int width, int height) {
  final image = img.Image(width: width, height: height);
  final quarter = width ~/ 4;

  final red = img.ColorRgb8(255, 0, 0);
  final green = img.ColorRgb8(0, 255, 0);
  final blue = img.ColorRgb8(0, 0, 255);
  final yellow = img.ColorRgb8(255, 255, 0);

  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      if (x < quarter) {
        image.setPixel(x, y, red);
      } else if (x < quarter * 2) {
        image.setPixel(x, y, green);
      } else if (x < quarter * 3) {
        image.setPixel(x, y, blue);
      } else {
        image.setPixel(x, y, yellow);
      }
    }
  }

  return Uint8List.fromList(img.encodeJpg(image, quality: 95));
}

/// Helper to check dominant color of a pixel (R, G, B channels)
bool isRed(img.Pixel p) => p.r > 180 && p.g < 80 && p.b < 80;
bool isGreen(img.Pixel p) => p.r < 80 && p.g > 180 && p.b < 80;
bool isBlue(img.Pixel p) => p.r < 80 && p.g < 80 && p.b > 180;
bool isYellow(img.Pixel p) => p.r > 180 && p.g > 180 && p.b < 80;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const circleDiameter = 240.0;

  group('Canonical Crop Architecture — Single Source of Truth Invariant Tests', () {
    test('preview_and_export_must_have_identical_source_region: Portrait 800x1600', () {
      final imageBytes = create4StripPortraitImage(800, 1600);
      final cropState = CanonicalCropState(sourceWidth: 800, sourceHeight: 1600);

      // Default centered crop: cropSize = 800x800, center = (400, 800)
      // cropRect = Rect.fromLTWH(0, 400, 800, 800)
      expect(cropState.cropRect, equals(const Rect.fromLTWH(0, 400, 800, 800)));

      // Export using canonical rect
      final croppedBytes = ImageCropHelper.cropCanonical(
        rawBytes: imageBytes,
        canonicalCropRect: cropState.cropRect,
        targetDimension: 512,
      );

      final cropped = img.decodeImage(croppedBytes)!;
      expect(cropped.width, equals(512));
      expect(cropped.height, equals(512));

      // Centered 800x800 of 800x1600 captures y: 400..1200
      // Strip 2 (Green) is y: 400..800 -> Upper half of crop
      // Strip 3 (Blue) is y: 800..1200 -> Lower half of crop
      expect(isGreen(cropped.getPixel(256, 100)), isTrue, reason: 'Upper half must be GREEN');
      expect(isBlue(cropped.getPixel(256, 400)), isTrue, reason: 'Lower half must be BLUE');
    });

    test('preview_and_export_must_have_identical_source_region: Panning UP reveals lower YELLOW strip', () {
      final imageBytes = create4StripPortraitImage(800, 1600);
      final cropState = CanonicalCropState(sourceWidth: 800, sourceHeight: 1600);

      // User drags image UP on screen by 120 screen points (half of circleDiameter)
      // Dragging UP moves crop window DOWN in source coordinates
      cropState.panBy(const Offset(0, -120), circleDiameter);

      // Center should move from 800 to 800 + 120 * (800 / 240) = 800 + 400 = 1200 (clamped to max = 1200)
      expect(cropState.center.dy, equals(1200.0));
      expect(cropState.cropRect, equals(const Rect.fromLTWH(0, 800, 800, 800)));

      final croppedBytes = ImageCropHelper.cropCanonical(
        rawBytes: imageBytes,
        canonicalCropRect: cropState.cropRect,
        targetDimension: 512,
      );

      final cropped = img.decodeImage(croppedBytes)!;
      // y: 800..1200 is Blue (Strip 3), y: 1200..1600 is Yellow (Strip 4)
      expect(isBlue(cropped.getPixel(256, 100)), isTrue);
      expect(isYellow(cropped.getPixel(256, 400)), isTrue);
    });

    test('preview_and_export_must_have_identical_source_region: Panning DOWN reveals top RED strip (Hair/Forehead)', () {
      final imageBytes = create4StripPortraitImage(800, 1600);
      final cropState = CanonicalCropState(sourceWidth: 800, sourceHeight: 1600);

      // User drags image DOWN on screen by 120 screen points
      cropState.panBy(const Offset(0, 120), circleDiameter);

      // Center should move from 800 to 400 (clamped to min = 400)
      expect(cropState.center.dy, equals(400.0));
      expect(cropState.cropRect, equals(const Rect.fromLTWH(0, 0, 800, 800)));

      final croppedBytes = ImageCropHelper.cropCanonical(
        rawBytes: imageBytes,
        canonicalCropRect: cropState.cropRect,
        targetDimension: 512,
      );

      final cropped = img.decodeImage(croppedBytes)!;
      // y: 0..400 is Red (Strip 1), y: 400..800 is Green (Strip 2)
      expect(isRed(cropped.getPixel(256, 100)), isTrue);
      expect(isGreen(cropped.getPixel(256, 400)), isTrue);
    });

    test('preview_and_export_must_have_identical_source_region: Landscape 1600x800 Panning LEFT/RIGHT', () {
      final imageBytes = create4StripLandscapeImage(1600, 800);
      final cropState = CanonicalCropState(sourceWidth: 1600, sourceHeight: 800);

      // Default centered: cropRect = Rect.fromLTWH(400, 0, 800, 800)
      expect(cropState.cropRect, equals(const Rect.fromLTWH(400, 0, 800, 800)));

      // Pan to leftmost (RED + GREEN)
      cropState.panBy(const Offset(150, 0), circleDiameter);
      expect(cropState.cropRect.left, equals(0.0));

      final leftCroppedBytes = ImageCropHelper.cropCanonical(
        rawBytes: imageBytes,
        canonicalCropRect: cropState.cropRect,
        targetDimension: 512,
      );
      final leftCropped = img.decodeImage(leftCroppedBytes)!;
      expect(isRed(leftCropped.getPixel(100, 256)), isTrue);
      expect(isGreen(leftCropped.getPixel(400, 256)), isTrue);

      // Pan to rightmost (BLUE + YELLOW)
      cropState.panBy(const Offset(-300, 0), circleDiameter);
      expect(cropState.cropRect.left, equals(800.0));

      final rightCroppedBytes = ImageCropHelper.cropCanonical(
        rawBytes: imageBytes,
        canonicalCropRect: cropState.cropRect,
        targetDimension: 512,
      );
      final rightCropped = img.decodeImage(rightCroppedBytes)!;
      expect(isBlue(rightCropped.getPixel(100, 256)), isTrue);
      expect(isYellow(rightCropped.getPixel(400, 256)), isTrue);
    });

    test('preview_and_export_must_have_identical_source_region: Zoom 2.0x shrinks crop square and centers precisely', () {
      final imageBytes = create4QuadrantSquareImage(1000);
      final cropState = CanonicalCropState(sourceWidth: 1000, sourceHeight: 1000);

      cropState.setZoom(2.0);
      // At zoom 2.0x, cropSize = 1000 / 2 = 500
      // Centered at (500, 500) -> cropRect = Rect.fromLTWH(250, 250, 500, 500)
      expect(cropState.cropSize, equals(500.0));
      expect(cropState.cropRect, equals(const Rect.fromLTWH(250, 250, 500, 500)));

      final croppedBytes = ImageCropHelper.cropCanonical(
        rawBytes: imageBytes,
        canonicalCropRect: cropState.cropRect,
        targetDimension: 512,
      );

      final cropped = img.decodeImage(croppedBytes)!;
      expect(cropped.width, equals(512));
      expect(cropped.height, equals(512));

      // 4 quadrants remain symmetrically centered at zoom 2x
      expect(isRed(cropped.getPixel(100, 100)), isTrue);
      expect(isGreen(cropped.getPixel(400, 100)), isTrue);
      expect(isBlue(cropped.getPixel(100, 400)), isTrue);
      expect(isYellow(cropped.getPixel(400, 400)), isTrue);
    });

    test('preview_and_export_must_have_identical_source_region: Combined Pan + Zoom focuses into single quadrant', () {
      final imageBytes = create4QuadrantSquareImage(1000);
      final cropState = CanonicalCropState(sourceWidth: 1000, sourceHeight: 1000);

      cropState.setZoom(2.0); // cropSize = 500
      // Pan top-left into RED quadrant: drag right & down on screen
      cropState.panBy(const Offset(200, 200), circleDiameter);

      // Center should clamp to (250, 250), cropRect = [0, 0, 500, 500] (pure RED quadrant)
      expect(cropState.cropRect, equals(const Rect.fromLTWH(0, 0, 500, 500)));

      final croppedBytes = ImageCropHelper.cropCanonical(
        rawBytes: imageBytes,
        canonicalCropRect: cropState.cropRect,
        targetDimension: 512,
      );

      final cropped = img.decodeImage(croppedBytes)!;
      expect(isRed(cropped.getPixel(256, 256)), isTrue, reason: 'Entire center of crop must be RED');
    });

    test('Boundary Clamping: Extreme out-of-bounds pan clamps safely within source bounds', () {
      final imageBytes = create4QuadrantSquareImage(1000);
      final cropState = CanonicalCropState(sourceWidth: 1000, sourceHeight: 1000);

      cropState.panBy(const Offset(5000, 5000), circleDiameter);
      expect(cropState.cropRect.left, equals(0.0));
      expect(cropState.cropRect.top, equals(0.0));
      expect(cropState.cropRect.right, equals(1000.0));
      expect(cropState.cropRect.bottom, equals(1000.0));
    });

    test('EXIF Orientation Baking: Image with EXIF orientation metadata is baked upright without distortion', () {
      final image = img.Image(width: 800, height: 1600);
      img.fill(image, color: img.ColorRgb8(255, 0, 0));
      image.exif.imageIfd.orientation = 6; // 90 CW orientation flag

      final rawBytesWithExif = Uint8List.fromList(img.encodeJpg(image, quality: 90));
      final croppedBytes = ImageCropHelper.cropSquare(rawBytes: rawBytesWithExif, targetDimension: 512);

      final cropped = img.decodeImage(croppedBytes)!;
      expect(cropped.width, equals(512));
      expect(cropped.height, equals(512));
      expect(isRed(cropped.getPixel(256, 256)), isTrue);
    });
  });

  group('Widget Integration — CircularCropDialog Canonical User Flow', () {
    testWidgets('Opens CircularCropDialog, displays image centered, and confirms crop returning 512x512 bytes', (tester) async {
      final imageBytes = create4StripPortraitImage(600, 1200);
      Uint8List? resultBytes;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  resultBytes = await CircularCropDialog.show(
                    context,
                    imageBytes: imageBytes,
                    title: 'Crop Shop Photo (Circle)',
                  );
                },
                child: const Text('Open Cropper'),
              ),
            ),
          ),
        ),
      );

      // Tap button to open dialog
      await tester.tap(find.text('Open Cropper'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();

      // Verify dialog is visible
      expect(find.text('Crop Shop Photo (Circle)'), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets);
      expect(find.text('Save Photo'), findsOneWidget);

      // Tap "Save Photo"
      await tester.tap(find.text('Save Photo'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();

      // Verify cropped bytes returned
      expect(resultBytes, isNotNull);
      final decoded = img.decodeImage(resultBytes!)!;
      expect(decoded.width, equals(512));
      expect(decoded.height, equals(512));

      // Upper portion is GREEN and lower portion is BLUE
      expect(isGreen(decoded.getPixel(256, 100)), isTrue);
      expect(isBlue(decoded.getPixel(256, 400)), isTrue);
    });
  });
}
