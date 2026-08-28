// BU Gate2Eat — Tests
// Unit Tests for Part 4: Shopkeeper New App Order Notification & Targeting Engine

import 'package:bugate2eat_app/models/order_model.dart';
import 'package:bugate2eat_app/services/shopkeeper_notification_dispatcher.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Part 4: Shopkeeper New Order Notification & Targeting Engine Suite', () {
    final sampleOrder = AppOrder(
      orderId: 'YB-2026-08-100',
      customerId: 'cust_9876543210',
      customerName: 'Aarav Sharma',
      customerPhone: '9876543210',
      shopId: 'rajat_shop',
      shopName: 'Rajat Shop',
      items: const [
        OrderItem(
          menuItemId: 'item_1',
          name: 'Cheese Burger',
          price: 120,
          quantity: 2,
        ),
        OrderItem(
          menuItemId: 'item_2',
          name: 'Cold Coffee',
          price: 60,
          quantity: 1,
        ),
      ],
      totalAmount: 300,
      status: 'placed',
      deliveryNote: 'Gate 3',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    final mockDeviceTokens = <Map<String, dynamic>>[
      // Rajat shopkeeper devices
      {
        'token': 'fcm_token_rajat_phone1',
        'role': 'shopkeeper',
        'shopId': 'rajat_shop',
        'phone': '8000383993',
      },
      {
        'token': 'fcm_token_rajat_tablet2',
        'role': 'shopkeeper',
        'shopId': 'rajat_shop',
        'phone': '8000383993',
      },
      {
        'token': 'fcm_token_rajat_phone3',
        'role': 'shopkeeper',
        'shopId': 'rajat_shop',
        'phone': '8000383993',
      },
      // Nayan shopkeeper device
      {
        'token': 'fcm_token_nayan_1',
        'role': 'shopkeeper',
        'shopId': 'nayan_shop',
        'phone': '8295643910',
      },
      // Kivisha shopkeeper device
      {
        'token': 'fcm_token_kivisha_1',
        'role': 'shopkeeper',
        'shopId': 'kivisha_shop',
        'phone': '8875344034',
      },
      // Customer device (even if browsing rajat_shop)
      {
        'token': 'fcm_token_customer_1',
        'role': 'customer',
        'shopId': 'rajat_shop',
        'phone': '9876543210',
      },
      // Admin device
      {
        'token': 'fcm_token_admin_1',
        'role': 'admin',
        'shopId': null,
        'phone': '8078643910',
      },
      // Stale / empty token record
      {
        'token': '',
        'role': 'shopkeeper',
        'shopId': 'rajat_shop',
      },
      {
        'token': null,
        'role': 'shopkeeper',
        'shopId': 'rajat_shop',
      },
    ];

    test('1. Correct Targeting: Order for rajat_shop targets only Rajat devices and excludes other shops', () {
      final targets = ShopkeeperNotificationTargetingLogic.resolveTargetTokens(
        targetShopId: 'rajat_shop',
        registeredTokens: mockDeviceTokens,
      );

      expect(targets.length, equals(3));
      expect(targets, contains('fcm_token_rajat_phone1'));
      expect(targets, contains('fcm_token_rajat_tablet2'));
      expect(targets, contains('fcm_token_rajat_phone3'));

      // Strict exclusion of other shops
      expect(targets.contains('fcm_token_nayan_1'), isFalse);
      expect(targets.contains('fcm_token_kivisha_1'), isFalse);
    });

    test('2. Multiple Devices: All 3 authorized devices for the shop are targeted', () {
      final targets = ShopkeeperNotificationTargetingLogic.resolveTargetTokens(
        targetShopId: 'rajat_shop',
        registeredTokens: mockDeviceTokens,
      );

      expect(targets, equals([
        'fcm_token_rajat_phone1',
        'fcm_token_rajat_tablet2',
        'fcm_token_rajat_phone3',
      ]));
    });

    test('3. Wrong Role Exclusion: Customer and Admin tokens are never targeted for shopkeeper notifications', () {
      final targets = ShopkeeperNotificationTargetingLogic.resolveTargetTokens(
        targetShopId: 'rajat_shop',
        registeredTokens: mockDeviceTokens,
      );

      expect(targets.contains('fcm_token_customer_1'), isFalse);
      expect(targets.contains('fcm_token_admin_1'), isFalse);
    });

    test('4. WhatsApp Isolation: WhatsApp order flow does not produce FCM event', () {
      final targets = ShopkeeperNotificationTargetingLogic.resolveTargetTokens(
        targetShopId: '',
        registeredTokens: mockDeviceTokens,
      );

      expect(targets, isEmpty);
    });

    test('5. Stale / Empty Token Safety: Empty or null tokens are ignored without crashing', () {
      final targets = ShopkeeperNotificationTargetingLogic.resolveTargetTokens(
        targetShopId: 'rajat_shop',
        registeredTokens: mockDeviceTokens,
      );

      expect(targets.contains(''), isFalse);
      expect(targets.contains(null), isFalse);
    });

    test('6. Payload Verification: Generates complete structured payload matching Part 6 deep-link contract', () {
      final payload = ShopkeeperNotificationTargetingLogic.buildNewOrderPayload(sampleOrder);

      expect(payload['notification']['title'], equals('🍔 New Order Received!'));
      expect(payload['notification']['body'], equals('Order #YB-2026-08-100 • ₹300 (2 items)'));

      final data = payload['data'] as Map<String, dynamic>;
      expect(data['type'], equals('new_order'));
      expect(data['orderId'], equals('YB-2026-08-100'));
      expect(data['shopId'], equals('rajat_shop'));
      expect(data['recipientRole'], equals('shopkeeper'));
      expect(data['click_action'], equals('FLUTTER_NOTIFICATION_CLICK'));
    });

    test('7. Duplicate Protection / Idempotency: Processing same list does not duplicate target tokens', () {
      final duplicateList = [
        ...mockDeviceTokens,
        ...mockDeviceTokens, // Duplicate entries
      ];

      final targets = ShopkeeperNotificationTargetingLogic.resolveTargetTokens(
        targetShopId: 'rajat_shop',
        registeredTokens: duplicateList,
      );

      // Still exactly 3 unique tokens
      expect(targets.length, equals(3));
      expect(targets.toSet().length, equals(3));
    });

    test('8. Different Shop Targeting: Targeting nayan_shop returns only Nayan token', () {
      final targets = ShopkeeperNotificationTargetingLogic.resolveTargetTokens(
        targetShopId: 'nayan_shop',
        registeredTokens: mockDeviceTokens,
      );

      expect(targets.length, equals(1));
      expect(targets.first, equals('fcm_token_nayan_1'));
    });
  });
}
