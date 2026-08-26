// BU Gate2Eat — Admin Panel
// Selected Shop In-App Orders List Screen (Phase D)
// Displays strictly isolated in-app Firestore orders for the selected shop.
// WhatsApp orders are counter-only and never appear in this list.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_constants.dart';
import '../../core/providers.dart';
import '../../models/order_model.dart';
import '../../services/order_service.dart';
import 'widgets/admin_order_details_modal.dart';

class AdminShopOrdersScreen extends ConsumerStatefulWidget {
  const AdminShopOrdersScreen({
    required this.shopId,
    super.key,
  });

  final String shopId;

  @override
  ConsumerState<AdminShopOrdersScreen> createState() => _AdminShopOrdersScreenState();
}

class _AdminShopOrdersScreenState extends ConsumerState<AdminShopOrdersScreen> {
  String _selectedFilter = 'All';

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final shopsAsync = ref.watch(shopsProvider);
    final ordersAsync = ref.watch(shopOrdersStreamProvider(widget.shopId));

    // Resolve shop name
    final shop = shopsAsync.valueOrNull
        ?.where((s) => s.id == widget.shopId)
        .firstOrNull;
    final shopName = shop?.name ?? 'Shop';

    return Scaffold(
      appBar: AppBar(
        title: Text(
          '$shopName App Orders',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
        elevation: 0,
      ),
      body: ordersAsync.when(
        data: (allOrders) {
          // Strict rule: Admin monitors ONLY processed/terminal business orders.
          // Active live orders (placed, accepted) are handled strictly in Customer & Shopkeeper operational panels.
          final terminalOrders = allOrders.where((o) {
            final s = o.status.trim().toLowerCase();
            return s != OrderStatusRules.statusPlaced &&
                s != OrderStatusRules.statusAccepted;
          }).toList();

          // Deterministic sorting: newest createdAt first, with orderId as tie-breaker
          terminalOrders.sort((a, b) {
            final cmp = b.createdAt.compareTo(a.createdAt);
            if (cmp != 0) return cmp;
            return b.orderId.compareTo(a.orderId);
          });

          if (terminalOrders.isEmpty) {
            return _buildEmptyState(isDark);
          }

          // Compute filter counts with safe case-insensitive comparison
          final deliveredOrders = terminalOrders
              .where((o) => o.status.trim().toLowerCase() == OrderStatusRules.statusDelivered)
              .toList();
          final rejectedOrders = terminalOrders
              .where((o) => o.status.trim().toLowerCase() == OrderStatusRules.statusRejected)
              .toList();
          final expiredOrders = terminalOrders
              .where((o) => o.status.trim().toLowerCase() == OrderStatusRules.statusDeliveryExpired)
              .toList();

          // Apply selected filter
          final filteredOrders = switch (_selectedFilter) {
            'Delivered' => deliveredOrders,
            'Rejected' => rejectedOrders,
            'Expired' => expiredOrders,
            _ => terminalOrders,
          };

          return Column(
            children: [
              // ── Summary & Filter Header ──
              _buildHeaderAndFilters(
                totalCount: terminalOrders.length,
                deliveredCount: deliveredOrders.length,
                rejectedCount: rejectedOrders.length,
                expiredCount: expiredOrders.length,
                isDark: isDark,
              ),

              // ── Orders List ──
              Expanded(
                child: filteredOrders.isEmpty
                    ? Center(
                        child: Text(
                          'No $_selectedFilter orders found',
                          style: TextStyle(
                            fontSize: 14,
                            color: isDark
                                ? AppColors.darkTextSecondary
                                : AppColors.textSecondary,
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                        physics: const BouncingScrollPhysics(),
                        itemCount: filteredOrders.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final order = filteredOrders[index];
                          return _AdminOrderCard(
                            order: order,
                            isDark: isDark,
                            onTap: () => AdminOrderDetailsModal.show(context, order),
                          );
                        },
                      ),
              ),
            ],
          );
        },
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
        error: (err, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.cloud_off_rounded,
                  size: 48,
                  color: AppColors.error,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Unable to load app orders',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Text(
                  err.toString(),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark
                        ? AppColors.darkTextSecondary
                        : AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () => ref.invalidate(shopOrdersStreamProvider(widget.shopId)),
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Retry'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.receipt_long_outlined,
                size: 36,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'No app orders yet',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Orders from this shop will appear here.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: isDark
                    ? AppColors.darkTextSecondary
                    : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderAndFilters({
    required int totalCount,
    required int deliveredCount,
    required int rejectedCount,
    required int expiredCount,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        border: Border(
          bottom: BorderSide(
            color: isDark ? AppColors.darkDivider : AppColors.divider,
            width: 1,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Total App Orders badge
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Completed Orders: $totalCount',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                'Newest First',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: isDark
                      ? AppColors.darkTextSecondary
                      : AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Filter Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              children: [
                _buildFilterChip('All', totalCount, isDark),
                const SizedBox(width: 8),
                _buildFilterChip('Delivered', deliveredCount, isDark),
                const SizedBox(width: 8),
                _buildFilterChip('Rejected', rejectedCount, isDark),
                const SizedBox(width: 8),
                _buildFilterChip('Expired', expiredCount, isDark),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, int count, bool isDark) {
    final isSelected = _selectedFilter == label;
    return InkWell(
      onTap: () => setState(() => _selectedFilter = label),
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary
              : (isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? AppColors.primary
                : (isDark ? AppColors.darkDivider : AppColors.divider),
          ),
        ),
        child: Text(
          '$label ($count)',
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
            color: isSelected
                ? Colors.white
                : (isDark ? AppColors.darkTextPrimary : AppColors.textPrimary),
          ),
        ),
      ),
    );
  }
}

class _AdminOrderCard extends StatelessWidget {
  const _AdminOrderCard({
    required this.order,
    required this.isDark,
    required this.onTap,
  });

  final AppOrder order;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? AppColors.darkDivider : AppColors.divider,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.20 : 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Row: Order ID & Status Badge
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '#${order.orderId}',
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.3,
                      ),
                    ),
                    _buildCardBadge(order.status),
                  ],
                ),
                const SizedBox(height: 8),

                // Customer Name
                Row(
                  children: [
                    const Icon(
                      Icons.person_outline_rounded,
                      size: 15,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        order.customerName.isNotEmpty ? order.customerName : 'Guest Customer',
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),

                // Item count & Total Price
                Row(
                  children: [
                    Text(
                      '${order.items.length} ${order.items.length == 1 ? 'item' : 'items'} • ₹${order.totalAmount.toStringAsFixed(0)}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Divider(height: 1, thickness: 0.6),
                const SizedBox(height: 8),

                // Date & View Details Link
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _formatDate(order.createdAt),
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
                      ),
                    ),
                    Row(
                      children: [
                        Text(
                          'View Details',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(width: 3),
                        const Icon(
                          Icons.arrow_forward_ios_rounded,
                          size: 11,
                          color: AppColors.primary,
                        ),
                      ],
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

  Widget _buildCardBadge(String status) {
    Color bg;
    Color fg;
    String label = status.toUpperCase().replaceAll('_', ' ');

    switch (status.toLowerCase()) {
      case 'placed':
        bg = Colors.blue.withValues(alpha: 0.12);
        fg = Colors.blue.shade700;
        break;
      case 'accepted':
        bg = Colors.amber.withValues(alpha: 0.12);
        fg = Colors.amber.shade900;
        break;
      case 'delivered':
        bg = AppColors.success.withValues(alpha: 0.12);
        fg = AppColors.success;
        label = 'DELIVERED';
        break;
      case 'rejected':
        bg = AppColors.error.withValues(alpha: 0.12);
        fg = AppColors.error;
        break;
      case 'delivery_expired':
        bg = Colors.deepPurple.withValues(alpha: 0.12);
        fg = Colors.deepPurple;
        label = 'EXPIRED';
        break;
      default:
        bg = Colors.grey.withValues(alpha: 0.12);
        fg = Colors.grey.shade700;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          color: fg,
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    final minute = dt.minute.toString().padLeft(2, '0');
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final month = months[dt.month - 1];
    return '${dt.day} $month • $hour:$minute $period';
  }
}
