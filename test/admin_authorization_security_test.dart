// BU Gate2Eat — Checkpoint 2.5: Admin Authorization Security Test Suite
//
// Verifies all 30 required security invariants:
// 1. Valid admin resolves as admin
// 2. Admin claims contain role only
// 3. Admin shopId remains null/absent
// 4. Customer cannot access /admin
// 5. Shopkeeper cannot access /admin
// 6. Anonymous user cannot access /admin
// 7. LocalStorage admin flag cannot elevate customer
// 8. LocalStorage admin flag cannot elevate shopkeeper
// 9. LocalStorage phone cannot elevate customer
// 10. LocalStorage phone cannot elevate shopkeeper
// 11. Customer cannot inject admin role
// 12. Shopkeeper cannot inject admin role
// 13. Customer cannot invoke admin-only service
// 14. Shopkeeper cannot invoke admin-only service
// 15. Anonymous cannot invoke admin-only service
// 16. Shopkeeper cannot execute stats reset
// 17. Customer cannot execute stats reset
// 18. Anonymous cannot execute stats reset
// 19. Only admin can reset shop stats
// 20. Only admin can reset monthly stats
// 21. Only admin can perform full shop reset
// 22. Only admin can delete terminal shop orders
// 23. Admin route remains protected after identity tampering
// 24. Admin identity remains UID-based/authenticated
// 25. Admin access remains platform-wide where explicitly intended
// 26. Shopkeeper tenant isolation remains intact
// 27. Customer isolation remains intact
// 28. Admin cannot be created by client payload
// 29. Admin cannot be created by route/query manipulation
// 30. Deactivated admin loses effective admin access after token/claim refresh

import 'package:bugate2eat_app/core/providers.dart';
import 'package:bugate2eat_app/core/router.dart';
import 'package:bugate2eat_app/models/shop_model.dart';
import 'package:bugate2eat_app/services/auth_service.dart';
import 'package:bugate2eat_app/services/firestore_service.dart';
import 'package:bugate2eat_app/services/order_service.dart';
import 'package:bugate2eat_app/services/shop_stats_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Fake Firebase User for deterministic offline identity tests.
class _FakeFirebaseUser implements User {
  _FakeFirebaseUser({
    required this.uid,
    this.phoneNumber,
  });

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
      GoRoute(path: '${AppRoutes.admin}/stats/:shopId', builder: (_, __) => const Scaffold(body: Text('Admin Stats View'))),
      GoRoute(path: AppRoutes.shopkeeper, builder: (_, __) => const Scaffold(body: Text('Shopkeeper Shell View'))),
    ],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
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
  }, 'test_shop_id',);

  group('Checkpoint 2.5 — Admin Authorization Security Suite', () {
    // ─── 1. Valid admin resolves as admin ─────────────────────────────────────
    test('1. Valid admin resolves as admin: Custom Claims {role: "admin"} yields AuthRole.admin and isAdmin == true', () {
      final user = _FakeFirebaseUser(uid: 'admin_uid_001', phoneNumber: '+918078643910');
      final claims = <String, dynamic>{'role': 'admin'};

      final identity = AuthService.mapUserToIdentity(user, claims);
      expect(identity.uid, equals('admin_uid_001'));
      expect(identity.role, equals(AuthRole.admin));
      expect(identity.isAdmin, isTrue);
      expect(identity.isCustomer, isFalse);
      expect(identity.isShopkeeper, isFalse);
      expect(identity.authStatus, equals(AuthStatus.authenticated));
    });

    // ─── 2. Admin claims contain role only ────────────────────────────────────
    test('2. Admin claims contain role only: Canonical admin claims strictly contain role without shopId or customerId', () {
      final user = _FakeFirebaseUser(uid: 'admin_uid_002', phoneNumber: '+918078643910');
      // Canonical admin claims contain role only
      final claims = <String, dynamic>{'role': 'admin'};

      expect(claims.keys.length, equals(1));
      expect(claims['role'], equals('admin'));
      expect(claims.containsKey('shopId'), isFalse);
      expect(claims.containsKey('customerId'), isFalse);
      expect(claims.containsKey('isAdmin'), isFalse);
      expect(claims.containsKey('phone'), isFalse);

      final identity = AuthService.mapUserToIdentity(user, claims);
      expect(identity.role, equals(AuthRole.admin));
      expect(identity.shopId, isNull);
    });

    // ─── 3. Admin shopId remains null/absent ──────────────────────────────────
    test('3. Admin shopId remains null/absent: Even if client or claims contain shopId, admin identity keeps shopId null', () {
      final user = _FakeFirebaseUser(uid: 'admin_uid_003', phoneNumber: '+918078643910');
      // Malicious or accidental shopId injected into admin claims
      final claims = <String, dynamic>{'role': 'admin', 'shopId': 'shop_spoof_attempt'};

      final identity = AuthService.mapUserToIdentity(user, claims);
      expect(identity.role, equals(AuthRole.admin));
      expect(identity.shopId, isNull);
    });

    // ─── 4. Customer cannot access /admin ─────────────────────────────────────
    testWidgets('4. Customer cannot access /admin: Redirected to home', (tester) async {
      const customerIdentity = CurrentIdentity(
        uid: 'cust_uid_004',
        phone: '9876543210',
        authStatus: AuthStatus.authenticated,
        role: AuthRole.customer,
        customerId: 'cust_uid_004',
      );

      final router = _buildTestRouter();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentIdentityProvider.overrideWithValue(customerIdentity),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      router.go(AppRoutes.admin);
      await tester.pumpAndSettle();

      expect(find.text('Admin Shell View'), findsNothing);
      expect(find.text('Customer Home View'), findsOneWidget);
    });

    // ─── 5. Shopkeeper cannot access /admin ───────────────────────────────────
    testWidgets('5. Shopkeeper cannot access /admin: Redirected to home', (tester) async {
      const shopkeeperIdentity = CurrentIdentity(
        uid: 'shop_uid_005',
        phone: '8000383993',
        authStatus: AuthStatus.authenticated,
        role: AuthRole.shopkeeper,
        customerId: 'shop_uid_005',
        shopId: 'shop_a',
      );

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

      router.go(AppRoutes.admin);
      await tester.pumpAndSettle();

      expect(find.text('Admin Shell View'), findsNothing);
      expect(find.text('Customer Home View'), findsOneWidget);
    });

    // ─── 6. Anonymous user cannot access /admin ───────────────────────────────
    testWidgets('6. Anonymous user cannot access /admin: Fails closed and redirects to onboarding', (tester) async {
      const anonymousIdentity = CurrentIdentity.unauthenticated;

      final router = _buildTestRouter(initialLocation: AppRoutes.splash);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentIdentityProvider.overrideWithValue(anonymousIdentity),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      router.go(AppRoutes.admin);
      await tester.pumpAndSettle();

      expect(find.text('Admin Shell View'), findsNothing);
      expect(find.text('Onboarding View'), findsOneWidget);
    });

    // ─── 7. LocalStorage admin flag cannot elevate customer ───────────────────
    test('7. LocalStorage admin flag cannot elevate customer: SharedPreferences role tampering is ignored', () async {
      await prefs.setString('userRole', 'admin');
      await prefs.setBool('isAdmin', true);
      await prefs.setString('phone', '8078643910');

      final user = _FakeFirebaseUser(uid: 'cust_uid_007', phoneNumber: '+919876543210');
      final claims = <String, dynamic>{'role': 'customer'};

      final identity = AuthService.mapUserToIdentity(user, claims);
      expect(identity.role, equals(AuthRole.customer));
      expect(identity.isAdmin, isFalse);
    });

    // ─── 8. LocalStorage admin flag cannot elevate shopkeeper ─────────────────
    test('8. LocalStorage admin flag cannot elevate shopkeeper: SharedPreferences role tampering is ignored', () async {
      await prefs.setString('userRole', 'admin');
      await prefs.setBool('isAdmin', true);
      await prefs.setString('phone', '8078643910');

      final user = _FakeFirebaseUser(uid: 'shop_uid_008', phoneNumber: '+918000383993');
      final claims = <String, dynamic>{'role': 'shopkeeper', 'shopId': 'shop_a'};

      final identity = AuthService.mapUserToIdentity(user, claims);
      expect(identity.role, equals(AuthRole.shopkeeper));
      expect(identity.isAdmin, isFalse);
      expect(identity.shopId, equals('shop_a'));
    });

    // ─── 9. LocalStorage phone cannot elevate customer ────────────────────────
    test('9. LocalStorage phone cannot elevate customer: Setting admin phone locally leaves customer as customer', () async {
      await prefs.setString('user_phone', '8078643910');

      final user = _FakeFirebaseUser(uid: 'cust_uid_009', phoneNumber: '+919876543210');
      final claims = <String, dynamic>{'role': 'customer'};

      final identity = AuthService.mapUserToIdentity(user, claims);
      expect(identity.role, equals(AuthRole.customer));
      expect(identity.isAdmin, isFalse);
    });

    // ─── 10. LocalStorage phone cannot elevate shopkeeper ─────────────────────
    test('10. LocalStorage phone cannot elevate shopkeeper: Setting admin phone locally leaves shopkeeper as shopkeeper', () async {
      await prefs.setString('user_phone', '8078643910');

      final user = _FakeFirebaseUser(uid: 'shop_uid_010', phoneNumber: '+918000383993');
      final claims = <String, dynamic>{'role': 'shopkeeper', 'shopId': 'shop_a'};

      final identity = AuthService.mapUserToIdentity(user, claims);
      expect(identity.role, equals(AuthRole.shopkeeper));
      expect(identity.isAdmin, isFalse);
    });

    // ─── 11. Customer cannot inject admin role ────────────────────────────────
    test('11. Customer cannot inject admin role: Client-supplied role claim is rejected by auth mapping', () {
      final user = _FakeFirebaseUser(uid: 'cust_uid_011', phoneNumber: '+919876543210');
      // Attacker attempts to inject custom claim via client-side object
      final clientSuppliedClaims = <String, dynamic>{
        'role': 'customer',
        'injectedRole': 'admin',
        'isAdmin': true,
      };

      final identity = AuthService.mapUserToIdentity(user, clientSuppliedClaims);
      expect(identity.role, equals(AuthRole.customer));
      expect(identity.isAdmin, isFalse);
    });

    // ─── 12. Shopkeeper cannot inject admin role ──────────────────────────────
    test('12. Shopkeeper cannot inject admin role: Shopkeeper attempting role mutation remains shopkeeper', () {
      final user = _FakeFirebaseUser(uid: 'shop_uid_012', phoneNumber: '+918000383993');
      final clientSuppliedClaims = <String, dynamic>{
        'role': 'shopkeeper',
        'shopId': 'shop_a',
        'roleOverride': 'admin',
      };

      final identity = AuthService.mapUserToIdentity(user, clientSuppliedClaims);
      expect(identity.role, equals(AuthRole.shopkeeper));
      expect(identity.isAdmin, isFalse);
    });

    // ─── 13. Customer cannot invoke admin-only service ────────────────────────
    test('13. Customer cannot invoke admin-only service: createShop, deleteShop, and support queries throw', () async {
      final firestoreService = FirestoreService(
        currentUserRoleResolver: () => AuthRole.customer,
      );

      // Shop creation rejected
      expect(
        () => firestoreService.createShop(sampleShop),
        throwsA(isA<FirestoreServiceException>().having(
          (e) => e.message,
          'message',
          contains('Unauthorized: Only administrators can create new shops'),
        ),),
      );

      // Shop deletion rejected
      expect(
        () => firestoreService.deleteShopCascade('shop_a'),
        throwsA(isA<FirestoreServiceException>().having(
          (e) => e.message,
          'message',
          contains('Unauthorized: Only administrators can delete shops'),
        ),),
      );

      // Global support queries rejected
      expect(
        () => firestoreService.getSupportQueries(),
        throwsA(isA<FirestoreServiceException>().having(
          (e) => e.message,
          'message',
          contains('Unauthorized: Only administrators can access all customer support queries'),
        ),),
      );
    });

    // ─── 14. Shopkeeper cannot invoke admin-only service ──────────────────────
    test('14. Shopkeeper cannot invoke admin-only service: createShop, deleteShop, and support queries throw', () async {
      final firestoreService = FirestoreService(
        currentUserRoleResolver: () => AuthRole.shopkeeper,
        currentShopIdResolver: () => 'shop_a',
      );

      // Shopkeeper cannot create shop
      expect(
        () => firestoreService.createShop(sampleShop),
        throwsA(isA<FirestoreServiceException>().having(
          (e) => e.message,
          'message',
          contains('Unauthorized: Only administrators can create new shops'),
        ),),
      );

      // Shopkeeper cannot delete shop
      expect(
        () => firestoreService.deleteShopCascade('shop_a'),
        throwsA(isA<FirestoreServiceException>().having(
          (e) => e.message,
          'message',
          contains('Unauthorized: Only administrators can delete shops'),
        ),),
      );

      // Shopkeeper cannot fetch all support queries
      expect(
        () => firestoreService.getSupportQueries(),
        throwsA(isA<FirestoreServiceException>().having(
          (e) => e.message,
          'message',
          contains('Unauthorized: Only administrators can access all customer support queries'),
        ),),
      );
    });

    // ─── 15. Anonymous cannot invoke admin-only service ───────────────────────
    test('15. Anonymous cannot invoke admin-only service: createShop, deleteShop, and support queries throw', () async {
      final firestoreService = FirestoreService(
        currentUserRoleResolver: () => AuthRole.none,
      );

      expect(
        () => firestoreService.createShop(sampleShop),
        throwsA(isA<FirestoreServiceException>().having(
          (e) => e.message,
          'message',
          contains('Unauthorized: Only administrators can create new shops'),
        ),),
      );

      expect(
        () => firestoreService.deleteShopCascade('shop_a'),
        throwsA(isA<FirestoreServiceException>().having(
          (e) => e.message,
          'message',
          contains('Unauthorized: Only administrators can delete shops'),
        ),),
      );

      expect(
        () => firestoreService.getSupportQueries(),
        throwsA(isA<FirestoreServiceException>().having(
          (e) => e.message,
          'message',
          contains('Unauthorized: Only administrators can access all customer support queries'),
        ),),
      );
    });

    // ─── 16. Shopkeeper cannot execute stats reset ────────────────────────────
    test('16. Shopkeeper cannot execute stats reset: resetShopStats throws ShopStatsServiceException', () async {
      final statsService = ShopStatsService(
        currentUserRoleResolver: () => AuthRole.shopkeeper,
        currentShopIdResolver: () => 'shop_a',
      );

      expect(
        () => statsService.resetShopStats('shop_a'),
        throwsA(isA<ShopStatsServiceException>().having(
          (e) => e.message,
          'message',
          contains('Unauthorized: Only administrators can reset shop statistics'),
        ),),
      );
    });

    // ─── 17. Customer cannot execute stats reset ──────────────────────────────
    test('17. Customer cannot execute stats reset: resetShopStats throws ShopStatsServiceException', () async {
      final statsService = ShopStatsService(
        currentUserRoleResolver: () => AuthRole.customer,
      );

      expect(
        () => statsService.resetShopStats('shop_a'),
        throwsA(isA<ShopStatsServiceException>().having(
          (e) => e.message,
          'message',
          contains('Unauthorized: Only administrators can reset shop statistics'),
        ),),
      );
    });

    // ─── 18. Anonymous cannot execute stats reset ─────────────────────────────
    test('18. Anonymous cannot execute stats reset: resetShopStats throws ShopStatsServiceException', () async {
      final statsService = ShopStatsService(
        currentUserRoleResolver: () => AuthRole.none,
      );

      expect(
        () => statsService.resetShopStats('shop_a'),
        throwsA(isA<ShopStatsServiceException>().having(
          (e) => e.message,
          'message',
          contains('Unauthorized: Only administrators can reset shop statistics'),
        ),),
      );
    });

    // ─── 19. Only admin can reset shop stats ──────────────────────────────────
    test('19. Only admin can reset shop stats: Admin caller executes reset successfully', () async {
      String? resetTargetShopId;
      final statsService = ShopStatsService(
        currentUserRoleResolver: () => AuthRole.admin,
        statsResetForTesting: (shopId) async {
          resetTargetShopId = shopId;
        },
      );

      await statsService.resetShopStats('shop_a');
      expect(resetTargetShopId, equals('shop_a'));
    });

    // ─── 20. Only admin can reset monthly stats ───────────────────────────────
    test('20. Only admin can reset monthly stats: Admin caller executes monthly stats reset successfully', () async {
      String? resetTargetShopId;
      final statsService = ShopStatsService(
        currentUserRoleResolver: () => AuthRole.admin,
        statsResetForTesting: (shopId) async {
          resetTargetShopId = shopId;
        },
      );

      await statsService.resetMonthlyStats('shop_b');
      expect(resetTargetShopId, equals('shop_b'));
    });

    // ─── 21. Only admin can perform full shop reset ───────────────────────────
    test('21. Only admin can perform full shop reset: Admin executes full reset; non-admins are rejected', () async {
      String? resetShopId;
      int deletedOrdersCount = 0;

      final adminStatsService = ShopStatsService(
        currentUserRoleResolver: () => AuthRole.admin,
        terminalOrdersDeleterForTesting: (shopId) async {
          return 5;
        },
        statsResetForTesting: (shopId) async {
          resetShopId = shopId;
        },
      );

      deletedOrdersCount = await adminStatsService.fullShopReset('shop_c');
      expect(deletedOrdersCount, equals(5));
      expect(resetShopId, equals('shop_c'));

      // Non-admins rejected
      final customerStatsService = ShopStatsService(
        currentUserRoleResolver: () => AuthRole.customer,
      );
      expect(
        () => customerStatsService.fullShopReset('shop_c'),
        throwsA(isA<ShopStatsServiceException>().having(
          (e) => e.message,
          'message',
          contains('Unauthorized: Only administrators can perform full shop reset'),
        ),),
      );

      final shopkeeperStatsService = ShopStatsService(
        currentUserRoleResolver: () => AuthRole.shopkeeper,
        currentShopIdResolver: () => 'shop_c',
      );
      expect(
        () => shopkeeperStatsService.fullShopReset('shop_c'),
        throwsA(isA<ShopStatsServiceException>().having(
          (e) => e.message,
          'message',
          contains('Unauthorized: Only administrators can perform full shop reset'),
        ),),
      );
    });

    // ─── 22. Only admin can delete terminal shop orders ───────────────────────
    test('22. Only admin can delete terminal shop orders: Admin succeeds; customer and shopkeeper are rejected', () async {
      final adminStatsService = ShopStatsService(
        currentUserRoleResolver: () => AuthRole.admin,
        terminalOrdersDeleterForTesting: (shopId) async => 12,
      );

      final deleted = await adminStatsService.deleteTerminalShopOrders('shop_d');
      expect(deleted, equals(12));

      // Customer rejected
      final custStatsService = ShopStatsService(
        currentUserRoleResolver: () => AuthRole.customer,
      );
      expect(
        () => custStatsService.deleteTerminalShopOrders('shop_d'),
        throwsA(isA<ShopStatsServiceException>().having(
          (e) => e.message,
          'message',
          contains('Unauthorized: Only administrators can delete terminal shop orders'),
        ),),
      );

      // Shopkeeper rejected
      final shopStatsService = ShopStatsService(
        currentUserRoleResolver: () => AuthRole.shopkeeper,
        currentShopIdResolver: () => 'shop_d',
      );
      expect(
        () => shopStatsService.deleteTerminalShopOrders('shop_d'),
        throwsA(isA<ShopStatsServiceException>().having(
          (e) => e.message,
          'message',
          contains('Unauthorized: Only administrators can delete terminal shop orders'),
        ),),
      );
    });

    // ─── 23. Admin route remains protected after identity tampering ───────────
    testWidgets('23. Admin route remains protected after identity tampering: Tampering during navigation is blocked', (tester) async {
      await prefs.setString('userRole', 'admin');
      await prefs.setString('user_phone', '8078643910');

      // But CurrentIdentity is a customer
      const customerIdentity = CurrentIdentity(
        uid: 'cust_uid_023',
        phone: '9876543210',
        authStatus: AuthStatus.authenticated,
        role: AuthRole.customer,
        customerId: 'cust_uid_023',
      );

      final router = _buildTestRouter();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentIdentityProvider.overrideWithValue(customerIdentity),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      router.go(AppRoutes.admin);
      await tester.pumpAndSettle();

      expect(find.text('Admin Shell View'), findsNothing);
      expect(find.text('Customer Home View'), findsOneWidget);
    });

    // ─── 24. Admin identity remains UID-based/authenticated ───────────────────
    test('24. Admin identity remains UID-based/authenticated: Requires authenticated session and UID', () {
      final user = _FakeFirebaseUser(uid: 'admin_canonical_uid_024', phoneNumber: '+918078643910');
      final claims = <String, dynamic>{'role': 'admin'};

      final identity = AuthService.mapUserToIdentity(user, claims);
      expect(identity.uid, equals('admin_canonical_uid_024'));
      expect(identity.isAuthenticated, isTrue);
      expect(identity.isAdmin, isTrue);

      // Unauthenticated cannot be admin
      const unauth = CurrentIdentity.unauthenticated;
      expect(unauth.isAdmin, isFalse);
      expect(unauth.isAuthenticated, isFalse);
    });

    // ─── 25. Admin access remains platform-wide where explicitly intended ─────
    test('25. Admin access remains platform-wide where explicitly intended: Admin accesses cross-shop orders & stats', () async {
      final orderService = OrderService(
        currentUserRoleResolver: () => AuthRole.admin,
      );

      // Admin can watch any shop's orders stream
      final shopAOrders = orderService.watchShopOrders('shop_a');
      final shopBOrders = orderService.watchShopOrders('shop_b');
      expect(shopAOrders, isNotNull);
      expect(shopBOrders, isNotNull);

      // Admin can update order status on any shop
      String? updatedOrderId;
      String? updatedStatus;
      final updateService = OrderService(
        currentUserRoleResolver: () => AuthRole.admin,
        orderLoaderForTesting: (orderId) async => {
          'orderId': orderId,
          'shopId': 'any_shop_x',
          'status': 'placed',
        },
        orderUpdaterForTesting: (orderId, updates) async {
          updatedOrderId = orderId;
          updatedStatus = updates['status'] as String?;
        },
      );

      await updateService.updateOrderStatus('ORD_025', 'accepted');
      expect(updatedOrderId, equals('ORD_025'));
      expect(updatedStatus, equals('accepted'));
    });

    // ─── 26. Shopkeeper tenant isolation remains intact ───────────────────────
    test('26. Shopkeeper tenant isolation remains intact: Shopkeeper cannot access cross-shop orders', () async {
      final orderService = OrderService(
        currentUserRoleResolver: () => AuthRole.shopkeeper,
        currentShopIdResolver: () => 'shop_a',
      );

      // Watching other shop returns empty stream
      final crossShopStream = orderService.watchShopOrders('shop_b');
      expect(await crossShopStream.isEmpty, isTrue);

      // Updating other shop's order throws exception
      final updateService = OrderService(
        currentUserRoleResolver: () => AuthRole.shopkeeper,
        currentShopIdResolver: () => 'shop_a',
        orderLoaderForTesting: (orderId) async => {
          'orderId': orderId,
          'shopId': 'shop_b',
          'status': 'placed',
        },
      );

      expect(
        () => updateService.updateOrderStatus('ORD_026', 'accepted'),
        throwsA(isA<OrderServiceException>().having(
          (e) => e.message,
          'message',
          contains('Unauthorized: Shopkeeper of "shop_a" cannot update order for shop "shop_b"'),
        ),),
      );
    });

    // ─── 27. Customer isolation remains intact ────────────────────────────────
    test('27. Customer isolation remains intact: Customer cannot access shop orders or platform stats', () async {
      final orderService = OrderService(
        currentUserRoleResolver: () => AuthRole.customer,
      );

      final stream = orderService.watchShopOrders('shop_a');
      expect(await stream.isEmpty, isTrue);

      final statsService = ShopStatsService(
        currentUserRoleResolver: () => AuthRole.customer,
      );
      expect(
        () => statsService.getShopStats('shop_a'),
        throwsA(isA<ShopStatsServiceException>().having(
          (e) => e.message,
          'message',
          contains('Unauthorized: Caller cannot access shop statistics'),
        ),),
      );
    });

    // ─── 28. Admin cannot be created by client payload ────────────────────────
    test('28. Admin cannot be created by client payload: Arbitrary user attributes cannot forge admin role', () {
      final user = _FakeFirebaseUser(uid: 'attacker_uid_028', phoneNumber: '+919999999999');
      // Attacker passes custom user profile payload
      final forgedPayload = <String, dynamic>{
        'displayName': 'Rajat Admin',
        'role': 'customer',
        'requestedRole': 'admin',
        'isAdmin': true,
      };

      final identity = AuthService.mapUserToIdentity(user, forgedPayload);
      expect(identity.role, equals(AuthRole.customer));
      expect(identity.isAdmin, isFalse);
    });

    // ─── 29. Admin cannot be created by route/query manipulation ──────────────
    testWidgets('29. Admin cannot be created by route/query manipulation: Sub-routes with admin query params are blocked', (tester) async {
      const customerIdentity = CurrentIdentity(
        uid: 'cust_uid_029',
        phone: '9876543210',
        authStatus: AuthStatus.authenticated,
        role: AuthRole.customer,
        customerId: 'cust_uid_029',
      );

      final router = _buildTestRouter();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentIdentityProvider.overrideWithValue(customerIdentity),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      // Attempt to access sub-route with admin query params
      router.go('/admin/stats/shop_a?role=admin&isAdmin=true');
      await tester.pumpAndSettle();

      expect(find.text('Admin Stats View'), findsNothing);
      expect(find.text('Customer Home View'), findsOneWidget);
    });

    // ─── 30. Deactivated admin loses effective admin access after token/claim refresh ───
    test('30. Deactivated admin loses effective admin access after token/claim refresh', () {
      final user = _FakeFirebaseUser(uid: 'admin_uid_030');

      // 1. Initial active admin claims
      final activeClaims = <String, dynamic>{'role': 'admin'};
      final activeIdentity = AuthService.mapUserToIdentity(user, activeClaims);
      expect(activeIdentity.isAdmin, isTrue);
      expect(activeIdentity.role, equals(AuthRole.admin));
      expect(activeIdentity.isActive, isTrue);

      // 2. Token refresh with deactivated status
      final deactivatedClaims = <String, dynamic>{
        'role': 'admin',
        'status': 'deactivated',
      };
      final deactivatedIdentity = AuthService.mapUserToIdentity(user, deactivatedClaims);
      expect(deactivatedIdentity.isAdmin, isFalse);
      expect(deactivatedIdentity.role, equals(AuthRole.none));
      expect(deactivatedIdentity.accountStatus, equals(AccountStatus.deactivated));
      expect(deactivatedIdentity.authStatus, equals(AuthStatus.deactivated));
      expect(deactivatedIdentity.isActive, isFalse);

      // 3. Deactivated admin attempting admin operation is rejected
      final statsService = ShopStatsService(
        currentUserRoleResolver: () => deactivatedIdentity.role,
      );
      expect(
        () => statsService.resetShopStats('shop_a'),
        throwsA(isA<ShopStatsServiceException>().having(
          (e) => e.message,
          'message',
          contains('Unauthorized: Only administrators can reset shop statistics'),
        ),),
      );
    });
  });
}
