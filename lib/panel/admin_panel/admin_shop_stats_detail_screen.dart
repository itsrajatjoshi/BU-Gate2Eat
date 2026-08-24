// BU Gate2Eat — Admin Panel
// Shop Statistics Detail Screen (Phase C, D & E)
// Shows isolated in-app order stats breakdown, WhatsApp count, navigation to App Orders list,
// and safe monthly reset for the selected shop.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_constants.dart';
import '../../core/providers.dart';
import '../../models/shop_model.dart';
import '../../models/shop_stats_model.dart';

class AdminShopStatsDetailScreen extends ConsumerStatefulWidget {
  const AdminShopStatsDetailScreen({
    required this.shopId,
    super.key,
  });

  final String shopId;

  @override
  ConsumerState<AdminShopStatsDetailScreen> createState() =>
      _AdminShopStatsDetailScreenState();
}

class _AdminShopStatsDetailScreenState
    extends ConsumerState<AdminShopStatsDetailScreen> {
  bool _isResetting = false;

  Future<void> _handleReset(String shopName) async {
    if (_isResetting) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Reset $shopName?'),
        content: const Text(
          "This will permanently delete this shop's current app order records and reset all order statistics. This action cannot be undone.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('Reset'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isResetting = true);

    try {
      await ref.read(shopStatsServiceProvider).fullShopReset(widget.shopId);

      // Invalidate stream caches to trigger fresh load immediately
      ref.invalidate(shopStatsStreamProvider(widget.shopId));
      ref.invalidate(shopOrdersStreamProvider(widget.shopId));
      ref.invalidate(allShopStatsStreamProvider);

      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text('$shopName data reset successfully.'),
              backgroundColor: AppColors.success,
              behavior: SnackBarBehavior.floating,
            ),
          );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text('Failed to reset $shopName data: $e'),
              backgroundColor: AppColors.error,
              behavior: SnackBarBehavior.floating,
            ),
          );
      }
    } finally {
      if (mounted) {
        setState(() => _isResetting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final shopsAsync = ref.watch(shopsProvider);
    final statsAsync = ref.watch(shopStatsStreamProvider(widget.shopId));

    // Resolve shop info
    final shop = shopsAsync.valueOrNull
        ?.where((s) => s.id == widget.shopId)
        .firstOrNull;

    final shopName = shop?.name ??
        (statsAsync.valueOrNull?.shopName.isNotEmpty == true
            ? statsAsync.valueOrNull!.shopName
            : 'Shop Statistics');

    return Scaffold(
      appBar: AppBar(
        title: Text(
          shopName,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
        elevation: 0,
      ),
      body: statsAsync.when(
        data: (rawStats) {
          final stats = rawStats ??
              ShopStats.zero(
                shopId: widget.shopId,
                shopName: shopName,
              );

          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            physics: const BouncingScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── 1. Shop Header & High-Level Summary Card ──
                _buildSummaryHeaderCard(context, shop, stats, isDark),
                const SizedBox(height: 16),

                // ── 2. In-App Orders Breakdown Card ──
                _buildAppOrdersBreakdownCard(context, stats, isDark),
                const SizedBox(height: 16),

                // ── 3. WhatsApp Orders Card ──
                _buildWhatsAppCard(context, stats, isDark),
                const SizedBox(height: 16),

                // ── 4. Billing Period & Reset Metadata Card ──
                _buildPeriodMetadataCard(context, stats, isDark),
                const SizedBox(height: 24),

                // ── 5. Action Buttons (View App Orders & Reset Data) ──
                _buildActionButtons(context, shopName, isDark),
              ],
            ),
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
                  Icons.error_outline_rounded,
                  size: 48,
                  color: AppColors.error,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Failed to load shop statistics',
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
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryHeaderCard(
    BuildContext context,
    Shop? shop,
    ShopStats stats,
    bool isDark,
  ) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? AppColors.darkDivider : AppColors.divider,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.storefront_rounded,
                  color: AppColors.primary,
                  size: 26,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      stats.shopName.isNotEmpty ? stats.shopName : 'Shop Statistics',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Shop ID: ${widget.shopId}',
                      style: TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
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
          const SizedBox(height: 16),
          const Divider(height: 1, thickness: 0.8),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _buildHeaderStatItem('Total Orders', '${stats.totalOrders}', AppColors.primary, isDark),
              ),
              Expanded(
                child: _buildHeaderStatItem('App Orders', '${stats.appOrders}', AppColors.primary, isDark),
              ),
              Expanded(
                child: _buildHeaderStatItem('WhatsApp', '${stats.whatsappOrders}', const Color(0xFF25D366), isDark),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderStatItem(
    String label,
    String value,
    Color color,
    bool isDark,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w900,
            color: color,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: isDark
                ? AppColors.darkTextSecondary
                : AppColors.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildAppOrdersBreakdownCard(
    BuildContext context,
    ShopStats stats,
    bool isDark,
  ) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? AppColors.darkDivider : AppColors.divider,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.phone_android_rounded,
                size: 20,
                color: AppColors.primary,
              ),
              SizedBox(width: 8),
              Text(
                'APP ORDERS BREAKDOWN',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1, thickness: 0.8),
          const SizedBox(height: 10),

          // Total App Orders
          _buildMetricRow(
            title: 'Total Handled App Orders',
            value: '${stats.appOrders}',
            color: AppColors.primary,
            icon: Icons.receipt_long_rounded,
            isDark: isDark,
            isBold: true,
          ),
          const Divider(height: 16, thickness: 0.6),

          // Accepted
          _buildMetricRow(
            title: 'Accepted Orders',
            value: '${stats.accepted}',
            color: AppColors.success,
            icon: Icons.check_circle_outline_rounded,
            isDark: isDark,
          ),
          const Divider(height: 16, thickness: 0.6),

          // Delivered
          _buildMetricRow(
            title: 'Delivered Successfully',
            value: '${stats.delivered}',
            color: AppColors.success,
            icon: Icons.task_alt_rounded,
            isDark: isDark,
          ),
          const Divider(height: 16, thickness: 0.6),

          // Not Accepted
          _buildMetricRow(
            title: 'Not Accepted / Timeout (20m)',
            value: '${stats.notAccepted}',
            color: AppColors.warning,
            icon: Icons.timer_off_outlined,
            isDark: isDark,
          ),
          const Divider(height: 16, thickness: 0.6),

          // Rejected After Accept
          _buildMetricRow(
            title: 'Rejected After Accept (≤15m)',
            value: '${stats.rejectedAfterAccept}',
            color: AppColors.error,
            icon: Icons.cancel_outlined,
            isDark: isDark,
          ),
          const Divider(height: 16, thickness: 0.6),

          // Delivery Expired
          _buildMetricRow(
            title: 'Delivery Expired (>90m)',
            value: '${stats.deliveryExpired}',
            color: Colors.deepPurple,
            icon: Icons.hourglass_disabled_rounded,
            isDark: isDark,
          ),
        ],
      ),
    );
  }

  Widget _buildWhatsAppCard(
    BuildContext context,
    ShopStats stats,
    bool isDark,
  ) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? AppColors.darkDivider : AppColors.divider,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.chat_bubble_rounded,
                size: 20,
                color: Color(0xFF25D366),
              ),
              SizedBox(width: 8),
              Text(
                'WHATSAPP ORDERS',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1, thickness: 0.8),
          const SizedBox(height: 12),
          _buildMetricRow(
            title: 'Total WhatsApp Orders',
            value: '${stats.whatsappOrders}',
            color: const Color(0xFF25D366),
            icon: Icons.send_rounded,
            isDark: isDark,
            isBold: true,
          ),
          const SizedBox(height: 8),
          Text(
            'WhatsApp orders are counter-tracked only. No customer data or documents are saved in Firestore.',
            style: TextStyle(
              fontSize: 11.5,
              color: isDark
                  ? AppColors.darkTextSecondary
                  : AppColors.textSecondary,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPeriodMetadataCard(
    BuildContext context,
    ShopStats stats,
    bool isDark,
  ) {
    final lastResetText = stats.lastResetAt != null
        ? '${stats.lastResetAt!.day}/${stats.lastResetAt!.month}/${stats.lastResetAt!.year} at ${stats.lastResetAt!.hour}:${stats.lastResetAt!.minute.toString().padLeft(2, '0')}'
        : 'Never (All-time tracking)';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? AppColors.darkDivider : AppColors.divider,
          width: 1,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Text(
                'Billing Period',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: isDark
                      ? AppColors.darkTextSecondary
                      : AppColors.textSecondary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  stats.currentPeriod.isNotEmpty ? stats.currentPeriod : 'Active Billing Cycle',
                  textAlign: TextAlign.end,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                'Last Reset',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: isDark
                      ? AppColors.darkTextSecondary
                      : AppColors.textSecondary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  lastResetText,
                  textAlign: TextAlign.end,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricRow({
    required String title,
    required String value,
    required Color color,
    required IconData icon,
    required bool isDark,
    bool isBold = false,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: isDark ? 0.20 : 0.10),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: color),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
              color: isDark
                  ? AppColors.darkTextPrimary
                  : AppColors.textPrimary,
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: isBold ? 17 : 15,
            fontWeight: isBold ? FontWeight.w900 : FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons(
    BuildContext context,
    String shopName,
    bool isDark,
  ) {
    return Column(
      children: [
        // ── View App Orders (Phase D) ──
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton.icon(
            onPressed: _isResetting
                ? null
                : () => context.push('/admin/stats/${widget.shopId}/orders'),
            icon: const Icon(Icons.list_alt_rounded, size: 18),
            label: const Text(
              'VIEW APP ORDERS',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),

        // ── Reset Shop Data (Phase E) ──
        SizedBox(
          width: double.infinity,
          height: 48,
          child: OutlinedButton.icon(
            onPressed: _isResetting ? null : () => _handleReset(shopName),
            icon: _isResetting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.error,
                    ),
                  )
                : const Icon(Icons.restart_alt_rounded, size: 18),
            label: Text(
              _isResetting ? 'RESETTING DATA...' : 'RESET DATA',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.error,
              side: const BorderSide(color: AppColors.error, width: 1.2),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
