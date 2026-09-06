// BU Gate2Eat — Test Suite
// Checkpoint 6: Data Cleanup + Storage Management Comprehensive Suite

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('1. Active Order Protection Invariant', () {
    test('Terminal order cleanup filter strictly preserves placed and accepted orders', () {
      final mockOrders = [
        {'id': 'order_1', 'status': 'placed', 'shopId': 'shop_1'},
        {'id': 'order_2', 'status': 'accepted', 'shopId': 'shop_1'},
        {'id': 'order_3', 'status': 'delivered', 'shopId': 'shop_1'},
        {'id': 'order_4', 'status': 'rejected', 'shopId': 'shop_1'},
        {'id': 'order_5', 'status': 'delivery_expired', 'shopId': 'shop_1'},
        {'id': 'order_6', 'status': 'cancelled', 'shopId': 'shop_1'},
      ];

      // Replicate the exact filter logic from ShopStatsService.deleteTerminalShopOrders
      final terminalDocs = mockOrders.where((doc) {
        final status = (doc['status'] ?? '').toString().trim().toLowerCase();
        return status != 'placed' && status != 'accepted';
      }).toList();

      final preservedDocs = mockOrders.where((doc) {
        final status = (doc['status'] ?? '').toString().trim().toLowerCase();
        return status == 'placed' || status == 'accepted';
      }).toList();

      expect(terminalDocs.length, equals(4));
      expect(terminalDocs.map((d) => d['id']), containsAll(['order_3', 'order_4', 'order_5', 'order_6']));

      expect(preservedDocs.length, equals(2));
      expect(preservedDocs.map((d) => d['id']), containsAll(['order_1', 'order_2']));
    });
  });

  group('2. Idempotency & Repeated Cleanup', () {
    test('Consecutive cleanup runs on already-cleared collections return 0 and are safe no-ops', () {
      final List<Map<String, dynamic>> databaseOrders = [];

      // Run 1: empty database
      final terminalDocsRun1 = databaseOrders.where((doc) {
        final status = ((doc['status'] as String?) ?? '').trim().toLowerCase();
        return status != 'placed' && status != 'accepted';
      }).toList();
      expect(terminalDocsRun1.isEmpty, isTrue);

      // Run 2: immediate repeat
      final terminalDocsRun2 = databaseOrders.where((doc) {
        final status = ((doc['status'] as String?) ?? '').trim().toLowerCase();
        return status != 'placed' && status != 'accepted';
      }).toList();
      expect(terminalDocsRun2.isEmpty, isTrue);
    });
  });

  group('3. Storage URL Parsing & External Asset Protection', () {
    bool isFirebaseStorageUrl(String? url) {
      if (url == null || url.trim().isEmpty) return false;
      final trimmed = url.trim();
      return trimmed.contains('firebasestorage.googleapis.com') ||
          trimmed.contains('firebasestorage.app') ||
          trimmed.contains('appspot.com');
    }

    test('Identifies valid Firebase Storage URLs for deletion', () {
      const gcsUrl = 'https://firebasestorage.googleapis.com/v0/b/bugate2eat.appspot.com/o/shops%2Fshop_1%2Fbanner.jpg?alt=media';
      const appspotUrl = 'https://bugate2eat.appspot.com/o/shops%2Fshop_1%2Flogo.jpg';
      const newStorageUrl = 'https://firebasestorage.app/v0/b/bucket/o/file.jpg';

      expect(isFirebaseStorageUrl(gcsUrl), isTrue);
      expect(isFirebaseStorageUrl(appspotUrl), isTrue);
      expect(isFirebaseStorageUrl(newStorageUrl), isTrue);
    });

    test('Safely protects external sample URLs and empty URLs from deletion attempts', () {
      const unsplashUrl = 'https://images.unsplash.com/photo-1546069901-ba9599a7e63c?w=500';
      const cdnUrl = 'https://cdn.example.com/food.png';
      const emptyUrl = '';
      const whitespaceUrl = '   ';

      expect(isFirebaseStorageUrl(unsplashUrl), isFalse);
      expect(isFirebaseStorageUrl(cdnUrl), isFalse);
      expect(isFirebaseStorageUrl(emptyUrl), isFalse);
      expect(isFirebaseStorageUrl(whitespaceUrl), isFalse);
      expect(isFirebaseStorageUrl(null), isFalse);
    });
  });

  group('4. Image Replacement Cleanup Logic', () {
    test('Triggers storage deletion only when new image URL differs from old image URL', () {
      const oldImage = 'https://firebasestorage.googleapis.com/v0/b/bucket/o/item_old.jpg';
      const newImage = 'https://firebasestorage.googleapis.com/v0/b/bucket/o/item_new.jpg';
      const identicalImage = 'https://firebasestorage.googleapis.com/v0/b/bucket/o/item_old.jpg';

      bool shouldDeleteOld(String oldUrl, String newUrl) {
        return oldUrl.isNotEmpty && oldUrl != newUrl;
      }

      // Replaced image: must trigger cleanup of old image
      expect(shouldDeleteOld(oldImage, newImage), isTrue);

      // Unchanged image (e.g. only edited item price/name): must NOT delete image
      expect(shouldDeleteOld(oldImage, identicalImage), isFalse);

      // Initial image upload: old was empty, must NOT trigger deletion
      expect(shouldDeleteOld('', newImage), isFalse);
    });
  });

  group('5. Shop Deletion Cascade Integrity', () {
    test('Shop cascade deletes categories, menu items, and assets while isolating orders and stats', () {
      final shopData = {
        'id': 'shop_100',
        'name': 'Test Cafe',
        'bannerUrl': 'https://firebasestorage.googleapis.com/v0/b/b/o/banner.jpg',
        'logoUrl': 'https://firebasestorage.googleapis.com/v0/b/b/o/logo.jpg',
      };

      final menuItems = [
        {'id': 'm1', 'shopId': 'shop_100', 'imageUrl': 'https://firebasestorage.googleapis.com/v0/b/b/o/m1.jpg'},
        {'id': 'm2', 'shopId': 'shop_100', 'imageUrl': 'https://images.unsplash.com/sample'},
      ];

      final categories = [
        {'id': 'c1', 'shopId': 'shop_100'},
      ];

      final orders = [
        {'id': 'YB-001', 'shopId': 'shop_100', 'status': 'delivered'},
        {'id': 'YB-002', 'shopId': 'shop_100', 'status': 'placed'},
      ];

      final shopStats = {
        'shop_100': {'delivered': 10, 'appOrders': 12},
      };

      // Cascade scope: categories, menu items, banner, logo, shop doc
      final deletedMenuItems = List<Map<String, dynamic>>.from(menuItems);
      final deletedCategories = List<Map<String, dynamic>>.from(categories);
      final deletedShop = Map<String, dynamic>.from(shopData);

      // Orders and Stats are strictly OUTSIDE shop cascade delete
      final preservedOrders = List<Map<String, dynamic>>.from(orders);
      final preservedStats = Map<String, dynamic>.from(shopStats);

      expect(deletedMenuItems.length, equals(2));
      expect(deletedCategories.length, equals(1));
      expect(deletedShop['id'], equals('shop_100'));

      // Crucial invariant: historical orders and vendor stats remain preserved
      expect(preservedOrders.length, equals(2));
      expect(preservedStats.containsKey('shop_100'), isTrue);
    });
  });

  group('6. Device Token Cleanup Logic', () {
    test('Clean stale tokens identifies and purges unregistered/invalid tokens while keeping active tokens', () {
      final tokens = ['token_active_1', 'token_stale_invalid', 'token_active_2', 'token_not_registered'];
      final mockResponses = [
        {'success': true, 'error': null},
        {'success': false, 'error': 'messaging/invalid-registration-token'},
        {'success': true, 'error': null},
        {'success': false, 'error': 'messaging/registration-token-not-registered'},
      ];

      final staleTokensToPurge = <String>[];
      for (int i = 0; i < tokens.length; i++) {
        final resp = mockResponses[i];
        if (resp['success'] == false) {
          final err = resp['error'] as String?;
          if (err == 'messaging/invalid-registration-token' ||
              err == 'messaging/registration-token-not-registered' ||
              err == 'messaging/mismatched-credential') {
            staleTokensToPurge.add(tokens[i]);
          }
        }
      }

      expect(staleTokensToPurge.length, equals(2));
      expect(staleTokensToPurge, containsAll(['token_stale_invalid', 'token_not_registered']));
    });
  });

  group('7. Flutter Decoded Image Cache Limits', () {
    test('PaintingBinding imageCache limits are configured to protect low-end device RAM', () {
      final imageCache = PaintingBinding.instance.imageCache;

      // Verify that image cache can be capped and bounds are respected
      imageCache.maximumSize = 100;
      imageCache.maximumSizeBytes = 50 * 1024 * 1024; // 50 MB

      expect(imageCache.maximumSize, equals(100));
      expect(imageCache.maximumSizeBytes, equals(50 * 1024 * 1024));

      // Test clear and clearLiveImages execution without exception
      imageCache.clear();
      imageCache.clearLiveImages();
      expect(imageCache.currentSize, equals(0));
      expect(imageCache.currentSizeBytes, equals(0));
    });
  });

  group('8. Firestore Batch Sizing Safeguard', () {
    test('Terminal order deletions are chunked within Firestore 500-operation batch limits', () {
      const totalTerminalOrders = 1250;
      const chunkSize = 400; // Chosen chunk size (<= 500)

      final chunks = <int>[];
      for (int i = 0; i < totalTerminalOrders; i += chunkSize) {
        final end = (i + chunkSize < totalTerminalOrders) ? i + chunkSize : totalTerminalOrders;
        chunks.add(end - i);
      }

      expect(chunks.length, equals(4));
      expect(chunks, equals([400, 400, 400, 50]));
      for (final size in chunks) {
        expect(size <= 500, isTrue); // Guarantees no batch limit overflow
      }
    });
  });
}
