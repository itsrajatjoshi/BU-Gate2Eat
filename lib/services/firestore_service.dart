// BU Gate2Eat — Services
// Firestore service for reading shop data

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/category_model.dart';
import '../models/menu_item_model.dart';
import '../models/shop_model.dart';

/// Service class for all Firestore read operations.
/// Handles shops, categories, and menu items.
class FirestoreService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ─── Shops ──────────────────────────────────────────────────

  /// Fetches all active shops, sorted by sortOrder.
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
      return [];
    }
  }

  /// Fetches a single shop by ID.
  Future<Shop?> getShop(String shopId) async {
    try {
      final doc = await _firestore.collection('shops').doc(shopId).get();
      if (!doc.exists) return null;
      return Shop.fromFirestore(doc);
    } catch (_) {
      return null;
    }
  }

  /// Stream of all active shops (real-time updates).
  Stream<List<Shop>> watchShops() {
    return _firestore
        .collection('shops')
        .where('isActive', isEqualTo: true)
        .orderBy('sortOrder')
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.docs.map((doc) => Shop.fromFirestore(doc)).toList(),
        );
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
    } catch (_) {
      return [];
    }
  }

  // ─── Menu Items ─────────────────────────────────────────────

  /// Fetches all menu items for a given shop, sorted by sortOrder.
  Future<List<MenuItem>> getMenuItems(String shopId) async {
    try {
      final snapshot = await _firestore
          .collection('shops')
          .doc(shopId)
          .collection('menuItems')
          .orderBy('sortOrder')
          .get();

      return snapshot.docs.map((doc) => MenuItem.fromFirestore(doc)).toList();
    } catch (_) {
      return [];
    }
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
    } catch (_) {
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
          .where('isAvailable', isEqualTo: true)
          .get();

      final items =
          snapshot.docs.map((doc) => MenuItem.fromFirestore(doc)).toList();
      items.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      return items;
    } catch (_) {
      return [];
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

