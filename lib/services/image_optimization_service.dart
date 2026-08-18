// BU Gate2Eat — Services
// Client-side image optimization (resizing & progressive compression in background isolate)

import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Target image classification with strict byte and dimension caps.
enum ImageTargetType {
  /// Menu item photos: Max 300 KB, target dimension ~800px.
  menuItem,

  /// Shop banner photos: Max 800 KB, target dimension ~1400px.
  shopBanner,
}

/// Service providing client-side automatic image resizing and compression.
class ImageOptimizationService {
  /// Maximum byte limit for menu items (300 KB).
  static const int maxMenuItemBytes = 300 * 1024;

  /// Maximum byte limit for shop banners (800 KB).
  static const int maxBannerBytes = 800 * 1024;

  /// Optimizes image bytes asynchronously on a background isolate ONLY if exceeding limits.
  ///
  /// Rule:
  /// - If `originalBytes.length <= limit` (<= 300 KB for items, <= 800 KB for banners):
  ///   Does NOT compress, resize, re-encode, or alter the file. Returns exact original bytes.
  /// - If `originalBytes.length > limit`:
  ///   Compresses & resizes in background isolate until within target limits.
  static Future<Uint8List> optimizeImageBytes({
    required Uint8List originalBytes,
    required ImageTargetType type,
  }) async {
    final int maxAllowedBytes = type == ImageTargetType.menuItem
        ? maxMenuItemBytes
        : maxBannerBytes;

    final originalSizeKb =
        (originalBytes.lengthInBytes / 1024).toStringAsFixed(1);
    final limitKb = (maxAllowedBytes / 1024).toInt();

    // 1. If file is already within the allowed limit, skip compression entirely
    if (originalBytes.lengthInBytes <= maxAllowedBytes) {
      debugPrint(
        '⚡ [IMAGE OPTIMIZE] Image is already within limit ($originalSizeKb KB <= $limitKb KB). Skipping compression, preserving original format & bytes as-is.',
      );
      return originalBytes;
    }

    // 2. If file exceeds limit, optimize in background isolate
    debugPrint(
      '🔄 [IMAGE OPTIMIZE] Image exceeds limit ($originalSizeKb KB > $limitKb KB). Starting auto-optimization for ${type.name}...',
    );

    try {
      final optimized = await compute(_processImageInIsolate, {
        'bytes': originalBytes,
        'typeIndex': type.index,
      });

      debugPrint(
        '✅ [IMAGE OPTIMIZE] Complete! Final size: ${(optimized.lengthInBytes / 1024).toStringAsFixed(1)} KB (Target limit: ${limitKb} KB)',
      );

      return optimized;
    } catch (e) {
      debugPrint('⚠️ [IMAGE OPTIMIZE] Isolate processing error: $e');
      return originalBytes;
    }
  }

  /// Detects MIME content-type from magic header bytes (PNG, WebP, JPEG).
  static String detectContentType(Uint8List bytes) {
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return 'image/png';
    }
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return 'image/webp';
    }
    return 'image/jpeg';
  }

  /// Background isolate processing function.
  static Uint8List _processImageInIsolate(Map<String, dynamic> params) {
    final Uint8List rawBytes = params['bytes'] as Uint8List;
    final int typeIndex = params['typeIndex'] as int;
    final type = ImageTargetType.values[typeIndex];

    final int maxAllowedBytes = type == ImageTargetType.menuItem
        ? maxMenuItemBytes
        : maxBannerBytes;

    final int initialMaxDimension =
        type == ImageTargetType.menuItem ? 800 : 1400;

    // Decode original image
    final decoded = img.decodeImage(rawBytes);
    if (decoded == null) {
      return rawBytes;
    }

    img.Image image = decoded;

    // 1. Initial dimension resize if larger than maximum target
    if (image.width > initialMaxDimension ||
        image.height > initialMaxDimension) {
      if (image.width >= image.height) {
        image = img.copyResize(image, width: initialMaxDimension);
      } else {
        image = img.copyResize(image, height: initialMaxDimension);
      }
    }

    // 2. Progressive quality stepping loop (85% -> 75% -> 65% -> 50% -> 40%)
    int quality = 85;
    Uint8List encoded =
        Uint8List.fromList(img.encodeJpg(image, quality: quality));

    while (encoded.lengthInBytes > maxAllowedBytes && quality > 40) {
      quality -= 10;
      encoded = Uint8List.fromList(img.encodeJpg(image, quality: quality));
    }

    // 3. Dimensional scaling loop if quality reduction alone is insufficient
    int currentDimension = initialMaxDimension;
    while (encoded.lengthInBytes > maxAllowedBytes && currentDimension > 350) {
      currentDimension = (currentDimension * 0.8).toInt();
      if (image.width >= image.height) {
        image = img.copyResize(image, width: currentDimension);
      } else {
        image = img.copyResize(image, height: currentDimension);
      }
      encoded = Uint8List.fromList(img.encodeJpg(image, quality: 70));
    }

    return encoded;
  }
}
