// BU Gate2Eat — Release vs Debug Privileged Authorization Security Test Suite
//
// Formally verifies:
// 1. Debug mode: Admin phone allows /admin panel access
// 2. Debug mode: Shopkeeper phone allows /shopkeeper panel access
// 3. Debug mode: Customer phone is denied /admin and /shopkeeper
// 4. Release mode: Admin phone WITHOUT authenticated trusted claims is strictly DENIED
// 5. Release mode: Shopkeeper phone WITHOUT authenticated trusted claims is strictly DENIED
// 6. Release mode: SharedPreferences / LocalStorage tampering CANNOT authorize privileged access
// 7. Release mode: Authenticated Firebase Auth user with admin custom claim is ALLOWED
// 8. Release mode: Authenticated Firebase Auth user with shopkeeper custom claim is ALLOWED
// 9. Release mode: Deep-link / direct route to /admin fails closed without trusted claim
// 10. Release mode: Deep-link / direct route to /shopkeeper fails closed without trusted claim

import 'package:bugate2eat_app/core/constants/app_constants.dart';
import 'package:bugate2eat_app/core/providers.dart';
import 'package:bugate2eat_app/core/router.dart';
import 'package:bugate2eat_app/models/shop_model.dart';
import 'package:bugate2eat_app/panel/admin_panel/widgets/admin_unauthorized_screen.dart';
import 'package:bugate2eat_app/services/auth_service.dart';
import 'package:bugate2eat_app/services/firestore_service.dart';
import 'package:bugate2eat_app/services/local_storage_service.dart';
import 'package:bugate2eat_app/services/shop_stats_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeReleaseUser implements User {
  _FakeReleaseUser({required this.uid, this.phoneNumber});
  @override
  final String uid;
  @override
  final String? phoneNumber;

  @override
  String? get displayName => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

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

  setUp(() {
    AppAuthRoles.overrideAllowPhoneFallbackForTesting = null;
  });

  tearDown(() {
    AppAuthRoles.overrideAllowPhoneFallbackForTesting = null;
  });

  final sampleShop = Shop.fromMap({
    'name': 'Admin Created Shop',
    'description': 'New shop created by admin',
    'bannerUrl': 'https://example.com/banner.jpg',
    'shopLogoImageUrl': 'https://example.com/logo.jpg',
    'openTime': '09:00',
    'closeTime': '22:00',
    'isClosedOverride': false,
    'isActive': true,
  }, 'test_shop_id');

  group('Debug Mode Privileged Authorization (Fallback Enabled)', () {
    test('1. Debug admin phone -> panel allowed', () {
      AppAuthRoles.overrideAllowPhoneFallbackForTesting = true;
      expect(AppAuthRoles.isPhoneFallbackAllowed, isTrue);
      expect(AppAuthRoles.isAdminPhone('8078643910'), isTrue);
    });

    test('2. Debug shopkeeper phone -> panel allowed', () {
      AppAuthRoles.overrideAllowPhoneFallbackForTesting = true;
      expect(AppAuthRoles.isPhoneFallbackAllowed, isTrue);
      expect(AppAuthRoles.isShopkeeperPhone('8000383993'), isTrue);
      expect(AppAuthRoles.getShopIdForPhone('8000383993'), equals('rajat_shop'));
    });

    test('3. Debug customer phone -> denied admin and shopkeeper', () {
      AppAuthRoles.overrideAllowPhoneFallbackForTesting = true;
      expect(AppAuthRoles.isAdminPhone('9876543210'), isFalse);
      expect(AppAuthRoles.isShopkeeperPhone('9876543210'), isFalse);
      expect(AppAuthRoles.getShopIdForPhone('9876543210'), isNull);
    });

    testWidgets('4. Debug mode: Admin phone routes to /admin shell', (tester) async {
      AppAuthRoles.overrideAllowPhoneFallbackForTesting = true;
      SharedPreferences.setMockInitialValues({
        'user_phone': '8078643910',
        'is_onboarded': true,
      });
      final prefs = await SharedPreferences.getInstance();
      final storage = LocalStorageService(prefs);

      final router = _buildTestRouter();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localStorageServiceProvider.overrideWithValue(storage),
            currentIdentityProvider.overrideWithValue(CurrentIdentity.unauthenticated),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      router.go(AppRoutes.admin);
      await tester.pumpAndSettle();

      expect(find.text('Admin Shell View'), findsOneWidget);
    });

    testWidgets('5. Debug mode: Shopkeeper phone routes to /shopkeeper shell', (tester) async {
      AppAuthRoles.overrideAllowPhoneFallbackForTesting = true;
      SharedPreferences.setMockInitialValues({
        'user_phone': '8000383993',
        'is_onboarded': true,
      });
      final prefs = await SharedPreferences.getInstance();
      final storage = LocalStorageService(prefs);

      final router = _buildTestRouter();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localStorageServiceProvider.overrideWithValue(storage),
            currentIdentityProvider.overrideWithValue(CurrentIdentity.unauthenticated),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      router.go(AppRoutes.shopkeeper);
      await tester.pumpAndSettle();

      expect(find.text('Shopkeeper Shell View'), findsOneWidget);
    });
  });

  group('Release Mode Privileged Authorization Invariant (Fallback Disabled)', () {
    test('6. Release mode: AppAuthRoles.isPhoneFallbackAllowed is false', () {
      AppAuthRoles.overrideAllowPhoneFallbackForTesting = false;
      expect(AppAuthRoles.isPhoneFallbackAllowed, isFalse);
    });

    testWidgets('7. Release admin phone without authenticated trusted identity -> denied /admin', (tester) async {
      AppAuthRoles.overrideAllowPhoneFallbackForTesting = false;
      SharedPreferences.setMockInitialValues({
        'user_phone': '8078643910',
        'is_onboarded': true,
        'user_role': 'admin',
      });
      final prefs = await SharedPreferences.getInstance();
      final storage = LocalStorageService(prefs);

      final router = _buildTestRouter();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localStorageServiceProvider.overrideWithValue(storage),
            currentIdentityProvider.overrideWithValue(CurrentIdentity.unauthenticated),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      // Deep link / direct access attempt to /admin
      router.go(AppRoutes.admin);
      await tester.pumpAndSettle();

      // STRICT INVARIANT: Admin shell is NOT shown; redirected to customer home!
      expect(find.text('Admin Shell View'), findsNothing);
      expect(find.text('Customer Home View'), findsOneWidget);

      // Verify isAdminAuthorized returns false in release mode
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localStorageServiceProvider.overrideWithValue(storage),
            currentIdentityProvider.overrideWithValue(CurrentIdentity.unauthenticated),
          ],
          child: Consumer(
            builder: (context, ref, _) {
              final authorized = isAdminAuthorized(ref);
              expect(authorized, isFalse);
              return Container();
            },
          ),
        ),
      );
    });

    testWidgets('8. Release shopkeeper phone without authenticated trusted identity -> denied /shopkeeper', (tester) async {
      AppAuthRoles.overrideAllowPhoneFallbackForTesting = false;
      SharedPreferences.setMockInitialValues({
        'user_phone': '8000383993',
        'is_onboarded': true,
        'user_role': 'shopkeeper',
      });
      final prefs = await SharedPreferences.getInstance();
      final storage = LocalStorageService(prefs);

      final router = _buildTestRouter();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localStorageServiceProvider.overrideWithValue(storage),
            currentIdentityProvider.overrideWithValue(CurrentIdentity.unauthenticated),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      // Deep link / direct access attempt to /shopkeeper
      router.go(AppRoutes.shopkeeper);
      await tester.pumpAndSettle();

      // STRICT INVARIANT: Shopkeeper shell is NOT shown; redirected to customer home!
      expect(find.text('Shopkeeper Shell View'), findsNothing);
      expect(find.text('Customer Home View'), findsOneWidget);

      // Verify currentShopkeeperShopIdProvider resolves to null
      final container = ProviderContainer(
        overrides: [
          localStorageServiceProvider.overrideWithValue(storage),
          currentIdentityProvider.overrideWithValue(CurrentIdentity.unauthenticated),
        ],
      );
      expect(container.read(currentShopkeeperShopIdProvider), isNull);
    });

    testWidgets('9. Release mode: Local storage tampering CANNOT authorize privileged access', (tester) async {
      AppAuthRoles.overrideAllowPhoneFallbackForTesting = false;
      // An attacker attempts to set admin phone, is_admin: true, and user_role: admin in SharedPreferences
      SharedPreferences.setMockInitialValues({
        'user_phone': '8078643910',
        'is_admin': true,
        'user_role': 'admin',
        'is_onboarded': true,
      });
      final prefs = await SharedPreferences.getInstance();
      final storage = LocalStorageService(prefs);

      final container = ProviderContainer(
        overrides: [
          localStorageServiceProvider.overrideWithValue(storage),
          currentIdentityProvider.overrideWithValue(CurrentIdentity.unauthenticated),
        ],
      );

      // Tampered values MUST NOT resolve privileged operations in services
      final firestoreService = container.read(firestoreServiceProvider);
      expect(
        () => firestoreService.createShop(sampleShop),
        throwsA(isA<FirestoreServiceException>().having(
          (e) => e.message,
          'message',
          contains('Unauthorized: Only administrators can create new shops'),
        )),
      );

      final statsServ = container.read(shopStatsServiceProvider);
      expect(
        () => statsServ.resetShopStats('test_shop'),
        throwsA(isA<ShopStatsServiceException>()),
      );

      // Support queries stream MUST fail closed to empty
      final queriesStream = container.read(supportQueriesStreamProvider);
      expect(queriesStream.asData?.value ?? [], isEmpty);
    });

    testWidgets('10. Release mode: Authenticated Firebase user with admin claim is ALLOWED', (tester) async {
      AppAuthRoles.overrideAllowPhoneFallbackForTesting = false;
      final user = _FakeReleaseUser(uid: 'admin_uid_777', phoneNumber: '+918078643910');
      final adminIdentity = AuthService.mapUserToIdentity(user, {'role': 'admin'});

      final router = _buildTestRouter();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentIdentityProvider.overrideWithValue(adminIdentity),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      router.go(AppRoutes.admin);
      await tester.pumpAndSettle();

      expect(find.text('Admin Shell View'), findsOneWidget);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentIdentityProvider.overrideWithValue(adminIdentity),
          ],
          child: Consumer(
            builder: (context, ref, _) {
              expect(isAdminAuthorized(ref), isTrue);
              return Container();
            },
          ),
        ),
      );
    });

    testWidgets('11. Release mode: Authenticated Firebase user with shopkeeper claim is ALLOWED', (tester) async {
      AppAuthRoles.overrideAllowPhoneFallbackForTesting = false;
      final user = _FakeReleaseUser(uid: 'shopkeeper_uid_999', phoneNumber: '+918000383993');
      final shopkeeperIdentity = AuthService.mapUserToIdentity(user, {
        'role': 'shopkeeper',
        'shopId': 'rajat_shop',
      });

      final router = _buildTestRouter();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentIdentityProvider.overrideWithValue(shopkeeperIdentity),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      router.go(AppRoutes.shopkeeper);
      await tester.pumpAndSettle();

      expect(find.text('Shopkeeper Shell View'), findsOneWidget);

      final container = ProviderContainer(
        overrides: [
          currentIdentityProvider.overrideWithValue(shopkeeperIdentity),
        ],
      );
      expect(container.read(currentShopkeeperShopIdProvider), equals('rajat_shop'));
    });
  });
}
