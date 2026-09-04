// BU Gate2Eat — Services
// Notification Router Bridge & Deep-Linking Engine (Part 6)
// Handles validated, exact-once deep linking for Customer and Shopkeeper notifications via GoRouter.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/constants/app_constants.dart';
import '../core/router.dart';
import 'local_storage_service.dart';
import 'notification_service.dart';

/// Result of validating an incoming notification payload.
class NotificationValidationResult {
  const NotificationValidationResult._({
    required this.isValid,
    this.errorMessage,
  });

  factory NotificationValidationResult.success() =>
      const NotificationValidationResult._(isValid: true);

  factory NotificationValidationResult.failure(String message) =>
      NotificationValidationResult._(isValid: false, errorMessage: message);

  final bool isValid;
  final String? errorMessage;
}

/// Result of resolving a validated notification payload into a GoRouter destination.
class ResolvedNotificationRoute {
  const ResolvedNotificationRoute({
    required this.isAuthorized,
    this.route,
    this.orderId,
    this.shopId,
    this.rejectionReason,
  });

  final bool isAuthorized;
  final String? route;
  final String? orderId;
  final String? shopId;
  final String? rejectionReason;
}

/// Centralized bridge connecting NotificationService events to GoRouter destinations.
class NotificationRouterBridge {
  NotificationRouterBridge._();

  static const Set<String> validCustomerTypes = {
    'order_accepted',
    'order_rejected',
    'order_delivered',
    'order_expired',
  };

  static const Set<String> validShopkeeperTypes = {
    'new_order',
  };

  // ─── Duplicate Tap Guard State ───────────────────────────────────────────
  static String? _lastHandledOrderId;
  static DateTime? _lastHandledTimestamp;
  static const Duration _duplicateThrottleWindow = Duration(milliseconds: 1500);

  /// Validates the structure and recognized event type of an incoming notification.
  static NotificationValidationResult validateNotification(
    PendingNotification notification,
  ) {
    final orderId = notification.orderId?.trim();
    if (orderId == null || orderId.isEmpty) {
      return NotificationValidationResult.failure(
        'Malformed payload: Missing or empty orderId',
      );
    }

    final type = notification.type.trim();
    if (type.isEmpty || type == 'unknown') {
      return NotificationValidationResult.failure(
        'Malformed payload: Missing or empty notification type',
      );
    }

    final isCustomerType = validCustomerTypes.contains(type);
    final isShopkeeperType = validShopkeeperTypes.contains(type);

    if (!isCustomerType && !isShopkeeperType) {
      return NotificationValidationResult.failure(
        'Unknown or unsupported notification type: "$type"',
      );
    }

    return NotificationValidationResult.success();
  }

  /// Determines whether a notification tap is an immediate duplicate.
  static bool isDuplicateTap(String? orderId) {
    if (orderId == null || orderId.isEmpty) return false;
    final now = DateTime.now();

    if (_lastHandledOrderId == orderId && _lastHandledTimestamp != null) {
      if (now.difference(_lastHandledTimestamp!) < _duplicateThrottleWindow) {
        debugPrint(
          '🛡️ [Notification Router] Suppressed duplicate tap for Order #$orderId',
        );
        return true;
      }
    }

    _lastHandledOrderId = orderId;
    _lastHandledTimestamp = now;
    return false;
  }

  /// Resolves the destination route and verifies role/shop authorization.
  static ResolvedNotificationRoute resolveRoute({
    required PendingNotification notification,
    required String userPhone,
  }) {
    final validation = validateNotification(notification);
    if (!validation.isValid) {
      debugPrint(
        '⚠️ [Notification Router] Validation failed: ${validation.errorMessage}',
      );
      return const ResolvedNotificationRoute(isAuthorized: false);
    }

    final cleanPhone = AppAuthRoles.normalizeCleanPhone(userPhone);
    final type = notification.type.trim();
    final orderId = notification.orderId!.trim();
    final shopId = notification.shopId?.trim() ?? '';
    final role = notification.recipientRole?.trim().toLowerCase();

    // ─── Case 1: Customer Notification ─────────────────────────────────────
    if (validCustomerTypes.contains(type) || role == 'customer') {
      final isAdmin = AppAuthRoles.isAdminPhone(cleanPhone);
      final isShopkeeper = AppAuthRoles.isShopkeeperPhone(cleanPhone);

      // If the current active user is an admin, do not expose customer order screens
      if (isAdmin) {
        debugPrint(
          '⛔ [Notification Router] Blocked customer notification tap: Current session is Admin.',
        );
        return const ResolvedNotificationRoute(
          isAuthorized: false,
          rejectionReason: 'Admin session cannot open customer order screen',
        );
      }

      if (isShopkeeper) {
        final authorizedShopId = AppAuthRoles.getShopIdForPhone(cleanPhone);
        if (shopId.isNotEmpty &&
            authorizedShopId != null &&
            shopId != authorizedShopId) {
          debugPrint(
            '⛔ [Notification Router] Cross-Shop Isolation: Shopkeeper for "$authorizedShopId" cannot open notification for "$shopId".',
          );
          return ResolvedNotificationRoute(
            isAuthorized: false,
            rejectionReason: 'Shopkeeper unauthorized for target shop: $shopId',
          );
        }
        debugPrint(
          'ℹ️ [Notification Router] Shopkeeper opening order detail: #$orderId',
        );
      }

      return ResolvedNotificationRoute(
        isAuthorized: true,
        route: '/order/$orderId',
        orderId: orderId,
        shopId: shopId,
      );
    }

    // ─── Case 2: Shopkeeper Notification ───────────────────────────────────
    if (validShopkeeperTypes.contains(type) || role == 'shopkeeper') {
      final authorizedShopId = AppAuthRoles.getShopIdForPhone(cleanPhone);

      if (authorizedShopId == null) {
        debugPrint(
          '⛔ [Notification Router] Blocked shopkeeper notification tap: User phone ($cleanPhone) is not an authorized shopkeeper.',
        );
        return const ResolvedNotificationRoute(
          isAuthorized: false,
          rejectionReason: 'User is not registered as a shopkeeper',
        );
      }

      // Shop isolation check: Payload shopId must match the shopkeeper's authorized shopId
      if (shopId.isNotEmpty && authorizedShopId != shopId) {
        debugPrint(
          '⛔ [Notification Router] Cross-Shop Isolation: Shopkeeper for "$authorizedShopId" cannot open notification for "$shopId".',
        );
        return ResolvedNotificationRoute(
          isAuthorized: false,
          rejectionReason: 'Shopkeeper unauthorized for target shop: $shopId',
        );
      }

      return ResolvedNotificationRoute(
        isAuthorized: true,
        route: AppRoutes.shopkeeper,
        orderId: orderId,
        shopId: authorizedShopId,
      );
    }

    return const ResolvedNotificationRoute(isAuthorized: false);
  }

  /// Handles a user notification tap event with full role validation and exact-once consumption.
  static bool handleNotificationTap({
    required BuildContext context,
    required PendingNotification notification,
    required LocalStorageService localStorage,
    required NotificationService notificationService,
    GoRouter? customRouter,
  }) {
    if (isDuplicateTap(notification.orderId)) {
      notificationService.consumePendingNotification();
      return false;
    }

    final resolved = resolveRoute(
      notification: notification,
      userPhone: localStorage.userPhone,
    );

    // Exact-once consumption: Clear pending notification in service
    notificationService.consumePendingNotification();

    if (!resolved.isAuthorized || resolved.route == null) {
      debugPrint(
        '⚠️ [Notification Router] Navigation rejected: ${resolved.rejectionReason ?? "Unauthorized"}',
      );
      return false;
    }

    final router = customRouter ?? GoRouter.of(context);
    final targetRoute = resolved.route!;

    debugPrint(
      '🚀 [Notification Router] Navigating to "$targetRoute" for Order #${resolved.orderId}',
    );

    try {
      router.go(targetRoute);
      return true;
    } catch (e, stack) {
      debugPrint(
        '❌ [Notification Router] Failed to navigate to "$targetRoute": $e\n$stack',
      );
      return false;
    }
  }

  /// Resets internal throttle state (useful for deterministic testing).
  @visibleForTesting
  static void resetThrottleState() {
    _lastHandledOrderId = null;
    _lastHandledTimestamp = null;
  }
}
