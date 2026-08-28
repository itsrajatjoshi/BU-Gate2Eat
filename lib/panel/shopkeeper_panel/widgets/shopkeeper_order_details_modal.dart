// BU Gate2Eat — Shopkeeper Panel
// Order Details Bottom Sheet (Phase 2 — Part 2.2, 2.3, 2.4, 2.5)
// Displays complete order details with active rejection, acceptance, and delivery handling

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/providers.dart';
import '../../../../core/utils/order_timer_helper.dart';
import '../../../../models/order_model.dart';
import '../../../../services/whatsapp_service.dart';
import 'accept_order_dialog.dart';
import 'mark_delivered_dialog.dart';
import 'reject_order_dialog.dart';

class ShopkeeperOrderDetailsModal extends ConsumerStatefulWidget {
  const ShopkeeperOrderDetailsModal({
    required this.order,
    super.key,
  });

  final AppOrder order;

  static Future<void> show(
    BuildContext context, {
    required AppOrder order,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ShopkeeperOrderDetailsModal(order: order),
    );
  }

  @override
  ConsumerState<ShopkeeperOrderDetailsModal> createState() =>
      _ShopkeeperOrderDetailsModalState();
}

class _ShopkeeperOrderDetailsModalState
    extends ConsumerState<ShopkeeperOrderDetailsModal> {
  bool _isSubmitting = false;

  Future<void> _handleAccept() async {
    if (_isSubmitting) return;
    final confirmed = await AcceptOrderDialog.show(context, order: widget.order);
    if (confirmed == true && mounted) {
      setState(() => _isSubmitting = true);
      try {
        await ref.read(orderServiceProvider).updateOrderStatus(
              widget.order.orderId,
              'accepted',
            );
        ref.read(dummyOrdersProvider.notifier).updateOrderStatus(
              widget.order.orderId,
              'accepted',
            );

        if (mounted) {
          Navigator.pop(context); // Close bottom sheet

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Order #${widget.order.orderId} accepted successfully',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              backgroundColor: AppColors.success,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          setState(() => _isSubmitting = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Failed to accept order: $e',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              backgroundColor: AppColors.error,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }
    }
  }

  Future<void> _handleMarkDelivered() async {
    if (_isSubmitting) return;
    final confirmed =
        await MarkDeliveredDialog.show(context, order: widget.order);
    if (confirmed == true && mounted) {
      setState(() => _isSubmitting = true);
      try {
        String deliveryPersonId = '';
        String deliveryPersonName = '';
        try {
          final localStorage = ref.read(localStorageServiceProvider);
          deliveryPersonId = localStorage.userPhone.trim();
          deliveryPersonName = localStorage.userName.trim();
        } catch (_) {}

        await ref.read(orderServiceProvider).updateOrderStatus(
              widget.order.orderId,
              'delivered',
              deliveryPersonId: deliveryPersonId,
              deliveryPersonName: deliveryPersonName,
            );
        ref.read(dummyOrdersProvider.notifier).updateOrderStatus(
              widget.order.orderId,
              'delivered',
            );

        if (mounted) {
          Navigator.pop(context); // Close bottom sheet

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Order #${widget.order.orderId} marked as delivered',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              backgroundColor: AppColors.success,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          setState(() => _isSubmitting = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Failed to mark order as delivered: $e',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              backgroundColor: AppColors.error,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }
    }
  }

  Future<void> _handleReject() async {
    if (_isSubmitting) return;
    final reason = await RejectOrderDialog.show(context, order: widget.order);
    if (reason != null && reason.trim().isNotEmpty && mounted) {
      setState(() => _isSubmitting = true);
      try {
        await ref.read(orderServiceProvider).updateOrderStatus(
              widget.order.orderId,
              'rejected',
              rejectionReason: reason.trim(),
            );
        ref.read(dummyOrdersProvider.notifier).updateOrderStatus(
              widget.order.orderId,
              'rejected',
              rejectionReason: reason.trim(),
            );

        if (mounted) {
          Navigator.pop(context); // Close bottom sheet

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Order #${widget.order.orderId} rejected',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              backgroundColor: AppColors.error,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          setState(() => _isSubmitting = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Failed to reject order: $e',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              backgroundColor: AppColors.error,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }
    }
  }

  Future<void> _handleCallCustomer(
    String customerPhone,
    String customerName,
  ) async {
    final clean = customerPhone.trim();
    if (clean.isEmpty || clean == 'Not provided') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Unable to call customer.\nCustomer phone number is unavailable for $customerName.',
          ),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
      return;
    }

    final launched = await WhatsAppService.launchPhoneCall(clean);
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not open phone dialer for +91 $clean'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final now = ref.watch(orderReconciliationTickerProvider).value ?? DateTime.now();

    final order = widget.order;
    final isPlaced = order.status == 'placed';
    final isAccepted = order.status == 'accepted';
    final isDelivered = order.status == 'delivered';
    final isRejected = order.status == 'rejected';
    final isCancelled = order.status == 'cancelled';
    final isExpired = order.status == 'delivery_expired';

    // Auto-reconcile on expired zero boundary
    if (isPlaced && OrderTimerHelper.isAcceptExpired(order, now)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(orderServiceProvider).checkAndExpireOrder(order.orderId, customNow: now);
      });
    } else if (isAccepted && OrderTimerHelper.isDeliveryExpired(order, now)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(orderServiceProvider).checkAndExpireOrder(order.orderId, customNow: now);
      });
    }

    final Color statusColor;
    final String statusText;
    final IconData statusIcon;
    String headerCountdown = '';

    if (isDelivered) {
      statusColor = AppColors.success;
      statusText = 'DELIVERED';
      statusIcon = Icons.task_alt_rounded;
    } else if (isAccepted) {
      final rem = OrderTimerHelper.getRemainingDeliveryDuration(order, now);
      headerCountdown = OrderTimerHelper.formatCountdown(rem);
      statusColor = AppColors.success;
      statusText = 'ACCEPTED';
      statusIcon = Icons.delivery_dining_rounded;
    } else if (isRejected) {
      statusColor = AppColors.error;
      statusText = 'REJECTED';
      statusIcon = Icons.cancel_outlined;
    } else if (isCancelled) {
      statusColor = isDark
          ? AppColors.darkTextSecondary
          : AppColors.textSecondary;
      statusText = 'CANCELLED';
      statusIcon = Icons.block_rounded;
    } else if (isExpired) {
      statusColor = Colors.deepPurple;
      statusText = 'EXPIRED';
      statusIcon = Icons.hourglass_disabled_rounded;
    } else {
      final rem = OrderTimerHelper.getRemainingAcceptDuration(order, now);
      headerCountdown = OrderTimerHelper.formatCountdown(rem);
      statusColor = AppColors.warning;
      statusText = 'PLACED';
      statusIcon = Icons.schedule_rounded;
    }

    final customerDisplayName = order.customerName.trim().isNotEmpty
        ? order.customerName.trim()
        : 'Customer';
    final customerDisplayPhone = order.customerPhone.trim().isNotEmpty
        ? order.customerPhone.trim()
        : 'Not provided';

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.88,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(
          color: isDark ? AppColors.darkDivider : AppColors.divider,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.40 : 0.15),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 1. Drag Handle
            const SizedBox(height: 12),
            Center(
              child: Container(
                width: 40,
                height: 4.5,
                decoration: BoxDecoration(
                  color: isDark
                      ? AppColors.darkTextSecondary.withValues(alpha: 0.35)
                      : AppColors.textSecondary.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // 2. Header: Order ID + Status Badge + Close Button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Order #${order.orderId}',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            fontFamily: 'monospace',
                            color: isDark
                                ? AppColors.darkTextPrimary
                                : AppColors.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 9,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: statusColor.withValues(
                                  alpha: isDark ? 0.20 : 0.12,
                                ),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: statusColor.withValues(
                                    alpha: isDark ? 0.45 : 0.35,
                                  ),
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    statusIcon,
                                    size: 13,
                                    color: statusColor,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    statusText,
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w900,
                                      color: statusColor,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  if (headerCountdown.isNotEmpty) ...[
                                    const SizedBox(width: 3),
                                    Text(
                                      '($headerCountdown)',
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w700,
                                        color: statusColor,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _formatTime(order.createdAt),
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
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                    tooltip: 'Close',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            const Divider(height: 1, thickness: 0.8),

            // 3. Scrollable Order Details Body
            Flexible(
              child: ListView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                children: [
                  // ── Rejection Reason Banner (If Rejected) ───────────────────
                  if (isRejected && order.rejectionReason.trim().isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.error.withValues(
                          alpha: isDark ? 0.15 : 0.08,
                        ),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: AppColors.error.withValues(
                            alpha: isDark ? 0.40 : 0.30,
                          ),
                          width: 1,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(
                                Icons.cancel_rounded,
                                size: 16,
                                color: AppColors.error,
                              ),
                              SizedBox(width: 6),
                              Text(
                                'Order Rejected',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.error,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Reason: ${order.rejectionReason.trim()}',
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w500,
                              color: isDark
                                  ? AppColors.darkTextPrimary
                                  : AppColors.textPrimary,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // ── Customer Information Card ──────────────────────────────
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color:
                            isDark ? AppColors.darkDivider : AppColors.divider,
                        width: 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Customer Details',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.4,
                            color: isDark
                                ? AppColors.darkTextSecondary
                                : AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(7),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(
                                  alpha: isDark ? 0.20 : 0.10,
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                Icons.person_rounded,
                                size: 16,
                                color: AppColors.primary,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                customerDisplayName,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: isDark
                                      ? AppColors.darkTextPrimary
                                      : AppColors.textPrimary,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(7),
                              decoration: BoxDecoration(
                                color: AppColors.success.withValues(
                                  alpha: isDark ? 0.20 : 0.10,
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                Icons.phone_rounded,
                                size: 16,
                                color: AppColors.success,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                customerDisplayPhone,
                                style: TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w600,
                                  fontFamily: 'monospace',
                                  color: isDark
                                      ? AppColors.darkTextPrimary
                                      : AppColors.textPrimary,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Call Customer Action Button (Compact 34x34 circular icon button)
                            Tooltip(
                              message: customerDisplayPhone != 'Not provided'
                                  ? 'Call $customerDisplayName (+91 $customerDisplayPhone)'
                                  : 'Call $customerDisplayName',
                              child: Material(
                                color: isDark
                                    ? Colors.white.withValues(alpha: 0.08)
                                    : Colors.black.withValues(alpha: 0.05),
                                shape: const CircleBorder(),
                                child: InkWell(
                                  onTap: () => _handleCallCustomer(
                                    order.customerPhone,
                                    customerDisplayName,
                                  ),
                                  customBorder: const CircleBorder(),
                                  child: Container(
                                    width: 34,
                                    height: 34,
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
                                      size: 17,
                                      color: isDark
                                          ? AppColors.darkTextPrimary
                                          : AppColors.textPrimary,
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
                  if (order.isDelivered) ...[
                    const SizedBox(height: 16),
                    Text(
                      'Delivery Information',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: isDark
                            ? AppColors.darkTextPrimary
                            : AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Theme.of(context).cardColor,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isDark
                              ? AppColors.darkDivider
                              : AppColors.divider,
                          width: 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppColors.success.withValues(
                                alpha: isDark ? 0.20 : 0.10,
                              ),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.delivery_dining_rounded,
                              size: 18,
                              color: AppColors.success,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Delivery By',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: isDark
                                        ? AppColors.darkTextSecondary
                                        : AppColors.textSecondary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  order.deliveryPersonName.trim().isNotEmpty
                                      ? order.deliveryPersonName.trim()
                                      : 'Not available',
                                  style: TextStyle(
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w700,
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
                  const SizedBox(height: 16),

                  // ── Order Items Breakdown ──────────────────────────────────
                  Text(
                    'Order Items (${order.totalItemCount})',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: isDark
                          ? AppColors.darkTextPrimary
                          : AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color:
                            isDark ? AppColors.darkDivider : AppColors.divider,
                        width: 1,
                      ),
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: order.items.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1, thickness: 0.8),
                      itemBuilder: (context, index) {
                        final item = order.items[index];
                        final itemTotal = item.price * item.quantity;

                        return Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          child: Row(
                            children: [
                              // Optional Item Thumbnail if URL available
                              if (item.imageUrl.trim().isNotEmpty) ...[
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: CachedNetworkImage(
                                    imageUrl: item.imageUrl,
                                    width: 44,
                                    height: 44,
                                    fit: BoxFit.cover,
                                    placeholder: (_, __) => Container(
                                      width: 44,
                                      height: 44,
                                      color: isDark
                                          ? AppColors.darkSurfaceVariant
                                          : AppColors.surfaceVariant,
                                      child: const Icon(
                                        Icons.fastfood_rounded,
                                        size: 20,
                                        color: AppColors.primary,
                                      ),
                                    ),
                                    errorWidget: (_, __, ___) => Container(
                                      width: 44,
                                      height: 44,
                                      color: isDark
                                          ? AppColors.darkSurfaceVariant
                                          : AppColors.surfaceVariant,
                                      child: const Icon(
                                        Icons.fastfood_rounded,
                                        size: 20,
                                        color: AppColors.primary,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                              ],

                              // Item Name & Quantity × Price
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.name,
                                      style: TextStyle(
                                        fontSize: 14.5,
                                        fontWeight: FontWeight.w700,
                                        color: isDark
                                            ? AppColors.darkTextPrimary
                                            : AppColors.textPrimary,
                                      ),
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
                                      ),
                                    ],
                                    const SizedBox(height: 3),
                                    Text(
                                      '₹${item.price} × ${item.quantity}',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: isDark
                                            ? AppColors.darkTextSecondary
                                            : AppColors.textSecondary,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              // Line Total
                              Text(
                                '₹$itemTotal',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: isDark
                                      ? AppColors.darkTextPrimary
                                      : AppColors.textPrimary,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ── Special Instructions (Only if present) ─────────────────
                  if (order.specialInstructions.trim().isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.warning.withValues(
                          alpha: isDark ? 0.15 : 0.08,
                        ),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: AppColors.warning.withValues(
                            alpha: isDark ? 0.35 : 0.25,
                          ),
                          width: 1,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(
                                Icons.note_alt_outlined,
                                size: 16,
                                color: AppColors.warning,
                              ),
                              SizedBox(width: 6),
                              Text(
                                'Special Instructions',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.warning,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            order.specialInstructions.trim(),
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w500,
                              color: isDark
                                  ? AppColors.darkTextPrimary
                                  : AppColors.textPrimary,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // ── Campus Delivery Informational Row ──────────────────────
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppColors.darkSurfaceVariant
                          : AppColors.surfaceVariant,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.location_on_outlined,
                          size: 16,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Delivery within Bennett University campus',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark
                                  ? AppColors.darkTextSecondary
                                  : AppColors.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ── Bill Summary (Grand Total) ─────────────────────────────
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color:
                            isDark ? AppColors.darkDivider : AppColors.divider,
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Total Items: ${order.totalItemCount}',
                              style: TextStyle(
                                fontSize: 13,
                                color: isDark
                                    ? AppColors.darkTextSecondary
                                    : AppColors.textSecondary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Grand Total',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: isDark
                                    ? AppColors.darkTextPrimary
                                    : AppColors.textPrimary,
                              ),
                            ),
                          ],
                        ),
                        Text(
                          order.formattedTotal,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // 4. Action Buttons (Only shown for Active Orders: Placed or Accepted)
            if (isPlaced || isAccepted) ...[
              const Divider(height: 1, thickness: 0.8),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
                child: isAccepted
                    ? Builder(
                        builder: (context) {
                          final canRejectAccepted = !OrderTimerHelper.isRejectExpired(order, now);

                          if (!canRejectAccepted) {
                            // 15-min rejection window has expired: Only show Mark Delivered button
                            return SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: _isSubmitting ? null : _handleMarkDelivered,
                                icon: _isSubmitting
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Icon(
                                        Icons.task_alt_rounded,
                                        size: 18,
                                      ),
                                label: Text(
                                  _isSubmitting ? 'Updating...' : 'Mark as Delivered',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14.5,
                                  ),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.success,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            );
                          }

                          final rejectCountdown = OrderTimerHelper.formatCountdown(
                            OrderTimerHelper.getRemainingRejectDuration(order, now),
                          );

                          return Row(
                            children: [
                              // Reject Order Button (Active only within 15-min window)
                              Expanded(
                                flex: 1,
                                child: OutlinedButton(
                                  onPressed: _isSubmitting ? null : _handleReject,
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppColors.error,
                                    side: BorderSide(
                                      color: AppColors.error.withValues(alpha: 0.4),
                                    ),
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        const Text(
                                          'Reject Order',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13.5,
                                          ),
                                        ),
                                        if (rejectCountdown.isNotEmpty) ...[
                                          const SizedBox(width: 4),
                                          Text(
                                            '($rejectCountdown)',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),

                              // Mark Delivered Button (Phase 2.5 Functional Delivery Flow)
                              Expanded(
                                flex: 2,
                                child: ElevatedButton.icon(
                                  onPressed: _isSubmitting ? null : _handleMarkDelivered,
                                  icon: _isSubmitting
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Icon(
                                          Icons.task_alt_rounded,
                                          size: 18,
                                        ),
                                  label: Text(
                                    _isSubmitting ? 'Updating...' : 'Mark as Delivered',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14.5,
                                    ),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.success,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      )
                    : Row(
                        children: [
                          // Reject Button (Phase 2.3 Functional Rejection Flow)
                          Expanded(
                            flex: 1,
                            child: OutlinedButton(
                              onPressed: _isSubmitting ? null : _handleReject,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.error,
                                side: BorderSide(
                                  color: AppColors.error.withValues(alpha: 0.4),
                                ),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: const Text(
                                'Reject',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),

                          // Accept Order Button (Phase 2.4 Functional Acceptance Flow)
                          Expanded(
                            flex: 2,
                            child: ElevatedButton.icon(
                              onPressed: _isSubmitting ? null : _handleAccept,
                              icon: _isSubmitting
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.check_rounded,
                                      size: 18,
                                    ),
                              label: Text(
                                _isSubmitting ? 'Updating...' : 'Accept Order',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14.5,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 45) {
      return 'Just now';
    } else if (diff.inMinutes < 60) {
      final mins = diff.inMinutes;
      return '$mins min${mins > 1 ? 's' : ''} ago';
    } else if (diff.inHours < 24) {
      final hrs = diff.inHours;
      return '$hrs hour${hrs > 1 ? 's' : ''} ago';
    } else {
      final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
      final minute = dt.minute.toString().padLeft(2, '0');
      final period = dt.hour >= 12 ? 'PM' : 'AM';
      return '$hour:$minute $period';
    }
  }
}
