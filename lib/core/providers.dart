// BU Gate2Eat — Core Providers
// Global Riverpod providers for services and shared state

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/category_model.dart';
import '../models/menu_item_model.dart';
import '../models/shop_model.dart';
import '../services/firestore_service.dart';
import '../services/force_update_service.dart';
import '../services/local_storage_service.dart';

/// Provider for the Firestore service (singleton).
final firestoreServiceProvider = Provider<FirestoreService>((ref) {
  return FirestoreService();
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


