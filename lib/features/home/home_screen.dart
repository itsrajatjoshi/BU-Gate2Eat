// BU Gate2Eat — Home Screen
// Main screen featuring bottom navigation (Home → Favourites → Cart → Profile),
// search, and horizontal category & status filter chips.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_constants.dart';
import '../../core/providers.dart';
import '../../core/router.dart';
import '../cart/cart_provider.dart';
import '../cart/cart_screen.dart';
import '../favourites/favourites_screen.dart';
import '../profile/profile_screen.dart';
import 'widgets/shop_card.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final cartState = ref.watch(cartProvider);
    final cartItemCount = cartState.totalItemCount;

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: const [
          _HomeTabContent(),
          FavouritesScreen(),
          CartScreen(),
          ProfileScreen(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
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
            icon: Icon(Icons.person_outline_rounded),
            activeIcon: Icon(Icons.person_rounded),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

class _HomeTabContent extends ConsumerStatefulWidget {
  const _HomeTabContent();

  @override
  ConsumerState<_HomeTabContent> createState() => _HomeTabContentState();
}

class _HomeTabContentState extends ConsumerState<_HomeTabContent> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedFilter = 'All';

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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screenWidth = MediaQuery.of(context).size.width;
    final horizontalPadding = screenWidth < 360 ? 10.0 : (screenWidth < 400 ? 14.0 : 16.0);

    return Scaffold(
      appBar: AppBar(
        title: Image.asset(
          'assets/images/yummbu_wordmark.png',
          height: 30,
          fit: BoxFit.contain,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push(AppRoutes.settings),
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
                onChanged: (value) => setState(
                  () => _searchQuery = value.trim().toLowerCase(),
                ),
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
                final filteredShops = shops.where((shop) {
                  // 1. Search Query Filter
                  if (_searchQuery.isNotEmpty) {
                    final nameMatches = shop.name.toLowerCase().contains(_searchQuery);
                    final keywordMatches = shop.searchKeywords.any(
                      (k) => k.toLowerCase().contains(_searchQuery),
                    );
                    final descMatches = shop.description.toLowerCase().contains(_searchQuery);
                    if (!nameMatches && !keywordMatches && !descMatches) return false;
                  }

                  // 2. Category / Status Filter Pill
                  switch (_selectedFilter) {
                    case 'Open Now':
                      return shop.isOpen;
                    case 'Fast Food':
                      return shop.searchKeywords.any(
                            (k) =>
                                k.toLowerCase().contains('fast food') ||
                                k.toLowerCase().contains('fastfood'),
                          ) ||
                          shop.description.toLowerCase().contains('fast food');
                    case 'Snacks':
                      return shop.searchKeywords.any(
                            (k) => k.toLowerCase().contains('snack'),
                          ) ||
                          shop.description.toLowerCase().contains('snack');
                    case 'Thalis':
                      return shop.searchKeywords.any(
                            (k) => k.toLowerCase().contains('thali'),
                          ) ||
                          shop.description.toLowerCase().contains('thali');
                    case 'Chinese':
                      return shop.searchKeywords.any(
                            (k) =>
                                k.toLowerCase().contains('chinese') ||
                                k.toLowerCase().contains('momo') ||
                                k.toLowerCase().contains('noodle'),
                          ) ||
                          shop.description.toLowerCase().contains('chinese');
                    case 'Veg':
                      return true; // Both shops offer vegetarian items
                    case 'Non-Veg':
                      return shop.searchKeywords.any(
                            (k) =>
                                k.toLowerCase().contains('non-veg') ||
                                k.toLowerCase().contains('chicken'),
                          ) ||
                          shop.id == 'nayan_shop' ||
                          shop.description.toLowerCase().contains('chicken');
                    case 'All':
                    default:
                      return true;
                  }
                }).toList();

                if (filteredShops.isEmpty) {
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
                        onTap: () => context.push('/shop/${shop.id}'),
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
