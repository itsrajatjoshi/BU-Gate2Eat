// BU Gate2Eat — Onboarding Screen
// First-time setup: collects Name, Phone, Age

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_constants.dart';
import '../../core/providers.dart';
import '../../core/router.dart';
import '../../models/order_model.dart';
import '../cart/cart_provider.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _onGetStarted() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final phone = _phoneController.text.trim();
    final localStorage = ref.read(localStorageServiceProvider);
    await localStorage.saveUserProfile(
      name: _nameController.text.trim(),
      phone: phone,
    );

    // Atomically synchronize customer identity and purge any leftover in-memory state from previous session
    ref.read(customerIdentityProvider.notifier).refresh();
    ref.read(cartProvider.notifier).clearCart();
    ref.read(dummyOrdersProvider.notifier).setOrders(<AppOrder>[]);
    ref.invalidate(customerActiveOrdersStreamProvider);
    ref.invalidate(customerOrderHistoryStreamProvider);
    ref.invalidate(favoritesProvider);
    ref.invalidate(currentShopkeeperShopIdProvider);
    ref.invalidate(shopActiveOrdersStreamProvider);
    ref.invalidate(shopOrderHistoryStreamProvider);
    ref.invalidate(shopStatsStreamProvider);
    ref.invalidate(shopCategoriesProvider);
    ref.invalidate(shopMenuItemsProvider);

    // Non-blocking notification permission request & token registration
    try {
      final notificationService = ref.read(notificationServiceProvider);
      await notificationService.requestPermission();
      await notificationService.syncCurrentSessionToken(localStorage: localStorage);
    } catch (e) {
      debugPrint('⚠️ [Onboarding] Note during notification session sync: $e');
    }

    if (!mounted) return;
    if (AppAuthRoles.isAdminPhone(phone)) {
      context.go(AppRoutes.admin);
    } else if (AppAuthRoles.isShopkeeperPhone(phone)) {
      context.go(AppRoutes.shopkeeper);
    } else {
      context.go(AppRoutes.home);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: AppSpacing.xxl),

                // Header
                Text(
                  'Welcome to',
                  style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                ),
                Text(
                  AppConfig.appName,
                  style: Theme.of(context).textTheme.displayLarge?.copyWith(
                        color: AppColors.primary,
                      ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Just a few details to get you started.',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                ),

                const SizedBox(height: AppSpacing.xxl),

                // Name field
                Text(
                  'Your Name',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: AppSpacing.sm),
                TextFormField(
                  controller: _nameController,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    hintText: 'Enter your name',
                    prefixIcon: Icon(Icons.person_outline_rounded),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter your name';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: AppSpacing.lg),

                // Phone field
                Text(
                  'Phone Number',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: AppSpacing.sm),
                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(10),
                  ],
                  decoration: const InputDecoration(
                    hintText: '10-digit phone number',
                    prefixIcon: Icon(Icons.phone_outlined),
                    prefixText: '+91 ',
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter your phone number';
                    }
                    if (value.trim().length != 10) {
                      return 'Phone number must be 10 digits';
                    }
                    if (!RegExp(r'^[6-9]\d{9}$').hasMatch(value.trim())) {
                      return 'Please enter a valid Indian phone number';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: AppSpacing.xxl),

                // Get Started button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _onGetStarted,
                    child: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Get Started'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
