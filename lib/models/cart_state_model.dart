// BU Gate2Eat — Data Models
// CartState model for authoritative single-shop cart management

import 'cart_item_model.dart';

/// Immutable representation of the current shopping cart state.
/// Enforces single-shop cart invariant: cart contains items from ONLY one shop at a time.
class CartState {
  const CartState({
    this.shopId,
    this.shopName,
    this.items = const [],
  });

  /// Authoritative ID of the shop to which this cart belongs. Null if empty.
  final String? shopId;

  /// Authoritative display name of the active shop. Null if empty.
  final String? shopName;

  /// List of cart items belonging exclusively to shopId.
  final List<CartItem> items;

  /// Returns true if cart has no items.
  bool get isEmpty => items.isEmpty;

  /// Returns true if cart has 1 or more items.
  bool get isNotEmpty => items.isNotEmpty;

  /// Returns sum of quantities across all items in cart.
  int get totalItemCount =>
      items.fold<int>(0, (sum, item) => sum + item.quantity);

  /// Returns grand total price of all items in cart.
  double get grandTotal =>
      items.fold<double>(0, (sum, item) => sum + item.totalPrice);

  /// Formatted grand total string.
  String get formattedGrandTotal => '₹${grandTotal.toStringAsFixed(0)}';

  /// Returns quantity of a menu item ONLY if the cart belongs to targetShopId.
  /// Scoped strictly by BOTH shopId AND menuItemId.
  int getQuantityForShop(String targetShopId, String menuItemId) {
    if (isEmpty || shopId != targetShopId) return 0;
    final match = items
        .where((i) => i.shopId == targetShopId && i.menuItem.id == menuItemId)
        .toList();
    return match.fold<int>(0, (sum, i) => sum + i.quantity);
  }

  /// Convenience wrapper requiring currentShopId for safe shop-scoped quantity lookup.
  int getQuantity(String menuItemId, String currentShopId) {
    return getQuantityForShop(currentShopId, menuItemId);
  }

  /// Creates a copy of this CartState with optional updated fields.
  CartState copyWith({
    String? shopId,
    String? shopName,
    List<CartItem>? items,
  }) {
    return CartState(
      shopId: shopId ?? this.shopId,
      shopName: shopName ?? this.shopName,
      items: items ?? this.items,
    );
  }
}
