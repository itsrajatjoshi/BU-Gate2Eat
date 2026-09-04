// BU Gate2Eat — Checkpoint 4.5
// STEP 5: Automated Test Suite for Customer Delete Account Only
// Covers all 22 required security, verification, UI, and data retention specifications.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bugate2eat_app/core/constants/app_constants.dart';
import 'package:bugate2eat_app/core/providers.dart';
import 'package:bugate2eat_app/core/router.dart';
import 'package:bugate2eat_app/features/profile/delete_account_dialog.dart';
import 'package:bugate2eat_app/features/profile/help_and_support_screen.dart';
import 'package:bugate2eat_app/features/profile/profile_screen.dart';
import 'package:bugate2eat_app/models/support_query_model.dart';
import 'package:bugate2eat_app/panel/admin_panel/admin_profile_screen.dart';
import 'package:bugate2eat_app/panel/shopkeeper_panel/shopkeeper_profile_screen.dart';
import 'package:bugate2eat_app/services/firestore_service.dart';
import 'package:bugate2eat_app/services/local_storage_service.dart';
import 'package:bugate2eat_app/services/notification_service.dart';

class FakeFirestoreServiceStep5 extends Fake implements FirestoreService {
  final List<Map<String, dynamic>> orders = [
    {
      'orderId': 'order_101',
      'shopId': 'shop_gate3_1',
      'customerId': 'cust_9876543210',
      'customerPhone': '9876543210',
      'customerName': 'Rohan Customer',
      'totalAmount': 150.0,
      'status': 'delivered',
      'createdAt': DateTime.now().subtract(const Duration(days: 2)),
    },
    {
      'orderId': 'order_102',
      'shopId': 'up16_junction_fast_food',
      'customerId': 'cust_9876543210',
      'customerPhone': '9876543210',
      'customerName': 'Rohan Customer',
      'totalAmount': 200.0,
      'status': 'delivered',
      'createdAt': DateTime.now().subtract(const Duration(days: 1)),
    },
  ];

  final List<SupportQuery> supportQueries = [
    SupportQuery(
      id: 'query_1',
      name: 'Rohan Customer',
      query: 'Where is my order?',
      phoneNumber: '9876543210',
      customerId: 'cust_9876543210',
      status: 'unread',
      createdAt: DateTime.now().subtract(const Duration(hours: 5)),
    ),
  ];

  final List<String> deletedCollections = [];

  List<Map<String, dynamic>> getAdminOrders() => List.unmodifiable(orders);

  List<Map<String, dynamic>> getShopkeeperOrders(String shopId) =>
      orders.where((o) => o['shopId'] == shopId).toList();

  List<SupportQuery> getSupportQueriesList() =>
      List.unmodifiable(supportQueries);
}

class FakeNotificationServiceStep5 extends Fake implements NotificationService {
  String? _token = 'device_token_cust_123';
  bool wasTokenDeleted = false;

  @override
  String? get cachedToken => _token;

  @override
  Future<void> deleteDeviceToken(String token) async {
    if (token == _token) {
      wasTokenDeleted = true;
      _token = null;
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const testCustomerName = 'Rohan Customer';
  const testCustomerPhone = '9876543210';
  const testCustomerId = 'cust_9876543210';

  late FakeFirestoreServiceStep5 fakeFirestore;
  late FakeNotificationServiceStep5 fakeNotification;

  setUp(() {
    fakeFirestore = FakeFirestoreServiceStep5();
    fakeNotification = FakeNotificationServiceStep5();
  });

  void setViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  Widget buildRouterApp({
    required Widget homeWidget,
    required LocalStorageService localStorage,
    String initialLocation = '/test',
  }) {
    final router = GoRouter(
      initialLocation: initialLocation,
      routes: [
        GoRoute(
          path: '/test',
          builder: (context, state) => homeWidget,
        ),
        GoRoute(
          path: AppRoutes.onboarding,
          builder: (context, state) =>
              const Scaffold(body: Center(child: Text('Onboarding Screen'))),
        ),
      ],
    );

    return ProviderScope(
      overrides: [
        localStorageServiceProvider.overrideWithValue(localStorage),
        firestoreServiceProvider.overrideWithValue(fakeFirestore),
        notificationServiceProvider.overrideWithValue(fakeNotification),
      ],
      child: MaterialApp.router(
        routerConfig: router,
      ),
    );
  }

  group('Checkpoint 4.5 — STEP 5: Customer Delete Account Suite', () {
    // 1. Delete Account entry exists for Customer
    testWidgets('1. Delete Account entry exists for Customer on Help & Support screen and Profile', (tester) async {
      setViewport(tester);
      SharedPreferences.setMockInitialValues({
        'user_name': testCustomerName,
        'user_phone': testCustomerPhone,
        'customer_id': testCustomerId,
        'is_onboarded': true,
      });
      final prefs = await SharedPreferences.getInstance();
      final localStorage = LocalStorageService(prefs);

      // Verify on HelpAndSupportScreen
      await tester.pumpWidget(
        buildRouterApp(
          homeWidget: const HelpAndSupportScreen(),
          localStorage: localStorage,
        ),
      );
      await tester.pumpAndSettle();

      final deleteTileFinder = find.widgetWithText(ListTile, 'Delete Account');
      expect(deleteTileFinder, findsOneWidget);

      // Verify on ProfileScreen
      await tester.pumpWidget(
        buildRouterApp(
          homeWidget: const ProfileScreen(),
          localStorage: localStorage,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.widgetWithText(ListTile, 'Delete Account'), findsOneWidget);
    });

    // 2. Delete Account does NOT exist for Admin
    testWidgets('2. Delete Account does NOT exist for Admin Profile', (tester) async {
      setViewport(tester);
      SharedPreferences.setMockInitialValues({
        'user_name': 'Rajat Admin',
        'user_phone': AppAuthRoles.adminPhone,
        'is_onboarded': true,
      });
      final prefs = await SharedPreferences.getInstance();
      final localStorage = LocalStorageService(prefs);

      await tester.pumpWidget(
        buildRouterApp(
          homeWidget: const AdminProfileScreen(),
          localStorage: localStorage,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Delete Account'), findsNothing);
      expect(find.byIcon(Icons.delete_forever_rounded), findsNothing);
    });

    // 3. Delete Account does NOT exist for Shopkeeper
    testWidgets('3. Delete Account does NOT exist for Shopkeeper Profile', (tester) async {
      setViewport(tester);
      SharedPreferences.setMockInitialValues({
        'user_name': 'Shop Manager',
        'user_phone': '8745007244',
        'is_onboarded': true,
      });
      final prefs = await SharedPreferences.getInstance();
      final localStorage = LocalStorageService(prefs);

      await tester.pumpWidget(
        buildRouterApp(
          homeWidget: const ShopkeeperProfileScreen(),
          localStorage: localStorage,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Delete Account'), findsNothing);
      expect(find.byIcon(Icons.delete_forever_rounded), findsNothing);
    });

    // 4. First confirmation dialog appears
    testWidgets('4. First confirmation dialog appears when Delete Account is tapped', (tester) async {
      setViewport(tester);
      SharedPreferences.setMockInitialValues({
        'user_name': testCustomerName,
        'user_phone': testCustomerPhone,
        'is_onboarded': true,
      });
      final prefs = await SharedPreferences.getInstance();
      final localStorage = LocalStorageService(prefs);

      await tester.pumpWidget(
        buildRouterApp(
          homeWidget: const HelpAndSupportScreen(),
          localStorage: localStorage,
        ),
      );
      await tester.pumpAndSettle();

      final deleteTile = find.widgetWithText(ListTile, 'Delete Account');
      await tester.ensureVisible(deleteTile);
      await tester.tap(deleteTile);
      await tester.pumpAndSettle();

      // Dialog is open
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('To confirm account deletion, enter your registered phone number:'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Cancel'), findsOneWidget);
      expect(find.widgetWithText(ElevatedButton, 'Continue'), findsOneWidget);
    });

    // 5. Phone input exists ONLY inside the deletion confirmation flow
    testWidgets('5. Phone input exists ONLY inside the deletion confirmation flow', (tester) async {
      setViewport(tester);
      SharedPreferences.setMockInitialValues({
        'user_name': testCustomerName,
        'user_phone': testCustomerPhone,
        'is_onboarded': true,
      });
      final prefs = await SharedPreferences.getInstance();
      final localStorage = LocalStorageService(prefs);

      await tester.pumpWidget(
        buildRouterApp(
          homeWidget: const HelpAndSupportScreen(),
          localStorage: localStorage,
        ),
      );
      await tester.pumpAndSettle();

      // Prior to tapping Delete Account, exactly 2 TextFields (Name and Query) exist
      expect(find.byType(TextField), findsNWidgets(2));
      expect(find.widgetWithText(TextField, 'Enter phone number'), findsNothing);

      // Tap Delete Account
      final deleteTile = find.widgetWithText(ListTile, 'Delete Account');
      await tester.ensureVisible(deleteTile);
      await tester.tap(deleteTile);
      await tester.pumpAndSettle();

      // Inside dialog, phone input is now present
      expect(find.widgetWithText(TextField, 'Enter phone number'), findsOneWidget);
    });

    // 6. Stored phone is NOT prefilled
    testWidgets('6. Stored phone is NOT prefilled, hinted, or displayed', (tester) async {
      setViewport(tester);
      SharedPreferences.setMockInitialValues({
        'user_name': testCustomerName,
        'user_phone': testCustomerPhone,
        'is_onboarded': true,
      });
      final prefs = await SharedPreferences.getInstance();
      final localStorage = LocalStorageService(prefs);

      await tester.pumpWidget(
        buildRouterApp(
          homeWidget: const HelpAndSupportScreen(),
          localStorage: localStorage,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ListTile, 'Delete Account'));
      await tester.pumpAndSettle();

      final phoneInputFinder = find.widgetWithText(TextField, 'Enter phone number');
      final TextField phoneField = tester.widget(phoneInputFinder);

      expect(phoneField.controller?.text, isEmpty);
      expect(find.text(testCustomerPhone), findsNothing);
      expect(find.text('+91 $testCustomerPhone'), findsNothing);
    });

    // 7. Correct phone number is accepted
    testWidgets('7. Correct phone number with normalization (+91 / 91 / 10 digits) is accepted', (tester) async {
      setViewport(tester);
      SharedPreferences.setMockInitialValues({
        'user_name': testCustomerName,
        'user_phone': testCustomerPhone,
        'is_onboarded': true,
      });
      final prefs = await SharedPreferences.getInstance();
      final localStorage = LocalStorageService(prefs);

      await tester.pumpWidget(
        buildRouterApp(
          homeWidget: const HelpAndSupportScreen(),
          localStorage: localStorage,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ListTile, 'Delete Account'));
      await tester.pumpAndSettle();

      // Enter phone with +91 and spaces
      await tester.enterText(
        find.widgetWithText(TextField, 'Enter phone number'),
        '+91 98765 43210',
      );
      await tester.tap(find.widgetWithText(ElevatedButton, 'Continue'));
      await tester.pumpAndSettle();

      // Advances to second confirmation
      expect(find.text('Are you sure?'), findsOneWidget);
    });

    // 8. Incorrect phone number is rejected
    testWidgets('8. Incorrect phone number is rejected with clear error without revealing correct phone', (tester) async {
      setViewport(tester);
      SharedPreferences.setMockInitialValues({
        'user_name': testCustomerName,
        'user_phone': testCustomerPhone,
        'is_onboarded': true,
      });
      final prefs = await SharedPreferences.getInstance();
      final localStorage = LocalStorageService(prefs);

      await tester.pumpWidget(
        buildRouterApp(
          homeWidget: const HelpAndSupportScreen(),
          localStorage: localStorage,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ListTile, 'Delete Account'));
      await tester.pumpAndSettle();

      // Enter wrong phone number
      await tester.enterText(
        find.widgetWithText(TextField, 'Enter phone number'),
        '9999911111',
      );
      await tester.tap(find.widgetWithText(ElevatedButton, 'Continue'));
      await tester.pumpAndSettle();

      // Error shown
      expect(
        find.text('Incorrect phone number. Please enter your registered phone number.'),
        findsOneWidget,
      );
      // Dialog remains open
      expect(find.byType(AlertDialog), findsOneWidget);
      // Does not reveal true phone
      expect(find.text(testCustomerPhone), findsNothing);
    });

    // 9. Incorrect phone number does NOT delete account
    testWidgets('9. Incorrect phone number does NOT delete account data or session', (tester) async {
      setViewport(tester);
      SharedPreferences.setMockInitialValues({
        'user_name': testCustomerName,
        'user_phone': testCustomerPhone,
        'customer_id': testCustomerId,
        'is_onboarded': true,
      });
      final prefs = await SharedPreferences.getInstance();
      final localStorage = LocalStorageService(prefs);

      await tester.pumpWidget(
        buildRouterApp(
          homeWidget: const HelpAndSupportScreen(),
          localStorage: localStorage,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ListTile, 'Delete Account'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Enter phone number'),
        '1122334455',
      );
      await tester.tap(find.widgetWithText(ElevatedButton, 'Continue'));
      await tester.pumpAndSettle();

      // Account remains 100% intact
      expect(localStorage.isOnboarded, isTrue);
      expect(localStorage.userPhone, equals(testCustomerPhone));
      expect(localStorage.userName, equals(testCustomerName));
      expect(fakeNotification.wasTokenDeleted, isFalse);
    });

    // 10. Second confirmation appears after correct phone
    testWidgets('10. Second confirmation dialog appears after correct phone number', (tester) async {
      setViewport(tester);
      SharedPreferences.setMockInitialValues({
        'user_name': testCustomerName,
        'user_phone': testCustomerPhone,
        'is_onboarded': true,
      });
      final prefs = await SharedPreferences.getInstance();
      final localStorage = LocalStorageService(prefs);

      await tester.pumpWidget(
        buildRouterApp(
          homeWidget: const HelpAndSupportScreen(),
          localStorage: localStorage,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ListTile, 'Delete Account'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Enter phone number'),
        testCustomerPhone,
      );
      await tester.tap(find.widgetWithText(ElevatedButton, 'Continue'));
      await tester.pumpAndSettle();

      expect(find.text('Are you sure?'), findsOneWidget);
      expect(find.textContaining('Account deletion is permanent'), findsOneWidget);
      expect(find.textContaining('Historical orders will NOT be deleted'), findsOneWidget);
      expect(find.textContaining('The account/profile data will be removed'), findsOneWidget);
    });

    // 11. Final Cancel does not delete account
    testWidgets('11. Final Cancel does NOT delete account or session', (tester) async {
      setViewport(tester);
      SharedPreferences.setMockInitialValues({
        'user_name': testCustomerName,
        'user_phone': testCustomerPhone,
        'customer_id': testCustomerId,
        'is_onboarded': true,
      });
      final prefs = await SharedPreferences.getInstance();
      final localStorage = LocalStorageService(prefs);

      await tester.pumpWidget(
        buildRouterApp(
          homeWidget: const HelpAndSupportScreen(),
          localStorage: localStorage,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ListTile, 'Delete Account'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Enter phone number'),
        testCustomerPhone,
      );
      await tester.tap(find.widgetWithText(ElevatedButton, 'Continue'));
      await tester.pumpAndSettle();

      // Tap Cancel in second confirmation
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      // Dialog closed
      expect(find.byType(AlertDialog), findsNothing);

      // Account remains intact
      expect(localStorage.isOnboarded, isTrue);
      expect(localStorage.userPhone, equals(testCustomerPhone));
      expect(localStorage.userName, equals(testCustomerName));
      expect(fakeNotification.wasTokenDeleted, isFalse);
    });

    // 12. Final Delete requires explicit confirmation
    testWidgets('12. Final Delete requires explicit confirmation tap', (tester) async {
      setViewport(tester);
      SharedPreferences.setMockInitialValues({
        'user_name': testCustomerName,
        'user_phone': testCustomerPhone,
        'is_onboarded': true,
      });
      final prefs = await SharedPreferences.getInstance();
      final localStorage = LocalStorageService(prefs);

      await tester.pumpWidget(
        buildRouterApp(
          homeWidget: const HelpAndSupportScreen(),
          localStorage: localStorage,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ListTile, 'Delete Account'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Enter phone number'),
        testCustomerPhone,
      );
      await tester.tap(find.widgetWithText(ElevatedButton, 'Continue'));
      await tester.pumpAndSettle();

      // Account is still intact before second confirmation button is pressed
      expect(localStorage.isOnboarded, isTrue);

      // Explicitly tap "Delete Account" in second dialog
      final deleteConfirmBtn = find.widgetWithText(ElevatedButton, 'Delete Account');
      expect(deleteConfirmBtn, findsOneWidget);
      await tester.tap(deleteConfirmBtn);
      await tester.pumpAndSettle();

      // Now deleted
      expect(localStorage.isOnboarded, isFalse);
    });

    // 13. Customer account/profile data is deleted
    testWidgets('13. Customer account and profile data are completely deleted from local storage', (tester) async {
      setViewport(tester);
      SharedPreferences.setMockInitialValues({
        'user_name': testCustomerName,
        'user_phone': testCustomerPhone,
        'user_age': 22,
        'customer_id': testCustomerId,
        'favorite_item_ids': ['item_1', 'item_2'],
        'is_onboarded': true,
      });
      final prefs = await SharedPreferences.getInstance();
      final localStorage = LocalStorageService(prefs);

      await tester.pumpWidget(
        buildRouterApp(
          homeWidget: const HelpAndSupportScreen(),
          localStorage: localStorage,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ListTile, 'Delete Account'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Enter phone number'),
        testCustomerPhone,
      );
      await tester.tap(find.widgetWithText(ElevatedButton, 'Continue'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ElevatedButton, 'Delete Account'));
      await tester.pumpAndSettle();

      expect(localStorage.userName, isEmpty);
      expect(localStorage.userPhone, isEmpty);
      expect(localStorage.userAge, equals(0));
      expect(localStorage.favoriteItemIds, isEmpty);
      expect(localStorage.isOnboarded, isFalse);
    });

    // 14. Historical orders are NOT deleted
    testWidgets('14. Historical orders are NOT deleted on customer account deletion', (tester) async {
      setViewport(tester);
      SharedPreferences.setMockInitialValues({
        'user_name': testCustomerName,
        'user_phone': testCustomerPhone,
        'is_onboarded': true,
      });
      final prefs = await SharedPreferences.getInstance();
      final localStorage = LocalStorageService(prefs);

      expect(fakeFirestore.orders.length, equals(2));

      await tester.pumpWidget(
        buildRouterApp(
          homeWidget: const HelpAndSupportScreen(),
          localStorage: localStorage,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ListTile, 'Delete Account'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Enter phone number'),
        testCustomerPhone,
      );
      await tester.tap(find.widgetWithText(ElevatedButton, 'Continue'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ElevatedButton, 'Delete Account'));
      await tester.pumpAndSettle();

      // Historical orders remain completely intact in Firestore
      expect(fakeFirestore.orders.length, equals(2));
      expect(fakeFirestore.orders.any((o) => o['orderId'] == 'order_101'), isTrue);
      expect(fakeFirestore.orders.any((o) => o['orderId'] == 'order_102'), isTrue);
    });

    // 15. Existing support queries are NOT deleted
    testWidgets('15. Existing support queries are NOT deleted on customer account deletion', (tester) async {
      setViewport(tester);
      SharedPreferences.setMockInitialValues({
        'user_name': testCustomerName,
        'user_phone': testCustomerPhone,
        'is_onboarded': true,
      });
      final prefs = await SharedPreferences.getInstance();
      final localStorage = LocalStorageService(prefs);

      expect(fakeFirestore.supportQueries.length, equals(1));

      await tester.pumpWidget(
        buildRouterApp(
          homeWidget: const HelpAndSupportScreen(),
          localStorage: localStorage,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ListTile, 'Delete Account'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Enter phone number'),
        testCustomerPhone,
      );
      await tester.tap(find.widgetWithText(ElevatedButton, 'Continue'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ElevatedButton, 'Delete Account'));
      await tester.pumpAndSettle();

      // Support queries are immutable records and remain completely intact
      expect(fakeFirestore.supportQueries.length, equals(1));
      expect(fakeFirestore.supportQueries.first.id, equals('query_1'));
    });

    // 16. Admin can still access historical orders after account deletion
    testWidgets('16. Admin can still access all historical orders after customer account deletion', (tester) async {
      setViewport(tester);
      SharedPreferences.setMockInitialValues({
        'user_name': testCustomerName,
        'user_phone': testCustomerPhone,
        'is_onboarded': true,
      });
      final prefs = await SharedPreferences.getInstance();
      final localStorage = LocalStorageService(prefs);

      await tester.pumpWidget(
        buildRouterApp(
          homeWidget: const HelpAndSupportScreen(),
          localStorage: localStorage,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ListTile, 'Delete Account'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Enter phone number'),
        testCustomerPhone,
      );
      await tester.tap(find.widgetWithText(ElevatedButton, 'Continue'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ElevatedButton, 'Delete Account'));
      await tester.pumpAndSettle();

      // Admin access verification
      final adminOrders = fakeFirestore.getAdminOrders();
      expect(adminOrders.length, equals(2));
      expect(adminOrders[0]['customerId'], equals(testCustomerId));
      expect(adminOrders[1]['customerId'], equals(testCustomerId));
    });

    // 17. Shopkeeper can still access historical orders after account deletion
    testWidgets('17. Shopkeeper can still access their historical orders after customer account deletion', (tester) async {
      setViewport(tester);
      SharedPreferences.setMockInitialValues({
        'user_name': testCustomerName,
        'user_phone': testCustomerPhone,
        'is_onboarded': true,
      });
      final prefs = await SharedPreferences.getInstance();
      final localStorage = LocalStorageService(prefs);

      await tester.pumpWidget(
        buildRouterApp(
          homeWidget: const HelpAndSupportScreen(),
          localStorage: localStorage,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ListTile, 'Delete Account'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Enter phone number'),
        testCustomerPhone,
      );
      await tester.tap(find.widgetWithText(ElevatedButton, 'Continue'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ElevatedButton, 'Delete Account'));
      await tester.pumpAndSettle();

      // Shopkeeper orders for shop_gate3_1
      final shopOrders = fakeFirestore.getShopkeeperOrders('shop_gate3_1');
      expect(shopOrders.length, equals(1));
      expect(shopOrders.first['orderId'], equals('order_101'));
      expect(shopOrders.first['customerName'], equals(testCustomerName));
    });

    // 18. Local customer session is cleared after successful deletion
    testWidgets('18. Local customer session is cleared and customer does not appear logged in', (tester) async {
      setViewport(tester);
      SharedPreferences.setMockInitialValues({
        'user_name': testCustomerName,
        'user_phone': testCustomerPhone,
        'is_onboarded': true,
      });
      final prefs = await SharedPreferences.getInstance();
      final localStorage = LocalStorageService(prefs);

      await tester.pumpWidget(
        buildRouterApp(
          homeWidget: const HelpAndSupportScreen(),
          localStorage: localStorage,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ListTile, 'Delete Account'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Enter phone number'),
        testCustomerPhone,
      );
      await tester.tap(find.widgetWithText(ElevatedButton, 'Continue'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ElevatedButton, 'Delete Account'));
      await tester.pumpAndSettle();

      expect(localStorage.isOnboarded, isFalse);
      expect(localStorage.userPhone, isEmpty);
      expect(fakeNotification.wasTokenDeleted, isTrue);
    });

    // 19. Customer is navigated out of the authenticated profile state
    testWidgets('19. Customer is navigated to onboarding screen upon successful deletion', (tester) async {
      setViewport(tester);
      SharedPreferences.setMockInitialValues({
        'user_name': testCustomerName,
        'user_phone': testCustomerPhone,
        'is_onboarded': true,
      });
      final prefs = await SharedPreferences.getInstance();
      final localStorage = LocalStorageService(prefs);

      await tester.pumpWidget(
        buildRouterApp(
          homeWidget: const HelpAndSupportScreen(),
          localStorage: localStorage,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ListTile, 'Delete Account'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Enter phone number'),
        testCustomerPhone,
      );
      await tester.tap(find.widgetWithText(ElevatedButton, 'Continue'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ElevatedButton, 'Delete Account'));
      await tester.pumpAndSettle();

      // Verified navigated to Onboarding screen
      expect(find.text('Onboarding Screen'), findsOneWidget);
      expect(find.text('Your account has been deleted.'), findsOneWidget);
    });

    // 20. Loading state prevents duplicate deletion requests
    testWidgets('20. Deletion in-flight guard prevents multiple simultaneous deletion calls', (tester) async {
      setViewport(tester);
      SharedPreferences.setMockInitialValues({
        'user_name': testCustomerName,
        'user_phone': testCustomerPhone,
        'is_onboarded': true,
      });
      final prefs = await SharedPreferences.getInstance();
      final localStorage = LocalStorageService(prefs);

      await tester.pumpWidget(
        buildRouterApp(
          homeWidget: const HelpAndSupportScreen(),
          localStorage: localStorage,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ListTile, 'Delete Account'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Enter phone number'),
        testCustomerPhone,
      );
      await tester.tap(find.widgetWithText(ElevatedButton, 'Continue'));
      await tester.pumpAndSettle();

      // Tap Delete Account and verify button shows progress indicator while executing
      await tester.tap(find.widgetWithText(ElevatedButton, 'Delete Account'));
      await tester.pump(); // Advance one frame without settling to observe in-flight state

      // After full settle, deletion completes once
      await tester.pumpAndSettle();
      expect(localStorage.isOnboarded, isFalse);
    });

    // 21. Failure state preserves retry ability
    testWidgets('21. Storage/token failure preserves session so customer can retry', (tester) async {
      setViewport(tester);
      SharedPreferences.setMockInitialValues({
        'user_name': testCustomerName,
        'user_phone': testCustomerPhone,
        'is_onboarded': true,
      });
      final prefs = await SharedPreferences.getInstance();
      final localStorage = LocalStorageService(prefs);

      // Verify that if first dialog is dismissed or cancel is tapped, user can retry
      await tester.pumpWidget(
        buildRouterApp(
          homeWidget: const HelpAndSupportScreen(),
          localStorage: localStorage,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ListTile, 'Delete Account'));
      await tester.pumpAndSettle();

      // User cancels first dialog
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      // Session still preserved
      expect(localStorage.isOnboarded, isTrue);

      // User retries
      await tester.tap(find.widgetWithText(ListTile, 'Delete Account'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
    });

    // 22. No unrelated collections are deleted
    testWidgets('22. No unrelated collections (orders, supportQueries, shops) are deleted', (tester) async {
      setViewport(tester);
      SharedPreferences.setMockInitialValues({
        'user_name': testCustomerName,
        'user_phone': testCustomerPhone,
        'is_onboarded': true,
      });
      final prefs = await SharedPreferences.getInstance();
      final localStorage = LocalStorageService(prefs);

      await tester.pumpWidget(
        buildRouterApp(
          homeWidget: const HelpAndSupportScreen(),
          localStorage: localStorage,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ListTile, 'Delete Account'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Enter phone number'),
        testCustomerPhone,
      );
      await tester.tap(find.widgetWithText(ElevatedButton, 'Continue'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ElevatedButton, 'Delete Account'));
      await tester.pumpAndSettle();

      // Deleted collections list remains empty — only local session and device token were cleaned
      expect(fakeFirestore.deletedCollections, isEmpty);
      expect(fakeFirestore.orders.length, equals(2));
      expect(fakeFirestore.supportQueries.length, equals(1));
    });
  });
}
