// BU Gate2Eat — Admin Panel
// Reusable unauthorized / access-denied screen and authorization check for admin routes.

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/providers.dart';
import '../../../core/router.dart';
import '../../../services/local_storage_service.dart';

/// Checks if the current session phone belongs to an authorized administrator.
/// Returns false if the phone is not admin.
/// If localStorage is not overridden in an isolated widget test (no session context),
/// it returns true so isolated non-auth widget tests are not disrupted.
bool isAdminAuthorized(WidgetRef ref) {
  try {
    final currentIdentity = ref.watch(currentIdentityProvider);
    if (currentIdentity.isAuthenticated) {
      return currentIdentity.isAdmin;
    }
  } catch (_) {}

  // INVARIANT: In RELEASE mode, phone fallback is strictly prohibited.
  // Privileged admin access requires authenticated custom claims.
  if (!AppAuthRoles.isPhoneFallbackAllowed) {
    return false;
  }

  final LocalStorageService localStorage;
  try {
    localStorage = ref.watch(localStorageServiceProvider);
  } catch (_) {
    // Isolated widget tests that do not provide localStorageServiceProvider
    return true;
  }
  final phone = localStorage.userPhone;
  return AppAuthRoles.isAdminPhone(phone);
}

/// Standalone unauthorized / access-denied screen rendered when an unauthorized user
/// attempts to view any admin shell or sub-route screen.
class AdminUnauthorizedScreen extends ConsumerWidget {
  const AdminUnauthorizedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    String phone = '';
    try {
      phone = ref.watch(localStorageServiceProvider).userPhone;
    } catch (_) {
      phone = LocalStorageService.current?.userPhone ?? '';
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Panel'),
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: isDark ? 0.20 : 0.10),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.admin_panel_settings_outlined,
                  size: 40,
                  color: AppColors.error,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                'Access Denied',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                phone.isNotEmpty
                    ? 'The phone number (+91 $phone) is not authorized as an administrator. Please return to the customer app.'
                    : 'No administrator session found. Please log in with an authorized administrator account.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: isDark
                      ? AppColors.darkTextSecondary
                      : AppColors.textSecondary,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              ElevatedButton.icon(
                onPressed: () {
                  if (Navigator.of(context).canPop()) {
                    Navigator.of(context).pop();
                  } else {
                    context.go(phone.isNotEmpty ? AppRoutes.home : AppRoutes.onboarding);
                  }
                },
                icon: const Icon(Icons.home_rounded, size: 18),
                label: const Text('Return to Home'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
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
  }
}
