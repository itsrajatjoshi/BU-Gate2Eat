import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_constants.dart';
import '../../core/providers.dart';
import '../../core/router.dart';
import 'shopkeeper_home_screen.dart';
import 'shopkeeper_order_history_screen.dart';
import 'shopkeeper_orders_screen.dart';

class ShopkeeperMainShell extends ConsumerStatefulWidget {
  const ShopkeeperMainShell({super.key});

  @override
  ConsumerState<ShopkeeperMainShell> createState() =>
      _ShopkeeperMainShellState();
}

class _ShopkeeperMainShellState extends ConsumerState<ShopkeeperMainShell> {
  int _currentIndex = 0;
  String? _lastShopId;

  @override
  Widget build(BuildContext context) {
    // Single source of truth: central provider resolving phone to shopId
    final shopId = ref.watch(currentShopkeeperShopIdProvider);

    // If phone number is unknown / not assigned to any shop, show safe unauthorized view
    if (shopId == null || shopId.isEmpty) {
      _lastShopId = null;
      _currentIndex = 0;
      return _buildUnauthorizedView(context);
    }

    // Reset tab index if switching between different shopkeepers
    if (_lastShopId != null && _lastShopId != shopId) {
      _currentIndex = 0;
    }
    _lastShopId = shopId;

    final screens = [
      ShopkeeperOrdersScreen(
        key: ValueKey('orders_$shopId'),
        shopId: shopId,
      ),
      ShopkeeperOrderHistoryScreen(
        key: ValueKey('history_$shopId'),
        shopId: shopId,
      ),
      ShopkeeperHomeScreen(
        key: ValueKey('home_$shopId'),
        shopId: shopId,
      ),
    ];

    return PopScope(
      canPop: _currentIndex == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_currentIndex != 0) {
          setState(() {
            _currentIndex = 0;
          });
        }
      },
      child: Scaffold(
        body: IndexedStack(
          key: ValueKey('shopkeeper_stack_$shopId'),
          index: _currentIndex,
          children: screens,
        ),
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) {
            if (_currentIndex != index) {
              setState(() => _currentIndex = index);
            }
          },
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.receipt_long_outlined),
              activeIcon: Icon(Icons.receipt_long_rounded),
              label: 'Orders',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.history_outlined),
              activeIcon: Icon(Icons.history_rounded),
              label: 'Order History',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.storefront_outlined),
              activeIcon: Icon(Icons.storefront_rounded),
              label: 'Shop',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUnauthorizedView(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final localStorage = ref.watch(localStorageServiceProvider);
    final phone = localStorage.userPhone;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Shopkeeper Panel'),
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
                  Icons.store_mall_directory_outlined,
                  size: 40,
                  color: AppColors.error,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                'No Shop Assigned',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                phone.isNotEmpty
                    ? 'The phone number (+91 $phone) is not registered with any active food shop. Please contact the administrator.'
                    : 'No phone number found for this session. Please log in again.',
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
                onPressed: () async {
                  await clearCustomerSession(ref);
                  if (context.mounted) {
                    context.go(AppRoutes.onboarding);
                  }
                },
                icon: const Icon(Icons.logout_rounded, size: 18),
                label: const Text('Return to Login'),
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
