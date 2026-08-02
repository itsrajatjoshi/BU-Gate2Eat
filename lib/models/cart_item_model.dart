// BU Gate2Eat — Data Models
// CartItem model for in-memory cart state

import 'menu_item_model.dart';

/// Represents an item in the user's cart with quantity.
/// Cart is in-memory only — not persisted across app restarts.
class CartItem {
  /// Creates a CartItem instance.
  const CartItem({
    required this.menuItem,
    required this.quantity,
    required this.shopId,
    required this.shopName,
  });

  final MenuItem menuItem;
  final int quantity;
  final String shopId;
  final String shopName;

  /// Total price for this cart item (price × quantity).
  double get totalPrice => menuItem.price * quantity;

  /// Formatted total price string.
  String get formattedTotalPrice => '₹${totalPrice.toStringAsFixed(0)}';

  /// Creates a copy of this CartItem with updated fields.
  CartItem copyWith({
    MenuItem? menuItem,
    int? quantity,
    String? shopId,
    String? shopName,
  }) {
    return CartItem(
      menuItem: menuItem ?? this.menuItem,
      quantity: quantity ?? this.quantity,
      shopId: shopId ?? this.shopId,
      shopName: shopName ?? this.shopName,
    );
  }
}
