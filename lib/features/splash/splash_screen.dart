// BU Gate2Eat — Splash Screen
// Initial screen: shows logo, checks force update, navigates to onboarding or home

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_constants.dart';
import '../../core/providers.dart';
import '../../core/router.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    // Wait for splash display (1.5 seconds)
    await Future<void>.delayed(const Duration(milliseconds: 1500));

    if (!mounted) return;

    // Check force update with timeout so splash screen never hangs
    try {
      final forceUpdateService = ref.read(forceUpdateServiceProvider);
      final updateResult = await forceUpdateService
          .checkForUpdate()
          .timeout(const Duration(seconds: 1));

      if (!mounted) return;

      if (updateResult.isUpdateRequired) {
        // Force update required
        return;
      }
    } catch (_) {
      // Ignore network timeout or Firestore offline errors on splash
    }

    if (!mounted) return;

    // Check if user has completed onboarding
    final localStorage = ref.read(localStorageServiceProvider);

    if (localStorage.isOnboarded) {
      context.go(AppRoutes.home);
    } else {
      context.go(AppRoutes.onboarding);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // App icon placeholder — will be replaced with actual logo
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(AppRadius.xl),
              ),
              child: const Icon(
                Icons.location_on_rounded,
                color: Colors.white,
                size: 50,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              AppConfig.appName,
              style: Theme.of(context).textTheme.displayMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              AppConfig.appTagline,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
