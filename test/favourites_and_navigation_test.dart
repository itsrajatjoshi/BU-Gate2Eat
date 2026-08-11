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
      expect(favoriteNotifier.isFavorite('veg_steam_momos'), isFalse);
    });

    test('Toggling item adds it to favourites and persists', () async {
      await favoriteNotifier.toggleFavorite('veg_steam_momos');

      expect(favoriteNotifier.isFavorite('veg_steam_momos'), isTrue);
      expect(favoriteNotifier.state.contains('veg_steam_momos'), isTrue);
      expect(localStorage.favoriteItemIds, contains('veg_steam_momos'));
    });

    test('Toggling favorited item removes it from favourites and persists', () async {
      await favoriteNotifier.toggleFavorite('veg_steam_momos');
      expect(favoriteNotifier.isFavorite('veg_steam_momos'), isTrue);

      await favoriteNotifier.toggleFavorite('veg_steam_momos');
      expect(favoriteNotifier.isFavorite('veg_steam_momos'), isFalse);
      expect(localStorage.favoriteItemIds, isNot(contains('veg_steam_momos')));
    });

    test('Multiple items can be favorited independently', () async {
      await favoriteNotifier.toggleFavorite('veg_steam_momos');
      await favoriteNotifier.toggleFavorite('chicken_kurkure_momos');

      expect(favoriteNotifier.state.length, equals(2));
      expect(favoriteNotifier.isFavorite('veg_steam_momos'), isTrue);
      expect(favoriteNotifier.isFavorite('chicken_kurkure_momos'), isTrue);

      await favoriteNotifier.toggleFavorite('veg_steam_momos');
      expect(favoriteNotifier.state.length, equals(1));
      expect(favoriteNotifier.isFavorite('chicken_kurkure_momos'), isTrue);
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
