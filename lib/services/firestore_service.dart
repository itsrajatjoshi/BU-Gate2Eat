// BU Gate2Eat — Services
// Firestore service for reading and writing shop & menu data + Firebase Storage

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' hide Category;

import '../core/auth/auth_status.dart';
import '../models/category_model.dart';
import '../models/menu_item_model.dart';
import '../models/shop_model.dart';
import '../models/support_query_model.dart';
import 'image_optimization_service.dart';

/// Exception thrown for Firestore operations, including security and tenant boundary violations.
class FirestoreServiceException implements Exception {
  const FirestoreServiceException(this.message);
  final String message;

  @override
  String toString() => 'FirestoreServiceException: $message';
}

/// Service class for all Firestore operations.
/// Handles shops, categories, menu items, and storage assets.
class FirestoreService {
  FirestoreService({
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
    FirebaseAuth? auth,
    String? Function()? currentUserIdResolver,
    String? Function()? currentShopIdResolver,
    AuthRole Function()? currentUserRoleResolver,
    Future<void> Function(String collection, String docId, Map<String, dynamic> data)? docWriterForTesting,
    Stream<List<SupportQuery>> Function(String customerId)? supportQueryStreamForTesting,
    Future<void> Function(String shopId, Map<String, dynamic> data)? shopUpdaterForTesting,
    Future<void> Function(String shopId, String itemId, Map<String, dynamic> data)? menuItemUpdaterForTesting,
    Future<void> Function(String shopId, String itemId)? menuItemDeleterForTesting,
    Future<String?> Function(String path, Uint8List bytes)? storageUploaderForTesting,
    Stream<List<Category>> Function(String shopId)? categoriesStreamForTesting,
    Future<String> Function(Shop shop)? shopCreatorForTesting,
    Future<void> Function(String shopId)? shopDeleterForTesting,
    Stream<List<SupportQuery>> Function()? allSupportQueriesStreamForTesting,
    Future<List<SupportQuery>> Function()? allSupportQueriesLoaderForTesting,
  })  : _customFirestore = firestore,
        _customStorage = storage,
        _customAuth = auth,
        _customUserIdResolver = currentUserIdResolver,
        _customShopIdResolver = currentShopIdResolver,
        _customUserRoleResolver = currentUserRoleResolver,
        _docWriterForTesting = docWriterForTesting,
        _supportQueryStreamForTesting = supportQueryStreamForTesting,
        _shopUpdaterForTesting = shopUpdaterForTesting,
        _menuItemUpdaterForTesting = menuItemUpdaterForTesting,
        _menuItemDeleterForTesting = menuItemDeleterForTesting,
        _storageUploaderForTesting = storageUploaderForTesting,
        _categoriesStreamForTesting = categoriesStreamForTesting,
        _shopCreatorForTesting = shopCreatorForTesting,
        _shopDeleterForTesting = shopDeleterForTesting,
        _allSupportQueriesStreamForTesting = allSupportQueriesStreamForTesting,
        _allSupportQueriesLoaderForTesting = allSupportQueriesLoaderForTesting;

  final FirebaseFirestore? _customFirestore;
  final FirebaseStorage? _customStorage;
  final FirebaseAuth? _customAuth;
  final String? Function()? _customUserIdResolver;
  final String? Function()? _customShopIdResolver;
  final AuthRole Function()? _customUserRoleResolver;
  final Future<void> Function(String collection, String docId, Map<String, dynamic> data)? _docWriterForTesting;
  final Stream<List<SupportQuery>> Function(String customerId)? _supportQueryStreamForTesting;
  final Future<void> Function(String shopId, Map<String, dynamic> data)? _shopUpdaterForTesting;
  final Future<void> Function(String shopId, String itemId, Map<String, dynamic> data)? _menuItemUpdaterForTesting;
  final Future<void> Function(String shopId, String itemId)? _menuItemDeleterForTesting;
  final Future<String?> Function(String path, Uint8List bytes)? _storageUploaderForTesting;
  final Stream<List<Category>> Function(String shopId)? _categoriesStreamForTesting;
  final Future<String> Function(Shop shop)? _shopCreatorForTesting;
  final Future<void> Function(String shopId)? _shopDeleterForTesting;
  final Stream<List<SupportQuery>> Function()? _allSupportQueriesStreamForTesting;
  final Future<List<SupportQuery>> Function()? _allSupportQueriesLoaderForTesting;

  /// Checks if Firebase is initialized or custom firestore instance is provided.
  bool get isAvailable {
    try {
      if (_customFirestore != null) return true;
      return Firebase.apps.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Resolves the authoritative authenticated Firebase Auth UID.
  String? get _currentAuthUid {
    if (_customUserIdResolver != null) {
      return _customUserIdResolver!();
    }
    try {
      if (_customAuth != null) {
        return _customAuth!.currentUser?.uid;
      }
      if (Firebase.apps.isNotEmpty) {
        return FirebaseAuth.instance.currentUser?.uid;
      }
    } catch (_) {}
    return null;
  }

  /// Resolves the authoritative authenticated role.
  AuthRole get _currentAuthRole {
    if (_customUserRoleResolver != null) {
      return _customUserRoleResolver!();
    }
    if (_currentAuthUid == null) {
      return AuthRole.none;
    }
    return AuthRole.customer;
  }

  /// Resolves the authoritative authenticated shopId.
  String? get _currentAuthShopId {
    if (_customShopIdResolver != null) {
      return _customShopIdResolver!();
    }
    return null;
  }

  FirebaseFirestore get _firestore =>
      _customFirestore ?? FirebaseFirestore.instance;
  FirebaseStorage get _storage => _customStorage ?? FirebaseStorage.instance;

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

  /// Fetches the authenticated shopkeeper's assigned shop document.
  Future<Shop?> getMyShop() async {
    final role = _currentAuthRole;
    final shopId = _currentAuthShopId;
    if (role != AuthRole.shopkeeper || shopId == null || shopId.isEmpty) {
      throw const FirestoreServiceException(
        'Unauthorized: Caller is not an authenticated shopkeeper with an assigned shop',
      );
    }
    return getShop(shopId);
  }

  /// Updates the authenticated shopkeeper's assigned shop document.
  Future<void> updateMyShop(Map<String, dynamic> data) async {
    final role = _currentAuthRole;
    final shopId = _currentAuthShopId;
    if (role != AuthRole.shopkeeper || shopId == null || shopId.isEmpty) {
      throw const FirestoreServiceException(
        'Unauthorized: Caller is not an authenticated shopkeeper with an assigned shop',
      );
    }
    return updateShop(shopId, data);
  }

  /// Updates the authenticated shopkeeper's assigned shop open/closed override.
  Future<void> updateMyShopOpenOverride(bool isClosedOverride) async {
    final role = _currentAuthRole;
    final shopId = _currentAuthShopId;
    if (role != AuthRole.shopkeeper || shopId == null || shopId.isEmpty) {
      throw const FirestoreServiceException(
        'Unauthorized: Caller is not an authenticated shopkeeper with an assigned shop',
      );
    }
    return updateShopOpenOverride(shopId, isClosedOverride);
  }

  /// Updates shop details (name, description, timings, bannerUrl, etc.).
  Future<void> updateShop(String shopId, Map<String, dynamic> data) async {
    // ── Security Check: Tenant Authorization ──
    final role = _currentAuthRole;
    final trustedShopId = _currentAuthShopId;
    if (role != AuthRole.admin && role != AuthRole.shopkeeper) {
      throw const FirestoreServiceException(
        'Unauthorized: Caller cannot update shop configuration',
      );
    }
    if (role == AuthRole.shopkeeper) {
      if (trustedShopId == null || trustedShopId.isEmpty || trustedShopId != shopId) {
        throw FirestoreServiceException(
          'Unauthorized: Shopkeeper of "$trustedShopId" cannot modify shop "$shopId"',
        );
      }
    }

    final updateData = Map<String, dynamic>.from(data);
    updateData['updatedAt'] = FieldValue.serverTimestamp();
    debugPrint(
      '📝 FirestoreService.updateShop -> updating shops/$shopId with: $updateData',
    );
    if (_shopUpdaterForTesting != null) {
      await _shopUpdaterForTesting!(shopId, updateData);
      return;
    }
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
    // ── Security Check: Tenant Authorization ──
    final role = _currentAuthRole;
    final trustedShopId = _currentAuthShopId;
    if (role != AuthRole.admin && role != AuthRole.shopkeeper) {
      throw const FirestoreServiceException(
        'Unauthorized: Caller cannot update shop open status',
      );
    }
    if (role == AuthRole.shopkeeper) {
      if (trustedShopId == null || trustedShopId.isEmpty || trustedShopId != shopId) {
        throw FirestoreServiceException(
          'Unauthorized: Shopkeeper of "$trustedShopId" cannot modify open status for shop "$shopId"',
        );
      }
    }

    debugPrint(
      '📝 FirestoreService.updateShopOpenOverride -> shops/$shopId => isClosedOverride: $isClosedOverride',
    );
    if (_shopUpdaterForTesting != null) {
      await _shopUpdaterForTesting!(shopId, {'isClosedOverride': isClosedOverride});
      return;
    }
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

  /// Creates a new shop document in Firestore with optional banner and logo uploads.
  Future<String> createShop(
    Shop shop, {
    Uint8List? bannerBytes,
    Uint8List? logoBytes,
  }) async {
    // ── Security Check: Admin Authorization ──
    final role = _currentAuthRole;
    if (role != AuthRole.admin) {
      throw const FirestoreServiceException(
        'Unauthorized: Only administrators can create new shops',
      );
    }
    if (_shopCreatorForTesting != null) {
      return _shopCreatorForTesting!(shop);
    }

    debugPrint('📝 FirestoreService.createShop -> creating shops/${shop.id}');
    try {
      String bannerUrl = shop.bannerUrl;
      String logoUrl = shop.shopLogoImageUrl;

      // Upload banner and logo concurrently if both provided
      if (bannerBytes != null && bannerBytes.isNotEmpty && logoBytes != null && logoBytes.isNotEmpty) {
        if (kDebugMode) debugPrint('[SHOP] Parallel logo & banner upload started for new shop');
        final results = await Future.wait([
          uploadImage(
            shopId: shop.id,
            path: 'banner',
            bytes: bannerBytes,
            fileName: 'shop_banner.jpg',
          ),
          uploadImage(
            shopId: shop.id,
            path: 'logo',
            bytes: logoBytes,
            fileName: 'shop_logo.jpg',
          ),
        ]);
        if (results[0] != null && results[0]!.isNotEmpty) {
          bannerUrl = results[0]!;
        }
        if (results[1] != null && results[1]!.isNotEmpty) {
          logoUrl = results[1]!;
        }
      } else if (bannerBytes != null && bannerBytes.isNotEmpty) {
        final uploadedUrl = await uploadImage(
          shopId: shop.id,
          path: 'banner',
          bytes: bannerBytes,
          fileName: 'shop_banner.jpg',
        );
        if (uploadedUrl != null && uploadedUrl.isNotEmpty) {
          bannerUrl = uploadedUrl;
        }
      } else if (logoBytes != null && logoBytes.isNotEmpty) {
        final uploadedLogoUrl = await uploadImage(
          shopId: shop.id,
          path: 'logo',
          bytes: logoBytes,
          fileName: 'shop_logo.jpg',
        );
        if (uploadedLogoUrl != null && uploadedLogoUrl.isNotEmpty) {
          logoUrl = uploadedLogoUrl;
        }
      }

      final shopData = shop.toFirestore();
      shopData['bannerUrl'] = bannerUrl;
      shopData['shopLogoImageUrl'] = logoUrl;
      shopData['createdAt'] = FieldValue.serverTimestamp();
      shopData['updatedAt'] = FieldValue.serverTimestamp();

      await _firestore.collection('shops').doc(shop.id).set(shopData);
      debugPrint('✅ FirestoreService.createShop -> SUCCESS for shops/${shop.id}');
      return shop.id;
    } catch (e, stack) {
      debugPrint('❌ FirestoreService.createShop -> ERROR: $e\n$stack');
      rethrow;
    }
  }

  /// Deep cascade delete for a shop (Menu items + Categories + Storage images + Shop doc).
  Future<void> deleteShopCascade(
    String shopId, {
    String? bannerUrl,
    String? logoUrl,
  }) async {
    // ── Security Check: Admin Authorization ──
    final role = _currentAuthRole;
    if (role != AuthRole.admin) {
      throw const FirestoreServiceException(
        'Unauthorized: Only administrators can delete shops',
      );
    }
    if (_shopDeleterForTesting != null) {
      return _shopDeleterForTesting!(shopId);
    }

    debugPrint('📝 FirestoreService.deleteShopCascade -> deleting shops/$shopId');
    try {
      // 1. Delete all menu items and their storage photos
      final menuSnapshot = await _firestore
          .collection('shops')
          .doc(shopId)
          .collection('menuItems')
          .get();

      if (menuSnapshot.docs.isNotEmpty) {
        for (final doc in menuSnapshot.docs) {
          final data = doc.data();
          final imageUrl = data['imageUrl'] as String?;
          if (imageUrl != null && imageUrl.isNotEmpty) {
            await deleteStorageImageByUrl(imageUrl);
          }
        }

        // Commit document deletions in bounded batches of 400 (Firestore limit is 500)
        const chunkSize = 400;
        for (int i = 0; i < menuSnapshot.docs.length; i += chunkSize) {
          final end = (i + chunkSize < menuSnapshot.docs.length)
              ? i + chunkSize
              : menuSnapshot.docs.length;
          final batch = _firestore.batch();
          for (int j = i; j < end; j++) {
            batch.delete(menuSnapshot.docs[j].reference);
          }
          await batch.commit();
        }
      }
      debugPrint('✅ Deleted ${menuSnapshot.docs.length} menu items for shops/$shopId');

      // 2. Delete all categories in bounded batches
      final catSnapshot = await _firestore
          .collection('shops')
          .doc(shopId)
          .collection('categories')
          .get();

      if (catSnapshot.docs.isNotEmpty) {
        const catChunkSize = 400;
        for (int i = 0; i < catSnapshot.docs.length; i += catChunkSize) {
          final end = (i + catChunkSize < catSnapshot.docs.length)
              ? i + catChunkSize
              : catSnapshot.docs.length;
          final batch = _firestore.batch();
          for (int j = i; j < end; j++) {
            batch.delete(catSnapshot.docs[j].reference);
          }
          await batch.commit();
        }
      }
      debugPrint('✅ Deleted ${catSnapshot.docs.length} categories for shops/$shopId');

      // 3. Delete shop banner image from storage
      if (bannerUrl != null && bannerUrl.isNotEmpty) {
        await deleteStorageImageByUrl(bannerUrl);
      }

      // 4. Delete shop logo image from storage
      if (logoUrl != null && logoUrl.isNotEmpty) {
        await deleteStorageImageByUrl(logoUrl);
      }

      // 5. Delete the parent shop document (Historical orders in 'orders' are strictly preserved!)
      await _firestore.collection('shops').doc(shopId).delete();
      debugPrint('✅ FirestoreService.deleteShopCascade -> SUCCESS for shops/$shopId');
    } catch (e, stack) {
      debugPrint('❌ FirestoreService.deleteShopCascade -> ERROR: $e\n$stack');
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
    if (_categoriesStreamForTesting != null) {
      return _categoriesStreamForTesting!(shopId);
    }
    if (!isAvailable) return const Stream.empty();
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

  /// Stream of active categories for the authenticated shopkeeper's assigned shop.
  Stream<List<Category>> watchMyShopCategories() {
    final role = _currentAuthRole;
    final shopId = _currentAuthShopId;
    if (role != AuthRole.shopkeeper || shopId == null || shopId.isEmpty) {
      return const Stream.empty();
    }
    return watchCategories(shopId);
  }

  /// Creates a new custom category for a shop with a fixed neutral image.
  /// (Existing categories cannot be edited/deleted).
  Future<Category> createCustomCategory(
    String shopId,
    String categoryName,
  ) async {
    // ── Security Check: Tenant Authorization ──
    final role = _currentAuthRole;
    final trustedShopId = _currentAuthShopId;
    if (role != AuthRole.admin && role != AuthRole.shopkeeper) {
      throw const FirestoreServiceException(
        'Unauthorized: Caller cannot create categories',
      );
    }
    if (role == AuthRole.shopkeeper) {
      if (trustedShopId == null || trustedShopId.isEmpty || trustedShopId != shopId) {
        throw FirestoreServiceException(
          'Unauthorized: Shopkeeper of "$trustedShopId" cannot create category for shop "$shopId"',
        );
      }
    }

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
    // ── Security Check: Tenant Authorization ──
    final role = _currentAuthRole;
    final trustedShopId = _currentAuthShopId;
    if (role != AuthRole.admin && role != AuthRole.shopkeeper) {
      throw const FirestoreServiceException(
        'Unauthorized: Caller cannot add menu items',
      );
    }
    if (role == AuthRole.shopkeeper) {
      if (trustedShopId == null || trustedShopId.isEmpty || trustedShopId != shopId) {
        throw FirestoreServiceException(
          'Unauthorized: Shopkeeper of "$trustedShopId" cannot add menu item to shop "$shopId"',
        );
      }
    }

    debugPrint(
      '📝 FirestoreService.addMenuItem -> shops/$shopId/menuItems/${item.id}',
    );
    if (_menuItemUpdaterForTesting != null) {
      await _menuItemUpdaterForTesting!(shopId, item.id, item.toFirestore());
      return;
    }
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
    // ── Security Check: Tenant Authorization ──
    final role = _currentAuthRole;
    final trustedShopId = _currentAuthShopId;
    if (role != AuthRole.admin && role != AuthRole.shopkeeper) {
      throw const FirestoreServiceException(
        'Unauthorized: Caller cannot update menu items',
      );
    }
    if (role == AuthRole.shopkeeper) {
      if (trustedShopId == null || trustedShopId.isEmpty || trustedShopId != shopId) {
        throw FirestoreServiceException(
          'Unauthorized: Shopkeeper of "$trustedShopId" cannot update menu item in shop "$shopId"',
        );
      }
      if (data.containsKey('shopId') && data['shopId'] != trustedShopId) {
        throw const FirestoreServiceException(
          'Unauthorized: Cannot alter menu item shop ownership (shopId mutation prohibited)',
        );
      }
    }

    debugPrint(
      '📝 FirestoreService.updateMenuItem -> shops/$shopId/menuItems/$menuItemId',
    );
    if (_menuItemUpdaterForTesting != null) {
      await _menuItemUpdaterForTesting!(shopId, menuItemId, data);
      return;
    }
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
    // ── Security Check: Tenant Authorization ──
    final role = _currentAuthRole;
    final trustedShopId = _currentAuthShopId;
    if (role != AuthRole.admin && role != AuthRole.shopkeeper) {
      throw const FirestoreServiceException(
        'Unauthorized: Caller cannot update menu item availability',
      );
    }
    if (role == AuthRole.shopkeeper) {
      if (trustedShopId == null || trustedShopId.isEmpty || trustedShopId != shopId) {
        throw FirestoreServiceException(
          'Unauthorized: Shopkeeper of "$trustedShopId" cannot update availability for shop "$shopId"',
        );
      }
    }

    debugPrint(
      '📝 FirestoreService.updateMenuItemAvailability -> shops/$shopId/menuItems/$menuItemId => $isAvailable',
    );
    if (_menuItemUpdaterForTesting != null) {
      await _menuItemUpdaterForTesting!(shopId, menuItemId, {'isAvailable': isAvailable});
      return;
    }
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

  /// Deletes a menu item from Firestore and cleans up its storage photo (best-effort).
  Future<void> deleteMenuItem(
    String shopId,
    String menuItemId, {
    String? imageUrl,
  }) async {
    // ── Security Check: Tenant Authorization ──
    final role = _currentAuthRole;
    final trustedShopId = _currentAuthShopId;
    if (role != AuthRole.admin && role != AuthRole.shopkeeper) {
      throw const FirestoreServiceException(
        'Unauthorized: Caller cannot delete menu items',
      );
    }
    if (role == AuthRole.shopkeeper) {
      if (trustedShopId == null || trustedShopId.isEmpty || trustedShopId != shopId) {
        throw FirestoreServiceException(
          'Unauthorized: Shopkeeper of "$trustedShopId" cannot delete menu item from shop "$shopId"',
        );
      }
    }

    debugPrint(
      '📝 FirestoreService.deleteMenuItem -> deleting shops/$shopId/menuItems/$menuItemId',
    );
    if (_menuItemDeleterForTesting != null) {
      await _menuItemDeleterForTesting!(shopId, menuItemId);
      return;
    }
    try {
      await _firestore
          .collection('shops')
          .doc(shopId)
          .collection('menuItems')
          .doc(menuItemId)
          .delete();
      debugPrint('✅ FirestoreService.deleteMenuItem -> doc deleted');

      // Best-effort cleanup of associated Firebase Storage image
      if (imageUrl != null && imageUrl.isNotEmpty) {
        try {
          await deleteStorageImageByUrl(imageUrl);
        } catch (e) {
          debugPrint('⚠️ Best-effort image cleanup skipped on delete: $e');
        }
      }
      debugPrint('✅ FirestoreService.deleteMenuItem -> SUCCESS');
    } catch (e, stack) {
      debugPrint('❌ FirestoreService.deleteMenuItem -> ERROR: $e\n$stack');
      rethrow;
    }
  }

  // ─── Firebase Storage Operations ─────────────────────────────

  /// Uploads optimized image bytes to Firebase Storage and returns download URL.
  Future<String?> uploadImage({
    required String shopId,
    required String path,
    required Uint8List bytes,
    required String fileName,
  }) async {
    final sizeKb = (bytes.lengthInBytes / 1024).toStringAsFixed(1);
    final uniqueName = '${DateTime.now().millisecondsSinceEpoch}_$fileName';
    final fullStoragePath = 'shops/$shopId/$path/$uniqueName';

    // ── Security Check: Tenant Authorization & Strict Path Parsing ──
    final role = _currentAuthRole;
    final trustedShopId = _currentAuthShopId;
    if (role != AuthRole.admin && role != AuthRole.shopkeeper) {
      throw const FirestoreServiceException(
        'Unauthorized: Caller cannot upload shop assets',
      );
    }
    if (role == AuthRole.shopkeeper) {
      if (trustedShopId == null || trustedShopId.isEmpty || trustedShopId != shopId) {
        throw FirestoreServiceException(
          'Unauthorized: Shopkeeper of "$trustedShopId" cannot upload images for shop "$shopId"',
        );
      }
      if (path.contains('..') ||
          path.contains('\\') ||
          fileName.contains('..') ||
          fileName.contains('/') ||
          fileName.contains('\\')) {
        throw const FirestoreServiceException(
          'Unauthorized: Malformed or path traversal detected in storage path',
        );
      }
      final segments = fullStoragePath.split('/');
      if (segments.length < 3 || segments[0] != 'shops' || segments[1] != trustedShopId) {
        throw FirestoreServiceException(
          'Unauthorized: Storage path "$fullStoragePath" violates tenant boundary for "$trustedShopId"',
        );
      }
    }

    if (kDebugMode) {
      debugPrint('STEP 1: NEW IMAGE UPLOAD START');
      debugPrint('STORAGE PATH: $fullStoragePath');
      debugPrint('OPTIMIZED SIZE: $sizeKb KB (${bytes.lengthInBytes} bytes)');
    }

    if (bytes.isEmpty) {
      if (kDebugMode) debugPrint('❌ UPLOAD ERROR: Byte array is empty!');
      throw Exception('Cannot upload empty image bytes');
    }

    if (_storageUploaderForTesting != null) {
      return _storageUploaderForTesting!(fullStoragePath, bytes);
    }

    try {
      final detectedType = ImageOptimizationService.detectContentType(bytes);
      final storageRef = _storage.ref(fullStoragePath);
      final metadata = SettableMetadata(
        contentType: detectedType,
        customMetadata: {
          'uploadedBy': 'shopkeeper',
          'shopId': shopId,
        },
      );

      final Stopwatch uploadStopwatch = Stopwatch()..start();
      final UploadTask uploadTask = storageRef.putData(bytes, metadata);

      // Await upload completion with safety timeout
      final TaskSnapshot snapshot = await uploadTask.timeout(
        const Duration(seconds: 40),
        onTimeout: () {
          if (kDebugMode) {
            debugPrint(
              '❌ UPLOAD ERROR: UploadTask timed out after 40 seconds. Check network and Firebase Storage rules.',
            );
          }
          throw Exception(
            'Storage upload timed out. Please check network and Firebase Storage configuration.',
          );
        },
      );
      final int uploadMs = uploadStopwatch.elapsedMilliseconds;

      final Stopwatch urlStopwatch = Stopwatch()..start();
      final downloadUrl = await snapshot.ref.getDownloadURL().timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          if (kDebugMode) debugPrint('❌ UPLOAD ERROR: getDownloadURL timed out');
          throw Exception('Failed to get download URL within 15 seconds.');
        },
      );
      final int urlMs = urlStopwatch.elapsedMilliseconds;

      if (kDebugMode) {
        debugPrint(
          '⏱️ [PERF UPLOAD] File: $fileName ($sizeKb KB) | Upload: ${uploadMs}ms | getDownloadURL: ${urlMs}ms | Total: ${uploadMs + urlMs}ms',
        );
      }
      return downloadUrl;
    } catch (e, stack) {
      if (kDebugMode) debugPrint('❌ UPLOAD ERROR (Exception caught): $e\n$stack');
      rethrow;
    }
  }

  /// Safely deletes an old image from Firebase Storage by its download URL.
  /// 100% best-effort: NEVER throws an error, NEVER interrupts save/update.
  Future<void> deleteStorageImageByUrl(String? imageUrl) async {
    if (imageUrl == null || imageUrl.trim().isEmpty) return;

    try {
      final trimmedUrl = imageUrl.trim();
      debugPrint('STEP 5: OLD IMAGE DELETE START');
      debugPrint('OLD URL: $trimmedUrl');

      if (trimmedUrl.contains('firebasestorage.googleapis.com') ||
          trimmedUrl.contains('firebasestorage.app') ||
          trimmedUrl.contains('appspot.com')) {
        try {
          final ref = _storage.refFromURL(trimmedUrl);
          debugPrint('OLD STORAGE PATH: ${ref.fullPath}');
          await ref.delete();
          debugPrint(
            '✅ STEP 5: OLD IMAGE DELETE COMPLETE (Deleted: ${ref.fullPath})',
          );
        } on FirebaseException catch (fe) {
          if (fe.code == 'object-not-found') {
            debugPrint(
              'ℹ️ STEP 5: OLD IMAGE NOT FOUND (object-not-found). Old image already missing. Ignored safely.',
            );
          } else {
            debugPrint(
              '⚠️ STEP 5: OLD IMAGE DELETE NOTE: ${fe.code} - ${fe.message}',
            );
          }
        } catch (e) {
          debugPrint(
            '⚠️ STEP 5: Could not parse/delete old storage ref (safe ignore): $e',
          );
        }
      } else {
        debugPrint(
          'ℹ️ STEP 5: Old image is external/sample image (e.g. Unsplash). No Storage delete needed.',
        );
      }
    } catch (e) {
      debugPrint('⚠️ STEP 5: Safe top-level fallback: $e');
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

  // ─── Customer Support Queries ────────────────────────────────

  /// Submits a customer support query to Firestore `supportQueries` collection.
  Future<String> submitSupportQuery({
    required String name,
    required String query,
    required String phoneNumber,
    String customerId = '',
  }) async {
    final cleanName = name.trim();
    final cleanQuery = query.trim();
    final cleanPhone = phoneNumber.trim();

    if (cleanName.isEmpty) {
      throw ArgumentError('Customer name cannot be empty.');
    }
    if (cleanQuery.isEmpty) {
      throw ArgumentError('Query text cannot be empty.');
    }

    final authUid = _currentAuthUid;
    final effectiveCustomerId = (authUid != null && authUid.isNotEmpty)
        ? authUid
        : customerId.trim();

    final data = {
      'name': cleanName,
      'query': cleanQuery,
      'phoneNumber': cleanPhone,
      'phone': cleanPhone,
      'customerId': effectiveCustomerId,
      'status': 'unread',
      'createdAt': FieldValue.serverTimestamp(),
    };

    if (_docWriterForTesting != null) {
      const mockId = 'mock_query_id_test';
      data['id'] = mockId;
      await _docWriterForTesting!('supportQueries', mockId, data);
      return mockId;
    }

    if (!isAvailable) return 'offline_support_query';

    final docRef = _firestore.collection('supportQueries').doc();
    data['id'] = docRef.id;

    debugPrint(
      '📝 FirestoreService.submitSupportQuery -> creating supportQueries/${docRef.id}',
    );
    try {
      await docRef.set(data);
      debugPrint(
        '✅ FirestoreService.submitSupportQuery -> SUCCESS for ${docRef.id}',
      );
      return docRef.id;
    } catch (e, stack) {
      debugPrint('❌ FirestoreService.submitSupportQuery -> ERROR: $e\n$stack');
      rethrow;
    }
  }

  /// Real-time stream of the authenticated customer's own support queries.
  /// Derives customer identity directly from authenticated Firebase Auth session.
  Stream<List<SupportQuery>> watchMySupportQueries() {
    final authUid = _currentAuthUid;
    if (authUid == null || authUid.isEmpty) {
      return const Stream.empty();
    }
    if (_supportQueryStreamForTesting != null) {
      return _supportQueryStreamForTesting!(authUid);
    }
    if (!isAvailable) return const Stream.empty();
    return _firestore
        .collection('supportQueries')
        .where('customerId', isEqualTo: authUid)
        .snapshots()
        .map((snapshot) {
      final queries = snapshot.docs
          .map((doc) => SupportQuery.fromFirestore(doc))
          .toList();
      queries.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return queries;
    });
  }

  /// Real-time stream of a customer's support queries.
  /// If [customerId] is provided, independently verifies it against authenticated Firebase UID.
  /// If unauthenticated or [customerId] does not match authenticated UID, returns empty stream.
  Stream<List<SupportQuery>> watchCustomerSupportQueries([String? customerId]) {
    final authUid = _currentAuthUid;
    if (authUid == null || authUid.isEmpty) {
      return const Stream.empty();
    }
    if (customerId != null &&
        customerId.isNotEmpty &&
        customerId.trim() != authUid) {
      debugPrint(
        '⛔ [FirestoreService] Blocked unauthorized query: Caller "$authUid" cannot access queries of "$customerId".',
      );
      return const Stream.empty();
    }
    return watchMySupportQueries();
  }

  /// Real-time stream of customer support queries for Admin, sorted newest first.
  Stream<List<SupportQuery>> watchSupportQueries() {
    final role = _currentAuthRole;
    if (role != AuthRole.admin) {
      debugPrint('⛔ [FirestoreService] Blocked watchSupportQueries: Role "$role" is not admin.');
      return const Stream.empty();
    }
    if (_allSupportQueriesStreamForTesting != null) {
      return _allSupportQueriesStreamForTesting!();
    }
    if (!isAvailable) return const Stream.empty();
    return _firestore
        .collection('supportQueries')
        .snapshots()
        .map((snapshot) {
      final queries = snapshot.docs
          .map((doc) => SupportQuery.fromFirestore(doc))
          .toList();
      queries.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return queries;
    });
  }

  /// One-time fetch of customer support queries for Admin, sorted newest first.
  Future<List<SupportQuery>> getSupportQueries() async {
    final role = _currentAuthRole;
    if (role != AuthRole.admin) {
      throw const FirestoreServiceException(
        'Unauthorized: Only administrators can access all customer support queries',
      );
    }
    if (_allSupportQueriesLoaderForTesting != null) {
      return _allSupportQueriesLoaderForTesting!();
    }
    try {
      final snapshot = await _firestore.collection('supportQueries').get();
      final queries = snapshot.docs
          .map((doc) => SupportQuery.fromFirestore(doc))
          .toList();
      queries.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return queries;
    } catch (e) {
      debugPrint('❌ Firestore getSupportQueries error: $e');
      return [];
    }
  }
}
