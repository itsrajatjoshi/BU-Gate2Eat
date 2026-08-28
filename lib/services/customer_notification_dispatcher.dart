// BU Gate2Eat — Services
// Customer Order Lifecycle Notification Targeting & Payload Engine (Part 5)
// Pure, deterministic business logic matching the server-side Cloud Function lifecycle rules.

import '../models/order_model.dart';

/// Pure business logic for resolving customer notification targets and formatting FCM payloads.
class CustomerNotificationTargetingLogic {
  CustomerNotificationTargetingLogic._();

  /// Supported notifiable customer state transitions.
  static const Set<String> notifiableTransitions = {
    'placed->accepted',
    'placed->rejected',
    'placed->delivery_expired',
    'accepted->rejected',
    'accepted->delivered',
    'accepted->delivery_expired',
  };

  /// Verifies if a given status change is a notifiable customer lifecycle event.
  static bool isNotifiableTransition(String oldStatus, String newStatus) {
    if (oldStatus == newStatus) return false;
    final key = '$oldStatus->$newStatus';
    return notifiableTransitions.contains(key);
  }

  /// Resolves the list of active device tokens for the customer associated with [customerId] or [customerPhone].
  /// Enforces:
  /// 1. `role == 'customer'` (strict role filtering — excludes shopkeepers and admins)
  /// 2. `customerId == targetCustomerId` OR `phone == targetCustomerPhone`
  /// 3. Non-empty token strings
  /// 4. Zero cross-customer leakage (Customer B never receives Customer A's notifications)
  static List<String> resolveCustomerTargetTokens({
    required String? customerId,
    required String? customerPhone,
    required List<Map<String, dynamic>> registeredTokens,
  }) {
    final cleanId = customerId?.trim() ?? '';
    final cleanPhone = customerPhone?.trim() ?? '';

    if (cleanId.isEmpty && cleanPhone.isEmpty) return const [];

    final targetTokens = <String>[];

    for (final record in registeredTokens) {
      final token = record['token']?.toString().trim();
      final role = record['role']?.toString().trim();
      final recCustomerId = record['customerId']?.toString().trim() ?? '';
      final recPhone = record['phone']?.toString().trim() ?? '';

      if (token == null || token.isEmpty) continue;
      // Strict role enforcement: Only customer devices receive customer lifecycle events
      if (role != 'customer') continue;

      final matchesId = cleanId.isNotEmpty && recCustomerId == cleanId;
      final matchesPhone = cleanPhone.isNotEmpty && recPhone == cleanPhone;

      if (matchesId || matchesPhone) {
        if (!targetTokens.contains(token)) {
          targetTokens.add(token);
        }
      }
    }

    return targetTokens;
  }

  /// Builds the structured, unprivileged FCM push payload for a customer lifecycle transition.
  static Map<String, dynamic>? buildCustomerLifecyclePayload({
    required String oldStatus,
    required String newStatus,
    required AppOrder order,
    String? customShopName,
    String? rejectionReason,
  }) {
    if (!isNotifiableTransition(oldStatus, newStatus)) {
      return null;
    }

    final shopName = customShopName ?? (order.shopName.isNotEmpty ? order.shopName : 'Shop');
    final reason = rejectionReason ?? order.rejectionReason;

    String type = '';
    String title = '';
    String body = '';

    if (oldStatus == 'placed' && newStatus == 'accepted') {
      type = 'order_accepted';
      title = '✅ Order Accepted';
      body = 'Your order from $shopName has been accepted.';
    } else if (oldStatus == 'placed' && newStatus == 'rejected') {
      type = 'order_rejected';
      title = '❌ Order Not Accepted';
      body = reason.trim().isNotEmpty
          ? 'Your order from $shopName could not be accepted ($reason).'
          : 'Your order from $shopName could not be accepted.';
    } else if (oldStatus == 'placed' && newStatus == 'delivery_expired') {
      type = 'order_expired';
      title = '⌛ Order Expired';
      body = 'Your order from $shopName was not accepted in time.';
    } else if (oldStatus == 'accepted' && newStatus == 'rejected') {
      type = 'order_rejected';
      title = '❌ Order Update';
      body = reason.trim().isNotEmpty
          ? 'Your order from $shopName could not be completed ($reason).'
          : 'Your order from $shopName could not be completed.';
    } else if (oldStatus == 'accepted' && newStatus == 'delivered') {
      type = 'order_delivered';
      title = '🎉 Order Delivered';
      body = 'Your order from $shopName has been delivered successfully.';
    } else if (oldStatus == 'accepted' && newStatus == 'delivery_expired') {
      type = 'order_expired';
      title = '⚠️ Order Update';
      body = 'Your order from $shopName has expired.';
    }

    return {
      'notification': {
        'title': title,
        'body': body,
      },
      'data': {
        'type': type,
        'orderId': order.orderId,
        'shopId': order.shopId,
        'recipientRole': 'customer',
        'click_action': 'FLUTTER_NOTIFICATION_CLICK',
      },
      'android': {
        'priority': 'high',
        'notification': {
          'channelId': 'yummbu_customer_orders_channel',
          'sound': 'default',
          'priority': 'high',
        },
      },
    };
  }
}
