// BU Gate2Eat — Router Configuration
// GoRouter setup with splash → onboarding → home flow

import 'package:go_router/go_router.dart';

import '../features/cart/cart_screen.dart';
import '../features/home/home_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/shop/shop_detail_screen.dart';
import '../features/splash/splash_screen.dart';

/// App route paths.
class AppRoutes {
  AppRoutes._();

  static const String splash = '/';
  static const String onboarding = '/onboarding';
  static const String home = '/home';
  static const String shopDetail = '/shop/:shopId';
  static const String cart = '/cart';
  static const String settings = '/settings';
}

/// GoRouter configuration for the app.
final GoRouter appRouter = GoRouter(
  initialLocation: AppRoutes.splash,
  routes: [
    GoRoute(
      path: AppRoutes.splash,
      builder: (context, state) => const SplashScreen(),
    ),
    GoRoute(
      path: AppRoutes.onboarding,
      builder: (context, state) => const OnboardingScreen(),
    ),
    GoRoute(
      path: AppRoutes.home,
      builder: (context, state) => const HomeScreen(),
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
      path: AppRoutes.settings,
      builder: (context, state) => const SettingsScreen(),
    ),
  ],
);
