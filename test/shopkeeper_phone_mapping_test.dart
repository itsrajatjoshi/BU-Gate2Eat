// BU Gate2Eat — Test Suite
// Checkpoint 1B: Shopkeeper Phone to Shop Mapping Unification Test

import 'package:bugate2eat_app/core/constants/app_constants.dart';
import 'package:bugate2eat_app/core/providers.dart';
import 'package:bugate2eat_app/models/order_model.dart';
import 'package:bugate2eat_app/models/shop_model.dart';
import 'package:bugate2eat_app/panel/shopkeeper_panel/shopkeeper_main_shell.dart';
import 'package:bugate2eat_app/core/router.dart';
import 'package:bugate2eat_app/services/local_storage_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Checkpoint 1B — Central AppAuthRoles Phone-to-Shop Mapping Resolver', () {
    test('1. Resolves registered shopkeeper phones to correct shop IDs', () {
      expect(AppAuthRoles.getShopIdForPhone('8000383993'), 'rajat_shop');
      expect(AppAuthRoles.getShopIdForPhone('+91 8000383993'), 'rajat_shop');
      expect(AppAuthRoles.getShopIdForPhone('08000383993'), 'rajat_shop');

      expect(AppAuthRoles.getShopIdForPhone('8295643910'), 'nayan_shop');
      expect(AppAuthRoles.getShopIdForPhone('+91 8295643910'), 'nayan_shop');

      expect(AppAuthRoles.getShopIdForPhone('8875344034'), 'kivisha_shop');
      expect(AppAuthRoles.getShopIdForPhone('+918875344034'), 'kivisha_shop');

      expect(AppAuthRoles.getShopIdForPhone('8079065843'), 'up16_junction_fast_food');
      expect(AppAuthRoles.getShopIdForPhone('8745007244'), 'up16_junction_fast_food');
      expect(AppAuthRoles.getShopIdForPhone('8745950335'), 'up16_junction_fast_food');

      expect(AppAuthRoles.getShopIdForPhone('8888822222'), 'raja_hotel');
      expect(AppAuthRoles.getShopIdForPhone('9999922222'), 'up16_coffee_queen');
    });

    test('2. Returns null for unknown / unregistered phone numbers', () {
      expect(AppAuthRoles.getShopIdForPhone('9999999999'), isNull);
      expect(AppAuthRoles.getShopIdForPhone('9876543210'), isNull);
      expect(AppAuthRoles.getShopIdForPhone(''), isNull);
      expect(AppAuthRoles.getShopIdForPhone('8078643910'), isNull); // Admin phone has no shop
    });
  });

  group('Checkpoint 1B — currentShopkeeperShopIdProvider resolution via LocalStorage', () {
    test('1. Resolves shopId from logged-in LocalStorage phone', () async {
      SharedPreferences.setMockInitialValues({
        'user_phone': '8000383993',
        'user_name': 'Rajat Shopkeeper',
      });
      final prefs = await SharedPreferences.getInstance();
      final localStorage = LocalStorageService(prefs);

      final container = ProviderContainer(
        overrides: [
          localStorageServiceProvider.overrideWithValue(localStorage),
        ],
      );

      expect(container.read(currentShopkeeperShopIdProvider), 'rajat_shop');
    });

    test('2. Returns null when LocalStorage phone is unknown', () async {
      SharedPreferences.setMockInitialValues({
        'user_phone': '9999999999',
        'user_name': 'Unknown Person',
      });
      final prefs = await SharedPreferences.getInstance();
      final localStorage = LocalStorageService(prefs);

      final container = ProviderContainer(
        overrides: [
          localStorageServiceProvider.overrideWithValue(localStorage),
        ],
      );

      expect(container.read(currentShopkeeperShopIdProvider), isNull);
    });
  });

  group('Checkpoint 1B — ShopkeeperMainShell UI Behavior', () {
    testWidgets('1. Shows active shopkeeper tabs when valid phone is logged in', (tester) async {
      SharedPreferences.setMockInitialValues({
        'user_phone': '8295643910',
        'user_name': 'Rajat Shopkeeper',
      });
      final prefs = await SharedPreferences.getInstance();
      final localStorage = LocalStorageService(prefs);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localStorageServiceProvider.overrideWithValue(localStorage),
            shopActiveOrdersStreamProvider.overrideWith((ref, shopId) => Stream.value(<AppOrder>[])),
            shopOrderHistoryStreamProvider.overrideWith((ref, shopId) => Stream.value(<AppOrder>[])),
            shopsProvider.overrideWith((ref) async => <Shop>[]),
          ],
          child: const MaterialApp(
            home: ShopkeeperMainShell(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.byType(BottomNavigationBar), findsOneWidget);
      expect(find.text('Orders'), findsWidgets);
      expect(find.text('Order History'), findsOneWidget);
      expect(find.text('Shop'), findsOneWidget);
      expect(find.text('No Shop Assigned'), findsNothing);
    });

    testWidgets('2. Shows safe unauthorized view when unregistered phone is logged in', (tester) async {
      SharedPreferences.setMockInitialValues({
        'user_phone': '9999999999',
        'user_name': 'Random Stranger',
      });
      final prefs = await SharedPreferences.getInstance();
      final localStorage = LocalStorageService(prefs);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localStorageServiceProvider.overrideWithValue(localStorage),
          ],
          child: const MaterialApp(
            home: ShopkeeperMainShell(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('No Shop Assigned'), findsOneWidget);
      expect(find.textContaining('9999999999'), findsOneWidget);
      expect(find.text('Return to Login'), findsOneWidget);
      expect(find.byType(BottomNavigationBar), findsNothing);
    });
  });

  group('S-003 Step 5 — Sequential Multi-Shop Login & Reactive Resolution Suite', () {
    test('Sequential logins: A -> logout -> B -> logout -> C -> logout -> D correctly resolves each shopId reactively', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final localStorage = LocalStorageService(prefs);

      final container = ProviderContainer(
        overrides: [
          localStorageServiceProvider.overrideWithValue(localStorage),
        ],
      );

      final mappings = [
        {'phone': '8000383993', 'shopId': 'rajat_shop'},
        {'phone': '8295643910', 'shopId': 'nayan_shop'},
        {'phone': '8875344034', 'shopId': 'kivisha_shop'},
        {'phone': '8079065843', 'shopId': 'up16_junction_fast_food'},
        {'phone': '8745007244', 'shopId': 'up16_junction_fast_food'},
        {'phone': '8745950335', 'shopId': 'up16_junction_fast_food'},
        {'phone': '8888822222', 'shopId': 'raja_hotel'},
        {'phone': '9999922222', 'shopId': 'up16_coffee_queen'},
      ];

      for (final item in mappings) {
        final phone = item['phone']!;
        final expectedShopId = item['shopId']!;

        // 1. Login as this shopkeeper
        await localStorage.saveUserProfile(name: 'Manager', phone: phone);
        container.read(customerIdentityProvider.notifier).refresh();
        container.invalidate(currentShopkeeperShopIdProvider);

        expect(
          container.read(currentShopkeeperShopIdProvider),
          equals(expectedShopId),
          reason: 'Phone $phone should resolve to $expectedShopId',
        );

        // 2. Logout
        await localStorage.logout();
        container.read(customerIdentityProvider.notifier).clear();
        container.invalidate(currentShopkeeperShopIdProvider);

        expect(
          container.read(currentShopkeeperShopIdProvider),
          isNull,
          reason: 'Logged out session should resolve to null',
        );
      }
    });

    testWidgets('Unauthorized-view recovery: Return to Login resets session and permits next valid shop login', (tester) async {
      SharedPreferences.setMockInitialValues({
        'user_phone': '9999999999',
        'user_name': 'Unknown Person',
      });
      final prefs = await SharedPreferences.getInstance();
      final localStorage = LocalStorageService(prefs);

      final container = ProviderContainer(
        overrides: [
          localStorageServiceProvider.overrideWithValue(localStorage),
          shopActiveOrdersStreamProvider.overrideWith((ref, shopId) => Stream.value(<AppOrder>[])),
          shopOrderHistoryStreamProvider.overrideWith((ref, shopId) => Stream.value(<AppOrder>[])),
          shopsProvider.overrideWith((ref) async => <Shop>[]),
        ],
      );

      final router = GoRouter(
        initialLocation: AppRoutes.shopkeeper,
        routes: [
          GoRoute(
            path: AppRoutes.shopkeeper,
            builder: (context, state) => const ShopkeeperMainShell(),
          ),
          GoRoute(
            path: AppRoutes.onboarding,
            builder: (context, state) => const Scaffold(body: Text('Onboarding Screen')),
          ),
        ],
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Unauthorized screen is visible
      expect(find.text('No Shop Assigned'), findsOneWidget);
      expect(find.text('Return to Login'), findsOneWidget);

      // Tap Return to Login
      await tester.tap(find.text('Return to Login'));
      await tester.pumpAndSettle();

      // Successfully navigated to Onboarding Screen
      expect(find.text('Onboarding Screen'), findsOneWidget);

      // Session was cleared
      expect(localStorage.userPhone, isEmpty);
      expect(container.read(currentShopkeeperShopIdProvider), isNull);

      // Now log in as Nayan Shop
      await localStorage.saveUserProfile(name: 'Nayan Mgr', phone: '8295643910');
      container.read(customerIdentityProvider.notifier).refresh();
      container.invalidate(currentShopkeeperShopIdProvider);

      // Verify immediate resolution to nayan_shop
      expect(container.read(currentShopkeeperShopIdProvider), equals('nayan_shop'));

      // Navigate back to shopkeeper shell
      router.go(AppRoutes.shopkeeper);
      await tester.pumpAndSettle();

      // Should now render active tabs, NOT No Shop Assigned
      expect(find.text('No Shop Assigned'), findsNothing);
      expect(find.byType(BottomNavigationBar), findsOneWidget);
      expect(find.text('Orders'), findsWidgets);
    });
  });
}
