// BU Gate2Eat — Services
// Seed service for populating shop & menu data in Firestore ONLY when missing

import 'package:cloud_firestore/cloud_firestore.dart';

/// Populates initial shop data into Firestore using custom document IDs.
/// NEVER overwrites existing shops or manually edited prices.
class SeedDataService {
  static const Set<String> _validCustomIds = {
    'veg_steam_momos',
    'veg_fried_momos',
    'paneer_steam_momos',
    'paneer_fried_momos',
    'chicken_kurkure_momos',
    'hakka_noodles',
    'samosa',
    'kachori',
    'pav_bhaji',
    'chole_bhature',
    'veg_thali',
    'veg_special_thali',
  };

  static Future<void> seedInitialData() async {
    final firestore = FirebaseFirestore.instance;

    // Ensure categories subcollections exist with full metadata
    await _ensureCategories('rajat_shop', [
      {'id': 'momos', 'name': 'Momos', 'imageUrl': 'https://images.unsplash.com/photo-1541696432-82c6da8ce7bf?w=300&auto=format&fit=crop&q=80', 'sortOrder': 1},
      {'id': 'pizzas', 'name': 'Pizzas', 'imageUrl': 'https://images.unsplash.com/photo-1513104890138-7c749659a591?w=300&auto=format&fit=crop&q=80', 'sortOrder': 2},
      {'id': 'burgers', 'name': 'Burgers', 'imageUrl': 'https://images.unsplash.com/photo-1568901346375-23c9450c58cd?w=300&auto=format&fit=crop&q=80', 'sortOrder': 3},
      {'id': 'biryani', 'name': 'Biryani', 'imageUrl': 'https://images.unsplash.com/photo-1633945274405-b6c8069047b0?w=300&auto=format&fit=crop&q=80', 'sortOrder': 4},
      {'id': 'thalis', 'name': 'Thali', 'imageUrl': 'https://images.unsplash.com/photo-1626777552726-4a6b54c97e46?w=300&auto=format&fit=crop&q=80', 'sortOrder': 5},
      {'id': 'snacks', 'name': 'Snacks', 'imageUrl': 'https://images.unsplash.com/photo-1601050690597-df0568f70950?w=300&auto=format&fit=crop&q=80', 'sortOrder': 6},
    ]);

    await _ensureCategories('nayan_shop', [
      {'id': 'momos', 'name': 'Momos', 'imageUrl': 'https://images.unsplash.com/photo-1541696432-82c6da8ce7bf?w=300&auto=format&fit=crop&q=80', 'sortOrder': 1},
      {'id': 'rolls', 'name': 'Rolls', 'imageUrl': 'https://images.unsplash.com/photo-1626700051175-6818013e1d4f?w=300&auto=format&fit=crop&q=80', 'sortOrder': 2},
      {'id': 'noodles', 'name': 'Noodles', 'imageUrl': 'https://images.unsplash.com/photo-1612927601601-6638404737ce?w=300&auto=format&fit=crop&q=80', 'sortOrder': 3},
      {'id': 'snacks', 'name': 'Snacks', 'imageUrl': 'https://images.unsplash.com/photo-1601050690597-df0568f70950?w=300&auto=format&fit=crop&q=80', 'sortOrder': 4},
      {'id': 'thalis', 'name': 'Thali', 'imageUrl': 'https://images.unsplash.com/photo-1626777552726-4a6b54c97e46?w=300&auto=format&fit=crop&q=80', 'sortOrder': 5},
    ]);

    final rajatDoc = await firestore.collection('shops').doc('rajat_shop').get();
    final nayanDoc = await firestore.collection('shops').doc('nayan_shop').get();

    // If both shops already exist in Firestore, DO NOT overwrite shop/menu details!
    if (rajatDoc.exists && nayanDoc.exists) {
      return;
    }

    // ─── Shop 1: Rajat Shop (Seed ONLY if doc does not exist) ────────
    if (!rajatDoc.exists) {
      final rajatRef = firestore.collection('shops').doc('rajat_shop');
      await rajatRef.set({
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
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      final rajatCategories = [
        {'id': 'momos', 'name': 'Momos', 'imageUrl': 'https://images.unsplash.com/photo-1541696432-82c6da8ce7bf?w=300&auto=format&fit=crop&q=80', 'sortOrder': 1},
        {'id': 'pizzas', 'name': 'Pizzas', 'imageUrl': 'https://images.unsplash.com/photo-1513104890138-7c749659a591?w=300&auto=format&fit=crop&q=80', 'sortOrder': 2},
        {'id': 'burgers', 'name': 'Burgers', 'imageUrl': 'https://images.unsplash.com/photo-1568901346375-23c9450c58cd?w=300&auto=format&fit=crop&q=80', 'sortOrder': 3},
        {'id': 'biryani', 'name': 'Biryani', 'imageUrl': 'https://images.unsplash.com/photo-1633945274405-b6c8069047b0?w=300&auto=format&fit=crop&q=80', 'sortOrder': 4},
        {'id': 'thalis', 'name': 'Thali', 'imageUrl': 'https://images.unsplash.com/photo-1626777552726-4a6b54c97e46?w=300&auto=format&fit=crop&q=80', 'sortOrder': 5},
        {'id': 'snacks', 'name': 'Snacks', 'imageUrl': 'https://images.unsplash.com/photo-1601050690597-df0568f70950?w=300&auto=format&fit=crop&q=80', 'sortOrder': 6},
      ];

      for (final cat in rajatCategories) {
        await rajatRef.collection('categories').doc(cat['id'] as String).set({
          'name': cat['name'],
          'imageUrl': cat['imageUrl'],
          'sortOrder': cat['sortOrder'],
          'isActive': true,
        });
      }

      final rajatItems = [
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

      for (int i = 0; i < rajatItems.length; i++) {
        final item = rajatItems[i];
        final docId = item['id'] as String;
        await rajatRef.collection('menuItems').doc(docId).set({
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

      await _cleanupOldRandomDocs(rajatRef);
    }

    // ─── Shop 2: Nayan Shop (Seed ONLY if doc does not exist) ────────
    if (!nayanDoc.exists) {
      final nayanRef = firestore.collection('shops').doc('nayan_shop');
      await nayanRef.set({
        'name': 'Nayan Shop',
        'description': 'Momos, Chinese, Fast Food & Value Thalis',
        'bannerUrl': 'https://images.unsplash.com/photo-1585937421612-70a008356fbe?w=500',
        'contactNumber': '8875344034',
        'orderNumber': '8875344034',
        'openTime': '08:00',
        'closeTime': '23:30',
        'isClosedOverride': false,
        'isActive': true,
        'sortOrder': 2,
        'searchKeywords': ['momos', 'chinese', 'fast food', 'nayan', 'chicken'],
        'deliveryNote': 'Pickup from Gate 2',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      final nayanCategories = [
        {'id': 'momos', 'name': 'Momos', 'imageUrl': 'https://images.unsplash.com/photo-1541696432-82c6da8ce7bf?w=300&auto=format&fit=crop&q=80', 'sortOrder': 1},
        {'id': 'rolls', 'name': 'Rolls', 'imageUrl': 'https://images.unsplash.com/photo-1626700051175-6818013e1d4f?w=300&auto=format&fit=crop&q=80', 'sortOrder': 2},
        {'id': 'noodles', 'name': 'Noodles', 'imageUrl': 'https://images.unsplash.com/photo-1612927601601-6638404737ce?w=300&auto=format&fit=crop&q=80', 'sortOrder': 3},
        {'id': 'snacks', 'name': 'Snacks', 'imageUrl': 'https://images.unsplash.com/photo-1601050690597-df0568f70950?w=300&auto=format&fit=crop&q=80', 'sortOrder': 4},
        {'id': 'thalis', 'name': 'Thali', 'imageUrl': 'https://images.unsplash.com/photo-1626777552726-4a6b54c97e46?w=300&auto=format&fit=crop&q=80', 'sortOrder': 5},
      ];

      for (final cat in nayanCategories) {
        await nayanRef.collection('categories').doc(cat['id'] as String).set({
          'name': cat['name'],
          'imageUrl': cat['imageUrl'],
          'sortOrder': cat['sortOrder'],
          'isActive': true,
        });
      }

      final nayanItems = [
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

      for (int i = 0; i < nayanItems.length; i++) {
        final item = nayanItems[i];
        final docId = item['id'] as String;
        await nayanRef.collection('menuItems').doc(docId).set({
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

      await _cleanupOldRandomDocs(nayanRef);
    }
  }

  /// Removes any old auto-generated random ID documents from menuItems subcollection.
  static Future<void> _cleanupOldRandomDocs(DocumentReference shopRef) async {
    try {
      final snapshot = await shopRef.collection('menuItems').get();
      for (final doc in snapshot.docs) {
        if (!_validCustomIds.contains(doc.id)) {
          await doc.reference.delete();
        }
      }
    } catch (_) {}
  }

  /// Ensures categories subcollection is populated with complete metadata.
  static Future<void> _ensureCategories(String shopId, List<Map<String, dynamic>> categories) async {
    try {
      final firestore = FirebaseFirestore.instance;
      final shopRef = firestore.collection('shops').doc(shopId);
      final snapshot = await shopRef.collection('categories').get();

      if (snapshot.docs.isEmpty) {
        for (final cat in categories) {
          await shopRef.collection('categories').doc(cat['id'] as String).set({
            'name': cat['name'],
            'imageUrl': cat['imageUrl'],
            'sortOrder': cat['sortOrder'],
            'isActive': true,
          });
        }
      } else {
        for (final cat in categories) {
          final docRef = shopRef.collection('categories').doc(cat['id'] as String);
          final doc = await docRef.get();
          if (!doc.exists) {
            await docRef.set({
              'name': cat['name'],
              'imageUrl': cat['imageUrl'],
              'sortOrder': cat['sortOrder'],
              'isActive': true,
            });
          } else {
            final data = doc.data();
            if (data != null && ((data['imageUrl'] as String?)?.isEmpty == true || data['isActive'] == null)) {
              await docRef.set({
                'imageUrl': (data['imageUrl'] as String?)?.isNotEmpty == true ? data['imageUrl'] : cat['imageUrl'],
                'isActive': data['isActive'] ?? true,
                'sortOrder': data['sortOrder'] ?? cat['sortOrder'],
              }, SetOptions(merge: true),);
            }
          }
        }
      }
    } catch (_) {}
  }
}

