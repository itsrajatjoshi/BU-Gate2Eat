// BU Gate2Eat — Services
// Firestore service for reading and writing shop & menu data

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' hide Category;

import '../models/category_model.dart';
import '../models/menu_item_model.dart';
import '../models/shop_model.dart';

/// Service class for all Firestore operations.
/// Handles shops, categories, and menu items.
class FirestoreService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  // Fixed neutral category image for new custom categories
  static const String defaultNeutralCategoryImageUrl =
      'https://images.unsplash.com/photo-1546069901-ba9599a7e63c?w=300&auto=format&fit=crop&q=80';

  // ─── Shops ──────────────────────────────────────────────────

  /// Fetches all active shops, sorted by sortOrder in memory.
  Future<List<Shop>> getShops() async {
    try {
      final snapshot = await _firestore
          .collection('shops')
          .where('isActive', isEqualTo: true)
          .get();

      final shops =
          snapshot.docs.map((doc) => Shop.fromFirestore(doc)).toList();

      shops.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      return shops;
    } catch (e) {
      debugPrint('❌ Firestore getShops error: $e');
      return [];
    }
  }

  /// Fetches a single shop by ID.
  Future<Shop?> getShop(String shopId) async {
    try {
      final doc = await _firestore.collection('shops').doc(shopId).get();
      if (!doc.exists) return null;
      return Shop.fromFirestore(doc);
    } catch (e) {
      debugPrint('❌ Firestore getShop error: $e');
      return null;
    }
  }

  /// Stream of all active shops (real-time updates, in-memory sorting).
  Stream<List<Shop>> watchShops() {
    return _firestore
        .collection('shops')
        .where('isActive', isEqualTo: true)
        .snapshots()
        .map(
      (snapshot) {
        final shops =
            snapshot.docs.map((doc) => Shop.fromFirestore(doc)).toList();
        shops.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
        return shops;
      },
    );
  }

  /// Stream of a specific shop document (real-time updates).
  Stream<Shop?> watchShop(String shopId) {
    return _firestore.collection('shops').doc(shopId).snapshots().map((doc) {
      if (!doc.exists) return null;
      return Shop.fromFirestore(doc);
    });
  }

  /// Updates shop details (name, description, timings, bannerUrl, etc.).
  Future<void> updateShop(String shopId, Map<String, dynamic> data) async {
    final updateData = Map<String, dynamic>.from(data);
    updateData['updatedAt'] = FieldValue.serverTimestamp();
    debugPrint(
      '📝 FirestoreService.updateShop -> updating shops/$shopId with: $updateData',
    );
    try {
      await _firestore
          .collection('shops')
          .doc(shopId)
          .set(updateData, SetOptions(merge: true));
      debugPrint('✅ FirestoreService.updateShop -> SUCCESS for shops/$shopId');
    } catch (e, stack) {
      debugPrint('❌ FirestoreService.updateShop -> ERROR: $e\n$stack');
      rethrow;
    }
  }

  /// Updates manual open/closed override.
  Future<void> updateShopOpenOverride(
    String shopId,
    bool isClosedOverride,
  ) async {
    debugPrint(
      '📝 FirestoreService.updateShopOpenOverride -> shops/$shopId => isClosedOverride: $isClosedOverride',
    );
    try {
      await _firestore.collection('shops').doc(shopId).set(
        {
          'isClosedOverride': isClosedOverride,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      debugPrint('✅ FirestoreService.updateShopOpenOverride -> SUCCESS');
    } catch (e, stack) {
      debugPrint(
        '❌ FirestoreService.updateShopOpenOverride -> ERROR: $e\n$stack',
      );
      rethrow;
    }
  }

  // ─── Categories ─────────────────────────────────────────────

  /// Fetches all active categories for a given shop, sorted by sortOrder.
  Future<List<Category>> getCategories(String shopId) async {
    try {
      final snapshot = await _firestore
          .collection('shops')
          .doc(shopId)
          .collection('categories')
          .get();

      final categories = snapshot.docs
          .map((doc) => Category.fromFirestore(doc))
          .where((c) => c.isActive)
          .toList();

      categories.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      return categories;
    } catch (e) {
      debugPrint('❌ Firestore getCategories error: $e');
      return [];
    }
  }

  /// Stream of active categories for a shop.
  Stream<List<Category>> watchCategories(String shopId) {
    return _firestore
        .collection('shops')
        .doc(shopId)
        .collection('categories')
        .snapshots()
        .map((snapshot) {
      final categories = snapshot.docs
          .map((doc) => Category.fromFirestore(doc))
          .where((c) => c.isActive)
          .toList();
      categories.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      return categories;
    });
  }

  /// Creates a new custom category for a shop with a fixed neutral image.
  /// (Existing categories cannot be edited/deleted).
  Future<Category> createCustomCategory(
    String shopId,
    String categoryName,
  ) async {
    final trimmed = categoryName.trim();
    final catId = trimmed
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');

    final effectiveId = catId.isNotEmpty
        ? catId
        : 'cat_${DateTime.now().millisecondsSinceEpoch}';
    final docRef = _firestore
        .collection('shops')
        .doc(shopId)
        .collection('categories')
        .doc(effectiveId);

    final existingDoc = await docRef.get();
    if (existingDoc.exists) {
      return Category.fromFirestore(existingDoc);
    }

    final newCategory = Category(
      id: effectiveId,
      name: trimmed,
      sortOrder: 99,
      imageUrl: defaultNeutralCategoryImageUrl,
      shopId: shopId,
    );

    debugPrint(
      '📝 FirestoreService.createCustomCategory -> shops/$shopId/categories/$effectiveId',
    );
    await docRef.set(newCategory.toFirestore(), SetOptions(merge: true));
    debugPrint('✅ FirestoreService.createCustomCategory -> SUCCESS');
    return newCategory;
  }

  // ─── Menu Items ─────────────────────────────────────────────

  /// Fetches all menu items for a given shop, sorted by sortOrder.
  Future<List<MenuItem>> getMenuItems(String shopId) async {
    try {
      final snapshot = await _firestore
          .collection('shops')
          .doc(shopId)
          .collection('menuItems')
          .get();

      final items =
          snapshot.docs.map((doc) => MenuItem.fromFirestore(doc)).toList();
      items.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      return items;
    } catch (e) {
      debugPrint('❌ Firestore getMenuItems error: $e');
      return [];
    }
  }

  /// Stream of menu items for a shop.
  Stream<List<MenuItem>> watchMenuItems(String shopId) {
    return _firestore
        .collection('shops')
        .doc(shopId)
        .collection('menuItems')
        .snapshots()
        .map((snapshot) {
      final items =
          snapshot.docs.map((doc) => MenuItem.fromFirestore(doc)).toList();
      items.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      return items;
    });
  }

  /// Fetches menu items for a specific category within a shop.
  Future<List<MenuItem>> getMenuItemsByCategory(
    String shopId,
    String categoryId,
  ) async {
    try {
      final snapshot = await _firestore
          .collection('shops')
          .doc(shopId)
          .collection('menuItems')
          .where('categoryId', isEqualTo: categoryId)
          .get();

      final items =
          snapshot.docs.map((doc) => MenuItem.fromFirestore(doc)).toList();
      items.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      return items;
    } catch (e) {
      debugPrint('❌ Firestore getMenuItemsByCategory error: $e');
      return [];
    }
  }

  /// Fetches recommended menu items for a shop (for Cart "You may also like").
  Future<List<MenuItem>> getRecommendedMenuItems(String shopId) async {
    try {
      final snapshot = await _firestore
          .collection('shops')
          .doc(shopId)
          .collection('menuItems')
          .where('isRecommended', isEqualTo: true)
          .get();

      final items = snapshot.docs
          .map((doc) => MenuItem.fromFirestore(doc))
          .where((i) => i.isAvailable)
          .toList();
      items.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      return items;
    } catch (e) {
      debugPrint('❌ Firestore getRecommendedMenuItems error: $e');
      return [];
    }
  }

  /// Adds a new menu item to a shop.
  Future<void> addMenuItem(String shopId, MenuItem item) async {
    debugPrint(
      '📝 FirestoreService.addMenuItem -> shops/$shopId/menuItems/${item.id}',
    );
    try {
      await _firestore
          .collection('shops')
          .doc(shopId)
          .collection('menuItems')
          .doc(item.id)
          .set(item.toFirestore(), SetOptions(merge: true));
      debugPrint('✅ FirestoreService.addMenuItem -> SUCCESS for ${item.id}');
    } catch (e, stack) {
      debugPrint('❌ FirestoreService.addMenuItem -> ERROR: $e\n$stack');
      rethrow;
    }
  }

  /// Updates an existing menu item.
  Future<void> updateMenuItem(
    String shopId,
    String menuItemId,
    Map<String, dynamic> data,
  ) async {
    debugPrint(
      '📝 FirestoreService.updateMenuItem -> shops/$shopId/menuItems/$menuItemId',
    );
    try {
      await _firestore
          .collection('shops')
          .doc(shopId)
          .collection('menuItems')
          .doc(menuItemId)
          .set(data, SetOptions(merge: true));
      debugPrint('✅ FirestoreService.updateMenuItem -> SUCCESS');
    } catch (e, stack) {
      debugPrint('❌ FirestoreService.updateMenuItem -> ERROR: $e\n$stack');
      rethrow;
    }
  }

  /// Updates menu item availability (Available / Out of Stock).
  Future<void> updateMenuItemAvailability(
    String shopId,
    String menuItemId,
    bool isAvailable,
  ) async {
    debugPrint(
      '📝 FirestoreService.updateMenuItemAvailability -> shops/$shopId/menuItems/$menuItemId => $isAvailable',
    );
    try {
      await _firestore
          .collection('shops')
          .doc(shopId)
          .collection('menuItems')
          .doc(menuItemId)
          .set({'isAvailable': isAvailable}, SetOptions(merge: true));
      debugPrint('✅ FirestoreService.updateMenuItemAvailability -> SUCCESS');
    } catch (e, stack) {
      debugPrint(
        '❌ FirestoreService.updateMenuItemAvailability -> ERROR: $e\n$stack',
      );
      rethrow;
    }
  }

  /// Deletes a menu item from Firestore.
  Future<void> deleteMenuItem(String shopId, String menuItemId) async {
    debugPrint(
      '📝 FirestoreService.deleteMenuItem -> deleting shops/$shopId/menuItems/$menuItemId',
    );
    try {
      await _firestore
          .collection('shops')
          .doc(shopId)
          .collection('menuItems')
          .doc(menuItemId)
          .delete();
      debugPrint('✅ FirestoreService.deleteMenuItem -> SUCCESS');
    } catch (e, stack) {
      debugPrint('❌ FirestoreService.deleteMenuItem -> ERROR: $e\n$stack');
      rethrow;
    }
  }

  // ─── Firebase Storage Uploads ────────────────────────────────

  /// Uploads image bytes to Firebase Storage and returns download URL.
  Future<String?> uploadImage({
    required String shopId,
    required String path,
    required Uint8List bytes,
    required String fileName,
  }) async {
    try {
      final uniqueName =
          '${DateTime.now().millisecondsSinceEpoch}_$fileName';
      final ref = _storage.ref().child('shops/$shopId/$path/$uniqueName');
      final metadata = SettableMetadata(contentType: 'image/jpeg');

      final uploadTask = await ref.putData(bytes, metadata);
      final downloadUrl = await uploadTask.ref.getDownloadURL();
      debugPrint('✅ FirebaseStorage uploadImage -> SUCCESS: $downloadUrl');
      return downloadUrl;
    } catch (e) {
      debugPrint('⚠️ FirebaseStorage uploadImage error (safe fallback): $e');
      return null;
    }
  }

  // ─── App Config ─────────────────────────────────────────────

  /// Fetches the app configuration (force update version, etc.).
  Future<Map<String, dynamic>?> getAppConfig() async {
    try {
      final doc = await _firestore
          .collection('config')
          .doc('app')
          .get()
          .timeout(const Duration(seconds: 2));
      if (!doc.exists) return null;
      return doc.data();
    } catch (_) {
      return null;
    }
  }
}
