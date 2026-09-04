// BU Gate2Eat — Checkpoint 4.5
// Automated Test Suite for Customer Help & Support Feature

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bugate2eat_app/core/constants/app_constants.dart';
import 'package:bugate2eat_app/core/providers.dart';
import 'package:bugate2eat_app/core/router.dart';
import 'package:bugate2eat_app/features/profile/help_and_support_screen.dart';
import 'package:bugate2eat_app/features/profile/profile_screen.dart';
import 'package:bugate2eat_app/models/support_query_model.dart';
import 'package:bugate2eat_app/panel/admin_panel/admin_profile_screen.dart';
import 'package:bugate2eat_app/panel/shopkeeper_panel/shopkeeper_profile_screen.dart';
import 'package:bugate2eat_app/services/firestore_service.dart';
import 'package:bugate2eat_app/services/local_storage_service.dart';

// Fake FirestoreService to simulate support query submission
class FakeFirestoreService extends Fake implements FirestoreService {
  final List<Map<String, dynamic>> submittedQueries = [];
  bool shouldFail = false;
  int submissionCount = 0;
  Duration? delay;

  @override
  Future<String> submitSupportQuery({
    required String name,
    required String query,
    required String phoneNumber,
    String customerId = '',
  }) async {
    submissionCount++;
    if (delay != null) {
      await Future<void>.delayed(delay!);
    }
    if (shouldFail) {
      throw Exception('Network error during query submission');
    }

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

  late FakeFirestoreService fakeFirestore;
  late SharedPreferences prefs;
  late LocalStorageService localStorage;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'user_name': 'Rajat Joshi',
      'user_phone': '9876543210',
      'customer_id': 'cust_rajat_123',
    });
    prefs = await SharedPreferences.getInstance();
    localStorage = LocalStorageService(prefs);
    fakeFirestore = FakeFirestoreService();
  });

  void setViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  Widget buildTestWidget({Widget? child}) {
    return ProviderScope(
      overrides: [
        localStorageServiceProvider.overrideWithValue(localStorage),
        firestoreServiceProvider.overrideWithValue(fakeFirestore),
      ],
      child: MaterialApp(
        home: child ?? const HelpAndSupportScreen(),
      ),
    );
  }

  group('Checkpoint 4.5 — Customer Help & Support Suite', () {
    // ── 1. Model Serialization & Invariants ──────────────────────────────────
    group('1. SupportQuery Model Tests', () {
      test('SupportQuery constructor and default values', () {
        final now = DateTime.now();
        final query = SupportQuery(
          id: 'sq_1',
          name: 'Rajat Joshi',
          query: 'Order cancellation query',
          phoneNumber: '9876543210',
          createdAt: now,
        );

        expect(query.id, equals('sq_1'));
        expect(query.name, equals('Rajat Joshi'));
        expect(query.query, equals('Order cancellation query'));
        expect(query.phoneNumber, equals('9876543210'));
        expect(query.status, equals('unread'));
        expect(query.createdAt, equals(now));
      });

      test('SupportQuery toMap serializes all fields correctly', () {
        final now = DateTime.now();
        final query = SupportQuery(
          id: 'sq_1',
          name: 'Rajat Joshi',
          query: 'Delivery delay',
          phoneNumber: '9876543210',
          customerId: 'cust_1',
          createdAt: now,
          status: 'unread',
        );

        final map = query.toMap();
        expect(map['id'], equals('sq_1'));
        expect(map['name'], equals('Rajat Joshi'));
        expect(map['query'], equals('Delivery delay'));
        expect(map['phoneNumber'], equals('9876543210'));
        expect(map['phone'], equals('9876543210'));
        expect(map['customerId'], equals('cust_1'));
        expect(map['status'], equals('unread'));
      });

      test('SupportQuery fromMap deserializes and handles fallbacks', () {
        final map = {
          'id': 'sq_99',
          'name': 'Aman Kumar',
          'query': 'Payment issue',
          'phone': '9123456780',
          'customerId': 'cust_99',
          'status': 'unread',
        };

        final query = SupportQuery.fromMap(map);
        expect(query.id, equals('sq_99'));
        expect(query.name, equals('Aman Kumar'));
        expect(query.query, equals('Payment issue'));
        expect(query.phoneNumber, equals('9123456780'));
        expect(query.status, equals('unread'));
      });
    });

    // ── 2. Screen UI & Field Invariants ───────────────────────────────────────
    group('2. HelpAndSupportScreen UI Invariants', () {
      testWidgets('Displays Contact Us section with Email and Instagram handle',
          (tester) async {
        setViewport(tester);
        await tester.pumpWidget(buildTestWidget());
        await tester.pumpAndSettle();

        expect(find.text('Contact Us'), findsOneWidget);
        expect(find.text('Email Us'), findsOneWidget);
        expect(find.text(AppConfig.supportEmail), findsOneWidget);
        expect(find.text('Instagram'), findsOneWidget);
        expect(find.text(AppConfig.supportInstagram), findsOneWidget);
      });

      testWidgets('Displays Send Your Query section with Name and Query fields',
          (tester) async {
        setViewport(tester);
        await tester.pumpWidget(buildTestWidget());
        await tester.pumpAndSettle();

        expect(find.text('Send Your Query'), findsOneWidget);
        expect(find.widgetWithText(TextField, 'Name *'), findsOneWidget);
        expect(find.widgetWithText(TextField, 'Your Query *'), findsOneWidget);
        expect(find.widgetWithText(ElevatedButton, 'Send Query'), findsOneWidget);
      });

      testWidgets('CRITICAL: Phone number is NOT an input field anywhere on this page',
          (tester) async {
        setViewport(tester);
        await tester.pumpWidget(buildTestWidget());
        await tester.pumpAndSettle();

        // Verify there is NO phone number text field or label
        expect(find.widgetWithText(TextField, 'Phone'), findsNothing);
        expect(find.widgetWithText(TextField, 'Phone Number'), findsNothing);
        expect(find.widgetWithText(TextField, 'Contact Number'), findsNothing);

        // Verify customer is NOT shown their phone number on this screen
        expect(find.text('9876543210'), findsNothing);
        expect(find.text('+91 9876543210'), findsNothing);
      });

      testWidgets('Query text field is multiline and uses TextInputAction.newline',
          (tester) async {
        setViewport(tester);
        await tester.pumpWidget(buildTestWidget());
        await tester.pumpAndSettle();

        final queryFieldFinder = find.widgetWithText(TextField, 'Your Query *');
        final TextField queryField = tester.widget(queryFieldFinder);

        expect(queryField.keyboardType, equals(TextInputType.multiline));
        expect(queryField.textInputAction, equals(TextInputAction.newline));
        expect(queryField.minLines, greaterThanOrEqualTo(3));
      });
    });

    // ── 3. Form Validation Tests ─────────────────────────────────────────────
    group('3. Validation & Submission Logic', () {
      testWidgets('Shows error snackbar if Name is empty or whitespace-only',
          (tester) async {
        setViewport(tester);
        await tester.pumpWidget(buildTestWidget());
        await tester.pumpAndSettle();

        // Clear name field
        final nameField = find.widgetWithText(TextField, 'Name *');
        await tester.enterText(nameField, '   ');

        // Enter query
        final queryField = find.widgetWithText(TextField, 'Your Query *');
        await tester.enterText(queryField, 'Valid test query text');

        // Tap send
        final sendBtn = find.widgetWithText(ElevatedButton, 'Send Query');
        await tester.ensureVisible(sendBtn);
        await tester.tap(sendBtn);
        await tester.pumpAndSettle();

        expect(find.text('Please enter your name'), findsOneWidget);
        expect(fakeFirestore.submittedQueries, isEmpty);
      });

      testWidgets('Shows error snackbar if Query is empty or whitespace-only',
          (tester) async {
        setViewport(tester);
        await tester.pumpWidget(buildTestWidget());
        await tester.pumpAndSettle();

        // Enter valid name
        final nameField = find.widgetWithText(TextField, 'Name *');
        await tester.enterText(nameField, 'Rajat');

        // Clear query field
        final queryField = find.widgetWithText(TextField, 'Your Query *');
        await tester.enterText(queryField, '   ');

        // Tap send
        final sendBtn = find.widgetWithText(ElevatedButton, 'Send Query');
        await tester.ensureVisible(sendBtn);
        await tester.tap(sendBtn);
        await tester.pumpAndSettle();

        expect(find.text('Please enter your query'), findsOneWidget);
        expect(fakeFirestore.submittedQueries, isEmpty);
      });

      testWidgets('Successful submission attaches session phone, clears query, and shows success',
          (tester) async {
        setViewport(tester);
        await tester.pumpWidget(buildTestWidget());
        await tester.pumpAndSettle();

        final nameField = find.widgetWithText(TextField, 'Name *');
        await tester.enterText(nameField, 'Rajat Joshi');

        final queryField = find.widgetWithText(TextField, 'Your Query *');
        await tester.enterText(queryField, 'Food was cold upon delivery at Gate 3.');

        fakeFirestore.delay = const Duration(milliseconds: 50);

        final sendBtn = find.widgetWithText(ElevatedButton, 'Send Query');
        await tester.ensureVisible(sendBtn);
        await tester.tap(sendBtn);
        await tester.pump(); // Start async submit

        // Verify loading indicator while in flight
        expect(find.byType(CircularProgressIndicator), findsOneWidget);

        await tester.pumpAndSettle(); // Finish async

        // Verify query was submitted to Firestore
        expect(fakeFirestore.submittedQueries.length, equals(1));
        final submitted = fakeFirestore.submittedQueries.first;
        expect(submitted['name'], equals('Rajat Joshi'));
        expect(submitted['query'], equals('Food was cold upon delivery at Gate 3.'));
        // Critical: Phone number was automatically attached from session!
        expect(submitted['phoneNumber'], equals('9876543210'));
        expect(submitted['status'], equals('unread'));

        // Verify success snackbar
        expect(find.text('Your query has been submitted successfully!'), findsOneWidget);

        // Verify query input was cleared
        final TextField updatedQueryField = tester.widget(queryField);
        expect(updatedQueryField.controller?.text, isEmpty);
      });

      testWidgets('Failed submission shows error snackbar and preserves query text',
          (tester) async {
        setViewport(tester);
        fakeFirestore.shouldFail = true;

        await tester.pumpWidget(buildTestWidget());
        await tester.pumpAndSettle();

        final nameField = find.widgetWithText(TextField, 'Name *');
        await tester.enterText(nameField, 'Rajat Joshi');

        final queryField = find.widgetWithText(TextField, 'Your Query *');
        await tester.enterText(queryField, 'Critical issue with payment');

        final sendBtn = find.widgetWithText(ElevatedButton, 'Send Query');
        await tester.ensureVisible(sendBtn);
        await tester.tap(sendBtn);
        await tester.pumpAndSettle();

        // Verify error snackbar
        expect(find.text('Failed to submit query. Please try again.'), findsOneWidget);

        // Verify query text is preserved so user does not lose input
        final TextField preservedQueryField = tester.widget(queryField);
        expect(preservedQueryField.controller?.text, equals('Critical issue with payment'));
      });

      testWidgets('Rapid duplicate taps trigger only ONE submission',
          (tester) async {
        setViewport(tester);
        await tester.pumpWidget(buildTestWidget());
        await tester.pumpAndSettle();

        final nameField = find.widgetWithText(TextField, 'Name *');
        await tester.enterText(nameField, 'Rajat Joshi');

        final queryField = find.widgetWithText(TextField, 'Your Query *');
        await tester.enterText(queryField, 'Testing double tap');

        final sendButton = find.widgetWithText(ElevatedButton, 'Send Query');
        await tester.ensureVisible(sendButton);

        // Tap once
        await tester.tap(sendButton);
        // Rapid second tap while in flight
        await tester.tap(sendButton);

        await tester.pumpAndSettle();

        expect(fakeFirestore.submissionCount, equals(1));
        expect(fakeFirestore.submittedQueries.length, equals(1));
      });
    });

    // ── 4. Profile Screen Isolation Tests ─────────────────────────────────────
    group('4. Profile Screen & Route Isolation Tests', () {
      testWidgets('Customer ProfileScreen contains "Help & Support" button',
          (tester) async {
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

        expect(find.widgetWithText(ListTile, 'Help & Support'), findsOneWidget);
        expect(find.text('Contact us or send a query'), findsOneWidget);
      });

      testWidgets('ShopkeeperProfileScreen does NOT contain "Help & Support"',
          (tester) async {
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

        expect(find.widgetWithText(ListTile, 'Help & Support'), findsNothing);
      });

      testWidgets('AdminProfileScreen does NOT contain "Help & Support"',
          (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              localStorageServiceProvider.overrideWithValue(localStorage),
              firestoreServiceProvider.overrideWithValue(fakeFirestore),
            ],
            child: const MaterialApp(
              home: AdminProfileScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.widgetWithText(ListTile, 'Help & Support'), findsNothing);
      });

      test('AppRoutes.helpAndSupport path is /help-and-support', () {
        expect(AppRoutes.helpAndSupport, equals('/help-and-support'));
      });
    });
  });
}
