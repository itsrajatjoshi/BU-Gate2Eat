// BU Gate2Eat — Cart Provider
// Riverpod state management for authoritative single-shop shopping cart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/cart_item_model.dart';
import '../../models/cart_state_model.dart';
import '../../models/menu_item_model.dart';

/// Provider for the single-shop cart state. Cart is in-memory only.
final cartProvider =
    StateNotifierProvider<CartNotifier, CartState>((ref) {
  return CartNotifier();
});

/// Convenience provider for getting items list directly.
final cartItemsProvider = Provider<List<CartItem>>((ref) {
  return ref.watch(cartProvider).items;
});

/// Manages the single-shop cart state — add, remove, update, clear, switch shop.
class CartNotifier extends StateNotifier<CartState> {
  CartNotifier() : super(const CartState());

  /// Checks if an item from newShopId can be added directly without confirmation.
  bool canAddItem(String newShopId) {
    return state.isEmpty || state.shopId == newShopId;
  }

  /// Adds an item to the cart or increments quantity if from the same shop.
  /// If from a different shop, returns false (signaling shop conflict requiring dialog).
  bool addItem(MenuItem menuItem, String shopId, String shopName) {
    // Single-Shop Invariant Check
    if (state.isNotEmpty && state.shopId != null && state.shopId != shopId) {
      return false; // Conflict! UI must prompt for clear & add.
    }

    final existingIndex = state.items.indexWhere(
      (item) => item.shopId == shopId && item.menuItem.id == menuItem.id,
    );

    if (existingIndex >= 0) {
      // Increment quantity
      final updated = [...state.items];
      updated[existingIndex] = updated[existingIndex].copyWith(
        quantity: updated[existingIndex].quantity + 1,
      );
      state = state.copyWith(items: updated);
    } else {
      // Add new item
      final newItem = CartItem(
        menuItem: menuItem,
        quantity: 1,
        shopId: shopId,
        shopName: shopName,
      );
      state = CartState(
        shopId: shopId,
        shopName: shopName,
        items: [...state.items, newItem],
      );
    }

    _enforceInvariant();
    return true;
  }

  /// Atomically clears existing cart items and adds a new item from new shop.
  void clearAndAddItem(MenuItem menuItem, String shopId, String shopName) {
    state = CartState(
      shopId: shopId,
      shopName: shopName,
      items: [
        CartItem(
          menuItem: menuItem,
          quantity: 1,
          shopId: shopId,
          shopName: shopName,
        ),
      ],
    );
    _enforceInvariant();
  }

  /// Decrements quantity or removes item completely if quantity becomes 0.
  void removeItem(String menuItemId, [String? shopId]) {
    final existingIndex = state.items.indexWhere(
      (item) => (shopId == null || item.shopId == shopId) && item.menuItem.id == menuItemId,
    );

    if (existingIndex < 0) return;

    final updated = [...state.items];
    if (updated[existingIndex].quantity > 1) {
      updated[existingIndex] = updated[existingIndex].copyWith(
        quantity: updated[existingIndex].quantity - 1,
      );
      state = state.copyWith(items: updated);
    } else {
      updated.removeAt(existingIndex);
      if (updated.isEmpty) {
        // EMPTY CART RULE: Reset active shop to null
        state = const CartState();
      } else {
        state = state.copyWith(items: updated);
      }
    }

    _enforceInvariant();
  }

  /// Removes an item completely from the cart.
  void deleteItem(String menuItemId, [String? shopId]) {
    final updated = state.items
        .where((item) =>
            !((shopId == null || item.shopId == shopId) && item.menuItem.id == menuItemId),)
        .toList();
    if (updated.isEmpty) {
      state = const CartState();
    } else {
      state = state.copyWith(items: updated);
    }
    _enforceInvariant();
  }

  /// Updates the quantity of a specific item.
  void updateQuantity(String menuItemId, int quantity, [String? shopId]) {
    if (quantity <= 0) {
      deleteItem(menuItemId, shopId);
      return;
    }

    final existingIndex = state.items.indexWhere(
      (item) => (shopId == null || item.shopId == shopId) && item.menuItem.id == menuItemId,
    );
    if (existingIndex < 0) return;

    final updated = [...state.items];
    updated[existingIndex] = updated[existingIndex].copyWith(
      quantity: quantity,
    );
    state = state.copyWith(items: updated);
    _enforceInvariant();
  }

  /// Clears all items and resets active shop to null.
  void clearCart() {
    state = const CartState();
  }

  /// Internal invariant enforcer to ensure state state consistency.
  void _enforceInvariant() {
    if (state.items.isEmpty) {
      if (state.shopId != null || state.shopName != null) {
        state = const CartState();
      }
    }
  }
}
