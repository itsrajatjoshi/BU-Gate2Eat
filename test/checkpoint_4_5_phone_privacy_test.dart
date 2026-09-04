// BU Gate2Eat — Checkpoint 4.5
// STEP 3: Automated Test Suite for Customer Phone Number Privacy

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bugate2eat_app/core/constants/app_constants.dart';
import 'package:bugate2eat_app/core/providers.dart';
import 'package:bugate2eat_app/features/profile/help_and_support_screen.dart';
import 'package:bugate2eat_app/features/profile/profile_screen.dart';
import 'package:bugate2eat_app/panel/admin_panel/admin_profile_screen.dart';
import 'package:bugate2eat_app/panel/shopkeeper_panel/shopkeeper_profile_screen.dart';
import 'package:bugate2eat_app/services/firestore_service.dart';
import 'package:bugate2eat_app/services/local_storage_service.dart';

// Fake FirestoreService to verify Help & Support auto-attachment in Step 3
class FakeFirestoreServiceStep3 extends Fake implements FirestoreService {
  final List<Map<String, dynamic>> submittedQueries = [];

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

  late FakeFirestoreServiceStep3 fakeFirestore;

  setUp(() {
    fakeFirestore = FakeFirestoreServiceStep3();
  });

  void setViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  group('Checkpoint 4.5 — STEP 3: Customer Phone Number Privacy', () {
    const testCustomerPhone = '9876543210';
    const testCustomerName = 'Aarav Sharma';

    testWidgets('1. Customer Profile does NOT display the customer phone number anywhere', (tester) async {
      setViewport(tester);
      SharedPreferences.setMockInitialValues({
        'user_name': testCustomerName,
        'user_phone': testCustomerPhone,
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

      // Customer name is displayed
      expect(find.text(testCustomerName), findsWidgets);
      expect(find.text('Bennett University'), findsOneWidget);

      // Customer phone number is NOT displayed in any form
      expect(find.text(testCustomerPhone), findsNothing);
      expect(find.text('+91 $testCustomerPhone'), findsNothing);
      expect(find.textContaining(testCustomerPhone), findsNothing);
    });

    testWidgets('2. Customer Profile does NOT have any phone input field or phone ListTile', (tester) async {
      setViewport(tester);
      SharedPreferences.setMockInitialValues({
        'user_name': testCustomerName,
        'user_phone': testCustomerPhone,
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

      // Exactly ONE text field for Name
      expect(find.byType(TextField), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Name'), findsOneWidget);

      // No phone textfield or phone label
      expect(find.text('Phone Number (Account Identity)'), findsNothing);
      expect(find.text('Phone Number'), findsNothing);
      expect(find.byIcon(Icons.phone_outlined), findsNothing);
    });

    testWidgets('3. Customer Profile has NO Change Phone / Edit Phone / Update Phone option', (tester) async {
      setViewport(tester);
      SharedPreferences.setMockInitialValues({
        'user_name': testCustomerName,
        'user_phone': testCustomerPhone,
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

      expect(find.text('Change Phone'), findsNothing);
      expect(find.text('Change Phone Number'), findsNothing);
      expect(find.text('Edit Phone'), findsNothing);
      expect(find.text('Edit Phone Number'), findsNothing);
      expect(find.text('Update Phone'), findsNothing);
      expect(find.text('Change Number'), findsNothing);
    });

    testWidgets('4. Updating name in Customer Profile preserves backend session phone', (tester) async {
      setViewport(tester);
      SharedPreferences.setMockInitialValues({
        'user_name': testCustomerName,
        'user_phone': testCustomerPhone,
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

      // Enter new name and save
      final nameFinder = find.widgetWithText(TextField, 'Name');
      await tester.enterText(nameFinder, 'Aarav Updated');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Save Changes'));
      await tester.pumpAndSettle();

      // Local storage name is updated, but phone is preserved completely!
      expect(localStorage.userName, equals('Aarav Updated'));
      expect(localStorage.userPhone, equals(testCustomerPhone));
    });

    testWidgets('5. Customer Identity provider retains phone internally without exposing to customer', (tester) async {
      SharedPreferences.setMockInitialValues({
        'user_name': testCustomerName,
        'user_phone': testCustomerPhone,
        'user_age': 20,
      });
      final prefs = await SharedPreferences.getInstance();
      final localStorage = LocalStorageService(prefs);

      final container = ProviderContainer(
        overrides: [
          localStorageServiceProvider.overrideWithValue(localStorage),
        ],
      );

      final identity = container.read(customerIdentityProvider);
      expect(identity.phone, equals(testCustomerPhone));
      expect(identity.name, equals(testCustomerName));
      expect(identity.customerId, isNotEmpty);
    });

    testWidgets('6. Help & Support screen has NO phone input field and does not display phone', (tester) async {
      setViewport(tester);
      SharedPreferences.setMockInitialValues({
        'user_name': testCustomerName,
        'user_phone': testCustomerPhone,
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

      // Only Name and Query fields exist
      expect(find.byType(TextField), findsNWidgets(2));
      expect(find.widgetWithText(TextField, 'Name *'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Your Query *'), findsOneWidget);

      // Phone is NOT displayed or requested
      expect(find.text(testCustomerPhone), findsNothing);
      expect(find.textContaining('Phone Number'), findsNothing);
      expect(find.textContaining('Phone'), findsNothing);
      expect(find.widgetWithText(TextField, 'Phone'), findsNothing);
    });

    testWidgets('7. Help & Support query submission STILL automatically attaches session phone', (tester) async {
      setViewport(tester);
      SharedPreferences.setMockInitialValues({
        'user_name': testCustomerName,
        'user_phone': testCustomerPhone,
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

      // Fill query and submit
      await tester.enterText(
        find.widgetWithText(TextField, 'Your Query *'),
        'Need assistance with payment refund.',
      );
      final sendBtn = find.widgetWithText(ElevatedButton, 'Send Query');
      await tester.ensureVisible(sendBtn);
      await tester.tap(sendBtn);
      await tester.pumpAndSettle();

      // Verify query was recorded with attached phone number from session
      expect(fakeFirestore.submittedQueries.length, equals(1));
      final query = fakeFirestore.submittedQueries.first;
      expect(query['name'], equals(testCustomerName));
      expect(query['query'], equals('Need assistance with payment refund.'));
      expect(query['phoneNumber'], equals(testCustomerPhone));
      expect(query['status'], equals('unread'));
    });

    testWidgets('8. Admin Profile screen still displays Admin phone number (Admin role preserved)', (tester) async {
      setViewport(tester);
      SharedPreferences.setMockInitialValues({
        'user_name': 'Rajat Admin',
        'user_phone': AppAuthRoles.adminPhone,
        'user_age': 25,
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

      // Admin profile still has the phone number displayed
      expect(find.textContaining(AppAuthRoles.adminPhone), findsWidgets);
    });

    testWidgets('9. Shopkeeper Profile screen still displays Shopkeeper phone number (Shop role preserved)', (tester) async {
      setViewport(tester);
      const testShopPhone = '8000383993'; // registered shop phone
      SharedPreferences.setMockInitialValues({
        'user_name': 'Rajat Shopkeeper',
        'user_phone': testShopPhone,
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

      // Shopkeeper profile still has the phone number displayed
      expect(find.textContaining(testShopPhone), findsWidgets);
    });
  });
}
