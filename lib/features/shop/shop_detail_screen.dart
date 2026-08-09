// BU Gate2Eat — Shop Detail Screen
// Shows menu, categories, search, veg/non-veg filter, and add-to-cart
// Features a premium collapsing header (fade, blur, compact title transition)

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
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
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.info_outline_rounded, color: Colors.white, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'No items currently available in ${categoryObj.name}',
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF1E293B),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
    final allCat = const Category(
      id: 'all',
      name: 'All',
      sortOrder: 0,
      imageUrl: 'https://images.unsplash.com/photo-1534422298391-e4f8c172dddb?w=300&auto=format&fit=crop&q=80',
      isActive: true,
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
        ));
      }
    }

    // If fetched is empty or loading, provide shop default fallback categories
    if (list.length == 1) {
      if (shopId == 'rajat_shop' || shopId.contains('rajat')) {
        list.addAll([
          const Category(id: 'momos', name: 'Momos', sortOrder: 1, imageUrl: 'https://images.unsplash.com/photo-1541696432-82c6da8ce7bf?w=300&auto=format&fit=crop&q=80'),
          const Category(id: 'pizzas', name: 'Pizzas', sortOrder: 2, imageUrl: 'https://images.unsplash.com/photo-1513104890138-7c749659a591?w=300&auto=format&fit=crop&q=80'),
          const Category(id: 'burgers', name: 'Burgers', sortOrder: 3, imageUrl: 'https://images.unsplash.com/photo-1568901346375-23c9450c58cd?w=300&auto=format&fit=crop&q=80'),
          const Category(id: 'biryani', name: 'Biryani', sortOrder: 4, imageUrl: 'https://images.unsplash.com/photo-1633945274405-b6c8069047b0?w=300&auto=format&fit=crop&q=80'),
          const Category(id: 'thalis', name: 'Thali', sortOrder: 5, imageUrl: 'https://images.unsplash.com/photo-1626777552726-4a6b54c97e46?w=300&auto=format&fit=crop&q=80'),
          const Category(id: 'snacks', name: 'Snacks', sortOrder: 6, imageUrl: 'https://images.unsplash.com/photo-1601050690597-df0568f70950?w=300&auto=format&fit=crop&q=80'),
        ]);
      } else if (shopId == 'nayan_shop' || shopId.contains('nayan')) {
        list.addAll([
          const Category(id: 'momos', name: 'Momos', sortOrder: 1, imageUrl: 'https://images.unsplash.com/photo-1541696432-82c6da8ce7bf?w=300&auto=format&fit=crop&q=80'),
          const Category(id: 'rolls', name: 'Rolls', sortOrder: 2, imageUrl: 'https://images.unsplash.com/photo-1626700051175-6818013e1d4f?w=300&auto=format&fit=crop&q=80'),
          const Category(id: 'noodles', name: 'Noodles', sortOrder: 3, imageUrl: 'https://images.unsplash.com/photo-1612927601601-6638404737ce?w=300&auto=format&fit=crop&q=80'),
          const Category(id: 'snacks', name: 'Snacks', sortOrder: 4, imageUrl: 'https://images.unsplash.com/photo-1601050690597-df0568f70950?w=300&auto=format&fit=crop&q=80'),
          const Category(id: 'thalis', name: 'Thali', sortOrder: 5, imageUrl: 'https://images.unsplash.com/photo-1626777552726-4a6b54c97e46?w=300&auto=format&fit=crop&q=80'),
        ]);
      }
    }

    return list;
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

              // Sticky Category Navigation Header
              SliverPersistentHeader(
                pinned: true,
                delegate: _StickyCategoryHeaderDelegate(
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
        var filtered = menuItems.where((item) {
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
            return [
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.all(32.0),
                    child: Text('No matching items found', style: TextStyle(color: AppColors.textHint)),
                  ),
                ),
              ),
            ];
          }
          return [
            _buildFlatSliverList(filtered, shop, isOpen, cartItems),
            const SliverToBoxAdapter(child: SizedBox(height: 80)),
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
                padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.lg, AppSpacing.md, AppSpacing.sm),
                child: Row(
                  children: [
                    Text(
                      category.name,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${categoryItems.length}',
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );

          // 2-column Grid for Category Items
          slivers.add(
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.65,
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

        if (slivers.isEmpty) {
          return [
            _buildFlatSliverList(filtered, shop, isOpen, cartItems),
            const SliverToBoxAdapter(child: SizedBox(height: 80)),
          ];
        }

        slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 100)));
        return slivers;
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
          childAspectRatio: 0.65,
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
    required this.cartItems,
  });

  final MenuItem item;
  final Shop shop;
  final bool isShopOpen;
  final List<CartItem> cartItems;

  Widget _buildVegIcon() {
    return Container(
      width: 13,
      height: 13,
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFF388E3C), width: 1.2),
        borderRadius: BorderRadius.circular(2.5),
      ),
      child: Center(
        child: Container(
          width: 5,
          height: 5,
          decoration: const BoxDecoration(
            color: Color(0xFF388E3C),
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }

  Widget _buildNonVegIcon() {
    return Container(
      width: 13,
      height: 13,
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFD32F2F), width: 1.2),
        borderRadius: BorderRadius.circular(2.5),
      ),
      child: const Center(
        child: CustomPaint(
          size: Size(6, 6),
          painter: _TrianglePainter(color: Color(0xFFD32F2F)),
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
  }) {
    const primaryColor = Color(0xFF5C59E5);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        InkWell(
          key: key,
          borderRadius: BorderRadius.circular(8),
          onTap: () => _handleCartChange(ref, context, 1),
          child: Container(
            width: 66,
            height: 30,
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
                  fontSize: 13.5,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 2),
        const Text(
          'customizable',
          style: TextStyle(
            color: AppColors.textHint,
            fontSize: 9.5,
            fontWeight: FontWeight.w400,
          ),
        ),
      ],
    );
  }

  Widget _buildQuantityStepper({
    required Key key,
    required BuildContext context,
    required WidgetRef ref,
    required int quantity,
  }) {
    const primaryColor = Color(0xFF5C59E5);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          key: key,
          width: 66,
          height: 30,
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
                  padding: EdgeInsets.symmetric(horizontal: 4.0, vertical: 2.0),
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
                  padding: EdgeInsets.symmetric(horizontal: 4.0, vertical: 2.0),
                  child: Icon(Icons.add_rounded, size: 14, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 2),
        const Text(
          'customizable',
          style: TextStyle(
            color: AppColors.textHint,
            fontSize: 9.5,
            fontWeight: FontWeight.w400,
          ),
        ),
      ],
    );
  }

  void _handleCartChange(WidgetRef ref, BuildContext context, int delta) {
    final cart = ref.read(cartProvider);
    final cartNotifier = ref.read(cartProvider.notifier);

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
    final displayImageUrl = _getEffectiveImageUrl(item);
    final favorites = ref.watch(favoritesProvider);
    final isFavorite = favorites.contains(item.id);

    final cartItem = cartItems
        .where((ci) => ci.menuItem.id == item.id)
        .toList();
    final quantityInCart =
        cartItem.isNotEmpty ? cartItem.first.quantity : 0;

    final originalPrice = (item.price * 1.35).round();

    return Opacity(
      opacity: isAvailable ? 1.0 : 0.55,
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.1),
            width: 0.8,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Food Image Container (~52% height)
            AspectRatio(
              aspectRatio: 1.35,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
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

                  // Favorite Heart Button (Top-Right overlay)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: GestureDetector(
                      onTap: () {
                        ref
                            .read(favoritesProvider.notifier)
                            .toggleFavorite(item.id);
                      },
                      child: Container(
                        width: 26,
                        height: 26,
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
                            size: 15,
                            color: isFavorite
                                ? const Color(0xFFE53935)
                                : AppColors.textHint,
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
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Item Title with Veg/Non-Veg icon
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            item.isVeg ? _buildVegIcon() : _buildNonVegIcon(),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                item.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                      height: 1.15,
                                    ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),

                        // Description
                        Text(
                          item.details.isNotEmpty
                              ? item.details
                              : '${item.name} served fresh with authentic taste & special dips.',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 10,
                            height: 1.2,
                          ),
                        ),

                        const SizedBox(height: 3),

                        // Rating stars row
                        Row(
                          children: [
                            ...List.generate(
                              4,
                              (index) => const Icon(
                                Icons.star_rounded,
                                size: 11,
                                color: Color(0xFFFFA000),
                              ),
                            ),
                            const Icon(
                              Icons.star_half_rounded,
                              size: 11,
                              color: Color(0xFFFFA000),
                            ),
                            const SizedBox(width: 3),
                            Text(
                              '2 Ratings',
                              style: TextStyle(
                                fontSize: 9.5,
                                color: Colors.grey.shade500,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),

                    // Bottom Row: Price Stack + Add Button / Stepper
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        // Price & Discount Stack
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Text(
                                  item.formattedPrice,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 14.5,
                                    color: Theme.of(context)
                                        .textTheme
                                        .bodyLarge
                                        ?.color,
                                  ),
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  '₹$originalPrice',
                                  style: TextStyle(
                                    decoration: TextDecoration.lineThrough,
                                    decorationColor: Colors.grey.shade400,
                                    color: Colors.grey.shade500,
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w400,
                                  ),
                                ),
                                const SizedBox(width: 1),
                                const Icon(
                                  Icons.bolt_rounded,
                                  size: 12,
                                  color: Color(0xFFFFB300),
                                ),
                              ],
                            ),
                            const SizedBox(height: 1),
                            const Text(
                              '25% OFF',
                              style: TextStyle(
                                color: Color(0xFF5C59E5),
                                fontWeight: FontWeight.bold,
                                fontSize: 10.5,
                              ),
                            ),
                          ],
                        ),

                        // Add Button / Stepper with customizable text
                        if (isAvailable)
                          quantityInCart > 0
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

/// Delegate for pinning Category Navigation Header when scrolling
class _StickyCategoryHeaderDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;

  const _StickyCategoryHeaderDelegate({
    required this.child,
  });

  static const double _headerHeight = 100.0;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: _headerHeight,
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
  double get maxExtent => _headerHeight;

  @override
  double get minExtent => _headerHeight;

  @override
  bool shouldRebuild(covariant _StickyCategoryHeaderDelegate oldDelegate) {
    return oldDelegate.child != child;
  }
}

/// Horizontal category navigation matching reference UI design
class _CategoryNavWidget extends StatelessWidget {
  final List<Category> categories;
  final String selectedCategoryId;
  final ValueChanged<String> onCategorySelected;
  final ScrollController scrollController;

  const _CategoryNavWidget({
    required this.categories,
    required this.selectedCategoryId,
    required this.onCategorySelected,
    required this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const primaryColor = Color(0xFFE65100); // Warm orange matching reference screenshot

    return ListView.separated(
      controller: scrollController,
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      itemCount: categories.length,
      separatorBuilder: (_, __) => const SizedBox(width: 16),
      itemBuilder: (context, index) {
        final cat = categories[index];
        final isSelected = selectedCategoryId == cat.id;

        return GestureDetector(
          onTap: () => onCategorySelected(cat.id),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  // Circular category photo container
                  Container(
                    width: 58,
                    height: 58,
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
                        width: 53,
                        height: 53,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Container(
                          color: isDark ? Colors.grey[850] : Colors.grey[200],
                          child: const Icon(Icons.fastfood_rounded, size: 22, color: Colors.grey),
                        ),
                        errorWidget: (context, url, error) => Container(
                          color: isDark ? Colors.grey[850] : Colors.grey[200],
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
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          color: primaryColor,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Theme.of(context).scaffoldBackgroundColor,
                            width: 1.5,
                          ),
                        ),
                        child: const Center(
                          child: Icon(
                            Icons.check_rounded,
                            size: 11,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),

              // Category Name Label
              Text(
                cat.name,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  color: isSelected
                      ? primaryColor
                      : (isDark ? Colors.white70 : Colors.black87),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

