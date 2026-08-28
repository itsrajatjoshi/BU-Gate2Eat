// BU Gate2Eat — Services
// Shopkeeper New Order Notification Targeting & Payload Engine (Part 4)
// Pure, deterministic business logic matching the server-side Cloud Function rules.

import '../models/order_model.dart';

/// Pure business logic for resolving shopkeeper notification targets and formatting FCM payloads.
class ShopkeeperNotificationTargetingLogic {
  ShopkeeperNotificationTargetingLogic._();

  /// Resolves the list of active device tokens for the shopkeeper(s) of [targetShopId].
  /// Enforces:
  /// 1. `role == 'shopkeeper'`
  /// 2. `shopId == targetShopId`
  /// 3. Non-empty token strings
  /// 4. Zero cross-shop leakage (ignoring other shops and customers)
  static List<String> resolveTargetTokens({
    required String targetShopId,
    required List<Map<String, dynamic>> registeredTokens,
  }) {
    if (targetShopId.trim().isEmpty) return const [];

    final cleanTargetShop = targetShopId.trim();
    final targetTokens = <String>[];

    for (final record in registeredTokens) {
      final token = record['token']?.toString().trim();
      final role = record['role']?.toString().trim();
      final shopId = record['shopId']?.toString().trim();

      if (token == null || token.isEmpty) continue;
      if (role != 'shopkeeper') continue;
      if (shopId != cleanTargetShop) continue;

      if (!targetTokens.contains(token)) {
        targetTokens.add(token);
      }
    }

    return targetTokens;
  }

  /// Builds the structured, unprivileged FCM push payload for a new in-app order.
  static Map<String, dynamic> buildNewOrderPayload(AppOrder order) {
    final itemCount = order.items.length;
    final itemText = itemCount == 1 ? '1 item' : '$itemCount items';
    final billAmount = order.totalAmount.toInt();

    return {
      'notification': {
        'title': '🍔 New Order Received!',
        'body': 'Order #${order.orderId} • ₹$billAmount ($itemText)',
      },
      'data': {
        'type': 'new_order',
        'orderId': order.orderId,
        'shopId': order.shopId,
        'recipientRole': 'shopkeeper',
        'click_action': 'FLUTTER_NOTIFICATION_CLICK',
      },
      'android': {
        'priority': 'high',
        'notification': {
          'channelId': 'yummbu_orders_channel',
          'sound': 'default',
          'priority': 'high',
        },
      },
    };
  }
}
