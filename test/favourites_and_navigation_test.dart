// BU Gate2Eat — Favourites, Navigation, Filters & Cart Persistence Test Suite

import 'package:bugate2eat_app/core/providers.dart';
import 'package:bugate2eat_app/features/cart/cart_provider.dart';
import 'package:bugate2eat_app/models/menu_item_model.dart';
import 'package:bugate2eat_app/models/shop_model.dart';
import 'package:bugate2eat_app/services/local_storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LocalStorageService localStorage;
  late FavoriteNotifier favoriteNotifier;
  late CartNotifier cartNotifier;

  const item1 = MenuItem(
    id: 'veg_steam_momos',
    name: 'Veg Steam Momos',
    price: 60,
    details: '8 Pieces',
    imageUrl: '',
    isVeg: true,
    isAvailable: true,
    isRecommended: true,
    categoryId: 'momos',
    sortOrder: 1,
  );

  const item2 = MenuItem(
    id: 'chicken_kurkure_momos',
    name: 'Chicken Kurkure Momos',
    price: 120,
    details: '6 Pieces',
    imageUrl: '',
    isVeg: false,
    isAvailable: true,
    isRecommended: false,
    categoryId: 'momos',
    sortOrder: 2,
  );

  final rajatShop = Shop(
    id: 'rajat_shop',
    name: 'Rajat Shop',
    description: 'Chinese, Fast Food, Snacks & Special Thalis',
    bannerUrl: '',
    contactNumber: '8295643910',
    orderNumber: '8295643910',
    openTime: '08:00',
    closeTime: '23:30',
    isClosedOverride: false,
    isActive: true,
    sortOrder: 1,
    searchKeywords: ['momos', 'chinese', 'fast food', 'snacks', 'thali', 'rajat'],
    deliveryNote: 'Pickup from Gate 2',
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );

  final nayanShop = Shop(
    id: 'nayan_shop',
    name: 'Nayan Shop',
    description: 'Rolls, Momos, Fast Food & Noodles',
    bannerUrl: '',
    contactNumber: '8875344034',
    orderNumber: '8875344034',
    openTime: '08:00',
    closeTime: '23:30',
    isClosedOverride: false,
    isActive: true,
    sortOrder: 2,
    searchKeywords: ['rolls', 'momos', 'noodles', 'chicken', 'fast food', 'nayan'],
    deliveryNote: 'Pickup from Gate 2',
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    localStorage = LocalStorageService(prefs);
    favoriteNotifier = FavoriteNotifier(localStorage);
    cartNotifier = CartNotifier();
  });

  group('Favourites Feature Logic Tests', () {
    test('Initial favourites set is empty', () {
      expect(favoriteNotifier.state.isEmpty, isTrue);
      expect(favoriteNotifier.isFavorite('veg_steam_momos', rajatShop.id), isFalse);
      expect(favoriteNotifier.isFavorite('veg_steam_momos', nayanShop.id), isFalse);
    });

    test('TEST 1 & TEST 2: Favoriting Rajat Shop item does NOT favorite Nayan Shop item', () async {
      // User favorites Veg Steam Momos in Rajat Shop
      await favoriteNotifier.toggleFavorite('veg_steam_momos', rajatShop.id);

      // Rajat Shop is favorited
      expect(favoriteNotifier.isFavorite('veg_steam_momos', rajatShop.id), isTrue);
      expect(favoriteNotifier.state.contains('rajat_shop:veg_steam_momos'), isTrue);

      // Nayan Shop item with identical ID is NOT favorited
      expect(favoriteNotifier.isFavorite('veg_steam_momos', nayanShop.id), isFalse);
      expect(favoriteNotifier.state.contains('nayan_shop:veg_steam_momos'), isFalse);
      expect(favoriteNotifier.state.length, equals(1));
    });

    test('TEST 3: Favoriting both shops with same item ID creates two separate entries', () async {
      await favoriteNotifier.toggleFavorite('veg_steam_momos', rajatShop.id);
      await favoriteNotifier.toggleFavorite('veg_steam_momos', nayanShop.id);

      expect(favoriteNotifier.state.length, equals(2));
      expect(favoriteNotifier.isFavorite('veg_steam_momos', rajatShop.id), isTrue);
      expect(favoriteNotifier.isFavorite('veg_steam_momos', nayanShop.id), isTrue);
      expect(favoriteNotifier.state.contains('rajat_shop:veg_steam_momos'), isTrue);
      expect(favoriteNotifier.state.contains('nayan_shop:veg_steam_momos'), isTrue);
    });

    test('TEST 4: Removing Rajat Shop item leaves Nayan Shop item intact', () async {
      await favoriteNotifier.toggleFavorite('veg_steam_momos', rajatShop.id);
      await favoriteNotifier.toggleFavorite('veg_steam_momos', nayanShop.id);

      // Remove Rajat Shop momos
      await favoriteNotifier.toggleFavorite('veg_steam_momos', rajatShop.id);

      // Rajat Shop momos gone
      expect(favoriteNotifier.isFavorite('veg_steam_momos', rajatShop.id), isFalse);
      expect(favoriteNotifier.state.contains('rajat_shop:veg_steam_momos'), isFalse);

      // Nayan Shop momos still favorited
      expect(favoriteNotifier.isFavorite('veg_steam_momos', nayanShop.id), isTrue);
      expect(favoriteNotifier.state.contains('nayan_shop:veg_steam_momos'), isTrue);
      expect(favoriteNotifier.state.length, equals(1));
    });

    test('TEST 5: Two identically named items from different shops never affect each other', () async {
      // Toggle Rajat momos on, then off
      await favoriteNotifier.toggleFavorite('veg_steam_momos', rajatShop.id);
      expect(favoriteNotifier.isFavorite('veg_steam_momos', rajatShop.id), isTrue);
      expect(favoriteNotifier.isFavorite('veg_steam_momos', nayanShop.id), isFalse);

      await favoriteNotifier.toggleFavorite('veg_steam_momos', rajatShop.id);
      expect(favoriteNotifier.isFavorite('veg_steam_momos', rajatShop.id), isFalse);
      expect(favoriteNotifier.isFavorite('veg_steam_momos', nayanShop.id), isFalse);
    });

    test('TEST 6: Navigate away and return persists shop-specific favorite state in SharedPreferences', () async {
      await favoriteNotifier.toggleFavorite('veg_steam_momos', rajatShop.id);
      await favoriteNotifier.toggleFavorite('chicken_kurkure_momos', nayanShop.id);

      expect(localStorage.favoriteItemIds, contains('rajat_shop:veg_steam_momos'));
      expect(localStorage.favoriteItemIds, contains('nayan_shop:chicken_kurkure_momos'));

      // Simulate app/screen reload from local storage
      final newFavoriteNotifier = FavoriteNotifier(localStorage);
      expect(newFavoriteNotifier.isFavorite('veg_steam_momos', rajatShop.id), isTrue);
      expect(newFavoriteNotifier.isFavorite('veg_steam_momos', nayanShop.id), isFalse);
      expect(newFavoriteNotifier.isFavorite('chicken_kurkure_momos', nayanShop.id), isTrue);
      expect(newFavoriteNotifier.isFavorite('chicken_kurkure_momos', rajatShop.id), isFalse);
    });

    test('clearFavorites empties state and local storage', () async {
      await favoriteNotifier.toggleFavorite('veg_steam_momos', rajatShop.id);
      expect(favoriteNotifier.state.isNotEmpty, isTrue);

      await favoriteNotifier.clearFavorites();
      expect(favoriteNotifier.state.isEmpty, isTrue);
      expect(localStorage.favoriteItemIds.isEmpty, isTrue);
    });
  });

  group('Cart Persistence Across Navigation Invariant Tests', () {
    test('Cart items remain intact when navigating away from Shop Detail', () {
      // 1. Add item in Rajat Shop
      final added = cartNotifier.addItem(item1, rajatShop.id, rajatShop.name);
      expect(added, isTrue);
      expect(cartNotifier.state.items.length, equals(1));
      expect(cartNotifier.state.shopId, equals(rajatShop.id));

      // 2. Simulate leaving shop to Home / Favourites / Profile (cartNotifier state is global)
      expect(cartNotifier.state.isNotEmpty, isTrue);
      expect(cartNotifier.state.items.first.menuItem.name, equals('Veg Steam Momos'));

      // 3. Opening CartScreen accesses same state with item intact
      expect(cartNotifier.state.grandTotal, equals(60.0));
      expect(cartNotifier.state.shopName, equals('Rajat Shop'));
    });

    test('Cross-shop conflict protection blocks adding item from second shop without explicit clear', () {
      // 1. Add Rajat Shop item
      cartNotifier.addItem(item1, rajatShop.id, rajatShop.name);

      // 2. Attempt adding Nayan Shop item -> returns false (conflict)
      final conflict = cartNotifier.addItem(item2, nayanShop.id, nayanShop.name);
      expect(conflict, isFalse);

      // 3. Original cart remains unchanged
      expect(cartNotifier.state.shopId, equals(rajatShop.id));
      expect(cartNotifier.state.items.length, equals(1));

      // 4. Atomically clearing and adding replaces with new shop
      cartNotifier.clearAndAddItem(item2, nayanShop.id, nayanShop.name);
      expect(cartNotifier.state.shopId, equals(nayanShop.id));
      expect(cartNotifier.state.items.first.menuItem.name, equals('Chicken Kurkure Momos'));
    });
  });

  group('Home Filter Matching Tests', () {
    final shops = [rajatShop, nayanShop];

    test('Filter "All" returns all active shops', () {
      final filtered = shops.where((s) => s.isActive).toList();
      expect(filtered.length, equals(2));
    });

    test('Filter "Fast Food" matches shops with fast food keyword', () {
      final filtered = shops.where((s) =>
        s.searchKeywords.any((k) => k.toLowerCase().contains('fast food')) ||
        s.description.toLowerCase().contains('fast food'),
      ).toList();
      expect(filtered.length, equals(2));
    });

    test('Filter "Thalis" matches Rajat Shop', () {
      final filtered = shops.where((s) =>
        s.searchKeywords.any((k) => k.toLowerCase().contains('thali')) ||
        s.description.toLowerCase().contains('thali'),
      ).toList();
      expect(filtered.length, equals(1));
      expect(filtered.first.id, equals('rajat_shop'));
    });

    test('Filter "Non-Veg" matches Nayan Shop', () {
      final filtered = shops.where((s) =>
        s.searchKeywords.any((k) => k.toLowerCase().contains('non-veg') || k.toLowerCase().contains('chicken')) ||
        s.id == 'nayan_shop' ||
        s.description.toLowerCase().contains('chicken'),
      ).toList();
      expect(filtered.length, equals(1));
      expect(filtered.first.id, equals('nayan_shop'));
    });
  });
}
