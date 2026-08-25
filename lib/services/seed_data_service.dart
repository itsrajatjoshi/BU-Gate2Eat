// BU Gate2Eat — Services
// Seed service for populating shop & menu data in Firestore ONLY when missing.
//
// CRITICAL BUSINESS RULE:
// Firestore is the permanent source of truth.
// Seed data is for first-time missing document creation only.
// If a shop document or field already exists in Firestore, it is NEVER overwritten.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Populates initial shop data into Firestore using custom document IDs.
/// NEVER overwrites existing shops, contact numbers, order numbers, or manually edited prices.
class SeedDataService {
  /// Entry point to ensure initial shops exist.
  /// Evaluates each shop independently so existing shops are 100% untouched.
  static Future<void> seedInitialData() async {
    final firestore = FirebaseFirestore.instance;

    // 1. Rajat Shop
    try {
      await _seedRajatShop(firestore);
    } catch (e) {
      debugPrint('Error checking/seeding Rajat Shop: $e');
    }

    // 2. Nayan Shop
    try {
      await _seedNayanShop(firestore);
    } catch (e) {
      debugPrint('Error checking/seeding Nayan Shop: $e');
    }

    // 3. Kivisha Shop
    try {
      await _seedKivishaShop(firestore);
    } catch (e) {
      debugPrint('Error checking/seeding Kivisha Shop: $e');
    }

    // 4. UP 16 Junction Fast Food
    try {
      await _seedUP16Shop(firestore);
    } catch (e) {
      debugPrint('Error checking/seeding UP16 Shop: $e');
    }
  }

  // ─── Shop 1: Rajat Shop ───────────────────────────────────────────────
  static Future<void> _seedRajatShop(FirebaseFirestore firestore) async {
    const shopId = 'rajat_shop';
    final shopRef = firestore.collection('shops').doc(shopId);
    final doc = await shopRef.get();

    if (!doc.exists) {
      debugPrint('🌱 SeedDataService: Creating initial document for $shopId');
      await shopRef.set({
        'name': 'Rajat Shop',
        'description': 'Chinese, Fast Food, Snacks & Special Thalis',
        'bannerUrl': 'https://images.unsplash.com/photo-1555396273-367ea4eb4db5?w=500',
        'contactNumber': '8295643910',
        'orderNumber': '8295643910',
        'openTime': '08:00',
        'closeTime': '23:30',
        'isClosedOverride': false,
        'isActive': true,
        'sortOrder': 1,
        'searchKeywords': ['momos', 'chinese', 'fast food', 'snacks', 'thali', 'rajat'],
        'deliveryNote': 'Pickup from Gate 2',
        'orderMethod': 'whatsapp',
        'minimumOrderAmount': 0,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Categories
      final categories = [
        {'id': 'momos', 'name': 'Momos', 'imageUrl': 'https://images.unsplash.com/photo-1541696432-82c6da8ce7bf?w=300&auto=format&fit=crop&q=80', 'sortOrder': 1},
        {'id': 'pizzas', 'name': 'Pizzas', 'imageUrl': 'https://images.unsplash.com/photo-1513104890138-7c749659a591?w=300&auto=format&fit=crop&q=80', 'sortOrder': 2},
        {'id': 'burgers', 'name': 'Burgers', 'imageUrl': 'https://images.unsplash.com/photo-1568901346375-23c9450c58cd?w=300&auto=format&fit=crop&q=80', 'sortOrder': 3},
        {'id': 'biryani', 'name': 'Biryani', 'imageUrl': 'https://images.unsplash.com/photo-1633945274405-b6c8069047b0?w=300&auto=format&fit=crop&q=80', 'sortOrder': 4},
        {'id': 'thalis', 'name': 'Thali', 'imageUrl': 'https://images.unsplash.com/photo-1626777552726-4a6b54c97e46?w=300&auto=format&fit=crop&q=80', 'sortOrder': 5},
        {'id': 'snacks', 'name': 'Snacks', 'imageUrl': 'https://images.unsplash.com/photo-1601050690597-df0568f70950?w=300&auto=format&fit=crop&q=80', 'sortOrder': 6},
      ];
      for (final cat in categories) {
        await shopRef.collection('categories').doc(cat['id'] as String).set({
          'name': cat['name'],
          'imageUrl': cat['imageUrl'],
          'sortOrder': cat['sortOrder'],
          'isActive': true,
        });
      }

      // Initial Menu Items
      final items = [
        {'id': 'veg_steam_momos', 'name': 'Veg Steam Momos', 'details': '8 Pieces', 'price': 60, 'cat': 'momos', 'isVeg': true, 'rec': true},
        {'id': 'veg_fried_momos', 'name': 'Veg Fried Momos', 'details': '8 Pieces', 'price': 70, 'cat': 'momos', 'isVeg': true, 'rec': false},
        {'id': 'paneer_steam_momos', 'name': 'Paneer Steam Momos', 'details': '8 Pieces', 'price': 70, 'cat': 'momos', 'isVeg': true, 'rec': true},
        {'id': 'paneer_fried_momos', 'name': 'Paneer Fried Momos', 'details': '8 Pieces', 'price': 80, 'cat': 'momos', 'isVeg': true, 'rec': false},
        {'id': 'hakka_noodles', 'name': 'Hakka Noodles', 'details': '1 Plate (500 gm)', 'price': 120, 'cat': 'snacks', 'isVeg': true, 'rec': true},
        {'id': 'samosa', 'name': 'Samosa', 'details': '1 Piece', 'price': 15, 'cat': 'snacks', 'isVeg': true, 'rec': false},
        {'id': 'kachori', 'name': 'Kachori', 'details': '1 Piece', 'price': 15, 'cat': 'snacks', 'isVeg': true, 'rec': false},
        {'id': 'pav_bhaji', 'name': 'Pav Bhaji', 'details': '2 Pav + Bhaji', 'price': 99, 'cat': 'snacks', 'isVeg': true, 'rec': true},
        {'id': 'chole_bhature', 'name': 'Chole Bhature', 'details': '2 Bhature + Chole', 'price': 149, 'cat': 'snacks', 'isVeg': true, 'rec': true},
        {'id': 'veg_thali', 'name': 'Veg Thali', 'details': 'Standard Meal', 'price': 199, 'cat': 'thalis', 'isVeg': true, 'rec': false},
        {'id': 'veg_special_thali', 'name': 'Veg Special Thali', 'details': 'Loaded Paneer Meal', 'price': 299, 'cat': 'thalis', 'isVeg': true, 'rec': true},
      ];
      for (int i = 0; i < items.length; i++) {
        final item = items[i];
        final docId = item['id'] as String;
        await shopRef.collection('menuItems').doc(docId).set({
          'name': item['name'],
          'details': item['details'],
          'price': item['price'],
          'imageUrl': '',
          'categoryId': item['cat'],
          'isVeg': item['isVeg'],
          'isAvailable': true,
          'isRecommended': item['rec'],
          'sortOrder': i + 1,
        });
      }
    } else {
      // Document already exists: NEVER OVERWRITE ANY EXISTING FIELD!
      await _backfillMissingShopFields(
        shopRef,
        doc,
        defaultOrderMethod: 'whatsapp',
        defaultMinOrderAmount: 0,
        fallbackName: 'Rajat Shop',
      );
    }
  }

  // ─── Shop 2: Nayan Shop ───────────────────────────────────────────────
  static Future<void> _seedNayanShop(FirebaseFirestore firestore) async {
    const shopId = 'nayan_shop';
    final shopRef = firestore.collection('shops').doc(shopId);
    final doc = await shopRef.get();

    if (!doc.exists) {
      debugPrint('🌱 SeedDataService: Creating initial document for $shopId');
      await shopRef.set({
        'name': 'Nayan Shop',
        'description': 'Momos, Chinese, Fast Food & Value Thalis',
        'bannerUrl': 'https://images.unsplash.com/photo-1585937421612-70a008356fbe?w=500',
        'contactNumber': '8295643910',
        'orderNumber': '8295643910',
        'openTime': '08:00',
        'closeTime': '23:30',
        'isClosedOverride': false,
        'isActive': true,
        'sortOrder': 2,
        'searchKeywords': ['momos', 'chinese', 'fast food', 'nayan', 'chicken'],
        'deliveryNote': 'Pickup from Gate 2',
        'orderMethod': 'whatsapp',
        'minimumOrderAmount': 0,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Categories
      final categories = [
        {'id': 'momos', 'name': 'Momos', 'imageUrl': 'https://images.unsplash.com/photo-1541696432-82c6da8ce7bf?w=300&auto=format&fit=crop&q=80', 'sortOrder': 1},
        {'id': 'rolls', 'name': 'Rolls', 'imageUrl': 'https://images.unsplash.com/photo-1626700051175-6818013e1d4f?w=300&auto=format&fit=crop&q=80', 'sortOrder': 2},
        {'id': 'noodles', 'name': 'Noodles', 'imageUrl': 'https://images.unsplash.com/photo-1612927601601-6638404737ce?w=300&auto=format&fit=crop&q=80', 'sortOrder': 3},
        {'id': 'snacks', 'name': 'Snacks', 'imageUrl': 'https://images.unsplash.com/photo-1601050690597-df0568f70950?w=300&auto=format&fit=crop&q=80', 'sortOrder': 4},
        {'id': 'thalis', 'name': 'Thali', 'imageUrl': 'https://images.unsplash.com/photo-1626777552726-4a6b54c97e46?w=300&auto=format&fit=crop&q=80', 'sortOrder': 5},
      ];
      for (final cat in categories) {
        await shopRef.collection('categories').doc(cat['id'] as String).set({
          'name': cat['name'],
          'imageUrl': cat['imageUrl'],
          'sortOrder': cat['sortOrder'],
          'isActive': true,
        });
      }

      // Initial Menu Items
      final items = [
        {'id': 'veg_steam_momos', 'name': 'Veg Steam Momos', 'details': '8 Pieces', 'price': 50, 'cat': 'momos', 'isVeg': true, 'rec': true},
        {'id': 'veg_fried_momos', 'name': 'Veg Fried Momos', 'details': '8 Pieces', 'price': 60, 'cat': 'momos', 'isVeg': true, 'rec': false},
        {'id': 'paneer_steam_momos', 'name': 'Paneer Steam Momos', 'details': '8 Pieces', 'price': 60, 'cat': 'momos', 'isVeg': true, 'rec': true},
        {'id': 'paneer_fried_momos', 'name': 'Paneer Fried Momos', 'details': '8 Pieces', 'price': 70, 'cat': 'momos', 'isVeg': true, 'rec': false},
        {'id': 'chicken_kurkure_momos', 'name': 'Chicken Kurkure Momos', 'details': '6 Pieces', 'price': 99, 'cat': 'momos', 'isVeg': false, 'rec': true},
        {'id': 'hakka_noodles', 'name': 'Hakka Noodles', 'details': '1 Plate (500 gm)', 'price': 110, 'cat': 'snacks', 'isVeg': true, 'rec': true},
        {'id': 'samosa', 'name': 'Samosa', 'details': '1 Piece', 'price': 10, 'cat': 'snacks', 'isVeg': true, 'rec': false},
        {'id': 'kachori', 'name': 'Kachori', 'details': '1 Piece', 'price': 10, 'cat': 'snacks', 'isVeg': true, 'rec': false},
        {'id': 'pav_bhaji', 'name': 'Pav Bhaji', 'details': '2 Pav + Bhaji', 'price': 79, 'cat': 'snacks', 'isVeg': true, 'rec': false},
        {'id': 'chole_bhature', 'name': 'Chole Bhature', 'details': '2 Bhature + Chole', 'price': 129, 'cat': 'snacks', 'isVeg': true, 'rec': true},
        {'id': 'veg_thali', 'name': 'Veg Thali', 'details': 'Value Meal', 'price': 149, 'cat': 'thalis', 'isVeg': true, 'rec': false},
        {'id': 'veg_special_thali', 'name': 'Veg Special Thali', 'details': 'Special Meal', 'price': 249, 'cat': 'thalis', 'isVeg': true, 'rec': true},
      ];
      for (int i = 0; i < items.length; i++) {
        final item = items[i];
        final docId = item['id'] as String;
        await shopRef.collection('menuItems').doc(docId).set({
          'name': item['name'],
          'details': item['details'],
          'price': item['price'],
          'imageUrl': '',
          'categoryId': item['cat'],
          'isVeg': item['isVeg'],
          'isAvailable': true,
          'isRecommended': item['rec'],
          'sortOrder': i + 1,
        });
      }
    } else {
      // Document already exists: NEVER OVERWRITE ANY EXISTING FIELD!
      await _backfillMissingShopFields(
        shopRef,
        doc,
        defaultOrderMethod: 'whatsapp',
        defaultMinOrderAmount: 0,
        fallbackName: 'Nayan Shop',
      );
    }
  }

  // ─── Shop 3: Kivisha Shop ─────────────────────────────────────────────
  static Future<void> _seedKivishaShop(FirebaseFirestore firestore) async {
    const shopId = 'kivisha_shop';
    final shopRef = firestore.collection('shops').doc(shopId);
    final doc = await shopRef.get();

    if (!doc.exists) {
      debugPrint('🌱 SeedDataService: Creating initial document for $shopId');
      await shopRef.set({
        'name': 'Kivisha Shop',
        'description': 'Fresh Food, Snacks & Fast Food',
        'bannerUrl': 'https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=500',
        'contactNumber': '8295643910',
        'orderNumber': '8295643910',
        'openTime': '08:00',
        'closeTime': '23:30',
        'isClosedOverride': false,
        'isActive': true,
        'sortOrder': 4,
        'searchKeywords': ['kivisha', 'snacks', 'fast food', 'food'],
        'deliveryNote': 'Pickup from Gate 2',
        'orderMethod': 'whatsapp',
        'minimumOrderAmount': 0,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } else {
      // Document already exists: NEVER OVERWRITE ANY EXISTING FIELD!
      await _backfillMissingShopFields(
        shopRef,
        doc,
        defaultOrderMethod: 'whatsapp',
        defaultMinOrderAmount: 0,
        fallbackName: 'Kivisha Shop',
      );
    }
  }

  // ─── Shop 4: UP 16 Junction Fast Food ─────────────────────────────────
  static Future<void> _seedUP16Shop(FirebaseFirestore firestore) async {
    const shopId = 'up16_junction_fast_food';
    final shopRef = firestore.collection('shops').doc(shopId);
    final doc = await shopRef.get();

    if (!doc.exists) {
      debugPrint('🌱 SeedDataService: Creating initial document for $shopId');
      await shopRef.set({
        'name': 'UP 16 Junction Fast Food',
        'description': 'Rolls, Momos, Chinese Starters, Noodles, Fries, Biryani, Rice & Indian Breads',
        'bannerUrl': 'https://images.unsplash.com/photo-1555396273-367ea4eb4db5?w=500',
        'contactNumber': '8295643910',
        'orderNumber': '8295643910',
        'openTime': '08:00 AM',
        'closeTime': '11:30 PM',
        'isClosedOverride': false,
        'isActive': true,
        'sortOrder': 3,
        'searchKeywords': ['up16', 'up 16', 'junction', 'rolls', 'momos', 'noodles', 'biryani', 'chinese', 'fast food'],
        'deliveryNote': 'Vill. Dabra, Near Bennett University • Free Home Delivery',
        'orderMethod': 'both',
        'minimumOrderAmount': 0,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Categories
      final categories = [
        {'id': 'rolls', 'name': 'Rolls', 'imageUrl': 'https://images.unsplash.com/photo-1626700051175-6818013e1d4f?w=300&auto=format&fit=crop&q=80', 'sortOrder': 1},
        {'id': 'momos', 'name': 'Momos', 'imageUrl': 'https://images.unsplash.com/photo-1541696432-82c6da8ce7bf?w=300&auto=format&fit=crop&q=80', 'sortOrder': 2},
        {'id': 'chinese_starters', 'name': 'Chinese Starters', 'imageUrl': 'https://images.unsplash.com/photo-1563245372-f21724e3856d?w=300&auto=format&fit=crop&q=80', 'sortOrder': 3},
        {'id': 'noodles', 'name': 'Noodles', 'imageUrl': 'https://images.unsplash.com/photo-1612927601601-6638404737ce?w=300&auto=format&fit=crop&q=80', 'sortOrder': 4},
        {'id': 'fries_snacks', 'name': 'Fries & Snacks', 'imageUrl': 'https://images.unsplash.com/photo-1576107232684-1279f3908594?w=300&auto=format&fit=crop&q=80', 'sortOrder': 5},
        {'id': 'chicken_biryani', 'name': 'Chicken & Biryani', 'imageUrl': 'https://images.unsplash.com/photo-1633945274405-b6c8069047b0?w=300&auto=format&fit=crop&q=80', 'sortOrder': 6},
        {'id': 'rice', 'name': 'Rice', 'imageUrl': 'https://images.unsplash.com/photo-1603133872878-684f208fb84b?w=300&auto=format&fit=crop&q=80', 'sortOrder': 7},
        {'id': 'indian_breads', 'name': 'Indian Breads', 'imageUrl': 'https://images.unsplash.com/photo-1626777552726-4a6b54c97e46?w=300&auto=format&fit=crop&q=80', 'sortOrder': 8},
      ];
      for (final cat in categories) {
        await shopRef.collection('categories').doc(cat['id'] as String).set({
          'name': cat['name'],
          'imageUrl': cat['imageUrl'],
          'sortOrder': cat['sortOrder'],
          'displayOrder': cat['sortOrder'],
          'isActive': true,
          'shopId': shopId,
        });
      }

      // Initial Menu Items (60 unique entries)
      final items = [
        {'id': 'up16_veg_roll', 'name': 'Veg Roll', 'details': 'Soft roll filled with seasoned vegetables.', 'price': 60, 'cat': 'rolls', 'isVeg': true, 'rec': false},
        {'id': 'up16_veg_kathi_roll', 'name': 'Veg Kathi Roll', 'details': 'Kathi-style roll with a flavourful vegetable filling.', 'price': 70, 'cat': 'rolls', 'isVeg': true, 'rec': true},
        {'id': 'up16_spring_roll', 'name': 'Spring Roll', 'details': 'Crispy spring roll filled with seasoned vegetables.', 'price': 90, 'cat': 'rolls', 'isVeg': true, 'rec': true},
        {'id': 'up16_veg_noodles_roll', 'name': 'Veg Noodles Roll', 'details': 'Soft roll filled with flavourful noodles and vegetables.', 'price': 70, 'cat': 'rolls', 'isVeg': true, 'rec': false},
        {'id': 'up16_paneer_roll', 'name': 'Paneer Roll', 'details': 'Soft roll filled with seasoned paneer.', 'price': 90, 'cat': 'rolls', 'isVeg': true, 'rec': true},
        {'id': 'up16_paneer_noodles_roll', 'name': 'Paneer Noodles Roll', 'details': 'Roll filled with paneer and flavourful noodles.', 'price': 110, 'cat': 'rolls', 'isVeg': true, 'rec': false},
        {'id': 'up16_paneer_chilli_roll', 'name': 'Paneer Chilli Roll', 'details': 'Roll filled with spicy chilli paneer.', 'price': 120, 'cat': 'rolls', 'isVeg': true, 'rec': false},
        {'id': 'up16_single_egg_paneer_roll', 'name': 'Single Egg Paneer Roll', 'details': 'Roll with paneer and a single egg filling.', 'price': 100, 'cat': 'rolls', 'isVeg': false, 'rec': false},
        {'id': 'up16_double_egg_paneer_roll', 'name': 'Double Egg Paneer Roll', 'details': 'Roll with paneer and double egg filling.', 'price': 110, 'cat': 'rolls', 'isVeg': false, 'rec': false},
        {'id': 'up16_single_egg_roll', 'name': 'Single Egg Roll', 'details': 'Soft roll filled with a single egg.', 'price': 60, 'cat': 'rolls', 'isVeg': false, 'rec': false},
        {'id': 'up16_double_egg_roll', 'name': 'Double Egg Roll', 'details': 'Soft roll filled with double egg.', 'price': 70, 'cat': 'rolls', 'isVeg': false, 'rec': false},
        {'id': 'up16_triple_egg_roll', 'name': 'Triple Egg Roll', 'details': 'Soft roll filled with triple egg.', 'price': 80, 'cat': 'rolls', 'isVeg': false, 'rec': false},
        {'id': 'up16_chicken_roll', 'name': 'Chicken Roll', 'details': 'Soft roll filled with seasoned chicken.', 'price': 90, 'cat': 'rolls', 'isVeg': false, 'rec': true},
        {'id': 'up16_chicken_keema_roll', 'name': 'Chicken Keema Roll', 'details': 'Roll filled with flavourful chicken keema.', 'price': 110, 'cat': 'rolls', 'isVeg': false, 'rec': false},
        {'id': 'up16_single_egg_chicken_roll', 'name': 'Single Egg Chicken Roll', 'details': 'Roll with chicken and a single egg.', 'price': 100, 'cat': 'rolls', 'isVeg': false, 'rec': false},
        {'id': 'up16_double_egg_chicken_roll', 'name': 'Double Egg Chicken Roll', 'details': 'Roll with chicken and double egg.', 'price': 110, 'cat': 'rolls', 'isVeg': false, 'rec': false},
        {'id': 'up16_chilli_chicken_roll', 'name': 'Chilli Chicken Roll', 'details': 'Roll filled with spicy chilli chicken.', 'price': 120, 'cat': 'rolls', 'isVeg': false, 'rec': false},
        {'id': 'up16_chicken_tikka_roll', 'name': 'Chicken Tikka Roll', 'details': 'Roll filled with flavourful chicken tikka.', 'price': 120, 'cat': 'rolls', 'isVeg': false, 'rec': true},
        {'id': 'up16_chicken_kebab_roll', 'name': 'Chicken Kebab Roll', 'details': 'Roll filled with seasoned chicken kebab.', 'price': 100, 'cat': 'rolls', 'isVeg': false, 'rec': false},
        {'id': 'up16_single_egg_chicken_kebab_roll', 'name': 'Single Egg Chicken Kebab Roll', 'details': 'Roll with chicken kebab and a single egg.', 'price': 110, 'cat': 'rolls', 'isVeg': false, 'rec': false},
        {'id': 'up16_mutton_kebab_roll', 'name': 'Mutton Kebab Roll', 'details': 'Roll filled with seasoned mutton kebab.', 'price': 100, 'cat': 'rolls', 'isVeg': false, 'rec': false},
        {'id': 'up16_single_egg_mutton_kebab_roll', 'name': 'Single Egg Mutton Kebab Roll', 'details': 'Roll with mutton kebab and a single egg.', 'price': 110, 'cat': 'rolls', 'isVeg': false, 'rec': false},
        {'id': 'up16_veg_crispy_momos_half', 'name': 'Veg Crispy Momos (Half)', 'details': 'Crispy momos filled with seasoned vegetables.', 'price': 80, 'cat': 'momos', 'isVeg': true, 'rec': true},
        {'id': 'up16_veg_crispy_momos_full', 'name': 'Veg Crispy Momos (Full)', 'details': 'Crispy momos filled with seasoned vegetables.', 'price': 130, 'cat': 'momos', 'isVeg': true, 'rec': false},
        {'id': 'up16_paneer_crispy_momos_half', 'name': 'Paneer Crispy Momos (Half)', 'details': 'Crispy momos filled with flavourful paneer.', 'price': 90, 'cat': 'momos', 'isVeg': true, 'rec': true},
        {'id': 'up16_paneer_crispy_momos_full', 'name': 'Paneer Crispy Momos (Full)', 'details': 'Crispy momos filled with flavourful paneer.', 'price': 140, 'cat': 'momos', 'isVeg': true, 'rec': false},
        {'id': 'up16_chicken_crispy_momos_half', 'name': 'Chicken Crispy Momos (Half)', 'details': 'Crispy momos filled with seasoned chicken.', 'price': 90, 'cat': 'momos', 'isVeg': false, 'rec': true},
        {'id': 'up16_chicken_crispy_momos_full', 'name': 'Chicken Crispy Momos (Full)', 'details': 'Crispy momos filled with seasoned chicken.', 'price': 140, 'cat': 'momos', 'isVeg': false, 'rec': false},
        {'id': 'up16_veg_momos_half', 'name': 'Veg Momos (Half)', 'details': 'Soft momos with a seasoned vegetable filling.', 'price': 50, 'cat': 'momos', 'isVeg': true, 'rec': false},
        {'id': 'up16_veg_momos_full', 'name': 'Veg Momos (Full)', 'details': 'Soft momos with a seasoned vegetable filling.', 'price': 70, 'cat': 'momos', 'isVeg': true, 'rec': false},
        {'id': 'up16_veg_fried_momos_half', 'name': 'Veg Fried Momos (Half)', 'details': 'Fried momos with a savoury vegetable filling.', 'price': 60, 'cat': 'momos', 'isVeg': true, 'rec': false},
        {'id': 'up16_veg_fried_momos_full', 'name': 'Veg Fried Momos (Full)', 'details': 'Fried momos with a savoury vegetable filling.', 'price': 80, 'cat': 'momos', 'isVeg': true, 'rec': false},
        {'id': 'up16_paneer_momos_half', 'name': 'Paneer Momos (Half)', 'details': 'Soft momos filled with paneer.', 'price': 60, 'cat': 'momos', 'isVeg': true, 'rec': false},
        {'id': 'up16_paneer_momos_full', 'name': 'Paneer Momos (Full)', 'details': 'Soft momos filled with paneer.', 'price': 90, 'cat': 'momos', 'isVeg': true, 'rec': false},
        {'id': 'up16_paneer_fried_momos_half', 'name': 'Paneer Fried Momos (Half)', 'details': 'Fried momos filled with flavourful paneer.', 'price': 60, 'cat': 'momos', 'isVeg': true, 'rec': false},
        {'id': 'up16_paneer_fried_momos_full', 'name': 'Paneer Fried Momos (Full)', 'details': 'Fried momos filled with flavourful paneer.', 'price': 100, 'cat': 'momos', 'isVeg': true, 'rec': false},
        {'id': 'up16_chicken_fried_momos_half', 'name': 'Chicken Fried Momos (Half)', 'details': 'Fried momos filled with seasoned chicken.', 'price': 60, 'cat': 'momos', 'isVeg': false, 'rec': false},
        {'id': 'up16_chicken_fried_momos_full', 'name': 'Chicken Fried Momos (Full)', 'details': 'Fried momos filled with seasoned chicken.', 'price': 90, 'cat': 'momos', 'isVeg': false, 'rec': false},
        {'id': 'up16_chilli_chicken_momos', 'name': 'Chilli Chicken Momos', 'details': 'Momos prepared with spicy chilli chicken flavours.', 'price': 140, 'cat': 'momos', 'isVeg': false, 'rec': true},
        {'id': 'up16_veg_chilli_momos', 'name': 'Veg Chilli Momos', 'details': 'Vegetable momos prepared with spicy chilli flavours.', 'price': 130, 'cat': 'momos', 'isVeg': true, 'rec': false},
        {'id': 'up16_paneer_chilli_momos', 'name': 'Paneer Chilli Momos', 'details': 'Paneer momos prepared with spicy chilli flavours.', 'price': 140, 'cat': 'momos', 'isVeg': true, 'rec': false},
        {'id': 'up16_chilli_chicken_half', 'name': 'Chilli Chicken (Dry/Gravy) (Half)', 'details': 'Spicy chilli chicken available in dry or gravy style.', 'price': 160, 'cat': 'chinese_starters', 'isVeg': false, 'rec': true},
        {'id': 'up16_chilli_chicken_full', 'name': 'Chilli Chicken (Dry/Gravy) (Full)', 'details': 'Spicy chilli chicken available in dry or gravy style.', 'price': 260, 'cat': 'chinese_starters', 'isVeg': false, 'rec': false},
        {'id': 'up16_chicken_manchurian_half', 'name': 'Chicken Manchurian (Dry/Gravy) (Half)', 'details': 'Chicken Manchurian available in dry or gravy style.', 'price': 160, 'cat': 'chinese_starters', 'isVeg': false, 'rec': false},
        {'id': 'up16_chicken_manchurian_full', 'name': 'Chicken Manchurian (Dry/Gravy) (Full)', 'details': 'Chicken Manchurian available in dry or gravy style.', 'price': 260, 'cat': 'chinese_starters', 'isVeg': false, 'rec': false},
        {'id': 'up16_paneer_manchurian_half', 'name': 'Paneer Manchurian (Dry/Gravy) (Half)', 'details': 'Paneer Manchurian available in dry or gravy style.', 'price': 160, 'cat': 'chinese_starters', 'isVeg': true, 'rec': false},
        {'id': 'up16_paneer_manchurian_full', 'name': 'Paneer Manchurian (Dry/Gravy) (Full)', 'details': 'Paneer Manchurian available in dry or gravy style.', 'price': 270, 'cat': 'chinese_starters', 'isVeg': true, 'rec': false},
        {'id': 'up16_garlic_chicken_half', 'name': 'Garlic Chicken (Dry/Gravy) (Half)', 'details': 'Garlic-flavoured chicken available in dry or gravy style.', 'price': 160, 'cat': 'chinese_starters', 'isVeg': false, 'rec': false},
        {'id': 'up16_garlic_chicken_full', 'name': 'Garlic Chicken (Dry/Gravy) (Full)', 'details': 'Garlic-flavoured chicken available in dry or gravy style.', 'price': 270, 'cat': 'chinese_starters', 'isVeg': false, 'rec': false},
        {'id': 'up16_chilli_potato_half', 'name': 'Chilli Potato (Half)', 'details': 'Crispy potato tossed in a spicy chilli preparation.', 'price': 70, 'cat': 'chinese_starters', 'isVeg': true, 'rec': true},
        {'id': 'up16_chilli_potato_full', 'name': 'Chilli Potato (Full)', 'details': 'Crispy potato tossed in a spicy chilli preparation.', 'price': 110, 'cat': 'chinese_starters', 'isVeg': true, 'rec': false},
        {'id': 'up16_honey_chilli_potato_half', 'name': 'Honey Chilli Potato (Half)', 'details': 'Crispy potato with sweet and spicy flavours.', 'price': 70, 'cat': 'chinese_starters', 'isVeg': true, 'rec': true},
        {'id': 'up16_honey_chilli_potato_full', 'name': 'Honey Chilli Potato (Full)', 'details': 'Crispy potato with sweet and spicy flavours.', 'price': 110, 'cat': 'chinese_starters', 'isVeg': true, 'rec': false},
        {'id': 'up16_chilli_paneer_half', 'name': 'Chilli Paneer (Dry/Gravy) (Half)', 'details': 'Spicy chilli paneer available in dry or gravy style.', 'price': 160, 'cat': 'chinese_starters', 'isVeg': true, 'rec': true},
        {'id': 'up16_chilli_paneer_full', 'name': 'Chilli Paneer (Dry/Gravy) (Full)', 'details': 'Spicy chilli paneer available in dry or gravy style.', 'price': 260, 'cat': 'chinese_starters', 'isVeg': true, 'rec': false},
        {'id': 'up16_veg_noodles_half', 'name': 'Veg Noodles (Half)', 'details': 'Stir-fried noodles prepared with vegetables.', 'price': 70, 'cat': 'noodles', 'isVeg': true, 'rec': false},
        {'id': 'up16_veg_noodles_full', 'name': 'Veg Noodles (Full)', 'details': 'Stir-fried noodles prepared with vegetables.', 'price': 100, 'cat': 'noodles', 'isVeg': true, 'rec': false},
        {'id': 'up16_paneer_noodles_half', 'name': 'Paneer Noodles (Half)', 'details': 'Stir-fried noodles with flavourful paneer.', 'price': 90, 'cat': 'noodles', 'isVeg': true, 'rec': false},
        {'id': 'up16_paneer_noodles_full', 'name': 'Paneer Noodles (Full)', 'details': 'Stir-fried noodles with flavourful paneer.', 'price': 130, 'cat': 'noodles', 'isVeg': true, 'rec': false},
        {'id': 'up16_chicken_noodles_half', 'name': 'Chicken Noodles (Half)', 'details': 'Stir-fried noodles prepared with chicken.', 'price': 90, 'cat': 'noodles', 'isVeg': false, 'rec': true},
        {'id': 'up16_chicken_noodles_full', 'name': 'Chicken Noodles (Full)', 'details': 'Stir-fried noodles prepared with chicken.', 'price': 130, 'cat': 'noodles', 'isVeg': false, 'rec': false},
        {'id': 'up16_chicken_mix_noodles_half', 'name': 'Chicken Mix Noodles (Half)', 'details': 'Flavourful noodles prepared with a chicken mix.', 'price': 100, 'cat': 'noodles', 'isVeg': false, 'rec': false},
        {'id': 'up16_chicken_mix_noodles_full', 'name': 'Chicken Mix Noodles (Full)', 'details': 'Flavourful noodles prepared with a chicken mix.', 'price': 140, 'cat': 'noodles', 'isVeg': false, 'rec': false},
        {'id': 'up16_egg_noodles_half', 'name': 'Egg Noodles (Half)', 'details': 'Stir-fried noodles prepared with egg.', 'price': 80, 'cat': 'noodles', 'isVeg': false, 'rec': false},
        {'id': 'up16_egg_noodles_full', 'name': 'Egg Noodles (Full)', 'details': 'Stir-fried noodles prepared with egg.', 'price': 120, 'cat': 'noodles', 'isVeg': false, 'rec': false},
        {'id': 'up16_chilli_garlic_noodles_half', 'name': 'Chilli Garlic Noodles (Half)', 'details': 'Noodles with chilli and garlic flavours.', 'price': 80, 'cat': 'noodles', 'isVeg': true, 'rec': false},
        {'id': 'up16_chilli_garlic_noodles_full', 'name': 'Chilli Garlic Noodles (Full)', 'details': 'Noodles with chilli and garlic flavours.', 'price': 130, 'cat': 'noodles', 'isVeg': true, 'rec': false},
        {'id': 'up16_hakka_noodles_half', 'name': 'Hakka Noodles (Half)', 'details': 'Flavourful stir-fried Hakka-style noodles.', 'price': 90, 'cat': 'noodles', 'isVeg': true, 'rec': true},
        {'id': 'up16_hakka_noodles_full', 'name': 'Hakka Noodles (Full)', 'details': 'Flavourful stir-fried Hakka-style noodles.', 'price': 130, 'cat': 'noodles', 'isVeg': true, 'rec': false},
        {'id': 'up16_singapore_noodles_half', 'name': 'Singapore Noodles (Half)', 'details': 'Flavourful noodles prepared in Singapore-style.', 'price': 90, 'cat': 'noodles', 'isVeg': true, 'rec': false},
        {'id': 'up16_singapore_noodles_full', 'name': 'Singapore Noodles (Full)', 'details': 'Flavourful noodles prepared in Singapore-style.', 'price': 130, 'cat': 'noodles', 'isVeg': true, 'rec': false},
        {'id': 'up16_french_fries_half', 'name': 'French Fries (Half)', 'details': 'Crispy fried potato strips.', 'price': 70, 'cat': 'fries_snacks', 'isVeg': true, 'rec': true},
        {'id': 'up16_french_fries_full', 'name': 'French Fries (Full)', 'details': 'Crispy fried potato strips.', 'price': 110, 'cat': 'fries_snacks', 'isVeg': true, 'rec': false},
        {'id': 'up16_chicken_biryani_half', 'name': 'Chicken Biryani (Half)', 'details': 'Aromatic rice prepared with seasoned chicken.', 'price': 100, 'cat': 'chicken_biryani', 'isVeg': false, 'rec': true},
        {'id': 'up16_chicken_biryani_full', 'name': 'Chicken Biryani (Full)', 'details': 'Aromatic rice prepared with seasoned chicken.', 'price': 160, 'cat': 'chicken_biryani', 'isVeg': false, 'rec': false},
        {'id': 'up16_hyderabadi_chicken_biryani_half', 'name': 'Hyderabadi Chicken Biryani (Half)', 'details': 'Hyderabadi-style biryani with aromatic spices and chicken.', 'price': 100, 'cat': 'chicken_biryani', 'isVeg': false, 'rec': true},
        {'id': 'up16_hyderabadi_chicken_biryani_full', 'name': 'Hyderabadi Chicken Biryani (Full)', 'details': 'Hyderabadi-style biryani with aromatic spices and chicken.', 'price': 160, 'cat': 'chicken_biryani', 'isVeg': false, 'rec': false},
        {'id': 'up16_chicken_korma_half', 'name': 'Chicken Korma (Half)', 'details': 'Rich and flavourful chicken curry.', 'price': 150, 'cat': 'chicken_biryani', 'isVeg': false, 'rec': false},
        {'id': 'up16_chicken_korma_full', 'name': 'Chicken Korma (Full)', 'details': 'Rich and flavourful chicken curry.', 'price': 280, 'cat': 'chicken_biryani', 'isVeg': false, 'rec': false},
        {'id': 'up16_chicken_fry_half', 'name': 'Chicken Fry (Half)', 'details': 'Crispy and flavourful fried chicken.', 'price': 230, 'cat': 'chicken_biryani', 'isVeg': false, 'rec': true},
        {'id': 'up16_chicken_fry_full', 'name': 'Chicken Fry (Full)', 'details': 'Crispy and flavourful fried chicken.', 'price': 380, 'cat': 'chicken_biryani', 'isVeg': false, 'rec': false},
        {'id': 'up16_veg_fried_rice_half', 'name': 'Veg Fried Rice (Half)', 'details': 'Stir-fried rice prepared with vegetables.', 'price': 70, 'cat': 'rice', 'isVeg': true, 'rec': false},
        {'id': 'up16_veg_fried_rice_full', 'name': 'Veg Fried Rice (Full)', 'details': 'Stir-fried rice prepared with vegetables.', 'price': 100, 'cat': 'rice', 'isVeg': true, 'rec': false},
        {'id': 'up16_paneer_fried_rice_half', 'name': 'Paneer Fried Rice (Half)', 'details': 'Fried rice combined with flavourful paneer.', 'price': 80, 'cat': 'rice', 'isVeg': true, 'rec': false},
        {'id': 'up16_paneer_fried_rice_full', 'name': 'Paneer Fried Rice (Full)', 'details': 'Fried rice combined with flavourful paneer.', 'price': 130, 'cat': 'rice', 'isVeg': true, 'rec': false},
        {'id': 'up16_veg_chilli_garlic_fried_rice_half', 'name': 'Veg Chilli Garlic Fried Rice (Half)', 'details': 'Vegetable fried rice with chilli and garlic flavours.', 'price': 80, 'cat': 'rice', 'isVeg': true, 'rec': false},
        {'id': 'up16_veg_chilli_garlic_fried_rice_full', 'name': 'Veg Chilli Garlic Fried Rice (Full)', 'details': 'Vegetable fried rice with chilli and garlic flavours.', 'price': 130, 'cat': 'rice', 'isVeg': true, 'rec': false},
        {'id': 'up16_chicken_fried_rice_half', 'name': 'Chicken Fried Rice (Half)', 'details': 'Stir-fried rice prepared with chicken.', 'price': 80, 'cat': 'rice', 'isVeg': false, 'rec': true},
        {'id': 'up16_chicken_fried_rice_full', 'name': 'Chicken Fried Rice (Full)', 'details': 'Stir-fried rice prepared with chicken.', 'price': 140, 'cat': 'rice', 'isVeg': false, 'rec': false},
        {'id': 'up16_chicken_mix_fried_rice_half', 'name': 'Chicken Mix Fried Rice (Half)', 'details': 'Fried rice prepared with a chicken mix.', 'price': 90, 'cat': 'rice', 'isVeg': false, 'rec': false},
        {'id': 'up16_chicken_mix_fried_rice_full', 'name': 'Chicken Mix Fried Rice (Full)', 'details': 'Fried rice prepared with a chicken mix.', 'price': 150, 'cat': 'rice', 'isVeg': false, 'rec': false},
        {'id': 'up16_egg_fried_rice_half', 'name': 'Egg Fried Rice (Half)', 'details': 'Stir-fried rice prepared with egg.', 'price': 80, 'cat': 'rice', 'isVeg': false, 'rec': false},
        {'id': 'up16_egg_fried_rice_full', 'name': 'Egg Fried Rice (Full)', 'details': 'Stir-fried rice prepared with egg.', 'price': 130, 'cat': 'rice', 'isVeg': false, 'rec': false},
        {'id': 'up16_rumali_roti', 'name': 'Rumali Roti', 'details': 'Thin and soft Indian flatbread.', 'price': 20, 'cat': 'indian_breads', 'isVeg': true, 'rec': false},
      ];
      for (int i = 0; i < items.length; i++) {
        final item = items[i];
        final docId = item['id'] as String;
        await shopRef.collection('menuItems').doc(docId).set({
          'name': item['name'],
          'details': item['details'],
          'price': item['price'],
          'imageUrl': '',
          'categoryId': item['cat'],
          'isVeg': item['isVeg'],
          'isAvailable': true,
          'isRecommended': item['rec'],
          'sortOrder': i + 1,
        });
      }
    } else {
      // Document already exists: NEVER OVERWRITE ANY EXISTING FIELD!
      await _backfillMissingShopFields(
        shopRef,
        doc,
        defaultOrderMethod: 'both',
        defaultMinOrderAmount: 0,
        fallbackName: 'UP 16 Junction Fast Food',
      );
    }
  }

  /// Ensures that any missing required schema fields in an existing shop are populated
  /// with safe defaults, without EVER overwriting or modifying any existing values.
  static Future<void> _backfillMissingShopFields(
    DocumentReference shopRef,
    DocumentSnapshot shopDoc, {
    required String defaultOrderMethod,
    required int defaultMinOrderAmount,
    required String fallbackName,
  }) async {
    final data = (shopDoc.data() as Map<String, dynamic>?) ?? {};
    final Map<String, dynamic> missingFieldsPatch = {};

    // Only add a field if the key is completely absent or null in Firestore
    if (!data.containsKey('orderMethod') || data['orderMethod'] == null) {
      missingFieldsPatch['orderMethod'] = defaultOrderMethod;
    }
    if (!data.containsKey('minimumOrderAmount') || data['minimumOrderAmount'] == null) {
      missingFieldsPatch['minimumOrderAmount'] = defaultMinOrderAmount;
    }
    if (!data.containsKey('isClosedOverride') || data['isClosedOverride'] == null) {
      missingFieldsPatch['isClosedOverride'] = false;
    }
    if (!data.containsKey('isActive') || data['isActive'] == null) {
      missingFieldsPatch['isActive'] = true;
    }
    if (!data.containsKey('name') || (data['name'] as String?)?.trim().isEmpty == true) {
      missingFieldsPatch['name'] = fallbackName;
    }

    if (missingFieldsPatch.isNotEmpty) {
      debugPrint('ℹ️ SeedDataService: Backfilling missing keys for ${shopDoc.id}: $missingFieldsPatch');
      await shopRef.set(missingFieldsPatch, SetOptions(merge: true));
    }
  }
}
