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
    print('🔥 Checking Firestore Database Seeding Condition...');

    final rajatDoc = await firestore.collection('shops').doc('rajat_shop').get();
    final nayanDoc = await firestore.collection('shops').doc('nayan_shop').get();

    // If both shops already exist in Firestore, DO NOT overwrite anything!
    if (rajatDoc.exists && nayanDoc.exists) {
      print('✅ Firestore shops already exist. Skipping seed to protect manual edits.');
      return;
    }

    // ─── Shop 1: Rajat Shop (Seed ONLY if doc does not exist) ────────
    if (!rajatDoc.exists) {
      print('🌱 Seeding Rajat Shop into Firestore...');
      final rajatRef = firestore.collection('shops').doc('rajat_shop');
      await rajatRef.set({
        'name': 'Rajat Shop',
        'description': 'Chinese, Fast Food, Snacks & Special Thalis',
        'imageUrl': 'https://images.unsplash.com/photo-1555396273-367ea4eb4db5?w=500',
        'whatsappNumber': '8295643910',
        'phoneNumber': '8295643910',
        'openTime': '08:00',
        'closeTime': '23:30',
        'isActive': true,
        'sortOrder': 1,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      final rajatMomosCat = rajatRef.collection('categories').doc('momos');
      await rajatMomosCat.set({'name': 'Momos', 'sortOrder': 1});

      final rajatSnacksCat = rajatRef.collection('categories').doc('snacks');
      await rajatSnacksCat.set({'name': 'Snacks & Fast Food', 'sortOrder': 2});

      final rajatThaliCat = rajatRef.collection('categories').doc('thalis');
      await rajatThaliCat.set({'name': 'Thalis & Meals', 'sortOrder': 3});

      final rajatItems = [
        {'id': 'veg_steam_momos', 'name': 'Veg Steam Momos', 'price': 60.0, 'cat': 'momos', 'isVeg': true},
        {'id': 'veg_fried_momos', 'name': 'Veg Fried Momos', 'price': 70.0, 'cat': 'momos', 'isVeg': true},
        {'id': 'paneer_steam_momos', 'name': 'Paneer Steam Momos', 'price': 70.0, 'cat': 'momos', 'isVeg': true},
        {'id': 'paneer_fried_momos', 'name': 'Paneer Fried Momos', 'price': 80.0, 'cat': 'momos', 'isVeg': true},
        {'id': 'hakka_noodles', 'name': 'Hakka Noodles', 'price': 120.0, 'cat': 'snacks', 'isVeg': true},
        {'id': 'samosa', 'name': 'Samosa', 'price': 15.0, 'cat': 'snacks', 'isVeg': true},
        {'id': 'kachori', 'name': 'Kachori', 'price': 15.0, 'cat': 'snacks', 'isVeg': true},
        {'id': 'pav_bhaji', 'name': 'Pav Bhaji', 'price': 99.0, 'cat': 'snacks', 'isVeg': true},
        {'id': 'chole_bhature', 'name': 'Chole Bhature', 'price': 149.0, 'cat': 'snacks', 'isVeg': true},
        {'id': 'veg_thali', 'name': 'Veg Thali', 'price': 199.0, 'cat': 'thalis', 'isVeg': true},
        {'id': 'veg_special_thali', 'name': 'Veg Special Thali', 'price': 299.0, 'cat': 'thalis', 'isVeg': true},
      ];

      for (int i = 0; i < rajatItems.length; i++) {
        final item = rajatItems[i];
        final docId = item['id'] as String;
        await rajatRef.collection('menuItems').doc(docId).set({
          'name': item['name'],
          'description': 'Delicious ${item['name']} prepared fresh at Rajat Shop.',
          'price': item['price'],
          'imageUrl': '',
          'categoryId': item['cat'],
          'isVeg': item['isVeg'],
          'isAvailable': true,
          'sortOrder': i + 1,
        });
      }

      await _cleanupOldRandomDocs(rajatRef);
    }

    // ─── Shop 2: Nayan Shop (Seed ONLY if doc does not exist) ────────
    if (!nayanDoc.exists) {
      print('🌱 Seeding Nayan Shop into Firestore...');
      final nayanRef = firestore.collection('shops').doc('nayan_shop');
      await nayanRef.set({
        'name': 'Nayan Shop',
        'description': 'Momos, Chinese, Fast Food & Value Thalis',
        'imageUrl': 'https://images.unsplash.com/photo-1585937421612-70a008356fbe?w=500',
        'whatsappNumber': '8875344034',
        'phoneNumber': '8875344034',
        'openTime': '08:00',
        'closeTime': '23:30',
        'isActive': true,
        'sortOrder': 2,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      final nayanMomosCat = nayanRef.collection('categories').doc('momos');
      await nayanMomosCat.set({'name': 'Momos', 'sortOrder': 1});

      final nayanSnacksCat = nayanRef.collection('categories').doc('snacks');
      await nayanSnacksCat.set({'name': 'Snacks & Fast Food', 'sortOrder': 2});

      final nayanThaliCat = nayanRef.collection('categories').doc('thalis');
      await nayanThaliCat.set({'name': 'Thalis & Meals', 'sortOrder': 3});

      final nayanItems = [
        {'id': 'veg_steam_momos', 'name': 'Veg Steam Momos', 'price': 50.0, 'cat': 'momos', 'isVeg': true},
        {'id': 'veg_fried_momos', 'name': 'Veg Fried Momos', 'price': 60.0, 'cat': 'momos', 'isVeg': true},
        {'id': 'paneer_steam_momos', 'name': 'Paneer Steam Momos', 'price': 60.0, 'cat': 'momos', 'isVeg': true},
        {'id': 'paneer_fried_momos', 'name': 'Paneer Fried Momos', 'price': 70.0, 'cat': 'momos', 'isVeg': true},
        {'id': 'chicken_kurkure_momos', 'name': 'Chicken Kurkure Momos', 'price': 99.0, 'cat': 'momos', 'isVeg': false},
        {'id': 'hakka_noodles', 'name': 'Hakka Noodles', 'price': 110.0, 'cat': 'snacks', 'isVeg': true},
        {'id': 'samosa', 'name': 'Samosa', 'price': 10.0, 'cat': 'snacks', 'isVeg': true},
        {'id': 'kachori', 'name': 'Kachori', 'price': 10.0, 'cat': 'snacks', 'isVeg': true},
        {'id': 'pav_bhaji', 'name': 'Pav Bhaji', 'price': 79.0, 'cat': 'snacks', 'isVeg': true},
        {'id': 'chole_bhature', 'name': 'Chole Bhature', 'price': 129.0, 'cat': 'snacks', 'isVeg': true},
        {'id': 'veg_thali', 'name': 'Veg Thali', 'price': 149.0, 'cat': 'thalis', 'isVeg': true},
        {'id': 'veg_special_thali', 'name': 'Veg Special Thali', 'price': 249.0, 'cat': 'thalis', 'isVeg': true},
      ];

      for (int i = 0; i < nayanItems.length; i++) {
        final item = nayanItems[i];
        final docId = item['id'] as String;
        await nayanRef.collection('menuItems').doc(docId).set({
          'name': item['name'],
          'description': 'Fresh ${item['name']} prepared hot at Nayan Shop.',
          'price': item['price'],
          'imageUrl': '',
          'categoryId': item['cat'],
          'isVeg': item['isVeg'],
          'isAvailable': true,
          'sortOrder': i + 1,
        });
      }

      await _cleanupOldRandomDocs(nayanRef);
    }

    print('✅ SUCCESS: Missing shop seeding completed!');
  }

  /// Removes any old auto-generated random ID documents from menuItems subcollection.
  static Future<void> _cleanupOldRandomDocs(DocumentReference shopRef) async {
    try {
      final snapshot = await shopRef.collection('menuItems').get();
      for (final doc in snapshot.docs) {
        if (!_validCustomIds.contains(doc.id)) {
          await doc.reference.delete();
          print('🗑️ Deleted old auto-generated document: ${doc.id}');
        }
      }
    } catch (e) {
      print('Note during doc cleanup: $e');
    }
  }
}
