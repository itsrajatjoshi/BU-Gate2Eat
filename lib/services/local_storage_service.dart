// BU Gate2Eat — Services
// Local storage service for user profile data

import 'package:shared_preferences/shared_preferences.dart';

/// Service for managing locally stored user data.
/// User profile is stored on-device only (no server-side accounts).
class LocalStorageService {
  /// Creates an instance with an initialized SharedPreferences.
  LocalStorageService(this._prefs);

  static const String _keyName = 'user_name';
  static const String _keyPhone = 'user_phone';
  static const String _keyAge = 'user_age';
  static const String _keyCustomerId = 'customer_id';
  static const String _keyIsOnboarded = 'is_onboarded';
  static const String _keyThemeMode = 'theme_mode';

  final SharedPreferences _prefs;

  /// Factory method to create an instance with initialized SharedPreferences.
  static Future<LocalStorageService> create() async {
    final prefs = await SharedPreferences.getInstance();
    return LocalStorageService(prefs);
  }

  // ─── Onboarding ─────────────────────────────────────────────

  /// Whether the user has completed the first-time setup.
  bool get isOnboarded => _prefs.getBool(_keyIsOnboarded) ?? false;

  /// Marks onboarding as complete.
  Future<void> setOnboarded() async {
    await _prefs.setBool(_keyIsOnboarded, true);
  }

  // ─── User Profile & Identity ───────────────────────────────

  /// Gets the stored customer ID or initializes a stable device/phone identifier.
  /// When a phone number exists, customer ID is strictly and deterministically derived from it.
  String get customerId {
    final phone = userPhone.trim();
    if (phone.isNotEmpty) {
      final expectedId = 'cust_$phone';
      final currentId = _prefs.getString(_keyCustomerId);
      if (currentId != expectedId) {
        _prefs.setString(_keyCustomerId, expectedId);
      }
      return expectedId;
    }

    var id = _prefs.getString(_keyCustomerId);
    if (id == null || id.isEmpty) {
      final rand = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
      id = 'cust_anon_$rand';
      _prefs.setString(_keyCustomerId, id);
    }
    return id;
  }

  /// Gets the stored user name.
  String get userName => _prefs.getString(_keyName) ?? '';

  /// Gets the stored phone number.
  String get userPhone => _prefs.getString(_keyPhone) ?? '';

  /// Gets the stored user age.
  int get userAge => _prefs.getInt(_keyAge) ?? 0;

  /// Saves user profile data during onboarding.
  Future<void> saveUserProfile({
    required String name,
    required String phone,
    int? age,
  }) async {
    final cleanPhone = phone.trim();
    await _prefs.setString(_keyName, name.trim());
    await _prefs.setString(_keyPhone, cleanPhone);
    if (cleanPhone.isNotEmpty) {
      await _prefs.setString(_keyCustomerId, 'cust_$cleanPhone');
    }
    if (age != null) {
      await _prefs.setInt(_keyAge, age);
    }
    await _prefs.setBool(_keyIsOnboarded, true);
  }

  /// Updates the user name.
  Future<void> updateName(String name) async {
    await _prefs.setString(_keyName, name);
  }

  /// Updates the phone number and synchronizes the customer ID.
  Future<void> updatePhone(String phone) async {
    final cleanPhone = phone.trim();
    await _prefs.setString(_keyPhone, cleanPhone);
    if (cleanPhone.isNotEmpty) {
      await _prefs.setString(_keyCustomerId, 'cust_$cleanPhone');
    }
  }

  /// Updates the age.
  Future<void> updateAge(int age) async {
    await _prefs.setInt(_keyAge, age);
  }

  static const String _keyFavorites = 'favorite_item_ids';

  // ─── Theme ──────────────────────────────────────────────────

  /// Gets the stored theme mode: permanently 'light'.
  String get themeMode => 'light';

  /// Saves the selected theme mode (no-op; light mode locked).
  Future<void> setThemeMode(String mode) async {
    await _prefs.setString(_keyThemeMode, 'light');
  }

  // ─── Favorites ──────────────────────────────────────────────

  /// Gets the locally stored list of favorite menu item IDs.
  List<String> get favoriteItemIds =>
      _prefs.getStringList(_keyFavorites) ?? [];

  /// Persists the list of favorite menu item IDs locally.
  Future<void> saveFavoriteItemIds(List<String> ids) async {
    await _prefs.setStringList(_keyFavorites, ids);
  }

  // ─── Session Management ────────────────────────────────────

  /// Clears the user profile, customer identity, and onboarding state, effectively logging out.
  Future<void> logout() async {
    await _prefs.remove(_keyIsOnboarded);
    await _prefs.remove(_keyName);
    await _prefs.remove(_keyPhone);
    await _prefs.remove(_keyAge);
    await _prefs.remove(_keyCustomerId);
  }
}
