// BU Gate2Eat — Shopkeeper Panel
// Reject Order Confirmation & Reason Selection Dialog (Phase 2 — Part 2.3)

import 'package:flutter/material.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../models/order_model.dart';

class RejectOrderDialog extends StatefulWidget {
  const RejectOrderDialog({
    required this.order,
    super.key,
  });

  final AppOrder order;

  static Future<String?> show(
    BuildContext context, {
    required AppOrder order,
  }) {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => RejectOrderDialog(order: order),
    );
  }

  @override
  State<RejectOrderDialog> createState() => _RejectOrderDialogState();
}

class _RejectOrderDialogState extends State<RejectOrderDialog> {
  static const List<String> _predefinedReasons = [
    'Items not available',
    'Shop closed early',
    'Too busy right now',
    'Other',
  ];

  String _selectedReason = 'Items not available';
  late final TextEditingController _customReasonController;

  @override
  void initState() {
    super.initState();
    _customReasonController = TextEditingController();
    _customReasonController.addListener(() {
      if (_selectedReason == 'Other') {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _customReasonController.dispose();
    super.dispose();
  }

  bool get _isConfirmEnabled {
    if (_selectedReason == 'Other') {
      return _customReasonController.text.trim().isNotEmpty;
    }
    return true;
  }

  String get _effectiveReason {
    if (_selectedReason == 'Other') {
      return _customReasonController.text.trim();
    }
    return _selectedReason;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
      ),
      backgroundColor: Theme.of(context).cardColor,
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: isDark ? 0.20 : 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.cancel_outlined,
              color: AppColors.error,
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          const Text(
            'Reject Order?',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Please select a reason for rejecting this order.',
              style: TextStyle(
                fontSize: 13.5,
                color: isDark
                    ? AppColors.darkTextSecondary
                    : AppColors.textSecondary,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 14),

            // Radio List of Rejection Reasons
            Column(
              children: _predefinedReasons.map((reason) {
                final isSelected = _selectedReason == reason;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: InkWell(
                    onTap: () {
                      setState(() {
                        _selectedReason = reason;
                      });
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? (isDark
                                ? AppColors.darkSurfaceVariant
                                : AppColors.surfaceVariant)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isSelected
                              ? AppColors.error.withValues(alpha: 0.6)
                              : (isDark
                                  ? AppColors.darkDivider
                                  : AppColors.divider),
                          width: isSelected ? 1.4 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isSelected
                                ? Icons.radio_button_checked_rounded
                                : Icons.radio_button_off_rounded,
                            size: 18,
                            color: isSelected
                                ? AppColors.error
                                : (isDark
                                    ? AppColors.darkTextSecondary
                                    : AppColors.textSecondary),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              reason,
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: isSelected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: isDark
                                    ? AppColors.darkTextPrimary
                                    : AppColors.textPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),

            // Custom Reason Input (Visible only when 'Other' is selected)
            if (_selectedReason == 'Other') ...[
              const SizedBox(height: 6),
              TextField(
                controller: _customReasonController,
                autofocus: true,
                maxLines: 2,
                maxLength: 120,
                style: TextStyle(
                  fontSize: 13.5,
                  color: isDark
                      ? AppColors.darkTextPrimary
                      : AppColors.textPrimary,
                ),
                decoration: InputDecoration(
                  hintText: 'Enter rejection reason',
                  hintStyle: TextStyle(
                    fontSize: 13,
                    color: isDark
                        ? AppColors.darkTextSecondary
                        : AppColors.textSecondary,
                  ),
                  filled: true,
                  fillColor: isDark
                      ? AppColors.darkSurfaceVariant
                      : AppColors.surfaceVariant,
                  contentPadding: const EdgeInsets.all(12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(
                      color: isDark ? AppColors.darkDivider : AppColors.divider,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(
                      color: AppColors.error,
                      width: 1.5,
                    ),
                  ),
                  counterText: '',
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: Text(
            'Cancel',
            style: TextStyle(
              color: isDark
                  ? AppColors.darkTextSecondary
                  : AppColors.textSecondary,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
        ),
        ElevatedButton(
          onPressed: _isConfirmEnabled
              ? () => Navigator.pop(context, _effectiveReason)
              : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.error,
            disabledBackgroundColor: AppColors.error.withValues(alpha: 0.35),
            foregroundColor: Colors.white,
            disabledForegroundColor: Colors.white.withValues(alpha: 0.6),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          child: const Text(
            'Reject Order',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ),
      ],
    );
  }
}
