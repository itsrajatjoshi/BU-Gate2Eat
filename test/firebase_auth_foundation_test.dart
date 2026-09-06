// BU Gate2Eat — Checkpoint 5.5
// STEP 4: Firebase Auth Foundation Verification Suite
// Tests all 12 required areas:
// 1. FirebaseAuth service initializes.
// 2. No Firebase user initially.
// 3. auth state provider handles signed-out state.
// 4. signOut safely handles no Firebase user.
// 5. Existing local customer login still works.
// 6. Existing shopkeeper login still works.
// 7. Existing admin login still works.
// 8. Customer identity provider remains functional.
// 9. Shopkeeper identity provider remains functional.
// 10. clearCustomerSession remains functional.
// 11. Existing authorization guards remain passing.
// 12. Existing identity isolation remains passing.

import 'package:bugate2eat_app/core/constants/app_constants.dart';
import 'package:bugate2eat_app/core/providers.dart';
import 'package:bugate2eat_app/core/router.dart';
import 'package:bugate2eat_app/features/cart/cart_provider.dart';
import 'package:bugate2eat_app/models/menu_item_model.dart';
import 'package:bugate2eat_app/services/auth_service.dart';
import 'package:bugate2eat_app/services/local_storage_service.dart';
import 'package:bugate2eat_app/services/notification_service.dart';
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
      GoRoute(path: AppRoutes.shopkeeper, builder: (_, __) => const Scaffold(body: Text('Shopkeeper Shell View'))),
    ],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Checkpoint 5.5 Step 4 — Firebase Auth Foundation Tests', () {
    // 1. FirebaseAuth service initializes.
    test('1. AuthService initializes cleanly without throwing', () {
      final authService = AuthService();
      expect(authService, isNotNull);
      expect(authService, isA<AuthService>());
    });

    // 2. No Firebase user initially.
    test('2. No Firebase user initially (currentUser is null, isSignedIn is false)', () {
      final authService = AuthService();
      expect(authService.currentUser, isNull);
      expect(authService.isSignedIn, isFalse);
    });

    // 3. Auth state provider handles signed-out state.
    test('3. authStateChangesProvider and currentFirebaseUserProvider handle signed-out state', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final authService = container.read(authServiceProvider);
      expect(authService, isNotNull);

      // authStateChanges provider should emit null in signed-out state
      final initialUser = await container.read(authStateChangesProvider.future);
      expect(initialUser, isNull);

      // currentFirebaseUserProvider should resolve to null
      final currentUser = container.read(currentFirebaseUserProvider);
      expect(currentUser, isNull);
    });

    // 4. signOut safely handles no Firebase user.
    test('4. signOut safely handles no Firebase user without throwing', () async {
      final authService = AuthService();
      expect(authService.currentUser, isNull);

      // Should complete normally without any exceptions
      await expectLater(authService.signOut(), completes);
    });

    // 4b. Custom token test hook - client does not create custom tokens
    test('4b. signInWithCustomToken throws StateError when uninitialized, enforcing server-minted pattern', () async {
      final authService = AuthService();
      expect(
        () => authService.signInWithCustomToken('dummy_token_123'),
        throwsA(isA<StateError>()),
      );
    });

    // 5. Existing local customer login still works.
    test('5. Existing local customer login still works with normal phone', () async {
      SharedPreferences.setMockInitialValues({
        'user_phone': '9876543210',
        'user_name': 'Test Student',
        'is_onboarded': true,
      });
      final prefs = await SharedPreferences.getInstance();
      final storage = LocalStorageService(prefs);

      expect(storage.isOnboarded, isTrue);
      expect(storage.userPhone, '9876543210');
      expect(storage.userName, 'Test Student');
      expect(AppAuthRoles.isAdminPhone(storage.userPhone), isFalse);
      expect(AppAuthRoles.getShopIdForPhone(storage.userPhone), isNull);
    });

    // 6. Existing shopkeeper login still works.
    test('6. Existing shopkeeper login still works for mapped shop phone', () async {
      const shopPhone = '8000383993'; // Rajat Shop
      SharedPreferences.setMockInitialValues({
        'user_phone': shopPhone,
        'user_name': 'Rajat Vendor',
        'is_onboarded': true,
      });
      final prefs = await SharedPreferences.getInstance();
      final storage = LocalStorageService(prefs);

      final resolvedShopId = AppAuthRoles.getShopIdForPhone(storage.userPhone);
      expect(resolvedShopId, equals('rajat_shop'));

      final container = ProviderContainer(
        overrides: [
          localStorageServiceProvider.overrideWithValue(storage),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(currentShopkeeperShopIdProvider), equals('rajat_shop'));
    });

    // 7. Existing admin login still works.
    test('7. Existing admin login still works for admin phone', () async {
      const adminPhone = AppAuthRoles.adminPhone;
      expect(AppAuthRoles.isAdminPhone(adminPhone), isTrue);

      SharedPreferences.setMockInitialValues({
        'user_phone': adminPhone,
        'user_name': 'Admin User',
        'is_onboarded': true,
      });
      final prefs = await SharedPreferences.getInstance();
      final storage = LocalStorageService(prefs);

      expect(AppAuthRoles.isAdminPhone(storage.userPhone), isTrue);
    });

    // 8. Customer identity provider remains functional.
    test('8. Customer identity provider accurately scopes customerId and updates reactively', () async {
      SharedPreferences.setMockInitialValues({
        'user_phone': '9876543210',
        'user_name': 'John Doe',
        'is_onboarded': true,
      });
      final prefs = await SharedPreferences.getInstance();
      final storage = LocalStorageService(prefs);

      final container = ProviderContainer(
        overrides: [
          localStorageServiceProvider.overrideWithValue(storage),
        ],
      );
      addTearDown(container.dispose);

      final identity = container.read(customerIdentityProvider);
      expect(identity.customerId, equals('cust_9876543210'));
      expect(identity.name, equals('John Doe'));
      expect(identity.phone, equals('9876543210'));

      // Test clear
      container.read(customerIdentityProvider.notifier).clear();
      final cleared = container.read(customerIdentityProvider);
      expect(cleared.customerId, isEmpty);
      expect(cleared.phone, isEmpty);
    });

    // 9. Shopkeeper identity provider remains functional.
    test('9. Shopkeeper identity provider returns null for non-vendor and canonical ID for vendor', () async {
      // Non-vendor
      SharedPreferences.setMockInitialValues({
        'user_phone': '9999999999',
        'user_name': 'Regular User',
        'is_onboarded': true,
      });
      var prefs = await SharedPreferences.getInstance();
      var storage = LocalStorageService(prefs);

      var container = ProviderContainer(
        overrides: [
          localStorageServiceProvider.overrideWithValue(storage),
        ],
      );
      expect(container.read(currentShopkeeperShopIdProvider), isNull);
      container.dispose();

      // Vendor: 8000383993 -> rajat_shop
      SharedPreferences.setMockInitialValues({
        'user_phone': '8000383993',
        'user_name': 'Rajat Vendor',
        'is_onboarded': true,
      });
      prefs = await SharedPreferences.getInstance();
      storage = LocalStorageService(prefs);

      container = ProviderContainer(
        overrides: [
          localStorageServiceProvider.overrideWithValue(storage),
        ],
      );
      expect(container.read(currentShopkeeperShopIdProvider), equals('rajat_shop'));
      container.dispose();
    });

    // 10. clearCustomerSession remains functional.
    test('10. clearCustomerSession purges local session, cart, identity, and calls signOut safely', () async {
      SharedPreferences.setMockInitialValues({
        'user_phone': '9876543210',
        'user_name': 'Active Student',
        'customer_id': 'cust_9876543210',
        'is_onboarded': true,
      });
      final prefs = await SharedPreferences.getInstance();
      final storage = LocalStorageService(prefs);

      final container = ProviderContainer(
        overrides: [
          localStorageServiceProvider.overrideWithValue(storage),
          notificationServiceProvider.overrideWithValue(NotificationService()),
        ],
      );
      addTearDown(container.dispose);

      // Add item to cart
      const testItem = MenuItem(
        id: 'm1',
        name: 'Burger',
        details: 'Tasty burger',
        price: 50,
        imageUrl: '',
        categoryId: 'cat_fast_food',
        isVeg: true,
        isAvailable: true,
        isRecommended: false,
        sortOrder: 1,
      );

      container.read(cartProvider.notifier).addItem(
            testItem,
            'rajat_shop',
            'Rajat Shop',
          );
      expect(container.read(cartProvider).items, isNotEmpty);

      // Perform clearCustomerSession
      await clearCustomerSession(container);

      // Verify cart cleared
      expect(container.read(cartProvider).items, isEmpty);

      // Verify customer identity cleared
      final identity = container.read(customerIdentityProvider);
      expect(identity.customerId, isEmpty);
      expect(identity.phone, isEmpty);

      // Verify localStorage logged out
      expect(storage.isOnboarded, isFalse);
      expect(storage.userPhone, isEmpty);
    });

    // 11. Existing authorization guards remain passing.
    testWidgets('11. Central route guard redirects unauthenticated customer attempting /admin to /home', (tester) async {
      SharedPreferences.setMockInitialValues({
        'user_phone': '9876543210', // non-admin
        'user_name': 'Customer User',
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

    // 12. Existing identity isolation remains passing.
    test('12. Independent ProviderContainers maintain completely isolated customer identities', () async {
      SharedPreferences.setMockInitialValues({
        'user_phone': '9111111111',
        'user_name': 'Alpha',
        'is_onboarded': true,
      });
      final prefsA = await SharedPreferences.getInstance();
      final storageA = LocalStorageService(prefsA);

      final containerA = ProviderContainer(
        overrides: [
          localStorageServiceProvider.overrideWithValue(storageA),
        ],
      );
      addTearDown(containerA.dispose);

      SharedPreferences.setMockInitialValues({
        'user_phone': '9222222222',
        'user_name': 'Beta',
        'is_onboarded': true,
      });
      final prefsB = await SharedPreferences.getInstance();
      final storageB = LocalStorageService(prefsB);

      final containerB = ProviderContainer(
        overrides: [
          localStorageServiceProvider.overrideWithValue(storageB),
        ],
      );
      addTearDown(containerB.dispose);

      final identityA = containerA.read(customerIdentityProvider);
      final identityB = containerB.read(customerIdentityProvider);

      expect(identityA.customerId, equals('cust_9111111111'));
      expect(identityB.customerId, equals('cust_9222222222'));
      expect(identityA.customerId, isNot(equals(identityB.customerId)));
    });
  });
}
