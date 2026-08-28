// BU Gate2Eat — Test Suite
// Checkpoint 1B: Item #2 (App Version Sync) & Item #3 (Admin Profile Persistence & Security)

import 'package:bugate2eat_app/core/constants/app_constants.dart';
import 'package:bugate2eat_app/core/providers.dart';
import 'package:bugate2eat_app/features/settings/settings_screen.dart';
import 'package:bugate2eat_app/panel/admin_panel/admin_profile_screen.dart';
import 'package:bugate2eat_app/services/local_storage_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Checkpoint 1B — Item #2: App Version Sync & Centralization', () {
    test('1. AppConfig.appVersion matches 1.0.7 single source of truth', () {
      expect(AppConfig.appVersion, '1.0.7');
    });

    testWidgets('2. Settings screen displays 1.0.7 app version', (tester) async {
      SharedPreferences.setMockInitialValues({
        'user_name': 'Rajat Joshi',
        'user_phone': '8078643910',
      });
      final prefs = await SharedPreferences.getInstance();
      final localStorage = LocalStorageService(prefs);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localStorageServiceProvider.overrideWithValue(localStorage),
          ],
          child: const MaterialApp(
            home: SettingsScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('App Version'), findsOneWidget);
      expect(find.text('1.0.7'), findsOneWidget);
      expect(find.text('1.0.4'), findsNothing);
    });
  });

  group('Checkpoint 1B — Item #3: Admin Profile Persistence & Security', () {
    testWidgets('1. Loads and displays persisted Admin profile details from LocalStorage', (tester) async {
      SharedPreferences.setMockInitialValues({
        'user_name': 'Rajat Chief Admin',
        'user_phone': '8078643910',
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

      expect(find.text('Rajat Chief Admin'), findsWidgets);
      expect(find.text('+91 8078643910'), findsWidgets);
      expect(find.text('26'), findsOneWidget);
      expect(find.text('ADMIN'), findsOneWidget);
    });

    testWidgets('2. Saves updated Admin Name and Age to LocalStorage', (tester) async {
      SharedPreferences.setMockInitialValues({
        'user_name': 'Original Admin',
        'user_phone': '8078643910',
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

      // Enter new name and age
      final nameField = find.widgetWithText(TextField, 'Full Name');
      final ageField = find.widgetWithText(TextField, 'Age');
      final saveButton = find.widgetWithText(ElevatedButton, 'Save Changes');

      await tester.enterText(nameField, 'Updated Head Admin');
      await tester.enterText(ageField, '28');
      await tester.tap(saveButton);
      await tester.pumpAndSettle();

      // Verify localStorage was updated
      expect(localStorage.userName, 'Updated Head Admin');
      expect(localStorage.userAge, 28);
      expect(find.text('Admin Profile updated successfully'), findsOneWidget);
      expect(find.text('Updated Head Admin'), findsWidgets);
    });

    testWidgets('3. Empty name validation prevents invalid update', (tester) async {
      SharedPreferences.setMockInitialValues({
        'user_name': 'Rajat Joshi',
        'user_phone': '8078643910',
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

      final nameField = find.widgetWithText(TextField, 'Full Name');
      final saveButton = find.widgetWithText(ElevatedButton, 'Save Changes');

      await tester.enterText(nameField, '   ');
      await tester.tap(saveButton);
      await tester.pumpAndSettle();

      // Name must NOT be wiped in LocalStorage
      expect(localStorage.userName, 'Rajat Joshi');
      expect(find.text('Name cannot be empty'), findsOneWidget);
    });

    test('4. Admin authorization is strictly derived from phone and cannot be altered by profile edits', () {
      expect(AppAuthRoles.isAdminPhone('8078643910'), isTrue);
      expect(AppAuthRoles.isAdminPhone('+91 8078643910'), isTrue);
      expect(AppAuthRoles.isAdminPhone('8295643910'), isFalse); // Shopkeeper phone
      expect(AppAuthRoles.isAdminPhone('9999999999'), isFalse); // Random phone
    });
  });
}
