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

  /// Adds an item or variant to the cart or increments quantity if from the same shop.
  /// If from a different shop, returns false (signaling shop conflict requiring dialog).
  bool addItem(
    MenuItem menuItem,
    String shopId,
    String shopName, {
    List<SelectedMenuItemOption> selectedOptions = const [],
    int? unitPrice,
  }) {
    // Single-Shop Invariant Check
    if (state.isNotEmpty && state.shopId != null && state.shopId != shopId) {
      return false; // Conflict! UI must prompt for clear & add.
    }

    final targetKey = CartItem.buildCartKey(menuItem.id, selectedOptions);

    final existingIndex = state.items.indexWhere(
      (item) => item.shopId == shopId && item.cartKey == targetKey,
    );

    if (existingIndex >= 0) {
      // Increment quantity for the exact matching variant/item
      final updated = [...state.items];
      updated[existingIndex] = updated[existingIndex].copyWith(
        quantity: updated[existingIndex].quantity + 1,
      );
      state = state.copyWith(items: updated);
    } else {
      // Add new variant/item line
      final newItem = CartItem(
        menuItem: menuItem,
        quantity: 1,
        shopId: shopId,
        shopName: shopName,
        selectedOptions: List.unmodifiable(selectedOptions),
        unitPriceOverride: unitPrice,
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

  /// Atomically clears existing cart items and adds a new item/variant from new shop.
  void clearAndAddItem(
    MenuItem menuItem,
    String shopId,
    String shopName, {
    List<SelectedMenuItemOption> selectedOptions = const [],
    int? unitPrice,
  }) {
    state = CartState(
      shopId: shopId,
      shopName: shopName,
      items: [
        CartItem(
          menuItem: menuItem,
          quantity: 1,
          shopId: shopId,
          shopName: shopName,
          selectedOptions: List.unmodifiable(selectedOptions),
          unitPriceOverride: unitPrice,
        ),
      ],
    );
    _enforceInvariant();
  }

  /// Adds multiple items to the cart (for Reorder flow).
  /// Merges quantities for existing items/variants in the same shop, or replaces if clearExisting is true.
  void addMultipleItems(
    List<({
      MenuItem item,
      int quantity,
      List<SelectedMenuItemOption> selectedOptions,
      int? unitPrice,
    })> itemsToAdd,
    String shopId,
    String shopName, {
    bool clearExisting = false,
  }) {
    if (itemsToAdd.isEmpty) return;

    if (clearExisting || state.isEmpty || state.shopId != shopId) {
      state = CartState(
        shopId: shopId,
        shopName: shopName,
        items: itemsToAdd
            .map((entry) => CartItem(
                  menuItem: entry.item,
                  quantity: entry.quantity,
                  shopId: shopId,
                  shopName: shopName,
                  selectedOptions: List.unmodifiable(entry.selectedOptions),
                  unitPriceOverride: entry.unitPrice,
                ))
            .toList(),
      );
    } else {
      // Merge with existing items
      final currentList = [...state.items];
      for (final entry in itemsToAdd) {
        final targetKey = CartItem.buildCartKey(entry.item.id, entry.selectedOptions);
        final idx = currentList.indexWhere(
          (ci) => ci.cartKey == targetKey && ci.shopId == shopId,
        );
        if (idx >= 0) {
          currentList[idx] = currentList[idx].copyWith(
            quantity: currentList[idx].quantity + entry.quantity,
          );
        } else {
          currentList.add(
            CartItem(
              menuItem: entry.item,
              quantity: entry.quantity,
              shopId: shopId,
              shopName: shopName,
              selectedOptions: List.unmodifiable(entry.selectedOptions),
              unitPriceOverride: entry.unitPrice,
            ),
          );
        }
      }
      state = state.copyWith(items: currentList);
    }
    _enforceInvariant();
  }

  /// Decrements quantity or removes item completely if quantity becomes 0.
  /// Matches by cartKey first, or by menuItem.id as fallback for backward compatibility.
  void removeItem(String cartKeyOrMenuItemId, [String? shopId]) {
    final existingIndex = state.items.indexWhere(
      (item) =>
          (shopId == null || item.shopId == shopId) &&
          (item.cartKey == cartKeyOrMenuItemId ||
              item.menuItem.id == cartKeyOrMenuItemId),
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
        // EMPTY CART RULE: Reset active shop and special instructions
        state = const CartState();
      } else {
        // Removing a cart item clears stale instructions so it never leaks across remaining items
        state = state.copyWith(items: updated, specialInstructions: '');
      }
    }

    _enforceInvariant();
  }

  /// Removes an item or variant completely from the cart.
  /// Matches by cartKey first, or by menuItem.id as fallback for backward compatibility.
  void deleteItem(String cartKeyOrMenuItemId, [String? shopId]) {
    final updated = state.items
        .where(
          (item) => !(
              (shopId == null || item.shopId == shopId) &&
              (item.cartKey == cartKeyOrMenuItemId ||
                  item.menuItem.id == cartKeyOrMenuItemId)
          ),
        )
        .toList();
    if (updated.isEmpty) {
      state = const CartState();
    } else {
      // Removing a cart item clears stale instructions so it never leaks across remaining items
      state = state.copyWith(items: updated, specialInstructions: '');
    }
    _enforceInvariant();
  }

  /// Updates the quantity of a specific item or variant.
  void updateQuantity(String cartKeyOrMenuItemId, int quantity, [String? shopId]) {
    if (quantity <= 0) {
      deleteItem(cartKeyOrMenuItemId, shopId);
      return;
    }

    final existingIndex = state.items.indexWhere(
      (item) =>
          (shopId == null || item.shopId == shopId) &&
          (item.cartKey == cartKeyOrMenuItemId ||
              item.menuItem.id == cartKeyOrMenuItemId),
    );
    if (existingIndex < 0) return;

    final updated = [...state.items];
    updated[existingIndex] = updated[existingIndex].copyWith(
      quantity: quantity,
    );
    state = state.copyWith(items: updated);
    _enforceInvariant();
  }

  /// Updates the special instructions / notes for the active cart draft.
  void setSpecialInstructions(String instructions) {
    state = state.copyWith(specialInstructions: instructions);
  }

  /// Clears all items, special instructions, and resets active shop to null.
  void clearCart() {
    state = const CartState();
  }

  /// Internal invariant enforcer to ensure state consistency.
  void _enforceInvariant() {
    if (state.items.isEmpty) {
      if (state.shopId != null || state.shopName != null || state.specialInstructions.isNotEmpty) {
        state = const CartState();
      }
    }
  }
}
