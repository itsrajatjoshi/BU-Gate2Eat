import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/category_model.dart';
import '../models/menu_item_model.dart';
import '../models/order_model.dart';
import '../models/shop_model.dart';
import '../models/shop_stats_model.dart';
import '../services/firestore_service.dart';
import '../services/force_update_service.dart';
import '../services/local_storage_service.dart';
import '../services/order_service.dart';
import '../services/notification_service.dart';
import '../services/report_service.dart';
import '../services/shop_stats_service.dart';
import 'constants/app_constants.dart';

export '../models/shop_model.dart' show ShopOrderMethod;

/// Provider for the Firestore service (singleton).
final firestoreServiceProvider = Provider<FirestoreService>((ref) {
  return FirestoreService();
});

/// Provider for the Notification service (singleton).
final notificationServiceProvider = Provider<NotificationService>((ref) {
  return NotificationService();
});

/// Provider for the Order service (singleton).
final orderServiceProvider = Provider<OrderService>((ref) {
  return OrderService();
});

/// Provider for the Report service (singleton).
final reportServiceProvider = Provider<ReportService>((ref) {
  return ReportService();
});

/// Family provider for fetching authoritative reset-to-export vendor statement data.
final shopStatementDataProvider = FutureProvider.family<
    MonthlyReportData,
    ({
      String shopId,
      String shopName,
      DateTime? statementStart,
      DateTime statementEnd,
      DateTime? fallbackCreatedAt,
    })>((ref, params) async {
  final reportService = ref.watch(reportServiceProvider);
  return reportService.fetchShopStatementData(
    shopId: params.shopId,
    shopName: params.shopName,
    startDateTime: params.statementStart,
    endDateTime: params.statementEnd,
    fallbackCreatedAt: params.fallbackCreatedAt,
  );
});

/// Family provider for fetching monthly report data (legacy adapter).
final monthlyReportDataProvider = FutureProvider.family<MonthlyReportData, ({String shopId, String shopName, DateTime month})>((ref, params) async {
  final reportService = ref.watch(reportServiceProvider);
  return reportService.fetchMonthlyShopReportData(
    shopId: params.shopId,
    shopName: params.shopName,
    month: params.month,
  );
});

/// Provider for the Shop Statistics service (singleton).
final shopStatsServiceProvider = Provider<ShopStatsService>((ref) {
  return ShopStatsService();
});

/// Real-time stream of all shops' statistics for admin dashboard.
final allShopStatsStreamProvider = StreamProvider<List<ShopStats>>((ref) {
  final statsService = ref.watch(shopStatsServiceProvider);
  return statsService.watchAllShopStats();
});

/// Real-time stream of a single shop's statistics.
final shopStatsStreamProvider =
    StreamProvider.family<ShopStats?, String>((ref, shopId) {
  final statsService = ref.watch(shopStatsServiceProvider);
  return statsService.watchShopStats(shopId);
});

/// Cached provider for fetching active shops list.
final shopsProvider = FutureProvider<List<Shop>>((ref) async {
  final firestoreService = ref.watch(firestoreServiceProvider);
  return firestoreService.getShops();
});

/// Cached provider for fetching shop categories by shop ID.
final shopCategoriesProvider =
    FutureProvider.family<List<Category>, String>((ref, shopId) async {
  final firestoreService = ref.watch(firestoreServiceProvider);
  return firestoreService.getCategories(shopId);
});

/// Cached provider for lazy-loading menu items by shop ID.
final shopMenuItemsProvider =
    FutureProvider.family<List<MenuItem>, String>((ref, shopId) async {
  final firestoreService = ref.watch(firestoreServiceProvider);
  return firestoreService.getMenuItems(shopId);
});

/// Provider for fetching all menu items mapped by shop ID (shopId -> List<MenuItem>).
/// Used by Homepage search and filter for instant, efficient in-memory filtering.
final allShopMenuItemsProvider = FutureProvider<Map<String, List<MenuItem>>>((ref) async {
  final shops = await ref.watch(shopsProvider.future);
  final Map<String, List<MenuItem>> result = {};
  await Future.wait(
    shops.map((shop) async {
      final items = await ref.watch(shopMenuItemsProvider(shop.id).future);
      result[shop.id] = items;
    }),
  );
  return result;
});

/// Provider for fetching all categories mapped by shop ID (shopId -> List<Category>).
/// Used by Homepage category filters for instant in-memory matching.
final allShopCategoriesProvider = FutureProvider<Map<String, List<Category>>>((ref) async {
  final shops = await ref.watch(shopsProvider.future);
  final Map<String, List<Category>> result = {};
  await Future.wait(
    shops.map((shop) async {
      final cats = await ref.watch(shopCategoriesProvider(shop.id).future);
      result[shop.id] = cats;
    }),
  );
  return result;
});

/// Resolves the deterministic list of slideshow images for a shop's main banner.
/// Follows 3.7.7 rule: Shop Banner is always index 0, followed by
/// Category first-item images in category sortOrder, then other menu item images, deduplicated.
final shopSlideshowImagesProvider =
    Provider.family<List<String>, Shop>((ref, shop) {
  final catsAsync = ref.watch(shopCategoriesProvider(shop.id));
  final itemsAsync = ref.watch(shopMenuItemsProvider(shop.id));

  final categories = catsAsync.value ?? [];
  final menuItems = itemsAsync.value ?? [];

  return resolveShopSlideshowImages(
    shopBannerUrl: shop.bannerUrl,
    categories: categories,
    menuItems: menuItems,
  );
});

/// Pure helper function to resolve deterministic slideshow images starting with shop banner at index 0.
List<String> resolveShopSlideshowImages({
  required List<Category> categories,
  required List<MenuItem> menuItems,
  String? shopBannerUrl,
  String? fallbackShopBannerUrl,
}) {
  final List<String> images = [];
  final Set<String> seenUrls = {};

  void addImage(String url) {
    final trimmed = url.trim();
    if (trimmed.isNotEmpty && !seenUrls.contains(trimmed)) {
      seenUrls.add(trimmed);
      images.add(trimmed);
    }
  }

  // 1. ALWAYS place Shop Banner at index 0 if available
  final primaryBanner = shopBannerUrl ?? fallbackShopBannerUrl;
  if (primaryBanner != null && primaryBanner.trim().isNotEmpty) {
    addImage(primaryBanner);
  }

  // 2. Sort categories by sortOrder
  final sortedCats = List<Category>.from(categories)
    ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

  // 3. Sort menu items by sortOrder
  final sortedItems = List<MenuItem>.from(menuItems)
    ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

  // 4. For each category, resolve the first menu item's image
  for (final cat in sortedCats) {
    final catItems = sortedItems.where((item) => item.categoryId == cat.id);
    final firstItemWithImg = catItems.cast<MenuItem?>().firstWhere(
      (item) => item != null && item.imageUrl.trim().isNotEmpty,
      orElse: () => null,
    );

    if (firstItemWithImg != null && firstItemWithImg.imageUrl.trim().isNotEmpty) {
      addImage(firstItemWithImg.imageUrl);
    } else if (cat.imageUrl.trim().isNotEmpty) {
      addImage(cat.imageUrl);
    }
  }

  // 5. If any other menu items have images not yet included, add them
  for (final item in sortedItems) {
    if (item.imageUrl.trim().isNotEmpty) {
      addImage(item.imageUrl);
    }
  }

  return images;
}

/// Cached provider for fetching recommended items for Cart "You may also like".
final recommendedMenuItemsProvider =
    FutureProvider.family<List<MenuItem>, String>((ref, shopId) async {
  final firestoreService = ref.watch(firestoreServiceProvider);
  return firestoreService.getRecommendedMenuItems(shopId);
});

/// Provider for the LocalStorage service.
/// Must be overridden in main.dart after initialization.
final localStorageServiceProvider = Provider<LocalStorageService>((ref) {
  throw UnimplementedError('LocalStorageService must be overridden at startup');
});

/// Immutable customer identity representation for development and testing.
class CustomerIdentity {
  const CustomerIdentity({
    required this.customerId,
    required this.name,
    required this.phone,
  });

  final String customerId;
  final String name;
  final String phone;
}

/// Provider for the current customer's identity.
/// Easily swappable with Firebase Auth UID in future phases.
final customerIdentityProvider = Provider<CustomerIdentity>((ref) {
  try {
    final localStorage = ref.watch(localStorageServiceProvider);
    final phone = localStorage.userPhone.trim();
    final name = localStorage.userName.trim();
    return CustomerIdentity(
      customerId: localStorage.customerId,
      name: name.isNotEmpty ? name : 'Student',
      phone: phone,
    );
  } catch (_) {
    return const CustomerIdentity(
      customerId: 'cust_default',
      name: 'Student',
      phone: '9876543210',
    );
  }
});

/// Provider for the ForceUpdate service.
final forceUpdateServiceProvider = Provider<ForceUpdateService>((ref) {
  return ForceUpdateService(ref.read(firestoreServiceProvider));
});

/// Provider for the current theme mode (Permanently locked to Light Mode).
final themeModeProvider = StateNotifierProvider<ThemeModeNotifier, ThemeMode>((ref) {
  final localStorage = ref.read(localStorageServiceProvider);
  return ThemeModeNotifier(localStorage);
});

/// Manages the app's theme mode state (Light Mode only).
class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  ThemeModeNotifier(this._localStorage) : super(ThemeMode.light);

  final LocalStorageService _localStorage;

  /// Updates the theme mode (Permanently Light).
  Future<void> setThemeMode(ThemeMode mode) async {
    state = ThemeMode.light;
    await _localStorage.setThemeMode('light');
  }
}

/// Provider for managing user favorite item keys stored locally.
final favoritesProvider =
    StateNotifierProvider<FavoriteNotifier, Set<String>>((ref) {
  final localStorage = ref.read(localStorageServiceProvider);
  return FavoriteNotifier(localStorage);
});

/// Manages local user favorite menu items with shop-specific composite keys (shopId:itemId).
class FavoriteNotifier extends StateNotifier<Set<String>> {
  FavoriteNotifier(this._localStorage)
      : super(_localStorage.favoriteItemIds.toSet());

  final LocalStorageService _localStorage;

  /// Builds a deterministic shop-specific composite key for a menu item.
  static String buildFavoriteKey(String shopId, String itemId) => '$shopId:$itemId';

  /// Toggles favorite status for a given item in a specific shop and persists to SharedPreferences.
  Future<void> toggleFavorite(String itemId, [String? shopId]) async {
    final key = (shopId != null && shopId.isNotEmpty)
        ? buildFavoriteKey(shopId, itemId)
        : itemId;
    final updated = Set<String>.from(state);
    if (updated.contains(key)) {
      updated.remove(key);
    } else {
      updated.add(key);
    }
    state = updated;
    await _localStorage.saveFavoriteItemIds(updated.toList());
  }

  /// Checks whether an item in a specific shop is favorited.
  bool isFavorite(String itemId, [String? shopId]) {
    if (shopId != null && shopId.isNotEmpty) {
      return state.contains(buildFavoriteKey(shopId, itemId)) || state.contains(itemId);
    }
    return state.contains(itemId);
  }

  /// Clears all stored favorites.
  Future<void> clearFavorites() async {
    state = {};
    await _localStorage.saveFavoriteItemIds([]);
  }
}

/// Represents a favorited menu item paired with its parent shop information.
class FavoriteItemData {
  const FavoriteItemData({
    required this.item,
    required this.shop,
  });

  final MenuItem item;
  final Shop shop;
}

/// Provider for fetching all favorited menu items paired with their parent shops.
/// Deduplicates reads by reusing shopMenuItemsProvider cached futures.
final favoriteItemsProvider = FutureProvider<List<FavoriteItemData>>((ref) async {
  final favoriteKeys = ref.watch(favoritesProvider);
  if (favoriteKeys.isEmpty) return [];

  final shops = await ref.watch(shopsProvider.future);
  final List<FavoriteItemData> results = [];

  // Identify target shop IDs if keys contain "shopId:itemId" or legacy "shopId_itemId"
  final Set<String> targetShopIds = {};
  bool hasLegacyBareKeys = false;
  for (final key in favoriteKeys) {
    if (key.contains(':')) {
      final shopId = key.substring(0, key.indexOf(':'));
      if (shopId.isNotEmpty) targetShopIds.add(shopId);
    } else if (key.contains('_')) {
      final shopId = key.substring(0, key.indexOf('_'));
      if (shopId.isNotEmpty) targetShopIds.add(shopId);
    } else {
      hasLegacyBareKeys = true;
    }
  }

  // Filter shops to inspect: only target shops if known, otherwise all shops
  final shopsToInspect = (targetShopIds.isNotEmpty && !hasLegacyBareKeys)
      ? shops.where((s) => targetShopIds.contains(s.id)).toList()
      : shops;

  for (final shop in shopsToInspect) {
    final menuItems = await ref.watch(shopMenuItemsProvider(shop.id).future);
    for (final item in menuItems) {
      final key = FavoriteNotifier.buildFavoriteKey(shop.id, item.id);
      if (favoriteKeys.contains(key) || favoriteKeys.contains(item.id)) {
        results.add(FavoriteItemData(item: item, shop: shop));
      }
    }
  }

  return results;
});

// shopOrderMethodProvider REMOVED — shop.orderMethod from Firestore is the single source of truth.

/// Real-time stream provider for current customer's active orders (placed, accepted).
final customerActiveOrdersStreamProvider =
    StreamProvider<List<AppOrder>>((ref) async* {
  final orderService = ref.watch(orderServiceProvider);
  final identity = ref.watch(customerIdentityProvider);
  final dummyOrders = ref.watch(dummyOrdersProvider);

  if (!orderService.isAvailable) {
    yield dummyOrders
        .where((o) => o.status == 'placed' || o.status == 'accepted')
        .toList();
    return;
  }

  yield* orderService
      .watchCustomerActiveOrders(
        customerId: identity.customerId,
        customerPhone: identity.phone,
      );
});

/// Auto-ticking 1-second stream provider for live order countdowns and active order reconciliation.
/// Automatically cleans up its periodic timer when disposed.
final orderReconciliationTickerProvider = StreamProvider.autoDispose<DateTime>((ref) {
  final controller = StreamController<DateTime>();
  controller.add(DateTime.now());

  Timer? timer;
  final bindingName = WidgetsBinding.instance.runtimeType.toString();
  final isTestEnvironment =
      bindingName.contains('Test') || bindingName.contains('Automated');

  if (!isTestEnvironment) {
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!controller.isClosed) {
        controller.add(DateTime.now());
      }
    });
  }

  ref.onDispose(() {
    timer?.cancel();
    if (!controller.isClosed) {
      controller.close();
    }
  });

  return controller.stream;
});

/// Real-time stream provider for current customer's order history (delivered, rejected, delivery_expired).
final customerOrderHistoryStreamProvider =
    StreamProvider<List<AppOrder>>((ref) async* {
  final orderService = ref.watch(orderServiceProvider);
  final identity = ref.watch(customerIdentityProvider);
  final dummyOrders = ref.watch(dummyOrdersProvider);

  if (!orderService.isAvailable) {
    yield dummyOrders
        .where((o) =>
            o.status == 'delivered' ||
            o.status == 'rejected' ||
            o.status == 'delivery_expired' ||
            o.status == 'cancelled')
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return;
  }

  yield* orderService
      .watchCustomerOrderHistory(
        customerId: identity.customerId,
        customerPhone: identity.phone,
      );
});

/// Real-time stream provider for watching a single order by orderId.
final singleOrderStreamProvider =
    StreamProvider.family<AppOrder?, String>((ref, orderId) async* {
  final orderService = ref.watch(orderServiceProvider);
  final dummyOrders = ref.watch(dummyOrdersProvider);

  AppOrder? getDummy() {
    try {
      return dummyOrders.firstWhere((o) => o.orderId == orderId);
    } catch (_) {
      return null;
    }
  }

  if (!orderService.isAvailable) {
    yield getDummy();
    return;
  }

  yield* orderService.watchOrder(orderId);
});

/// Real-time stream provider for a shop's active orders (placed, accepted).
final shopActiveOrdersStreamProvider =
    StreamProvider.family<List<AppOrder>, String?>((ref, shopId) async* {
  final orderService = ref.watch(orderServiceProvider);
  final dummyOrders = ref.watch(dummyOrdersProvider);
  final effectiveShopId = (shopId != null && shopId.isNotEmpty)
      ? shopId
      : ref.watch(currentShopkeeperShopIdProvider);

  if (effectiveShopId == null || effectiveShopId.isEmpty) {
    yield [];
    return;
  }

  if (!orderService.isAvailable) {
    yield dummyOrders
        .where((o) =>
            o.shopId == effectiveShopId &&
            (o.status == 'placed' || o.status == 'accepted'))
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return;
  }

  yield* orderService.watchShopActiveOrders(effectiveShopId);
});

/// Real-time stream provider for a shop's order history (delivered, rejected, delivery_expired).
final shopOrderHistoryStreamProvider =
    StreamProvider.family<List<AppOrder>, String?>((ref, shopId) async* {
  final orderService = ref.watch(orderServiceProvider);
  final dummyOrders = ref.watch(dummyOrdersProvider);
  final effectiveShopId = (shopId != null && shopId.isNotEmpty)
      ? shopId
      : ref.watch(currentShopkeeperShopIdProvider);

  if (effectiveShopId == null || effectiveShopId.isEmpty) {
    yield [];
    return;
  }

  if (!orderService.isAvailable) {
    yield dummyOrders
        .where((o) =>
            o.shopId == effectiveShopId &&
            (o.status == 'delivered' ||
                o.status == 'rejected' ||
                o.status == 'delivery_expired' ||
                o.status == 'cancelled'))
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return;
  }

  yield* orderService.watchShopOrderHistory(effectiveShopId);
});

/// Real-time stream of ALL in-app orders for a specific shop (isolated by shopId).
/// Used by Admin Panel for Shop In-App Orders List.
final shopOrdersStreamProvider =
    StreamProvider.family<List<AppOrder>, String>((ref, shopId) async* {
  final orderService = ref.watch(orderServiceProvider);
  if (!orderService.isAvailable) {
    yield [];
    return;
  }
  yield* orderService.watchShopOrders(shopId);
});

/// Local/session state provider for dummy customer orders (Used by Shopkeeper until Part 3.4)
final dummyOrdersProvider =
    StateNotifierProvider<DummyOrdersNotifier, List<AppOrder>>((ref) {
  return DummyOrdersNotifier();
});

class DummyOrdersNotifier extends StateNotifier<List<AppOrder>> {
  DummyOrdersNotifier() : super([]);

  void addOrder(AppOrder order) {
    state = [order, ...state];
  }

  void cancelOrder(String orderId) {
    state = state.map((order) {
      if (order.orderId == orderId) {
        return order.copyWith(status: 'cancelled');
      }
      return order;
    }).toList();
  }

  void updateOrderStatus(
    String orderId,
    String newStatus, {
    String? rejectionReason,
  }) {
    state = state.map((order) {
      if (order.orderId == orderId) {
        return order.copyWith(
          status: newStatus,
          rejectionReason: rejectionReason,
        );
      }
      return order;
    }).toList();
  }

  AppOrder? getOrder(String orderId) {
    try {
      return state.firstWhere((o) => o.orderId == orderId);
    } catch (_) {
      return null;
    }
  }
}

// shopMinimumOrderProvider REMOVED — shop.minimumOrderAmount from Firestore is the single source of truth.

/// Provider for resolving active shopkeeper's shopId based on logged-in phone number.
/// Returns null if phone number is not linked to any registered shopkeeper.
final currentShopkeeperShopIdProvider = Provider<String?>((ref) {
  try {
    final localStorage = ref.watch(localStorageServiceProvider);
    final phone = localStorage.userPhone;
    final resolvedShopId = AppAuthRoles.getShopIdForPhone(phone);
    if (resolvedShopId != null && resolvedShopId.isNotEmpty) {
      return resolvedShopId;
    }
  } catch (_) {}
  return null;
});


