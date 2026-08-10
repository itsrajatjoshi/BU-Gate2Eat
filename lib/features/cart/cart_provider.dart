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

    final existingIndex =
        state.items.indexWhere((item) => item.menuItem.id == menuItem.id);

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
  void removeItem(String menuItemId) {
    final existingIndex =
        state.items.indexWhere((item) => item.menuItem.id == menuItemId);

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
  void deleteItem(String menuItemId) {
    final updated =
        state.items.where((item) => item.menuItem.id != menuItemId).toList();
    if (updated.isEmpty) {
      state = const CartState();
    } else {
      state = state.copyWith(items: updated);
    }
    _enforceInvariant();
  }

  /// Updates the quantity of a specific item.
  void updateQuantity(String menuItemId, int quantity) {
    if (quantity <= 0) {
      deleteItem(menuItemId);
      return;
    }

    final existingIndex =
        state.items.indexWhere((item) => item.menuItem.id == menuItemId);
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

  /// Safety guard: Enforces strict single-shop invariant.
  void _enforceInvariant() {
    if (state.isEmpty) {
      if (state.shopId != null || state.shopName != null) {
        state = const CartState();
      }
      return;
    }

    final activeShopId = state.shopId;
    if (activeShopId != null) {
      final validItems =
          state.items.where((i) => i.shopId == activeShopId).toList();
      if (validItems.length != state.items.length) {
        if (validItems.isEmpty) {
          state = const CartState();
        } else {
          state = state.copyWith(items: validItems);
        }
      }
    }
  }

  /// Helper getters for backwards compatibility
  List<CartItem> get items => state.items;
  double get grandTotal => state.grandTotal;
  int get totalItemCount => state.totalItemCount;
}
