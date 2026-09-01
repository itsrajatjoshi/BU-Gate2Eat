// BU Gate2Eat — Test Suite
// Checkpoint 1B: Shopkeeper Phone to Shop Mapping Unification Test

import 'package:bugate2eat_app/core/constants/app_constants.dart';
import 'package:bugate2eat_app/core/providers.dart';
import 'package:bugate2eat_app/models/order_model.dart';
import 'package:bugate2eat_app/models/shop_model.dart';
import 'package:bugate2eat_app/panel/shopkeeper_panel/shopkeeper_main_shell.dart';
import 'package:bugate2eat_app/services/local_storage_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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
      expect(AppAuthRoles.getShopIdForPhone('9999922222'), 'up16_queens');
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
}
