// BU Gate2Eat — Features / Orders
// Universal Order Card (Single source of truth for Customer, Shopkeeper, and Admin order lists)
// Ultra-compact, information-dense, premium design with high scannability for 1000+ orders.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/utils/order_timer_helper.dart';
import '../../../models/order_model.dart';

/// Defines which perspective is viewing the order card.
enum OrderCardPerspective {
  /// Customer view: Displays the Shop Name & shop icon as primary identity.
  customer,

  /// Shopkeeper view: Displays the Customer Name & user icon as primary identity.
  shopkeeper,

  /// Admin view: Displays Shop Name (or specified identity) with shop icon.
  admin,
}

/// Status style metadata for rendering consistent badges across all panels.
class _StatusBadgeStyle {
  const _StatusBadgeStyle({
    required this.label,
    required this.color,
    required this.icon,
  });

  final String label;
  final Color color;
  final IconData icon;
}

/// The Universal Order Card component used everywhere across the YummBU app.
class UniversalOrderCard extends StatelessWidget {
  const UniversalOrderCard({
    required this.order,
    this.onTap,
    this.perspective = OrderCardPerspective.customer,
    this.identityTitle,
    this.showCountdown = true,
    this.customNow,
    super.key,
  });

  final AppOrder order;
  final VoidCallback? onTap;
  final OrderCardPerspective perspective;

  /// Optional override for the identity title (e.g. custom shop/customer string).
  final String? identityTitle;

  /// Whether to display live countdown string in active states (placed/accepted).
  final bool showCountdown;

  /// Optional time override for deterministic testing / countdowns.
  final DateTime? customNow;

  _StatusBadgeStyle _resolveStatusStyle(String rawStatus) {
    final status = rawStatus.trim().toLowerCase();
    switch (status) {
      case 'placed':
        return const _StatusBadgeStyle(
          label: 'PLACED',
          color: Color(0xFFE58500),
          icon: Icons.schedule_rounded,
        );
      case 'accepted':
        return const _StatusBadgeStyle(
          label: 'ACCEPTED',
          color: AppColors.success,
          icon: Icons.delivery_dining_rounded,
        );
      case 'delivered':
        return const _StatusBadgeStyle(
          label: 'DELIVERED',
          color: AppColors.success,
          icon: Icons.check_circle_outline_rounded,
        );
      case 'rejected':
        return const _StatusBadgeStyle(
          label: 'REJECTED',
          color: AppColors.error,
          icon: Icons.cancel_outlined,
        );
      case 'cancelled':
        return const _StatusBadgeStyle(
          label: 'CANCELLED',
          color: AppColors.error,
          icon: Icons.block_rounded,
        );
      case 'delivery_expired':
      case 'expired':
        return const _StatusBadgeStyle(
          label: 'EXPIRED',
          color: AppColors.error,
          icon: Icons.timer_off_outlined,
        );
      default:
        return _StatusBadgeStyle(
          label: rawStatus.toUpperCase(),
          color: AppColors.textSecondary,
          icon: Icons.info_outline_rounded,
        );
    }
  }

  String _resolveIdentityTitle() {
    if (identityTitle != null && identityTitle!.trim().isNotEmpty) {
      return identityTitle!.trim();
    }
    switch (perspective) {
      case OrderCardPerspective.customer:
        return order.shopName.trim().isNotEmpty
            ? order.shopName.trim()
            : 'Shop Order';
      case OrderCardPerspective.shopkeeper:
        return order.customerName.trim().isNotEmpty
            ? order.customerName.trim()
            : 'Customer';
      case OrderCardPerspective.admin:
        return order.shopName.trim().isNotEmpty
            ? order.shopName.trim()
            : (order.customerName.trim().isNotEmpty
                ? order.customerName.trim()
                : 'Order');
    }
  }

  IconData _resolveIdentityIcon() {
    switch (perspective) {
      case OrderCardPerspective.customer:
      case OrderCardPerspective.admin:
        return Icons.storefront_rounded;
      case OrderCardPerspective.shopkeeper:
        return Icons.person_rounded;
    }
  }

  static String _formatRelativeTimestamp(DateTime dateTime, DateTime now) {
    final local = dateTime.toLocal();
    final current = now.toLocal();
    final diff = current.difference(local);

    if (diff.isNegative) {
      return DateFormat('h:mm a').format(local);
    }
    if (diff.inMinutes < 1) {
      return 'Just now';
    }
    if (diff.inMinutes < 60) {
      final mins = diff.inMinutes;
      return mins == 1 ? '1 min ago' : '$mins mins ago';
    }
    if (local.year == current.year &&
        local.month == current.month &&
        local.day == current.day) {
      return DateFormat('h:mm a').format(local);
    }
    final yesterday = current.subtract(const Duration(days: 1));
    if (local.year == yesterday.year &&
        local.month == yesterday.month &&
        local.day == yesterday.day) {
      return 'Yesterday, ${DateFormat('h:mm a').format(local)}';
    }
    return DateFormat('d MMM, h:mm a').format(local);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final now = customNow ?? DateTime.now();

    final statusStyle = _resolveStatusStyle(order.status);
    final isPlaced = order.isPlaced;
    final isAccepted = order.isAccepted;

    // Resolve countdown string for active orders if enabled
    String countdownBadgeText = '';
    if (showCountdown) {
      if (isPlaced) {
        final rem = OrderTimerHelper.getRemainingAcceptDuration(order, now);
        countdownBadgeText = OrderTimerHelper.formatCountdown(rem);
      } else if (isAccepted) {
        final rem = OrderTimerHelper.getRemainingDeliveryDuration(order, now);
        countdownBadgeText = OrderTimerHelper.formatCountdown(rem);
      }
    }

    final identity = _resolveIdentityTitle();
    final identityIcon = _resolveIdentityIcon();
    final totalCount = order.totalItemCount;

    final hasRejectionReason = (order.isRejected || order.isCancelled) &&
        order.rejectionReason.trim().isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark
              ? AppColors.darkDivider.withValues(alpha: 0.6)
              : AppColors.divider.withValues(alpha: 0.7),
          width: 0.8,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.18 : 0.03),
            blurRadius: 6,
            offset: const Offset(0, 1.5),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── 1. Top Row: Identity & Universal Status Badge ──
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Identity (Shop / Customer)
                    Expanded(
                      child: Row(
                        children: [
                          Container(
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(
                                alpha: isDark ? 0.18 : 0.08,
                              ),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Center(
                              child: Icon(
                                identityIcon,
                                size: 13.5,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Text(
                              identity,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: isDark
                                    ? AppColors.darkTextPrimary
                                    : AppColors.textPrimary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Status Badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7.5,
                        vertical: 2.5,
                      ),
                      decoration: BoxDecoration(
                        color: statusStyle.color.withValues(
                          alpha: isDark ? 0.16 : 0.09,
                        ),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: statusStyle.color.withValues(
                            alpha: isDark ? 0.38 : 0.28,
                          ),
                          width: 0.8,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            statusStyle.icon,
                            size: 11,
                            color: statusStyle.color,
                          ),
                          const SizedBox(width: 3.5),
                          Text(
                            statusStyle.label,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: statusStyle.color,
                              letterSpacing: 0.3,
                            ),
                          ),
                          if (countdownBadgeText.isNotEmpty) ...[
                            const SizedBox(width: 3),
                            Text(
                              '($countdownBadgeText)',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: statusStyle.color,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 5),

                // ── 2. Second Row: Monospace Order ID ──
                Text(
                  'Order #${order.orderId}',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'monospace',
                    color: isDark
                        ? AppColors.darkTextSecondary
                        : AppColors.textSecondary,
                  ),
                ),

                // ── 3 (Conditional): Single-Line Rejection / Cancellation Reason ──
                if (hasRejectionReason) ...[
                  const SizedBox(height: 3.5),
                  Text(
                    'Reason: ${order.rejectionReason.trim()}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: AppColors.error,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],

                const SizedBox(height: 6),

                // ── 4. Bottom Row: Item Summary + Timestamp ──
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Item count & Total Price
                    Text(
                      '$totalCount ${totalCount == 1 ? 'item' : 'items'} • ${order.formattedTotal}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: isDark
                            ? AppColors.darkTextPrimary
                            : AppColors.textPrimary,
                      ),
                    ),

                    // Timestamp / Relative time
                    Text(
                      _formatRelativeTimestamp(order.createdAt, now),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: isDark
                            ? AppColors.darkTextSecondary
                            : AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
