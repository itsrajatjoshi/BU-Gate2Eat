// BU Gate2Eat — Shop Detail Bottom Sheet
// Customer-facing bottom sheet displaying complete shop details, timings, contacts, and description
// Matches the visual elegance and slide-up transition of Item Details Page.

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/providers.dart';
import '../../../models/menu_item_model.dart';
import '../../../models/shop_model.dart';
import '../../../services/whatsapp_service.dart';

/// Universal Gateway for displaying the Shop Details Bottom Sheet.
void showShopDetailBottomSheet({
  required BuildContext context,
  required Shop shop,
  List<MenuItem>? menuItems,
}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (ctx) => _ShopDetailBottomSheet(
      shop: shop,
      menuItems: menuItems,
    ),
  );
}

class _ShopDetailBottomSheet extends ConsumerWidget {
  const _ShopDetailBottomSheet({
    required this.shop,
    this.menuItems,
  });

  final Shop shop;
  final List<MenuItem>? menuItems;

  Future<void> _callShop(BuildContext context) async {
    final number = shop.contactNumber.isNotEmpty
        ? shop.contactNumber
        : shop.orderNumber;
    final clean = number.trim();

    if (clean.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Contact number for ${shop.name} is not available.'),
          backgroundColor: AppColors.yummbuRed,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final launched = await WhatsAppService.launchPhoneCall(clean);
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not open phone dialer for +91 $clean'),
          backgroundColor: AppColors.yummbuRed,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Widget _buildVegIcon() {
    return Container(
      width: 15,
      height: 15,
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.vegGreen, width: 1.4),
        borderRadius: BorderRadius.circular(3.5),
      ),
      child: Center(
        child: Container(
          width: 6.5,
          height: 6.5,
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
        border: Border.all(color: AppColors.yummbuRed, width: 1.4),
        borderRadius: BorderRadius.circular(3.5),
      ),
      child: Center(
        child: Container(
          width: 6.5,
          height: 6.5,
          decoration: const BoxDecoration(
            color: AppColors.yummbuRed,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Row(
      children: [
        Container(
          width: 3.5,
          height: 15,
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 7),
        Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 15,
            color: AppColors.textPrimary,
            letterSpacing: -0.2,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOpen = shop.isOpen;
    final mediaQuery = MediaQuery.of(context);
    final maxHeight = mediaQuery.size.height * 0.88;
    final screenWidth = mediaQuery.size.width;
    final isSmallScreen = screenWidth < 360;

    final effectiveMenuItems =
        menuItems ?? ref.watch(shopMenuItemsProvider(shop.id)).value ?? [];

    final bool hasVeg = effectiveMenuItems.any((item) => item.isVeg);
    final bool hasNonVeg = effectiveMenuItems.any((item) => !item.isVeg);

    // If menu has items, show exactly what exists; if empty, default to Veg
    final bool showVeg = hasVeg || (!hasVeg && !hasNonVeg);
    final bool showNonVeg = hasNonVeg;

    return Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 560,
          maxHeight: maxHeight,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
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
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),

              // 2. Scrollable Content Body
              Flexible(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(
                    isSmallScreen ? 14 : 18,
                    8,
                    isSmallScreen ? 14 : 18,
                    24 + mediaQuery.padding.bottom,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ─── Banner Image with Top Overlay Buttons ───────
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Container(
                            height: isSmallScreen ? 180 : 210,
                            width: double.infinity,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(20),
                              color: AppColors.surfaceVariant,
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(20),
                              child: shop.bannerUrl.isNotEmpty
                                  ? CachedNetworkImage(
                                      imageUrl: shop.bannerUrl,
                                      fit: BoxFit.cover,
                                      placeholder: (_, __) => Container(
                                        color: AppColors.surfaceVariant,
                                        child: const Center(
                                          child: Icon(
                                            Icons.storefront_rounded,
                                            size: 48,
                                            color: Colors.grey,
                                          ),
                                        ),
                                      ),
                                      errorWidget: (_, __, ___) => Container(
                                        color: AppColors.surfaceVariant,
                                        child: const Center(
                                          child: Icon(
                                            Icons.storefront_rounded,
                                            size: 48,
                                            color: Colors.grey,
                                          ),
                                        ),
                                      ),
                                    )
                                  : const Center(
                                      child: Icon(
                                        Icons.storefront_rounded,
                                        size: 48,
                                        color: Colors.grey,
                                      ),
                                    ),
                            ),
                          ),

                          // Top-Left: Close / Back Button
                          Positioned(
                            top: 12,
                            left: 12,
                            child: GestureDetector(
                              onTap: () => Navigator.of(context).pop(),
                              child: Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.92),
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.15),
                                      blurRadius: 6,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: const Center(
                                  child: Icon(
                                    Icons.arrow_back_rounded,
                                    size: 18,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                              ),
                            ),
                          ),

                          // Top-Right: Call Shop Button
                          Positioned(
                            top: 12,
                            right: 12,
                            child: GestureDetector(
                              onTap: () => _callShop(context),
                              child: Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.92),
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.15),
                                      blurRadius: 6,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: const Center(
                                  child: Icon(
                                    Icons.call_rounded,
                                    size: 18,
                                    color: AppColors.primary,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),

                      // ─── Shop Name ──────────────────────────────────
                      Text(
                        shop.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 22,
                          color: AppColors.textPrimary,
                          letterSpacing: -0.4,
                        ),
                      ),
                      const SizedBox(height: 8),

                      // ─── Food Type Indicators (Veg • Non-Veg ONLY) ──
                      if (showVeg || showNonVeg) ...[
                        Row(
                          children: [
                            if (showVeg)
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _buildVegIcon(),
                                  const SizedBox(width: 5),
                                  const Text(
                                    'Veg',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12.5,
                                      color: AppColors.vegGreen,
                                    ),
                                  ),
                                ],
                              ),
                            if (showVeg && showNonVeg) ...[
                              const SizedBox(width: 8),
                              const Text(
                                '|',
                                style: TextStyle(
                                  color: AppColors.divider,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],
                            if (showNonVeg)
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _buildNonVegIcon(),
                                  const SizedBox(width: 5),
                                  const Text(
                                    'Non-Veg',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12.5,
                                      color: AppColors.yummbuRed,
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ],

                      const SizedBox(height: 18),
                      const Divider(height: 1, thickness: 0.6, color: AppColors.divider),
                      const SizedBox(height: 16),

                      // ─── Shop Information Section ───────────────────
                      _buildSectionHeader('Shop Information'),
                      const SizedBox(height: 12),

                      // Operating Status & Timings
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3.5,
                            ),
                            decoration: BoxDecoration(
                              color: isOpen
                                  ? AppColors.success.withValues(alpha: 0.12)
                                  : AppColors.yummbuRed.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              isOpen ? 'Open Now' : 'Closed',
                              style: TextStyle(
                                color: isOpen ? AppColors.success : AppColors.yummbuRed,
                                fontWeight: FontWeight.w700,
                                fontSize: 11.5,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          const Icon(
                            Icons.access_time_rounded,
                            size: 14,
                            color: AppColors.textSecondary,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            '${Shop.format12hr(shop.openTime)} – ${Shop.format12hr(shop.closeTime)}',
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      // Location / Area
                      Row(
                        children: [
                          const Icon(
                            Icons.location_on_outlined,
                            size: 16,
                            color: AppColors.textSecondary,
                          ),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Text(
                              shop.address.isNotEmpty
                                  ? shop.address
                                  : 'Address not specified',
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),

                      // Phone Contact Numbers
                      if (shop.contactNumber.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            const Icon(
                              Icons.phone_outlined,
                              size: 16,
                              color: AppColors.textSecondary,
                            ),
                            const SizedBox(width: 7),
                            Text(
                              shop.contactNumber,
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            if (shop.orderNumber.isNotEmpty &&
                                shop.orderNumber != shop.contactNumber) ...[
                              Text(
                                ', ${shop.orderNumber}',
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],

                      if (shop.orderNumber.isNotEmpty &&
                          shop.orderNumber != shop.contactNumber) ...[
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            const Icon(
                              Icons.chat_outlined,
                              size: 16,
                              color: Color(0xFF25D366),
                            ),
                            const SizedBox(width: 7),
                            Text(
                              '${shop.orderNumber} (WhatsApp)',
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ],

                      const SizedBox(height: 18),
                      const Divider(height: 1, thickness: 0.6, color: AppColors.divider),
                      const SizedBox(height: 16),

                      // ─── Actual Description Section ─────────────────
                      _buildSectionHeader('Description'),
                      const SizedBox(height: 8),

                      Text(
                        shop.description.isNotEmpty
                            ? shop.description
                            : 'At ${shop.name}, we serve fresh and delicious food prepared with authentic ingredients and quality spices. Great taste and satisfying meals for every craving!',
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 13.5,
                          height: 1.45,
                          fontWeight: FontWeight.w400,
                        ),
                      ),

                      const SizedBox(height: 18),
                      const Divider(height: 1, thickness: 0.6, color: AppColors.divider),
                      const SizedBox(height: 16),

                      // ─── Payment Section ────────────────────────────
                      _buildSectionHeader('Payment'),
                      const SizedBox(height: 8),

                      const Text(
                        'Cash / UPI / Online Payment available.',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
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

/// Custom painter for the non-veg red triangle icon.
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
  bool shouldRepaint(covariant _TrianglePainter oldDelegate) =>
      oldDelegate.color != color;
}
