// BU Gate2Eat — Shopkeeper Panel
// Main Shell with exactly 3 bottom tabs: Home | Orders | Profile
// Visual styling identical to User App HomeScreen

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers.dart';
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

  @override
  Widget build(BuildContext context) {
    final localStorage = ref.watch(localStorageServiceProvider);
    final cleanPhone =
        localStorage.userPhone.replaceAll(RegExp(r'[^0-9]'), '');

    // Dynamically resolve shop ownership by phone number
    String shopId = 'rajat_shop';
    if (cleanPhone.endsWith('8295643910') || cleanPhone == '8295643910') {
      shopId = 'nayan_shop';
    } else if (cleanPhone.endsWith('8000383993') ||
        cleanPhone == '8000383993') {
      shopId = 'rajat_shop';
    }

    final screens = [
      ShopkeeperOrdersScreen(shopId: shopId),
      ShopkeeperOrderHistoryScreen(shopId: shopId),
      ShopkeeperHomeScreen(shopId: shopId),
    ];

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: screens,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
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
    );
  }
}
