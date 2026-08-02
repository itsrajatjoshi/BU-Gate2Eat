// BU Gate2Eat — Cart Screen
// Review order, adjust quantities, add special instructions, place order via WhatsApp

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_constants.dart';
import '../../core/providers.dart';
import '../../models/cart_item_model.dart';
import '../../services/whatsapp_service.dart';
import 'cart_provider.dart';

class CartScreen extends ConsumerStatefulWidget {
  const CartScreen({super.key});

  @override
  ConsumerState<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends ConsumerState<CartScreen> {
  final _specialInstructionsController = TextEditingController();

  @override
  void dispose() {
    _specialInstructionsController.dispose();
    super.dispose();
  }

  Future<void> _placeOrder() async {
    final cartItems = ref.read(cartProvider);
    if (cartItems.isEmpty) return;

    final localStorage = ref.read(localStorageServiceProvider);
    final shopName = cartItems.first.shopName;

    // Find the shop's WhatsApp number
    final firestoreService = ref.read(firestoreServiceProvider);
    final shop = await firestoreService.getShop(cartItems.first.shopId);
    if (shop == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Shop not found')),
        );
      }
      return;
    }

    // Generate the message
    final message = WhatsAppService.generateOrderMessage(
      shopName: shopName,
      userName: localStorage.userName,
      userPhone: localStorage.userPhone,
      cartItems: cartItems,
      specialInstructions: _specialInstructionsController.text,
    );

    // Launch WhatsApp
    final success = await WhatsAppService.launchWhatsApp(
      whatsappNumber: shop.whatsappNumber,
      message: message,
    );

    if (!success && mounted) {
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('WhatsApp Not Found'),
          content: const Text(
            'Please install WhatsApp to place orders.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cartItems = ref.watch(cartProvider);
    final cartNotifier = ref.read(cartProvider.notifier);

    final grandTotal =
        cartItems.fold<double>(0, (sum, item) => sum + item.totalPrice);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Your Cart'),
        actions: [
          if (cartItems.isNotEmpty)
            TextButton(
              onPressed: () {
                cartNotifier.clearCart();
              },
              child: const Text('Clear'),
            ),
        ],
      ),
      body: cartItems.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.shopping_cart_outlined,
                    size: 64,
                    color: AppColors.textHint,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'Your cart is empty',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Browse shops and add items to get started',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.textHint,
                        ),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                // Shop name header
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.md),
                  color: AppColors.primary.withValues(alpha: 0.05),
                  child: Text(
                    'Ordering from ${cartItems.first.shopName}',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: AppColors.primary,
                        ),
                  ),
                ),

                // Cart items list
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    itemCount: cartItems.length + 1, // +1 for special instructions
                    itemBuilder: (context, index) {
                      if (index < cartItems.length) {
                        final item = cartItems[index];
                        return _CartItemTile(
                          item: item,
                          onIncrement: () =>
                              cartNotifier.addItem(item.menuItem, item.shopId, item.shopName),
                          onDecrement: () =>
                              cartNotifier.removeItem(item.menuItem.id),
                          onDelete: () =>
                              cartNotifier.deleteItem(item.menuItem.id),
                        );
                      }

                      // Special instructions field
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: AppSpacing.md),
                          Text(
                            'Special Instructions (optional)',
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          TextField(
                            controller: _specialInstructionsController,
                            maxLines: 2,
                            maxLength: AppConfig.maxSpecialInstructionsLength,
                            decoration: const InputDecoration(
                              hintText: 'e.g., Extra spicy, No onion...',
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),

                // Bottom bar with total and place order
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 10,
                        offset: const Offset(0, -2),
                      ),
                    ],
                  ),
                  child: SafeArea(
                    child: Row(
                      children: [
                        // Total
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Total',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: AppColors.textSecondary),
                            ),
                            Text(
                              '₹${grandTotal.toStringAsFixed(0)}',
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineMedium
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const SizedBox(width: AppSpacing.lg),

                        // Place Order button
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _placeOrder,
                            icon: const Icon(Icons.send_rounded,
                                color: Colors.white),
                            label: const Text('Place Order'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

/// A single cart item row with quantity controls and swipe-to-delete.
class _CartItemTile extends StatelessWidget {
  final CartItem item;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final VoidCallback onDelete;

  const _CartItemTile({
    required this.item,
    required this.onIncrement,
    required this.onDecrement,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey(item.menuItem.id),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onDelete(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: AppSpacing.lg),
        color: AppColors.error,
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      child: Card(
        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              // Veg/Non-Veg indicator
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: item.menuItem.isVeg
                        ? AppColors.vegGreen
                        : AppColors.nonVegRed,
                    width: 2,
                  ),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Center(
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: item.menuItem.isVeg
                          ? AppColors.vegGreen
                          : AppColors.nonVegRed,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),

              // Item name and price
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.menuItem.name,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      item.formattedTotalPrice,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ],
                ),
              ),

              // Quantity controls
              Container(
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove,
                          size: 18, color: AppColors.primary),
                      constraints:
                          const BoxConstraints(minWidth: 32, minHeight: 32),
                      padding: EdgeInsets.zero,
                      onPressed: onDecrement,
                    ),
                    Text(
                      '${item.quantity}',
                      style:
                          Theme.of(context).textTheme.titleMedium?.copyWith(
                                color: AppColors.primary,
                                fontWeight: FontWeight.bold,
                              ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add,
                          size: 18, color: AppColors.primary),
                      constraints:
                          const BoxConstraints(minWidth: 32, minHeight: 32),
                      padding: EdgeInsets.zero,
                      onPressed: onIncrement,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
