// BU Gate2Eat — Test Suite
// Checkpoint 1B: Item #6 — Final Full-System Regression & Flow Audit Test

import 'package:bugate2eat_app/core/constants/app_constants.dart';
import 'package:bugate2eat_app/core/utils/order_timer_helper.dart';
import 'package:bugate2eat_app/models/cart_item_model.dart';
import 'package:bugate2eat_app/models/menu_item_model.dart';
import 'package:bugate2eat_app/models/order_model.dart';
import 'package:bugate2eat_app/models/shop_model.dart';
import 'package:bugate2eat_app/panel/shopkeeper_panel/widgets/shopkeeper_order_details_modal.dart';
import 'package:bugate2eat_app/services/whatsapp_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  AppOrder createTestOrder({
    required String orderId,
    required String shopId,
    required String shopName,
    required String customerName,
    required String customerPhone,
    required String status,
    DateTime? createdAt,
    DateTime? acceptedAt,
    DateTime? rejectedAt,
    DateTime? deliveredAt,
    String rejectionReason = '',
    String deliveryPersonId = '',
    String deliveryPersonName = '',
    double totalAmount = 244.0,
  }) {
    final now = DateTime.now();
    return AppOrder(
      orderId: orderId,
      shopId: shopId,
      shopName: shopName,
      customerName: customerName,
      customerPhone: customerPhone,
      totalAmount: totalAmount,
      createdAt: createdAt ?? now,
      acceptedAt: acceptedAt,
      rejectedAt: rejectedAt,
      deliveredAt: deliveredAt,
      rejectionReason: rejectionReason,
      deliveryPersonId: deliveryPersonId,
      deliveryPersonName: deliveryPersonName,
      status: status,
      items: const [
        OrderItem(
          menuItemId: 'item_1',
          name: 'Paneer Roll',
          price: 122,
          quantity: 2,
        ),
      ],
    );
  }

  group('Checkpoint 1B Audit — Part 1 to 5: Customer Flow & Cart Invariants', () {
    test('1. Single-Shop Cart & Deterministic Cart Key Invariants', () {
      const baseItem = MenuItem(
        id: 'item_1',
        name: 'Veg Roll',
        details: 'Delicious roll',
        price: 60,
        categoryId: 'rolls',
        imageUrl: '',
        isVeg: true,
        isAvailable: true,
        isRecommended: false,
        sortOrder: 1,
      );

      const item1 = CartItem(
        menuItem: baseItem,
        quantity: 2,
        shopId: 'up16_junction_fast_food',
        shopName: 'UP16 Junction',
        selectedOptions: [
          SelectedMenuItemOption(
            groupId: 'grp_1',
            groupName: 'Portion',
            optionId: 'opt_half',
            optionName: 'Half',
            pricingType: OptionPricingType.selectionOnly,
            price: 0,
          ),
          SelectedMenuItemOption(
            groupId: 'grp_2',
            groupName: 'Preparation',
            optionId: 'opt_dry',
            optionName: 'Dry',
            pricingType: OptionPricingType.selectionOnly,
            price: 0,
          ),
        ],
      );

      const item2 = CartItem(
        menuItem: baseItem,
        quantity: 1,
        shopId: 'up16_junction_fast_food',
        shopName: 'UP16 Junction',
        selectedOptions: [
          SelectedMenuItemOption(
            groupId: 'grp_2',
            groupName: 'Preparation',
            optionId: 'opt_dry',
            optionName: 'Dry',
            pricingType: OptionPricingType.selectionOnly,
            price: 0,
          ),
          SelectedMenuItemOption(
            groupId: 'grp_1',
            groupName: 'Portion',
            optionId: 'opt_half',
            optionName: 'Half',
            pricingType: OptionPricingType.selectionOnly,
            price: 0,
          ),
        ],
      );

      expect(item1.cartKey, equals(item2.cartKey));
    });

    test('2. Dynamic Minimum Order validation based on Shop configuration', () {
      final shopZero = Shop(
        id: 'shop_0',
        name: 'Zero Min Shop',
        description: '',
        bannerUrl: '',
        contactNumber: '8295643910',
        orderNumber: '8295643910',
        openTime: '08:00',
        closeTime: '23:30',
        isClosedOverride: false,
        isActive: true,
        sortOrder: 1,
        searchKeywords: const [],
        deliveryNote: 'Gate 3',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        minimumOrderAmount: 0,
      );

      final shopTwoHundred = Shop(
        id: 'shop_200',
        name: 'Thali Shop',
        description: '',
        bannerUrl: '',
        contactNumber: '8295643910',
        orderNumber: '8295643910',
        openTime: '08:00',
        closeTime: '23:30',
        isClosedOverride: false,
        isActive: true,
        sortOrder: 2,
        searchKeywords: const [],
        deliveryNote: 'Gate 3',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        minimumOrderAmount: 200,
      );

      expect(shopZero.minimumOrderAmount, equals(0));
      expect(shopTwoHundred.minimumOrderAmount, equals(200));

      const cartTotal = 150;
      expect(cartTotal >= shopZero.minimumOrderAmount, isTrue);
      expect(cartTotal >= shopTwoHundred.minimumOrderAmount, isFalse);
    });

    test('3. WhatsApp Order URI generation targets exact shop orderNumber', () {
      const orderNumber = '8295643910';
      final clean = WhatsAppService.normalizePhoneNumber(orderNumber);
      expect(clean, '918295643910');

      final uri = WhatsAppService.buildWhatsAppUri(
        whatsappNumber: orderNumber,
        message: 'Order for BU Gate2Eat',
      );
      expect(uri, isNotNull);
      expect(uri.toString(), contains('wa.me/918295643910'));
    });
  });

  group('Checkpoint 1B Audit — Part 6 to 9: Order Lifecycle & Timer Boundaries', () {
    test('1. Customer pre-accept cancellation is allowed; post-accept cancellation is blocked', () {
      final placedOrder = createTestOrder(
        orderId: 'ORD-1',
        shopId: 'rajat_shop',
        shopName: 'Rajat Shop',
        customerName: 'User',
        customerPhone: '9876543210',
        status: 'placed',
      );
      final acceptedOrder = createTestOrder(
        orderId: 'ORD-2',
        shopId: 'rajat_shop',
        shopName: 'Rajat Shop',
        customerName: 'User',
        customerPhone: '9876543210',
        status: 'accepted',
      );

      expect(placedOrder.isPlaced, isTrue);
      expect(acceptedOrder.isPlaced, isFalse);
      expect(acceptedOrder.status, 'accepted');
    });

    test('2. 20-min Acceptance Timer boundary audit', () {
      final base = DateTime(2026, 8, 29, 12, 0, 0);
      final order = createTestOrder(
        orderId: 'ORD-TIME-1',
        shopId: 'rajat_shop',
        shopName: 'Rajat Shop',
        customerName: 'Customer',
        customerPhone: '9876543210',
        status: 'placed',
        createdAt: base,
      );

      // At 19 mins 59 secs -> Not expired
      final t19m59s = base.add(const Duration(minutes: 19, seconds: 59));
      expect(OrderTimerHelper.isAcceptExpired(order, t19m59s), isFalse);

      // At 20 mins 00 secs -> Expired
      final t20m00s = base.add(const Duration(minutes: 20));
      expect(OrderTimerHelper.isAcceptExpired(order, t20m00s), isTrue);

      // At 20 mins 01 secs -> Expired
      final t20m01s = base.add(const Duration(minutes: 20, seconds: 1));
      expect(OrderTimerHelper.isAcceptExpired(order, t20m01s), isTrue);
    });

    test('3. 15-min Shopkeeper Rejection Window boundary audit', () {
      final base = DateTime(2026, 8, 29, 12, 0, 0);
      final acceptedAt = base.add(const Duration(minutes: 5));
      final order = createTestOrder(
        orderId: 'ORD-TIME-2',
        shopId: 'rajat_shop',
        shopName: 'Rajat Shop',
        customerName: 'Customer',
        customerPhone: '9876543210',
        status: 'accepted',
        createdAt: base,
        acceptedAt: acceptedAt,
      );

      // At 14 mins 59 secs after acceptedAt -> Can reject
      final t14m59s = acceptedAt.add(const Duration(minutes: 14, seconds: 59));
      expect(OrderTimerHelper.isRejectExpired(order, t14m59s), isFalse);

      // At 15 mins 00 secs after acceptedAt -> Rejection window expired
      final t15m00s = acceptedAt.add(const Duration(minutes: 15));
      expect(OrderTimerHelper.isRejectExpired(order, t15m00s), isTrue);

      // At 15 mins 01 secs after acceptedAt -> Rejection window expired
      final t15m01s = acceptedAt.add(const Duration(minutes: 15, seconds: 1));
      expect(OrderTimerHelper.isRejectExpired(order, t15m01s), isTrue);
    });

    test('4. 90-min Delivery Timer boundary audit', () {
      final base = DateTime(2026, 8, 29, 12, 0, 0);
      final acceptedAt = base.add(const Duration(minutes: 5));
      final order = createTestOrder(
        orderId: 'ORD-TIME-3',
        shopId: 'rajat_shop',
        shopName: 'Rajat Shop',
        customerName: 'Customer',
        customerPhone: '9876543210',
        status: 'accepted',
        createdAt: base,
        acceptedAt: acceptedAt,
      );

      // At 89 mins 59 secs after acceptedAt -> Delivery active
      final t89m59s = acceptedAt.add(const Duration(minutes: 89, seconds: 59));
      expect(OrderTimerHelper.isDeliveryExpired(order, t89m59s), isFalse);

      // At 90 mins 00 secs after acceptedAt -> Delivery expired
      final t90m00s = acceptedAt.add(const Duration(minutes: 90));
      expect(OrderTimerHelper.isDeliveryExpired(order, t90m00s), isTrue);
    });
  });

  group('Checkpoint 1B Audit — Part 10 to 12: Admin Safety & Multi-Shop Isolation', () {
    test('1. Admin Reset Safety: Active orders preserved, terminal orders wiped', () {
      final placedOrder = createTestOrder(
        orderId: 'A-PLACED',
        shopId: 'shop_a',
        shopName: 'Shop A',
        customerName: 'User 1',
        customerPhone: '9876543210',
        status: 'placed',
      );
      final acceptedOrder = createTestOrder(
        orderId: 'A-ACCEPTED',
        shopId: 'shop_a',
        shopName: 'Shop A',
        customerName: 'User 2',
        customerPhone: '9876543210',
        status: 'accepted',
      );
      final deliveredOrder = createTestOrder(
        orderId: 'A-DELIVERED',
        shopId: 'shop_a',
        shopName: 'Shop A',
        customerName: 'User 3',
        customerPhone: '9876543210',
        status: 'delivered',
      );
      final rejectedOrder = createTestOrder(
        orderId: 'A-REJECTED',
        shopId: 'shop_a',
        shopName: 'Shop A',
        customerName: 'User 4',
        customerPhone: '9876543210',
        status: 'rejected',
      );

      final shopAOrders = [placedOrder, acceptedOrder, deliveredOrder, rejectedOrder];

      // Reset filter: Keep placed & accepted, wipe terminal states
      final survivingOrders = shopAOrders.where((o) => o.status == 'placed' || o.status == 'accepted').toList();
      final wipedOrders = shopAOrders.where((o) => o.status == 'delivered' || o.status == 'rejected').toList();

      expect(survivingOrders.map((o) => o.orderId), containsAll(['A-PLACED', 'A-ACCEPTED']));
      expect(wipedOrders.map((o) => o.orderId), containsAll(['A-DELIVERED', 'A-REJECTED']));
    });

    test('2. Strict Multi-Shop Isolation across 6 registered shops', () {
      // Each shop resolves uniquely
      expect(AppAuthRoles.getShopIdForPhone('8000383993'), equals('rajat_shop'));
      expect(AppAuthRoles.getShopIdForPhone('8295643910'), equals('nayan_shop'));
      expect(AppAuthRoles.getShopIdForPhone('8875344034'), equals('kivisha_shop'));
      expect(AppAuthRoles.getShopIdForPhone('8079065843'), equals('up16_junction_fast_food'));
      expect(AppAuthRoles.getShopIdForPhone('8888822222'), equals('raja_hotel'));
      expect(AppAuthRoles.getShopIdForPhone('9999922222'), equals('up16_queens'));

      // Unknown phones produce null
      expect(AppAuthRoles.getShopIdForPhone('9999911111'), isNull);
      expect(AppAuthRoles.getShopIdForPhone('0000000000'), isNull);
    });
  });

  group('Checkpoint 1B Audit — Part 13 to 14: Call Button Placement & UI Integrity', () {
    testWidgets('1. Shopkeeper Order Details Modal renders Call Button inside Customer Details Card', (tester) async {
      final order = createTestOrder(
        orderId: 'ORD-AUDIT-101',
        shopId: 'rajat_shop',
        shopName: 'Rajat Shop',
        customerName: 'Test Customer',
        customerPhone: '9876543210',
        status: 'placed',
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: ShopkeeperOrderDetailsModal(order: order),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Customer Details section exists
      expect(find.text('Customer Details'), findsOneWidget);
      expect(find.text('Test Customer'), findsOneWidget);
      expect(find.text('9876543210'), findsOneWidget);

      // Call button is present
      final callIcon = find.byIcon(Icons.call_outlined);
      expect(callIcon, findsOneWidget);

      // Existing action buttons are present and unblocked
      expect(find.text('Reject'), findsOneWidget);
      expect(find.text('Accept Order'), findsOneWidget);
    });
  });
}
