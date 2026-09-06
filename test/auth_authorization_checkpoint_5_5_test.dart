// BU Gate2Eat — Checkpoint 5.5
// STEP 1: Targeted Authorization & Security Verification Suite
// Tests all 4 areas:
// 1. AdminMainShell authorization
// 2. Admin Sub-Route authorization (5 sub-routes)
// 3. ShopkeeperProfileScreen authorization
// 4. Central GoRouter redirect guards (/admin* and /shopkeeper*)

import 'package:bugate2eat_app/core/constants/app_constants.dart';
import 'package:bugate2eat_app/core/providers.dart';
import 'package:bugate2eat_app/core/router.dart';
import 'package:bugate2eat_app/models/shop_model.dart';
import 'package:bugate2eat_app/models/shop_stats_model.dart';
import 'package:bugate2eat_app/panel/admin_panel/admin_customer_queries_screen.dart';
import 'package:bugate2eat_app/panel/admin_panel/admin_main_shell.dart';
import 'package:bugate2eat_app/panel/admin_panel/admin_monthly_reports_screen.dart';
import 'package:bugate2eat_app/panel/admin_panel/admin_shop_detail_screen.dart';
import 'package:bugate2eat_app/panel/admin_panel/admin_shop_orders_screen.dart';
import 'package:bugate2eat_app/panel/admin_panel/admin_shop_stats_detail_screen.dart';
import 'package:bugate2eat_app/panel/admin_panel/widgets/admin_unauthorized_screen.dart';
import 'package:bugate2eat_app/panel/shopkeeper_panel/shopkeeper_profile_screen.dart';
import 'package:bugate2eat_app/services/local_storage_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

GoRouter _buildTestRouter({String initialLocation = AppRoutes.home}) {
  return GoRouter(
    initialLocation: initialLocation,
    redirect: centralRouteGuard,
    routes: [
      GoRoute(path: AppRoutes.splash, builder: (_, __) => const Scaffold(body: Text('Splash View'))),
      GoRoute(path: AppRoutes.onboarding, builder: (_, __) => const Scaffold(body: Text('Onboarding View'))),
      GoRoute(path: AppRoutes.home, builder: (_, __) => const Scaffold(body: Text('Customer Home View'))),
      GoRoute(path: AppRoutes.admin, builder: (_, __) => const Scaffold(body: Text('Admin Shell View'))),
      GoRoute(path: AppRoutes.adminShopDetail, builder: (_, __) => const Scaffold(body: Text('Admin Shop Detail View'))),
      GoRoute(path: AppRoutes.adminMonthlyReports, builder: (_, __) => const Scaffold(body: Text('Admin Monthly Reports View'))),
      GoRoute(path: AppRoutes.adminCustomerQueries, builder: (_, __) => const Scaffold(body: Text('Admin Queries View'))),
      GoRoute(path: AppRoutes.shopkeeper, builder: (_, __) => const Scaffold(body: Text('Shopkeeper Shell View'))),
      GoRoute(path: AppRoutes.shopkeeperProfile, builder: (_, __) => const Scaffold(body: Text('Shopkeeper Profile View'))),
    ],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final mockShop = Shop(
    id: 'rajat_shop',
    name: 'Rajat Shop',
    description: 'Fresh rolls and snacks',
    bannerUrl: '',
    contactNumber: '8000383993',
    orderNumber: '8000383993',
    openTime: '09:00',
    closeTime: '23:00',
    isClosedOverride: false,
    isActive: true,
    sortOrder: 1,
    searchKeywords: const ['rolls'],
    deliveryNote: 'Delivery at Gate 2',
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );

  group('Checkpoint 5.5: Central GoRouter Redirect Guard Tests', () {
    testWidgets('1. Central Guard: Customer phone attempting /admin is redirected to /home', (tester) async {
      SharedPreferences.setMockInitialValues({
        'user_phone': '9876543210',
        'user_name': 'Test Customer',
        'is_onboarded': true,
      });
      final prefs = await SharedPreferences.getInstance();
      final localStorage = LocalStorageService(prefs);
      final router = _buildTestRouter();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localStorageServiceProvider.overrideWithValue(localStorage),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      router.go(AppRoutes.admin);
      await tester.pumpAndSettle();

      expect(find.text('Customer Home View'), findsOneWidget);
      expect(find.text('Admin Shell View'), findsNothing);
    });

    testWidgets('2. Central Guard: Customer phone attempting /admin/shop/:shopId is redirected to /home', (tester) async {
      SharedPreferences.setMockInitialValues({
        'user_phone': '9876543210',
        'user_name': 'Test Customer',
        'is_onboarded': true,
      });
      final prefs = await SharedPreferences.getInstance();
      final localStorage = LocalStorageService(prefs);
      final router = _buildTestRouter();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localStorageServiceProvider.overrideWithValue(localStorage),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      router.go('/admin/shop/rajat_shop');
      await tester.pumpAndSettle();

      expect(find.text('Customer Home View'), findsOneWidget);
      expect(find.text('Admin Shop Detail View'), findsNothing);
    });

    testWidgets('3. Central Guard: Customer phone attempting /admin/reports is redirected to /home', (tester) async {
      SharedPreferences.setMockInitialValues({
        'user_phone': '9876543210',
        'user_name': 'Test Customer',
        'is_onboarded': true,
      });
      final prefs = await SharedPreferences.getInstance();
      final localStorage = LocalStorageService(prefs);
      final router = _buildTestRouter();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localStorageServiceProvider.overrideWithValue(localStorage),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      router.go(AppRoutes.adminMonthlyReports);
      await tester.pumpAndSettle();

      expect(find.text('Customer Home View'), findsOneWidget);
      expect(find.text('Admin Monthly Reports View'), findsNothing);
    });

    testWidgets('4. Central Guard: Customer phone attempting /admin/customer-queries is redirected to /home', (tester) async {
      SharedPreferences.setMockInitialValues({
        'user_phone': '9876543210',
        'user_name': 'Test Customer',
        'is_onboarded': true,
      });
      final prefs = await SharedPreferences.getInstance();
      final localStorage = LocalStorageService(prefs);
      final router = _buildTestRouter();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localStorageServiceProvider.overrideWithValue(localStorage),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      router.go(AppRoutes.adminCustomerQueries);
      await tester.pumpAndSettle();

      expect(find.text('Customer Home View'), findsOneWidget);
      expect(find.text('Admin Queries View'), findsNothing);
    });

    testWidgets('5. Central Guard: Unauthenticated user attempting /admin is redirected to /onboarding', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final localStorage = LocalStorageService(prefs);
      final router = _buildTestRouter(initialLocation: AppRoutes.splash);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localStorageServiceProvider.overrideWithValue(localStorage),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      router.go(AppRoutes.admin);
      await tester.pumpAndSettle();

      expect(find.text('Onboarding View'), findsOneWidget);
      expect(find.text('Admin Shell View'), findsNothing);
    });

    testWidgets('6. Central Guard: Unauthenticated user attempting /shopkeeper is redirected to /onboarding', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final localStorage = LocalStorageService(prefs);
      final router = _buildTestRouter(initialLocation: AppRoutes.splash);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localStorageServiceProvider.overrideWithValue(localStorage),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      router.go(AppRoutes.shopkeeper);
      await tester.pumpAndSettle();

      expect(find.text('Onboarding View'), findsOneWidget);
      expect(find.text('Shopkeeper Shell View'), findsNothing);
    });

    testWidgets('7. Central Guard: Customer phone attempting /shopkeeper is redirected to /home', (tester) async {
      SharedPreferences.setMockInitialValues({
        'user_phone': '9876543210',
        'user_name': 'Test Customer',
        'is_onboarded': true,
      });
      final prefs = await SharedPreferences.getInstance();
      final localStorage = LocalStorageService(prefs);
      final router = _buildTestRouter();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localStorageServiceProvider.overrideWithValue(localStorage),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      router.go(AppRoutes.shopkeeper);
      await tester.pumpAndSettle();

      expect(find.text('Customer Home View'), findsOneWidget);
      expect(find.text('Shopkeeper Shell View'), findsNothing);
    });

    testWidgets('8. Central Guard: Customer phone attempting /shopkeeper/profile is redirected to /home', (tester) async {
      SharedPreferences.setMockInitialValues({
        'user_phone': '9876543210',
        'user_name': 'Test Customer',
        'is_onboarded': true,
      });
      final prefs = await SharedPreferences.getInstance();
      final localStorage = LocalStorageService(prefs);
      final router = _buildTestRouter();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localStorageServiceProvider.overrideWithValue(localStorage),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      router.go(AppRoutes.shopkeeperProfile);
      await tester.pumpAndSettle();

      expect(find.text('Customer Home View'), findsOneWidget);
      expect(find.text('Shopkeeper Profile View'), findsNothing);
    });

    testWidgets('9. Central Guard: Shopkeeper phone attempting /admin is redirected to /home', (tester) async {
      SharedPreferences.setMockInitialValues({
        'user_phone': '8000383993',
        'user_name': 'Rajat Shopkeeper',
        'is_onboarded': true,
      });
      final prefs = await SharedPreferences.getInstance();
      final localStorage = LocalStorageService(prefs);
      final router = _buildTestRouter();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localStorageServiceProvider.overrideWithValue(localStorage),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      router.go(AppRoutes.admin);
      await tester.pumpAndSettle();

      expect(find.text('Customer Home View'), findsOneWidget);
      expect(find.text('Admin Shell View'), findsNothing);
    });

    testWidgets('10. Central Guard: Shopkeeper phone attempting /admin/customer-queries is redirected to /home', (tester) async {
      SharedPreferences.setMockInitialValues({
        'user_phone': '8000383993',
        'user_name': 'Rajat Shopkeeper',
        'is_onboarded': true,
      });
      final prefs = await SharedPreferences.getInstance();
      final localStorage = LocalStorageService(prefs);
      final router = _buildTestRouter();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localStorageServiceProvider.overrideWithValue(localStorage),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      router.go(AppRoutes.adminCustomerQueries);
      await tester.pumpAndSettle();

      expect(find.text('Customer Home View'), findsOneWidget);
      expect(find.text('Admin Queries View'), findsNothing);
    });

    testWidgets('11. Central Guard: Admin phone attempting /admin is allowed', (tester) async {
      SharedPreferences.setMockInitialValues({
        'user_phone': '8078643910',
        'user_name': 'Super Admin',
        'is_onboarded': true,
      });
      final prefs = await SharedPreferences.getInstance();
      final localStorage = LocalStorageService(prefs);
      final router = _buildTestRouter();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localStorageServiceProvider.overrideWithValue(localStorage),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      router.go(AppRoutes.admin);
      await tester.pumpAndSettle();

      expect(find.text('Admin Shell View'), findsOneWidget);
    });

    testWidgets('12. Central Guard: Admin phone attempting /admin/reports is allowed', (tester) async {
      SharedPreferences.setMockInitialValues({
        'user_phone': '8078643910',
        'user_name': 'Super Admin',
        'is_onboarded': true,
      });
      final prefs = await SharedPreferences.getInstance();
      final localStorage = LocalStorageService(prefs);
      final router = _buildTestRouter();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localStorageServiceProvider.overrideWithValue(localStorage),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      router.go(AppRoutes.adminMonthlyReports);
      await tester.pumpAndSettle();

      expect(find.text('Admin Monthly Reports View'), findsOneWidget);
    });

    testWidgets('13. Central Guard: Valid shopkeeper phone attempting /shopkeeper is allowed', (tester) async {
      SharedPreferences.setMockInitialValues({
        'user_phone': '8000383993',
        'user_name': 'Rajat Shopkeeper',
        'is_onboarded': true,
      });
      final prefs = await SharedPreferences.getInstance();
      final localStorage = LocalStorageService(prefs);
      final router = _buildTestRouter();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localStorageServiceProvider.overrideWithValue(localStorage),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      router.go(AppRoutes.shopkeeper);
      await tester.pumpAndSettle();

      expect(find.text('Shopkeeper Shell View'), findsOneWidget);
    });

    testWidgets('14. Central Guard: Valid shopkeeper phone attempting /shopkeeper/profile is allowed', (tester) async {
      SharedPreferences.setMockInitialValues({
        'user_phone': '8000383993',
        'user_name': 'Rajat Shopkeeper',
        'is_onboarded': true,
      });
      final prefs = await SharedPreferences.getInstance();
      final localStorage = LocalStorageService(prefs);
      final router = _buildTestRouter();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localStorageServiceProvider.overrideWithValue(localStorage),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      router.go(AppRoutes.shopkeeperProfile);
      await tester.pumpAndSettle();

      expect(find.text('Shopkeeper Profile View'), findsOneWidget);
    });
  });

  group('Checkpoint 5.5: Admin Screen-Level Defense-in-Depth Tests', () {
    testWidgets('15. AdminMainShell renders AdminUnauthorizedScreen for customer session', (tester) async {
      SharedPreferences.setMockInitialValues({
        'user_phone': '9876543210',
        'user_name': 'Customer User',
        'is_onboarded': true,
      });
      final prefs = await SharedPreferences.getInstance();
      final localStorage = LocalStorageService(prefs);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localStorageServiceProvider.overrideWithValue(localStorage),
          ],
          child: const MaterialApp(
            home: AdminMainShell(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(AdminUnauthorizedScreen), findsOneWidget);
      expect(find.text('Access Denied'), findsOneWidget);
      expect(find.textContaining('is not authorized as an administrator'), findsOneWidget);
      expect(find.text('Return to Home'), findsOneWidget);
    });

    testWidgets('16. AdminShopDetailScreen renders AdminUnauthorizedScreen for customer session', (tester) async {
      SharedPreferences.setMockInitialValues({
        'user_phone': '9876543210',
        'user_name': 'Customer User',
        'is_onboarded': true,
      });
      final prefs = await SharedPreferences.getInstance();
      final localStorage = LocalStorageService(prefs);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localStorageServiceProvider.overrideWithValue(localStorage),
          ],
          child: const MaterialApp(
            home: AdminShopDetailScreen(shopId: 'rajat_shop'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(AdminUnauthorizedScreen), findsOneWidget);
      expect(find.text('Access Denied'), findsOneWidget);
    });

    testWidgets('17. AdminShopStatsDetailScreen renders AdminUnauthorizedScreen for customer session', (tester) async {
      SharedPreferences.setMockInitialValues({
        'user_phone': '9876543210',
        'user_name': 'Customer User',
        'is_onboarded': true,
      });
      final prefs = await SharedPreferences.getInstance();
      final localStorage = LocalStorageService(prefs);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localStorageServiceProvider.overrideWithValue(localStorage),
            shopsProvider.overrideWith((ref) => Future.value([mockShop])),
          ],
          child: const MaterialApp(
            home: AdminShopStatsDetailScreen(shopId: 'rajat_shop'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(AdminUnauthorizedScreen), findsOneWidget);
      expect(find.text('Access Denied'), findsOneWidget);
    });

    testWidgets('18. AdminShopOrdersScreen renders AdminUnauthorizedScreen for customer session', (tester) async {
      SharedPreferences.setMockInitialValues({
        'user_phone': '9876543210',
        'user_name': 'Customer User',
        'is_onboarded': true,
      });
      final prefs = await SharedPreferences.getInstance();
      final localStorage = LocalStorageService(prefs);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localStorageServiceProvider.overrideWithValue(localStorage),
            shopsProvider.overrideWith((ref) => Future.value([mockShop])),
          ],
          child: const MaterialApp(
            home: AdminShopOrdersScreen(shopId: 'rajat_shop'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(AdminUnauthorizedScreen), findsOneWidget);
      expect(find.text('Access Denied'), findsOneWidget);
    });

    testWidgets('19. AdminMonthlyReportsScreen renders AdminUnauthorizedScreen for customer session', (tester) async {
      SharedPreferences.setMockInitialValues({
        'user_phone': '9876543210',
        'user_name': 'Customer User',
        'is_onboarded': true,
      });
      final prefs = await SharedPreferences.getInstance();
      final localStorage = LocalStorageService(prefs);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localStorageServiceProvider.overrideWithValue(localStorage),
            shopsProvider.overrideWith((ref) => Future.value([mockShop])),
          ],
          child: const MaterialApp(
            home: AdminMonthlyReportsScreen(initialShopId: 'rajat_shop'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(AdminUnauthorizedScreen), findsOneWidget);
      expect(find.text('Access Denied'), findsOneWidget);
    });

    testWidgets('20. AdminCustomerQueriesScreen renders AdminUnauthorizedScreen for customer session', (tester) async {
      SharedPreferences.setMockInitialValues({
        'user_phone': '9876543210',
        'user_name': 'Customer User',
        'is_onboarded': true,
      });
      final prefs = await SharedPreferences.getInstance();
      final localStorage = LocalStorageService(prefs);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localStorageServiceProvider.overrideWithValue(localStorage),
          ],
          child: const MaterialApp(
            home: AdminCustomerQueriesScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(AdminUnauthorizedScreen), findsOneWidget);
      expect(find.text('Access Denied'), findsOneWidget);
    });
  });

  group('Checkpoint 5.5: Shopkeeper Profile Authorization Tests', () {
    testWidgets('21. ShopkeeperProfileScreen blocks customer phone and displays spinner before redirect', (tester) async {
      SharedPreferences.setMockInitialValues({
        'user_phone': '9876543210',
        'user_name': 'Customer User',
        'is_onboarded': true,
      });
      final prefs = await SharedPreferences.getInstance();
      final localStorage = LocalStorageService(prefs);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localStorageServiceProvider.overrideWithValue(localStorage),
            shopsProvider.overrideWith((ref) => Future.value([mockShop])),
          ],
          child: const MaterialApp(
            home: ShopkeeperProfileScreen(),
          ),
        ),
      );

      // Customer session should NOT render the shopkeeper profile UI
      expect(find.text('Shop Manager'), findsNothing);
      expect(find.text('Logout'), findsNothing);
    });

    testWidgets('22. ShopkeeperProfileScreen renders full profile for valid shopkeeper phone', (tester) async {
      SharedPreferences.setMockInitialValues({
        'user_phone': '8000383993',
        'user_name': 'Rajat Manager',
        'is_onboarded': true,
      });
      final prefs = await SharedPreferences.getInstance();
      final localStorage = LocalStorageService(prefs);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localStorageServiceProvider.overrideWithValue(localStorage),
            shopsProvider.overrideWith((ref) => Future.value([mockShop])),
          ],
          child: const MaterialApp(
            home: ShopkeeperProfileScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Valid shopkeeper session renders profile normally
      expect(find.text('Profile'), findsOneWidget);
      expect(find.text('Logout'), findsOneWidget);
      expect(find.text('+91 8000383993'), findsOneWidget);
    });
  });
}
