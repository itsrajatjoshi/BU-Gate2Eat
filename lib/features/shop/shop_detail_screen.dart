// BU Gate2Eat — Shop Detail Screen
// Shows menu, categories, search, veg/non-veg filter, and add-to-cart
// Features a premium collapsing header (fade, blur, compact title transition)

import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_constants.dart';
import '../../core/providers.dart';
import '../../core/router.dart';
import '../../models/cart_item_model.dart';
import '../../models/category_model.dart';
import '../../models/menu_item_model.dart';
import '../../models/shop_model.dart';
import '../cart/cart_dialog_helper.dart';
import '../cart/cart_provider.dart';

/// Provider that fetches shop details by ID, reusing cached shops list to eliminate redundant Firestore reads.
final shopDetailProvider =
    FutureProvider.family<Shop?, String>((ref, shopId) async {
  final shopsAsync = ref.watch(shopsProvider);
  final cachedShops = shopsAsync.value;
  if (cachedShops != null && cachedShops.isNotEmpty) {
    final match = cachedShops.where((s) => s.id == shopId).toList();
    if (match.isNotEmpty) return match.first;
  }

  final firestoreService = ref.watch(firestoreServiceProvider);
  return firestoreService.getShop(shopId);
});

/// Filter state for veg/non-veg.
enum FoodFilter { all, veg, nonVeg }

class ShopDetailScreen extends ConsumerStatefulWidget {
  const ShopDetailScreen({
    required this.shopId,
    super.key,
  });

  final String shopId;

  @override
  ConsumerState<ShopDetailScreen> createState() => _ShopDetailScreenState();
}

class _ShopDetailScreenState extends ConsumerState<ShopDetailScreen> {
  final _searchController = TextEditingController();
  final ScrollController _mainScrollController = ScrollController();
  final ScrollController _categoryScrollController = ScrollController();
  final Map<String, GlobalKey> _categoryKeys = {};

  String _searchQuery = '';
  FoodFilter _foodFilter = FoodFilter.all;
  String _selectedCategoryId = 'all';
  bool _isManualCategoryTap = false;

  @override
  void initState() {
    super.initState();
    _mainScrollController.addListener(_onMainScroll);
  }

  @override
  void dispose() {
    _mainScrollController.removeListener(_onMainScroll);
    _mainScrollController.dispose();
    _categoryScrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  GlobalKey _getCategoryKey(String catId) {
    return _categoryKeys.putIfAbsent(catId, () => GlobalKey());
  }

  /// Detects active section on main list scroll and syncs top category tab (Domino's / Zomato style)
  void _onMainScroll() {
    if (_isManualCategoryTap || !_mainScrollController.hasClients) return;

    String? newlyVisibleCategory;
    double minDistance = double.infinity;

    for (final entry in _categoryKeys.entries) {
      final keyContext = entry.value.currentContext;
      if (keyContext != null) {
        final box = keyContext.findRenderObject() as RenderBox?;
        if (box != null && box.attached) {
          final position = box.localToGlobal(Offset.zero);
          final topOffset = position.dy;

          const targetOffset = 220.0;
          final distance = (topOffset - targetOffset).abs();

          if (topOffset <= targetOffset + 140 && distance < minDistance) {
            minDistance = distance;
            newlyVisibleCategory = entry.key;
          }
        }
      }
    }

    if (newlyVisibleCategory != null && newlyVisibleCategory != _selectedCategoryId) {
      setState(() {
        _selectedCategoryId = newlyVisibleCategory!;
      });
      _autoScrollCategoryTab(newlyVisibleCategory);
    }
  }

  /// Centers the active category chip in top horizontal navigation bar
  void _autoScrollCategoryTab(String catId) {
    if (!_categoryScrollController.hasClients) return;
    final categories = _getEffectiveCategories(widget.shopId, null);
    final index = categories.indexWhere((c) => c.id == catId);
    if (index != -1) {
      const itemWidth = 74.0;
      final screenWidth = MediaQuery.of(context).size.width;
      final targetOffset = (index * itemWidth) - (screenWidth / 2) + (itemWidth / 2) + 14;
      _categoryScrollController.animateTo(
        targetOffset.clamp(0.0, _categoryScrollController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
      );
    }
  }

  /// Tapping a top category tab smoothly scrolls main menu list to that section
  void _onCategoryTapped(String catId) {
    if (catId != 'all') {
      final menuItems = ref.read(shopMenuItemsProvider(widget.shopId)).value ?? [];
      final categories = ref.read(shopCategoriesProvider(widget.shopId)).value ?? [];
      final effectiveCategories = _getEffectiveCategories(widget.shopId, categories);

      final categoryObj = effectiveCategories.firstWhere(
        (c) => c.id == catId,
        orElse: () => Category(id: catId, name: catId, sortOrder: 0),
      );

      final hasItems = menuItems.any((item) {
        final itemCat = item.categoryId.toLowerCase();
        final target = catId.toLowerCase();
        return itemCat == target ||
            (target == 'thalis' && itemCat == 'thali') ||
            (target == 'thali' && itemCat == 'thalis') ||
            (target == 'momos' && itemCat == 'momo') ||
            (target == 'momo' && itemCat == 'momos') ||
            (target == 'pizzas' && itemCat == 'pizza') ||
            (target == 'pizza' && itemCat == 'pizzas') ||
            (target == 'burgers' && itemCat == 'burger') ||
            (target == 'burger' && itemCat == 'burgers');
      });

      if (!hasItems) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  color: isDark ? AppColors.primary : Colors.white,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'No items currently available in ${categoryObj.name}',
                    style: TextStyle(
                      fontWeight: FontWeight.w500,
                      color: isDark ? AppColors.darkTextPrimary : Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            backgroundColor: isDark ? AppColors.darkSurfaceVariant : AppColors.textPrimary,
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: isDark ? const BorderSide(color: AppColors.darkDivider) : BorderSide.none,
            ),
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          ),
        );
        return;
      }
    }

    setState(() {
      _selectedCategoryId = catId;
    });
    _autoScrollCategoryTab(catId);

    if (catId == 'all') {
      _isManualCategoryTap = true;
      _mainScrollController
          .animateTo(
            0,
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeInOut,
          )
          .then((_) => _isManualCategoryTap = false);
      return;
    }

    final key = _categoryKeys[catId];
    final keyContext = key?.currentContext;
    if (keyContext != null) {
      _isManualCategoryTap = true;
      Scrollable.ensureVisible(
        keyContext,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
        alignment: 0.05,
      ).then((_) => _isManualCategoryTap = false);
    }
  }

  /// Generates clean data-driven shop categories fetching dynamically from Firestore.
  List<Category> _getEffectiveCategories(String shopId, List<Category>? fetched) {
    const allCat = Category(
      id: 'all',
      name: 'All',
      sortOrder: 0,
      imageUrl: 'https://images.unsplash.com/photo-1534422298391-e4f8c172dddb?w=300&auto=format&fit=crop&q=80',
    );

    final List<Category> list = [allCat];

    if (fetched != null && fetched.isNotEmpty) {
      for (final c in fetched) {
        if (c.id == 'all' || !c.isActive) continue;
        String img = c.imageUrl;
        if (img.isEmpty) {
          final nameL = c.name.toLowerCase();
          if (nameL.contains('momo')) {
            img = 'https://images.unsplash.com/photo-1541696432-82c6da8ce7bf?w=300&auto=format&fit=crop&q=80';
          } else if (nameL.contains('pizza')) {
            img = 'https://images.unsplash.com/photo-1513104890138-7c749659a591?w=300&auto=format&fit=crop&q=80';
          } else if (nameL.contains('burger')) {
            img = 'https://images.unsplash.com/photo-1568901346375-23c9450c58cd?w=300&auto=format&fit=crop&q=80';
          } else if (nameL.contains('biryani')) {
            img = 'https://images.unsplash.com/photo-1633945274405-b6c8069047b0?w=300&auto=format&fit=crop&q=80';
          } else if (nameL.contains('thali')) {
            img = 'https://images.unsplash.com/photo-1626777552726-4a6b54c97e46?w=300&auto=format&fit=crop&q=80';
          } else if (nameL.contains('roll')) {
            img = 'https://images.unsplash.com/photo-1626700051175-6818013e1d4f?w=300&auto=format&fit=crop&q=80';
          } else {
            img = 'https://images.unsplash.com/photo-1601050690597-df0568f70950?w=300&auto=format&fit=crop&q=80';
          }
        }
        list.add(Category(
          id: c.id,
          name: c.name,
          sortOrder: c.sortOrder,
          imageUrl: img,
          isActive: c.isActive,
          shopId: shopId,
        ),);
      }
    }

    return list;
  }

  @override
  Widget build(BuildContext context) {
    final shopAsync = ref.watch(shopDetailProvider(widget.shopId));
    final categoriesAsync = ref.watch(shopCategoriesProvider(widget.shopId));
    final menuItemsAsync = ref.watch(shopMenuItemsProvider(widget.shopId));
    final cartState = ref.watch(cartProvider);
    final cartItems = cartState.items;

    // Count items in cart for badge (sum of quantities)
    final cartItemCount = cartState.totalItemCount;

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
          final isDark = Theme.of(context).brightness == Brightness.dark;
          const double expandedHeaderHeight = 160.0;

          return CustomScrollView(
            controller: _mainScrollController,
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
                                    child: CachedNetworkImage(
                                      imageUrl: shop.bannerUrl,
                                      fit: BoxFit.cover,
                                      placeholder: (_, __) => Container(
                                        color: AppColors.surfaceVariant,
                                        child: const Icon(
                                          Icons.store_rounded,
                                          size: 48,
                                          color: AppColors.textHint,
                                        ),
                                      ),
                                      errorWidget: (_, __, ___) => Container(
                                        color: AppColors.surfaceVariant,
                                        child: const Icon(
                                          Icons.store_rounded,
                                          size: 48,
                                          color: AppColors.textHint,
                                        ),
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
                child: Builder(
                  builder: (context) {
                    final screenWidth = MediaQuery.of(context).size.width;
                    final horizontalPadding = screenWidth < 360 ? 10.0 : (screenWidth < 400 ? 12.0 : 14.0);

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Shop info section
                        Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: horizontalPadding,
                            vertical: 12,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (shop.description.isNotEmpty) ...[
                                Text(
                                  shop.description,
                                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                        color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
                                      ),
                                ),
                                const SizedBox(height: AppSpacing.xs),
                              ],
                              if (shop.contactNumber.isNotEmpty) ...[
                                Text(
                                  'Contact: ${shop.contactNumber}',
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        color: isDark ? AppColors.darkTextSecondary : AppColors.textHint,
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
                                  Icon(
                                    Icons.access_time_rounded,
                                    size: 14,
                                    color: isDark ? AppColors.darkTextSecondary : AppColors.textHint,
                                  ),
                                  const SizedBox(width: AppSpacing.xs),
                                  Text(
                                    shop.formattedTimings,
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                          color: isDark ? AppColors.darkTextSecondary : AppColors.textHint,
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
                          padding: EdgeInsets.symmetric(
                            horizontal: horizontalPadding,
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
                          padding: EdgeInsets.symmetric(
                            horizontal: horizontalPadding,
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
                    );
                  },
                ),
              ),

              // Sticky Category Navigation Header
              SliverPersistentHeader(
                pinned: true,
                delegate: _StickyCategoryHeaderDelegate(
                  height: MediaQuery.of(context).size.width < 360 ? 106.0 : 114.0,
                  child: _CategoryNavWidget(
                    categories: _getEffectiveCategories(
                      shop.id,
                      categoriesAsync.value,
                    ),
                    selectedCategoryId: _selectedCategoryId,
                    onCategorySelected: _onCategoryTapped,
                    scrollController: _categoryScrollController,
                  ),
                ),
              ),

              // Menu items section (SliverList / Categorized Slivers)
              ..._buildMenuSlivers(
                context: context,
                menuItemsAsync: menuItemsAsync,
                categoriesAsync: categoriesAsync,
                selectedCategoryId: _selectedCategoryId,
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

  /// Calculates responsive Grid parameters based on screen width & text scale
  static SliverGridDelegateWithFixedCrossAxisCount _getResponsiveGridDelegate(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final horizontalPadding = screenWidth < 360 ? 10.0 : (screenWidth < 400 ? 12.0 : 14.0);
    final crossAxisSpacing = screenWidth < 360 ? 8.0 : 10.0;
    final mainAxisSpacing = screenWidth < 360 ? 10.0 : 12.0;
    final cardWidth = (screenWidth - (horizontalPadding * 2) - crossAxisSpacing) / 2;

    // Scale for Android accessibility text scaling
    final textScale = MediaQuery.textScalerOf(context).scale(1.0);
    final extraTextHeight = (textScale > 1.0) ? (textScale - 1.0) * 36.0 : 0.0;

    // Dynamic Body Height Allocation:
    // - Title (up to 2 lines): ~34px
    // - Spacing: 4px
    // - Description (up to 2 lines): ~28px
    // - Bottom Row (Price + Add Button): ~30px
    // - Padding: 14px (7 top + 7 bottom)
    // - Internal spacing: ~6px
    final bodyHeight = 116.0 + extraTextHeight;
    final cardHeight = (cardWidth / 1.3) + bodyHeight;
    final childAspectRatio = cardWidth / cardHeight;

    return SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: 2,
      mainAxisSpacing: mainAxisSpacing,
      crossAxisSpacing: crossAxisSpacing,
      childAspectRatio: childAspectRatio,
    );
  }

  /// Builds slivers for menu items list (categorized or flat).
  List<Widget> _buildMenuSlivers({
    required BuildContext context,
    required AsyncValue<List<MenuItem>> menuItemsAsync,
    required AsyncValue<List<Category>> categoriesAsync,
    required String selectedCategoryId,
    required String searchQuery,
    required FoodFilter foodFilter,
    required Shop shop,
    required bool isOpen,
    required List<CartItem> cartItems,
  }) {
    final screenWidth = MediaQuery.of(context).size.width;
    final horizontalPadding = screenWidth < 360 ? 10.0 : (screenWidth < 400 ? 12.0 : 14.0);
    final gridDelegate = _getResponsiveGridDelegate(context);

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

        if (searchQuery.isNotEmpty) {
          if (filtered.isEmpty) {
            final isDark = Theme.of(context).brightness == Brightness.dark;
            return [
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32.0),
                    child: Text(
                      'No matching items found',
                      style: TextStyle(
                        color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
            ];
          }
          return [
            _buildFlatSliverList(context, filtered, shop, isOpen, cartItems),
            SliverToBoxAdapter(
              child: SizedBox(height: 80 + MediaQuery.of(context).padding.bottom),
            ),
          ];
        }

        // Domino's / Zomato style Categorized Sections
        final effectiveCategories = _getEffectiveCategories(shop.id, categoriesAsync.value);
        final List<Widget> slivers = [];

        for (final category in effectiveCategories) {
          if (category.id == 'all') continue;

          final categoryItems = filtered.where((item) {
            final catId = item.categoryId.toLowerCase();
            final target = category.id.toLowerCase();

            return catId == target ||
                (target == 'thalis' && catId == 'thali') ||
                (target == 'thali' && catId == 'thalis') ||
                (target == 'momos' && catId == 'momo') ||
                (target == 'momo' && catId == 'momos') ||
                (target == 'pizzas' && catId == 'pizza') ||
                (target == 'pizza' && catId == 'pizzas') ||
                (target == 'burgers' && catId == 'burger') ||
                (target == 'burger' && catId == 'burgers');
          }).toList();

          if (categoryItems.isEmpty) continue;

          // Section Title Header with GlobalKey for Scroll-Spy tracking
          slivers.add(
            SliverToBoxAdapter(
              child: Padding(
                key: _getCategoryKey(category.id),
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding + 2,
                  20,
                  horizontalPadding + 2,
                  10,
                ),
                child: Row(
                  children: [
                    Text(
                      category.name,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                            fontSize: screenWidth < 360 ? 17 : 18,
                            letterSpacing: -0.2,
                          ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${categoryItems.length}',
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );

          // 2-column Responsive Grid for Category Items
          slivers.add(
            SliverPadding(
              padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
              sliver: SliverGrid(
                gridDelegate: gridDelegate,
                delegate: SliverChildBuilderDelegate(
                  (context, index) => _MenuItemCard(
                    key: ValueKey('${shop.id}_${categoryItems[index].id}'),
                    item: categoryItems[index],
                    shop: shop,
                    isShopOpen: isOpen,
                  ),
                  childCount: categoryItems.length,
                ),
              ),
            ),
          );
        }

        if (slivers.isEmpty) {
          return [
            _buildFlatSliverList(context, filtered, shop, isOpen, cartItems),
            SliverToBoxAdapter(
              child: SizedBox(height: 80 + MediaQuery.of(context).padding.bottom),
            ),
          ];
        }

        slivers.add(
          SliverToBoxAdapter(
            child: SizedBox(height: 80 + MediaQuery.of(context).padding.bottom),
          ),
        );
        return slivers;
      },
    );
  }

  /// Builds a flat SliverGrid.
  Widget _buildFlatSliverList(
    BuildContext context,
    List<MenuItem> items,
    Shop shop,
    bool isOpen,
    List<CartItem> cartItems,
  ) {
    final screenWidth = MediaQuery.of(context).size.width;
    final horizontalPadding = screenWidth < 360 ? 10.0 : (screenWidth < 400 ? 12.0 : 14.0);
    final gridDelegate = _getResponsiveGridDelegate(context);

    return SliverPadding(
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
      sliver: SliverGrid(
        gridDelegate: gridDelegate,
        delegate: SliverChildBuilderDelegate(
          (context, index) => _MenuItemCard(
            key: ValueKey('${shop.id}_${items[index].id}'),
            item: items[index],
            shop: shop,
            isShopOpen: isOpen,
          ),
          childCount: items.length,
        ),
      ),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
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
            color: isSelected
                ? chipColor
                : (isDark ? AppColors.darkDivider : AppColors.divider),
          ),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: isSelected
                    ? chipColor
                    : (isDark ? AppColors.darkTextSecondary : AppColors.textSecondary),
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
        ),
      ),
    );
  }
}

/// Painter for drawing the Non-Veg Red Triangle symbol inside a square badge.
class _TrianglePainter extends CustomPainter {
  const _TrianglePainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    path.moveTo(size.width / 2, 0);
    path.lineTo(size.width, size.height);
    path.lineTo(0, size.height);
    path.close();
    final paint = Paint()..color = color;
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// A 2-column grid menu card visually identical to Zomato/Magicpin reference screenshots.
class _MenuItemCard extends ConsumerWidget {
  const _MenuItemCard({
    required this.item,
    required this.shop,
    required this.isShopOpen,
    super.key,
  });

  final MenuItem item;
  final Shop shop;
  final bool isShopOpen;

  Widget _buildVegIcon() {
    return Container(
      width: 15,
      height: 15,
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.vegGreen, width: 1.3),
        borderRadius: BorderRadius.circular(2.5),
      ),
      child: Center(
        child: Container(
          width: 6,
          height: 6,
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
      width: 15,
      height: 15,
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.nonVegRed, width: 1.3),
        borderRadius: BorderRadius.circular(2.5),
      ),
      child: const Center(
        child: CustomPaint(
          size: Size(6, 6),
          painter: _TrianglePainter(color: AppColors.nonVegRed),
        ),
      ),
    );
  }

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

  Widget _buildAddButton({
    required Key key,
    required BuildContext context,
    required WidgetRef ref,
    double width = 64,
    double height = 30,
  }) {
    const primaryColor = AppColors.primary;
    return InkWell(
      key: key,
      borderRadius: BorderRadius.circular(8),
      onTap: () => _handleCartChange(ref, context, 1),
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: primaryColor,
            width: 1.3,
          ),
        ),
        child: const Center(
          child: Text(
            'Add',
            style: TextStyle(
              color: primaryColor,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildQuantityStepper({
    required Key key,
    required BuildContext context,
    required WidgetRef ref,
    required int quantity,
    double width = 64,
    double height = 30,
  }) {
    const primaryColor = AppColors.primary;
    return Container(
      key: key,
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: primaryColor,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: primaryColor.withValues(alpha: 0.3),
            blurRadius: 4,
            offset: const Offset(0, 1.5),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          InkWell(
            onTap: () => _handleCartChange(ref, context, -1),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 3.0, vertical: 2.0),
              child: Icon(Icons.remove_rounded, size: 14, color: Colors.white),
            ),
          ),
          Text(
            '$quantity',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
          InkWell(
            onTap: () => _handleCartChange(ref, context, 1),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 3.0, vertical: 2.0),
              child: Icon(Icons.add_rounded, size: 14, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  void _handleCartChange(WidgetRef ref, BuildContext context, int delta) {
    if (delta > 0) {
      tryAddToCart(
        context: context,
        ref: ref,
        item: item,
        shopId: shop.id,
        shopName: shop.name,
      );
    } else {
      ref.read(cartProvider.notifier).removeItem(item.id);
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isAvailable = item.isAvailable && isShopOpen;
    final displayImageUrl = _getEffectiveImageUrl(item);
    final favorites = ref.watch(favoritesProvider);
    final isFavorite = favorites.contains(FavoriteNotifier.buildFavoriteKey(shop.id, item.id));

    final cartState = ref.watch(cartProvider);
    final quantityInCart = cartState.getQuantityForShop(shop.id, item.id);

    void showItemDetail() {
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        barrierColor: Colors.black.withValues(alpha: 0.55),
        builder: (ctx) => _ItemDetailBottomSheet(
          item: item,
          shop: shop,
          isAvailable: isAvailable,
          displayImageUrl: displayImageUrl,
        ),
      );
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 360;

    return Opacity(
      opacity: isAvailable ? 1.0 : 0.55,
      child: GestureDetector(
        onTap: showItemDetail,
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: Theme.of(context).dividerColor.withValues(alpha: 0.08),
              width: 0.8,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2.5),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Food Image Container
              AspectRatio(
                aspectRatio: 1.3,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(18),
                        ),
                        child: displayImageUrl.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: displayImageUrl,
                                fit: BoxFit.cover,
                                placeholder: (_, __) =>
                                    _buildImagePlaceholder(context),
                                errorWidget: (_, __, ___) =>
                                    _buildImagePlaceholder(context),
                              )
                            : _buildImagePlaceholder(context),
                      ),
                    ),

                    // Favorite Heart Button (Top-Right overlay)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: GestureDetector(
                        onTap: () {
                          ref
                              .read(favoritesProvider.notifier)
                              .toggleFavorite(item.id, shop.id);
                        },
                        child: Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .cardColor
                                .withValues(alpha: 0.9),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.12),
                                blurRadius: 3,
                              ),
                            ],
                          ),
                          child: Center(
                            child: Icon(
                              isFavorite
                                  ? Icons.favorite_rounded
                                  : Icons.favorite_outline_rounded,
                              size: 16,
                              color: isFavorite
                                  ? AppColors.nonVegRed
                                  : (isDark ? AppColors.darkTextSecondary : AppColors.textHint),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // 2. Card Content Body
              Expanded(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    isSmallScreen ? 8 : 10,
                    7,
                    isSmallScreen ? 8 : 10,
                    7,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Item Title with Veg/Non-Veg icon (Supports 2 lines to avoid aggressive ellipsis)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: item.isVeg ? _buildVegIcon() : _buildNonVegIcon(),
                              ),
                              const SizedBox(width: 5),
                              Expanded(
                                child: Text(
                                  item.name,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(
                                        fontWeight: FontWeight.w700,
                                        fontSize: isSmallScreen ? 13.0 : 13.8,
                                        height: 1.2,
                                      ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),

                          // Description with clean "... more"
                          Builder(
                            builder: (context) {
                              final rawDetails = item.details.isNotEmpty
                                  ? item.details
                                  : '${item.name} prepared fresh with authentic spices';
                              final cleanDetails = rawDetails.replaceAll(RegExp(r'\.+$'), '').trim();
                              return Text.rich(
                                TextSpan(
                                  style: TextStyle(
                                    color: isDark ? AppColors.darkTextSecondary : Colors.grey.shade600,
                                    fontSize: isSmallScreen ? 10.8 : 11.5,
                                    height: 1.28,
                                  ),
                                  children: [
                                    TextSpan(text: '$cleanDetails '),
                                    const TextSpan(
                                      text: 'more',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.primary,
                                      ),
                                    ),
                                  ],
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              );
                            },
                          ),
                        ],
                      ),

                      // Bottom Row: Clean Price + Add Button / Stepper
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Flexible(
                            child: Text(
                              item.formattedPrice,
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: isSmallScreen ? 14.5 : 15.5,
                                color: Theme.of(context)
                                    .textTheme
                                    .bodyLarge
                                    ?.color,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 4),

                          // Add Button / Stepper with responsive width
                          if (isAvailable)
                            quantityInCart > 0
                                ? _buildQuantityStepper(
                                    key: const ValueKey('stepper'),
                                    context: context,
                                    ref: ref,
                                    quantity: quantityInCart,
                                    width: isSmallScreen ? 58.0 : 64.0,
                                    height: isSmallScreen ? 28.0 : 30.0,
                                  )
                                : _buildAddButton(
                                    key: const ValueKey('add_btn'),
                                    context: context,
                                    ref: ref,
                                    width: isSmallScreen ? 58.0 : 64.0,
                                    height: isSmallScreen ? 28.0 : 30.0,
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
      ),
    );
  }
}

/// Delegate for pinning Category Navigation Header when scrolling
class _StickyCategoryHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _StickyCategoryHeaderDelegate({
    required this.child,
    this.height = 114.0,
  });

  final Widget child;
  final double height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        boxShadow: overlapsContent
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.06),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: child,
    );
  }

  @override
  double get maxExtent => height;

  @override
  double get minExtent => height;

  @override
  bool shouldRebuild(covariant _StickyCategoryHeaderDelegate oldDelegate) {
    return oldDelegate.child != child || oldDelegate.height != height;
  }
}

/// Horizontal category navigation matching reference UI design
class _CategoryNavWidget extends StatelessWidget {
  const _CategoryNavWidget({
    required this.categories,
    required this.selectedCategoryId,
    required this.onCategorySelected,
    required this.scrollController,
  });

  final List<Category> categories;
  final String selectedCategoryId;
  final ValueChanged<String> onCategorySelected;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const primaryColor = AppColors.primary; // Warm orange matching reference screenshot

    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 360;
    final itemWidth = isSmallScreen ? 68.0 : (screenWidth < 400 ? 73.0 : 76.0);
    final circleSize = isSmallScreen ? 52.0 : 58.0;
    final imageSize = isSmallScreen ? 46.0 : 51.0;
    final itemSpacing = isSmallScreen ? 6.0 : 8.0;
    final horizontalPadding = isSmallScreen ? 10.0 : 14.0;

    return ListView.separated(
      controller: scrollController,
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: 8),
      itemCount: categories.length,
      separatorBuilder: (_, __) => SizedBox(width: itemSpacing),
      itemBuilder: (context, index) {
        final cat = categories[index];
        final isSelected = selectedCategoryId == cat.id;

        return GestureDetector(
          onTap: () => onCategorySelected(cat.id),
          child: SizedBox(
            width: itemWidth,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Stack(
                    children: [
                      // Circular category photo container
                      Container(
                        width: circleSize,
                        height: circleSize,
                        padding: const EdgeInsets.all(2.5),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isSelected
                                ? primaryColor
                                : Colors.transparent,
                            width: isSelected ? 2.5 : 0,
                          ),
                        ),
                        child: ClipOval(
                          child: CachedNetworkImage(
                            imageUrl: cat.imageUrl,
                            width: imageSize,
                            height: imageSize,
                            fit: BoxFit.cover,
                            placeholder: (context, url) => Container(
                              color: isDark ? AppColors.darkSurfaceVariant : Colors.grey[200],
                              child: const Icon(Icons.fastfood_rounded, size: 22, color: Colors.grey),
                            ),
                            errorWidget: (context, url, error) => Container(
                              color: isDark ? AppColors.darkSurfaceVariant : Colors.grey[200],
                              child: const Icon(Icons.fastfood_rounded, size: 22, color: Colors.grey),
                            ),
                          ),
                        ),
                      ),

                      // Selected checkmark badge (Orange circle with white check icon at top-right)
                      if (isSelected)
                        Positioned(
                          top: 0,
                          right: 0,
                          child: Container(
                            width: isSmallScreen ? 16 : 18,
                            height: isSmallScreen ? 16 : 18,
                            decoration: BoxDecoration(
                              color: primaryColor,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Theme.of(context).scaffoldBackgroundColor,
                                width: 1.5,
                              ),
                            ),
                            child: Center(
                              child: Icon(
                                Icons.check_rounded,
                                size: isSmallScreen ? 10 : 11,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),

                // Category Name Label (Fully visible, clean 2-line wrap without ellipsis truncation)
                Text(
                  cat.name,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  softWrap: true,
                  style: TextStyle(
                    fontSize: isSmallScreen ? 10.5 : 11.5,
                    height: 1.15,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                    color: isSelected
                        ? primaryColor
                        : (isDark ? Colors.white70 : Colors.black87),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Modern, premium bottom sheet displaying full item details matching top-tier food delivery apps (Swiggy/Zomato/Zepto).
class _ItemDetailBottomSheet extends ConsumerStatefulWidget {
  const _ItemDetailBottomSheet({
    required this.item,
    required this.shop,
    required this.isAvailable,
    required this.displayImageUrl,
  });

  final MenuItem item;
  final Shop shop;
  final bool isAvailable;
  final String displayImageUrl;

  @override
  ConsumerState<_ItemDetailBottomSheet> createState() => _ItemDetailBottomSheetState();
}

class _ItemDetailBottomSheetState extends ConsumerState<_ItemDetailBottomSheet> {
  double _favoriteScale = 1.0;

  Widget _buildVegIcon() {
    return Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.vegGreen, width: 1.5),
        borderRadius: BorderRadius.circular(3.5),
      ),
      child: Center(
        child: Container(
          width: 7,
          height: 7,
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
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.nonVegRed, width: 1.5),
        borderRadius: BorderRadius.circular(3.5),
      ),
      child: const Center(
        child: CustomPaint(
          size: Size(8, 8),
          painter: _TrianglePainter(color: AppColors.nonVegRed),
        ),
      ),
    );
  }

  void _onFavoriteTap() {
    setState(() => _favoriteScale = 1.28);
    ref.read(favoritesProvider.notifier).toggleFavorite(widget.item.id, widget.shop.id);
    Future.delayed(const Duration(milliseconds: 160), () {
      if (mounted) setState(() => _favoriteScale = 1.0);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final favorites = ref.watch(favoritesProvider);
    final isFavorite = favorites.contains(FavoriteNotifier.buildFavoriteKey(widget.shop.id, widget.item.id));

    final liveCart = ref.watch(cartProvider);
    final quantityInCart =
        liveCart.getQuantityForShop(widget.shop.id, widget.item.id);
    final isItemAvailable = widget.isAvailable;

    final mediaQuery = MediaQuery.of(context);
    final bottomPadding = mediaQuery.padding.bottom;
    final maxHeight = mediaQuery.size.height * 0.88;

    return Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 560,
          maxHeight: maxHeight,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.15),
                blurRadius: 20,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 1. Drag Handle Bar
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 10, bottom: 6),
                  width: 40,
                  height: 4.5,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.grey[700] : Colors.grey[300],
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),

              // 2. Scrollable Body
              Flexible(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Hero Food Image Container
                      if (widget.displayImageUrl.isNotEmpty)
                        Container(
                          height: 240,
                          width: double.infinity,
                          margin: const EdgeInsets.fromLTRB(16, 6, 16, 16),
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Positioned.fill(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(20),
                                  child: CachedNetworkImage(
                                    imageUrl: widget.displayImageUrl,
                                    fit: BoxFit.cover,
                                    placeholder: (_, __) => Container(
                                      color: isDark ? AppColors.darkSurfaceVariant : Colors.grey[200],
                                      child: const Icon(
                                        Icons.restaurant_menu_rounded,
                                        size: 48,
                                        color: Colors.grey,
                                      ),
                                    ),
                                    errorWidget: (_, __, ___) => Container(
                                      color: isDark ? AppColors.darkSurfaceVariant : Colors.grey[200],
                                      child: const Icon(
                                        Icons.restaurant_menu_rounded,
                                        size: 48,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ),
                                ),
                              ),

                              // Gradient Vignette overlay for subtle depth
                              Positioned.fill(
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(20),
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [
                                        Colors.black.withValues(alpha: 0.15),
                                        Colors.transparent,
                                        Colors.black.withValues(alpha: 0.25),
                                      ],
                                      stops: const [0.0, 0.5, 1.0],
                                    ),
                                  ),
                                ),
                              ),

                              // Recommended Badge (if true in model)
                              if (widget.item.isRecommended)
                                Positioned(
                                  top: 12,
                                  left: 12,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: AppColors.primary,
                                      borderRadius: BorderRadius.circular(8),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(alpha: 0.2),
                                          blurRadius: 4,
                                        ),
                                      ],
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.star_rounded, size: 14, color: Colors.amber),
                                        SizedBox(width: 4),
                                        Text(
                                          'RECOMMENDED',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: 0.4,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),

                              // Animated Favorite Heart Button (Top-Right)
                              Positioned(
                                top: 12,
                                right: 12,
                                child: GestureDetector(
                                  onTap: _onFavoriteTap,
                                  child: AnimatedScale(
                                    scale: _favoriteScale,
                                    duration: const Duration(milliseconds: 160),
                                    curve: Curves.easeOutBack,
                                    child: Container(
                                      width: 38,
                                      height: 38,
                                      decoration: BoxDecoration(
                                        color: isDark ? AppColors.darkSurfaceVariant : Colors.white.withValues(alpha: 0.92),
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: isDark ? AppColors.darkDivider : Colors.transparent,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.18),
                                            blurRadius: 6,
                                            offset: const Offset(0, 2),
                                          ),
                                        ],
                                      ),
                                      child: Center(
                                        child: Icon(
                                          isFavorite
                                              ? Icons.favorite_rounded
                                              : Icons.favorite_outline_rounded,
                                          size: 20,
                                          color: isFavorite
                                              ? AppColors.nonVegRed
                                              : (isDark ? AppColors.darkTextSecondary : AppColors.textHint),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                      // Info Section (Title, Origin, Description)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Veg/Non-Veg Tag + Shop Name Subtitle
                            Row(
                              children: [
                                widget.item.isVeg ? _buildVegIcon() : _buildNonVegIcon(),
                                const SizedBox(width: 8),
                                Text(
                                  widget.item.isVeg ? 'PURE VEG' : 'NON-VEG',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.6,
                                    color: widget.item.isVeg
                                        ? AppColors.vegGreen
                                        : AppColors.nonVegRed,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  width: 3,
                                  height: 3,
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade400,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    widget.shop.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),

                            // Item Name Title
                            Text(
                              widget.item.name,
                              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 22,
                                    height: 1.22,
                                    letterSpacing: -0.3,
                                  ),
                            ),
                            const SizedBox(height: 14),

                            // Thin Divider
                            Divider(
                              height: 1,
                              thickness: 1,
                              color: Theme.of(context).dividerColor.withValues(alpha: 0.08),
                            ),
                            const SizedBox(height: 14),

                            // Description Header
                            Text(
                              'DESCRIPTION',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.8,
                                color: isDark ? Colors.grey[400] : Colors.grey[500],
                              ),
                            ),
                            const SizedBox(height: 6),

                            // Complete Detailed Description (Never truncated)
                            Text(
                              widget.item.details.isNotEmpty
                                  ? widget.item.details
                                  : '${widget.item.name} is cooked fresh with high quality authentic ingredients, rich herbs, and served hot with delicious house-made dips.',
                              style: TextStyle(
                                fontSize: 14,
                                height: 1.55,
                                color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 20),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // 3. Sticky Bottom Action Bar (Fixed at bottom)
              Container(
                padding: EdgeInsets.fromLTRB(
                  20,
                  14,
                  20,
                  (bottomPadding > 0 ? bottomPadding : 16) + 12,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  border: Border(
                    top: BorderSide(
                      color: Theme.of(context).dividerColor.withValues(alpha: 0.08),
                    ),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.05),
                      blurRadius: 10,
                      offset: const Offset(0, -3),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Price Section
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'TOTAL PRICE',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.6,
                            color: isDark ? Colors.grey[400] : Colors.grey[500],
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.item.formattedPrice,
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 22,
                            letterSpacing: -0.4,
                            color: Theme.of(context).textTheme.bodyLarge?.color,
                          ),
                        ),
                      ],
                    ),

                    // Primary Action Button (Add to Cart / Interactive Stepper)
                    if (isItemAvailable)
                      quantityInCart > 0
                          ? _buildQuantityStepper(context, ref, quantityInCart)
                          : _buildAddButton(context, ref)
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.grey.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'Currently Unavailable',
                          style: TextStyle(
                            color: isDark ? Colors.grey[400] : Colors.grey[600],
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
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

  Widget _buildAddButton(BuildContext context, WidgetRef ref) {
    const primaryColor = AppColors.primary;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          tryAddToCart(
            context: context,
            ref: ref,
            item: widget.item,
            shopId: widget.shop.id,
            shopName: widget.shop.name,
          );
        },
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 28),
          decoration: BoxDecoration(
            color: primaryColor,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: primaryColor.withValues(alpha: 0.35),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.shopping_bag_outlined, size: 18, color: Colors.white),
              SizedBox(width: 8),
              Text(
                'Add to Cart',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuantityStepper(BuildContext context, WidgetRef ref, int quantity) {
    const primaryColor = AppColors.primary;
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: primaryColor,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: primaryColor.withValues(alpha: 0.35),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => ref.read(cartProvider.notifier).removeItem(widget.item.id),
              borderRadius: const BorderRadius.horizontal(left: Radius.circular(14)),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Icon(Icons.remove_rounded, size: 20, color: Colors.white),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              '$quantity',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 17,
              ),
            ),
          ),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => tryAddToCart(
                context: context,
                ref: ref,
                item: widget.item,
                shopId: widget.shop.id,
                shopName: widget.shop.name,
              ),
              borderRadius: const BorderRadius.horizontal(right: Radius.circular(14)),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Icon(Icons.add_rounded, size: 20, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

