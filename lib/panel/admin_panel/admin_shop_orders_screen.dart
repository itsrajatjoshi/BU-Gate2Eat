// BU Gate2Eat — Admin Panel
// Selected Shop In-App Orders List Screen (Phase D)
// Displays strictly isolated in-app Firestore orders for the selected shop.
// WhatsApp orders are counter-only and never appear in this list.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_constants.dart';
import '../../core/providers.dart';
import '../../features/orders/widgets/universal_order_card.dart';
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
  final _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedFilter = 'All';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _matchesOrderSearch(AppOrder order, String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;

    final nameMatches = order.customerName.toLowerCase().contains(q);
    final phoneMatches = order.customerPhone
        .replaceAll(RegExp(r'\s+'), '')
        .contains(q.replaceAll(RegExp(r'\s+'), ''));
    final cleanQ = q.replaceAll('#', '').trim();
    final idMatches = order.orderId.toLowerCase().replaceAll('#', '').contains(cleanQ) ||
        order.orderId.toLowerCase().contains(q);

    return nameMatches || phoneMatches || idMatches;
  }

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

          // Apply selected filter + search query with AND logic
          final baseFiltered = switch (_selectedFilter) {
            'Delivered' => deliveredOrders,
            'Rejected' => rejectedOrders,
            'Expired' => expiredOrders,
            _ => terminalOrders,
          };

          final filteredOrders = baseFiltered
              .where((o) => _matchesOrderSearch(o, _searchQuery))
              .toList();

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
                          return UniversalOrderCard(
                            order: order,
                            perspective: OrderCardPerspective.shopkeeper,
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

          // ── Search Field (Customer Name, Phone, Order ID) ──
          Container(
            height: 40,
            decoration: BoxDecoration(
              color: isDark
                  ? AppColors.darkSurfaceVariant
                  : AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(10),
            ),
            child: TextField(
              controller: _searchController,
              textAlignVertical: TextAlignVertical.center,
              style: TextStyle(
                fontSize: 13,
                color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
              ),
              decoration: InputDecoration(
                hintText: 'Search customer, phone, order ID...',
                hintStyle: TextStyle(
                  fontSize: 13,
                  color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
                ),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                prefixIcon: Icon(
                  Icons.search_rounded,
                  size: 19,
                  color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
                ),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 16),
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

