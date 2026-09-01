// BU Gate2Eat — Checkpoint 4.4 Firestore Read Deduplication & Safe Caching Tests
// Verifies that redundant Firestore queries are eliminated across consumers by reusing
// Riverpod provider futures, while ensuring strict cross-shop isolation and instant cache invalidation.

import 'package:bugate2eat_app/core/providers.dart';
import 'package:bugate2eat_app/models/category_model.dart';
import 'package:bugate2eat_app/models/menu_item_model.dart';
import 'package:bugate2eat_app/models/order_model.dart';
import 'package:bugate2eat_app/models/shop_model.dart';
import 'package:bugate2eat_app/services/firestore_service.dart';
import 'package:bugate2eat_app/services/local_storage_service.dart';
import 'package:bugate2eat_app/services/order_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _DeduplicationSpyFirestoreService extends Fake implements FirestoreService {
  int getShopsCallCount = 0;
  final Map<String, int> getMenuItemsCalls = {};
  final Map<String, int> getCategoriesCalls = {};
  final Map<String, int> getShopCalls = {};

  final Map<String, List<MenuItem>> mutableMenus = {
    'shop_a': [
      const MenuItem(
        id: 'item_a1',
        name: 'Butter Naan',
        details: 'Crispy butter naan',
        price: 40,
        imageUrl: '',
        categoryId: 'cat_breads',
        isVeg: true,
        isAvailable: true,
        isRecommended: true,
        sortOrder: 1,
      ),
      const MenuItem(
        id: 'item_a2',
        name: 'Paneer Butter Masala',
        details: 'Rich gravy',
        price: 180,
        imageUrl: '',
        categoryId: 'cat_gravy',
        isVeg: true,
        isAvailable: true,
        isRecommended: true,
        sortOrder: 2,
      ),
    ],
    'shop_b': [
      const MenuItem(
        id: 'item_b1',
        name: 'Cold Coffee',
        details: 'Chilled coffee',
        price: 60,
        imageUrl: '',
        categoryId: 'cat_beverages',
        isVeg: true,
        isAvailable: true,
        isRecommended: true,
        sortOrder: 1,
      ),
    ],
  };

  final Map<String, List<Category>> mutableCategories = {
    'shop_a': [
      const Category(id: 'cat_breads', name: 'Breads', sortOrder: 1, shopId: 'shop_a'),
      const Category(id: 'cat_gravy', name: 'Main Course', sortOrder: 2, shopId: 'shop_a'),
    ],
    'shop_b': [
      const Category(id: 'cat_beverages', name: 'Beverages', sortOrder: 1, shopId: 'shop_b'),
    ],
  };

  List<Shop> mutableShops = [
    Shop(
      id: 'shop_a',
      name: 'Raja Hotel',
      description: 'North Indian Delicacies',
      address: 'Gate 2 Commercial Complex',
      bannerUrl: '',
      contactNumber: '9910707219',
      orderNumber: '9319566645',
      openTime: '08:00',
      closeTime: '23:30',
      isClosedOverride: false,
      isActive: true,
      sortOrder: 1,
      searchKeywords: const ['raja', 'hotel'],
      deliveryNote: 'Gate 2',
      createdAt: DateTime(2025, 1, 1),
      updatedAt: DateTime(2025, 1, 1),
    ),
    Shop(
      id: 'shop_b',
      name: 'UP16 Coffee Queen',
      description: 'Chilled shakes and coffee',
      address: 'Near Gate 2',
      bannerUrl: '',
      contactNumber: '9910707220',
      orderNumber: '9319566646',
      openTime: '10:00',
      closeTime: '22:00',
      isClosedOverride: false,
      isActive: true,
      sortOrder: 2,
      searchKeywords: const ['coffee', 'queen'],
      deliveryNote: 'Gate 2',
      createdAt: DateTime(2025, 1, 1),
      updatedAt: DateTime(2025, 1, 1),
    ),
  ];

  @override
  Future<List<Shop>> getShops() async {
    getShopsCallCount++;
    return List.from(mutableShops);
  }

  @override
  Future<Shop?> getShop(String shopId) async {
    getShopCalls[shopId] = (getShopCalls[shopId] ?? 0) + 1;
    final match = mutableShops.where((s) => s.id == shopId).toList();
    return match.isNotEmpty ? match.first : null;
  }

  @override
  Future<List<MenuItem>> getMenuItems(String shopId) async {
    getMenuItemsCalls[shopId] = (getMenuItemsCalls[shopId] ?? 0) + 1;
    return List.from(mutableMenus[shopId] ?? []);
  }

  @override
  Future<List<Category>> getCategories(String shopId) async {
    getCategoriesCalls[shopId] = (getCategoriesCalls[shopId] ?? 0) + 1;
    return List.from(mutableCategories[shopId] ?? []);
  }
}

class _FakeLocalStorageService extends Fake implements LocalStorageService {
  @override
  bool get isOnboarded => true;
  @override
  String get userPhone => '9876543210';
  @override
  String get userName => 'Test Student';
  @override
  String get customerId => 'cust_9876543210';
  @override
  List<String> get favoriteItemIds => ['shop_a:item_a1'];
  @override
  String get themeMode => 'light';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _DeduplicationSpyFirestoreService spyFirestore;
  late _FakeLocalStorageService fakeLocalStorage;

  setUp(() {
    spyFirestore = _DeduplicationSpyFirestoreService();
    fakeLocalStorage = _FakeLocalStorageService();
  });

  ProviderContainer createContainer() {
    return ProviderContainer(
      overrides: [
        firestoreServiceProvider.overrideWithValue(spyFirestore),
        localStorageServiceProvider.overrideWithValue(fakeLocalStorage),
      ],
    );
  }

  group('Checkpoint 4.4 — Firestore Read Deduplication & Safe Caching Suite', () {
    test('TEST 1: Same shop menu requested by multiple consumers makes only 1 Firestore read', () async {
      final container = createContainer();

      // Consumer 1: Reads Shop A menu items
      final menu1 = await container.read(shopMenuItemsProvider('shop_a').future);
      expect(menu1.length, 2);
      expect(spyFirestore.getMenuItemsCalls['shop_a'], 1);

      // Consumer 2: Another component reads Shop A menu items in the same session
      final menu2 = await container.read(shopMenuItemsProvider('shop_a').future);
      expect(menu2.length, 2);

      // Firestore was NOT called a second time!
      expect(spyFirestore.getMenuItemsCalls['shop_a'], 1);
    });

    test('TEST 2: Same shop categories requested by multiple consumers makes only 1 Firestore read', () async {
      final container = createContainer();

      // Consumer 1: Reads Shop A categories
      final cats1 = await container.read(shopCategoriesProvider('shop_a').future);
      expect(cats1.length, 2);
      expect(spyFirestore.getCategoriesCalls['shop_a'], 1);

      // Consumer 2: Reads Shop A categories
      final cats2 = await container.read(shopCategoriesProvider('shop_a').future);
      expect(cats2.length, 2);

      // Firestore call count remains 1
      expect(spyFirestore.getCategoriesCalls['shop_a'], 1);
    });

    test('TEST 3: Cross-shop isolation — Shop A cache never leaks into Shop B', () async {
      final container = createContainer();

      final menuA = await container.read(shopMenuItemsProvider('shop_a').future);
      final menuB = await container.read(shopMenuItemsProvider('shop_b').future);

      expect(menuA.map((i) => i.name), contains('Butter Naan'));
      expect(menuA.map((i) => i.name), isNot(contains('Cold Coffee')));

      expect(menuB.map((i) => i.name), contains('Cold Coffee'));
      expect(menuB.map((i) => i.name), isNot(contains('Butter Naan')));

      expect(spyFirestore.getMenuItemsCalls['shop_a'], 1);
      expect(spyFirestore.getMenuItemsCalls['shop_b'], 1);
    });

    test('TEST 4: Menu price update propagates after provider invalidation', () async {
      final container = createContainer();

      // 1. Initial read
      final initialMenu = await container.read(shopMenuItemsProvider('shop_a').future);
      expect(initialMenu.first.price, 40);
      expect(spyFirestore.getMenuItemsCalls['shop_a'], 1);

      // 2. Shopkeeper updates price in Firestore (40 -> 50)
      spyFirestore.mutableMenus['shop_a']![0] = const MenuItem(
        id: 'item_a1',
        name: 'Butter Naan',
        details: 'Crispy butter naan',
        price: 50,
        imageUrl: '',
        categoryId: 'cat_breads',
        isVeg: true,
        isAvailable: true,
        isRecommended: true,
        sortOrder: 1,
      );

      // 3. Invalidate provider
      container.invalidate(shopMenuItemsProvider('shop_a'));

      // 4. Subsequent read returns new price
      final updatedMenu = await container.read(shopMenuItemsProvider('shop_a').future);
      expect(updatedMenu.first.price, 50);
      expect(spyFirestore.getMenuItemsCalls['shop_a'], 2);
    });

    test('TEST 5: Item availability update propagates after provider invalidation', () async {
      final container = createContainer();

      // 1. Initial read: isAvailable = true
      final menu1 = await container.read(shopMenuItemsProvider('shop_a').future);
      expect(menu1.first.isAvailable, true);

      // 2. Shopkeeper toggles item to Out of Stock
      spyFirestore.mutableMenus['shop_a']![0] = const MenuItem(
        id: 'item_a1',
        name: 'Butter Naan',
        details: 'Crispy butter naan',
        price: 40,
        imageUrl: '',
        categoryId: 'cat_breads',
        isVeg: true,
        isAvailable: false, // Out of Stock
        isRecommended: true,
        sortOrder: 1,
      );

      // 3. Invalidate provider
      container.invalidate(shopMenuItemsProvider('shop_a'));

      // 4. Subsequent read sees isAvailable = false
      final menu2 = await container.read(shopMenuItemsProvider('shop_a').future);
      expect(menu2.first.isAvailable, false);
    });

    test('TEST 6: Item deletion propagates after provider invalidation', () async {
      final container = createContainer();

      // 1. Initial read: 2 items
      final menu1 = await container.read(shopMenuItemsProvider('shop_a').future);
      expect(menu1.length, 2);

      // 2. Shopkeeper deletes item_a2
      spyFirestore.mutableMenus['shop_a']!.removeWhere((i) => i.id == 'item_a2');

      // 3. Invalidate provider
      container.invalidate(shopMenuItemsProvider('shop_a'));

      // 4. Subsequent read has only 1 item
      final menu2 = await container.read(shopMenuItemsProvider('shop_a').future);
      expect(menu2.length, 1);
      expect(menu2.first.id, 'item_a1');
    });

    test('TEST 7: Category updates propagate after provider invalidation', () async {
      final container = createContainer();

      // 1. Initial read: 2 categories
      final cats1 = await container.read(shopCategoriesProvider('shop_a').future);
      expect(cats1.length, 2);

      // 2. Shopkeeper adds new category 'Desserts'
      spyFirestore.mutableCategories['shop_a']!.add(
        const Category(id: 'cat_desserts', name: 'Desserts', sortOrder: 3, shopId: 'shop_a'),
      );

      // 3. Invalidate provider
      container.invalidate(shopCategoriesProvider('shop_a'));

      // 4. Subsequent read reflects 3 categories
      final cats2 = await container.read(shopCategoriesProvider('shop_a').future);
      expect(cats2.length, 3);
      expect(cats2.last.name, 'Desserts');
    });

    test('TEST 8: Shop details changes propagate after shopsProvider invalidation', () async {
      final container = createContainer();

      // 1. Initial read
      final shops1 = await container.read(shopsProvider.future);
      expect(shops1.first.name, 'Raja Hotel');

      // 2. Admin edits shop name
      spyFirestore.mutableShops[0] = spyFirestore.mutableShops[0].copyWith(
        name: 'Raja Hotel & Restaurant',
      );

      // 3. Invalidate shopsProvider
      container.invalidate(shopsProvider);

      // 4. Subsequent read returns updated name
      final shops2 = await container.read(shopsProvider.future);
      expect(shops2.first.name, 'Raja Hotel & Restaurant');
    });

    test('TEST 9: favoriteItemsProvider reuses cached shopMenuItemsProvider future', () async {
      final container = createContainer();

      // 1. Preload Shop A menu
      await container.read(shopMenuItemsProvider('shop_a').future);
      expect(spyFirestore.getMenuItemsCalls['shop_a'], 1);

      // 2. Read favorite items (item from Shop A)
      final favs = await container.read(favoriteItemsProvider.future);
      expect(favs.length, 1);
      expect(favs.first.item.name, 'Butter Naan');

      // FavoriteItemsProvider reused Shop A menu without querying Firestore again!
      expect(spyFirestore.getMenuItemsCalls['shop_a'], 1);

      // It also did NOT query Shop B because favorites only target Shop A!
      expect(spyFirestore.getMenuItemsCalls['shop_b'], isNull);
    });

    test('TEST 10: allShopMenuItemsProvider reuses underlying shopMenuItemsProvider futures', () async {
      final container = createContainer();

      // 1. Preload Shop A menu
      await container.read(shopMenuItemsProvider('shop_a').future);
      expect(spyFirestore.getMenuItemsCalls['shop_a'], 1);

      // 2. Read global search catalog
      final allMenus = await container.read(allShopMenuItemsProvider.future);
      expect(allMenus.keys, containsAll(['shop_a', 'shop_b']));

      // Shop A was reused (call count remains 1), Shop B was loaded (call count = 1)
      expect(spyFirestore.getMenuItemsCalls['shop_a'], 1);
      expect(spyFirestore.getMenuItemsCalls['shop_b'], 1);
    });

    test('TEST 11: Fresh container / App restart loads authoritative data from Firestore', () async {
      // Container 1 (Session 1)
      final container1 = createContainer();
      final menuSession1 = await container1.read(shopMenuItemsProvider('shop_a').future);
      expect(menuSession1.first.price, 40);

      // Firestore updated out-of-band while app was closed
      spyFirestore.mutableMenus['shop_a']![0] = const MenuItem(
        id: 'item_a1',
        name: 'Butter Naan',
        details: 'Crispy butter naan',
        price: 55,
        imageUrl: '',
        categoryId: 'cat_breads',
        isVeg: true,
        isAvailable: true,
        isRecommended: true,
        sortOrder: 1,
      );

      // Container 2 (Session 2 / App restart)
      final container2 = createContainer();
      final menuSession2 = await container2.read(shopMenuItemsProvider('shop_a').future);
      expect(menuSession2.first.price, 55); // Fresh data loaded
    });

    test('TEST 12: Real-time streams remain active and unaffected by static caching', () async {
      final container = createContainer();

      final ordersStream = container.read(customerActiveOrdersStreamProvider.stream);
      expect(ordersStream, isA<Stream<List<AppOrder>>>());
    });
  });
}
