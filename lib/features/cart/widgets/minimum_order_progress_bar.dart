import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/providers.dart';

/// Compact Zepto-inspired minimum order progress bar.
/// Displays circular progress ring, remaining amount needed, and minimum order target.
class MinimumOrderProgressBar extends ConsumerWidget {
  const MinimumOrderProgressBar({
    required this.shopId,
    required this.currentTotal,
    this.padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    this.compact = false,
    super.key,
  });

  final String shopId;
  final double currentTotal;
  final EdgeInsetsGeometry padding;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final minOrderMap = ref.watch(shopMinimumOrderProvider);
    final minOrderAmount = minOrderMap[shopId] ?? 0;

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
        color: isDark ? const Color(0xFF1B2420) : const Color(0xFFEDF7F2),
        borderRadius: BorderRadius.circular(compact ? 24 : 14),
        border: Border.all(
          color: AppColors.success.withValues(
            alpha: isDark ? 0.35 : 0.25,
          ),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Circular Progress Ring with Smooth Fill Animation
          SizedBox(
            width: compact ? 30 : 34,
            height: compact ? 30 : 34,
            child: Stack(
              alignment: Alignment.center,
              children: [
                TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0.0, end: progress),
                  duration: const Duration(milliseconds: 600),
                  curve: Curves.easeOutCubic,
                  builder: (context, animatedProgress, _) {
                    return CircularProgressIndicator(
                      value: animatedProgress,
                      strokeWidth: 3,
                      backgroundColor: isDark
                          ? Colors.grey.shade800
                          : Colors.grey.shade300,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        AppColors.success,
                      ),
                    );
                  },
                ),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: Icon(
                    isReached
                        ? Icons.check_rounded
                        : Icons.delivery_dining_rounded,
                    key: ValueKey<bool>(isReached),
                    size: compact ? 15 : 17,
                    color: AppColors.success,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Text Details
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isReached
                      ? 'Minimum order reached ✓'
                      : 'Add ₹$diff more to place order',
                  style: TextStyle(
                    fontSize: compact ? 11.5 : 12.5,
                    fontWeight: FontWeight.w700,
                    color: isReached
                        ? AppColors.success
                        : (isDark ? Colors.white : AppColors.textPrimary),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 1),
                Text(
                  'Minimum order ₹$minOrderAmount',
                  style: TextStyle(
                    fontSize: compact ? 10 : 10.5,
                    fontWeight: FontWeight.w500,
                    color: isDark
                        ? AppColors.darkTextSecondary
                        : AppColors.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
