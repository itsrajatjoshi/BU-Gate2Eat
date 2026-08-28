// BU Gate2Eat — Services
// Firebase Cloud Messaging (FCM) & Device Token Registration Service (Part 2)
// Centralized token lifecycle management and idempotent Firestore registration.

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../core/constants/app_constants.dart';
import 'local_storage_service.dart';

/// Service responsible for FCM initialization, device token retrieval,
/// token refresh listening, and Firestore device token synchronization.
class NotificationService {
  NotificationService({
    FirebaseMessaging? messaging,
    FirebaseFirestore? firestore,
  })  : _messaging = messaging,
        _firestore = firestore;

  final FirebaseMessaging? _messaging;
  final FirebaseFirestore? _firestore;

  StreamSubscription<String>? _tokenRefreshSubscription;
  String? _cachedToken;
  String? _lastRegisteredPhone;
  String? _lastRegisteredRole;
  String? _lastRegisteredShopId;

  /// Gets the active FirebaseMessaging instance if available.
  FirebaseMessaging? get _messagingInstance {
    if (_messaging != null) return _messaging;
    try {
      if (Firebase.apps.isNotEmpty) {
        return FirebaseMessaging.instance;
      }
    } catch (_) {}
    return null;
  }

  /// Gets the active FirebaseFirestore instance if available.
  FirebaseFirestore? get _firestoreInstance {
    if (_firestore != null) return _firestore;
    try {
      if (Firebase.apps.isNotEmpty) {
        return FirebaseFirestore.instance;
      }
    } catch (_) {}
    return null;
  }

  /// Currently cached FCM token in memory.
  String? get cachedToken => _cachedToken;

  /// Current platform identifier ('android', 'ios', 'web', 'unknown').
  String get currentPlatform {
    if (kIsWeb) return 'web';
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.iOS:
        return 'ios';
      default:
        return 'unknown';
    }
  }

  /// Masks token string for safe development logging.
  static String maskToken(String? token) {
    if (token == null || token.isEmpty) return '<null>';
    if (token.length <= 12) return '***';
    return '${token.substring(0, 6)}...${token.substring(token.length - 6)} (${token.length} chars)';
  }

  /// Initializes the notification service foundation and attaches token refresh listener.
  /// Does NOT block app startup if FCM is unavailable or permission is pending.
  Future<void> initialize({LocalStorageService? localStorage}) async {
    try {
      debugPrint('🔔 [FCM] NotificationService initialization started...');
      final messaging = _messagingInstance;
      if (messaging == null) {
        debugPrint('⚠️ [FCM] Firebase not initialized; skipping FCM setup.');
        return;
      }

      // Retrieve initial token safely
      final token = await getToken();
      _cachedToken = token;

      if (token != null && localStorage != null) {
        await syncCurrentSessionToken(localStorage: localStorage);
      }

      // Attach token refresh listener
      _listenToTokenRefresh(localStorage);

      debugPrint('✅ [FCM] NotificationService initialized successfully. Cached Token: ${maskToken(_cachedToken)}');
    } catch (e, stack) {
      debugPrint('⚠️ [FCM] NotificationService init note (non-fatal): $e\n$stack');
    }
  }

  /// Safely obtains the device's current FCM registration token.
  Future<String?> getToken() async {
    try {
      final messaging = _messagingInstance;
      if (messaging == null) return null;

      final token = await messaging.getToken();
      if (token != null) {
        _cachedToken = token;
        debugPrint('🔑 [FCM] Token received: ${maskToken(token)}');
      }
      return token;
    } catch (e) {
      debugPrint('⚠️ [FCM] Token retrieval note (non-fatal): $e');
      return null;
    }
  }

  /// Listens to FCM token refresh events and updates the Firestore registration.
  void _listenToTokenRefresh(LocalStorageService? localStorage) {
    try {
      final messaging = _messagingInstance;
      if (messaging == null) return;

      _tokenRefreshSubscription?.cancel();
      _tokenRefreshSubscription = messaging.onTokenRefresh.listen(
        (newToken) async {
          debugPrint('🔄 [FCM] Token refresh detected: ${maskToken(newToken)}');
          _cachedToken = newToken;
          if (localStorage != null) {
            await syncCurrentSessionToken(localStorage: localStorage);
          } else if (_lastRegisteredPhone != null) {
            await registerDeviceToken(
              token: newToken,
              phone: _lastRegisteredPhone!,
              role: _lastRegisteredRole ?? 'customer',
              shopId: _lastRegisteredShopId,
            );
          }
        },
        onError: (Object error) {
          debugPrint('⚠️ [FCM] Token refresh error (non-fatal): $error');
        },
      );
    } catch (e) {
      debugPrint('⚠️ [FCM] Token refresh listener error: $e');
    }
  }

  /// Synchronizes the current user session's device token with Firestore.
  /// Dynamically determines whether the user is a customer, shopkeeper, or admin.
  Future<void> syncCurrentSessionToken({
    required LocalStorageService localStorage,
    String? explicitRole,
    String? explicitShopId,
  }) async {
    final token = _cachedToken ?? await getToken();
    if (token == null || token.isEmpty) {
      debugPrint('⚠️ [FCM] No token available to sync session.');
      return;
    }

    final phone = localStorage.userPhone.trim();
    final customerId = localStorage.customerId;

    // Determine role and shopId
    String role = explicitRole ?? 'customer';
    String? shopId = explicitShopId;

    if (explicitRole == null) {
      if (phone == AppAuthRoles.adminPhone) {
        role = 'admin';
      } else {
        final mappedShop = AppAuthRoles.getShopIdForPhone(phone);
        if (mappedShop != null) {
          role = 'shopkeeper';
          shopId = mappedShop;
        } else {
          role = 'customer';
          shopId = null;
        }
      }
    }

    await registerDeviceToken(
      token: token,
      phone: phone,
      role: role,
      shopId: shopId,
      customerId: customerId,
    );
  }

  /// Idempotently registers or updates the device token in Firestore under `deviceTokens/{token}`.
  /// Uses token as document ID to guarantee zero duplicates on repeated app launches.
  Future<void> registerDeviceToken({
    required String token,
    required String phone,
    required String role,
    String? shopId,
    String? customerId,
  }) async {
    if (token.isEmpty) return;

    try {
      final firestore = _firestoreInstance;
      if (firestore == null) {
        debugPrint('⚠️ [FCM] Firestore not available for token registration.');
        return;
      }

      final cleanPhone = phone.trim();
      final effectiveCustomerId = customerId ?? (cleanPhone.isNotEmpty ? 'cust_$cleanPhone' : 'cust_anon');

      final tokenDocRef = firestore.collection('deviceTokens').doc(token);

      final data = <String, dynamic>{
        'token': token,
        'phone': cleanPhone,
        'role': role,
        'shopId': shopId,
        'customerId': effectiveCustomerId,
        'platform': currentPlatform,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      // Set with merge: true ensures createdAt is preserved if existing, or written if new.
      await tokenDocRef.set(data, SetOptions(merge: true));

      _lastRegisteredPhone = cleanPhone;
      _lastRegisteredRole = role;
      _lastRegisteredShopId = shopId;

      debugPrint(
        '📱 [FCM] Device token registered: role=$role, phone=${cleanPhone.isEmpty ? "anon" : cleanPhone}, shopId=${shopId ?? "none"}',
      );
    } catch (e, stack) {
      debugPrint('⚠️ [FCM] Device token registration failed (non-fatal): $e\n$stack');
    }
  }

  /// Cleans up token listener when disposing.
  void dispose() {
    _tokenRefreshSubscription?.cancel();
    _tokenRefreshSubscription = null;
  }
}
