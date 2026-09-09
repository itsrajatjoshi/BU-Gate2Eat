// BU Gate2Eat — Services
// Local storage service for user profile data

import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants/app_constants.dart';

/// Service for managing locally stored user data.
/// User profile is stored on-device only (no server-side accounts).
class LocalStorageService {
  /// Creates an instance with an initialized SharedPreferences.
  LocalStorageService(this._prefs) {
    current = this;
  }

  /// Globally accessible active instance for synchronous route redirects and security checks.
  static LocalStorageService? current;

  static const String _keyName = 'user_name';
  static const String _keyPhone = 'user_phone';
  static const String _keyAge = 'user_age';
  static const String _keyCustomerId = 'customer_id';
  static const String _keyIsOnboarded = 'is_onboarded';
  static const String _keyIsOtpVerified = 'is_otp_verified';
  static const String _keyVerifiedPhone = 'verified_phone';
  static const String _keyThemeMode = 'theme_mode';

  // ─── Purchase Attempt Idempotency Persistence (Phase 4.4) ──────
  static const String _keyPendingOrderId = 'pending_order_id';
  static const String _keyPendingCartSignature = 'pending_cart_signature';
  static const String _keyPendingIdempotencyKey = 'pending_idempotency_key';
  static const String _keyPendingOrderTimestamp = 'pending_order_timestamp';
  static const int _pendingAttemptTtlHours = 24;

  final SharedPreferences _prefs;

  /// Factory method to create an instance with initialized SharedPreferences.
  static Future<LocalStorageService> create() async {
    final prefs = await SharedPreferences.getInstance();
    final service = LocalStorageService(prefs);
    current = service;
    return service;
  }

  // ─── Onboarding & OTP Verification State ─────────────────────

  /// Whether the user has completed the first-time setup (entered Name).
  bool get isOnboarded => _prefs.getBool(_keyIsOnboarded) ?? false;

  /// Marks onboarding as complete.
  Future<void> setOnboarded() async {
    await _prefs.setBool(_keyIsOnboarded, true);
  }

  /// Whether the temporary OTP verification succeeded before Name submission.
  bool get isOtpVerified => _prefs.getBool(_keyIsOtpVerified) ?? false;

  /// Gets the verified phone number for the active onboarding attempt.
  String get verifiedPhone => _prefs.getString(_keyVerifiedPhone) ?? '';

  /// Persists temporary OTP verification state across app restarts.
  Future<void> saveOtpVerificationState(String phone) async {
    final cleanPhone = AppAuthRoles.normalizeCleanPhone(phone);
    await _prefs.setBool(_keyIsOtpVerified, true);
    await _prefs.setString(_keyVerifiedPhone, cleanPhone);
  }

  /// Clears temporary OTP verification state.
  Future<void> clearOtpVerificationState() async {
    await _prefs.remove(_keyIsOtpVerified);
    await _prefs.remove(_keyVerifiedPhone);
  }

  // ─── Local Presentation & Cache Data (Demoted from Security Authority) ───
  // NOTE (Checkpoint 1.4):
  // Values stored here (customerId, userPhone, userName) are strictly local cache
  // and UI presentation preferences. They carry ZERO security or authorization authority.
  // Authoritative identity originates strictly from Firebase Auth (CurrentIdentity / uid).

  /// Gets the locally cached customer ID for offline/test presentation.
  /// Non-authoritative: Authoritative security identity is strictly Firebase UID.
  String get customerId {
    final rawPhone = userPhone.trim();
    final phone = AppAuthRoles.normalizeCleanPhone(rawPhone);
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

  /// Gets the stored phone number (normalized 10 digits when valid).
  String get userPhone => _prefs.getString(_keyPhone) ?? '';

  /// Gets the stored user age.
  int get userAge => _prefs.getInt(_keyAge) ?? 0;

  /// Saves user profile data during onboarding.
  Future<void> saveUserProfile({
    required String name,
    required String phone,
    int? age,
  }) async {
    final cleanPhone = AppAuthRoles.normalizeCleanPhone(phone);
    await _prefs.setString(_keyName, name.trim());
    await _prefs.setString(_keyPhone, cleanPhone);
    if (cleanPhone.isNotEmpty) {
      await _prefs.setString(_keyCustomerId, 'cust_$cleanPhone');
    }
    if (age != null) {
      await _prefs.setInt(_keyAge, age);
    }
    await _prefs.setBool(_keyIsOnboarded, true);
    await clearOtpVerificationState();
  }

  /// Updates the user name.
  Future<void> updateName(String name) async {
    await _prefs.setString(_keyName, name);
  }

  /// Updates the phone number and synchronizes the customer ID.
  Future<void> updatePhone(String phone) async {
    final cleanPhone = AppAuthRoles.normalizeCleanPhone(phone);
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

  // ─── Purchase Attempt Idempotency Persistence (Phase 4.4) ──────

  /// Whether an active, unexpired purchase attempt is stored in persistent local storage.
  bool get hasActivePendingAttempt {
    final key = pendingIdempotencyKey;
    final sig = pendingCartSignature;
    final time = pendingOrderTimestamp;
    if (key == null || key.isEmpty || sig == null || sig.isEmpty || time == null) {
      return false;
    }
    final age = DateTime.now().difference(time);
    if (age.isNegative || age.inHours >= _pendingAttemptTtlHours) {
      return false;
    }
    return true;
  }

  /// Gets the persisted pending order ID if present.
  String? get pendingOrderId => _prefs.getString(_keyPendingOrderId);

  /// Gets the persisted pending cart fingerprint signature if present.
  String? get pendingCartSignature => _prefs.getString(_keyPendingCartSignature);

  /// Gets the persisted pending idempotency key if present.
  String? get pendingIdempotencyKey => _prefs.getString(_keyPendingIdempotencyKey);

  /// Gets the persisted timestamp when the pending purchase attempt was initiated.
  DateTime? get pendingOrderTimestamp {
    final ms = _prefs.getInt(_keyPendingOrderTimestamp);
    return ms != null ? DateTime.fromMillisecondsSinceEpoch(ms) : null;
  }

  /// Retrieves the active unexpired pending idempotency key matching [cartSignature].
  /// Returns null if missing, expired (>24h), or if the cart signature has changed.
  String? getActivePendingIdempotencyKey(String cartSignature) {
    if (!hasActivePendingAttempt) return null;
    if (pendingCartSignature != cartSignature) return null;
    return pendingIdempotencyKey;
  }

  /// Retrieves the active unexpired pending orderId matching [cartSignature].
  /// Returns null if missing, expired (>24h), or if the cart signature has changed.
  String? getActivePendingOrderId(String cartSignature) {
    if (!hasActivePendingAttempt) return null;
    if (pendingCartSignature != cartSignature) return null;
    return pendingOrderId;
  }

  /// Persists an active purchase attempt to ensure network retries reuse the identical
  /// idempotency key and orderId across app backgrounding, widget unmounting, and app restarts.
  Future<void> savePendingOrderAttempt({
    required String orderId,
    required String cartSignature,
    required String idempotencyKey,
    DateTime? timestamp,
  }) async {
    final time = timestamp ?? DateTime.now();
    await _prefs.setString(_keyPendingOrderId, orderId);
    await _prefs.setString(_keyPendingCartSignature, cartSignature);
    await _prefs.setString(_keyPendingIdempotencyKey, idempotencyKey);
    await _prefs.setInt(_keyPendingOrderTimestamp, time.millisecondsSinceEpoch);
  }

  /// Clears the persisted purchase attempt upon confirmed order creation,
  /// explicit cart reset, or user logout.
  Future<void> clearPendingOrderAttempt() async {
    await _prefs.remove(_keyPendingOrderId);
    await _prefs.remove(_keyPendingCartSignature);
    await _prefs.remove(_keyPendingIdempotencyKey);
    await _prefs.remove(_keyPendingOrderTimestamp);
  }

  // ─── Session Management ────────────────────────────────────

  /// Clears the user profile, customer identity, and onboarding state, effectively logging out.
  Future<void> logout() async {
    await clearOtpVerificationState();
    await clearPendingOrderAttempt();
    await _prefs.remove(_keyIsOnboarded);
    await _prefs.remove(_keyName);
    await _prefs.remove(_keyPhone);
    await _prefs.remove(_keyAge);
    await _prefs.remove(_keyCustomerId);
    await _prefs.remove(_keyFavorites);
  }

  /// Permanently deletes customer account profile, identity, favorites, and session state.
  Future<void> deleteCustomerAccount() async {
    await clearOtpVerificationState();
    await clearPendingOrderAttempt();
    await _prefs.remove(_keyIsOnboarded);
    await _prefs.remove(_keyName);
    await _prefs.remove(_keyPhone);
    await _prefs.remove(_keyAge);
    await _prefs.remove(_keyCustomerId);
    await _prefs.remove(_keyFavorites);
  }
}

