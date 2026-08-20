// BU Gate2Eat — Shopkeeper Panel
// Shopkeeper Home Screen (Connected to Firestore & Real-Time Data)
// UI/UX Visual Match with User ShopDetailScreen

import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/providers.dart';
import '../../../models/category_model.dart';
import '../../../models/menu_item_model.dart';
import '../../../models/shop_model.dart';
import '../admin_panel/widgets/delete_shop_dialog.dart';
import 'widgets/add_content_modal.dart';
import 'widgets/edit_menu_item_modal.dart';
import 'widgets/edit_shop_modal.dart';

/// Filter state for veg/non-veg.
enum FoodFilter { all, veg, nonVeg }

class ShopkeeperHomeScreen extends ConsumerStatefulWidget {
  const ShopkeeperHomeScreen({
    this.shopId = 'rajat_shop',
    this.isAdmin = false,
    super.key,
  });

  final String shopId;
  final bool isAdmin;

  @override
  ConsumerState<ShopkeeperHomeScreen> createState() =>
      _ShopkeeperHomeScreenState();
}

class _ShopkeeperHomeScreenState extends ConsumerState<ShopkeeperHomeScreen> {
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

  /// Detects active section on main list scroll and syncs top category tab
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

    if (newlyVisibleCategory != null &&
        newlyVisibleCategory != _selectedCategoryId) {
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
      final targetOffset =
          (index * itemWidth) - (screenWidth / 2) + (itemWidth / 2) + 14;
      _categoryScrollController.animateTo(
        targetOffset.clamp(
          0.0,
          _categoryScrollController.position.maxScrollExtent,
        ),
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
      );
    }
  }

  /// Tapping a top category tab smoothly scrolls main menu list to that section
  void _onCategoryTapped(String catId) {
    setState(() {
      _selectedCategoryId = catId;
    });
    _autoScrollCategoryTab(catId);

    final targetKey = _categoryKeys[catId];
    if (targetKey != null && targetKey.currentContext != null) {
      _isManualCategoryTap = true;
      Scrollable.ensureVisible(
        targetKey.currentContext!,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOutCubic,
        alignment: 0.18,
      ).then((_) {
        Future.delayed(const Duration(milliseconds: 150), () {
          if (mounted) {
            setState(() {
              _isManualCategoryTap = false;
            });
          }
        });
      });
    }
  }

  List<Category> _getEffectiveCategories(
    String shopId,
    List<Category>? rawCategories,
  ) {
    final list = <Category>[
      Category(
        id: 'all',
        name: 'All',
        sortOrder: 0,
        imageUrl:
            'https://images.unsplash.com/photo-1541696432-82c6da8ce7bf?w=300&auto=format&fit=crop&q=80',
        shopId: shopId,
      ),
    ];

    if (rawCategories != null && rawCategories.isNotEmpty) {
      for (final c in rawCategories) {
        String img = c.imageUrl;
        if (img.isEmpty) {
          final nameL = c.name.toLowerCase();
          if (nameL.contains('momo')) {
            img =
                'https://images.unsplash.com/photo-1541696432-82c6da8ce7bf?w=300&auto=format&fit=crop&q=80';
          } else if (nameL.contains('pizza')) {
            img =
                'https://images.unsplash.com/photo-1513104890138-7c749659a591?w=300&auto=format&fit=crop&q=80';
          } else if (nameL.contains('burger')) {
            img =
                'https://images.unsplash.com/photo-1568901346375-23c9450c58cd?w=300&auto=format&fit=crop&q=80';
          } else if (nameL.contains('biryani')) {
            img =
                'https://images.unsplash.com/photo-1633945274405-b6c8069047b0?w=300&auto=format&fit=crop&q=80';
          } else if (nameL.contains('thali')) {
            img =
                'https://images.unsplash.com/photo-1626777552726-4a6b54c97e46?w=300&auto=format&fit=crop&q=80';
          } else {
            img =
                'https://images.unsplash.com/photo-1601050690597-df0568f70950?w=300&auto=format&fit=crop&q=80';
          }
        }
        list.add(
          Category(
            id: c.id,
            name: c.name,
            sortOrder: c.sortOrder,
            imageUrl: img,
            isActive: c.isActive,
            shopId: shopId,
          ),
        );
      }
    }

    return list;
  }

  /// Calculates responsive Grid parameters based on screen width & text scale
  static SliverGridDelegateWithFixedCrossAxisCount _getResponsiveGridDelegate(
    BuildContext context,
  ) {
    final screenWidth = MediaQuery.of(context).size.width;
    final horizontalPadding =
        screenWidth < 360 ? 10.0 : (screenWidth < 400 ? 12.0 : 14.0);
    final crossAxisSpacing = screenWidth < 360 ? 8.0 : 10.0;
    final mainAxisSpacing = screenWidth < 360 ? 10.0 : 12.0;

    final availableWidth =
        screenWidth - (horizontalPadding * 2) - crossAxisSpacing;
    final cardWidth = availableWidth / 2;

    final textScale = MediaQuery.textScalerOf(context).scale(1.0);
    final extraTextHeight = (textScale > 1.0) ? (textScale - 1.0) * 36.0 : 0.0;

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

  @override
  Widget build(BuildContext context) {
    final shopsAsync = ref.watch(shopsProvider);
    final categoriesAsync = ref.watch(shopCategoriesProvider(widget.shopId));
    final menuItemsAsync = ref.watch(shopMenuItemsProvider(widget.shopId));

    final shops = shopsAsync.value ?? [];
    final shop = shops.where((s) => s.id == widget.shopId).firstOrNull ??
        Shop(
          id: widget.shopId,
          name: widget.shopId == 'rajat_shop' ? 'Rajat Shop' : 'Shop',
          description: '',
          bannerUrl: '',
          contactNumber: widget.shopId == 'rajat_shop' ? '8295643910' : '',
          orderNumber: widget.shopId == 'rajat_shop' ? '8295643910' : '',
          openTime: '08:00',
          closeTime: '23:30',
          isClosedOverride: false,
          isActive: true,
          sortOrder: 1,
          searchKeywords: const [],
          deliveryNote: 'Pickup from Gate 2',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

    final rawCategories = categoriesAsync.value ?? [];
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const double expandedHeaderHeight = 160.0;

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => AddContentModal.show(
          context,
          categories: rawCategories,
          shopId: shop.id,
        ),
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: const Text(
          'Add',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: CustomScrollView(
        controller: _mainScrollController,
        physics: const BouncingScrollPhysics(),
        slivers: [
          // ─── 1. Collapsing SliverAppBar (Identical to User App) ─────
          SliverAppBar(
            pinned: true,
            expandedHeight: expandedHeaderHeight,
            elevation: 0,
            scrolledUnderElevation: 0,
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    widget.isAdmin ? 'ADMIN' : 'SHOPKEEPER',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      color: AppColors.primary,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    shop.name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 17,
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              if (widget.isAdmin)
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert_rounded),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  onSelected: (value) async {
                    if (value == 'edit') {
                      EditShopModal.show(context, shop);
                    } else if (value == 'delete') {
                      final deleted =
                          await DeleteShopDialog.show(context, shop);
                      if (deleted == true && context.mounted) {
                        Navigator.of(context).pop();
                      }
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          Icon(Icons.edit_outlined, size: 18),
                          SizedBox(width: 10),
                          Text('Edit Shop Info'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(
                            Icons.delete_outline_rounded,
                            color: AppColors.error,
                            size: 18,
                          ),
                          SizedBox(width: 10),
                          Text(
                            'Delete Shop',
                            style: TextStyle(color: AppColors.error),
                          ),
                        ],
                      ),
                    ),
                  ],
                )
              else
                IconButton(
                  tooltip: 'Edit Shop Info',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => EditShopModal.show(context, shop),
                ),
            ],
            flexibleSpace: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final double top = constraints.biggest.height;
                final double statusBarHeight =
                    MediaQuery.of(context).padding.top;
                final double minHeight = kToolbarHeight + statusBarHeight;
                final double maxHeight = expandedHeaderHeight + statusBarHeight;

                final double delta = maxHeight - minHeight;
                final double t = delta > 0
                    ? ((top - minHeight) / delta).clamp(0.0, 1.0)
                    : 0.0;
                final double bannerOpacity = t;
                final double blurSigma = (1.0 - t) * 12.0;

                return FlexibleSpaceBar(
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
                                  memCacheWidth: 800,
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
                            Positioned.fill(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Colors.black.withValues(alpha: 0.25 * t),
                                      Theme.of(context)
                                          .scaffoldBackgroundColor
                                          .withValues(
                                            alpha: (1.0 - t) * 0.9,
                                          ),
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

          // ─── 2. Shop Info, Search & Filter Section (Exact User Styling) ─
          SliverToBoxAdapter(
            child: Builder(
              builder: (context) {
                final screenWidth = MediaQuery.of(context).size.width;
                final horizontalPadding = screenWidth < 360
                    ? 10.0
                    : (screenWidth < 400 ? 12.0 : 14.0);

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Shop Info Section
                    Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: horizontalPadding,
                        vertical: 12,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      shop.name,
                                      style: Theme.of(context)
                                          .textTheme
                                          .headlineSmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: -0.3,
                                          ),
                                    ),
                                    if (shop.description.isNotEmpty) ...[
                                      const SizedBox(height: AppSpacing.xs),
                                      Text(
                                        shop.description,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyMedium
                                            ?.copyWith(
                                              color: isDark
                                                  ? AppColors.darkTextSecondary
                                                  : AppColors.textSecondary,
                                            ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),

                              // Shop Edit Button
                              OutlinedButton.icon(
                                onPressed: () =>
                                    EditShopModal.show(context, shop),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppColors.primary,
                                  side: const BorderSide(
                                    color: AppColors.primary,
                                    width: 1.2,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  visualDensity: VisualDensity.compact,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                icon: const Icon(Icons.edit_outlined, size: 15),
                                label: const Text(
                                  'Edit',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.sm),

                          // Open/Closed badge, timing and delivery note (Live status)
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.sm,
                                  vertical: AppSpacing.xs,
                                ),
                                decoration: BoxDecoration(
                                  color: (shop.isOpen
                                          ? AppColors.success
                                          : AppColors.error)
                                      .withValues(alpha: 0.1),
                                  borderRadius:
                                      BorderRadius.circular(AppRadius.sm),
                                ),
                                child: Text(
                                  shop.isOpen ? 'Open Now' : 'Closed',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: shop.isOpen
                                            ? AppColors.success
                                            : AppColors.error,
                                        fontWeight: FontWeight.w600,
                                      ),
                                ),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Icon(
                                Icons.access_time_rounded,
                                size: 14,
                                color: isDark
                                    ? AppColors.darkTextSecondary
                                    : AppColors.textHint,
                              ),
                              const SizedBox(width: AppSpacing.xs),
                              Text(
                                shop.formattedTimings,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: isDark
                                          ? AppColors.darkTextSecondary
                                          : AppColors.textHint,
                                    ),
                              ),
                              const Spacer(),
                              Text(
                                shop.deliveryNote.isNotEmpty
                                    ? shop.deliveryNote
                                    : 'Pickup from Gate 2',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: isDark
                                          ? AppColors.darkTextSecondary
                                          : AppColors.textHint,
                                    ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const Divider(height: 1),

                    // Search bar (Exact User App Search styling)
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
                        onChanged: (value) => setState(
                          () => _searchQuery = value.trim().toLowerCase(),
                        ),
                      ),
                    ),

                    // Veg/Non-Veg filter chips (Exact User App FilterChip styling)
                    Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: horizontalPadding,
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
                  ],
                );
              },
            ),
          ),

          // ─── 3. Sticky Category Header (Exact User App CategoryNavWidget) ─
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

          // ─── 4. Menu Items Section: 2-Column Grid (Exact User App) ──
          ..._buildMenuSlivers(
            context: context,
            menuItemsAsync: menuItemsAsync,
            categoriesAsync: categoriesAsync,
            selectedCategoryId: _selectedCategoryId,
            searchQuery: _searchQuery,
            foodFilter: _foodFilter,
            shop: shop,
            rawCategories: rawCategories,
          ),
        ],
      ),
    );
  }

  /// Builds slivers for menu items list (2-Column Grid with Section Headers)
  List<Widget> _buildMenuSlivers({
    required BuildContext context,
    required AsyncValue<List<MenuItem>> menuItemsAsync,
    required AsyncValue<List<Category>> categoriesAsync,
    required String selectedCategoryId,
    required String searchQuery,
    required FoodFilter foodFilter,
    required Shop shop,
    required List<Category> rawCategories,
  }) {
    final screenWidth = MediaQuery.of(context).size.width;
    final horizontalPadding =
        screenWidth < 360 ? 10.0 : (screenWidth < 400 ? 12.0 : 14.0);
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
                        color: isDark
                            ? AppColors.darkTextSecondary
                            : AppColors.textSecondary,
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
            SliverPadding(
              padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
              sliver: SliverGrid(
                gridDelegate: gridDelegate,
                delegate: SliverChildBuilderDelegate(
                  (context, index) => _ShopkeeperMenuItemCard(
                    key: ValueKey('${shop.id}_${filtered[index].id}'),
                    item: filtered[index],
                    shop: shop,
                    categories: rawCategories,
                  ),
                  childCount: filtered.length,
                ),
              ),
            ),
            SliverToBoxAdapter(
              child:
                  SizedBox(height: 80 + MediaQuery.of(context).padding.bottom),
            ),
          ];
        }

        // Categorized 2-column Grid sections matching User App exactly
        final effectiveCategories =
            _getEffectiveCategories(shop.id, categoriesAsync.value);
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

          // Section Title Header
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
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2.5,
                      ),
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
                  (context, index) => _ShopkeeperMenuItemCard(
                    key: ValueKey('${shop.id}_${categoryItems[index].id}'),
                    item: categoryItems[index],
                    shop: shop,
                    categories: rawCategories,
                  ),
                  childCount: categoryItems.length,
                ),
              ),
            ),
          );
        }

        if (slivers.isEmpty) {
          return [
            SliverPadding(
              padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
              sliver: SliverGrid(
                gridDelegate: gridDelegate,
                delegate: SliverChildBuilderDelegate(
                  (context, index) => _ShopkeeperMenuItemCard(
                    key: ValueKey('${shop.id}_${filtered[index].id}'),
                    item: filtered[index],
                    shop: shop,
                    categories: rawCategories,
                  ),
                  childCount: filtered.length,
                ),
              ),
            ),
            SliverToBoxAdapter(
              child:
                  SizedBox(height: 80 + MediaQuery.of(context).padding.bottom),
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
}

/// 2-column Grid Menu Card matching User App _MenuItemCard exactly + Edit Button
class _ShopkeeperMenuItemCard extends ConsumerWidget {
  const _ShopkeeperMenuItemCard({
    required this.item,
    required this.shop,
    required this.categories,
    super.key,
  });

  final MenuItem item;
  final Shop shop;
  final List<Category> categories;

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

  String _getEffectiveImageUrl(MenuItem item) {
    if (item.imageUrl.isNotEmpty) return item.imageUrl;

    final nameLower = item.name.toLowerCase();
    if (nameLower.contains('momo') || nameLower.contains('dumpling')) {
      if (nameLower.contains('fried')) {
        return 'https://images.unsplash.com/photo-1541696432-82c6da8ce7bf?w=500&auto=format&fit=crop&q=80';
      }
      return 'https://images.unsplash.com/photo-1534422298391-e4f8c172dddb?w=500&auto=format&fit=crop&q=80';
    } else if (nameLower.contains('noodle') ||
        nameLower.contains('chow') ||
        nameLower.contains('maggi')) {
      return 'https://images.unsplash.com/photo-1612927601601-6638404737ce?w=500&auto=format&fit=crop&q=80';
    } else if (nameLower.contains('burger')) {
      return 'https://images.unsplash.com/photo-1568901346375-23c9450c58cd?w=500&auto=format&fit=crop&q=80';
    } else if (nameLower.contains('paneer') || nameLower.contains('curry')) {
      return 'https://images.unsplash.com/photo-1631452180519-c014fe946bc7?w=500&auto=format&fit=crop&q=80';
    } else if (nameLower.contains('roll') ||
        nameLower.contains('wrap') ||
        nameLower.contains('frankie')) {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final displayImageUrl = _getEffectiveImageUrl(item);
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 360;

    void showEditSheet() {
      EditMenuItemModal.show(
        context,
        item: item,
        categories: categories,
        shopId: shop.id,
      );
    }

    return Opacity(
      opacity: item.isAvailable ? 1.0 : 0.65,
      child: GestureDetector(
        onTap: showEditSheet,
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: item.isAvailable
                  ? Theme.of(context).dividerColor.withValues(alpha: 0.08)
                  : AppColors.error.withValues(alpha: 0.3),
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
              // 1. Food Image Container (aspectRatio 1.3 matching User App)
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
                                memCacheWidth: 400,
                                memCacheHeight: 300,
                                placeholder: (_, __) =>
                                    _buildImagePlaceholder(context),
                                errorWidget: (_, __, ___) =>
                                    _buildImagePlaceholder(context),
                              )
                            : _buildImagePlaceholder(context),
                      ),
                    ),

                    // Out of Stock or Special Badge
                    if (!item.isAvailable)
                      Positioned(
                        top: 6,
                        left: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.error,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'OUT OF STOCK',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      )
                    else if (item.isRecommended)
                      Positioned(
                        top: 6,
                        left: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'SPECIAL',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
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
                      // Item Title with Veg/Non-Veg icon (2 lines matching User App)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: item.isVeg
                                    ? _buildVegIcon()
                                    : _buildNonVegIcon(),
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

                          // Description with clean "... more" (Matching User App)
                          Builder(
                            builder: (context) {
                              final rawDetails = item.details.isNotEmpty
                                  ? item.details
                                  : '${item.name} prepared fresh with authentic spices';
                              final cleanDetails = rawDetails
                                  .replaceAll(RegExp(r'\.+$'), '')
                                  .trim();
                              return Text.rich(
                                TextSpan(
                                  style: TextStyle(
                                    color: isDark
                                        ? AppColors.darkTextSecondary
                                        : Colors.grey.shade600,
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

                      // Bottom Row: Price + Edit Button (Matching User App Add button size)
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

                          // Edit Button styled cleanly like User App Add button
                          InkWell(
                            onTap: showEditSheet,
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              width: isSmallScreen ? 58.0 : 64.0,
                              height: isSmallScreen ? 28.0 : 30.0,
                              decoration: BoxDecoration(
                                color: Theme.of(context).cardColor,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: AppColors.primary,
                                  width: 1.3,
                                ),
                              ),
                              child: const Center(
                                child: Text(
                                  'Edit',
                                  style: TextStyle(
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                  ),
                                ),
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
      ),
    );
  }
}

/// Category Navigation Header matching User App _CategoryNavWidget
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
    const primaryColor = AppColors.primary;

    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 360;
    final itemWidth =
        isSmallScreen ? 68.0 : (screenWidth < 400 ? 73.0 : 76.0);
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
                              color: isDark
                                  ? AppColors.darkSurfaceVariant
                                  : Colors.grey[200],
                              child: const Icon(
                                Icons.fastfood_rounded,
                                size: 22,
                                color: Colors.grey,
                              ),
                            ),
                            errorWidget: (context, url, error) => Container(
                              color: isDark
                                  ? AppColors.darkSurfaceVariant
                                  : Colors.grey[200],
                              child: const Icon(
                                Icons.fastfood_rounded,
                                size: 22,
                                color: Colors.grey,
                              ),
                            ),
                          ),
                        ),
                      ),

                      // Selected checkmark badge (Orange circle with white check icon)
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
                                color:
                                    Theme.of(context).scaffoldBackgroundColor,
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

                // Category Name Label (2-line wrap matching User App)
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

/// Filter chip for Veg/Non-Veg/All (Matching User App _FilterChip)
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
          color: isSelected
              ? chipColor.withValues(alpha: 0.15)
              : Colors.transparent,
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
                    : (isDark
                        ? AppColors.darkTextSecondary
                        : AppColors.textSecondary),
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
        ),
      ),
    );
  }
}

/// Painter for drawing the Non-Veg Red Triangle symbol
class _TrianglePainter extends CustomPainter {
  const _TrianglePainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final path = Path()
      ..moveTo(size.width / 2, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Delegate for pinning Category Navigation Header
class _StickyCategoryHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _StickyCategoryHeaderDelegate({
    required this.child,
    this.height = 114.0,
  });

  final Widget child;
  final double height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
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
