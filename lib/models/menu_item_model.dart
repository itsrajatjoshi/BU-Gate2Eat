// BU Gate2Eat — Data Models
// MenuItem model for individual food items with universal options & variations support

import 'package:cloud_firestore/cloud_firestore.dart';

/// Specifies how an individual option affects the total item price.
enum OptionPricingType {
  /// Option specifies a full fixed price for the portion/size (e.g. Half = ₹80, Full = ₹140).
  fixedPrice,

  /// Option specifies an additional surcharge or adjustment on top of the base price (e.g. Fried = +₹20, With Ice Cream = +₹10).
  priceAdjustment,

  /// Option is purely a selection without any price impact (e.g. Dry, Gravy, Regular Crust).
  selectionOnly,
}

/// Defines the behavior, selection rules, and pricing structure for an entire option group.
enum OptionGroupType {
  /// Exactly one option is required. Options specify full fixed prices for the variant (e.g. Size: Large ₹70, XL ₹90).
  fixed,

  /// Exactly one option must be selected. Choices have zero price impact (e.g. Sauce: With Sauce, Without Sauce).
  choice,

  /// Optional choices (0 or 1 selection). Each option adds a price surcharge (e.g. Extras: Cheese +₹10, Extra Patty +₹30).
  extra,
}

/// Represents an individual selectable choice within an option group.
/// (e.g., "Half" ₹80, "Full" ₹140, "XL" ₹130, "Fried" +₹20, "Dry" selectionOnly).
class MenuItemOption {
  const MenuItemOption({
    required this.id,
    required this.name,
    this.price = 0,
    this.pricingType = OptionPricingType.fixedPrice,
    this.isDefault = false,
  });

  /// Unique identifier for this option within the group (e.g., 'opt_half', 'opt_full').
  final String id;

  /// Human-readable label (e.g., 'Half', 'Full', 'Regular', 'Large', 'Dry', 'Gravy', 'Fried').
  final String name;

  /// Price value:
  /// - If [pricingType] is [OptionPricingType.fixedPrice]: The complete price for this option (e.g. 80).
  /// - If [pricingType] is [OptionPricingType.priceAdjustment]: Surcharge added to base price (e.g. 20).
  /// - If [pricingType] is [OptionPricingType.selectionOnly]: Always 0.
  final int price;

  /// How this price is applied.
  final OptionPricingType pricingType;

  /// Whether this option is selected by default when the modal opens.
  final bool isDefault;

  /// Converts this option to a Firestore/JSON compatible map.
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'price': pricingType == OptionPricingType.selectionOnly ? 0 : price,
      'pricingType': pricingType.name,
      'isDefault': isDefault,
    };
  }

  /// Deserializes option safely from a map, falling back to safe defaults if fields are missing.
  factory MenuItemOption.fromMap(Map<String, dynamic> map) {
    final pricingTypeStr = map['pricingType'] as String?;
    final pricingType = OptionPricingType.values.firstWhere(
      (e) => e.name == pricingTypeStr,
      orElse: () => OptionPricingType.fixedPrice,
    );

    return MenuItemOption(
      id: (map['id'] as String?) ?? '',
      name: (map['name'] as String?) ?? '',
      price: pricingType == OptionPricingType.selectionOnly
          ? 0
          : ((map['price'] as num?) ?? 0).toInt(),
      pricingType: pricingType,
      isDefault: (map['isDefault'] as bool?) ?? false,
    );
  }
}

/// Represents a collection of related choices for a menu item.
/// (e.g. "Portion", "Size", "Preparation", "Flavour").
class MenuItemOptionGroup {
  const MenuItemOptionGroup({
    required this.id,
    required this.name,
    required this.options,
    this.required = true,
    this.groupType = OptionGroupType.fixed,
  });

  /// Unique identifier for this group (e.g., 'grp_portion', 'grp_size').
  final String id;

  /// Group title displayed to user (e.g., 'Choose Portion', 'Choose Size', 'Choose Preparation').
  final String name;

  /// The list of choices available in this group.
  final List<MenuItemOption> options;

  /// Whether the customer is required to make a selection from this group before adding to cart.
  /// (Fixed & Choice are required by default; Extra is optional by default).
  final bool required;

  /// Group-level pricing & selection type: [OptionGroupType.fixed], [OptionGroupType.choice], or [OptionGroupType.extra].
  final OptionGroupType groupType;

  /// Converts this option group to a Firestore/JSON compatible map.
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'required': required,
      'groupType': groupType.name,
      'options': options.map((o) => o.toMap()).toList(),
    };
  }

  /// Deserializes an option group safely from a map with backward-compatible legacy inference.
  factory MenuItemOptionGroup.fromMap(Map<String, dynamic> map) {
    final rawOptions = map['options'];
    final optionsList = <MenuItemOption>[];
    if (rawOptions is List) {
      for (final item in rawOptions) {
        if (item is Map<String, dynamic>) {
          optionsList.add(MenuItemOption.fromMap(item));
        } else if (item is Map) {
          optionsList.add(MenuItemOption.fromMap(Map<String, dynamic>.from(item)));
        }
      }
    }

    // 1. If explicit 'groupType' exists in map, use it
    OptionGroupType groupType;
    final groupTypeStr = map['groupType'] as String?;
    if (groupTypeStr != null && groupTypeStr.isNotEmpty) {
      groupType = OptionGroupType.values.firstWhere(
        (e) => e.name == groupTypeStr,
        orElse: () => OptionGroupType.fixed,
      );
    } else {
      // 2. Safe backward-compatible legacy inference:
      // - If any fixedPrice option exists -> fixed
      // - Else if any priceAdjustment option exists -> extra
      // - Else -> choice
      if (optionsList.any((o) => o.pricingType == OptionPricingType.fixedPrice)) {
        groupType = OptionGroupType.fixed;
      } else if (optionsList.any((o) => o.pricingType == OptionPricingType.priceAdjustment)) {
        groupType = OptionGroupType.extra;
      } else {
        groupType = OptionGroupType.choice;
      }
    }

    final bool isRequired = (map['required'] as bool?) ?? (groupType != OptionGroupType.extra);

    return MenuItemOptionGroup(
      id: (map['id'] as String?) ?? '',
      name: (map['name'] as String?) ?? '',
      required: isRequired,
      groupType: groupType,
      options: optionsList,
    );
  }
}

/// Represents a single menu item within a shop.
class MenuItem {
  /// Creates a MenuItem instance.
  /// [optionGroups] defaults to empty list [const []] for complete backward compatibility.
  const MenuItem({
    required this.id,
    required this.name,
    required this.details,
    required this.price,
    required this.imageUrl,
    required this.categoryId,
    required this.isVeg,
    required this.isAvailable,
    required this.isRecommended,
    required this.sortOrder,
    this.optionGroups = const [],
  });

  /// Creates a MenuItem from a Firestore document snapshot.
  /// Fully backward-compatible with legacy Firestore documents that do not contain optionGroups.
  factory MenuItem.fromFirestore(DocumentSnapshot doc) {
    final data = (doc.data() as Map<String, dynamic>?) ?? {};

    final rawGroups = data['optionGroups'];
    final groupsList = <MenuItemOptionGroup>[];
    if (rawGroups is List) {
      for (final g in rawGroups) {
        if (g is Map<String, dynamic>) {
          groupsList.add(MenuItemOptionGroup.fromMap(g));
        } else if (g is Map) {
          groupsList.add(MenuItemOptionGroup.fromMap(Map<String, dynamic>.from(g)));
        }
      }
    }

    return MenuItem(
      id: doc.id,
      name: (data['name'] as String?) ?? '',
      details: (data['details'] as String?) ?? (data['description'] as String?) ?? '',
      price: ((data['price'] as num?) ?? 0).toInt(),
      imageUrl: (data['imageUrl'] as String?) ?? '',
      categoryId: (data['categoryId'] as String?) ?? '',
      isVeg: (data['isVeg'] as bool?) ?? true,
      isAvailable: (data['isAvailable'] as bool?) ?? true,
      isRecommended: (data['isRecommended'] as bool?) ?? false,
      sortOrder: (data['sortOrder'] as int?) ?? 0,
      optionGroups: groupsList,
    );
  }

  final String id;
  final String name;
  final String details;
  final int price;
  final String imageUrl;
  final String categoryId;
  final bool isVeg;
  final bool isAvailable;
  final bool isRecommended;
  final int sortOrder;

  /// Optional list of variation/option groups (e.g. Portion, Size, Preparation).
  /// If empty, this is a standard simple item that adds directly to cart.
  final List<MenuItemOptionGroup> optionGroups;

  /// Single source of truth: Item has options if and only if optionGroups is not empty.
  bool get hasOptions => optionGroups.isNotEmpty;

  /// Calculates the minimum valid starting price representing the lowest purchasable configuration.
  /// - If [hasOptions] is false: returns the base [price].
  /// - If [hasOptions] is true: safely sums the minimum price from each fixed group + non-negative adjustments.
  int get startingPrice {
    if (!hasOptions) return price;

    int baseConfigurationPrice = 0;
    bool hasAnyFixedGroup = false;

    // 1. Accumulate minimum prices from fixed-price option groups and required adjustment groups
    for (final group in optionGroups) {
      final fixedOptions = group.options
          .where((o) => o.pricingType == OptionPricingType.fixedPrice && o.price > 0)
          .toList();

      if (fixedOptions.isNotEmpty) {
        hasAnyFixedGroup = true;
        final minFixedInGroup = fixedOptions
            .map((o) => o.price)
            .reduce((a, b) => a < b ? a : b);
        baseConfigurationPrice += minFixedInGroup;
      } else if (group.required) {
        final adjustments = group.options
            .where((o) => o.pricingType == OptionPricingType.priceAdjustment)
            .map((o) => o.price)
            .toList();
        if (adjustments.isNotEmpty) {
          final minAdj = adjustments.reduce((a, b) => a < b ? a : b);
          if (minAdj > 0) {
            baseConfigurationPrice += minAdj;
          }
        }
      }
    }

    // 2. If no fixed-price group exists, use base price + required adjustments
    if (!hasAnyFixedGroup) {
      baseConfigurationPrice = price;
      for (final group in optionGroups) {
        if (group.required) {
          final adjustments = group.options
              .where((o) => o.pricingType == OptionPricingType.priceAdjustment)
              .map((o) => o.price)
              .toList();
          if (adjustments.isNotEmpty) {
            final minAdj = adjustments.reduce((a, b) => a < b ? a : b);
            if (minAdj > 0) {
              baseConfigurationPrice += minAdj;
            }
          }
        }
      }
    }

    // 3. Conservative fallback if calculated price is not strictly positive
    if (baseConfigurationPrice <= 0) {
      return price > 0 ? price : 0;
    }

    return baseConfigurationPrice;
  }

  /// Formatted price string with rupee symbol.
  String get formattedPrice => '₹$price';

  /// Formatted starting price for menu cards.
  /// Example: "Starting from ₹80" for option items, "₹50" for normal items.
  String get formattedStartingPrice =>
      hasOptions ? 'Starting from ₹$startingPrice' : formattedPrice;

  /// Converts MenuItem to a Firestore-compatible map.
  /// Only writes 'optionGroups' when options actually exist to preserve clean documents for normal items.
  Map<String, dynamic> toFirestore() {
    final map = <String, dynamic>{
      'name': name,
      'details': details,
      'price': price,
      'imageUrl': imageUrl,
      'categoryId': categoryId,
      'isVeg': isVeg,
      'isAvailable': isAvailable,
      'isRecommended': isRecommended,
      'sortOrder': sortOrder,
    };

    if (optionGroups.isNotEmpty) {
      map['optionGroups'] = optionGroups.map((g) => g.toMap()).toList();
    }

    return map;
  }
}
