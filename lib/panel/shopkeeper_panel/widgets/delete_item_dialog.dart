// BU Gate2Eat — Shopkeeper Panel
// Delete Menu Item Confirmation Dialog

import 'package:flutter/material.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../models/menu_item_model.dart';

class DeleteItemDialog extends StatelessWidget {
  const DeleteItemDialog({
    required this.item,
    super.key,
  });

  final MenuItem item;

  static Future<bool?> show(BuildContext context, MenuItem item) {
    return showDialog<bool>(
      context: context,
      builder: (_) => DeleteItemDialog(item: item),
    );
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
            'Delete this item?',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
      content: Text(
        'Are you sure you want to delete "${item.name}" from your shop menu? This action cannot be undone.',
        style: TextStyle(
          color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
          fontSize: 14,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
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
          onPressed: () => Navigator.pop(context, true),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.error,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
          ),
          child: const Text(
            'Delete',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}
