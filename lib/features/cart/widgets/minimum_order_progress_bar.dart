import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/providers.dart';

/// A customer-facing live visual progress indicator for shop minimum order requirements.
///
/// Displays:
/// - Target minimum order amount
/// - Animated progress bar with vibrant green branding
/// - Remaining amount needed (or completion checkmark)
/// - Automatically hides if minimumOrderAmount <= 0 or cart has no items for this shop
class MinimumOrderProgressBar extends ConsumerWidget {
  const MinimumOrderProgressBar({
    required this.shopId,
    required this.currentTotal,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
    super.key,
  });

  final String shopId;
  final double currentTotal;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final minOrderMap = ref.watch(shopMinimumOrderProvider);
    final minOrderAmount = minOrderMap[shopId] ?? 0;

    // Hide if no minimum is configured for this shop
    if (minOrderAmount <= 0) {
      return const SizedBox.shrink();
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isReached = currentTotal >= minOrderAmount;
    final progress = (currentTotal / minOrderAmount).clamp(0.0, 1.0);
    final diff = (minOrderAmount - currentTotal).ceil();

    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.success.withValues(
          alpha: isDark ? 0.12 : 0.08,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.success.withValues(
            alpha: isDark ? 0.35 : 0.22,
          ),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Minimum order ₹$minOrderAmount',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isDark
                      ? AppColors.darkTextSecondary
                      : AppColors.textSecondary,
                ),
              ),
              Text(
                isReached ? '✓ 100%' : '${(progress * 100).toInt()}%',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: AppColors.success,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor:
                  isDark ? Colors.grey.shade800 : Colors.grey.shade200,
              valueColor: const AlwaysStoppedAnimation<Color>(
                AppColors.success,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(
                Icons.check_circle_rounded,
                size: 14,
                color: AppColors.success,
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  isReached
                      ? 'Minimum order reached ✓'
                      : '₹$diff more to reach minimum ₹$minOrderAmount',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: isReached
                        ? AppColors.success
                        : (isDark
                            ? Colors.green.shade300
                            : const Color(0xFF1B8755)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
