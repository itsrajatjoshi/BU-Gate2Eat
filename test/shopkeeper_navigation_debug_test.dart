import 'package:bugate2eat_app/core/providers.dart';
import 'package:bugate2eat_app/core/router.dart';
import 'package:bugate2eat_app/models/order_model.dart';
import 'package:bugate2eat_app/models/shop_model.dart';
import 'package:bugate2eat_app/panel/shopkeeper_panel/shopkeeper_main_shell.dart';
import 'package:bugate2eat_app/panel/shopkeeper_panel/shopkeeper_profile_screen.dart';
import 'package:bugate2eat_app/services/local_storage_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Shopkeeper S-001 Navigation Tests', () {
    testWidgets('1. Bottom tab switching & Android system back returns to Orders tab', (tester) async {
      SharedPreferences.setMockInitialValues({
        'user_phone': '8000383993',
        'user_name': 'Rajat Shopkeeper',
        'is_onboarded': true,
      });
      final prefs = await SharedPreferences.getInstance();
      final localStorage = LocalStorageService(prefs);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localStorageServiceProvider.overrideWithValue(localStorage),
            shopActiveOrdersStreamProvider.overrideWith(
              (ref, shopId) => Stream.value(<AppOrder>[]),
            ),
            shopOrderHistoryStreamProvider.overrideWith(
              (ref, shopId) => Stream.value(<AppOrder>[]),
            ),
            shopsProvider.overrideWith((ref) async => <Shop>[]),
          ],
          child: MaterialApp.router(
            routerConfig: appRouter,
          ),
        ),
      );
      await tester.pumpAndSettle();

      appRouter.go(AppRoutes.shopkeeper);
      await tester.pumpAndSettle();

      // Starts on Orders tab (index 0)
      expect(find.byType(ShopkeeperMainShell), findsOneWidget);
      var navBar = tester.widget<BottomNavigationBar>(find.byType(BottomNavigationBar));
      expect(navBar.currentIndex, equals(0));

      // Switch to Order History tab (index 1)
      await tester.tap(find.text('Order History'));
      await tester.pumpAndSettle();
      navBar = tester.widget<BottomNavigationBar>(find.byType(BottomNavigationBar));
      expect(navBar.currentIndex, equals(1));

      // Android back from Order History returns to Orders tab (index 0)
      var didPop = await tester.binding.handlePopRoute();
      expect(didPop, isTrue);
      await tester.pumpAndSettle();
      navBar = tester.widget<BottomNavigationBar>(find.byType(BottomNavigationBar));
      expect(navBar.currentIndex, equals(0));

      // Switch to Shop tab (index 2)
      await tester.tap(find.text('Shop'));
      await tester.pumpAndSettle();
      navBar = tester.widget<BottomNavigationBar>(find.byType(BottomNavigationBar));
      expect(navBar.currentIndex, equals(2));

      // Android back from Shop returns to Orders tab (index 0)
      didPop = await tester.binding.handlePopRoute();
      expect(didPop, isTrue);
      await tester.pumpAndSettle();
      navBar = tester.widget<BottomNavigationBar>(find.byType(BottomNavigationBar));
      expect(navBar.currentIndex, equals(0));

      // On Orders tab (index 0), system back allows app to exit
      didPop = await tester.binding.handlePopRoute();
      expect(didPop, isFalse);
    });

    testWidgets('2. Profile avatar navigation to ShopkeeperProfileScreen and back', (tester) async {
      SharedPreferences.setMockInitialValues({
        'user_phone': '8000383993',
        'user_name': 'Rajat Shopkeeper',
        'is_onboarded': true,
      });
      final prefs = await SharedPreferences.getInstance();
      final localStorage = LocalStorageService(prefs);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localStorageServiceProvider.overrideWithValue(localStorage),
            shopActiveOrdersStreamProvider.overrideWith(
              (ref, shopId) => Stream.value(<AppOrder>[]),
            ),
            shopOrderHistoryStreamProvider.overrideWith(
              (ref, shopId) => Stream.value(<AppOrder>[]),
            ),
            shopsProvider.overrideWith((ref) async => <Shop>[]),
          ],
          child: MaterialApp.router(
            routerConfig: appRouter,
          ),
        ),
      );
      await tester.pumpAndSettle();

      appRouter.go(AppRoutes.shopkeeper);
      await tester.pumpAndSettle();

      // Tap profile avatar in Orders AppBar
      final inkWellFinder = find.byWidgetPredicate(
        (widget) => widget is InkWell && widget.child is Container,
      );
      expect(inkWellFinder, findsWidgets);
      await tester.tap(inkWellFinder.first);
      await tester.pumpAndSettle();

      expect(find.byType(ShopkeeperProfileScreen), findsOneWidget);

      // Back button in AppBar returns to ShopkeeperMainShell
      final backButton = find.byType(BackButton);
      expect(backButton, findsOneWidget);
      await tester.tap(backButton);
      await tester.pumpAndSettle();

      expect(find.byType(ShopkeeperMainShell), findsOneWidget);
    });
  });
}
