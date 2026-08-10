// BU Gate2Eat — Cart Dialog Helper
// Intercepts add-to-cart operations when items belong to a different shop

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/menu_item_model.dart';
import 'cart_provider.dart';

/// Attempts to add [item] to cart.
/// If the cart already contains items from another shop, presents a confirmation dialog.
Future<void> tryAddToCart({
  required BuildContext context,
  required WidgetRef ref,
  required MenuItem item,
  required String shopId,
  required String shopName,
}) async {
  final cartNotifier = ref.read(cartProvider.notifier);
  final success = cartNotifier.addItem(item, shopId, shopName);

  if (!success) {
    final currentShopName = ref.read(cartProvider).shopName ?? 'another shop';
    final shouldClearAndAdd = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Replace cart items?',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        content: Text(
          'Your cart contains items from $currentShopName.\n\nDo you want to clear your current cart and add this item from $shopName?',
          style: const TextStyle(fontSize: 14, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text(
              'KEEP CART',
              style: TextStyle(fontWeight: FontWeight.w600, color: Colors.grey),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF5C59E5),
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
      cartNotifier.clearAndAddItem(item, shopId, shopName);
    }
  }
}
