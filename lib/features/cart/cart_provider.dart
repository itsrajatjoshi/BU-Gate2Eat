// BU Gate2Eat — Cart Provider
// Riverpod state management for the shopping cart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/cart_item_model.dart';
import '../../models/menu_item_model.dart';

/// Provider for the cart state. Cart is in-memory only.
final cartProvider =
    StateNotifierProvider<CartNotifier, List<CartItem>>((ref) {
  return CartNotifier();
});

/// Manages the cart state — add, remove, update, clear.
class CartNotifier extends StateNotifier<List<CartItem>> {
  CartNotifier() : super([]);

  /// Adds an item to the cart or increments quantity if already present.
  void addItem(MenuItem menuItem, String shopId, String shopName) {
    final existingIndex =
        state.indexWhere((item) => item.menuItem.id == menuItem.id);

    if (existingIndex >= 0) {
      // Increment quantity
      final updated = [...state];
      updated[existingIndex] = updated[existingIndex].copyWith(
        quantity: updated[existingIndex].quantity + 1,
      );
      state = updated;
    } else {
      // Add new item
      state = [
        ...state,
        CartItem(
          menuItem: menuItem,
          quantity: 1,
          shopId: shopId,
          shopName: shopName,
        ),
      ];
    }
  }

  /// Decrements quantity or removes item if quantity reaches 0.
  void removeItem(String menuItemId) {
    final existingIndex =
        state.indexWhere((item) => item.menuItem.id == menuItemId);

    if (existingIndex < 0) return;

    final updated = [...state];
    if (updated[existingIndex].quantity > 1) {
      updated[existingIndex] = updated[existingIndex].copyWith(
        quantity: updated[existingIndex].quantity - 1,
      );
      state = updated;
    } else {
      updated.removeAt(existingIndex);
      state = updated;
    }
  }

  /// Removes an item completely from the cart.
  void deleteItem(String menuItemId) {
    state = state.where((item) => item.menuItem.id != menuItemId).toList();
  }

  /// Updates the quantity of a specific item.
  void updateQuantity(String menuItemId, int quantity) {
    if (quantity <= 0) {
      deleteItem(menuItemId);
      return;
    }

    final existingIndex =
        state.indexWhere((item) => item.menuItem.id == menuItemId);
    if (existingIndex < 0) return;

    final updated = [...state];
    updated[existingIndex] = updated[existingIndex].copyWith(
      quantity: quantity,
    );
    state = updated;
  }

  /// Clears all items from the cart.
  void clearCart() {
    state = [];
  }

  /// Returns the grand total of all items in the cart.
  double get grandTotal =>
      state.fold<double>(0, (sum, item) => sum + item.totalPrice);

  /// Returns the total number of items (sum of quantities).
  int get totalItemCount =>
      state.fold<int>(0, (sum, item) => sum + item.quantity);
}
