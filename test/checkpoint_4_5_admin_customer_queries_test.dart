// BU Gate2Eat — Checkpoint 4.5
// STEP 4: Automated Test Suite for Admin Customer Queries

import 'dart:io';

import 'package:bugate2eat_app/core/constants/app_constants.dart';
import 'package:bugate2eat_app/core/providers.dart';
import 'package:bugate2eat_app/core/router.dart';
import 'package:bugate2eat_app/features/profile/help_and_support_screen.dart';
import 'package:bugate2eat_app/features/profile/profile_screen.dart';
import 'package:bugate2eat_app/models/support_query_model.dart';
import 'package:bugate2eat_app/panel/admin_panel/admin_customer_queries_screen.dart';
import 'package:bugate2eat_app/panel/admin_panel/admin_profile_screen.dart';
import 'package:bugate2eat_app/panel/admin_panel/widgets/admin_query_details_modal.dart';
import 'package:bugate2eat_app/panel/shopkeeper_panel/shopkeeper_profile_screen.dart';
import 'package:bugate2eat_app/services/firestore_service.dart';
import 'package:bugate2eat_app/services/local_storage_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeFirestoreServiceStep4 extends Fake implements FirestoreService {
  final List<SupportQuery> queries = [];
  final List<Map<String, dynamic>> submittedQueries = [];
  bool shouldFail = false;

  @override
  Stream<List<SupportQuery>> watchSupportQueries() {
    if (shouldFail) {
      return Stream.error(Exception('Firestore stream error'));
    }
    final sorted = List<SupportQuery>.from(queries)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return Stream.value(sorted);
  }

  @override
  Future<List<SupportQuery>> getSupportQueries() async {
    if (shouldFail) {
      throw Exception('Firestore fetch error');
    }
    final sorted = List<SupportQuery>.from(queries)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return sorted;
  }

  @override
  Future<String> submitSupportQuery({
    required String name,
    required String query,
    required String phoneNumber,
    String customerId = '',
  }) async {
    final queryMap = {
      'id': 'query_${submittedQueries.length + 1}',
      'name': name.trim(),
      'query': query.trim(),
      'phoneNumber': phoneNumber.trim(),
      'customerId': customerId.trim(),
      'status': 'unread',
      'createdAt': DateTime.now(),
    };
    submittedQueries.add(queryMap);
    return queryMap['id'] as String;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeFirestoreServiceStep4 fakeFirestore;

  setUp(() {
    fakeFirestore = FakeFirestoreServiceStep4();
  });

  void setViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  group('Checkpoint 4.5 — STEP 4: Admin Customer Queries Suite', () {
    // 1. Admin Profile displays "Customer Queries"
    testWidgets('1. Admin Profile displays "Customer Queries" button', (tester) async {
      setViewport(tester);
      SharedPreferences.setMockInitialValues({
        'user_name': 'Rajat Admin',
        'user_phone': AppAuthRoles.adminPhone,
        'user_age': 26,
      });
      final prefs = await SharedPreferences.getInstance();
      final localStorage = LocalStorageService(prefs);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localStorageServiceProvider.overrideWithValue(localStorage),
          ],
          child: const MaterialApp(
            home: AdminProfileScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Customer Queries'), findsOneWidget);
      expect(find.text('View customer support queries'), findsOneWidget);
    });

    // 2. Customer Profile does NOT display "Customer Queries"
    testWidgets('2. Customer Profile does NOT display "Customer Queries"', (tester) async {
      setViewport(tester);
      SharedPreferences.setMockInitialValues({
        'user_name': 'Student Aarav',
        'user_phone': '9876543210',
        'user_age': 20,
      });
      final prefs = await SharedPreferences.getInstance();
      final localStorage = LocalStorageService(prefs);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localStorageServiceProvider.overrideWithValue(localStorage),
          ],
          child: const MaterialApp(
            home: ProfileScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Customer Queries'), findsNothing);
      expect(find.text('Help & Support'), findsOneWidget);
    });

    // 3. Shopkeeper Profile does NOT display "Customer Queries"
    testWidgets('3. Shopkeeper Profile does NOT display "Customer Queries"', (tester) async {
      setViewport(tester);
      SharedPreferences.setMockInitialValues({
        'user_name': 'Shopkeeper Nayana',
        'user_phone': '8295643910',
        'user_age': 30,
      });
      final prefs = await SharedPreferences.getInstance();
      final localStorage = LocalStorageService(prefs);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localStorageServiceProvider.overrideWithValue(localStorage),
          ],
          child: const MaterialApp(
            home: ShopkeeperProfileScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Customer Queries'), findsNothing);
    });

    // 4. Admin Customer Queries route exists
    test('4. Admin Customer Queries route exists and matches path', () {
      expect(AppRoutes.adminCustomerQueries, equals('/admin/customer-queries'));
      final matchingRoute = appRouter.configuration.routes
          .whereType<GoRoute>()
          .any((r) => r.path == AppRoutes.adminCustomerQueries);
      expect(matchingRoute, isTrue);
    });

    // 5. Existing supportQueries model/data can be deserialized and read
    test('5. SupportQuery model deserializes existing schema correctly', () {
      final now = DateTime.now();
      final map = {
        'id': 'sq_101',
        'name': 'Rahul Verma',
        'query': 'Payment debited but order not confirmed.',
        'phoneNumber': '9123456780',
        'customerId': 'cust_abc',
        'createdAt': now.toIso8601String(),
        'status': 'unread',
      };

      final query = SupportQuery.fromMap(map);
      expect(query.id, equals('sq_101'));
      expect(query.name, equals('Rahul Verma'));
      expect(query.query, equals('Payment debited but order not confirmed.'));
      expect(query.phoneNumber, equals('9123456780'));
      expect(query.status, equals('unread'));
    });

    // 6 & 7. Query list displays customer name and query preview
    testWidgets('6 & 7. Query list displays customer name and query preview', (tester) async {
      setViewport(tester);
      final testQuery = SupportQuery(
        id: 'q1',
        name: 'Simran Kaur',
        query: 'My cold coffee was delivered without straw and sugar.',
        phoneNumber: '9888877777',
        createdAt: DateTime(2026, 9, 4, 14, 30),
      );
      fakeFirestore.queries.add(testQuery);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            firestoreServiceProvider.overrideWithValue(fakeFirestore),
          ],
          child: const MaterialApp(
            home: AdminCustomerQueriesScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Simran Kaur'), findsOneWidget);
      expect(find.text('My cold coffee was delivered without straw and sugar.'), findsOneWidget);
      expect(find.text('UNREAD'), findsOneWidget);
    });

    // 8, 9, 10, 11. Query details displays customer name, phone number, full query, and status
    testWidgets('8, 9, 10, 11. Tapping query opens Details modal showing name, phone, query, status', (tester) async {
      setViewport(tester);
      const testPhone = '9876501234';
      final testQuery = SupportQuery(
        id: 'q_detail',
        name: 'Aakash Patel',
        query: 'Very long detailed query regarding campus delivery location at Gate 2 hostel.',
        phoneNumber: testPhone,
        customerId: 'cust_999',
        createdAt: DateTime(2026, 9, 4, 15),
      );
      fakeFirestore.queries.add(testQuery);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            firestoreServiceProvider.overrideWithValue(fakeFirestore),
          ],
          child: const MaterialApp(
            home: AdminCustomerQueriesScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap the card to open details modal
      await tester.tap(find.text('Aakash Patel'));
      await tester.pumpAndSettle();

      // Admin Query Details Modal verification:
      expect(find.byType(AdminQueryDetailsModal), findsOneWidget);
      expect(find.text('Query Details'), findsOneWidget);
      expect(find.text('Aakash Patel'), findsWidgets);
      // Admin sees the customer's phone number
      expect(find.textContaining(testPhone), findsOneWidget);
      // Admin sees full query inside modal
      expect(
        find.descendant(
          of: find.byType(AdminQueryDetailsModal),
          matching: find.text('Very long detailed query regarding campus delivery location at Gate 2 hostel.'),
        ),
        findsOneWidget,
      );
      // Status badge in modal
      expect(find.text('UNREAD'), findsWidgets);
    });

    // 12. Newest queries appear first
    testWidgets('12. Newest queries appear first in the list', (tester) async {
      setViewport(tester);
      final olderQuery = SupportQuery(
        id: 'q_old',
        name: 'Old Query Customer',
        query: 'Submitted an hour ago',
        phoneNumber: '9000000001',
        createdAt: DateTime(2026, 9, 4, 12),
      );
      final newerQuery = SupportQuery(
        id: 'q_new',
        name: 'New Query Customer',
        query: 'Submitted 5 minutes ago',
        phoneNumber: '9000000002',
        createdAt: DateTime(2026, 9, 4, 15),
      );

      // Add older first to the store
      fakeFirestore.queries.addAll([olderQuery, newerQuery]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            firestoreServiceProvider.overrideWithValue(fakeFirestore),
          ],
          child: const MaterialApp(
            home: AdminCustomerQueriesScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final firstItem = find.text('New Query Customer');
      final secondItem = find.text('Old Query Customer');
      expect(firstItem, findsOneWidget);
      expect(secondItem, findsOneWidget);

      final firstY = tester.getTopLeft(firstItem).dy;
      final secondY = tester.getTopLeft(secondItem).dy;
      expect(firstY, lessThan(secondY)); // Newest appears above older
    });

    // 13. Empty state works
    testWidgets('13. Empty state displays "No customer queries yet"', (tester) async {
      setViewport(tester);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            firestoreServiceProvider.overrideWithValue(fakeFirestore),
          ],
          child: const MaterialApp(
            home: AdminCustomerQueriesScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No customer queries yet'), findsOneWidget);
      expect(find.byIcon(Icons.inbox_outlined), findsOneWidget);
    });

    // 14. Loading state works
    testWidgets('14. Loading state shows CircularProgressIndicator', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            supportQueriesStreamProvider.overrideWith(
              (ref) => const Stream.empty(),
            ),
          ],
          child: const MaterialApp(
            home: AdminCustomerQueriesScreen(),
          ),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    // 15. Error state works with retry button
    testWidgets('15. Error state displays error message and Retry button', (tester) async {
      setViewport(tester);
      fakeFirestore.shouldFail = true;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            firestoreServiceProvider.overrideWithValue(fakeFirestore),
          ],
          child: const MaterialApp(
            home: AdminCustomerQueriesScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Failed to load customer queries'), findsOneWidget);
      expect(find.widgetWithText(ElevatedButton, 'Retry'), findsOneWidget);
    });

    // 16. Missing/invalid createdAt does not crash the screen
    testWidgets('16. Missing/invalid createdAt does not crash the screen', (tester) async {
      setViewport(tester);
      final invalidDateQuery = SupportQuery.fromMap({
        'id': 'sq_null_date',
        'name': 'Pending Timestamp User',
        'query': 'Server timestamp is currently null or pending.',
        'phoneNumber': '9111222333',
        'createdAt': null, // null createdAt
        'status': 'unread',
      });
      fakeFirestore.queries.add(invalidDateQuery);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            firestoreServiceProvider.overrideWithValue(fakeFirestore),
          ],
          child: const MaterialApp(
            home: AdminCustomerQueriesScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Pending Timestamp User'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    // 17. Customer phone remains hidden from customer Help & Support UI
    testWidgets('17. Customer phone remains hidden from customer Help & Support UI', (tester) async {
      setViewport(tester);
      const testPhone = '9876543210';
      SharedPreferences.setMockInitialValues({
        'user_name': 'Aarav Customer',
        'user_phone': testPhone,
      });
      final prefs = await SharedPreferences.getInstance();
      final localStorage = LocalStorageService(prefs);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localStorageServiceProvider.overrideWithValue(localStorage),
            firestoreServiceProvider.overrideWithValue(fakeFirestore),
          ],
          child: const MaterialApp(
            home: HelpAndSupportScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(testPhone), findsNothing);
      expect(find.text('+91 $testPhone'), findsNothing);
      expect(find.widgetWithText(TextField, 'Phone'), findsNothing);
    });

    // 18. Existing Help & Support submission still works
    testWidgets('18. Existing Help & Support submission still works with automatic phone attachment', (tester) async {
      setViewport(tester);
      const testPhone = '9876543210';
      SharedPreferences.setMockInitialValues({
        'user_name': 'Aarav Customer',
        'user_phone': testPhone,
      });
      final prefs = await SharedPreferences.getInstance();
      final localStorage = LocalStorageService(prefs);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localStorageServiceProvider.overrideWithValue(localStorage),
            firestoreServiceProvider.overrideWithValue(fakeFirestore),
          ],
          child: const MaterialApp(
            home: HelpAndSupportScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Your Query *'),
        'Testing query submission preservation',
      );
      final sendBtn = find.widgetWithText(ElevatedButton, 'Send Query');
      await tester.ensureVisible(sendBtn);
      await tester.tap(sendBtn);
      await tester.pumpAndSettle();

      expect(fakeFirestore.submittedQueries.length, equals(1));
      expect(fakeFirestore.submittedQueries.first['phoneNumber'], equals(testPhone));
    });

    // 19, 20, 21. Firestore rules validation
    test('19, 20, 21. Firestore rules enforce isAuthorizedAdmin and block public read', () {
      final rulesFile = File('firestore.rules');
      expect(rulesFile.existsSync(), isTrue);
      final content = rulesFile.readAsStringSync();

      // Rule does NOT have allow read: if true; for supportQueries
      expect(content.contains('match /supportQueries/{queryId} {\n      allow create: if isValidSupportQuery();\n      allow read: if true;'), isFalse);
      expect(content.contains('allow read: if isAuthorizedAdmin();'), isTrue);

      // Uses existing Admin authorization phone 8078643910
      expect(content.contains(AppAuthRoles.adminPhone), isTrue);
      expect(content.contains('isAuthorizedAdmin()'), isTrue);
    });

    // 22. No customer phone number is logged/exposed unnecessarily in Admin screen list
    testWidgets('22. Customer phone number is not exposed in list cards', (tester) async {
      setViewport(tester);
      const sensitivePhone = '9876543210';
      final query = SupportQuery(
        id: 'q_privacy',
        name: 'Privacy Minded Customer',
        query: 'Checking if phone is exposed in card',
        phoneNumber: sensitivePhone,
        createdAt: DateTime.now(),
      );
      fakeFirestore.queries.add(query);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            firestoreServiceProvider.overrideWithValue(fakeFirestore),
          ],
          child: const MaterialApp(
            home: AdminCustomerQueriesScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Phone is NOT displayed on the list card
      expect(find.text(sensitivePhone), findsNothing);
      expect(find.text('+91 $sensitivePhone'), findsNothing);
    });
  });
}
