// BU Gate2Eat — Logout Unit Tests
// Tests for LocalStorageService.logout()

import 'package:bugate2eat_app/services/local_storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BU Gate2Eat — Logout Tests', () {
    test('logout() clears user profile and onboarding state while preserving theme and favorites', () async {
      SharedPreferences.setMockInitialValues({
        'is_onboarded': true,
        'user_name': 'Rajat Joshi',
        'user_phone': '9876543210',
        'user_age': 21,
        'theme_mode': 'dark',
        'favorite_item_ids': ['rajat_shop:veg_steam_momos'],
      });

      final localStorage = await LocalStorageService.create();

      // Verify initial session state
      expect(localStorage.isOnboarded, isTrue);
      expect(localStorage.userName, equals('Rajat Joshi'));
      expect(localStorage.userPhone, equals('9876543210'));
      expect(localStorage.userAge, equals(21));
      expect(localStorage.themeMode, equals('dark'));
      expect(localStorage.favoriteItemIds, equals(['rajat_shop:veg_steam_momos']));

      // Perform Logout
      await localStorage.logout();

      // Verify user session is cleared
      expect(localStorage.isOnboarded, isFalse);
      expect(localStorage.userName, isEmpty);
      expect(localStorage.userPhone, isEmpty);
      expect(localStorage.userAge, equals(0));

      // Verify non-session preferences like theme are preserved
      expect(localStorage.themeMode, equals('dark'));
    });
  });
}
