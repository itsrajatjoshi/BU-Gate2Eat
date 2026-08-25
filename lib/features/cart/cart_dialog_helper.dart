// BU Gate2Eat — Cart Dialog Helper
// Intercepts add-to-cart operations when items belong to a different shop

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../models/cart_item_model.dart';
import '../../models/menu_item_model.dart';
import 'cart_provider.dart';

/// Attempts to add [item] to cart.
/// If the cart already contains items from another shop, presents a confirmation dialog.
/// Returns true if item was successfully added, false if cancelled by user.
Future<bool> tryAddToCart({
  required BuildContext context,
  required WidgetRef ref,
  required MenuItem item,
  required String shopId,
  required String shopName,
  List<SelectedMenuItemOption> selectedOptions = const [],
  int? unitPrice,
}) async {
  final cartNotifier = ref.read(cartProvider.notifier);
  final success = cartNotifier.addItem(
    item,
    shopId,
    shopName,
    selectedOptions: selectedOptions,
    unitPrice: unitPrice,
  );

  if (!success) {
    final currentShopName = ref.read(cartProvider).shopName ?? 'another shop';
    final shouldClearAndAdd = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Replace cart items?',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
            color: Theme.of(ctx).brightness == Brightness.dark
                ? AppColors.darkTextPrimary
                : AppColors.textPrimary,
          ),
        ),
        content: Text(
          'Your cart contains items from $currentShopName.\n\nDo you want to clear your current cart and add this item from $shopName?',
          style: TextStyle(
            fontSize: 14,
            height: 1.4,
            color: Theme.of(ctx).brightness == Brightness.dark
                ? AppColors.darkTextSecondary
                : AppColors.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'KEEP CART',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Theme.of(ctx).brightness == Brightness.dark
                    ? AppColors.darkTextSecondary
                    : AppColors.textSecondary,
              ),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              'CLEAR & ADD',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (shouldClearAndAdd == true) {
      cartNotifier.clearAndAddItem(
        item,
        shopId,
        shopName,
        selectedOptions: selectedOptions,
        unitPrice: unitPrice,
      );
      return true;
    }
    return false;
  }
  return true;
}
