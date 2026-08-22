// BU Gate2Eat — Features
// Reorder Helper (Resolves current live menu prices/availability and populates Cart)

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_constants.dart';
import '../../core/providers.dart';
import '../../core/router.dart';
import '../../models/menu_item_model.dart';
import '../../models/order_model.dart';
import '../cart/cart_provider.dart';

class ReorderHelper {
  const ReorderHelper._();

  /// Executes the Reorder flow for a delivered order.
  /// Validates items against current shop menu, handles cross-shop cart conflict,
  /// and opens Cart Screen for manual user review & order placement.
  static Future<void> handleReorder({
    required BuildContext context,
    required WidgetRef ref,
    required AppOrder order,
  }) async {
    // 1. Fetch current live menu for order.shopId
    final firestoreService = ref.read(firestoreServiceProvider);
    final currentMenu = await firestoreService.getMenuItems(order.shopId);

    // 2. Map previous order items to current live available items
    final List<({MenuItem item, int quantity})> availableItems = [];
    int unavailableCount = 0;

    for (final orderItem in order.items) {
      final matchingItem = currentMenu.firstWhere(
        (m) => m.id == orderItem.menuItemId,
        orElse: () => const MenuItem(
          id: '',
          name: '',
          price: 0,
          details: '',
          imageUrl: '',
          isVeg: true,
          isAvailable: false,
          isRecommended: false,
          categoryId: '',
          sortOrder: 0,
        ),
      );

      if (matchingItem.id.isNotEmpty && matchingItem.isAvailable) {
        // Use current live menu item (with current price) and previous order's quantity
        availableItems.add((item: matchingItem, quantity: orderItem.quantity));
      } else {
        unavailableCount++;
      }
    }

    if (!context.mounted) return;

    // 3. If NONE of the items are currently available
    if (availableItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'None of the previous items are currently available.',
          ),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
      return;
    }

    // 4. Check single-shop cart conflict
    final cartState = ref.read(cartProvider);
    final hasConflict = cartState.isNotEmpty &&
        cartState.shopId != null &&
        cartState.shopId != order.shopId;

    if (hasConflict) {
      final shouldReplace = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text(
            'Replace cart items?',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: Text(
            'Your cart already contains items from ${cartState.shopName ?? "another shop"}. Replace it with this order from ${order.shopName}?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text('Replace Cart'),
            ),
          ],
        ),
      );

      if (shouldReplace != true || !context.mounted) return;

      ref.read(cartProvider.notifier).addMultipleItems(
            availableItems,
            order.shopId,
            order.shopName,
            clearExisting: true,
          );
    } else {
      ref.read(cartProvider.notifier).addMultipleItems(
            availableItems,
            order.shopId,
            order.shopName,
            clearExisting: false,
          );
    }

    if (!context.mounted) return;

    // 5. If some items were skipped, show warning feedback
    if (unavailableCount > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            unavailableCount == 1
                ? '1 item is no longer available and was skipped.'
                : '$unavailableCount items are no longer available and were skipped.',
          ),
          backgroundColor: const Color(0xFFE58500),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    }

    // 6. Navigate to Cart Screen for review & manual order placement
    context.push(AppRoutes.cart);
  }
}
