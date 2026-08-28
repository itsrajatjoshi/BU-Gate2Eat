// BU Gate2Eat — Services
// Firebase Cloud Messaging (FCM) & Device Token Registration Service (Part 2, 3, 7)
// Centralized token lifecycle management, permission handling, session switching, and foreground/background/killed app listeners.

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../core/constants/app_constants.dart';
import 'local_storage_service.dart';

/// Top-level background message handler invoked by Firebase when the app is in the background or killed.
/// Must be annotated with @pragma('vm:entry-point') so it is not tree-shaken by the Dart AOT compiler.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    debugPrint(
      '🌙 [FCM Background] Message received in background isolate: type=${message.data['type'] ?? 'unknown'}, orderId=${message.data['orderId'] ?? 'none'}',
    );
  } catch (e) {
    debugPrint('⚠️ [FCM Background] Note handling background message: $e');
  }
}

/// Represents a parsed, sanitized notification payload for in-app processing and deep-linking.
class PendingNotification {
  const PendingNotification({
    required this.type,
    required this.receivedAt,
    this.orderId,
    this.shopId,
    this.recipientRole,
    this.title,
    this.body,
    this.rawData = const {},
  });

  /// Constructs a [PendingNotification] from a [RemoteMessage].
  factory PendingNotification.fromRemoteMessage(RemoteMessage message) {
    final data = message.data;
    final type = data['type']?.toString().trim() ?? 'unknown';
    final orderId = data['orderId']?.toString().trim();
    final shopId = data['shopId']?.toString().trim();
    final recipientRole =
        (data['recipientRole'] ?? data['role'])?.toString().trim();

    return PendingNotification(
      type: type.isEmpty ? 'unknown' : type,
      receivedAt: DateTime.now(),
      orderId: (orderId != null && orderId.isNotEmpty) ? orderId : null,
      shopId: (shopId != null && shopId.isNotEmpty) ? shopId : null,
      recipientRole: (recipientRole != null && recipientRole.isNotEmpty)
          ? recipientRole
          : null,
      title: message.notification?.title ?? data['title']?.toString(),
      body: message.notification?.body ?? data['body']?.toString(),
      rawData: Map<String, dynamic>.unmodifiable(data),
    );
  }

  final String type;
  final DateTime receivedAt;
  final String? orderId;
  final String? shopId;
  final String? recipientRole;
  final String? title;
  final String? body;
  final Map<String, dynamic> rawData;

  bool get isValidOrderNotification => orderId != null && orderId!.isNotEmpty;

  @override
  String toString() =>
      'PendingNotification(type: $type, orderId: $orderId, shopId: $shopId, role: $recipientRole, receivedAt: $receivedAt)';
}

/// Service responsible for FCM initialization, device token registration,
/// runtime permissions, session switching, and message lifecycle handling across all app states.
class NotificationService {
  NotificationService({
    FirebaseMessaging? messaging,
    FirebaseFirestore? firestore,
  })  : _messaging = messaging,
        _firestore = firestore;

  final FirebaseMessaging? _messaging;
  final FirebaseFirestore? _firestore;

  StreamSubscription<String>? _tokenRefreshSubscription;
  StreamSubscription<RemoteMessage>? _foregroundMessageSubscription;
  StreamSubscription<RemoteMessage>? _messageOpenedAppSubscription;

  final StreamController<PendingNotification> _foregroundNotificationController =
      StreamController<PendingNotification>.broadcast();
  final StreamController<PendingNotification> _openedNotificationController =
      StreamController<PendingNotification>.broadcast();

  String? _cachedToken;
  String? _lastRegisteredPhone;
  String? _lastRegisteredRole;
  String? _lastRegisteredShopId;
  PendingNotification? _pendingNotification;

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

  /// Pending notification payload awaiting routing consumption.
  PendingNotification? get pendingNotification => _pendingNotification;

  /// Stream of incoming foreground notifications.
  Stream<PendingNotification> get onForegroundNotification =>
      _foregroundNotificationController.stream;

  /// Stream of notification tap events when app is opened from background.
  Stream<PendingNotification> get onNotificationOpened =>
      _openedNotificationController.stream;

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

  /// Initializes the notification service foundation and attaches all lifecycle listeners.
  /// Does NOT block app startup if FCM is unavailable or permission is pending.
  Future<void> initialize({LocalStorageService? localStorage}) async {
    try {
      debugPrint('🔔 [FCM] NotificationService initialization started...');
      final messaging = _messagingInstance;
      if (messaging == null) {
        debugPrint('⚠️ [FCM] Firebase not initialized; skipping FCM setup.');
        return;
      }

      // 1. Retrieve initial token safely
      final token = await getToken();
      _cachedToken = token;

      if (token != null && localStorage != null) {
        await syncCurrentSessionToken(localStorage: localStorage);
      }

      // 2. Attach token refresh listener
      _listenToTokenRefresh(localStorage);

      // 3. Attach foreground message listener
      _listenToForegroundMessages();

      // 4. Attach background app-opened listener
      _listenToOpenedAppMessages();

      // 5. Check if app was launched from a terminated/killed state by a notification
      await _checkInitialMessage();

      debugPrint(
        '✅ [FCM] NotificationService initialized successfully. Cached Token: ${maskToken(_cachedToken)}',
      );
    } catch (e, stack) {
      debugPrint('⚠️ [FCM] NotificationService init note (non-fatal): $e\n$stack');
    }
  }

  /// Requests notification permission from the user safely without crashing.
  Future<NotificationSettings?> requestPermission() async {
    try {
      final messaging = _messagingInstance;
      if (messaging == null) return null;

      final settings = await messaging.requestPermission();

      debugPrint('🔔 [FCM Permission] Status: ${settings.authorizationStatus}');
      return settings;
    } catch (e) {
      debugPrint('⚠️ [FCM Permission] Request note (non-fatal): $e');
      return null;
    }
  }

  /// Checks current notification authorization status.
  Future<AuthorizationStatus> getPermissionStatus() async {
    try {
      final messaging = _messagingInstance;
      if (messaging == null) return AuthorizationStatus.notDetermined;

      final settings = await messaging.getNotificationSettings();
      return settings.authorizationStatus;
    } catch (e) {
      debugPrint('⚠️ [FCM Permission] Check status note (non-fatal): $e');
      return AuthorizationStatus.notDetermined;
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
  /// Automatically removes previous registration if token changed.
  void _listenToTokenRefresh(LocalStorageService? localStorage) {
    try {
      final messaging = _messagingInstance;
      if (messaging == null) return;

      _tokenRefreshSubscription?.cancel();
      _tokenRefreshSubscription = messaging.onTokenRefresh.listen(
        (newToken) async {
          debugPrint('🔄 [FCM] Token refresh detected: ${maskToken(newToken)}');
          final oldToken = _cachedToken;
          _cachedToken = newToken;

          // Delete old token document from Firestore to prevent accumulation
          if (oldToken != null && oldToken.isNotEmpty && oldToken != newToken) {
            await deleteDeviceToken(oldToken);
          }

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

  /// Listens to foreground FCM messages and broadcasts them safely.
  void _listenToForegroundMessages() {
    try {
      _foregroundMessageSubscription?.cancel();
      _foregroundMessageSubscription = FirebaseMessaging.onMessage.listen(
        (message) {
          final pending = PendingNotification.fromRemoteMessage(message);
          debugPrint(
            '📩 [FCM Foreground] Message received: type=${pending.type}, orderId=${pending.orderId ?? "none"}',
          );
          _pendingNotification = pending;
          if (!_foregroundNotificationController.isClosed) {
            _foregroundNotificationController.add(pending);
          }
        },
        onError: (Object error) {
          debugPrint('⚠️ [FCM Foreground] Stream error: $error');
        },
      );
    } catch (e) {
      debugPrint('⚠️ [FCM Foreground] Listener attach error: $e');
    }
  }

  /// Listens to notification tap events when app was in background.
  void _listenToOpenedAppMessages() {
    try {
      _messageOpenedAppSubscription?.cancel();
      _messageOpenedAppSubscription =
          FirebaseMessaging.onMessageOpenedApp.listen(
        (message) {
          final pending = PendingNotification.fromRemoteMessage(message);
          debugPrint(
            '📱 [FCM Opened App] Background message tap: type=${pending.type}, orderId=${pending.orderId ?? "none"}',
          );
          _pendingNotification = pending;
          if (!_openedNotificationController.isClosed) {
            _openedNotificationController.add(pending);
          }
        },
        onError: (Object error) {
          debugPrint('⚠️ [FCM Opened App] Stream error: $error');
        },
      );
    } catch (e) {
      debugPrint('⚠️ [FCM Opened App] Listener attach error: $e');
    }
  }

  /// Checks whether a notification tap caused a cold-start from killed state.
  Future<void> _checkInitialMessage() async {
    try {
      final messaging = _messagingInstance;
      if (messaging == null) return;

      final initialMessage = await messaging.getInitialMessage();
      if (initialMessage != null) {
        final pending = PendingNotification.fromRemoteMessage(initialMessage);
        debugPrint(
          '🚀 [FCM Cold Start] Initial message detected: type=${pending.type}, orderId=${pending.orderId ?? "none"}',
        );
        _pendingNotification = pending;
      }
    } catch (e) {
      debugPrint('⚠️ [FCM Cold Start] Check note (non-fatal): $e');
    }
  }

  /// Consumes and clears the pending notification payload after routing has handled it.
  PendingNotification? consumePendingNotification() {
    final notification = _pendingNotification;
    _pendingNotification = null;
    return notification;
  }

  /// Synchronizes the current user session's device token with Firestore.
  /// Dynamically determines whether the user is a customer, shopkeeper, or admin.
  /// Completely re-registers token document to ensure session switches erase stale role/shop fields.
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
      final effectiveCustomerId = customerId ??
          (cleanPhone.isNotEmpty ? 'cust_$cleanPhone' : 'cust_anon');

      final tokenDocRef = firestore.collection('deviceTokens').doc(token);

      final data = <String, dynamic>{
        'token': token,
        'phone': cleanPhone,
        'role': role,
        'shopId': role == 'shopkeeper' ? shopId : null,
        'customerId': role == 'customer' ? effectiveCustomerId : null,
        'platform': currentPlatform,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      // Set without merge ensures role-switch cleanly wipes unused fields from previous sessions
      await tokenDocRef.set(data);

      _lastRegisteredPhone = cleanPhone;
      _lastRegisteredRole = role;
      _lastRegisteredShopId = shopId;

      debugPrint(
        '📱 [FCM] Device token registered: role=$role, phone=${cleanPhone.isEmpty ? "anon" : cleanPhone}, shopId=${shopId ?? "none"}',
      );
    } catch (e, stack) {
      debugPrint(
        '⚠️ [FCM] Device token registration failed (non-fatal): $e\n$stack',
      );
    }
  }

  /// Safely deletes a stale or revoked device token from Firestore.
  Future<void> deleteDeviceToken(String token) async {
    if (token.isEmpty) return;

    try {
      final firestore = _firestoreInstance;
      if (firestore == null) return;

      await firestore.collection('deviceTokens').doc(token).delete();
      debugPrint('🧹 [FCM] Purged token registration: ${maskToken(token)}');
    } catch (e) {
      debugPrint('⚠️ [FCM] Token deletion note (non-fatal): $e');
    }
  }

  /// Cleans up subscriptions and controllers when disposing.
  void dispose() {
    _tokenRefreshSubscription?.cancel();
    _foregroundMessageSubscription?.cancel();
    _messageOpenedAppSubscription?.cancel();
    _foregroundNotificationController.close();
    _openedNotificationController.close();
  }
}
