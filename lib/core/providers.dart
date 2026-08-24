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
import '../services/shop_stats_service.dart';

export '../models/shop_model.dart' show ShopOrderMethod;

/// Provider for the Firestore service (singleton).
final firestoreServiceProvider = Provider<FirestoreService>((ref) {
  return FirestoreService();
});

/// Provider for the Order service (singleton).
final orderServiceProvider = Provider<OrderService>((ref) {
  return OrderService();
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

/// Provider for the current theme mode.
/// Reads initial value from local storage, can be updated from Settings.
final themeModeProvider = StateNotifierProvider<ThemeModeNotifier, ThemeMode>((ref) {
  final localStorage = ref.read(localStorageServiceProvider);
  return ThemeModeNotifier(localStorage);
});

/// Manages the app's theme mode state.
class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  ThemeModeNotifier(this._localStorage) : super(_parseThemeMode(_localStorage.themeMode));

  final LocalStorageService _localStorage;

  /// Updates the theme mode and persists the choice.
  Future<void> setThemeMode(ThemeMode mode) async {
    state = mode;
    await _localStorage.setThemeMode(_themeModeToString(mode));
  }

  static ThemeMode _parseThemeMode(String mode) {
    switch (mode) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  static String _themeModeToString(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
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
final favoriteItemsProvider = FutureProvider<List<FavoriteItemData>>((ref) async {
  final favoriteKeys = ref.watch(favoritesProvider);
  if (favoriteKeys.isEmpty) return [];

  final shops = await ref.watch(shopsProvider.future);
  final firestoreService = ref.watch(firestoreServiceProvider);

  final List<FavoriteItemData> results = [];

  for (final shop in shops) {
    final menuItems = await firestoreService.getMenuItems(shop.id);
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

/// Real-time stream provider for current customer's order history (delivered, rejected, cancelled).
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

/// Real-time stream provider for a shop's order history (delivered, rejected, cancelled).
final shopOrderHistoryStreamProvider =
    StreamProvider.family<List<AppOrder>, String?>((ref, shopId) async* {
  final orderService = ref.watch(orderServiceProvider);
  final dummyOrders = ref.watch(dummyOrdersProvider);
  final effectiveShopId = (shopId != null && shopId.isNotEmpty)
      ? shopId
      : ref.watch(currentShopkeeperShopIdProvider);

  if (!orderService.isAvailable) {
    yield dummyOrders
        .where((o) =>
            o.shopId == effectiveShopId &&
            (o.status == 'delivered' ||
                o.status == 'rejected' ||
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
final currentShopkeeperShopIdProvider = Provider<String>((ref) {
  try {
    final localStorage = ref.watch(localStorageServiceProvider);
    final cleanPhone =
        localStorage.userPhone.replaceAll(RegExp(r'[^0-9]'), '');

    if (cleanPhone.endsWith('8745007244') || cleanPhone.endsWith('8745950335')) {
      return 'up16_junction_fast_food';
    }
    if (cleanPhone.endsWith('8875344034') || cleanPhone == '8875344034') {
      return 'nayan_shop';
    }
    if (cleanPhone.endsWith('8295643910') || cleanPhone == '8295643910') {
      return 'rajat_shop';
    }
  } catch (_) {}
  return 'rajat_shop';
});


