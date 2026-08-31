// BU Gate2Eat — Universal Menu Item Card
// Single Source of Truth for Menu Item presentation across Customer, Shopkeeper, and Admin panels.

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/providers.dart';
import '../../../models/category_model.dart';
import '../../../models/menu_item_model.dart';
import '../../../models/shop_model.dart';
import '../../../panel/shopkeeper_panel/widgets/edit_menu_item_modal.dart';
import '../shop_detail_screen.dart';

enum ItemCardPerspective {
  customer,
  shopkeeper,
  admin,
}

/// Universal Menu Item Card matching the approved Customer Item Card design.
/// Used everywhere items/menu cards are displayed.
class UniversalMenuItemCard extends ConsumerWidget {
  const UniversalMenuItemCard({
    required this.item,
    required this.shop,
    this.isShopOpen = true,
    this.perspective = ItemCardPerspective.customer,
    this.onTap,
    this.onAction,
    this.actionButtonText,
    this.showFavorite,
    this.categories,
    super.key,
  });

  final MenuItem item;
  final Shop shop;
  final bool isShopOpen;
  final ItemCardPerspective perspective;
  final VoidCallback? onTap;
  final VoidCallback? onAction;
  final String? actionButtonText;
  final bool? showFavorite;
  final List<Category>? categories;

  bool get _isCustomer => perspective == ItemCardPerspective.customer;

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
          width: 5.5,
          height: 5.5,
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
          width: 5.5,
          height: 5.5,
          decoration: const BoxDecoration(
            color: AppColors.nonVegRed,
            shape: BoxShape.circle,
          ),
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

  Widget _buildActionButton({
    required Key key,
    required BuildContext context,
    required VoidCallback onActionPressed,
    required String label,
    double width = 64,
    double height = 30,
  }) {
    const primaryColor = AppColors.primary;
    return InkWell(
      key: key,
      borderRadius: BorderRadius.circular(8),
      onTap: onActionPressed,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: primaryColor,
            width: 1.2,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: GoogleFonts.outfit(
              color: primaryColor,
              fontWeight: FontWeight.w700,
              fontSize: 13,
              letterSpacing: 0.15,
            ),
          ),
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
    } else if (nameLower.contains('shake') ||
        nameLower.contains('drink') ||
        nameLower.contains('tea') ||
        nameLower.contains('coffee')) {
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
    final isAvailable = _isCustomer ? (item.isAvailable && isShopOpen) : item.isAvailable;
    final displayImageUrl = _getEffectiveImageUrl(item);
    final shouldShowFavorite = showFavorite ?? _isCustomer;

    final favorites = ref.watch(favoritesProvider);
    final isFavorite = favorites.contains(FavoriteNotifier.buildFavoriteKey(shop.id, item.id));

    void handleCardTap() {
      if (onTap != null) {
        onTap!();
        return;
      }

      if (_isCustomer) {
        showItemDetailBottomSheet(
          context: context,
          item: item,
          shop: shop,
          isAvailable: isAvailable,
          displayImageUrl: displayImageUrl,
        );
      } else {
        EditMenuItemModal.show(
          context,
          item: item,
          categories: categories ?? const [],
          shopId: shop.id,
        );
      }
    }

    void handleActionPress() {
      if (onAction != null) {
        onAction!();
        return;
      }
      handleCardTap();
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 360;
    final buttonLabel = actionButtonText ?? (_isCustomer ? 'Add' : 'Edit');

    return Opacity(
      opacity: isAvailable ? 1.0 : (_isCustomer ? 0.55 : 0.65),
      child: GestureDetector(
        onTap: handleCardTap,
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Theme.of(context).dividerColor.withValues(alpha: isDark ? 0.12 : 0.06),
              width: 0.8,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.035),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.12 : 0.015),
                blurRadius: 3,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Food Image Container
              AspectRatio(
                aspectRatio: 1.25,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(16),
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

                    // Out of Stock Badge (Shopkeeper/Admin side when unavailable)
                    if (!_isCustomer && !item.isAvailable)
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
                      ),

                    // Favorite Heart Button (Top-Right overlay for Customer)
                    if (shouldShowFavorite)
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
                    isSmallScreen ? 9 : 11,
                    8,
                    isSmallScreen ? 9 : 11,
                    9,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Item Title with Veg/Non-Veg icon (Supports up to 2 lines)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 3.0),
                            child: item.isVeg ? _buildVegIcon() : _buildNonVegIcon(),
                          ),
                          const SizedBox(width: 5.5),
                          Expanded(
                            child: Text(
                              item.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.gideonRoman(
                                fontWeight: FontWeight.w900,
                                fontSize: isSmallScreen ? 14.8 : 15.8,
                                height: 1.16,
                                letterSpacing: 0.1,
                                color: isDark
                                    ? AppColors.darkTextPrimary
                                    : AppColors.textPrimary,
                                shadows: [
                                  Shadow(
                                    color: (isDark
                                            ? AppColors.darkTextPrimary
                                            : AppColors.textPrimary)
                                        .withValues(alpha: 0.65),
                                    offset: const Offset(0.35, 0.25),
                                    blurRadius: 0.3,
                                  ),
                                  Shadow(
                                    color: (isDark
                                            ? AppColors.darkTextPrimary
                                            : AppColors.textPrimary)
                                        .withValues(alpha: 0.65),
                                    offset: const Offset(-0.25, -0.15),
                                    blurRadius: 0.3,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),

                      // Bottom Row: Clean Price + Action Button
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Flexible(
                            child: Text(
                              item.formattedStartingPrice,
                              style: GoogleFonts.notoSansJp(
                                fontWeight: FontWeight.w800,
                                fontSize: isSmallScreen ? 14.5 : 15.5,
                                color: isDark
                                    ? AppColors.darkTextPrimary
                                    : AppColors.textPrimary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 4),

                          // Action Button (Add for Customer, Edit for Shopkeeper/Admin)
                          if (isAvailable || !_isCustomer)
                            _buildActionButton(
                              key: _isCustomer
                                  ? const ValueKey('add_btn')
                                  : const ValueKey('edit_btn'),
                              context: context,
                              onActionPressed: handleActionPress,
                              label: buttonLabel,
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
