// BU Gate2Eat — Data Models
// CartItem & SelectedMenuItemOption models for in-memory cart state

import 'menu_item_model.dart';

/// Immutable snapshot of an option selected by the user for a menu item.
class SelectedMenuItemOption {
  const SelectedMenuItemOption({
    required this.groupId,
    required this.groupName,
    required this.optionId,
    required this.optionName,
    required this.pricingType,
    required this.price,
  });

  final String groupId;
  final String groupName;
  final String optionId;
  final String optionName;
  final OptionPricingType pricingType;
  final int price;

  /// Short display text.
  String get displayText => optionName;

  /// Formatted price or adjustment string.
  String get formattedPriceString =>
      pricingType == OptionPricingType.fixedPrice ? '₹$price' : '+₹$price';

  /// Serializes to a standard Map for order persistence.
  Map<String, dynamic> toMap() {
    return {
      'groupId': groupId,
      'groupName': groupName,
      'optionId': optionId,
      'optionName': optionName,
      'pricingType': pricingType.name,
      'price': price,
    };
  }

  /// Deserializes from Map.
  factory SelectedMenuItemOption.fromMap(Map<String, dynamic> map) {
    return SelectedMenuItemOption(
      groupId: map['groupId'] as String? ?? '',
      groupName: map['groupName'] as String? ?? '',
      optionId: map['optionId'] as String? ?? '',
      optionName: map['optionName'] as String? ?? '',
      pricingType: OptionPricingType.values.firstWhere(
        (e) => e.name == map['pricingType'],
        orElse: () => OptionPricingType.fixedPrice,
      ),
      price: (map['price'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SelectedMenuItemOption &&
          runtimeType == other.runtimeType &&
          groupId == other.groupId &&
          optionId == other.optionId &&
          price == other.price &&
          pricingType == other.pricingType;

  @override
  int get hashCode =>
      groupId.hashCode ^
      optionId.hashCode ^
      price.hashCode ^
      pricingType.hashCode;

  @override
  String toString() => '$groupName: $optionName ($formattedPriceString)';
}

/// Represents an item or custom variant in the user's cart with quantity.
/// Cart is in-memory only — not persisted across app restarts.
class CartItem {
  /// Creates a CartItem instance.
  const CartItem({
    required this.menuItem,
    required this.quantity,
    required this.shopId,
    required this.shopName,
    this.selectedOptions = const [],
    this.unitPriceOverride,
  });

  final MenuItem menuItem;
  final int quantity;
  final String shopId;
  final String shopName;
  final List<SelectedMenuItemOption> selectedOptions;
  final int? unitPriceOverride;

  /// Effective unit price for 1 quantity of this item/variant.
  int get unitPrice => unitPriceOverride ?? menuItem.price;

  /// Total price for this cart item (unitPrice × quantity).
  double get totalPrice => (unitPrice * quantity).toDouble();

  /// Formatted total price string.
  String get formattedTotalPrice => '₹${totalPrice.toStringAsFixed(0)}';

  /// Formatted single unit price string.
  String get formattedUnitPrice => '₹$unitPrice';

  /// True if this cart item has custom options selected.
  bool get hasSelectedOptions => selectedOptions.isNotEmpty;

  /// Human-readable summary of selected options, e.g. "Half · Fried".
  String get optionsDescription {
    if (selectedOptions.isEmpty) return '';
    return selectedOptions.map((o) => o.optionName).join(' · ');
  }

  /// Deterministic unique cart key.
  /// Normal item: "menuItem.id"
  /// Variant item: "menuItem.id|groupId:optionId|groupId:optionId" (sorted deterministically by groupId + optionId)
  String get cartKey => buildCartKey(menuItem.id, selectedOptions);

  /// Static helper to build deterministic cartKey for any menuItem + options.
  static String buildCartKey(
    String menuItemId,
    List<SelectedMenuItemOption> options,
  ) {
    if (options.isEmpty) return menuItemId;

    // Sort deterministically by groupId and optionId so list order does not alter the key
    final sorted = List<SelectedMenuItemOption>.from(options)
      ..sort((a, b) {
        final gComp = a.groupId.compareTo(b.groupId);
        if (gComp != 0) return gComp;
        return a.optionId.compareTo(b.optionId);
      });

    final optionTokens =
        sorted.map((o) => '${o.groupId}:${o.optionId}').join('|');
    return '$menuItemId|$optionTokens';
  }

  /// Creates a copy of this CartItem with updated fields.
  CartItem copyWith({
    MenuItem? menuItem,
    int? quantity,
    String? shopId,
    String? shopName,
    List<SelectedMenuItemOption>? selectedOptions,
    int? unitPriceOverride,
  }) {
    return CartItem(
      menuItem: menuItem ?? this.menuItem,
      quantity: quantity ?? this.quantity,
      shopId: shopId ?? this.shopId,
      shopName: shopName ?? this.shopName,
      selectedOptions: selectedOptions ?? this.selectedOptions,
      unitPriceOverride: unitPriceOverride ?? this.unitPriceOverride,
    );
  }
}
