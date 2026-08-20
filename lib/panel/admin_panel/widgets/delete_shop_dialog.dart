// BU Gate2Eat — Admin Panel
// Delete Shop Confirmation Dialog (Real Cascade Delete & Storage Cleanup)

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/providers.dart';
import '../../../models/shop_model.dart';

class DeleteShopDialog extends ConsumerStatefulWidget {
  const DeleteShopDialog({
    required this.shop,
    super.key,
  });

  final Shop shop;

  static Future<bool?> show(BuildContext context, Shop shop) {
    return showDialog<bool>(
      context: context,
      builder: (_) => DeleteShopDialog(shop: shop),
    );
  }

  @override
  ConsumerState<DeleteShopDialog> createState() => _DeleteShopDialogState();
}

class _DeleteShopDialogState extends ConsumerState<DeleteShopDialog> {
  bool _isDeleting = false;

  Future<void> _onDelete() async {
    setState(() => _isDeleting = true);

    try {
      final firestoreService = ref.read(firestoreServiceProvider);
      await firestoreService.deleteShopCascade(
        widget.shop.id,
        bannerUrl: widget.shop.bannerUrl,
      );

      ref.invalidate(shopsProvider);

      if (mounted) {
        setState(() => _isDeleting = false);
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(
                  Icons.delete_outline_rounded,
                  color: Colors.white,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '"${widget.shop.name}" and all menu items deleted.',
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
              ],
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
        setState(() => _isDeleting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete shop: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      title: const Row(
        children: [
          Icon(Icons.delete_outline_rounded, color: AppColors.error, size: 24),
          SizedBox(width: 8),
          Text(
            'Delete this shop?',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
      content: Text(
        'Are you sure you want to delete "${widget.shop.name}" from YummBU? All associated menu items, categories, and photos will be permanently removed.',
        style: TextStyle(
          color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
          fontSize: 14,
          height: 1.4,
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isDeleting ? null : () => Navigator.pop(context, false),
          child: Text(
            'Cancel',
            style: TextStyle(
              color: isDark
                  ? AppColors.darkTextSecondary
                  : AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        ElevatedButton(
          onPressed: _isDeleting ? null : _onDelete,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.error,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
          ),
          child: _isDeleting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text(
                  'Delete',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
        ),
      ],
    );
  }
}
