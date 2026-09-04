// BU Gate2Eat — Shopkeeper Panel
// Orders Screen (Phase 2 — Part 2.2: Shopkeeper Order Details Bottom Sheet)
// Connected to local dummy order state with strict shopId filtering & card tap details

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/providers.dart';
import '../../../core/router.dart';
import '../../../core/utils/order_timer_helper.dart';
import '../../../models/order_model.dart';
import '../../features/orders/widgets/universal_order_card.dart';
import 'widgets/shopkeeper_order_details_modal.dart';

class ShopkeeperOrdersScreen extends ConsumerStatefulWidget {
  const ShopkeeperOrdersScreen({
    this.shopId,
    super.key,
  });

  final String? shopId;

  @override
  ConsumerState<ShopkeeperOrdersScreen> createState() =>
      _ShopkeeperOrdersScreenState();
}

class _ShopkeeperOrdersScreenState
    extends ConsumerState<ShopkeeperOrdersScreen> {
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void didUpdateWidget(ShopkeeperOrdersScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.shopId != widget.shopId) {
      _searchController.clear();
      _searchQuery = '';
    }
  }

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
    final effectiveShopId =
        widget.shopId ?? ref.watch(currentShopkeeperShopIdProvider);

    final activeOrdersAsync =
        ref.watch(shopActiveOrdersStreamProvider(effectiveShopId));
    final now = ref.watch(orderReconciliationTickerProvider).value ?? DateTime.now();

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Orders',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: InkWell(
              onTap: () => context.push(AppRoutes.shopkeeperProfile),
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
      body: activeOrdersAsync.when(
        data: (allActiveOrders) {
          if (allActiveOrders.isEmpty) {
            return _EmptyActiveOrdersView(isDark: isDark);
          }

          final activeOrders = allActiveOrders
              .where((o) => _matchesOrderSearch(o, _searchQuery))
              .toList();

          // Auto-reconciliation check on live boundary
          for (final order in activeOrders) {
            if (order.isPlaced && OrderTimerHelper.isAcceptExpired(order, now)) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                ref.read(orderServiceProvider).checkAndExpireOrder(order.orderId, customNow: now);
              });
            } else if (order.isAccepted && OrderTimerHelper.isDeliveryExpired(order, now)) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                ref.read(orderServiceProvider).checkAndExpireOrder(order.orderId, customNow: now);
              });
            }
          }

          return ListView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              // ── Search Field (Customer Name, Phone, Order ID) ──
              Container(
                height: 42,
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
                      color: isDark
                          ? AppColors.darkTextSecondary
                          : AppColors.textSecondary,
                    ),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    prefixIcon: Icon(
                      Icons.search_rounded,
                      size: 20,
                      color: isDark
                          ? AppColors.darkTextSecondary
                          : AppColors.textSecondary,
                    ),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 18),
                            color: isDark
                                ? AppColors.darkTextSecondary
                                : AppColors.textSecondary,
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
              const SizedBox(height: 14),

              // 1. Active Orders Section Header with Count Badge
              Row(
                children: [
                  Text(
                    'Active Orders',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: isDark
                          ? AppColors.darkTextPrimary
                          : AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2.5,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(
                        alpha: isDark ? 0.25 : 0.12,
                      ),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.primary.withValues(
                          alpha: isDark ? 0.50 : 0.30,
                        ),
                      ),
                    ),
                    child: Text(
                      '${activeOrders.length}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // 2. Compact Active Order Cards (placed & accepted)
              if (activeOrders.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      'No matching active orders found',
                      style: TextStyle(
                        fontSize: 14,
                        color: isDark
                            ? AppColors.darkTextSecondary
                            : AppColors.textSecondary,
                      ),
                    ),
                  ),
                )
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: activeOrders.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final order = activeOrders[index];
                    return UniversalOrderCard(
                      order: order,
                      perspective: OrderCardPerspective.shopkeeper,
                      customNow: now,
                      onTap: () => ShopkeeperOrderDetailsModal.show(
                        context,
                        order: order,
                      ),
                    );
                  },
                ),
            ],
          );
        },
        loading: () => const Center(
          child: CircularProgressIndicator(
            color: AppColors.primary,
          ),
        ),
        error: (err, stack) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.error_outline_rounded,
                  size: 48,
                  color: AppColors.error,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Failed to load active orders',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  err.toString(),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark
                        ? AppColors.darkTextSecondary
                        : AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => ref.invalidate(
                    shopActiveOrdersStreamProvider(effectiveShopId),
                  ),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Retry'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyActiveOrdersView extends StatelessWidget {
  const _EmptyActiveOrdersView({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Center(
                child: Icon(
                  Icons.receipt_long_outlined,
                  size: 44,
                  color: AppColors.primary,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'No active orders',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    fontSize: 19,
                    color: isDark
                        ? AppColors.darkTextPrimary
                        : AppColors.textPrimary,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              'Customer orders will appear here when placed.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5,
                color: isDark
                    ? AppColors.darkTextSecondary
                    : AppColors.textSecondary,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
