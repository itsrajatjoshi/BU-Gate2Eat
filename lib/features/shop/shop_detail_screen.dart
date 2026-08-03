// BU Gate2Eat — Shop Detail Screen
// Shows menu, categories, search, veg/non-veg filter, and add-to-cart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_constants.dart';
import '../../core/providers.dart';
import '../../core/router.dart';
import '../../models/shop_model.dart';
import '../../models/category_model.dart';
import '../../models/menu_item_model.dart';
import '../../models/cart_item_model.dart';
import '../cart/cart_provider.dart';

/// Provider that fetches shop details by ID.
final shopDetailProvider =
    FutureProvider.family<Shop?, String>((ref, shopId) async {
  final firestoreService = ref.watch(firestoreServiceProvider);
  return firestoreService.getShop(shopId);
});

/// Filter state for veg/non-veg.
enum FoodFilter { all, veg, nonVeg }

class ShopDetailScreen extends ConsumerStatefulWidget {
  final String shopId;

  const ShopDetailScreen({super.key, required this.shopId});

  @override
  ConsumerState<ShopDetailScreen> createState() => _ShopDetailScreenState();
}

class _ShopDetailScreenState extends ConsumerState<ShopDetailScreen> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  FoodFilter _foodFilter = FoodFilter.all;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shopAsync = ref.watch(shopDetailProvider(widget.shopId));
    final categoriesAsync = ref.watch(shopCategoriesProvider(widget.shopId));
    final menuItemsAsync = ref.watch(shopMenuItemsProvider(widget.shopId));
    final cartItems = ref.watch(cartProvider);

    // Count items in cart for badge
    final cartItemCount =
        cartItems.fold<int>(0, (sum, item) => sum + item.quantity);

    return Scaffold(
      appBar: AppBar(
        title: shopAsync.when(
          data: (shop) => Text(shop?.name ?? 'Shop'),
          loading: () => const Text('Loading...'),
          error: (_, __) => const Text('Shop'),
        ),
      ),
      // Cart FAB
      floatingActionButton: cartItemCount > 0
          ? FloatingActionButton.extended(
              onPressed: () => context.push(AppRoutes.cart),
              backgroundColor: AppColors.primary,
              icon: const Icon(Icons.shopping_cart_rounded, color: Colors.white),
              label: Text(
                '$cartItemCount item${cartItemCount > 1 ? 's' : ''} in cart',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            )
          : null,
      body: shopAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Text('Error loading shop: $error'),
        ),
        data: (shop) {
          if (shop == null) {
            return const Center(child: Text('Shop not found'));
          }

          final isOpen = shop.isOpen;

          return Column(
            children: [
              // Shop banner image
              if (shop.bannerUrl.isNotEmpty)
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Image.network(
                    shop.bannerUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: AppColors.surfaceVariant,
                      child: const Icon(Icons.store_rounded,
                          size: 48, color: AppColors.textHint),
                    ),
                  ),
                ),

              // Shop info section
              Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Description
                    if (shop.description.isNotEmpty)
                      Text(
                        shop.description,
                        style:
                            Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: AppColors.textSecondary,
                                ),
                      ),
                    const SizedBox(height: AppSpacing.xs),

                    // Contact Number (plain text display only)
                    if (shop.contactNumber.isNotEmpty)
                      Text(
                        'Contact: ${shop.contactNumber}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppColors.textHint,
                            ),
                      ),
                    const SizedBox(height: AppSpacing.sm),

                    // Status and timing row
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.sm,
                            vertical: AppSpacing.xs,
                          ),
                          decoration: BoxDecoration(
                            color: isOpen
                                ? AppColors.success.withValues(alpha: 0.1)
                                : AppColors.error.withValues(alpha: 0.1),
                            borderRadius:
                                BorderRadius.circular(AppRadius.sm),
                          ),
                          child: Text(
                            isOpen ? 'Open Now' : 'Closed',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                  color: isOpen
                                      ? AppColors.success
                                      : AppColors.error,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        const Icon(Icons.access_time_rounded,
                            size: 14, color: AppColors.textHint),
                        const SizedBox(width: AppSpacing.xs),
                        Text(
                          '${shop.openTime} – ${shop.closeTime}',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: AppColors.textHint,
                                  ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const Divider(height: 1),

              // Search bar
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search menu items...',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                    isDense: true,
                  ),
                  onChanged: (value) =>
                      setState(() => _searchQuery = value.trim().toLowerCase()),
                ),
              ),

              // Veg/Non-Veg filter
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                ),
                child: Row(
                  children: [
                    _FilterChip(
                      label: 'All',
                      isSelected: _foodFilter == FoodFilter.all,
                      onTap: () =>
                          setState(() => _foodFilter = FoodFilter.all),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    _FilterChip(
                      label: 'Veg',
                      isSelected: _foodFilter == FoodFilter.veg,
                      color: AppColors.vegGreen,
                      onTap: () =>
                          setState(() => _foodFilter = FoodFilter.veg),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    _FilterChip(
                      label: 'Non-Veg',
                      isSelected: _foodFilter == FoodFilter.nonVeg,
                      color: AppColors.nonVegRed,
                      onTap: () =>
                          setState(() => _foodFilter = FoodFilter.nonVeg),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: AppSpacing.sm),

              // Menu items list
              Expanded(
                child: menuItemsAsync.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (error, _) => Center(
                    child: Text('Error loading menu: $error'),
                  ),
                  data: (menuItems) {
                    // Apply filters
                    final filtered = menuItems.where((item) {
                      if (_searchQuery.isNotEmpty &&
                          !item.name
                              .toLowerCase()
                              .contains(_searchQuery)) {
                        return false;
                      }
                      if (_foodFilter == FoodFilter.veg && !item.isVeg) {
                        return false;
                      }
                      if (_foodFilter == FoodFilter.nonVeg && item.isVeg) {
                        return false;
                      }
                      return true;
                    }).toList();

                    if (filtered.isEmpty) {
                      return const Center(
                        child: Text('No items found'),
                      );
                    }

                    return categoriesAsync.when(
                      loading: () => const Center(
                          child: CircularProgressIndicator()),
                      error: (_, __) => _buildFlatList(
                          filtered, shop, isOpen, cartItems),
                      data: (categories) {
                        if (categories.isEmpty) {
                          return _buildFlatList(
                              filtered, shop, isOpen, cartItems);
                        }
                        return _buildCategorizedList(
                            categories, filtered, shop, isOpen, cartItems);
                      },
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Builds a flat list of menu items (no categories).
  Widget _buildFlatList(List<MenuItem> items, Shop shop, bool isOpen,
      List<CartItem> cartItems) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      itemCount: items.length,
      itemBuilder: (context, index) {
        return _MenuItemCard(
          item: items[index],
          shop: shop,
          isShopOpen: isOpen,
          cartItems: cartItems,
        );
      },
    );
  }

  /// Builds a categorized list of menu items grouped by category.
  Widget _buildCategorizedList(List<Category> categories,
      List<MenuItem> items, Shop shop, bool isOpen, List<CartItem> cartItems) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      itemCount: categories.length,
      itemBuilder: (context, index) {
        final category = categories[index];
        final categoryItems = items
            .where((item) => item.categoryId == category.id)
            .toList();

        if (categoryItems.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Text(
                category.name,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            ...categoryItems.map((item) => _MenuItemCard(
                  item: item,
                  shop: shop,
                  isShopOpen: isOpen,
                  cartItems: cartItems,
                )),
          ],
        );
      },
    );
  }
}

/// Filter chip for Veg/Non-Veg/All.
class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.color,
  });

  final String label;
  final bool isSelected;
  final Color? color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final chipColor = color ?? AppColors.primary;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: isSelected ? chipColor.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.full),
          border: Border.all(
            color: isSelected ? chipColor : AppColors.divider,
          ),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: isSelected ? chipColor : AppColors.textSecondary,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
        ),
      ),
    );
  }
}

/// A card displaying a single menu item with add-to-cart controls.
class _MenuItemCard extends ConsumerWidget {
  const _MenuItemCard({
    required this.item,
    required this.shop,
    required this.isShopOpen,
    required this.cartItems,
  });

  final MenuItem item;
  final Shop shop;
  final bool isShopOpen;
  final List<CartItem> cartItems;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAvailable = item.isAvailable && isShopOpen;

    // Find current quantity in cart
    final cartItem = cartItems
        .where((ci) => ci.menuItem.id == item.id)
        .toList();
    final quantityInCart =
        cartItem.isNotEmpty ? cartItem.first.quantity : 0;

    return Opacity(
      opacity: isAvailable ? 1.0 : 0.5,
      child: Card(
        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Veg/Non-Veg indicator
              Container(
                margin: const EdgeInsets.only(top: 4),
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: item.isVeg
                        ? AppColors.vegGreen
                        : AppColors.nonVegRed,
                    width: 2,
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Center(
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: item.isVeg
                          ? AppColors.vegGreen
                          : AppColors.nonVegRed,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),

              // Item details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (item.details.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.xs),
                        child: Text(
                          item.details,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: AppColors.textSecondary),
                        ),
                      ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      item.formattedPrice,
                      style:
                          Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                    ),
                    if (!item.isAvailable)
                      Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.xs),
                        child: Text(
                          'Out of Stock',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                color: AppColors.error,
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                      ),
                  ],
                ),
              ),

              // Add to cart / Quantity controls
              if (isAvailable)
                quantityInCart > 0
                    ? Container(
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          borderRadius:
                              BorderRadius.circular(AppRadius.sm),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(
                                Icons.remove,
                                size: 18,
                                color: AppColors.primary,
                              ),
                              constraints: const BoxConstraints(
                                minWidth: 32,
                                minHeight: 32,
                              ),
                              padding: EdgeInsets.zero,
                              onPressed: () {
                                _handleCartChange(ref, context, -1);
                              },
                            ),
                            Text(
                              '$quantityInCart',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.add,
                                size: 18,
                                color: AppColors.primary,
                              ),
                              constraints: const BoxConstraints(
                                minWidth: 32,
                                minHeight: 32,
                              ),
                              padding: EdgeInsets.zero,
                              onPressed: () {
                                _handleCartChange(ref, context, 1);
                              },
                            ),
                          ],
                        ),
                      )
                    : ElevatedButton(
                        onPressed: () {
                          _handleCartChange(ref, context, 1);
                        },
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md,
                            vertical: AppSpacing.sm,
                          ),
                          minimumSize: Size.zero,
                          tapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text('Add'),
                      ),
            ],
          ),
        ),
      ),
    );
  }

  /// Handles adding/removing items from cart, with shop-switch confirmation.
  void _handleCartChange(WidgetRef ref, BuildContext context, int delta) {
    final cart = ref.read(cartProvider);
    final cartNotifier = ref.read(cartProvider.notifier);

    // Check if cart has items from a different shop
    if (cart.isNotEmpty && cart.first.shopId != shop.id) {
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Replace cart?'),
          content: Text(
            'Your cart has items from ${cart.first.shopName}. '
            'Clear the cart to order from ${shop.name}?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                cartNotifier.clearCart();
                cartNotifier.addItem(item, shop.id, shop.name);
              },
              child: const Text('Clear & Add'),
            ),
          ],
        ),
      );
      return;
    }

    if (delta > 0) {
      cartNotifier.addItem(item, shop.id, shop.name);
    } else {
      cartNotifier.removeItem(item.id);
    }
  }
}

