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

  /// Sample fallback shops when Firestore API is offline or initial database is empty.
  static final List<Shop> fallbackShops = [
    Shop(
      id: 'rajat_shop',
      name: 'Rajat Shop',
      description: 'Chinese, Fast Food, Snacks & Special Thalis',
      imageUrl: 'https://images.unsplash.com/photo-1555396273-367ea4eb4db5?w=500',
      whatsappNumber: '8295643910',
      phoneNumber: '8295643910',
      openTime: '08:00',
      closeTime: '23:30',
      isActive: true,
      sortOrder: 1,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    ),
    Shop(
      id: 'nayan_shop',
      name: 'Nayan Shop',
      description: 'Momos, Chinese, Fast Food & Value Thalis',
      imageUrl: 'https://images.unsplash.com/photo-1585937421612-70a008356fbe?w=500',
      whatsappNumber: '8875344034',
      phoneNumber: '8875344034',
      openTime: '08:00',
      closeTime: '23:30',
      isActive: true,
      sortOrder: 2,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    ),
  ];

  /// Fallback categories for shops
  static final List<Category> fallbackCategories = [
    const Category(id: 'momos', name: 'Momos', sortOrder: 1),
    const Category(id: 'snacks', name: 'Snacks & Fast Food', sortOrder: 2),
    const Category(id: 'thalis', name: 'Thalis & Meals', sortOrder: 3),
  ];

  /// Fallback menu items for Rajat Shop
  static final List<MenuItem> rajatMenuItems = [
    const MenuItem(id: 'veg_steam_momos', name: 'Veg Steam Momos', description: 'Freshly steamed veg momos with chutney', price: 60.0, imageUrl: '', categoryId: 'momos', isVeg: true, isAvailable: true, sortOrder: 1),
    const MenuItem(id: 'veg_fried_momos', name: 'Veg Fried Momos', description: 'Crispy fried veg momos with chutney', price: 70.0, imageUrl: '', categoryId: 'momos', isVeg: true, isAvailable: true, sortOrder: 2),
    const MenuItem(id: 'paneer_steam_momos', name: 'Paneer Steam Momos', description: 'Steamed paneer momos with chutney', price: 70.0, imageUrl: '', categoryId: 'momos', isVeg: true, isAvailable: true, sortOrder: 3),
    const MenuItem(id: 'paneer_fried_momos', name: 'Paneer Fried Momos', description: 'Crispy fried paneer momos', price: 80.0, imageUrl: '', categoryId: 'momos', isVeg: true, isAvailable: true, sortOrder: 4),
    const MenuItem(id: 'hakka_noodles', name: 'Hakka Noodles', description: 'Classic wok-tossed veg hakka noodles', price: 120.0, imageUrl: '', categoryId: 'snacks', isVeg: true, isAvailable: true, sortOrder: 5),
    const MenuItem(id: 'samosa', name: 'Samosa', description: 'Crispy potato stuffed samosa', price: 15.0, imageUrl: '', categoryId: 'snacks', isVeg: true, isAvailable: true, sortOrder: 6),
    const MenuItem(id: 'kachori', name: 'Kachori', description: 'Spicy khasta kachori with chutney', price: 15.0, imageUrl: '', categoryId: 'snacks', isVeg: true, isAvailable: true, sortOrder: 7),
    const MenuItem(id: 'pav_bhaji', name: 'Pav Bhaji', description: 'Butter pav served with spicy bhaji', price: 99.0, imageUrl: '', categoryId: 'snacks', isVeg: true, isAvailable: true, sortOrder: 8),
    const MenuItem(id: 'chole_bhature', name: 'Chole Bhature', description: '2 fluffy bhature served with spicy chole', price: 149.0, imageUrl: '', categoryId: 'snacks', isVeg: true, isAvailable: true, sortOrder: 9),
    const MenuItem(id: 'veg_thali', name: 'Veg Thali', description: 'Complete North Indian veg thali meal', price: 199.0, imageUrl: '', categoryId: 'thalis', isVeg: true, isAvailable: true, sortOrder: 10),
    const MenuItem(id: 'veg_special_thali', name: 'Veg Special Thali', description: 'Special paneer thali with sweet & extra dishes', price: 299.0, imageUrl: '', categoryId: 'thalis', isVeg: true, isAvailable: true, sortOrder: 11),
  ];

  /// Fallback menu items for Nayan Shop
  static final List<MenuItem> nayanMenuItems = [
    const MenuItem(id: 'veg_steam_momos', name: 'Veg Steam Momos', description: 'Steamed veg momos served hot', price: 50.0, imageUrl: '', categoryId: 'momos', isVeg: true, isAvailable: true, sortOrder: 1),
    const MenuItem(id: 'veg_fried_momos', name: 'Veg Fried Momos', description: 'Crispy fried veg momos', price: 60.0, imageUrl: '', categoryId: 'momos', isVeg: true, isAvailable: true, sortOrder: 2),
    const MenuItem(id: 'paneer_steam_momos', name: 'Paneer Steam Momos', description: 'Soft steamed paneer momos', price: 60.0, imageUrl: '', categoryId: 'momos', isVeg: true, isAvailable: true, sortOrder: 3),
    const MenuItem(id: 'paneer_fried_momos', name: 'Paneer Fried Momos', description: 'Golden fried paneer momos', price: 70.0, imageUrl: '', categoryId: 'momos', isVeg: true, isAvailable: true, sortOrder: 4),
    const MenuItem(id: 'chicken_kurkure_momos', name: 'Chicken Kurkure Momos', description: 'Crunchy kurkure coated chicken momos', price: 99.0, imageUrl: '', categoryId: 'momos', isVeg: false, isAvailable: true, sortOrder: 5),
    const MenuItem(id: 'hakka_noodles', name: 'Hakka Noodles', description: 'Veg noodles tossed with fresh veggies', price: 110.0, imageUrl: '', categoryId: 'snacks', isVeg: true, isAvailable: true, sortOrder: 6),
    const MenuItem(id: 'samosa', name: 'Samosa', description: 'Fresh hot samosa', price: 10.0, imageUrl: '', categoryId: 'snacks', isVeg: true, isAvailable: true, sortOrder: 7),
    const MenuItem(id: 'kachori', name: 'Kachori', description: 'Hot spicy kachori', price: 10.0, imageUrl: '', categoryId: 'snacks', isVeg: true, isAvailable: true, sortOrder: 8),
    const MenuItem(id: 'pav_bhaji', name: 'Pav Bhaji', description: 'Hot pav bhaji with extra butter', price: 79.0, imageUrl: '', categoryId: 'snacks', isVeg: true, isAvailable: true, sortOrder: 9),
    const MenuItem(id: 'chole_bhature', name: 'Chole Bhature', description: '2 hot bhature with spicy chole', price: 129.0, imageUrl: '', categoryId: 'snacks', isVeg: true, isAvailable: true, sortOrder: 10),
    const MenuItem(id: 'veg_thali', name: 'Veg Thali', description: 'Delicious veg thali meal', price: 149.0, imageUrl: '', categoryId: 'thalis', isVeg: true, isAvailable: true, sortOrder: 11),
    const MenuItem(id: 'veg_special_thali', name: 'Veg Special Thali', description: 'Loaded special veg thali meal', price: 249.0, imageUrl: '', categoryId: 'thalis', isVeg: true, isAvailable: true, sortOrder: 12),
  ];

  // ─── Shops ──────────────────────────────────────────────────

  /// Fetches all active shops, sorted by sortOrder (with fallback on offline/error).
  Future<List<Shop>> getShops() async {
    try {
      final snapshot = await _firestore
          .collection('shops')
          .where('isActive', isEqualTo: true)
          .get()
          .timeout(const Duration(seconds: 3));

      final shops =
          snapshot.docs.map((doc) => Shop.fromFirestore(doc)).toList();

      shops.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

      if (shops.isEmpty) return fallbackShops;
      return shops;
    } catch (_) {
      return fallbackShops;
    }
  }

  /// Fetches a single shop by ID.
  Future<Shop?> getShop(String shopId) async {
    try {
      final doc = await _firestore
          .collection('shops')
          .doc(shopId)
          .get()
          .timeout(const Duration(seconds: 3));
      if (!doc.exists) {
        return _getFallbackShopById(shopId);
      }
      return Shop.fromFirestore(doc);
    } catch (_) {
      return _getFallbackShopById(shopId);
    }
  }

  Shop _getFallbackShopById(String shopId) {
    return fallbackShops.firstWhere(
      (s) => s.id == shopId || s.name.toLowerCase().contains(shopId.toLowerCase()),
      orElse: () => fallbackShops.first,
    );
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

  /// Fetches all categories for a given shop, sorted by sortOrder.
  Future<List<Category>> getCategories(String shopId) async {
    try {
      final snapshot = await _firestore
          .collection('shops')
          .doc(shopId)
          .collection('categories')
          .orderBy('sortOrder')
          .get()
          .timeout(const Duration(seconds: 3));

      final categories =
          snapshot.docs.map((doc) => Category.fromFirestore(doc)).toList();
      if (categories.isEmpty) return fallbackCategories;
      return categories;
    } catch (_) {
      return fallbackCategories;
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
          .get()
          .timeout(const Duration(seconds: 3));

      final items =
          snapshot.docs.map((doc) => MenuItem.fromFirestore(doc)).toList();
      if (items.isEmpty) return _getFallbackMenuItems(shopId);
      return items;
    } catch (_) {
      return _getFallbackMenuItems(shopId);
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
          .get()
          .timeout(const Duration(seconds: 3));

      final items =
          snapshot.docs.map((doc) => MenuItem.fromFirestore(doc)).toList();
      items.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

      if (items.isEmpty) {
        return _getFallbackMenuItems(shopId)
            .where((i) => i.categoryId == categoryId)
            .toList();
      }
      return items;
    } catch (_) {
      return _getFallbackMenuItems(shopId)
          .where((i) => i.categoryId == categoryId)
          .toList();
    }
  }

  List<MenuItem> _getFallbackMenuItems(String shopId) {
    if (shopId.contains('nayan')) {
      return nayanMenuItems;
    }
    return rajatMenuItems;
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
