// BU Gate2Eat — Checkpoint 2.1: RBAC Role Model & Custom Claims Security Test Suite
//
// Verifies:
// 1. Role Integrity:
//    - Client cannot choose role (claims originate strictly from server).
//    - Local storage role (userRole/isAdmin) cannot override Custom Claims role.
//    - Phone number cannot override Custom Claims role.
// 2. Canonical Claim Mapping:
//    - Customer claim -> AuthRole.customer, shopId: null, isCustomer: true.
//    - Shopkeeper claim -> AuthRole.shopkeeper, valid shopId, isShopkeeper: true.
//    - Admin claim -> AuthRole.admin, shopId: null, isAdmin: true.
// 3. Missing, Invalid & Unassigned Roles (Fail-Closed):
//    - Authenticated user without role claim safely defaults to AuthRole.customer.
//    - Authenticated user with invalid/unknown role safely defaults to AuthRole.customer.
//    - Shopkeeper role claim without valid shopId has vendor permissions denied (isShopkeeper == false, role == customer).
//    - CurrentIdentity with shopkeeper role but null shopId returns isShopkeeper == false.
// 4. Role Conflicts & Precedence:
//    - Custom Claims override SharedPreferences / local storage role tampering.
//    - Custom Claims override legacy phone mapping.
//    - Route guard relies strictly on Custom Claims role, redirecting unauthorized users to /home.
// 5. Role Revocation & Account Deactivation:
//    - Admin role revocation (admin -> customer) strips admin privileges upon token refresh.
//    - Shopkeeper role revocation (shopkeeper -> customer) strips shopkeeper and shopId.
//    - Account deactivation via claims (status: 'deactivated') sets AuthStatus.deactivated and AuthRole.none.
//    - Account deactivation via role (role: 'deactivated') sets AuthStatus.deactivated and AuthRole.none.

import 'package:bugate2eat_app/core/providers.dart';
import 'package:bugate2eat_app/core/router.dart';
import 'package:bugate2eat_app/services/auth_service.dart';
import 'package:bugate2eat_app/services/local_storage_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Fake Firebase User for deterministic offline identity and claim mapping tests.
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

  group('Checkpoint 2.1: RBAC Role Model & Custom Claims Security Suite', () {
    late SharedPreferences prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues({
        'user_phone': '9876543210',
        'user_name': 'Test User',
        'is_onboarded': true,
        'userRole': 'admin', // Simulated local storage tampering
      });
      prefs = await SharedPreferences.getInstance();
    });

    // ─── 1. Role Integrity Tests ──────────────────────────────────────────────
    group('1. Role Integrity', () {
      test('Client cannot choose role: CurrentIdentity strictly maps server-supplied claims', () {
        final user = _FakeFirebaseUser(uid: 'uid_cust_001', phoneNumber: '+919876543210');
        // Backend issued customer claims
        final serverClaims = <String, dynamic>{'role': 'customer'};

        final identity = AuthService.mapUserToIdentity(user, serverClaims);
        expect(identity.role, equals(AuthRole.customer));
        expect(identity.isAdmin, isFalse);
        expect(identity.isShopkeeper, isFalse);
        expect(identity.isCustomer, isTrue);
      });

      test('Local storage role tampering cannot override server Custom Claims', () {
        // Local storage has 'userRole': 'admin'
        expect(prefs.getString('userRole'), equals('admin'));

        final user = _FakeFirebaseUser(uid: 'uid_cust_tamper', phoneNumber: '+919876543210');
        final serverClaims = <String, dynamic>{'role': 'customer'};

        final identity = AuthService.mapUserToIdentity(user, serverClaims);
        // Authoritative server claim takes precedence over untrusted local storage
        expect(identity.role, equals(AuthRole.customer));
        expect(identity.isAdmin, isFalse);
      });

      test('Phone number cannot override Custom Claims role', () {
        // User's phone number happens to match the hardcoded admin phone (8078643910)
        // but their Firebase token claims say "customer"
        final user = _FakeFirebaseUser(uid: 'uid_cust_same_phone', phoneNumber: '+918078643910');
        final serverClaims = <String, dynamic>{'role': 'customer', 'phone': '8078643910'};

        final identity = AuthService.mapUserToIdentity(user, serverClaims);
        // Phone match in legacy map must NOT grant admin when claims say customer
        expect(identity.role, equals(AuthRole.customer));
        expect(identity.isAdmin, isFalse);
      });

      test('Phone matching shopkeeper map cannot override customer claim', () {
        // Phone matches Rajat Shop in legacy map (8000383993), but claims say customer
        final user = _FakeFirebaseUser(uid: 'uid_cust_shop_phone', phoneNumber: '+918000383993');
        final serverClaims = <String, dynamic>{'role': 'customer', 'phone': '8000383993'};

        final identity = AuthService.mapUserToIdentity(user, serverClaims);
        expect(identity.role, equals(AuthRole.customer));
        expect(identity.isShopkeeper, isFalse);
        expect(identity.shopId, isNull);
      });
    });

    // ─── 2. Canonical Claim Mapping Tests ────────────────────────────────────
    group('2. Canonical Claim Mapping', () {
      test('Customer claim maps to customer role with canonical customerId == UID and null shopId', () {
        final user = _FakeFirebaseUser(uid: 'uid_cust_123', phoneNumber: '+919876543210');
        // Canonical customer claim: strictly { role: 'customer' } (no customerId in claims!)
        final claims = <String, dynamic>{
          'role': 'customer',
        };

        final identity = AuthService.mapUserToIdentity(user, claims);
        expect(identity.uid, equals('uid_cust_123'));
        expect(identity.role, equals(AuthRole.customer));
        expect(identity.isCustomer, isTrue);
        expect(identity.isShopkeeper, isFalse);
        expect(identity.isAdmin, isFalse);
        expect(identity.shopId, isNull);
        // Canonical customer identity: customerId == request.auth.uid == user.uid
        expect(identity.customerId, equals('uid_cust_123'));
        expect(identity.authStatus, equals(AuthStatus.authenticated));
      });

      test('Shopkeeper claim with valid shopId maps to shopkeeper role and shopId', () {
        final user = _FakeFirebaseUser(uid: 'uid_shop_456', phoneNumber: '+918000383993');
        final claims = <String, dynamic>{
          'role': 'shopkeeper',
          'shopId': 'rajat_shop',
        };

        final identity = AuthService.mapUserToIdentity(user, claims);
        expect(identity.uid, equals('uid_shop_456'));
        expect(identity.role, equals(AuthRole.shopkeeper));
        expect(identity.isShopkeeper, isTrue);
        expect(identity.isCustomer, isFalse);
        expect(identity.isAdmin, isFalse);
        expect(identity.shopId, equals('rajat_shop'));
        expect(identity.customerId, equals('uid_shop_456'));
      });

      test('Admin claim maps to admin role with strictly null shopId', () {
        final user = _FakeFirebaseUser(uid: 'uid_admin_789', phoneNumber: '+918078643910');
        final claims = <String, dynamic>{
          'role': 'admin',
        };

        final identity = AuthService.mapUserToIdentity(user, claims);
        expect(identity.uid, equals('uid_admin_789'));
        expect(identity.role, equals(AuthRole.admin));
        expect(identity.isAdmin, isTrue);
        expect(identity.isCustomer, isFalse);
        expect(identity.isShopkeeper, isFalse);
        expect(identity.shopId, isNull);
      });

      test('Admin claim with injected shopId strictly ignores shopId claim', () {
        final user = _FakeFirebaseUser(uid: 'uid_admin_injected');
        final claims = <String, dynamic>{
          'role': 'admin',
          'shopId': 'malicious_shop_override',
        };

        final identity = AuthService.mapUserToIdentity(user, claims);
        expect(identity.role, equals(AuthRole.admin));
        expect(identity.isAdmin, isTrue);
        // Security invariant: Admin claims NEVER scope to a shopId
        expect(identity.shopId, isNull);
      });
    });

    // ─── 3. Missing, Invalid & Unassigned Roles (Fail-Closed) ──────────────────
    group('3. Missing, Invalid & Unassigned Roles (Fail-Closed)', () {
      test('Missing role claim safely defaults to customer role with zero elevated access', () {
        final user = _FakeFirebaseUser(uid: 'uid_no_claims');
        final claims = <String, dynamic>{}; // No role claim

        final identity = AuthService.mapUserToIdentity(user, claims);
        expect(identity.role, equals(AuthRole.customer));
        expect(identity.isCustomer, isTrue);
        expect(identity.isShopkeeper, isFalse);
        expect(identity.isAdmin, isFalse);
        expect(identity.shopId, isNull);
      });

      test('Unknown or invalid role string safely defaults to customer role', () {
        final user = _FakeFirebaseUser(uid: 'uid_unknown_role');
        final claims = <String, dynamic>{
          'role': 'super_admin_fake',
        };

        final identity = AuthService.mapUserToIdentity(user, claims);
        expect(identity.role, equals(AuthRole.customer));
        expect(identity.isAdmin, isFalse);
        expect(identity.isShopkeeper, isFalse);
        expect(identity.shopId, isNull);
      });

      test('Shopkeeper claim without shopId is demoted to customer with zero vendor access', () {
        final user = _FakeFirebaseUser(uid: 'uid_unassigned_vendor');
        final claims = <String, dynamic>{
          'role': 'shopkeeper',
          // Missing shopId
        };

        final identity = AuthService.mapUserToIdentity(user, claims);
        expect(identity.role, equals(AuthRole.customer));
        expect(identity.isShopkeeper, isFalse);
        expect(identity.shopId, isNull);
      });

      test('Shopkeeper claim with empty shopId is demoted to customer', () {
        final user = _FakeFirebaseUser(uid: 'uid_empty_shop_vendor');
        final claims = <String, dynamic>{
          'role': 'shopkeeper',
          'shopId': '   ',
        };

        final identity = AuthService.mapUserToIdentity(user, claims);
        expect(identity.role, equals(AuthRole.customer));
        expect(identity.isShopkeeper, isFalse);
        expect(identity.shopId, isNull);
      });

      test('CurrentIdentity isShopkeeper returns false if shopId is null even if role is shopkeeper', () {
        const manualIdentity = CurrentIdentity(
          uid: 'uid_edge_case',
          phone: '9876543210',
          authStatus: AuthStatus.authenticated,
          role: AuthRole.shopkeeper,
          customerId: 'uid_edge_case',
        );

        // Security invariant: shopkeeper without valid shopId must not obtain vendor permissions
        expect(manualIdentity.isShopkeeper, isFalse);
        expect(manualIdentity.shopId, isNull);
      });
    });

    // ─── 4. Role Conflicts & Precedence ───────────────────────────────────────
    group('4. Role Conflicts & Precedence', () {
      testWidgets('Conflict: LocalStorage claims admin, but Custom Claims is customer -> access denied', (tester) async {
        // Storage claims admin
        SharedPreferences.setMockInitialValues({
          'user_phone': '9876543210',
          'user_name': 'Attacker',
          'userRole': 'admin',
          'is_onboarded': true,
        });
        final localPrefs = await SharedPreferences.getInstance();
        final localService = LocalStorageService(localPrefs);

        // Server Custom Claims state: customer
        const customerIdentity = CurrentIdentity(
          uid: 'uid_cust_real',
          phone: '9876543210',
          authStatus: AuthStatus.authenticated,
          role: AuthRole.customer,
          customerId: 'uid_cust_real',
        );

        final router = _buildTestRouter();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              localStorageServiceProvider.overrideWithValue(localService),
              currentIdentityProvider.overrideWithValue(customerIdentity),
            ],
            child: MaterialApp.router(routerConfig: router),
          ),
        );
        await tester.pumpAndSettle();

        // Attempt navigation to /admin
        router.go(AppRoutes.admin);
        await tester.pumpAndSettle();

        // Guard must redirect to home because CurrentIdentity.isAdmin is false
        expect(find.text('Admin Shell View'), findsNothing);
        expect(find.text('Customer Home View'), findsOneWidget);
      });

      testWidgets('Conflict: Phone matches shopkeeper map, but Custom Claims is customer -> access denied', (tester) async {
        // Storage has Rajat Shopkeeper phone
        SharedPreferences.setMockInitialValues({
          'user_phone': '8000383993',
          'user_name': 'Rajat Vendor Phone',
          'is_onboarded': true,
        });
        final localPrefs = await SharedPreferences.getInstance();
        final localService = LocalStorageService(localPrefs);

        // But token custom claim says customer (e.g. revoked or unprovisioned)
        const customerIdentity = CurrentIdentity(
          uid: 'uid_revoked_shop',
          phone: '8000383993',
          authStatus: AuthStatus.authenticated,
          role: AuthRole.customer,
          customerId: 'uid_revoked_shop',
        );

        final router = _buildTestRouter();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              localStorageServiceProvider.overrideWithValue(localService),
              currentIdentityProvider.overrideWithValue(customerIdentity),
            ],
            child: MaterialApp.router(routerConfig: router),
          ),
        );
        await tester.pumpAndSettle();

        // Attempt navigation to /shopkeeper
        router.go(AppRoutes.shopkeeper);
        await tester.pumpAndSettle();

        // Guard redirects to /home because CurrentIdentity.isShopkeeper is false
        expect(find.text('Shopkeeper Shell View'), findsNothing);
        expect(find.text('Customer Home View'), findsOneWidget);
      });

      test('Conflict: LocalStorage customerId = cust_someone_else, authenticated UID = UID_A -> authoritative customer identity = UID_A', () async {
        // Attacker or stale session wrote an unauthorized customerId into local storage
        SharedPreferences.setMockInitialValues({
          'user_phone': '9876543210',
          'user_name': 'Attacker',
          'customer_id': 'cust_someone_else',
          'is_onboarded': true,
        });

        // Authenticated session has Firebase UID = 'UID_A'
        final user = _FakeFirebaseUser(uid: 'UID_A', phoneNumber: '+919876543210');
        // Canonical customer claims: strictly { role: 'customer' }
        final claims = <String, dynamic>{'role': 'customer'};

        final identity = AuthService.mapUserToIdentity(user, claims);
        // Security Invariant: Authoritative customerId MUST be the Firebase UID ('UID_A')
        expect(identity.customerId, equals('UID_A'));
        expect(identity.uid, equals('UID_A'));
        expect(identity.customerId, isNot(equals('cust_someone_else')));
      });
    });

    // ─── 5. Role Revocation & Account Deactivation ────────────────────────────
    group('5. Role Revocation & Account Deactivation', () {
      test('Admin demoted to customer loses admin privileges immediately upon claim refresh', () {
        final user = _FakeFirebaseUser(uid: 'uid_admin_revoked');
        
        // Initial admin state
        final adminClaims = <String, dynamic>{'role': 'admin'};
        final initialIdentity = AuthService.mapUserToIdentity(user, adminClaims);
        expect(initialIdentity.isAdmin, isTrue);

        // Backend revokes admin role, setting role to customer
        final revokedClaims = <String, dynamic>{'role': 'customer'};
        final updatedIdentity = AuthService.mapUserToIdentity(user, revokedClaims);
        expect(updatedIdentity.isAdmin, isFalse);
        expect(updatedIdentity.isCustomer, isTrue);
        expect(updatedIdentity.role, equals(AuthRole.customer));
      });

      test('Shopkeeper revoked loses shopkeeper role and shopId upon claim refresh', () {
        final user = _FakeFirebaseUser(uid: 'uid_vendor_revoked');
        
        // Initial shopkeeper state
        final shopClaims = <String, dynamic>{'role': 'shopkeeper', 'shopId': 'rajat_shop'};
        final initialIdentity = AuthService.mapUserToIdentity(user, shopClaims);
        expect(initialIdentity.isShopkeeper, isTrue);
        expect(initialIdentity.shopId, equals('rajat_shop'));

        // Backend revokes shopkeeper role to customer
        final revokedClaims = <String, dynamic>{'role': 'customer'};
        final updatedIdentity = AuthService.mapUserToIdentity(user, revokedClaims);
        expect(updatedIdentity.isShopkeeper, isFalse);
        expect(updatedIdentity.shopId, isNull);
        expect(updatedIdentity.role, equals(AuthRole.customer));
      });

      test('Account deactivation via status claim strips all roles and sets deactivated status', () {
        final user = _FakeFirebaseUser(uid: 'uid_deactivated_user');
        final claims = <String, dynamic>{
          'role': 'customer',
          'status': 'deactivated',
        };

        final identity = AuthService.mapUserToIdentity(user, claims);
        expect(identity.accountStatus, equals(AccountStatus.deactivated));
        expect(identity.authStatus, equals(AuthStatus.deactivated));
        expect(identity.role, equals(AuthRole.none));
        expect(identity.isActive, isFalse);
        expect(identity.isCustomer, isFalse);
        expect(identity.isShopkeeper, isFalse);
        expect(identity.isAdmin, isFalse);
      });

      test('Account deactivation via role: deactivated sets deactivated state and AuthRole.none', () {
        final user = _FakeFirebaseUser(uid: 'uid_deactivated_role');
        final claims = <String, dynamic>{
          'role': 'deactivated',
        };

        final identity = AuthService.mapUserToIdentity(user, claims);
        expect(identity.accountStatus, equals(AccountStatus.deactivated));
        expect(identity.authStatus, equals(AuthStatus.deactivated));
        expect(identity.role, equals(AuthRole.none));
        expect(identity.isActive, isFalse);
      });
    });
  });
}
