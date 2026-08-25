// BU Gate2Eat — Cart Screen
// Redesigned to match premium order overview design reference
// Resolves live backend/Firestore menu item images dynamically.
// Bill summary & Place Order button pinned safely at bottom via bottomNavigationBar + SafeArea.

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_constants.dart';
import '../../core/providers.dart';
import '../../models/cart_item_model.dart';
import '../../models/menu_item_model.dart';
import '../../models/order_model.dart';
import '../../services/whatsapp_service.dart';
import 'cart_provider.dart';
import 'widgets/minimum_order_progress_bar.dart';

class CartScreen extends ConsumerStatefulWidget {
  const CartScreen({super.key});

  @override
  ConsumerState<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends ConsumerState<CartScreen> {
  final _specialInstructionsController = TextEditingController();
  bool _isPlacingOrder = false;

  @override
  void dispose() {
    _specialInstructionsController.dispose();
    super.dispose();
  }

  String _generateOrderId() {
    final now = DateTime.now();
    final timeSuffix =
        '${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
    final dateSuffix =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    final microSuffix = (now.microsecond % 1000).toString().padLeft(3, '0');
    return 'YB-$dateSuffix-$timeSuffix-$microSuffix';
  }

  Future<void> _placeAppOrder() async {
    if (_isPlacingOrder) return;

    final cartState = ref.read(cartProvider);
    final cartItems = cartState.items;
    if (cartItems.isEmpty) return;

    final shopName = cartState.shopName ?? cartItems.first.shopName;
    final grandTotal = cartState.grandTotal;
    final shopId = cartState.shopId ?? cartItems.first.shopId;

    // Check Minimum Order Amount (source of truth: Firestore shop document)
    final currentShop = ref
        .read(shopsProvider)
        .valueOrNull
        ?.where((s) => s.id == shopId)
        .firstOrNull;
    final minOrderAmount = currentShop?.minimumOrderAmount ?? 0;
    if (minOrderAmount > 0 && grandTotal < minOrderAmount) {
      final diff = (minOrderAmount - grandTotal).ceil();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  color: Colors.white,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Minimum order amount for $shopName is ₹$minOrderAmount. Add ₹$diff more to order.',
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
      return;
    }

    // 1. Show Confirmation Dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Confirm Order',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Confirm order from $shopName for ₹${grandTotal.toStringAsFixed(0)}?',
          style: const TextStyle(fontSize: 14.5),
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
            child: const Text('Confirm'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isPlacingOrder = true);

    try {
      final localStorage = ref.read(localStorageServiceProvider);
      final customerIdentity = ref.read(customerIdentityProvider);
      final firestoreService = ref.read(firestoreServiceProvider);
      final shop = await firestoreService.getShop(shopId);
      final deliveryNote = (shop != null && shop.deliveryNote.trim().isNotEmpty)
          ? shop.deliveryNote.trim()
          : 'Bennett University • Gate No. 2';

      final now = DateTime.now();
      final orderId = _generateOrderId();

      final customerName = customerIdentity.name.trim().isNotEmpty
          ? customerIdentity.name.trim()
          : (localStorage.userName.isNotEmpty
              ? localStorage.userName
              : 'Student');
      final customerPhone = customerIdentity.phone.trim().isNotEmpty
          ? customerIdentity.phone.trim()
          : localStorage.userPhone;

      // 2. Build immutable Order Snapshot
      final newOrder = AppOrder(
        orderId: orderId,
        shopId: shopId,
        shopName: shopName,
        customerId: customerIdentity.customerId,
        customerName: customerName,
        customerPhone: customerPhone,
        items: cartItems
            .map((ci) => OrderItem(
                  menuItemId: ci.menuItem.id,
                  name: ci.menuItem.name,
                  price: ci.menuItem.price,
                  quantity: ci.quantity,
                  imageUrl: ci.menuItem.imageUrl,
                ))
            .toList(),
        totalAmount: grandTotal,
        specialInstructions: _specialInstructionsController.text.trim(),
        deliveryNote: deliveryNote,
        status: 'placed',
        createdAt: now,
      );

      // 3. Create real Firestore order document
      await ref.read(orderServiceProvider).createOrder(newOrder);

      // 4. Temporary UI bridge: update local dummy state so existing screens reflect it
      ref.read(dummyOrdersProvider.notifier).addOrder(newOrder);

      // 5. Clear Cart ONLY after Firestore confirmation
      ref.read(cartProvider.notifier).clearCart();

      // 6. Navigate to Order Detail Screen
      if (mounted) {
        context.push(
          '/order/$orderId',
          extra: newOrder,
        );
      }
    } catch (e) {
      debugPrint('❌ In-App Order placement error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(
                  Icons.error_outline_rounded,
                  color: Colors.white,
                  size: 20,
                ),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Failed to place order. Please check your connection and try again.',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isPlacingOrder = false);
      }
    }
  }

  Future<void> _placeWhatsAppOrder() async {
    if (_isPlacingOrder) return;
    final cartState = ref.read(cartProvider);
    final cartItems = cartState.items;
    if (cartItems.isEmpty) return;

    final shopName = cartState.shopName ?? cartItems.first.shopName;
    final grandTotal = cartState.grandTotal;
    final shopId = cartState.shopId ?? cartItems.first.shopId;

    // Check Minimum Order Amount (source of truth: Firestore shop document)
    final currentShop = ref
        .read(shopsProvider)
        .valueOrNull
        ?.where((s) => s.id == shopId)
        .firstOrNull;
    final minOrderAmount = currentShop?.minimumOrderAmount ?? 0;
    if (minOrderAmount > 0 && grandTotal < minOrderAmount) {
      final diff = (minOrderAmount - grandTotal).ceil();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  color: Colors.white,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Minimum order amount for $shopName is ₹$minOrderAmount. Add ₹$diff more to order.',
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
      return;
    }

    setState(() => _isPlacingOrder = true);

    try {
      final localStorage = ref.read(localStorageServiceProvider);

      // Find the shop's contact/order number from Firestore
      final firestoreService = ref.read(firestoreServiceProvider);
      final shop = await firestoreService.getShop(shopId);

      final rawTargetNumber = (shop != null && shop.contactNumber.trim().isNotEmpty)
          ? shop.contactNumber.trim()
          : (shop != null && shop.orderNumber.trim().isNotEmpty)
              ? shop.orderNumber.trim()
              : '';

      final normalizedNumber =
          WhatsAppService.normalizePhoneNumber(rawTargetNumber);

      if (normalizedNumber.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Row(
                children: [
                  Icon(
                    Icons.error_outline_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'This shop has no valid WhatsApp contact number.',
                      style: TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
              backgroundColor: AppColors.error,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
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
        whatsappNumber: normalizedNumber,
        message: message,
      );

      if (success) {
        // Atomic shop-wise WhatsApp counter increment (Rule 9: No order doc, only counter)
        await ref.read(shopStatsServiceProvider).incrementWhatsappOrders(shopId);
        ref.read(cartProvider.notifier).clearCart();
      } else if (mounted) {
        showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
    } catch (e) {
      debugPrint('❌ WhatsApp order placement error: $e');
    } finally {
      if (mounted) {
        setState(() => _isPlacingOrder = false);
      }
    }
  }

  String _getEffectiveImageUrl(MenuItem item) {
    if (item.imageUrl.isNotEmpty) return item.imageUrl;

    final nameLower = item.name.toLowerCase();
    if (nameLower.contains('momo') || nameLower.contains('dumpling')) {
      if (nameLower.contains('fried')) {
        return 'https://images.unsplash.com/photo-1541696432-82c6da8ce7bf?w=500&auto=format&fit=crop&q=80';
      }
      return 'https://images.unsplash.com/photo-1534422298391-e4f8c172dddb?w=500&auto=format&fit=crop&q=80';
    } else if (nameLower.contains('noodle') || nameLower.contains('chow') || nameLower.contains('maggi')) {
      return 'https://images.unsplash.com/photo-1612927601601-6638404737ce?w=500&auto=format&fit=crop&q=80';
    } else if (nameLower.contains('burger')) {
      return 'https://images.unsplash.com/photo-1568901346375-23c9450c58cd?w=500&auto=format&fit=crop&q=80';
    } else if (nameLower.contains('paneer') || nameLower.contains('curry')) {
      return 'https://images.unsplash.com/photo-1631452180519-c014fe946bc7?w=500&auto=format&fit=crop&q=80';
    } else if (nameLower.contains('roll') || nameLower.contains('wrap') || nameLower.contains('frankie')) {
      return 'https://images.unsplash.com/photo-1626700051175-6818013e1d4f?w=500&auto=format&fit=crop&q=80';
    } else if (nameLower.contains('pizza')) {
      return 'https://images.unsplash.com/photo-1513104890138-7c749659a591?w=500&auto=format&fit=crop&q=80';
    }

    final fallbacks = [
      'https://images.unsplash.com/photo-1534422298391-e4f8c172dddb?w=500&auto=format&fit=crop&q=80',
      'https://images.unsplash.com/photo-1541696432-82c6da8ce7bf?w=500&auto=format&fit=crop&q=80',
      'https://images.unsplash.com/photo-1612927601601-6638404737ce?w=500&auto=format&fit=crop&q=80',
      'https://images.unsplash.com/photo-1631452180519-c014fe946bc7?w=500&auto=format&fit=crop&q=80',
    ];
    return fallbacks[item.id.hashCode.abs() % fallbacks.length];
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cartState = ref.watch(cartProvider);
    final cartItems = cartState.items;
    final cartNotifier = ref.read(cartProvider.notifier);

    final grandTotal = cartState.grandTotal;
    final shopId = cartState.shopId ?? '';
    final shopName = cartState.shopName ?? (cartItems.isNotEmpty ? cartItems.first.shopName : '');

    final screenWidth = MediaQuery.of(context).size.width;
    final horizontalPadding = screenWidth < 360 ? 12.0 : 16.0;

    // Live menu items resolution from Firestore
    final liveMenuItemsAsync = shopId.isNotEmpty
        ? ref.watch(shopMenuItemsProvider(shopId))
        : const AsyncValue<List<MenuItem>>.data([]);
    final liveMenuItems = liveMenuItemsAsync.value ?? <MenuItem>[];

    // Filter suggestions from current shop's live menu items (max 3, in-stock, excluded if in cart)
    final cartItemIds = cartItems.map((ci) => ci.menuItem.id).toSet();
    final suggestions = liveMenuItems
        .where((item) => item.isAvailable && !cartItemIds.contains(item.id))
        .take(3)
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Your Cart',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          if (cartItems.isNotEmpty)
            TextButton(
              onPressed: () => cartNotifier.clearCart(),
              child: Text(
                'Clear',
                style: TextStyle(
                  color: Colors.red.shade400,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
      body: cartItems.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.shopping_bag_outlined,
                      size: 64,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    'Your cart is empty',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Browse shops and add items to get started',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
                        ),
                  ),
                ],
              ),
            )
          : SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                12,
                horizontalPadding,
                24 + MediaQuery.of(context).padding.bottom,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. Current Order Header Section
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Current Order',
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                                fontSize: screenWidth < 360 ? 22 : 24,
                                letterSpacing: -0.3,
                              ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Gate 2 Pickup • $shopName',
                          style: TextStyle(
                            color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const Divider(height: 1, thickness: 0.8),
                  const SizedBox(height: 12),

                  // 2. Cart Items List
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: cartItems.length,
                    separatorBuilder: (_, __) => const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Divider(height: 1, thickness: 0.6),
                    ),
                    itemBuilder: (context, index) {
                      final cartItem = cartItems[index];

                      // Resolve live MenuItem from Firestore if available
                      final liveMatch = liveMenuItems.where((m) => m.id == cartItem.menuItem.id).toList();
                      final effectiveMenuItem = liveMatch.isNotEmpty ? liveMatch.first : cartItem.menuItem;
                      final effectiveImageUrl = _getEffectiveImageUrl(effectiveMenuItem);

                      return _CartItemRow(
                        cartItem: cartItem,
                        menuItem: effectiveMenuItem,
                        imageUrl: effectiveImageUrl,
                        onIncrement: () => cartNotifier.addItem(
                          effectiveMenuItem,
                          cartItem.shopId,
                          cartItem.shopName,
                        ),
                        onDecrement: () => cartNotifier.removeItem(
                          cartItem.menuItem.id,
                          cartItem.shopId,
                        ),
                        onDelete: () => cartNotifier.deleteItem(
                          cartItem.menuItem.id,
                          cartItem.shopId,
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 20),

                  // 3. Special Instructions Section (Exact previous implementation)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
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
                  ),

                  // 4. Cart Suggestions Section ("Complete your order")
                  if (suggestions.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Divider(height: 1, thickness: 0.8),
                    const SizedBox(height: 16),
                    _CartSuggestionsSection(
                      suggestions: suggestions,
                      onAdd: (item) {
                        cartNotifier.addItem(item, shopId, shopName);
                      },
                      getEffectiveImageUrl: _getEffectiveImageUrl,
                    ),
                  ],
                ],
              ),
            ),

      // 4. Pinned Bottom Navigation Bar: Bill Summary + Place Order Button
      // Uses SafeArea to guarantee it NEVER collides or superimposes with system navigation bar!
      bottomNavigationBar: cartItems.isEmpty
          ? null
          : Container(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.08),
                    blurRadius: 14,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 0. Minimum Order Progress Indicator (if minOrderAmount > 0)
                    MinimumOrderProgressBar(
                      shopId: shopId,
                      currentTotal: grandTotal,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 9,
                      ),
                    ),
                    Builder(
                      builder: (context) {
                        final currentShop = ref
                            .watch(shopsProvider)
                            .valueOrNull
                            ?.where((s) => s.id == shopId)
                            .firstOrNull;
                        final minOrderAmount =
                            currentShop?.minimumOrderAmount ?? 0;
                        if (minOrderAmount > 0) {
                          return const SizedBox(height: 12);
                        }
                        return const SizedBox.shrink();
                      },
                    ),

                    // Bill Rows
                    _BillRow(label: 'Subtotal', value: '₹${grandTotal.toStringAsFixed(0)}'),
                    const SizedBox(height: 8),
                    const _BillRow(label: 'Tax (5%)', value: 'Included'),
                    const SizedBox(height: 8),
                    const _BillRow(label: 'Service Charge', value: 'Free (Gate 2)'),
                    const SizedBox(height: 12),
                    const Divider(height: 1, thickness: 0.8),
                    const SizedBox(height: 12),

                    // Total Price
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Total',
                          style: TextStyle(
                            fontSize: 18.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          '₹${grandTotal.toStringAsFixed(0)}',
                          style: const TextStyle(
                            fontSize: 21.5,
                            fontWeight: FontWeight.w900,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Place Order Action Button(s) based on Shop's Order Method
                    Builder(
                      builder: (context) {
                        final currentShop = ref
                            .watch(shopsProvider)
                            .valueOrNull
                            ?.where((s) => s.id == shopId)
                            .firstOrNull;
                        final orderMethod = currentShop?.orderMethod ??
                            ShopOrderMethod.whatsapp;

                        if (orderMethod == ShopOrderMethod.both) {
                          return Row(
                            children: [
                              // 1. In-App Place Order Button
                              Expanded(
                                child: SizedBox(
                                  height: 50,
                                  child: ElevatedButton(
                                    onPressed: _isPlacingOrder
                                        ? null
                                        : _placeAppOrder,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.primary,
                                      foregroundColor: Colors.white,
                                      elevation: 2,
                                      shadowColor: AppColors.primary
                                          .withValues(alpha: 0.35),
                                      shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(14),
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6),
                                    ),
                                    child: _isPlacingOrder
                                        ? const SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(
                                              color: Colors.white,
                                              strokeWidth: 2.2,
                                            ),
                                          )
                                        : const Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Icon(Icons.send_rounded,
                                                  color: Colors.white,
                                                  size: 17),
                                              SizedBox(width: 6),
                                              Flexible(
                                                child: Text(
                                                  'Place Order',
                                                  style: TextStyle(
                                                    fontSize: 14,
                                                    fontWeight:
                                                        FontWeight.bold,
                                                    letterSpacing: 0.2,
                                                  ),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              // 2. WhatsApp Order Button (Existing WhatsApp Flow)
                              Expanded(
                                child: SizedBox(
                                  height: 50,
                                  child: ElevatedButton(
                                    onPressed: _isPlacingOrder
                                        ? null
                                        : _placeWhatsAppOrder,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor:
                                          const Color(0xFF25D366),
                                      foregroundColor: Colors.white,
                                      elevation: 2,
                                      shadowColor: const Color(0xFF25D366)
                                          .withValues(alpha: 0.35),
                                      shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(14),
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6),
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        SvgPicture.asset(
                                          'assets/icons/whatsapp.svg',
                                          width: 19,
                                          height: 19,
                                          colorFilter:
                                              const ColorFilter.mode(
                                            Colors.white,
                                            BlendMode.srcIn,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        const Flexible(
                                          child: Text(
                                            'Order via WhatsApp',
                                            style: TextStyle(
                                              fontSize: 13.5,
                                              fontWeight: FontWeight.bold,
                                              letterSpacing: 0.2,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        }

                        return SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton(
                            onPressed: orderMethod == ShopOrderMethod.app
                                ? (_isPlacingOrder ? null : _placeAppOrder)
                                : (_isPlacingOrder
                                    ? null
                                    : _placeWhatsAppOrder),
                            style: ElevatedButton.styleFrom(
                              backgroundColor:
                                  orderMethod == ShopOrderMethod.whatsapp
                                      ? const Color(0xFF25D366)
                                      : AppColors.primary,
                              foregroundColor: Colors.white,
                              elevation: 2,
                              shadowColor: (orderMethod ==
                                          ShopOrderMethod.whatsapp
                                      ? const Color(0xFF25D366)
                                      : AppColors.primary)
                                  .withValues(alpha: 0.35),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: _isPlacingOrder
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2.2,
                                    ),
                                  )
                                : Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.center,
                                    children: [
                                      if (orderMethod ==
                                          ShopOrderMethod.whatsapp) ...[
                                        SvgPicture.asset(
                                          'assets/icons/whatsapp.svg',
                                          width: 20,
                                          height: 20,
                                          colorFilter:
                                              const ColorFilter.mode(
                                            Colors.white,
                                            BlendMode.srcIn,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        const Text(
                                          'Order via WhatsApp',
                                          style: TextStyle(
                                            fontSize: 16.5,
                                            fontWeight: FontWeight.bold,
                                            letterSpacing: 0.2,
                                          ),
                                        ),
                                      ] else ...[
                                        const Icon(Icons.send_rounded,
                                            color: Colors.white, size: 20),
                                        const SizedBox(width: 8),
                                        const Text(
                                          'Place Order',
                                          style: TextStyle(
                                            fontSize: 16.5,
                                            fontWeight: FontWeight.bold,
                                            letterSpacing: 0.2,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

/// Cart Item Row styled matching reference screenshot
class _CartItemRow extends StatelessWidget {
  const _CartItemRow({
    required this.cartItem,
    required this.menuItem,
    required this.imageUrl,
    required this.onIncrement,
    required this.onDecrement,
    required this.onDelete,
  });

  final CartItem cartItem;
  final MenuItem menuItem;
  final String imageUrl;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. Food Image (Square rounded)
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: SizedBox(
            width: 68,
            height: 68,
            child: imageUrl.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: imageUrl,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => Container(
                      color: isDark ? AppColors.darkSurfaceVariant : Colors.grey.shade200,
                      child: const Center(
                        child: Icon(Icons.restaurant_rounded, size: 20, color: Colors.grey),
                      ),
                    ),
                    errorWidget: (_, __, ___) => Container(
                      color: isDark ? AppColors.darkSurfaceVariant : Colors.grey.shade200,
                      child: const Center(
                        child: Icon(Icons.fastfood_rounded, size: 20, color: Colors.grey),
                      ),
                    ),
                  )
                : Container(
                    color: isDark ? AppColors.darkSurfaceVariant : Colors.grey.shade200,
                    child: const Center(
                      child: Icon(Icons.fastfood_rounded, size: 20, color: Colors.grey),
                    ),
                  ),
          ),
        ),
        const SizedBox(width: 12),

        // 2. Middle Details Column + Stepper
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                menuItem.name,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (menuItem.details.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  menuItem.details,
                  style: TextStyle(
                    color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
                    fontSize: 12,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 10),

              // Stepper Controls
              Row(
                children: [
                  InkWell(
                    onTap: onDecrement,
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Icon(
                        Icons.remove_rounded,
                        size: 16,
                        color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      '${cartItem.quantity}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14.5,
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: onIncrement,
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Icon(
                        Icons.add_rounded,
                        size: 16,
                        color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // 3. Right Column: Delete Icon + Price
        SizedBox(
          height: 68,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Delete Trash Button
              GestureDetector(
                onTap: onDelete,
                child: const Padding(
                  padding: EdgeInsets.all(2),
                  child: Icon(
                    Icons.delete_outline_rounded,
                    size: 20,
                    color: AppColors.error,
                  ),
                ),
              ),

              // Item Total Price
              Text(
                '₹${cartItem.totalPrice.toStringAsFixed(0)}',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15.5,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Bill Summary Row
class _BillRow extends StatelessWidget {
  const _BillRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// Suggestions / Upsell Section ("Complete your order")
class _CartSuggestionsSection extends StatelessWidget {
  const _CartSuggestionsSection({
    required this.suggestions,
    required this.onAdd,
    required this.getEffectiveImageUrl,
  });

  final List<MenuItem> suggestions;
  final void Function(MenuItem item) onAdd;
  final String Function(MenuItem item) getEffectiveImageUrl;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.stars_rounded,
              size: 20,
              color: AppColors.primary,
            ),
            const SizedBox(width: 6),
            Text(
              'Complete your order with',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    letterSpacing: -0.2,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: suggestions.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final item = suggestions[index];
            final imageUrl = getEffectiveImageUrl(item);

            return _SuggestionRow(
              item: item,
              imageUrl: imageUrl,
              onAdd: () => onAdd(item),
            );
          },
        ),
      ],
    );
  }
}

/// Compact Suggestion Item Row
class _SuggestionRow extends StatelessWidget {
  const _SuggestionRow({
    required this.item,
    required this.imageUrl,
    required this.onAdd,
  });

  final MenuItem item;
  final String imageUrl;
  final VoidCallback onAdd;

  Widget _buildVegIcon() {
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.vegGreen, width: 1.2),
        borderRadius: BorderRadius.circular(2.5),
      ),
      child: Center(
        child: Container(
          width: 5,
          height: 5,
          decoration: const BoxDecoration(
            color: AppColors.vegGreen,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }

  Widget _buildNonVegIcon() {
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.nonVegRed, width: 1.2),
        borderRadius: BorderRadius.circular(2.5),
      ),
      child: Center(
        child: Container(
          width: 5,
          height: 5,
          decoration: const BoxDecoration(
            color: AppColors.nonVegRed,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.grey.shade200,
        ),
      ),
      child: Row(
        children: [
          // Food Image
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 52,
              height: 52,
              child: imageUrl.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: imageUrl,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(
                        color: isDark ? AppColors.darkSurfaceVariant : Colors.grey.shade200,
                        child: const Center(
                          child: Icon(Icons.restaurant_rounded, size: 16, color: Colors.grey),
                        ),
                      ),
                      errorWidget: (_, __, ___) => Container(
                        color: isDark ? AppColors.darkSurfaceVariant : Colors.grey.shade200,
                        child: const Center(
                          child: Icon(Icons.fastfood_rounded, size: 16, color: Colors.grey),
                        ),
                      ),
                    )
                  : Container(
                      color: isDark ? AppColors.darkSurfaceVariant : Colors.grey.shade200,
                      child: const Center(
                        child: Icon(Icons.fastfood_rounded, size: 16, color: Colors.grey),
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 12),

          // Details: Name & Veg Icon + Price
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    item.isVeg ? _buildVegIcon() : _buildNonVegIcon(),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        item.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '₹${item.price.toStringAsFixed(0)}',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                    color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 8),

          // Small Add Button
          OutlinedButton(
            onPressed: onAdd,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: const BorderSide(color: AppColors.primary, width: 1.2),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              minimumSize: const Size(60, 32),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              visualDensity: VisualDensity.compact,
            ),
            child: const Text(
              'ADD',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 12.5,
                letterSpacing: 0.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
