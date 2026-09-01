// BU Gate2Eat — Home Screen
// Main screen featuring bottom navigation (Home → Favourites → Cart → Profile),
// search, and horizontal category & status filter chips.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_constants.dart';
import '../../core/providers.dart';
import '../../core/router.dart';
import '../../models/category_model.dart';
import '../../models/menu_item_model.dart';
import '../../models/shop_model.dart';
import '../cart/cart_provider.dart';
import '../cart/cart_screen.dart';
import '../favourites/favourites_screen.dart';
import '../orders/order_history_screen.dart';
import 'widgets/shop_card.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _currentIndex = 0;
  final Set<int> _visitedIndices = {0};

  void _onTabTapped(int index) {
    if (_currentIndex != index) {
      setState(() {
        _currentIndex = index;
        _visitedIndices.add(index);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cartState = ref.watch(cartProvider);
    final cartItemCount = cartState.totalItemCount;

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          const HomeTabContent(),
          _visitedIndices.contains(1)
              ? const FavouritesScreen()
              : const SizedBox.shrink(),
          _visitedIndices.contains(2)
              ? const CartScreen()
              : const SizedBox.shrink(),
          _visitedIndices.contains(3)
              ? const OrderHistoryScreen()
              : const SizedBox.shrink(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: _onTabTapped,
        items: [
          const BottomNavigationBarItem(
            icon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.favorite_outline_rounded),
            activeIcon: Icon(Icons.favorite_rounded),
            label: 'Favourites',
          ),
          BottomNavigationBarItem(
            icon: cartItemCount > 0
                ? Badge(
                    label: Text(
                      '$cartItemCount',
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    backgroundColor: AppColors.error,
                    child: const Icon(Icons.shopping_bag_outlined),
                  )
                : const Icon(Icons.shopping_bag_outlined),
            activeIcon: cartItemCount > 0
                ? Badge(
                    label: Text(
                      '$cartItemCount',
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    backgroundColor: AppColors.error,
                    child: const Icon(Icons.shopping_bag_rounded),
                  )
                : const Icon(Icons.shopping_bag_rounded),
            label: 'Cart',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.receipt_long_outlined),
            activeIcon: Icon(Icons.receipt_long_rounded),
            label: 'Orders',
          ),
        ],
      ),
    );
  }
}

class HomeTabContent extends ConsumerStatefulWidget {
  const HomeTabContent({
    this.onShopTap,
    this.floatingActionButton,
    super.key,
  });

  final void Function(Shop shop)? onShopTap;
  final Widget? floatingActionButton;

  @override
  ConsumerState<HomeTabContent> createState() => _HomeTabContentState();
}

class _HomeTabContentState extends ConsumerState<HomeTabContent> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedFilter = 'All';
  bool _isSearchActive = false;

  bool get _needsGlobalCatalog =>
      _isSearchActive ||
      _searchQuery.isNotEmpty ||
      (_selectedFilter != 'All' && _selectedFilter != 'Open Now');

  static const List<String> _filters = [
    'All',
    'Open Now',
    'Fast Food',
    'Snacks',
    'Thalis',
    'Chinese',
    'Veg',
    'Non-Veg',
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shopsAsync = ref.watch(shopsProvider);
    final Map<String, List<MenuItem>> allMenuItemsMap = _needsGlobalCatalog
        ? (ref.watch(allShopMenuItemsProvider).valueOrNull ?? const {})
        : const {};
    final Map<String, List<Category>> allCategoriesMap = _needsGlobalCatalog
        ? (ref.watch(allShopCategoriesProvider).valueOrNull ?? const {})
        : const {};
    final isCatalogLoading = _needsGlobalCatalog &&
        ((ref.watch(allShopMenuItemsProvider).isLoading) ||
            (ref.watch(allShopCategoriesProvider).isLoading));
    final activeOrders =
        ref.watch(customerActiveOrdersStreamProvider).valueOrNull ?? [];

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screenWidth = MediaQuery.of(context).size.width;
    final horizontalPadding = screenWidth < 360 ? 10.0 : (screenWidth < 400 ? 14.0 : 16.0);

    return Scaffold(
      floatingActionButton: widget.floatingActionButton ??
          (activeOrders.isNotEmpty
              ? FloatingActionButton.extended(
                  onPressed: () {
                    context.push(AppRoutes.activeOrders);
                  },
                  backgroundColor: AppColors.primary,
                  elevation: 4,
                  icon: const Icon(
                    Icons.delivery_dining_rounded,
                    color: Colors.white,
                  ),
                  label: Text(
                    activeOrders.length > 1
                        ? 'Active Orders (${activeOrders.length})'
                        : 'Track Your Order',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.2,
                    ),
                  ),
                )
              : null),
      appBar: AppBar(
        title: Image.asset(
          'assets/images/yummbu_wordmark.png',
          height: 30,
          fit: BoxFit.contain,
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: InkWell(
              onTap: () => context.push(AppRoutes.profile),
              borderRadius: BorderRadius.circular(20),
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primary.withValues(
                    alpha: isDark ? 0.20 : 0.12,
                  ),
                  border: Border.all(
                    color: AppColors.primary.withValues(
                      alpha: isDark ? 0.50 : 0.35,
                    ),
                    width: 1.3,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: isDark
                          ? Colors.black.withValues(alpha: 0.30)
                          : AppColors.primary.withValues(alpha: 0.10),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Center(
                  child: Icon(
                    Icons.person_rounded,
                    size: 21,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // ─── 1. Search Bar ──────────────────────────────────────────
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: horizontalPadding,
              vertical: AppSpacing.sm,
            ),
            child: Container(
              height: 48,
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: TextField(
                controller: _searchController,
                textAlignVertical: TextAlignVertical.center,
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
                ),
                onTap: () {
                  if (!_isSearchActive) {
                    setState(() => _isSearchActive = true);
                  }
                },
                decoration: InputDecoration(
                  hintText: 'Search shops or food (e.g. momos)...',
                  hintStyle: TextStyle(
                    fontSize: 14,
                    color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
                    fontWeight: FontWeight.w400,
                  ),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    size: 22,
                    color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
                  ),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, size: 20),
                          color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                ),
                onChanged: (value) => setState(() {
                  _searchQuery = value.trim().toLowerCase();
                  if (!_isSearchActive) _isSearchActive = true;
                }),
              ),
            ),
          ),

          // ─── 2. Filter Pills Row ──────────────────────────────────
          SizedBox(
            height: 38,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
              itemCount: _filters.length,
              itemBuilder: (context, index) {
                final filter = _filters[index];
                final isSelected = _selectedFilter == filter;
                final isOpenNow = filter == 'Open Now';

                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: InkWell(
                    onTap: () {
                      setState(() {
                        _selectedFilter = filter;
                        if (filter != 'All' && filter != 'Open Now') {
                          _isSearchActive = true;
                        }
                      });
                    },
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppColors.primary
                            : (isDark ? AppColors.darkSurfaceVariant : Colors.white),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isSelected
                              ? AppColors.primary
                              : (isDark ? AppColors.darkDivider : AppColors.divider),
                          width: 1.1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isOpenNow) ...[
                            Container(
                              width: 7.5,
                              height: 7.5,
                              margin: const EdgeInsets.only(right: 6),
                              decoration: const BoxDecoration(
                                color: AppColors.vegGreen,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ],
                          Text(
                            filter,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                              color: isSelected
                                  ? Colors.white
                                  : (isDark ? AppColors.darkTextPrimary : AppColors.textPrimary),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: AppSpacing.sm),

          // ─── 3. Shop List ───────────────────────────────────────────
          Expanded(
            child: shopsAsync.when(
              loading: () => const Center(
                child: CircularProgressIndicator(),
              ),
              error: (error, stack) {
                debugPrint('🔥 Error fetching shops from Firestore: $error\n$stack');
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.error_outline_rounded,
                          size: 48,
                          color: AppColors.error,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          'Error Loading Shops',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          '$error',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        ElevatedButton.icon(
                          onPressed: () => ref.invalidate(shopsProvider),
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                );
              },
              data: (shops) {
                // Filter shops by search query AND active filter pill
                // Authoritative fields ONLY: shop.name, menuItem.name, category.name, menuItem.isVeg, shop.isOpen
                // Description/details fields are NEVER used for search or filtering.
                final filteredShops = shops.where((shop) {
                  final menuItems = allMenuItemsMap[shop.id] ?? const [];
                  final categories = allCategoriesMap[shop.id] ?? const [];

                  // 1. Search Query Filter (Matches shop.name OR actual menuItem.name)
                  if (_searchQuery.isNotEmpty) {
                    final query = _searchQuery;
                    final nameMatches =
                        shop.name.toLowerCase().contains(query);
                    final foodMatches = menuItems.any(
                      (item) => item.name.toLowerCase().contains(query),
                    );
                    if (!nameMatches && !foodMatches) return false;
                  }

                  // 2. Category / Status Filter Pill (Authoritative data only)
                  switch (_selectedFilter) {
                    case 'Open Now':
                      return shop.isOpen;
                    case 'Fast Food':
                      final catMatch = categories.any(
                        (c) =>
                            c.name.toLowerCase().contains('fast food') ||
                            c.name.toLowerCase().contains('fastfood'),
                      );
                      final itemMatch = menuItems.any(
                        (i) =>
                            i.name.toLowerCase().contains('burger') ||
                            i.name.toLowerCase().contains('pizza') ||
                            i.name.toLowerCase().contains('sandwich') ||
                            i.name.toLowerCase().contains('wrap') ||
                            i.name.toLowerCase().contains('fast food'),
                      );
                      return catMatch || itemMatch;
                    case 'Snacks':
                      final catMatch = categories.any(
                        (c) => c.name.toLowerCase().contains('snack'),
                      );
                      final itemMatch = menuItems.any(
                        (i) =>
                            i.name.toLowerCase().contains('snack') ||
                            i.name.toLowerCase().contains('fries') ||
                            i.name.toLowerCase().contains('maggi') ||
                            i.name.toLowerCase().contains('nugget') ||
                            i.name.toLowerCase().contains('nachos') ||
                            i.name.toLowerCase().contains('garlic bread'),
                      );
                      return catMatch || itemMatch;
                    case 'Thalis':
                      final catMatch = categories.any(
                        (c) => c.name.toLowerCase().contains('thali'),
                      );
                      final itemMatch = menuItems.any(
                        (i) => i.name.toLowerCase().contains('thali'),
                      );
                      return catMatch || itemMatch;
                    case 'Chinese':
                      final catMatch = categories.any(
                        (c) =>
                            c.name.toLowerCase().contains('chinese') ||
                            c.name.toLowerCase().contains('momo') ||
                            c.name.toLowerCase().contains('noodle'),
                      );
                      final itemMatch = menuItems.any(
                        (i) =>
                            i.name.toLowerCase().contains('chinese') ||
                            i.name.toLowerCase().contains('momo') ||
                            i.name.toLowerCase().contains('noodle') ||
                            i.name.toLowerCase().contains('manchurian') ||
                            i.name.toLowerCase().contains('chowmein'),
                      );
                      return catMatch || itemMatch;
                    case 'Veg':
                      // Shop must offer at least one vegetarian menu item
                      return menuItems.any((item) => item.isVeg);
                    case 'Non-Veg':
                      // Shop must offer at least one non-vegetarian menu item
                      return menuItems.any((item) => !item.isVeg);
                    case 'All':
                    default:
                      return true;
                  }
                }).toList();

                if (filteredShops.isEmpty) {
                  if (isCatalogLoading) {
                    return const Center(
                      child: CircularProgressIndicator(),
                    );
                  }
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.store_mall_directory_outlined,
                          size: 48,
                          color: isDark ? AppColors.darkTextSecondary : AppColors.textHint,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          _searchQuery.isEmpty
                              ? (_selectedFilter != 'All'
                                  ? 'No shops found for "$_selectedFilter"'
                                  : 'No shops available')
                              : 'No shops found for "$_searchQuery"',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
                              ),
                        ),
                      ],
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(shopsProvider);
                  },
                  child: ListView.builder(
                    padding: EdgeInsets.fromLTRB(
                      horizontalPadding,
                      4,
                      horizontalPadding,
                      16 + MediaQuery.of(context).padding.bottom,
                    ),
                    itemCount: filteredShops.length,
                    itemBuilder: (context, index) {
                      final shop = filteredShops[index];
                      return ShopCard(
                        shop: shop,
                        onTap: () {
                          if (widget.onShopTap != null) {
                            widget.onShopTap!(shop);
                          } else {
                            context.push('/shop/${shop.id}');
                          }
                        },
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
