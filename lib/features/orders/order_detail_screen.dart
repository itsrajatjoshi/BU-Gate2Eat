// BU Gate2Eat — Features
// Order Detail Screen (Customer In-App Order Status & Item Overview)

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_constants.dart';
import '../../core/providers.dart';
import '../../core/utils/order_timer_helper.dart';
import '../../models/order_model.dart';
import '../../services/whatsapp_service.dart';
import 'reorder_helper.dart';

class OrderDetailScreen extends ConsumerWidget {
  const OrderDetailScreen({
    required this.orderId,
    this.initialOrder,
    super.key,
  });

  final String orderId;
  final AppOrder? initialOrder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final orderAsync = ref.watch(singleOrderStreamProvider(orderId));
    final dummyOrders = ref.watch(dummyOrdersProvider);

    // Fallback resolution for local testing/transitional orders
    AppOrder? getFallback() {
      try {
        return dummyOrders.firstWhere((o) => o.orderId == orderId);
      } catch (_) {
        return initialOrder;
      }
    }

    return orderAsync.when(
      data: (order) {
        final effectiveOrder = order ?? getFallback();
        if (effectiveOrder == null) {
          return _buildNotFoundScreen(context);
        }
        return _buildOrderContent(context, ref, effectiveOrder, isDark);
      },
      loading: () {
        final fallback = getFallback();
        if (fallback != null) {
          return _buildOrderContent(context, ref, fallback, isDark);
        }
        return Scaffold(
          appBar: AppBar(title: const Text('Order Details')),
          body: const Center(
            child: CircularProgressIndicator(color: AppColors.primary),
          ),
        );
      },
      error: (err, _) {
        final fallback = getFallback();
        if (fallback != null) {
          return _buildOrderContent(context, ref, fallback, isDark);
        }
        return Scaffold(
          appBar: AppBar(title: const Text('Order Details')),
          body: Center(
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
                  Text(
                    'Failed to load order details: $err',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: isDark
                          ? AppColors.darkTextSecondary
                          : AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () =>
                        ref.refresh(singleOrderStreamProvider(orderId)),
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
        );
      },
    );
  }

  Widget _buildNotFoundScreen(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Order Details'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.receipt_long_outlined,
              size: 64,
              color: Colors.grey,
            ),
            const SizedBox(height: 16),
            const Text(
              'Order not found',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: () => context.pop(),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text('Go Back'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderContent(
    BuildContext context,
    WidgetRef ref,
    AppOrder order,
    bool isDark,
  ) {
    final now = ref.watch(orderReconciliationTickerProvider).value ?? DateTime.now();

    final isCancelled = order.status == 'cancelled';
    final isRejected = order.status == 'rejected';
    final isExpired = order.status == 'delivery_expired';
    final isDelivered = order.status == 'delivered';
    final isAccepted = order.status == 'accepted';
    final isPlaced = order.status == 'placed';

    final shops = ref.watch(shopsProvider).valueOrNull ?? [];
    final shop = shops.where((s) => s.id == order.shopId).firstOrNull;
    final shopPhone = (shop?.contactNumber.trim().isNotEmpty == true)
        ? shop!.contactNumber.trim()
        : ((shop?.orderNumber.trim().isNotEmpty == true)
            ? shop!.orderNumber.trim()
            : (AppAuthRoles.shopkeeperPhoneMap.entries
                    .where((e) => e.value == order.shopId)
                    .map((e) => e.key)
                    .firstOrNull ??
                ''));

    // Live zero-boundary auto-reconciliation
    if (isPlaced && OrderTimerHelper.isAcceptExpired(order, now)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(orderServiceProvider).checkAndExpireOrder(order.orderId, customNow: now);
      });
    } else if (isAccepted && OrderTimerHelper.isDeliveryExpired(order, now)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(orderServiceProvider).checkAndExpireOrder(order.orderId, customNow: now);
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Order Details',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Text(
              order.orderId,
              style: TextStyle(
                fontSize: 12,
                color: isDark
                    ? AppColors.darkTextSecondary
                    : AppColors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        actions: [
          if (!isCancelled)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: Tooltip(
                  message: shopPhone.isNotEmpty
                      ? 'Call ${order.shopName} (+91 $shopPhone)'
                      : 'Call ${order.shopName}',
                  child: Material(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.08)
                        : Colors.black.withValues(alpha: 0.05),
                    shape: const CircleBorder(),
                    child: InkWell(
                      onTap: () => _handleCallShop(context, order.shopName, shopPhone),
                      customBorder: const CircleBorder(),
                      child: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.12)
                                : Colors.black.withValues(alpha: 0.08),
                            width: 1,
                          ),
                        ),
                        child: Icon(
                          Icons.call_outlined,
                          size: 19,
                          color: isDark
                              ? AppColors.darkTextPrimary
                              : AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ─── 1. Status Stepper Card ─────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkSurface : Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        order.shopName,
                        style: const TextStyle(
                          fontSize: 16.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      _buildStatusBadge(order, now, isDark),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (isCancelled)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppColors.error.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.cancel_outlined, color: AppColors.error, size: 18),
                          SizedBox(width: 8),
                          Text(
                            'This order was cancelled.',
                            style: TextStyle(
                              color: AppColors.error,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    )
                  else if (isRejected)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppColors.error.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.cancel_outlined, color: AppColors.error, size: 18),
                              SizedBox(width: 8),
                              Text(
                                'This order was rejected by shopkeeper.',
                                style: TextStyle(
                                  color: AppColors.error,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                          if (order.rejectionReason.trim().isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              'Reason: ${order.rejectionReason.trim()}',
                              style: TextStyle(
                                color: isDark
                                    ? AppColors.darkTextSecondary
                                    : AppColors.textSecondary,
                                fontSize: 12.5,
                              ),
                            ),
                          ],
                        ],
                      ),
                    )
                  else if (isExpired)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.deepPurple.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.hourglass_disabled_rounded, color: Colors.deepPurple, size: 18),
                              SizedBox(width: 8),
                              Text(
                                'This order has expired.',
                                style: TextStyle(
                                  color: Colors.deepPurple,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                          if (order.rejectionReason.trim().isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              'Reason: ${order.rejectionReason.trim()}',
                              style: TextStyle(
                                color: isDark
                                    ? AppColors.darkTextSecondary
                                    : AppColors.textSecondary,
                                fontSize: 12.5,
                              ),
                            ),
                          ],
                        ],
                      ),
                    )
                  else
                    _buildStatusStepper(
                      isPlaced: isPlaced,
                      isAccepted: isAccepted,
                      isDelivered: isDelivered,
                      isDark: isDark,
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ─── 2. Ordered Items List ──────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkSurface : Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Items (${order.totalItemCount})',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Divider(height: 1, thickness: 0.8),
                  const SizedBox(height: 12),
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: order.items.length,
                    separatorBuilder: (_, __) => const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Divider(height: 1, thickness: 0.5),
                    ),
                    itemBuilder: (context, index) {
                      final item = order.items[index];
                      return Row(
                        children: [
                          // Item Thumbnail
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: item.imageUrl.isNotEmpty
                                ? CachedNetworkImage(
                                    imageUrl: item.imageUrl,
                                    width: 44,
                                    height: 44,
                                    fit: BoxFit.cover,
                                    errorWidget: (_, __, ___) => Container(
                                      width: 44,
                                      height: 44,
                                      color: isDark
                                          ? AppColors.darkSurfaceVariant
                                          : AppColors.surfaceVariant,
                                      child: const Icon(
                                        Icons.fastfood_rounded,
                                        size: 20,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  )
                                : Container(
                                    width: 44,
                                    height: 44,
                                    color: isDark
                                        ? AppColors.darkSurfaceVariant
                                        : AppColors.surfaceVariant,
                                    child: const Icon(
                                      Icons.fastfood_rounded,
                                      size: 20,
                                      color: Colors.grey,
                                    ),
                                  ),
                          ),
                          const SizedBox(width: 12),

                          // Name & Quantity
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (item.hasOptions) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    item.optionsDescription,
                                    style: const TextStyle(
                                      color: AppColors.primary,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                                const SizedBox(height: 2),
                                Text(
                                  'Qty: ${item.quantity} × ₹${item.price}',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    color: isDark
                                        ? AppColors.darkTextSecondary
                                        : AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // Total
                          Text(
                            '₹${item.totalPrice.toStringAsFixed(0)}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14.5,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ─── 3. Special Instructions (if any) ───────────────────────
            if (order.specialInstructions.trim().isNotEmpty) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.darkSurface : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isDark ? AppColors.darkDivider : AppColors.divider,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.note_alt_outlined,
                          size: 16,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Special Instructions',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: isDark
                                ? AppColors.darkTextSecondary
                                : AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      order.specialInstructions.trim(),
                      style: const TextStyle(fontSize: 13.5, height: 1.3),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // ─── 4. Delivery Pickup Location Card ───────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkSurface : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isDark ? AppColors.darkDivider : AppColors.divider,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.location_on_rounded,
                      size: 20,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Delivery Location',
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          order.deliveryNote.isNotEmpty
                              ? order.deliveryNote
                              : 'Bennett University • Gate No. 3',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark
                                ? AppColors.darkTextSecondary
                                : AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (order.isDelivered) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.darkSurface : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isDark ? AppColors.darkDivider : AppColors.divider,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppColors.success.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.delivery_dining_rounded,
                        size: 20,
                        color: AppColors.success,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Delivered By',
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            order.deliveryPersonName.trim().isNotEmpty
                                ? order.deliveryPersonName.trim()
                                : 'Not available',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: isDark
                                  ? AppColors.darkTextPrimary
                                  : AppColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.08),
              blurRadius: 14,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Bill Rows
              _buildBillRow('Subtotal', order.formattedTotal, isDark),
              const SizedBox(height: 6),
              _buildBillRow('Tax (5%)', 'Included', isDark),
              const SizedBox(height: 6),
              _buildBillRow('Delivery / Service', 'Free (Gate 3)', isDark),
              const SizedBox(height: 8),
              const Divider(height: 1, thickness: 0.8),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Total Payable',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    order.formattedTotal,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Payment: Cash / UPI at delivery',
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? AppColors.darkTextSecondary : AppColors.textHint,
                  ),
                ),
              ),
              if (isPlaced) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: OutlinedButton(
                    onPressed: () =>
                        _confirmCancelDialog(context, ref, order.orderId),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.error,
                      side: const BorderSide(color: AppColors.error, width: 1.2),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.close_rounded, size: 18),
                        SizedBox(width: 6),
                        Text(
                          'Cancel Order',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ] else if (isDelivered) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: ElevatedButton(
                    onPressed: () => ReorderHelper.handleReorder(
                      context: context,
                      ref: ref,
                      order: order,
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.replay_rounded, size: 18),
                        SizedBox(width: 8),
                        Text(
                          'Reorder',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static Widget _buildStatusBadge(AppOrder order, DateTime now, bool isDark) {
    Color color = AppColors.warning;
    String label = 'Placed 🟡';

    if (order.status == 'accepted') {
      color = AppColors.success;
      label = 'Accepted 🟢';
    } else if (order.status == 'delivered') {
      color = AppColors.success;
      label = 'Delivered ✅';
    } else if (order.status == 'cancelled') {
      color = AppColors.error;
      label = 'Cancelled ❌';
    } else if (order.status == 'rejected') {
      color = AppColors.error;
      label = 'Rejected ❌';
    } else if (order.status == 'delivery_expired') {
      color = Colors.deepPurple;
      label = 'Expired ⏱️';
    }

    String countdown = '';
    if (order.status == 'placed') {
      final rem = OrderTimerHelper.getRemainingAcceptDuration(order, now);
      countdown = OrderTimerHelper.formatCountdown(rem);
    } else if (order.status == 'accepted') {
      final rem = OrderTimerHelper.getRemainingDeliveryDuration(order, now);
      countdown = OrderTimerHelper.formatCountdown(rem);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 12.5,
            ),
          ),
          if (countdown.isNotEmpty) ...[
            const SizedBox(width: 4),
            Text(
              '($countdown)',
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }

  static Widget _buildStatusStepper({
    required bool isPlaced,
    required bool isAccepted,
    required bool isDelivered,
    required bool isDark,
  }) {
    return Row(
      children: [
        _buildStepNode(
          title: 'Placed',
          isReached: true,
          isDark: isDark,
        ),
        _buildStepLine(isDone: isAccepted || isDelivered, isDark: isDark),
        _buildStepNode(
          title: 'Accepted',
          isReached: isAccepted || isDelivered,
          isDark: isDark,
        ),
        _buildStepLine(isDone: isDelivered, isDark: isDark),
        _buildStepNode(
          title: 'Delivered',
          isReached: isDelivered,
          isDark: isDark,
        ),
      ],
    );
  }

  static Widget _buildStepNode({
    required String title,
    required bool isReached,
    required bool isDark,
  }) {
    return Column(
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: isReached
                ? AppColors.success
                : (isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant),
            shape: BoxShape.circle,
            border: Border.all(
              color: isReached
                  ? AppColors.success
                  : (isDark ? AppColors.darkDivider : AppColors.divider),
              width: 1.5,
            ),
          ),
          child: Center(
            child: isReached
                ? const Icon(
                    Icons.check_rounded,
                    size: 18,
                    color: Colors.white,
                  )
                : Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.darkTextHint : AppColors.textHint,
                      shape: BoxShape.circle,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 5),
        Text(
          title,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: isReached ? FontWeight.w700 : FontWeight.w500,
            color: isReached
                ? AppColors.success
                : (isDark ? AppColors.darkTextSecondary : AppColors.textHint),
          ),
        ),
      ],
    );
  }

  static Widget _buildStepLine({required bool isDone, required bool isDark}) {
    return Expanded(
      child: Container(
        height: 2.5,
        margin: const EdgeInsets.only(bottom: 20),
        color: isDone
            ? AppColors.success
            : (isDark ? AppColors.darkDivider : AppColors.divider),
      ),
    );
  }

  static Widget _buildBillRow(String label, String value, bool isDark) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
          ),
        ),
      ],
    );
  }

  void _confirmCancelDialog(
      BuildContext context, WidgetRef ref, String orderId) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Cancel Order?',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'Are you sure you want to cancel this order? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('No, Keep Order'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                // Real Firestore Cancellation
                await ref.read(orderServiceProvider).cancelOrder(orderId);
                // Also update local dummy state for safety in transitional phase
                ref.read(dummyOrdersProvider.notifier).cancelOrder(orderId);

                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('Order has been cancelled.'),
                      backgroundColor: AppColors.error,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Failed to cancel order: $e'),
                      backgroundColor: AppColors.error,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('Yes, Cancel'),
          ),
        ],
      ),
    );
  }

  Future<void> _handleCallShop(
    BuildContext context,
    String shopName,
    String shopPhone,
  ) async {
    final clean = shopPhone.trim();
    if (clean.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Contact number for $shopName is not available.'),
          backgroundColor: AppColors.error,
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
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}
