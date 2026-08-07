// BU Gate2Eat — Shop Detail Screen
// Shows menu, categories, search, veg/non-veg filter, and add-to-cart
// Features a premium collapsing header (fade, blur, compact title transition)

import 'dart:ui';
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
        error: (error, _) => Scaffold(
          appBar: AppBar(title: const Text('Error')),
          body: Center(child: Text('Error loading shop: $error')),
        ),
        data: (shop) {
          if (shop == null) {
            return Scaffold(
              appBar: AppBar(title: const Text('Shop Not Found')),
              body: const Center(child: Text('Shop not found')),
            );
          }

          final isOpen = shop.isOpen;
          const double expandedHeaderHeight = 160.0;

          return CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              // Premium Collapsing SliverAppBar
              SliverAppBar(
                pinned: true,
                expandedHeight: expandedHeaderHeight,
                elevation: 0,
                scrolledUnderElevation: 0,
                backgroundColor: Theme.of(context).scaffoldBackgroundColor,
                leading: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: CircleAvatar(
                    backgroundColor: Theme.of(context).brightness == Brightness.dark
                        ? Colors.black.withValues(alpha: 0.5)
                        : Colors.white.withValues(alpha: 0.85),
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back_rounded),
                      color: Theme.of(context).iconTheme.color,
                      onPressed: () => context.pop(),
                    ),
                  ),
                ),
                flexibleSpace: LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints constraints) {
                    final double top = constraints.biggest.height;
                    final double statusBarHeight = MediaQuery.of(context).padding.top;
                    final double minHeight = kToolbarHeight + statusBarHeight;
                    final double maxHeight = expandedHeaderHeight + statusBarHeight;
                    
                    // Collapse ratio t: 1.0 = fully expanded, 0.0 = fully collapsed
                    final double delta = maxHeight - minHeight;
                    final double t = delta > 0
                        ? ((top - minHeight) / delta).clamp(0.0, 1.0)
                        : 0.0;
                        
                    final double bannerOpacity = t;
                    final double blurSigma = (1.0 - t) * 12.0;
                    final double titleOpacity = (1.0 - t).clamp(0.0, 1.0);

                    return FlexibleSpaceBar(
                      centerTitle: true,
                      title: Opacity(
                        opacity: titleOpacity,
                        child: Text(
                          shop.name,
                          style: TextStyle(
                            color: Theme.of(context).textTheme.titleLarge?.color,
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                      ),
                      background: shop.bannerUrl.isNotEmpty
                          ? Stack(
                              fit: StackFit.expand,
                              children: [
                                Opacity(
                                  opacity: bannerOpacity,
                                  child: ImageFiltered(
                                    imageFilter: ImageFilter.blur(
                                      sigmaX: blurSigma,
                                      sigmaY: blurSigma,
                                    ),
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
                                ),
                                // Smooth bottom shadow/gradient for fluid visual blend
                                Positioned.fill(
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                        colors: [
                                          Colors.black.withValues(alpha: 0.25 * t),
                                          Theme.of(context).scaffoldBackgroundColor.withValues(alpha: (1.0 - t) * 0.9),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            )
                          : Container(color: AppColors.surfaceVariant),
                    );
                  },
                ),
              ),

              // Shop info, search bar, and veg/non-veg filter section
              SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Shop info section
                    Padding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (shop.description.isNotEmpty) ...[
                            Text(
                              shop.description,
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: AppColors.textSecondary,
                                  ),
                            ),
                            const SizedBox(height: AppSpacing.xs),
                          ],
                          if (shop.contactNumber.isNotEmpty) ...[
                            Text(
                              'Contact: ${shop.contactNumber}',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: AppColors.textHint,
                                  ),
                            ),
                            const SizedBox(height: AppSpacing.sm),
                          ],
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
                                  borderRadius: BorderRadius.circular(AppRadius.sm),
                                ),
                                child: Text(
                                  isOpen ? 'Open Now' : 'Closed',
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        color: isOpen ? AppColors.success : AppColors.error,
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
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
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
                            onTap: () => setState(() => _foodFilter = FoodFilter.all),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          _FilterChip(
                            label: 'Veg',
                            isSelected: _foodFilter == FoodFilter.veg,
                            color: AppColors.vegGreen,
                            onTap: () => setState(() => _foodFilter = FoodFilter.veg),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          _FilterChip(
                            label: 'Non-Veg',
                            isSelected: _foodFilter == FoodFilter.nonVeg,
                            color: AppColors.nonVegRed,
                            onTap: () => setState(() => _foodFilter = FoodFilter.nonVeg),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: AppSpacing.sm),
                  ],
                ),
              ),

              // Menu items section (SliverList / Categorized Slivers)
              ..._buildMenuSlivers(
                context: context,
                menuItemsAsync: menuItemsAsync,
                categoriesAsync: categoriesAsync,
                searchQuery: _searchQuery,
                foodFilter: _foodFilter,
                shop: shop,
                isOpen: isOpen,
                cartItems: cartItems,
              ),
            ],
          );
        },
      ),
    );
  }

  /// Builds slivers for menu items list (categorized or flat).
  List<Widget> _buildMenuSlivers({
    required BuildContext context,
    required AsyncValue<List<MenuItem>> menuItemsAsync,
    required AsyncValue<List<Category>> categoriesAsync,
    required String searchQuery,
    required FoodFilter foodFilter,
    required Shop shop,
    required bool isOpen,
    required List<CartItem> cartItems,
  }) {
    return menuItemsAsync.when(
      loading: () => [
        const SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: CircularProgressIndicator()),
        ),
      ],
      error: (error, _) => [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: Text('Error loading menu: $error')),
        ),
      ],
      data: (menuItems) {
        // Apply search & veg filters
        final filtered = menuItems.where((item) {
          if (searchQuery.isNotEmpty &&
              !item.name.toLowerCase().contains(searchQuery)) {
            return false;
          }
          if (foodFilter == FoodFilter.veg && !item.isVeg) {
            return false;
          }
          if (foodFilter == FoodFilter.nonVeg && item.isVeg) {
            return false;
          }
          return true;
        }).toList();

        if (filtered.isEmpty) {
          return [
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: Text('No items found')),
            ),
          ];
        }

        return categoriesAsync.when(
          loading: () => [
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: CircularProgressIndicator()),
            ),
          ],
          error: (_, __) => [
            _buildFlatSliverList(filtered, shop, isOpen, cartItems),
          ],
          data: (categories) {
            if (categories.isEmpty) {
              return [
                _buildFlatSliverList(filtered, shop, isOpen, cartItems),
              ];
            }
            return _buildCategorizedSlivers(
                context, categories, filtered, shop, isOpen, cartItems);
          },
        );
      },
    );
  }
   /// Builds a flat SliverGrid.
  Widget _buildFlatSliverList(List<MenuItem> items, Shop shop, bool isOpen,
      List<CartItem> cartItems) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 0.77,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) => _MenuItemCard(
            item: items[index],
            shop: shop,
            isShopOpen: isOpen,
            cartItems: cartItems,
          ),
          childCount: items.length,
        ),
      ),
    );
  }

  /// Builds categorized sliver lists with category headers and 2-column grids.
  List<Widget> _buildCategorizedSlivers(
      BuildContext context,
      List<Category> categories,
      List<MenuItem> items,
      Shop shop,
      bool isOpen,
      List<CartItem> cartItems) {
    final List<Widget> slivers = [];

    for (final category in categories) {
      final categoryItems =
          items.where((item) => item.categoryId == category.id).toList();

      if (categoryItems.isEmpty) continue;

      // Category title header
      slivers.add(
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.md,
            ),
            child: Text(
              category.name,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
        ),
      );

      // Category items 2-column grid
      slivers.add(
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.77,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) => _MenuItemCard(
                item: categoryItems[index],
                shop: shop,
                isShopOpen: isOpen,
                cartItems: cartItems,
              ),
              childCount: categoryItems.length,
            ),
          ),
        ),
      );
    }

    // Add bottom padding below last item
    slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 80)));

    return slivers;
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

/// A refined 2-column grid card displaying a single menu item (Blinkit + Zomato inspired hybrid).
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

  // Premium Shimmer/Gradient Image Placeholder
  Widget _buildImagePlaceholder(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [
                  Colors.grey.shade900,
                  Colors.grey.shade800.withValues(alpha: 0.6),
                ]
              : [
                  AppColors.surfaceVariant,
                  AppColors.surfaceVariant.withValues(alpha: 0.5),
                ],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.restaurant_menu_rounded,
          size: 24,
          color: AppColors.textHint.withValues(alpha: 0.35),
        ),
      ),
    );
  }

  // Blinkit Refined Floating ADD Button Style
  Widget _buildAddButton({
    required Key key,
    required BuildContext context,
    required WidgetRef ref,
  }) {
    return Container(
      key: key,
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: AppColors.vegGreen,
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 3,
            offset: const Offset(0, 1.5),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () => _handleCartChange(ref, context, 1),
          child: const Center(
            child: Text(
              'ADD',
              style: TextStyle(
                color: AppColors.vegGreen,
                fontWeight: FontWeight.w800,
                fontSize: 11.5,
                letterSpacing: 0.4,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Blinkit Refined Stepper Style
  Widget _buildQuantityStepper({
    required Key key,
    required BuildContext context,
    required WidgetRef ref,
    required int quantity,
  }) {
    return Container(
      key: key,
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        color: AppColors.vegGreen,
        borderRadius: BorderRadius.circular(6),
        boxShadow: [
          BoxShadow(
            color: AppColors.vegGreen.withValues(alpha: 0.25),
            blurRadius: 4,
            offset: const Offset(0, 1.5),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: () => _handleCartChange(ref, context, -1),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4.0, vertical: 1.0),
              child: Icon(Icons.remove_rounded, size: 13, color: Colors.white),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3.0),
            child: Text(
              '$quantity',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 11.5,
              ),
            ),
          ),
          InkWell(
            onTap: () => _handleCartChange(ref, context, 1),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4.0, vertical: 1.0),
              child: Icon(Icons.add_rounded, size: 13, color: Colors.white),
            ),
          ),
        ],
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

  /// Returns Firebase Storage imageUrl if present, or realistic food photo for UI preview testing.
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
    } else if (nameLower.contains('shake') || nameLower.contains('drink') || nameLower.contains('tea') || nameLower.contains('coffee')) {
      return 'https://images.unsplash.com/photo-1572490122747-3968b75cc699?w=500&auto=format&fit=crop&q=80';
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
  Widget build(BuildContext context, WidgetRef ref) {
    final isAvailable = item.isAvailable && isShopOpen;
    final isRecommended = item.isRecommended;
    final displayImageUrl = _getEffectiveImageUrl(item);

    // Find current quantity in cart
    final cartItem = cartItems
        .where((ci) => ci.menuItem.id == item.id)
        .toList();
    final quantityInCart =
        cartItem.isNotEmpty ? cartItem.first.quantity : 0;

    return Opacity(
      opacity: isAvailable ? 1.0 : 0.55,
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.08),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.035),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Image Section (~62% height allocation for larger image)
            Expanded(
              flex: 62,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // Image with rounded top corners
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(16),
                      ),
                      child: displayImageUrl.isNotEmpty
                          ? Image.network(
                              displayImageUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  _buildImagePlaceholder(context),
                            )
                          : _buildImagePlaceholder(context),
                    ),
                  ),
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  _buildImagePlaceholder(context),
                            )
                          : _buildImagePlaceholder(context),
                    ),
                  ),

                  // Floating Veg/Non-Veg Badge (Top-Left)
                  Positioned(
                    top: 6,
                    left: 6,
                    child: Container(
                      padding: const EdgeInsets.all(2.5),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .cardColor
                            .withValues(alpha: 0.94),
                        borderRadius: BorderRadius.circular(4),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 3,
                          ),
                        ],
                      ),
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: item.isVeg
                                ? AppColors.vegGreen
                                : AppColors.nonVegRed,
                            width: 1.5,
                          ),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Center(
                          child: Container(
                            width: 5,
                            height: 5,
                            decoration: BoxDecoration(
                              color: item.isVeg
                                  ? AppColors.vegGreen
                                  : AppColors.nonVegRed,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Floating Bestseller Tag (Top-Right if isRecommended)
                  if (isRecommended)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(4),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.12),
                              blurRadius: 3,
                            ),
                          ],
                        ),
                        child: const Text(
                          '★ Bestseller',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 8.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),

                  // Blinkit Floating ADD Button / Stepper
                  if (isAvailable)
                    Positioned(
                      bottom: -11,
                      right: 6,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        switchInCurve: Curves.easeOutBack,
                        switchOutCurve: Curves.easeIn,
                        transitionBuilder:
                            (Widget child, Animation<double> animation) {
                          return ScaleTransition(
                            scale: animation,
                            child: FadeTransition(
                              opacity: animation,
                              child: child,
                            ),
                          );
                        },
                        child: quantityInCart > 0
                            ? _buildQuantityStepper(
                                key: const ValueKey('stepper'),
                                context: context,
                                ref: ref,
                                quantity: quantityInCart,
                              )
                            : _buildAddButton(
                                key: const ValueKey('add_btn'),
                                context: context,
                                ref: ref,
                              ),
                      ),
                    ),
                ],
              ),
            ),

            // Middle & Bottom Info Section (~38% flex)
            Expanded(
              flex: 38,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 12, 8, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Item Name (max 2 lines) & Subtitle Details (max 1 line)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w700,
                                fontSize: 13.5,
                                height: 1.18,
                              ),
                        ),
                        if (item.details.isNotEmpty) ...[
                          const SizedBox(height: 1.5),
                          Text(
                            item.details,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                  color: AppColors.textSecondary
                                      .withValues(alpha: 0.85),
                                  fontSize: 10,
                                ),
                          ),
                        ],
                      ],
                    ),

                    // Bottom Row: Larger Bolder Price & Out of stock status
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          item.formattedPrice,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                                color: Theme.of(context)
                                    .textTheme
                                    .bodyLarge
                                    ?.color,
                              ),
                        ),
                        if (!item.isAvailable)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: AppColors.error.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'Out of stock',
                              style: TextStyle(
                                color: AppColors.error,
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
