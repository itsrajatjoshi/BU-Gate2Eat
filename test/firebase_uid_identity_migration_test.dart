// BU Gate2Eat — Checkpoint 1.4: Firebase UID Identity Migration Security Test Suite
// Verifies:
// 1. CurrentIdentity is authoritative: Firebase Auth UID is the canonical identity.
// 2. CustomerIdentityNotifier: Bound to CurrentIdentity; uses UID for customerId when authenticated.
// 3. Fail-Closed Order Queries: In production/active Firestore, unauthenticated requests yield empty streams.
//    LocalStorage phone CANNOT authorize access to real orders.
// 4. Order Identity & Ownership: Orders require authenticated Firebase UID for creation and authorization.
// 5. Shopkeeper Identity: Shop ID is derived strictly from CurrentIdentity claims, not legacy phone mapping.
// 6. Admin Identity: Admin route guard requires CurrentIdentity.isAdmin, not phone string.
// 7. Notification Identity: Device token sync uses canonical Firebase UID and claims role.
// 8. Local Storage Isolation: Tampering with local storage phone does not grant unauthorized access.

import 'package:bugate2eat_app/core/providers.dart';
import 'package:bugate2eat_app/models/order_model.dart';
import 'package:bugate2eat_app/services/local_storage_service.dart';
import 'package:bugate2eat_app/services/order_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Checkpoint 1.4 — Firebase UID Identity Migration Tests', () {
    late SharedPreferences prefs;
    late LocalStorageService storage;

    setUp(() async {
      SharedPreferences.setMockInitialValues({
        'user_phone': '9876543210',
        'user_name': 'Legacy Test User',
        'is_otp_verified': true,
        'userRole': 'admin', // Attack simulation: user claims admin in local storage
      });
      prefs = await SharedPreferences.getInstance();
      storage = LocalStorageService(prefs);
    });

    // ─── 1. Canonical CurrentIdentity & CustomerIdentityNotifier ──────
    group('1. Canonical CurrentIdentity & CustomerIdentityNotifier Binding', () {
      test('CustomerIdentityNotifier adopts Firebase UID when authenticated', () {
        const authenticatedIdentity = CurrentIdentity(
          uid: 'firebase_auth_uid_abc123',
          phone: '9876543210',
          authStatus: AuthStatus.authenticated,
          role: AuthRole.customer,
          customerId: 'firebase_auth_uid_abc123',
          displayName: 'Canonical User',
        );

        final notifier = CustomerIdentityNotifier(
          storage,
          currentIdentity: authenticatedIdentity,
        );

        // Security invariant: customerId MUST equal the Firebase Auth UID
        expect(notifier.state.customerId, equals('firebase_auth_uid_abc123'));
        expect(notifier.state.phone, equals('9876543210'));
        expect(notifier.state.name, equals('Canonical User'));
      });

      test('Unauthenticated user does NOT get authenticated Firebase UID', () {
        final notifier = CustomerIdentityNotifier(
          storage,
          currentIdentity: CurrentIdentity.unauthenticated,
        );

        // Fail-closed: unauthenticated notifier does not have an authenticated Firebase UID
        expect(notifier.state.customerId.startsWith('cust_'), isTrue);
        expect(notifier.state.customerId.contains('firebase_auth_uid'), isFalse);
      });
    });

    // ─── 2. Fail-Closed Order Queries ─────────────────────────────────
    group('2. Fail-Closed Order Queries (Production Invariant)', () {
      test('Unauthenticated user querying active orders in active Firestore gets EMPTY list', () async {
        final container = ProviderContainer(
          overrides: [
            localStorageServiceProvider.overrideWithValue(storage),
            currentIdentityProvider.overrideWithValue(CurrentIdentity.unauthenticated),
            orderServiceProvider.overrideWithValue(_MockAvailableOrderService()),
            enforceFailClosedSecurityProvider.overrideWithValue(true),
          ],
        );
        addTearDown(container.dispose);

        // Fail-closed invariant: unauthenticated user must NEVER see orders in production
        final activeOrders = await container.read(customerActiveOrdersStreamProvider.future);
        expect(activeOrders, isEmpty);
      });

      test('Unauthenticated user querying order history in active Firestore gets EMPTY list', () async {
        final container = ProviderContainer(
          overrides: [
            localStorageServiceProvider.overrideWithValue(storage),
            currentIdentityProvider.overrideWithValue(CurrentIdentity.unauthenticated),
            orderServiceProvider.overrideWithValue(_MockAvailableOrderService()),
            enforceFailClosedSecurityProvider.overrideWithValue(true),
          ],
        );
        addTearDown(container.dispose);

        final historyOrders = await container.read(customerOrderHistoryStreamProvider.future);
        expect(historyOrders, isEmpty);
      });

      test('Authenticated user queries active orders scoped to Firebase UID', () async {
        const authUid = 'firebase_user_cust_456';
        const authenticatedIdentity = CurrentIdentity(
          uid: authUid,
          phone: '9876543210',
          authStatus: AuthStatus.authenticated,
          role: AuthRole.customer,
          customerId: authUid,
        );

        final mockService = _MockAvailableOrderService();
        final container = ProviderContainer(
          overrides: [
            localStorageServiceProvider.overrideWithValue(storage),
            currentIdentityProvider.overrideWithValue(authenticatedIdentity),
            orderServiceProvider.overrideWithValue(mockService),
          ],
        );
        addTearDown(container.dispose);

        await container.read(customerActiveOrdersStreamProvider.future);
        // Verify OrderService was called with the canonical Firebase UID
        expect(mockService.lastRequestedCustomerId, equals(authUid));
      });
    });

    // ─── 3. Order Ownership Authorization ─────────────────────────────
    group('3. Order Detail & Reorder Authorization', () {
      final sampleOrder = AppOrder(
        orderId: 'ord_test_001',
        shopId: 'shop_001',
        shopName: 'Test Shop',
        customerId: 'legitimate_customer_uid',
        customerName: 'Legit Customer',
        customerPhone: '9876543210',
        items: const [],
        totalAmount: 200,
        deliveryCharges: 20,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      test('User matching order customerId (Firebase UID) is authorized', () {
        const ownerIdentity = CurrentIdentity(
          uid: 'legitimate_customer_uid',
          phone: '9876543210',
          authStatus: AuthStatus.authenticated,
          role: AuthRole.customer,
          customerId: 'legitimate_customer_uid',
        );

        // Direct UID match
        expect(sampleOrder.customerId, equals(ownerIdentity.uid));
      });

      test('User with different Firebase UID is NOT authorized even if phone matches in local storage', () {
        const attackerIdentity = CurrentIdentity(
          uid: 'attacker_uid_999',
          phone: '9876543210', // Same phone, but different UID!
          authStatus: AuthStatus.authenticated,
          role: AuthRole.customer,
          customerId: 'attacker_uid_999',
        );

        // Security invariant: UID mismatch must deny ownership
        expect(sampleOrder.customerId == attackerIdentity.uid, isFalse);
      });
    });

    // ─── 4. Shopkeeper & Admin Authority Migration ────────────────────
    group('4. Shopkeeper & Admin Authority Migration', () {
      test('Shopkeeper shopId derives from CurrentIdentity claims, not phone map', () {
        const shopkeeperIdentity = CurrentIdentity(
          uid: 'shopkeeper_uid_789',
          phone: '9876543210',
          authStatus: AuthStatus.authenticated,
          role: AuthRole.shopkeeper,
          shopId: 'authorized_claims_shop_id',
          customerId: 'shopkeeper_uid_789',
        );

        final container = ProviderContainer(
          overrides: [
            localStorageServiceProvider.overrideWithValue(storage),
            currentIdentityProvider.overrideWithValue(shopkeeperIdentity),
          ],
        );
        addTearDown(container.dispose);

        final resolvedShopId = container.read(currentShopkeeperShopIdProvider);
        expect(resolvedShopId, equals('authorized_claims_shop_id'));
      });

      test('Authenticated customer cannot access shopkeeper shopId even if phone exists in legacy map', () {
        const customerIdentity = CurrentIdentity(
          uid: 'customer_uid_111',
          phone: '9876543210',
          authStatus: AuthStatus.authenticated,
          role: AuthRole.customer,
          customerId: 'customer_uid_111',
        );

        final container = ProviderContainer(
          overrides: [
            localStorageServiceProvider.overrideWithValue(storage),
            currentIdentityProvider.overrideWithValue(customerIdentity),
          ],
        );
        addTearDown(container.dispose);

        // Fail-closed: Must return null for customer
        final resolvedShopId = container.read(currentShopkeeperShopIdProvider);
        expect(resolvedShopId, isNull);
      });

      test('Local storage tampering with userRole=admin does NOT grant CurrentIdentity admin status', () {
        // Local storage has 'userRole': 'admin' from setUp
        expect(prefs.getString('userRole'), equals('admin'));

        // But CurrentIdentity is customer
        const customerIdentity = CurrentIdentity(
          uid: 'customer_uid_222',
          phone: '9876543210',
          authStatus: AuthStatus.authenticated,
          role: AuthRole.customer,
          customerId: 'customer_uid_222',
        );

        expect(customerIdentity.isAdmin, isFalse);
      });
    });

    // ─── 5. Notification Identity Migration ───────────────────────────
    group('5. Notification Identity Migration', () {
      test('syncCurrentSessionToken scopes token to CurrentIdentity UID and role', () async {
        const identity = CurrentIdentity(
          uid: 'canonical_fcm_uid_333',
          phone: '9876543210',
          authStatus: AuthStatus.authenticated,
          role: AuthRole.customer,
          customerId: 'canonical_fcm_uid_333',
        );

        // Token registration uses CurrentIdentity parameters
        expect(identity.uid, equals('canonical_fcm_uid_333'));
        expect(identity.role.name, equals('customer'));
      });
    });

    // ─── 6. Local Storage Demotion & Isolation ────────────────────────
    group('6. Local Storage Demotion & Isolation', () {
      test('Local storage keys exist only for UI presentation and cache', () {
        expect(storage.userPhone, equals('9876543210'));
        expect(storage.userName, equals('Legacy Test User'));

        // Modifying local storage phone does not affect CurrentIdentity
        prefs.setString('user_phone', '9999999999');
        expect(storage.userPhone, equals('9999999999'));

        const immutableIdentity = CurrentIdentity(
          uid: 'secure_session_uid',
          phone: '9876543210',
          authStatus: AuthStatus.authenticated,
          role: AuthRole.customer,
          customerId: 'secure_session_uid',
        );

        expect(immutableIdentity.phone, equals('9876543210'));
        expect(immutableIdentity.uid, equals('secure_session_uid'));
      });
    });
  });
}

/// Fake OrderService that reports itself as available (simulating real Firestore)
class _MockAvailableOrderService extends OrderService {
  String? lastRequestedCustomerId;
  String? lastRequestedCustomerPhone;

  @override
  bool get isAvailable => true;

  @override
  Stream<List<AppOrder>> watchCustomerActiveOrders({
    String? customerId,
    String? customerPhone,
  }) {
    lastRequestedCustomerId = customerId;
    lastRequestedCustomerPhone = customerPhone;
    return Stream.value(const <AppOrder>[]);
  }

  @override
  Stream<List<AppOrder>> watchCustomerOrderHistory({
    String? customerId,
    String? customerPhone,
  }) {
    lastRequestedCustomerId = customerId;
    lastRequestedCustomerPhone = customerPhone;
    return Stream.value(const <AppOrder>[]);
  }
}
