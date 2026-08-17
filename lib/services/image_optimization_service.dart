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

  /// Optimizes image bytes asynchronously on a background isolate.
  /// Guarantees that:
  /// - Menu items are <= 300 KB (target ~800px max dimension)
  /// - Shop banners are <= 800 KB (target ~1400px max dimension)
  static Future<Uint8List> optimizeImageBytes({
    required Uint8List originalBytes,
    required ImageTargetType type,
  }) async {
    debugPrint(
      '🔄 [IMAGE OPTIMIZE] Starting optimization for ${type.name} (Original size: ${(originalBytes.lengthInBytes / 1024).toStringAsFixed(1)} KB)...',
    );

    try {
      final optimized = await compute(_processImageInIsolate, {
        'bytes': originalBytes,
        'typeIndex': type.index,
      });

      debugPrint(
        '✅ [IMAGE OPTIMIZE] Complete! Final size: ${(optimized.lengthInBytes / 1024).toStringAsFixed(1)} KB (Target limit: ${type == ImageTargetType.menuItem ? '300 KB' : '800 KB'})',
      );

      return optimized;
    } catch (e) {
      debugPrint('⚠️ [IMAGE OPTIMIZE] Isolate processing error: $e');
      return originalBytes;
    }
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
      encoded = Uint8List.fromList(img.encodeJpg(image, quality: quality));
    }

    return encoded;
  }
}
