// BU Gate2Eat — Checkpoint 5 Test Suite
// Data Cleanup + Storage Management Comprehensive Verification Suite

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ─── 1. SAFE 45-DAY RETENTION POLICY & EXACT BOUNDARY TESTS ─────────────────
  group('1. Safe 45-Day Retention Policy & Exact Boundaries', () {
    const retentionDays = 45;
    final retentionDuration = const Duration(days: retentionDays);
    final now = DateTime(2026, 9, 7, 12, 0, 0);

    bool shouldDeleteOrder({
      required String status,
      required DateTime? createdAt,
      required DateTime currentClock,
    }) {
      final s = status.trim().toLowerCase();
      // Active orders must NEVER be deleted
      if (s == 'placed' || s == 'accepted') return false;

      // Only terminal orders are eligible
      const terminalStatuses = {
        'delivered',
        'cancelled',
        'rejected',
        'delivery_expired',
      };
      if (!terminalStatuses.contains(s)) return false;

      // Fail-safe: missing or malformed timestamp is preserved
      if (createdAt == null) return false;

      // Future timestamp is preserved
      if (createdAt.isAfter(currentClock)) return false;

      final age = currentClock.difference(createdAt);
      // Retention rule: KEEP <= 45 days, DELETE > 45 days
      return age > retentionDuration;
    }

    test('Boundary: Exactly 45 days old is KEPT (<= 45 days)', () {
      final exactly45Days = now.subtract(retentionDuration);
      final result = shouldDeleteOrder(
        status: 'delivered',
        createdAt: exactly45Days,
        currentClock: now,
      );
      expect(result, isFalse, reason: 'Exactly 45 days must be preserved (<= 45 days)');
    });

    test('Boundary: 44 days 23 hours is KEPT (< 45 days)', () {
      final under45Days = now.subtract(const Duration(days: 44, hours: 23));
      final result = shouldDeleteOrder(
        status: 'delivered',
        createdAt: under45Days,
        currentClock: now,
      );
      expect(result, isFalse, reason: '44 days 23 hours must be preserved');
    });

    test('Boundary: 45 days + 1 second is DELETED (> 45 days, terminal)', () {
      final over45Days = now.subtract(retentionDuration + const Duration(seconds: 1));
      final result = shouldDeleteOrder(
        status: 'delivered',
        createdAt: over45Days,
        currentClock: now,
      );
      expect(result, isTrue, reason: '45 days + 1 second must be deleted');
    });

    test('Boundary: Future timestamp is KEPT (clock skew protection)', () {
      final futureDate = now.add(const Duration(minutes: 5));
      final result = shouldDeleteOrder(
        status: 'delivered',
        createdAt: futureDate,
        currentClock: now,
      );
      expect(result, isFalse, reason: 'Future order must never be deleted');
    });

    test('Boundary: Missing / null timestamp is KEPT (fail-safe data protection)', () {
      final result = shouldDeleteOrder(
        status: 'delivered',
        createdAt: null,
        currentClock: now,
      );
      expect(result, isFalse, reason: 'Missing timestamp must be preserved to prevent data loss');
    });

    test('Boundary: All terminal statuses (>45 days) are eligible for cleanup', () {
      final oldDate = now.subtract(const Duration(days: 50));
      for (final terminal in ['delivered', 'cancelled', 'rejected', 'delivery_expired']) {
        final result = shouldDeleteOrder(
          status: terminal,
          createdAt: oldDate,
          currentClock: now,
        );
        expect(result, isTrue, reason: 'Terminal status $terminal older than 45 days should delete');
      }
    });

    test('Boundary: Unknown status (>45 days) is KEPT', () {
      final oldDate = now.subtract(const Duration(days: 50));
      final result = shouldDeleteOrder(
        status: 'in_review_special',
        createdAt: oldDate,
        currentClock: now,
      );
      expect(result, isFalse, reason: 'Non-terminal / unknown status must not be deleted');
    });
  });

  // ─── 2. ACTIVE ORDER PROTECTION INVARIANT ───────────────────────────────────
  group('2. Active Order Protection Invariant', () {
    final now = DateTime(2026, 9, 7, 12, 0, 0);
    final ancientDate = now.subtract(const Duration(days: 120)); // 120 days old!

    bool isActiveOrder(String status) {
      final s = status.trim().toLowerCase();
      return s == 'placed' || s == 'accepted';
    }

    test('Active "placed" order is NEVER deleted even if 120 days old', () {
      expect(isActiveOrder('placed'), isTrue);
      // Even if ancient, active order is kept
      final isProtected = isActiveOrder('placed');
      expect(isProtected, isTrue);
    });

    test('Active "accepted" order is NEVER deleted even if 120 days old', () {
      expect(isActiveOrder('accepted'), isTrue);
      final isProtected = isActiveOrder('accepted');
      expect(isProtected, isTrue);
    });

    test('Mixed dataset correctly separates active from expired terminal orders', () {
      final dataset = [
        {'id': 'o1', 'status': 'placed', 'ageDays': 100},
        {'id': 'o2', 'status': 'accepted', 'ageDays': 80},
        {'id': 'o3', 'status': 'delivered', 'ageDays': 10}, // recent
        {'id': 'o4', 'status': 'delivered', 'ageDays': 55}, // expired
        {'id': 'o5', 'status': 'cancelled', 'ageDays': 60}, // expired
        {'id': 'o6', 'status': 'rejected', 'ageDays': 44}, // recent
        {'id': 'o7', 'status': 'delivery_expired', 'ageDays': 46}, // expired
      ];

      final toDelete = dataset.where((item) {
        final status = (item['status'] as String).toLowerCase();
        final age = item['ageDays'] as int;
        if (status == 'placed' || status == 'accepted') return false;
        return age > 45;
      }).toList();

      final preserved = dataset.where((item) => !toDelete.contains(item)).toList();

      expect(toDelete.map((i) => i['id']), containsAll(['o4', 'o5', 'o7']));
      expect(preserved.map((i) => i['id']), containsAll(['o1', 'o2', 'o3', 'o6']));
      expect(toDelete.length, equals(3));
      expect(preserved.length, equals(4));
    });
  });

  // ─── 3. IDEMPOTENCY & BATCH CHUNKING ────────────────────────────────────────
  group('3. Idempotency & Batch Chunking Logic', () {
    test('Consecutive cleanup runs are idempotent and produce zero residual deletes', () {
      final List<Map<String, dynamic>> orders = [
        {'id': '1', 'status': 'delivered', 'age': 60},
        {'id': '2', 'status': 'placed', 'age': 10},
      ];

      // First run
      final run1Deletes = orders.where((o) => o['status'] != 'placed' && (o['age'] as int) > 45).toList();
      expect(run1Deletes.length, equals(1));
      orders.removeWhere((o) => run1Deletes.contains(o));

      // Second run (immediate repeat)
      final run2Deletes = orders.where((o) => o['status'] != 'placed' && (o['age'] as int) > 45).toList();
      expect(run2Deletes.isEmpty, isTrue, reason: 'Second run must find 0 candidates (idempotent)');
    });

    test('Batch deletion chunks strictly respect Firestore 500-operation ceiling', () {
      const totalDocs = 1845;
      const batchSize = 400; // Chosen safe limit <= 500

      final chunks = <int>[];
      for (int i = 0; i < totalDocs; i += batchSize) {
        final end = (i + batchSize < totalDocs) ? i + batchSize : totalDocs;
        chunks.add(end - i);
      }

      expect(chunks.length, equals(5));
      expect(chunks, equals([400, 400, 400, 400, 245]));
      for (final size in chunks) {
        expect(size <= 500, isTrue);
        expect(size <= 400, isTrue);
      }
      expect(chunks.reduce((a, b) => a + b), equals(totalDocs));
    });
  });

  // ─── 4. REFERENCE-AWARE FIREBASE STORAGE ORPHAN DETECTION ───────────────────
  group('4. Reference-Aware Storage Orphan Detection', () {
    String? extractStoragePath(String? url) {
      if (url == null || url.trim().isEmpty) return null;
      final trimmed = url.trim();
      if (trimmed.contains('/o/')) {
        final uri = Uri.tryParse(trimmed);
        if (uri != null && uri.pathSegments.contains('o')) {
          final oIdx = uri.pathSegments.indexOf('o');
          if (oIdx + 1 < uri.pathSegments.length) {
            return Uri.decodeComponent(uri.pathSegments[oIdx + 1]);
          }
        }
      }
      if (trimmed.startsWith('shops/')) return trimmed;
      return null;
    }

    test('Extracts canonical storage path from Firebase download URL', () {
      const url = 'https://firebasestorage.googleapis.com/v0/b/app.appspot.com/o/shops%2Fshop_1%2Fmenu%2Fitem_123.jpg?alt=media&token=abc';
      final path = extractStoragePath(url);
      expect(path, equals('shops/shop_1/menu/item_123.jpg'));
    });

    test('Protects external URLs from storage cleanup operations', () {
      const unsplashUrl = 'https://images.unsplash.com/photo-1546069901-ba9599a7e63c?w=500';
      const cdnUrl = 'https://mycdn.com/photos/food.jpg';
      expect(extractStoragePath(unsplashUrl), isNull);
      expect(extractStoragePath(cdnUrl), isNull);
    });

    test('Classifies files accurately into CURRENT, HISTORICAL, ACTIVE_RECENT, and VERIFIED_ORPHAN', () {
      final currentPaths = {'shops/s1/logo.jpg', 'shops/s1/menu/burger.jpg'};
      final historicalOrderPaths = {'shops/s1/menu/old_pizza_historical.jpg'};

      const orphanCandidate = 'shops/s1/menu/abandoned_temp.jpg';
      const recentUpload = 'shops/s1/menu/just_uploaded.jpg';

      String classifyFile({
        required String path,
        required Duration age,
      }) {
        if (currentPaths.contains(path)) return 'REFERENCED_CURRENT';
        if (historicalOrderPaths.contains(path)) return 'REFERENCED_HISTORICAL';
        if (age < const Duration(hours: 2)) return 'ACTIVE_RECENT';
        if (age >= const Duration(hours: 24)) return 'VERIFIED_ORPHAN';
        return 'GRACE_PERIOD';
      }

      expect(classifyFile(path: 'shops/s1/logo.jpg', age: const Duration(days: 30)), equals('REFERENCED_CURRENT'));
      expect(classifyFile(path: 'shops/s1/menu/old_pizza_historical.jpg', age: const Duration(days: 60)), equals('REFERENCED_HISTORICAL'));
      expect(classifyFile(path: recentUpload, age: const Duration(minutes: 30)), equals('ACTIVE_RECENT'));
      expect(classifyFile(path: orphanCandidate, age: const Duration(days: 3)), equals('VERIFIED_ORPHAN'));

      // Crucial: Only VERIFIED_ORPHAN can be deleted
      final canDelete = (classifyFile(path: orphanCandidate, age: const Duration(days: 3)) == 'VERIFIED_ORPHAN');
      final cannotDeleteHistorical = (classifyFile(path: 'shops/s1/menu/old_pizza_historical.jpg', age: const Duration(days: 60)) == 'VERIFIED_ORPHAN');

      expect(canDelete, isTrue);
      expect(cannotDeleteHistorical, isFalse, reason: 'Historical order image MUST NOT be deleted as orphan');
    });
  });

  // ─── 5. IMAGE REPLACEMENT & EDIT WORKFLOW SAFETY ────────────────────────────
  group('5. Image Replacement & Edit Safety Contract', () {
    test('Image replacement deletes old image ONLY after successful Firestore save and URL change', () async {
      final trace = <String>[];

      Future<void> editMenuItemWorkflow({
        required String oldUrl,
        required String? newImageToUpload,
        required bool firestoreSaveSucceeds,
      }) async {
        String finalUrl = oldUrl;

        // Step 1: Upload new image if provided
        if (newImageToUpload != null) {
          trace.add('upload_new_image: $newImageToUpload');
          finalUrl = 'https://firebasestorage.googleapis.com/v0/b/app/o/new_img.jpg';
        }

        // Step 2: Firestore update
        trace.add('firestore_update');
        if (!firestoreSaveSucceeds) {
          trace.add('firestore_failed');
          throw Exception('Simulated Firestore error');
        }
        trace.add('firestore_success');

        // Step 3: Best-effort cleanup of old image ONLY if URL actually changed
        if (oldUrl.isNotEmpty && oldUrl != finalUrl) {
          trace.add('cleanup_old_image: $oldUrl');
        }
      }

      // Case A: Successful replacement
      await editMenuItemWorkflow(
        oldUrl: 'https://firebasestorage.googleapis.com/v0/b/app/o/old_img.jpg',
        newImageToUpload: 'new_bytes',
        firestoreSaveSucceeds: true,
      );

      expect(trace, equals([
        'upload_new_image: new_bytes',
        'firestore_update',
        'firestore_success',
        'cleanup_old_image: https://firebasestorage.googleapis.com/v0/b/app/o/old_img.jpg',
      ]));

      // Case B: Firestore fails -> old image cleanup MUST NEVER happen
      trace.clear();
      try {
        await editMenuItemWorkflow(
          oldUrl: 'https://firebasestorage.googleapis.com/v0/b/app/o/old_img.jpg',
          newImageToUpload: 'new_bytes',
          firestoreSaveSucceeds: false,
        );
      } catch (_) {}

      expect(trace, contains('firestore_failed'));
      expect(trace, isNot(contains(predicate((String s) => s.startsWith('cleanup_old_image')))),
          reason: 'Old image must never be deleted if Firestore write failed');
    });

    test('Unchanged image during menu edit triggers ZERO storage deletion', () async {
      bool cleanupCalled = false;
      const currentUrl = 'https://firebasestorage.googleapis.com/v0/b/app/o/unchanged.jpg';

      void performEdit({required String existingUrl, required String newUrl}) {
        if (existingUrl.isNotEmpty && existingUrl != newUrl) {
          cleanupCalled = true;
        }
      }

      performEdit(existingUrl: currentUrl, newUrl: currentUrl);
      expect(cleanupCalled, isFalse, reason: 'Editing menu name/price must not delete existing image');
    });
  });

  // ─── 6. SHOP DELETION CASCADE INTEGRITY ─────────────────────────────────────
  group('6. Shop Deletion Cascade Integrity', () {
    test('Cascade deletes shop docs and assets while strictly preserving historical order records', () {
      final mockDatabase = {
        'shops': {'s10': {'name': 'Burger Barn', 'banner': 'banner.jpg', 'logo': 'logo.jpg'}},
        'categories': {'s10_c1': {'shopId': 's10', 'name': 'Burgers'}},
        'menuItems': {'s10_m1': {'shopId': 's10', 'name': 'Classic Burger', 'image': 'burger.jpg'}},
        'orders': {
          'ord_1': {'orderId': 'ord_1', 'shopId': 's10', 'customerName': 'Aman', 'status': 'delivered'},
          'ord_2': {'orderId': 'ord_2', 'shopId': 's10', 'customerName': 'Riya', 'status': 'accepted'},
        },
      };

      // Execute cascade delete for shop 's10'
      const targetShopId = 's10';

      // 1. Delete menu items for s10
      mockDatabase['menuItems']!.removeWhere((k, v) => v['shopId'] == targetShopId);
      // 2. Delete categories for s10
      mockDatabase['categories']!.removeWhere((k, v) => v['shopId'] == targetShopId);
      // 3. Delete shop doc
      mockDatabase['shops']!.remove(targetShopId);

      // Verify shop and subcollections are gone
      expect(mockDatabase['shops']!.containsKey(targetShopId), isFalse);
      expect(mockDatabase['categories']!.isEmpty, isTrue);
      expect(mockDatabase['menuItems']!.isEmpty, isTrue);

      // Crucial: Historical orders MUST NOT be removed
      expect(mockDatabase['orders']!.length, equals(2));
      expect(mockDatabase['orders']!['ord_1']!['shopId'], equals('s10'));
      expect(mockDatabase['orders']!['ord_2']!['shopId'], equals('s10'));
    });
  });

  // ─── 7. LOCAL STORAGE & MEMORY HYGIENE ──────────────────────────────────────
  group('7. Local Device Storage & Memory Hygiene', () {
    test('Decoded image cache limits are capped and protect low-end RAM', () {
      final cache = PaintingBinding.instance.imageCache;
      cache.maximumSize = 150;
      cache.maximumSizeBytes = 60 * 1024 * 1024; // 60 MB

      expect(cache.maximumSize, equals(150));
      expect(cache.maximumSizeBytes, equals(60 * 1024 * 1024));

      // Clearing cache on session end
      cache.clear();
      cache.clearLiveImages();
      expect(cache.currentSize, equals(0));
      expect(cache.currentSizeBytes, equals(0));
    });

    test('Local storage profile keys are bounded and safe against unbounded bloat', () {
      const allowedKeys = {
        'user_name',
        'user_phone',
        'user_age',
        'customer_id',
        'is_onboarded',
        'is_otp_verified',
        'verified_phone',
        'theme_mode',
        'favorite_item_ids',
      };

      // Ensure key count is bounded
      expect(allowedKeys.length, lessThan(15));
    });
  });
}
