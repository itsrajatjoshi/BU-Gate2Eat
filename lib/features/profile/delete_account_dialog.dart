// BU Gate2Eat — Delete Account Dialog
// Two-step confirmation flow with phone number verification and safe account deletion.
// Historical orders and support queries are NEVER deleted.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_constants.dart';
import '../../core/providers.dart';
import '../../core/router.dart';

/// Shows the two-step Delete Account flow for the authenticated customer.
/// Returns true if the account was successfully deleted, false otherwise.
Future<bool> showCustomerDeleteAccountFlow(
  BuildContext context,
  WidgetRef ref,
) async {
  final localStorage = ref.read(localStorageServiceProvider);
  final sessionPhone = localStorage.userPhone.trim();

  // ─── 1. First Confirmation: Enter Phone Number ───────────────────────
  final phoneConfirmed = await showDialog<bool>(
    context: context,
    builder: (dialogCtx) {
      final phoneController = TextEditingController();
      String? errorMessage;

      return StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.lg),
            ),
            title: const Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  color: AppColors.error,
                  size: 24,
                ),
                SizedBox(width: 8),
                Text(
                  'Delete Account',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Account deletion is permanent. All your personal profile data and session will be removed.',
                  style: TextStyle(fontSize: 13, height: 1.4),
                ),
                const SizedBox(height: 12),
                const Text(
                  'To confirm account deletion, enter your registered phone number:',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: phoneController,
                  keyboardType: TextInputType.phone,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: 'Enter phone number',
                    prefixIcon: const Icon(Icons.phone_outlined, size: 20),
                    errorText: errorMessage,
                    isDense: true,
                  ),
                  onChanged: (_) {
                    if (errorMessage != null) {
                      setDialogState(() => errorMessage = null);
                    }
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogCtx).pop(false),
                child: const Text(
                  'Cancel',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              ElevatedButton(
                onPressed: () {
                  final entered = phoneController.text.trim();
                  final cleanEntered = AppAuthRoles.normalizeCleanPhone(entered);
                  final cleanSession =
                      AppAuthRoles.normalizeCleanPhone(sessionPhone);

                  if (cleanEntered.isEmpty ||
                      cleanEntered.length < 10 ||
                      cleanEntered != cleanSession) {
                    setDialogState(() {
                      errorMessage =
                          'Incorrect phone number. Please enter your registered phone number.';
                    });
                    return;
                  }

                  Navigator.of(dialogCtx).pop(true);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.error,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                ),
                child: const Text(
                  'Continue',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          );
        },
      );
    },
  );

  if (phoneConfirmed != true || !context.mounted) {
    return false;
  }

  // ─── 2. Second Confirmation: Final Explicit Warning ──────────────────
  final finalConfirmed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogCtx) {
      bool isDeleting = false;

      return StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.lg),
            ),
            title: const Row(
              children: [
                Icon(
                  Icons.delete_forever_rounded,
                  color: AppColors.error,
                  size: 24,
                ),
                SizedBox(width: 8),
                Text(
                  'Are you sure?',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            content: const Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Are you sure you want to permanently delete your account?',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                SizedBox(height: 12),
                Text(
                  '• Account deletion is permanent.\n'
                  '• Historical orders will NOT be deleted.\n'
                  '• The account/profile data will be removed.',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.45,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: isDeleting
                    ? null
                    : () => Navigator.of(dialogCtx).pop(false),
                child: const Text(
                  'Cancel',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              ElevatedButton(
                onPressed: isDeleting
                    ? null
                    : () async {
                        setDialogState(() => isDeleting = true);

                        try {
                          // 1. Delete FCM device token if registered
                          final notificationService =
                              ref.read(notificationServiceProvider);
                          final cachedToken = notificationService.cachedToken;
                          if (cachedToken != null && cachedToken.isNotEmpty) {
                            await notificationService
                                .deleteDeviceToken(cachedToken)
                                .catchError((Object e) {
                              debugPrint(
                                '⚠️ Non-fatal token deletion note: $e',
                              );
                            });
                          }

                          // 2. Clear customer account, profile data, favorites, and session
                          await localStorage.deleteCustomerAccount();

                          if (ctx.mounted) {
                            Navigator.of(dialogCtx).pop(true);
                          }
                        } catch (e) {
                          debugPrint('❌ Account deletion error: $e');
                          if (ctx.mounted) {
                            setDialogState(() => isDeleting = false);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Failed to delete account. Please try again.',
                                ),
                                backgroundColor: AppColors.error,
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.error,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                ),
                child: isDeleting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Text(
                        'Delete Account',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
              ),
            ],
          );
        },
      );
    },
  );

  if (finalConfirmed == true && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(
              Icons.check_circle_outline_rounded,
              color: Colors.white,
              size: 20,
            ),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Your account has been deleted.',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        backgroundColor: AppColors.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        duration: const Duration(seconds: 3),
      ),
    );

    context.go(AppRoutes.onboarding);
    return true;
  }

  return false;
}
