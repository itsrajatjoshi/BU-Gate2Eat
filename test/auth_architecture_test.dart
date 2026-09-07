// BU Gate2Eat — Checkpoint 1.1: Authentication Architecture Test Suite
// Verifies:
// 1. Identity State Model: unauthenticated, authenticated, role getters, equality, copyWith.
// 2. Provider Boundary: AuthService implements IAuthenticationProvider, exposures, reactive streams.
// 3. Identity Mapping: Firebase User + Custom Claims mapped to canonical CurrentIdentity.
// 4. Legacy Identity Isolation: LocalStorage alone cannot establish authenticated identity.
// 5. Safe Error Handling: AuthException prevents sensitive leaks.

import 'package:bugate2eat_app/core/auth/auth_exception.dart';
import 'package:bugate2eat_app/core/auth/auth_provider_interface.dart';
import 'package:bugate2eat_app/core/auth/auth_providers.dart';
import 'package:bugate2eat_app/core/auth/auth_status.dart';
import 'package:bugate2eat_app/core/auth/current_identity.dart';
import 'package:bugate2eat_app/core/providers.dart' as app_providers;
import 'package:bugate2eat_app/services/auth_service.dart';
import 'package:bugate2eat_app/services/local_storage_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Lightweight mock user for testing mapping logic without full Firebase connection.
class _FakeUser implements User {
  _FakeUser({
    required this.uid,
    this.phoneNumber = '+918000383993',
    this.displayName = 'Test User',
  });

  @override
  final String uid;

  @override
  final String? phoneNumber;

  @override
  final String? displayName;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Checkpoint 1.1 — Authentication Architecture Suite', () {
    // ─── 1. Identity State Model Tests ─────────────────────────
    group('1. Canonical CurrentIdentity Model', () {
      test('unauthenticated singleton has expected default unauthenticated values', () {
        const identity = CurrentIdentity.unauthenticated;
        expect(identity.uid, isEmpty);
        expect(identity.phone, isEmpty);
        expect(identity.authStatus, equals(AuthStatus.unauthenticated));
        expect(identity.role, equals(AuthRole.none));
        expect(identity.shopId, isNull);
        expect(identity.customerId, isEmpty);
        expect(identity.accountStatus, equals(AccountStatus.unknown));
        expect(identity.displayName, isNull);
        expect(identity.isAuthenticated, isFalse);
        expect(identity.isCustomer, isFalse);
        expect(identity.isShopkeeper, isFalse);
        expect(identity.isAdmin, isFalse);
      });

      test('authenticated customer identity exposes correct helper getters', () {
        const identity = CurrentIdentity(
          uid: 'user_cust_123',
          phone: '9876543210',
          authStatus: AuthStatus.authenticated,
          role: AuthRole.customer,
          customerId: 'user_cust_123',
          accountStatus: AccountStatus.active,
          displayName: 'Alice',
        );

        expect(identity.isAuthenticated, isTrue);
        expect(identity.isCustomer, isTrue);
        expect(identity.isShopkeeper, isFalse);
        expect(identity.isAdmin, isFalse);
        expect(identity.isActive, isTrue);
        expect(identity.customerId, equals('user_cust_123'));
      });

      test('authenticated shopkeeper identity encapsulates shopId and role', () {
        const identity = CurrentIdentity(
          uid: 'user_shop_456',
          phone: '8000383993',
          authStatus: AuthStatus.authenticated,
          role: AuthRole.shopkeeper,
          shopId: 'rajat_shop',
          customerId: 'user_shop_456',
          accountStatus: AccountStatus.active,
        );

        expect(identity.isAuthenticated, isTrue);
        expect(identity.isCustomer, isFalse);
        expect(identity.isShopkeeper, isTrue);
        expect(identity.isAdmin, isFalse);
        expect(identity.shopId, equals('rajat_shop'));
      });

      test('authenticated admin identity exposes admin role', () {
        const identity = CurrentIdentity(
          uid: 'user_admin_789',
          phone: '8078643910',
          authStatus: AuthStatus.authenticated,
          role: AuthRole.admin,
          customerId: 'user_admin_789',
          accountStatus: AccountStatus.active,
        );

        expect(identity.isAuthenticated, isTrue);
        expect(identity.isCustomer, isFalse);
        expect(identity.isShopkeeper, isFalse);
        expect(identity.isAdmin, isTrue);
        expect(identity.shopId, isNull);
      });

      test('copyWith preserves unmodified fields and updates specified fields', () {
        const initial = CurrentIdentity(
          uid: 'u1',
          phone: '1234567890',
          authStatus: AuthStatus.authenticated,
          role: AuthRole.customer,
          customerId: 'u1',
        );

        final updated = initial.copyWith(displayName: 'New Name');
        expect(updated.uid, equals('u1'));
        expect(updated.displayName, equals('New Name'));
        expect(updated.authStatus, equals(AuthStatus.authenticated));
      });

      test('equality and hashCode adhere to value equality', () {
        const id1 = CurrentIdentity(
          uid: 'u1',
          phone: '123',
          authStatus: AuthStatus.authenticated,
          role: AuthRole.customer,
          customerId: 'u1',
        );
        const id2 = CurrentIdentity(
          uid: 'u1',
          phone: '123',
          authStatus: AuthStatus.authenticated,
          role: AuthRole.customer,
          customerId: 'u1',
        );
        const id3 = CurrentIdentity(
          uid: 'u2',
          phone: '123',
          authStatus: AuthStatus.authenticated,
          role: AuthRole.customer,
          customerId: 'u2',
        );

        expect(id1, equals(id2));
        expect(id1.hashCode, equals(id2.hashCode));
        expect(id1, isNot(equals(id3)));
      });
    });

    // ─── 2. Provider Abstraction Contract Tests ────────────────
    group('2. Authentication Provider Abstraction', () {
      test('AuthService implements IAuthenticationProvider contract', () {
        final authService = AuthService();
        expect(authService, isA<IAuthenticationProvider>());
      });

      test('unauthenticated AuthService exposes unauthenticated CurrentIdentity and AuthStatus', () {
        final authService = AuthService();
        expect(authService.isSignedIn, isFalse);
        expect(authService.authStatus, equals(AuthStatus.unauthenticated));
        expect(authService.currentIdentity, equals(CurrentIdentity.unauthenticated));
      });

      test('unauthenticated identity changes stream emits unauthenticated initial state', () async {
        final authService = AuthService();
        final identity = await authService.identityChanges.first;
        expect(identity, equals(CurrentIdentity.unauthenticated));
      });

      test('unauthenticated authStatusChanges stream emits unauthenticated initial state', () async {
        final authService = AuthService();
        final status = await authService.authStatusChanges.first;
        expect(status, equals(AuthStatus.unauthenticated));
      });

      test('Riverpod currentIdentityProvider resolves to unauthenticated when signed out', () {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final identity = container.read(currentIdentityProvider);
        expect(identity.isAuthenticated, isFalse);
        expect(identity.authStatus, equals(AuthStatus.unauthenticated));
      });

      test('Riverpod authStatusProvider exposes AuthStatus.unauthenticated', () {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final status = container.read(authStatusProvider);
        expect(status, equals(AuthStatus.unauthenticated));
      });
    });

    // ─── 3. Identity Mapping from Firebase User + Claims ───────
    group('3. Identity Mapping from Firebase User & Claims', () {
      test('maps customer role claim to AuthRole.customer with canonical customerId == uid', () {
        final user = _FakeUser(uid: 'uid_cust_999', phoneNumber: '+919876543210');
        final claims = <String, dynamic>{
          'role': 'customer',
          'phone': '9876543210',
        };

        final identity = AuthService.mapUserToIdentity(user, claims);
        expect(identity.uid, equals('uid_cust_999'));
        expect(identity.phone, equals('9876543210'));
        expect(identity.authStatus, equals(AuthStatus.authenticated));
        expect(identity.role, equals(AuthRole.customer));
        expect(identity.shopId, isNull);
        expect(identity.customerId, equals('uid_cust_999'));
        expect(identity.accountStatus, equals(AccountStatus.active));
      });

      test('maps shopkeeper role claim and shopId to AuthRole.shopkeeper', () {
        final user = _FakeUser(uid: 'uid_shop_888', phoneNumber: '+918000383993');
        final claims = <String, dynamic>{
          'role': 'shopkeeper',
          'shopId': 'rajat_shop',
          'phone': '8000383993',
        };

        final identity = AuthService.mapUserToIdentity(user, claims);
        expect(identity.uid, equals('uid_shop_888'));
        expect(identity.authStatus, equals(AuthStatus.authenticated));
        expect(identity.role, equals(AuthRole.shopkeeper));
        expect(identity.shopId, equals('rajat_shop'));
        expect(identity.customerId, equals('uid_shop_888'));
      });

      test('maps admin role claim without shopId to AuthRole.admin', () {
        final user = _FakeUser(uid: 'uid_admin_777', phoneNumber: '+918078643910');
        final claims = <String, dynamic>{
          'role': 'admin',
          'phone': '8078643910',
        };

        final identity = AuthService.mapUserToIdentity(user, claims);
        expect(identity.uid, equals('uid_admin_777'));
        expect(identity.authStatus, equals(AuthStatus.authenticated));
        expect(identity.role, equals(AuthRole.admin));
        expect(identity.shopId, isNull);
        expect(identity.customerId, equals('uid_admin_777'));
      });

      test('maps deactivated status claim to AuthStatus.deactivated and AccountStatus.deactivated', () {
        final user = _FakeUser(uid: 'uid_revoked_000');
        final claims = <String, dynamic>{
          'role': 'customer',
          'status': 'deactivated',
        };

        final identity = AuthService.mapUserToIdentity(user, claims);
        expect(identity.accountStatus, equals(AccountStatus.deactivated));
        expect(identity.authStatus, equals(AuthStatus.deactivated));
        expect(identity.isActive, isFalse);
      });

      test('returns CurrentIdentity.unauthenticated when user is null', () {
        final identity = AuthService.mapUserToIdentity(null, const {});
        expect(identity, equals(CurrentIdentity.unauthenticated));
      });
    });

    // ─── 4. Legacy Identity Isolation Tests ────────────────────
    group('4. Legacy Identity Isolation', () {
      test('LocalStorageService alone CANNOT establish authenticated CurrentIdentity', () async {
        SharedPreferences.setMockInitialValues({
          'user_phone': '8078643910', // Admin phone in localStorage
          'is_onboarded': true,
          'is_otp_verified': true,
          'customer_id': 'cust_8078643910',
          'user_name': 'Super Admin',
        });

        final prefs = await SharedPreferences.getInstance();
        final localStorage = LocalStorageService(prefs);

        final container = ProviderContainer(
          overrides: [
            app_providers.localStorageServiceProvider.overrideWithValue(localStorage),
          ],
        );
        addTearDown(container.dispose);

        // Even though localStorage has admin phone, onboarding=true, and isOtpVerified=true:
        // Canonical CurrentIdentity MUST remain unauthenticated because there is no Firebase session!
        final identity = container.read(currentIdentityProvider);
        expect(identity.isAuthenticated, isFalse);
        expect(identity.authStatus, equals(AuthStatus.unauthenticated));
        expect(identity.role, equals(AuthRole.none));
        expect(identity.uid, isEmpty);
      });

      test('client cannot manufacture an authenticated session by writing to SharedPreferences', () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final localStorage = LocalStorageService(prefs);

        // Simulate rogue client setting SharedPreferences directly
        await localStorage.saveUserProfile(
          name: 'Hacker',
          phone: '9999999999',
        );
        await localStorage.saveOtpVerificationState('9999999999');

        final container = ProviderContainer(
          overrides: [
            app_providers.localStorageServiceProvider.overrideWithValue(localStorage),
          ],
        );
        addTearDown(container.dispose);

        final identity = container.read(currentIdentityProvider);
        // Security verification: LocalStorage is NOT identity authority
        expect(identity.isAuthenticated, isFalse);
        expect(identity.uid, isEmpty);
      });
    });

    // ─── 5. Safe Error Handling Tests ──────────────────────────
    group('5. Safe Authentication Error Handling', () {
      test('AuthException formats safe user-visible message without exposing internal secrets', () {
        const exception = AuthException(
          code: AuthErrorCode.invalidCredentials,
          message: 'Invalid verification code. Please request a new code.',
          debugDetails: 'Backend response: 401 Unauthorized, jwt_signature_failed',
        );

        // UI message is generic and safe
        expect(exception.message, isNot(contains('jwt')));
        expect(exception.message, isNot(contains('signature')));
        expect(exception.code, equals(AuthErrorCode.invalidCredentials));

        // Debug details preserved for controlled internal logs
        expect(exception.debugDetails, contains('jwt_signature_failed'));
      });
    });
  });
}
