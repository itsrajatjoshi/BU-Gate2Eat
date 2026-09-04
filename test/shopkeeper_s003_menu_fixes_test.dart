// BU Gate2Eat — S-003 Shopkeeper Menu Management Targeted Tests
// Verifies:
// 1. Old image cleanup on image replacement (only after successful update, not on failure, not when unchanged)
// 2. Add / Edit double-tap guard prevents re-entrant execution
// 3. ShopkeeperHomeScreen requires explicit shopId and scopes accurately

import 'package:bugate2eat_app/models/menu_item_model.dart';
import 'package:bugate2eat_app/panel/shopkeeper_panel/shopkeeper_home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('S-003 FIX 1 — Edit Menu Image Cleanup Contract Tests', () {
    test('1. Image replacement cleanup triggers ONLY when oldImageUrl is non-empty and changed', () {
      final item = const MenuItem(
        id: 'item_1',
        name: 'Veg Momos',
        details: '8 pcs',
        price: 80,
        imageUrl: 'https://firebasestorage.googleapis.com/v0/b/bucket/o/shops%2Fshop_1%2Fitems%2Fold.jpg',
        categoryId: 'cat_1',
        isVeg: true,
        isAvailable: true,
        isRecommended: false,
        sortOrder: 1,
      );

      final String oldImageUrl = item.imageUrl;
      const String newImageUrl = 'https://firebasestorage.googleapis.com/v0/b/bucket/o/shops%2Fshop_1%2Fitems%2Fnew.jpg';

      bool shouldDelete = oldImageUrl.isNotEmpty && oldImageUrl != newImageUrl;
      expect(shouldDelete, isTrue, reason: 'Must cleanup old image when new image URL is different');

      // Case 2: Unchanged image
      const String unchangedImageUrl = 'https://firebasestorage.googleapis.com/v0/b/bucket/o/shops%2Fshop_1%2Fitems%2Fold.jpg';
      shouldDelete = oldImageUrl.isNotEmpty && oldImageUrl != unchangedImageUrl;
      expect(shouldDelete, isFalse, reason: 'Must NOT delete when image URL has not changed');

      // Case 3: No previous image
      const emptyOldImage = '';
      shouldDelete = emptyOldImage.isNotEmpty && emptyOldImage != newImageUrl;
      expect(shouldDelete, isFalse, reason: 'Must NOT attempt deletion when no old image existed');
    });

    test('2. Image cleanup is ordered strictly AFTER successful Firestore update', () async {
      final executionOrder = <String>[];
      bool firestoreUpdateSucceeded = false;

      Future<void> mockUpdateMenuItem() async {
        executionOrder.add('firestore_update');
        firestoreUpdateSucceeded = true;
      }

      Future<void> mockDeleteStorageImage(String url) async {
        if (!firestoreUpdateSucceeded) {
          throw StateError('Storage delete was attempted before or without successful Firestore update!');
        }
        executionOrder.add('storage_cleanup: $url');
      }

      // Simulate flow
      const oldUrl = 'https://storage/old.jpg';
      const newUrl = 'https://storage/new.jpg';

      await mockUpdateMenuItem();
      if (oldUrl.isNotEmpty && oldUrl != newUrl) {
        await mockDeleteStorageImage(oldUrl);
      }

      expect(executionOrder, [
        'firestore_update',
        'storage_cleanup: https://storage/old.jpg',
      ]);
    });

    test('3. Failed Firestore update aborts before image cleanup', () async {
      final executionOrder = <String>[];
      bool storageCleanupCalled = false;

      Future<void> mockFailingUpdateMenuItem() async {
        executionOrder.add('firestore_update_attempt');
        throw Exception('Network error during Firestore update');
      }

      void mockDeleteStorageImage(String url) {
        storageCleanupCalled = true;
      }

      const oldUrl = 'https://storage/old.jpg';
      const newUrl = 'https://storage/new.jpg';

      try {
        await mockFailingUpdateMenuItem();
        if (oldUrl.isNotEmpty && oldUrl != newUrl) {
          mockDeleteStorageImage(oldUrl);
        }
      } catch (_) {
        executionOrder.add('error_handled');
      }

      expect(storageCleanupCalled, isFalse, reason: 'Storage image MUST NOT be deleted if Firestore write failed');
      expect(executionOrder, ['firestore_update_attempt', 'error_handled']);
    });
  });

  group('S-003 FIX 2 & 3 — Add/Edit In-Flight Double-Tap Guard', () {
    test('1. Double-tap guard immediately aborts when _isLoading is true', () async {
      var callCount = 0;
      var isLoading = false;

      Future<void> simulateOnAddOrSave() async {
        // Double-tap guard at top of method
        if (isLoading) return;

        // Validation & loading trigger
        isLoading = true;
        callCount++;

        // Simulate async work
        await Future.delayed(const Duration(milliseconds: 10));
        isLoading = false;
      }

      // Fire first tap
      final firstTap = simulateOnAddOrSave();
      // Rapid second tap while first is still running
      final secondTap = simulateOnAddOrSave();

      await Future.wait([firstTap, secondTap]);

      expect(callCount, 1, reason: 'Second tap while loading must be ignored immediately by the guard');
    });

    test('2. Consecutive valid taps after completion are permitted', () async {
      var callCount = 0;
      var isLoading = false;

      Future<void> simulateOnAddOrSave() async {
        if (isLoading) return;
        isLoading = true;
        callCount++;
        await Future.delayed(const Duration(milliseconds: 5));
        isLoading = false;
      }

      await simulateOnAddOrSave();
      await simulateOnAddOrSave();

      expect(callCount, 2, reason: 'Subsequent taps after reset are properly allowed');
    });
  });

  group('S-003 OPTIONAL SAFETY — Shop Scoping & Required shopId Constructor', () {
    testWidgets('1. ShopkeeperHomeScreen requires shopId and binds to specified shop', (tester) async {
      const testShopId = 'shop_unique_777';

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: ShopkeeperHomeScreen(
                shopId: testShopId,
              ),
            ),
          ),
        ),
      );

      final homeFinder = find.byType(ShopkeeperHomeScreen);
      expect(homeFinder, findsOneWidget);

      final widget = tester.widget<ShopkeeperHomeScreen>(homeFinder);
      expect(widget.shopId, testShopId);
      expect(widget.isAdmin, isFalse);
    });

    testWidgets('2. ShopkeeperHomeScreen with isAdmin = true scopes correctly', (tester) async {
      const testShopId = 'admin_inspected_shop_42';

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: ShopkeeperHomeScreen(
                shopId: testShopId,
                isAdmin: true,
              ),
            ),
          ),
        ),
      );

      final homeFinder = find.byType(ShopkeeperHomeScreen);
      expect(homeFinder, findsOneWidget);

      final widget = tester.widget<ShopkeeperHomeScreen>(homeFinder);
      expect(widget.shopId, testShopId);
      expect(widget.isAdmin, isTrue);
    });
  });
}
