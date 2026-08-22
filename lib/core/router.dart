// BU Gate2Eat — Router Configuration
// GoRouter setup with splash → onboarding → home flow

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/cart/cart_screen.dart';
import '../features/home/home_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/orders/active_orders_screen.dart';
import '../features/orders/order_detail_screen.dart';
import '../features/orders/order_history_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/shop/shop_detail_screen.dart';
import '../features/splash/splash_screen.dart';
import '../models/order_model.dart';
import '../panel/admin_panel/admin_main_shell.dart';
import '../panel/admin_panel/admin_shop_detail_screen.dart';
import '../panel/shopkeeper_panel/shopkeeper_main_shell.dart';
import '../panel/shopkeeper_panel/shopkeeper_profile_screen.dart';

/// App route paths.
class AppRoutes {
  AppRoutes._();

  static const String splash = '/';
  static const String onboarding = '/onboarding';
  static const String home = '/home';
  static const String shopDetail = '/shop/:shopId';
  static const String cart = '/cart';
  static const String activeOrders = '/active-orders';
  static const String orderDetail = '/order/:orderId';
  static const String orderHistory = '/order-history';
  static const String profile = '/profile';
  static const String settings = '/settings';
  static const String shopkeeper = '/shopkeeper';
  static const String shopkeeperProfile = '/shopkeeper/profile';
  static const String admin = '/admin';
  static const String adminShopDetail = '/admin/shop/:shopId';
}

/// GoRouter configuration for the app.
final GoRouter appRouter = GoRouter(
  initialLocation: AppRoutes.splash,
  routes: [
    GoRoute(
      path: AppRoutes.splash,
      pageBuilder: (context, state) => CustomTransitionPage(
        key: state.pageKey,
        child: const SplashScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) =>
            FadeTransition(opacity: animation, child: child),
        transitionDuration: const Duration(milliseconds: 400),
      ),
    ),
    GoRoute(
      path: AppRoutes.onboarding,
      pageBuilder: (context, state) => CustomTransitionPage(
        key: state.pageKey,
        child: const OnboardingScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) =>
            FadeTransition(opacity: animation, child: child),
        transitionDuration: const Duration(milliseconds: 400),
      ),
    ),
    GoRoute(
      path: AppRoutes.home,
      pageBuilder: (context, state) => CustomTransitionPage(
        key: state.pageKey,
        child: const HomeScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) =>
            FadeTransition(opacity: animation, child: child),
        transitionDuration: const Duration(milliseconds: 400),
      ),
    ),
    GoRoute(
      path: AppRoutes.shopkeeper,
      pageBuilder: (context, state) => CustomTransitionPage(
        key: state.pageKey,
        child: const ShopkeeperMainShell(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    ),
    GoRoute(
      path: AppRoutes.admin,
      pageBuilder: (context, state) => CustomTransitionPage(
        key: state.pageKey,
        child: const AdminMainShell(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    ),
    GoRoute(
      path: AppRoutes.adminShopDetail,
      builder: (context, state) {
        final shopId = state.pathParameters['shopId'] ?? '';
        return AdminShopDetailScreen(shopId: shopId);
      },
    ),
    GoRoute(
      path: AppRoutes.shopDetail,
      builder: (context, state) {
        final shopId = state.pathParameters['shopId'] ?? '';
        return ShopDetailScreen(shopId: shopId);
      },
    ),
    GoRoute(
      path: AppRoutes.cart,
      builder: (context, state) => const CartScreen(),
    ),
    GoRoute(
      path: AppRoutes.activeOrders,
      builder: (context, state) => const ActiveOrdersScreen(),
    ),
    GoRoute(
      path: AppRoutes.orderDetail,
      builder: (context, state) {
        final orderId = state.pathParameters['orderId'] ?? '';
        final extraOrder = state.extra as AppOrder?;
        return OrderDetailScreen(orderId: orderId, initialOrder: extraOrder);
      },
    ),
    GoRoute(
      path: AppRoutes.orderHistory,
      builder: (context, state) => const OrderHistoryScreen(),
    ),
    GoRoute(
      path: AppRoutes.profile,
      builder: (context, state) => const ProfileScreen(),
    ),
    GoRoute(
      path: AppRoutes.shopkeeperProfile,
      builder: (context, state) => const ShopkeeperProfileScreen(),
    ),
    GoRoute(
      path: AppRoutes.settings,
      builder: (context, state) => const SettingsScreen(),
    ),
  ],
);
