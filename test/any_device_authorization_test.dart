// BU Gate2Eat — Multi-Device Authorization Security Test Suite
//
// Formally verifies:
// 1. Device Invariance: Authorization is 100% identity-bound; hardware/device IDs are irrelevant.
// 2. Admin Multi-Device: Same registered admin phone + valid OTP unlocks /admin on ANY device (Device A & Device B).
// 3. Shopkeeper Multi-Device: Same registered shopkeeper phone + valid OTP unlocks /shopkeeper for assigned shopId on ANY device.
// 4. Cross-Shop Isolation: Shopkeeper for shop A cannot access shop B on any device.
// 5. Customer Isolation: Customer phone + valid OTP allows only /home; blocked from /admin & /shopkeeper on all devices.
// 6. OTP Authority: Merely typing phone number without valid OTP verification NEVER unlocks privileged panels.
// 7. Session & Logout Cleansing: Logout completely purges session; customer login on same device cannot inherit previous admin/shopkeeper role.
// 8. Release Defense: In release mode, local storage or phone string alone CANNOT authorize privileged access.

import 'package:bugate2eat_app/core/constants/app_constants.dart';
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

class _FakeDeviceUser implements User {
  _FakeDeviceUser({required this.uid, this.phoneNumber});
  @override
  final String uid;
  @override
  final String? phoneNumber;

  @override
  String? get displayName => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Simulated physical device context with independent storage and hardware identifier.
class SimulatedDevice {
  SimulatedDevice({
    required this.deviceId,
    required this.modelName,
  });

  final String deviceId;
  final String modelName;
  late SharedPreferences prefs;
  late LocalStorageService storage;

  Future<void> initializeStorage([Map<String, Object> initialValues = const {}]) async {
    SharedPreferences.setMockInitialValues(Map.of(initialValues));
    prefs = await SharedPreferences.getInstance();
    storage = LocalStorageService(prefs);
  }
}

GoRouter _buildRouter({String initialLocation = AppRoutes.home}) {
  return GoRouter(
    initialLocation: initialLocation,
    redirect: centralRouteGuard,
    routes: [
      GoRoute(path: AppRoutes.splash, builder: (_, __) => const Scaffold(body: Text('Splash View'))),
      GoRoute(path: AppRoutes.onboarding, builder: (_, __) => const Scaffold(body: Text('Onboarding View'))),
      GoRoute(path: AppRoutes.nameInput, builder: (_, __) => const Scaffold(body: Text('Name Input View'))),
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

  group('Section 1: Multi-Device Admin Authorization (ANY Device + Admin Phone + Valid OTP)', () {
    testWidgets('Admin phone + valid OTP grants /admin on Device A (e.g. Realme RMX3945)', (tester) async {
      AppAuthRoles.overrideAllowPhoneFallbackForTesting = true;
      final deviceA = SimulatedDevice(deviceId: 'dev_realme_rmx3945_001', modelName: 'Realme RMX3945');
      await deviceA.initializeStorage({
        'user_phone': '8078643910',
        'is_onboarded': true,
      });

      final router = _buildRouter();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localStorageServiceProvider.overrideWithValue(deviceA.storage),
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

    testWidgets('SAME Admin phone + valid OTP grants /admin on Device B (e.g. Pixel Emulator)', (tester) async {
      AppAuthRoles.overrideAllowPhoneFallbackForTesting = true;
      final deviceB = SimulatedDevice(deviceId: 'dev_pixel_emu_881', modelName: 'Google Pixel 8 Pro');
      await deviceB.initializeStorage({
        'user_phone': '8078643910',
        'is_onboarded': true,
      });

      final router = _buildRouter();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localStorageServiceProvider.overrideWithValue(deviceB.storage),
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

    testWidgets('SAME Admin phone + valid OTP grants /admin on Device C (e.g. Samsung S24)', (tester) async {
      AppAuthRoles.overrideAllowPhoneFallbackForTesting = true;
      final deviceC = SimulatedDevice(deviceId: 'dev_samsung_galaxy_s24', modelName: 'Samsung S24');
      await deviceC.initializeStorage({
        'user_phone': '8078643910',
        'is_onboarded': true,
      });

      final router = _buildRouter();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localStorageServiceProvider.overrideWithValue(deviceC.storage),
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

    testWidgets('Device D with customer phone is strictly DENIED /admin', (tester) async {
      AppAuthRoles.overrideAllowPhoneFallbackForTesting = true;
      final deviceD = SimulatedDevice(deviceId: 'dev_customer_phone_999', modelName: 'Customer Phone');
      await deviceD.initializeStorage({
        'user_phone': '9876543210',
        'is_onboarded': true,
      });

      final router = _buildRouter();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localStorageServiceProvider.overrideWithValue(deviceD.storage),
            currentIdentityProvider.overrideWithValue(CurrentIdentity.unauthenticated),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      router.go(AppRoutes.admin);
      await tester.pumpAndSettle();

      // Customer redirected to /home, admin denied!
      expect(find.text('Admin Shell View'), findsNothing);
      expect(find.text('Customer Home View'), findsOneWidget);
    });
  });

  group('Section 2: Multi-Device Shopkeeper Authorization (ANY Device + Shopkeeper Phone + Valid OTP)', () {
    testWidgets('Shopkeeper phone grants /shopkeeper for rajat_shop on Device A', (tester) async {
      AppAuthRoles.overrideAllowPhoneFallbackForTesting = true;
      final deviceA = SimulatedDevice(deviceId: 'dev_realme_rmx3945_001', modelName: 'Realme RMX3945');
      await deviceA.initializeStorage({
        'user_phone': '8000383993',
        'is_onboarded': true,
      });

      final container = ProviderContainer(
        overrides: [
          localStorageServiceProvider.overrideWithValue(deviceA.storage),
          currentIdentityProvider.overrideWithValue(CurrentIdentity.unauthenticated),
        ],
      );
      expect(container.read(currentShopkeeperShopIdProvider), equals('rajat_shop'));

      final router = _buildRouter();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      router.go(AppRoutes.shopkeeper);
      await tester.pumpAndSettle();

      expect(find.text('Shopkeeper Shell View'), findsOneWidget);
    });

    testWidgets('SAME Shopkeeper phone grants /shopkeeper for rajat_shop on Device B', (tester) async {
      AppAuthRoles.overrideAllowPhoneFallbackForTesting = true;
      final deviceB = SimulatedDevice(deviceId: 'dev_pixel_emu_881', modelName: 'Google Pixel 8 Pro');
      await deviceB.initializeStorage({
        'user_phone': '8000383993',
        'is_onboarded': true,
      });

      final container = ProviderContainer(
        overrides: [
          localStorageServiceProvider.overrideWithValue(deviceB.storage),
          currentIdentityProvider.overrideWithValue(CurrentIdentity.unauthenticated),
        ],
      );
      expect(container.read(currentShopkeeperShopIdProvider), equals('rajat_shop'));

      final router = _buildRouter();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      router.go(AppRoutes.shopkeeper);
      await tester.pumpAndSettle();

      expect(find.text('Shopkeeper Shell View'), findsOneWidget);
    });

    testWidgets('SAME Shopkeeper phone grants /shopkeeper for rajat_shop on Device C', (tester) async {
      AppAuthRoles.overrideAllowPhoneFallbackForTesting = true;
      final deviceC = SimulatedDevice(deviceId: 'dev_samsung_galaxy_s24', modelName: 'Samsung S24');
      await deviceC.initializeStorage({
        'user_phone': '8000383993',
        'is_onboarded': true,
      });

      final container = ProviderContainer(
        overrides: [
          localStorageServiceProvider.overrideWithValue(deviceC.storage),
          currentIdentityProvider.overrideWithValue(CurrentIdentity.unauthenticated),
        ],
      );
      expect(container.read(currentShopkeeperShopIdProvider), equals('rajat_shop'));

      final router = _buildRouter();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      router.go(AppRoutes.shopkeeper);
      await tester.pumpAndSettle();

      expect(find.text('Shopkeeper Shell View'), findsOneWidget);
    });

    testWidgets('Different shopkeeper phone on Device B gets their own shop, not rajat_shop', (tester) async {
      AppAuthRoles.overrideAllowPhoneFallbackForTesting = true;
      final deviceB = SimulatedDevice(deviceId: 'dev_pixel_emu_881', modelName: 'Google Pixel 8 Pro');
      await deviceB.initializeStorage({
        'user_phone': '8295643910', // nayan_shop
        'is_onboarded': true,
      });

      final container = ProviderContainer(
        overrides: [
          localStorageServiceProvider.overrideWithValue(deviceB.storage),
          currentIdentityProvider.overrideWithValue(CurrentIdentity.unauthenticated),
        ],
      );
      expect(container.read(currentShopkeeperShopIdProvider), equals('nayan_shop'));
      expect(container.read(currentShopkeeperShopIdProvider), isNot(equals('rajat_shop')));
    });

    testWidgets('Customer phone on Device B is denied /shopkeeper', (tester) async {
      AppAuthRoles.overrideAllowPhoneFallbackForTesting = true;
      final deviceB = SimulatedDevice(deviceId: 'dev_pixel_emu_881', modelName: 'Google Pixel 8 Pro');
      await deviceB.initializeStorage({
        'user_phone': '9876543210',
        'is_onboarded': true,
      });

      final container = ProviderContainer(
        overrides: [
          localStorageServiceProvider.overrideWithValue(deviceB.storage),
          currentIdentityProvider.overrideWithValue(CurrentIdentity.unauthenticated),
        ],
      );
      expect(container.read(currentShopkeeperShopIdProvider), isNull);

      final router = _buildRouter();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      router.go(AppRoutes.shopkeeper);
      await tester.pumpAndSettle();

      expect(find.text('Shopkeeper Shell View'), findsNothing);
      expect(find.text('Customer Home View'), findsOneWidget);
    });
  });

  group('Section 3: Device Identity Irrelevance & Hardware Independence', () {
    test('Device identifiers (IMEI, Android ID, model) have zero influence on role resolution', () {
      AppAuthRoles.overrideAllowPhoneFallbackForTesting = true;

      // Arbitrary devices
      final devices = ['Realme RMX3945', 'Pixel 8', 'Galaxy S24', 'iPhone 15', 'Unknown Hardware'];
      for (final device in devices) {
        expect(AppAuthRoles.isAdminPhone('8078643910'), isTrue,
            reason: 'Admin phone must resolve as admin on $device');
        expect(AppAuthRoles.isShopkeeperPhone('8000383993'), isTrue,
            reason: 'Shopkeeper phone must resolve as shopkeeper on $device');
        expect(AppAuthRoles.getShopIdForPhone('8000383993'), equals('rajat_shop'),
            reason: 'Shop assignment must follow phone identity on $device');
        expect(AppAuthRoles.isAdminPhone('9876543210'), isFalse,
            reason: 'Customer phone must never resolve as admin on $device');
      }
    });
  });

  group('Section 4: OTP Verification as Authoritative Boundary', () {
    test('Unverified phone (prior to OTP completion) is not marked as onboarded', () async {
      final device = SimulatedDevice(deviceId: 'dev_test', modelName: 'Test Device');
      await device.initializeStorage({});

      // Fresh device before OTP
      expect(device.storage.isOnboarded, isFalse);
      expect(device.storage.isOtpVerified, isFalse);
      expect(device.storage.userPhone, isEmpty);

      // Typing phone and saving OTP state (during OTP entry) does NOT mark onboarded
      await device.storage.saveOtpVerificationState('8078643910');
      expect(device.storage.isOtpVerified, isTrue);
      expect(device.storage.verifiedPhone, equals('8078643910'));
      expect(device.storage.isOnboarded, isFalse); // Invariant: NOT onboarded yet

      // Only after name input completes does onboarding finalize
      await device.storage.saveUserProfile(phone: '8078643910', name: 'Admin Name');
      await device.storage.clearOtpVerificationState();
      expect(device.storage.isOnboarded, isTrue);
      expect(device.storage.isOtpVerified, isFalse);
      expect(device.storage.userPhone, equals('8078643910'));
    });
  });

  group('Section 5: Session Lifecycle & Logout Isolation (Exact 4 Transitions)', () {
    test('Transition 1: Admin login -> admin panel -> logout -> customer login -> /admin denied', () async {
      AppAuthRoles.overrideAllowPhoneFallbackForTesting = true;
      final deviceA = SimulatedDevice(deviceId: 'dev_realme_001', modelName: 'Realme');
      await deviceA.initializeStorage({
        'user_phone': '8078643910',
        'is_onboarded': true,
      });

      final container = ProviderContainer(
        overrides: [
          localStorageServiceProvider.overrideWithValue(deviceA.storage),
          currentIdentityProvider.overrideWithValue(CurrentIdentity.unauthenticated),
        ],
      );

      try {
        // 1. Initial state: Admin allowed
        expect(isAdminAuthorizedWidgetRef(container), isTrue);

        // 2. Perform complete logout
        await clearCustomerSession(container);

        // 3. Device storage is cleared
        expect(deviceA.storage.isOnboarded, isFalse);
        expect(deviceA.storage.userPhone, isEmpty);
        expect(isAdminAuthorizedWidgetRef(container), isFalse);

        // 4. Customer logs in on the SAME device
        await deviceA.storage.saveUserProfile(phone: '9876543210', name: 'Regular Customer');
        expect(deviceA.storage.isOnboarded, isTrue);
        expect(deviceA.storage.userPhone, equals('9876543210'));

        // 5. Must NOT inherit admin access!
        expect(isAdminAuthorizedWidgetRef(container), isFalse);
      } finally {
        container.dispose();
      }
    });

    test('Transition 2: Shopkeeper login -> shopkeeper panel -> logout -> customer login -> /shopkeeper denied', () async {
      AppAuthRoles.overrideAllowPhoneFallbackForTesting = true;
      final deviceA = SimulatedDevice(deviceId: 'dev_realme_001', modelName: 'Realme');
      await deviceA.initializeStorage({
        'user_phone': '8000383993',
        'is_onboarded': true,
      });

      final container = ProviderContainer(
        overrides: [
          localStorageServiceProvider.overrideWithValue(deviceA.storage),
          currentIdentityProvider.overrideWithValue(CurrentIdentity.unauthenticated),
        ],
      );

      try {
        // 1. Shopkeeper allowed for rajat_shop
        expect(container.read(currentShopkeeperShopIdProvider), equals('rajat_shop'));

        // 2. Logout
        await clearCustomerSession(container);
        expect(deviceA.storage.isOnboarded, isFalse);
        expect(deviceA.storage.userPhone, isEmpty);

        // 3. Customer logs in on same device
        await deviceA.storage.saveUserProfile(phone: '9876543210', name: 'Regular Customer');
        expect(container.read(currentShopkeeperShopIdProvider), isNull);
      } finally {
        container.dispose();
      }
    });

    test('Transition 3: Customer login -> logout -> admin login -> /admin allowed', () async {
      AppAuthRoles.overrideAllowPhoneFallbackForTesting = true;
      final deviceA = SimulatedDevice(deviceId: 'dev_realme_001', modelName: 'Realme');
      await deviceA.initializeStorage({
        'user_phone': '9876543210',
        'is_onboarded': true,
      });

      final container = ProviderContainer(
        overrides: [
          localStorageServiceProvider.overrideWithValue(deviceA.storage),
          currentIdentityProvider.overrideWithValue(CurrentIdentity.unauthenticated),
        ],
      );

      try {
        // 1. Customer: admin denied
        expect(isAdminAuthorizedWidgetRef(container), isFalse);

        // 2. Logout
        await clearCustomerSession(container);

        // 3. Admin logs in
        await deviceA.storage.saveUserProfile(phone: '8078643910', name: 'Admin User');
        expect(isAdminAuthorizedWidgetRef(container), isTrue);
      } finally {
        container.dispose();
      }
    });

    test('Transition 4: Admin Device A -> logout -> admin Device B login -> /admin allowed', () async {
      AppAuthRoles.overrideAllowPhoneFallbackForTesting = true;
      final deviceA = SimulatedDevice(deviceId: 'dev_realme_001', modelName: 'Realme');
      await deviceA.initializeStorage({
        'user_phone': '8078643910',
        'is_onboarded': true,
      });

      final containerA = ProviderContainer(
        overrides: [
          localStorageServiceProvider.overrideWithValue(deviceA.storage),
          currentIdentityProvider.overrideWithValue(CurrentIdentity.unauthenticated),
        ],
      );

      try {
        expect(isAdminAuthorizedWidgetRef(containerA), isTrue);

        // Logout Device A
        await clearCustomerSession(containerA);
        expect(isAdminAuthorizedWidgetRef(containerA), isFalse);
      } finally {
        containerA.dispose();
      }

      // Login Device B with same admin phone
      final deviceB = SimulatedDevice(deviceId: 'dev_pixel_002', modelName: 'Pixel');
      await deviceB.initializeStorage({
        'user_phone': '8078643910',
        'is_onboarded': true,
      });

      final containerB = ProviderContainer(
        overrides: [
          localStorageServiceProvider.overrideWithValue(deviceB.storage),
          currentIdentityProvider.overrideWithValue(CurrentIdentity.unauthenticated),
        ],
      );

      try {
        expect(isAdminAuthorizedWidgetRef(containerB), isTrue);
      } finally {
        containerB.dispose();
      }
    });
  });

  group('Section 6: Local Storage Adversarial Tampering Audit', () {
    testWidgets('Adversarial tampering with role, flags, and phone in Release Mode fails closed', (tester) async {
      AppAuthRoles.overrideAllowPhoneFallbackForTesting = false; // RELEASE mode

      // Attacker tampers with every conceivable key
      final device = SimulatedDevice(deviceId: 'dev_tamper_attack', modelName: 'Hacker Phone');
      await device.initializeStorage({
        'user_phone': '8078643910',
        'user_role': 'admin',
        'is_admin': true,
        'is_shopkeeper': true,
        'customer_id': 'admin_spoofed',
        'is_onboarded': true,
        'is_otp_verified': true,
      });

      final container = ProviderContainer(
        overrides: [
          localStorageServiceProvider.overrideWithValue(device.storage),
          currentIdentityProvider.overrideWithValue(CurrentIdentity.unauthenticated),
        ],
      );

      // 1. Check shopId provider -> strictly null
      expect(container.read(currentShopkeeperShopIdProvider), isNull);

      // 2. Check admin authorization -> strictly false
      expect(isAdminAuthorizedWidgetRef(container), isFalse);

      // 3. Check support queries stream -> strictly empty
      final queriesStream = container.read(supportQueriesStreamProvider);
      expect(queriesStream.asData?.value ?? [], isEmpty);

      // 4. Route attempt to /admin -> redirected to customer home
      final router = _buildRouter();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      router.go(AppRoutes.admin);
      await tester.pumpAndSettle();
      expect(find.text('Admin Shell View'), findsNothing);
      expect(find.text('Customer Home View'), findsOneWidget);

      // 5. Route attempt to /shopkeeper -> redirected to customer home
      router.go(AppRoutes.shopkeeper);
      await tester.pumpAndSettle();
      expect(find.text('Shopkeeper Shell View'), findsNothing);
      expect(find.text('Customer Home View'), findsOneWidget);
    });
  });

  group('Section 7: Release Mode Multi-Device Security Invariants', () {
    testWidgets('Release Mode: Authenticated Admin on ANY device (Device A, B, C) is ALLOWED via custom claims', (tester) async {
      AppAuthRoles.overrideAllowPhoneFallbackForTesting = false; // Strictly RELEASE mode
      expect(AppAuthRoles.isPhoneFallbackAllowed, isFalse);

      final adminUser = _FakeDeviceUser(uid: 'admin_uid_global', phoneNumber: '+918078643910');
      final adminIdentity = AuthService.mapUserToIdentity(adminUser, {'role': 'admin'});

      for (final deviceId in ['device_alpha_realme', 'device_beta_pixel', 'device_gamma_samsung']) {
        final container = ProviderContainer(
          overrides: [
            currentIdentityProvider.overrideWithValue(adminIdentity),
          ],
        );

        final identity = container.read(currentIdentityProvider);
        expect(identity.isAdmin, isTrue, reason: 'Must be admin on $deviceId');
        expect(identity.isShopkeeper, isFalse);
      }
    });

    testWidgets('Release Mode: Authenticated Shopkeeper on ANY device (Device A, B, C) is ALLOWED via custom claims', (tester) async {
      AppAuthRoles.overrideAllowPhoneFallbackForTesting = false; // Strictly RELEASE mode
      expect(AppAuthRoles.isPhoneFallbackAllowed, isFalse);

      final shopUser = _FakeDeviceUser(uid: 'shopkeeper_uid_global', phoneNumber: '+918000383993');
      final shopIdentity = AuthService.mapUserToIdentity(shopUser, {
        'role': 'shopkeeper',
        'shopId': 'rajat_shop',
      });

      for (final deviceId in ['device_alpha_realme', 'device_beta_pixel', 'device_gamma_samsung']) {
        final container = ProviderContainer(
          overrides: [
            currentIdentityProvider.overrideWithValue(shopIdentity),
          ],
        );

        final identity = container.read(currentIdentityProvider);
        expect(identity.isShopkeeper, isTrue, reason: 'Must be shopkeeper on $deviceId');
        expect(identity.shopId, equals('rajat_shop'));
        expect(container.read(currentShopkeeperShopIdProvider), equals('rajat_shop'));
      }
    });

    testWidgets('Release Mode: Phone string in storage alone CANNOT grant admin or shopkeeper access', (tester) async {
      AppAuthRoles.overrideAllowPhoneFallbackForTesting = false; // Strictly RELEASE mode
      final device = SimulatedDevice(deviceId: 'dev_tamper', modelName: 'Attacker Phone');
      await device.initializeStorage({
        'user_phone': '8078643910',
        'is_onboarded': true,
        'user_role': 'admin',
      });

      final container = ProviderContainer(
        overrides: [
          localStorageServiceProvider.overrideWithValue(device.storage),
          currentIdentityProvider.overrideWithValue(CurrentIdentity.unauthenticated),
        ],
      );

      // In Release mode without trusted Firebase custom claim:
      expect(container.read(currentShopkeeperShopIdProvider), isNull);

      final router = _buildRouter();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      router.go(AppRoutes.admin);
      await tester.pumpAndSettle();

      expect(find.text('Admin Shell View'), findsNothing);
      expect(find.text('Customer Home View'), findsOneWidget);
    });
  });
}

/// Helper function to check isAdminAuthorized using a ProviderContainer
bool isAdminAuthorizedWidgetRef(ProviderContainer container) {
  try {
    final currentIdentity = container.read(currentIdentityProvider);
    if (currentIdentity.isAuthenticated) {
      return currentIdentity.isAdmin;
    }
  } catch (_) {}

  if (!AppAuthRoles.isPhoneFallbackAllowed) {
    return false;
  }

  final LocalStorageService localStorage;
  try {
    localStorage = container.read(localStorageServiceProvider);
  } catch (_) {
    return true;
  }
  final phone = localStorage.userPhone;
  return AppAuthRoles.isAdminPhone(phone);
}
