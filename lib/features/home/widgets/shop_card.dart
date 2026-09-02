// BU Gate2Eat — Shop Card Widget
// Combines YummBU status & contact, Zomato typography & timing, EatClub circular logo,
// and auto-sliding + swipeable category food images slideshow.

import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/providers.dart';
import '../../../models/shop_model.dart';

class ShopCard extends ConsumerStatefulWidget {
  const ShopCard({
    required this.shop,
    required this.onTap,
    this.slideshowImages,
    this.autoSlideInterval = const Duration(seconds: 4),
    super.key,
  });

  final Shop shop;
  final VoidCallback onTap;
  final List<String>? slideshowImages;
  final Duration autoSlideInterval;

  @override
  ConsumerState<ShopCard> createState() => _ShopCardState();
}

class _ShopCardState extends ConsumerState<ShopCard> {
  late final PageController _pageController;
  Timer? _autoSlideTimer;
  int _currentPage = 0;
  int _lastResolvedImageCount = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _autoSlideTimer?.cancel();
    _autoSlideTimer = null;
    _pageController.dispose();
    super.dispose();
  }

  void _syncAutoSlide(int imageCount) {
    if (imageCount == _lastResolvedImageCount &&
        _autoSlideTimer != null &&
        _autoSlideTimer!.isActive) {
      return;
    }
    _lastResolvedImageCount = imageCount;
    _startAutoSlide(imageCount);
  }

  void _startAutoSlide(int imageCount) {
    _autoSlideTimer?.cancel();
    _autoSlideTimer = null;
    if (imageCount <= 1 || !mounted) return;

    _autoSlideTimer = Timer.periodic(widget.autoSlideInterval, (timer) {
      if (!mounted || !_pageController.hasClients) return;
      final nextPage = (_currentPage + 1) % imageCount;
      _pageController.animateToPage(
        nextPage,
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOut,
      );
    });
  }

  /// Converts time string to 12hr AM/PM format.
  String _formatTime12hr(String time) => Shop.format12hr(time);

  @override
  Widget build(BuildContext context) {
    final shop = widget.shop;
    final isOpen = shop.isOpen;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 380;
    final horizontalPadding = isSmallScreen ? 12.0 : 14.0;
    final circleSize = isSmallScreen ? 76.0 : 84.0;
    final circleRight = isSmallScreen ? 14.0 : 18.0;
    final textRightPadding = circleRight + circleSize + 8.0;

    // Resolve slideshow images from explicit override or Riverpod provider
    final List<String> images = widget.slideshowImages ??
        ref.watch(shopSlideshowImagesProvider(shop));

    // Post-frame check to manage auto-sliding timer safely
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _syncAutoSlide(images.length);
      }
    });

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.06),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final cardWidth = constraints.maxWidth;
            // Premium food card aspect ratio matching modern restaurant listings (1.85:1)
            final bannerHeight = cardWidth / 1.85;
            final circleTop = bannerHeight - (circleSize / 2);

            return Stack(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 1. Banner Image Area (1.85:1 ratio) with Slideshow & Status Badge
                    Stack(
                      children: [
                        AspectRatio(
                          aspectRatio: 1.85 / 1,
                          child: _buildBannerSlideshow(images, isDark),
                        ),

                        // Glassmorphic Status Badge (Top-Left)
                        Positioned(
                          top: 10,
                          left: 10,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: isOpen
                                  ? Colors.black.withValues(alpha: 0.65)
                                  : AppColors.nonVegRed.withValues(alpha: 0.88),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.2),
                                width: 0.8,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.2),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 6,
                                      height: 6,
                                      decoration: BoxDecoration(
                                        color: isOpen
                                            ? AppColors.vegGreen
                                            : Colors.white,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      isOpen ? 'OPEN' : 'CLOSED',
                                      style: GoogleFonts.outfit(
                                        color: Colors.white,
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0.8,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  isOpen
                                      ? 'Till ${_formatTime12hr(shop.closeTime)}'
                                      : 'Opens ${_formatTime12hr(shop.openTime)}',
                                  style: GoogleFonts.inter(
                                    color: Colors.white.withValues(alpha: 0.92),
                                    fontSize: 10,
                                    fontWeight: FontWeight.w500,
                                    letterSpacing: -0.1,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),

                    // 2. Main Information Section (Zomato-aligned visual hierarchy)
                    Padding(
                      padding: EdgeInsets.only(
                        left: horizontalPadding,
                        right: textRightPadding,
                        top: 10,
                        bottom: 12,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Shop Name (Bold, prominent header matching Zomato title density)
                          Text(
                            shop.name,
                            style: GoogleFonts.outfit(
                              fontWeight: FontWeight.w800,
                              color: isDark
                                  ? AppColors.darkTextPrimary
                                  : const Color(0xFF1C1C1C),
                              fontSize: isSmallScreen ? 17.5 : 19.5,
                              letterSpacing: -0.4,
                              height: 1.2,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),

                          // Clock Timings Badge (Icon + Text) underneath Shop Name
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.schedule_rounded,
                                size: 13.5,
                                color: isDark
                                    ? AppColors.darkTextSecondary
                                    : const Color(0xFF686B78),
                              ),
                              const SizedBox(width: 4.5),
                              Flexible(
                                child: Text(
                                  '${_formatTime12hr(shop.openTime)} – ${_formatTime12hr(shop.closeTime)}',
                                  style: GoogleFonts.inter(
                                    color: isDark
                                        ? AppColors.darkTextSecondary
                                        : const Color(0xFF686B78),
                                    fontWeight: FontWeight.w500,
                                    fontSize: isSmallScreen ? 11.5 : 12.5,
                                    letterSpacing: -0.1,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),

                          // Contact Chip Pill (Compact tertiary supporting element)
                          if (shop.contactNumber.isNotEmpty) ...[
                            const SizedBox(height: 7),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8.5,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? AppColors.darkSurfaceVariant
                                    : const Color(0xFFF1F3F6),
                                borderRadius: BorderRadius.circular(7),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.phone_outlined,
                                    size: 11.5,
                                    color: isDark
                                        ? AppColors.darkTextSecondary
                                        : const Color(0xFF52575C),
                                  ),
                                  const SizedBox(width: 4.5),
                                  Text(
                                    shop.contactNumber,
                                    style: GoogleFonts.inter(
                                      color: isDark
                                          ? AppColors.darkTextSecondary
                                          : const Color(0xFF52575C),
                                      fontSize: 11.0,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 0.2,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),

                // 3. EatClub-style Prominent Circular Shop Logo (50-50 Boundary Overlap — 🔒 FROZEN)
                Positioned(
                  top: circleTop,
                  right: circleRight,
                  child: _buildCircularShopLogo(
                    size: circleSize,
                    isDark: isDark,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Builds the main banner image area supporting multi-image auto & manual swipe slideshow.
  Widget _buildBannerSlideshow(List<String> images, bool isDark) {
    if (images.isEmpty) {
      return _buildPlaceholder(isDark);
    }

    if (images.length == 1) {
      return CachedNetworkImage(
        imageUrl: images.first,
        fit: BoxFit.cover,
        memCacheWidth: 800,
        placeholder: (context, url) => _buildPlaceholder(isDark),
        errorWidget: (context, url, error) => _buildPlaceholder(isDark),
      );
    }

    return Stack(
      children: [
        PageView.builder(
          key: const ValueKey('shop_card_slideshow_pageview'),
          controller: _pageController,
          itemCount: images.length,
          onPageChanged: (index) {
            _currentPage = index;
            _startAutoSlide(images.length);
            setState(() {});
          },
          itemBuilder: (context, index) {
            return CachedNetworkImage(
              imageUrl: images[index],
              fit: BoxFit.cover,
              memCacheWidth: 800,
              placeholder: (context, url) => _buildPlaceholder(isDark),
              errorWidget: (context, url, error) => _buildPlaceholder(isDark),
            );
          },
        ),

        // Subtle Page Indicator Dots (Bottom-Center of banner)
        Positioned(
          bottom: 7,
          left: 0,
          right: 0,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(images.length, (index) {
              final isSelected = index == _currentPage;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                margin: const EdgeInsets.symmetric(horizontal: 2.5),
                width: isSelected ? 14 : 5,
                height: 4.5,
                decoration: BoxDecoration(
                  color: isSelected
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(3),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.35),
                      blurRadius: 3,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
              );
            }),
          ),
        ),
      ],
    );
  }

  /// Builds the EatClub-style circular shop image overlapping the boundary (🔒 FROZEN).
  Widget _buildCircularShopLogo({
    required double size,
    required bool isDark,
  }) {
    return Container(
      key: const ValueKey('shop_card_circular_logo'),
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isDark ? AppColors.darkSurfaceVariant : Colors.white,
        border: Border.all(
          color: isDark ? AppColors.darkSurface : Colors.white,
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.12),
            blurRadius: 10,
            spreadRadius: 0.5,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.06),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: ClipOval(
        child: widget.shop.shopLogoImageUrl.trim().isNotEmpty
            ? CachedNetworkImage(
                imageUrl: widget.shop.shopLogoImageUrl.trim(),
                fit: BoxFit.cover,
                memCacheWidth: 160,
                memCacheHeight: 160,
                placeholder: (context, url) =>
                    _buildLogoPlaceholder(isDark, size),
                errorWidget: (context, url, error) =>
                    _buildLogoPlaceholder(isDark, size),
              )
            : _buildLogoPlaceholder(isDark, size),
      ),
    );
  }

  Widget _buildLogoPlaceholder(bool isDark, double size) {
    return Container(
      color: isDark ? AppColors.darkSurfaceVariant : const Color(0xFFF5F5F5),
      child: Center(
        child: Icon(
          Icons.storefront_rounded,
          size: size * 0.42,
          color: isDark ? AppColors.darkTextSecondary : AppColors.textHint,
        ),
      ),
    );
  }

  Widget _buildPlaceholder(bool isDark) {
    return Container(
      color: isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant,
      child: Center(
        child: Icon(
          Icons.storefront_rounded,
          size: 36,
          color: isDark ? AppColors.darkTextSecondary : AppColors.textHint,
        ),
      ),
    );
  }
}
