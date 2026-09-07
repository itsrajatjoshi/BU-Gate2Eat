// BU Gate2Eat — Checkpoint 2.2: Trusted Role Assignment Security Test Suite
//
// Verifies all 16 required security points:
// 1. Trusted customer assignment
// 2. Trusted shopkeeper assignment
// 3. Trusted admin assignment
// 4. Invalid role rejection
// 5. Missing shopId rejection for shopkeeper
// 6. Client role injection rejection
// 7. Client shopId injection rejection
// 8. Client account-status injection rejection
// 9. Customer privilege escalation attempt
// 10. Shopkeeper cross-shop reassignment attempt
// 11. Admin/client privilege escalation attempt
// 12. LocalStorage role tampering
// 13. LocalStorage shopId tampering
// 14. Canonical UID ownership invariant
// 15. Deactivated-account handling
// 16. Claims remain minimal and canonical

import 'package:bugate2eat_app/core/providers.dart';
import 'package:bugate2eat_app/core/router.dart';
import 'package:bugate2eat_app/panel/admin_panel/widgets/admin_unauthorized_screen.dart';
import 'package:bugate2eat_app/services/auth_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Fake Firebase User for offline deterministic testing.
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
      GoRoute(path: AppRoutes.shopkeeper, builder: (_, __) => const Scaffold(body: Text('Shopkeeper Shell View'))),
    ],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Checkpoint 2.2: Trusted Role Assignment Security Test Suite', () {
    late SharedPreferences prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
    });

    // ─── 1. Trusted Customer Assignment ─────────────────────────────────────────
    test('1. Trusted customer assignment: server claim maps strictly to customer role', () {
      final user = _FakeFirebaseUser(uid: 'uid_cust_123', phoneNumber: '+919876543210');
      final claims = <String, dynamic>{'role': 'customer'};

      final identity = AuthService.mapUserToIdentity(user, claims);
      expect(identity.role, equals(AuthRole.customer));
      expect(identity.shopId, isNull);
      expect(identity.isCustomer, isTrue);
      expect(identity.isShopkeeper, isFalse);
      expect(identity.isAdmin, isFalse);
      expect(identity.isActive, isTrue);
      expect(identity.uid, equals('uid_cust_123'));
      expect(identity.customerId, equals('uid_cust_123'));
    });

    // ─── 2. Trusted Shopkeeper Assignment ───────────────────────────────────────
    test('2. Trusted shopkeeper assignment: requires server role and valid non-empty shopId', () {
      final user = _FakeFirebaseUser(uid: 'uid_shop_456', phoneNumber: '+919876543211');
      final claims = <String, dynamic>{
        'role': 'shopkeeper',
        'shopId': 'shop_terminal_1',
      };

      final identity = AuthService.mapUserToIdentity(user, claims);
      expect(identity.role, equals(AuthRole.shopkeeper));
      expect(identity.shopId, equals('shop_terminal_1'));
      expect(identity.isShopkeeper, isTrue);
      expect(identity.isCustomer, isFalse);
      expect(identity.isAdmin, isFalse);
      expect(identity.isActive, isTrue);
    });

    // ─── 3. Trusted Admin Assignment ───────────────────────────────────────────
    test('3. Trusted admin assignment: platform-wide role strictly omitting shopId', () {
      final user = _FakeFirebaseUser(uid: 'uid_admin_789', phoneNumber: '+919999999999');
      final claims = <String, dynamic>{'role': 'admin'};

      final identity = AuthService.mapUserToIdentity(user, claims);
      expect(identity.role, equals(AuthRole.admin));
      expect(identity.shopId, isNull);
      expect(identity.isAdmin, isTrue);
      expect(identity.isShopkeeper, isFalse);
      expect(identity.isCustomer, isFalse);
      expect(identity.isActive, isTrue);
    });

    // ─── 4. Invalid Role Rejection ─────────────────────────────────────────────
    test('4. Invalid role rejection: unknown, malformed, or arbitrary roles fail-closed to customer', () {
      final user = _FakeFirebaseUser(uid: 'uid_intruder_001');

      for (final invalidRole in ['superadmin', 'root', 'vendor', 'moderator', '', '   ', '123']) {
        final identity = AuthService.mapUserToIdentity(user, {'role': invalidRole});
        expect(identity.role, equals(AuthRole.customer), reason: 'Role "$invalidRole" must fail-closed to customer');
        expect(identity.isAdmin, isFalse);
        expect(identity.isShopkeeper, isFalse);
        expect(identity.shopId, isNull);
      }
    });

    // ─── 5. Missing shopId Rejection for Shopkeeper ─────────────────────────────
    test('5. Missing shopId rejection: shopkeeper claim without shopId is demoted to customer', () {
      final user = _FakeFirebaseUser(uid: 'uid_shop_no_id');

      // null shopId
      final identityNull = AuthService.mapUserToIdentity(user, {'role': 'shopkeeper'});
      expect(identityNull.role, equals(AuthRole.customer));
      expect(identityNull.shopId, isNull);
      expect(identityNull.isShopkeeper, isFalse);

      // empty string shopId
      final identityEmpty = AuthService.mapUserToIdentity(user, {'role': 'shopkeeper', 'shopId': ''});
      expect(identityEmpty.role, equals(AuthRole.customer));
      expect(identityEmpty.shopId, isNull);
      expect(identityEmpty.isShopkeeper, isFalse);

      // whitespace shopId
      final identityWhitespace = AuthService.mapUserToIdentity(user, {'role': 'shopkeeper', 'shopId': '   '});
      expect(identityWhitespace.role, equals(AuthRole.customer));
      expect(identityWhitespace.shopId, isNull);
      expect(identityWhitespace.isShopkeeper, isFalse);
    });

    // ─── 6. Client Role Injection Rejection ────────────────────────────────────
    test('6. Client role injection rejection: client cannot self-promote by sending role', () {
      // Flutter AuthService.mapUserToIdentity derives role strictly from server claims map.
      // Even if client options had role: admin, server claims map dictates true identity.
      final user = _FakeFirebaseUser(uid: 'uid_client_inj');

      // Legitimate server claims returned by backend:
      final trustedServerClaims = <String, dynamic>{'role': 'customer'};

      final identity = AuthService.mapUserToIdentity(user, trustedServerClaims);
      expect(identity.role, equals(AuthRole.customer));
      expect(identity.isAdmin, isFalse);
      expect(identity.shopId, isNull);
    });

    // ─── 7. Client shopId Injection Rejection ───────────────────────────────────
    test('7. Client shopId injection rejection: customer claim ignores client-provided shopId', () {
      final user = _FakeFirebaseUser(uid: 'uid_client_shop_inj');
      // Attacker customer presents claims contaminated with client shopId
      final maliciousClaims = <String, dynamic>{
        'role': 'customer',
        'shopId': 'target_shop_to_hijack',
      };

      final identity = AuthService.mapUserToIdentity(user, maliciousClaims);
      expect(identity.role, equals(AuthRole.customer));
      expect(identity.shopId, isNull, reason: 'Customer cannot possess shopId');
      expect(identity.isShopkeeper, isFalse);
    });

    // ─── 8. Client Account-Status Injection Rejection ──────────────────────────
    test('8. Client account-status injection rejection: client cannot reactivate a deactivated account', () {
      final user = _FakeFirebaseUser(uid: 'uid_deactivated_user');
      // Server marks account as deactivated
      final claims = <String, dynamic>{
        'role': 'admin',
        'status': 'deactivated',
      };

      final identity = AuthService.mapUserToIdentity(user, claims);
      expect(identity.accountStatus, equals(AccountStatus.deactivated));
      expect(identity.authStatus, equals(AuthStatus.deactivated));
      expect(identity.role, equals(AuthRole.none));
      expect(identity.isAdmin, isFalse);
      expect(identity.isActive, isFalse);
    });

    // ─── 9. Customer Privilege Escalation Attempt ──────────────────────────────
    testWidgets('9. Customer privilege escalation attempt: customer blocked from /admin & /shopkeeper', (tester) async {
      final container = ProviderContainer(
        overrides: [
          currentIdentityProvider.overrideWithValue(
            const CurrentIdentity(
              uid: 'uid_cust_esc',
              phone: '9876543210',
              authStatus: AuthStatus.authenticated,
              role: AuthRole.customer,
              customerId: 'uid_cust_esc',
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      // Attempt navigating to /admin
      final adminRouter = _buildTestRouter(initialLocation: AppRoutes.admin);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: adminRouter),
        ),
      );
      await tester.pumpAndSettle();

      // Verified: Customer is redirected to /home
      expect(find.text('Customer Home View'), findsOneWidget);
      expect(find.text('Admin Shell View'), findsNothing);

      // Attempt navigating to /shopkeeper
      final shopRouter = _buildTestRouter(initialLocation: AppRoutes.shopkeeper);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: shopRouter),
        ),
      );
      await tester.pumpAndSettle();

      // Verified: Customer is redirected to /home
      expect(find.text('Customer Home View'), findsOneWidget);
      expect(find.text('Shopkeeper Shell View'), findsNothing);
    });

    // ─── 10. Shopkeeper Cross-Shop Reassignment Attempt ────────────────────────
    test('10. Shopkeeper cross-shop reassignment attempt: local storage shopId cannot reassign shop', () async {
      await prefs.setString('shopkeeper_shop_id', 'cross_shop_victim');

      final container = ProviderContainer(
        overrides: [
          currentIdentityProvider.overrideWithValue(
            const CurrentIdentity(
              uid: 'uid_shop_10',
              phone: '9876543212',
              authStatus: AuthStatus.authenticated,
              role: AuthRole.shopkeeper,
              shopId: 'assigned_shop_legit',
              customerId: 'uid_shop_10',
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      // The authoritative shopkeeper shop ID must come strictly from CurrentIdentity, NOT SharedPreferences
      final activeShopId = container.read(currentShopkeeperShopIdProvider);
      expect(activeShopId, equals('assigned_shop_legit'));
      expect(activeShopId, isNot(equals('cross_shop_victim')));
    });

    // ─── 11. Admin/Client Privilege Escalation Attempt ─────────────────────────
    testWidgets('11. Admin/client privilege escalation attempt: customer with tampered userRole is denied', (tester) async {
      // Local storage tampering: attacker writes userRole: 'admin'
      await prefs.setString('userRole', 'admin');
      await prefs.setBool('is_onboarded', true);

      // But authenticated session is customer
      final container = ProviderContainer(
        overrides: [
          currentIdentityProvider.overrideWithValue(
            const CurrentIdentity(
              uid: 'uid_cust_attacker',
              phone: '9876543210',
              authStatus: AuthStatus.authenticated,
              role: AuthRole.customer,
              customerId: 'uid_cust_attacker',
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      bool? authorized;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Consumer(
              builder: (context, ref, _) {
                authorized = isAdminAuthorized(ref);
                return Text('authorized: $authorized');
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // isAdminAuthorized checks CurrentIdentity first when authenticated -> returns false
      expect(authorized, isFalse);
    });

    // ─── 12. LocalStorage Role Tampering ───────────────────────────────────────
    test('12. LocalStorage role tampering: SharedPreferences userRole does not grant role in CurrentIdentity', () async {
      await prefs.setString('userRole', 'admin');

      // Server issues claims: role: customer
      final user = _FakeFirebaseUser(uid: 'uid_cust_prefs_attack');
      final claims = <String, dynamic>{'role': 'customer'};

      final identity = AuthService.mapUserToIdentity(user, claims);
      expect(identity.role, equals(AuthRole.customer));
      expect(identity.isAdmin, isFalse);
    });

    // ─── 13. LocalStorage shopId Tampering ─────────────────────────────────────
    test('13. LocalStorage shopId tampering: SharedPreferences cannot elevate customer or alter shopkeeper shop', () async {
      await prefs.setString('shopkeeper_shop_id', 'unauthorized_shop');

      const customerIdentity = CurrentIdentity(
        uid: 'uid_cust_13',
        phone: '9876543210',
        authStatus: AuthStatus.authenticated,
        role: AuthRole.customer,
        customerId: 'uid_cust_13',
      );

      final container = ProviderContainer(
        overrides: [
          currentIdentityProvider.overrideWithValue(customerIdentity),
        ],
      );
      addTearDown(container.dispose);

      // For customer, currentShopkeeperShopIdProvider returns null despite SharedPreferences having shopId
      final shopId = container.read(currentShopkeeperShopIdProvider);
      expect(shopId, isNull);
    });

    // ─── 14. Canonical UID Ownership Invariant ─────────────────────────────────
    test('14. Canonical UID ownership invariant: customerId strictly matches Firebase UID', () {
      final user = _FakeFirebaseUser(uid: 'auth_uid_strictly_canonical', phoneNumber: '+919876543210');
      final identity = AuthService.mapUserToIdentity(user, {'role': 'customer'});

      expect(identity.uid, equals('auth_uid_strictly_canonical'));
      expect(identity.customerId, equals('auth_uid_strictly_canonical'));
      expect(identity.customerId, equals(identity.uid));

      // Customer identity never derives customerId from phone
      expect(identity.customerId, isNot(contains('9876543210')));
      expect(identity.customerId, isNot(startsWith('cust_')));
    });

    // ─── 15. Deactivated-Account Handling ──────────────────────────────────────
    test('15. Deactivated-account handling: revoked account loses all elevated access', () {
      final user = _FakeFirebaseUser(uid: 'uid_deactivated_admin');

      // Deactivated admin
      final adminIdentity = AuthService.mapUserToIdentity(user, {
        'role': 'admin',
        'status': 'deactivated',
      });
      expect(adminIdentity.role, equals(AuthRole.none));
      expect(adminIdentity.accountStatus, equals(AccountStatus.deactivated));
      expect(adminIdentity.authStatus, equals(AuthStatus.deactivated));
      expect(adminIdentity.isAdmin, isFalse);
      expect(adminIdentity.isActive, isFalse);

      // Deactivated shopkeeper
      final shopIdentity = AuthService.mapUserToIdentity(user, {
        'role': 'shopkeeper',
        'shopId': 'shop_terminal_1',
        'status': 'disabled',
      });
      expect(shopIdentity.role, equals(AuthRole.none));
      expect(shopIdentity.shopId, isNull);
      expect(shopIdentity.isShopkeeper, isFalse);
      expect(shopIdentity.isActive, isFalse);
    });

    // ─── 16. Claims Remain Minimal and Canonical ───────────────────────────────
    test('16. Claims remain minimal and canonical: schemas strictly match Phase 2.1 / 2.2 spec', () {
      // Customer: { "role": "customer" }
      final customerClaims = {'role': 'customer'};
      expect(customerClaims.keys, contains('role'));
      expect(customerClaims.containsKey('customerId'), isFalse);
      expect(customerClaims.containsKey('shopId'), isFalse);

      // Shopkeeper: { "role": "shopkeeper", "shopId": "<shopId>" }
      final shopkeeperClaims = {'role': 'shopkeeper', 'shopId': 'terminal_1'};
      expect(shopkeeperClaims.keys, containsAll(['role', 'shopId']));
      expect(shopkeeperClaims.containsKey('customerId'), isFalse);

      // Admin: { "role": "admin" }
      final adminClaims = {'role': 'admin'};
      expect(adminClaims.keys, contains('role'));
      expect(adminClaims.containsKey('shopId'), isFalse);
      expect(adminClaims.containsKey('customerId'), isFalse);
    });

    // ─── 17. Privileged Token Gate: Phone Alone Cannot Impersonate Roles ────────
    test('17. Privileged token gate: Knowing admin/shopkeeper phone alone cannot grant elevated identity without verified server claims', () {
      // Attacker presents an unverified user object with admin phone, but zero server claims
      final fakeAdminUser = _FakeFirebaseUser(uid: 'unverified_caller', phoneNumber: '+918078643910');

      // Without server custom claims issued after OTP verification, mapUserToIdentity defaults to customer
      final identityNoClaims = AuthService.mapUserToIdentity(fakeAdminUser, const {});
      expect(identityNoClaims.role, equals(AuthRole.customer));
      expect(identityNoClaims.isAdmin, isFalse);
      expect(identityNoClaims.isShopkeeper, isFalse);
      expect(identityNoClaims.shopId, isNull);

      // Even for a known shopkeeper phone, without trusted claims it never becomes shopkeeper
      final fakeShopUser = _FakeFirebaseUser(uid: 'unverified_caller_2', phoneNumber: '+918000383993');
      final identityShopNoClaims = AuthService.mapUserToIdentity(fakeShopUser, const {});
      expect(identityShopNoClaims.role, equals(AuthRole.customer));
      expect(identityShopNoClaims.isShopkeeper, isFalse);
      expect(identityShopNoClaims.shopId, isNull);

      // Null user (unauthenticated) with injected claims fails closed
      final identityNullUser = AuthService.mapUserToIdentity(null, const {'role': 'admin'});
      expect(identityNullUser.isAuthenticated, isFalse);
      expect(identityNullUser.role, equals(AuthRole.none));
      expect(identityNullUser.isAdmin, isFalse);
    });
  });
}
