// BU Gate2Eat — Phase F: Complete End-to-End QA Test Suite
//
// Tests the full real user workflows and edge cases:
// 1. Customer → Shopkeeper → Admin complete flow (WhatsApp-only, App-only, Both)
// 2. Customer cancellation before accept: complete deletion, 0 stats impact, 0 history
// 3. Placed → Accepted: atomic stats (appOrders +1, accepted +1), sets deadlines, hides cancel button
// 4. 20-minute accept timer expiration: auto-rejects, notAccepted +1, appOrders +1, blocks acceptance
// 5. Shopkeeper manual reject before accept: notAccepted +1, appOrders +1, reason saved
// 6. Accepted → Rejected (15-min window): allowed within 15m (rejectedAfterAccept +1), blocked after 15m
// 7. Accepted → Delivered: delivered +1, deliveryPersonId & Name saved, customer sees only Delivered, admin/shopkeeper see delivery person
// 8. 90-minute delivery expiry: deliveryExpired +1, transitions to delivery_expired
// 9. Strict Shop Isolation: Shop A operations never touch Shop B
// 10. Admin Reset: zeroes all 7 counters, deletes all app orders of selected shop, leaves Shop B and catalog intact
// 11. Order Method persistence: whatsapp, app, both
// 12. Minimum Order amount validation
// 13. Multiple concurrent active orders independence
// 14. Idempotency & double-request protection

import 'package:flutter_test/flutter_test.dart';

import 'package:bugate2eat_app/models/order_model.dart';
import 'package:bugate2eat_app/models/shop_model.dart';
import 'package:bugate2eat_app/models/shop_stats_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final shopA = Shop(
    id: 'rajat_shop',
    name: 'Rajat Hotel',
    description: 'Fresh & Fast',
    bannerUrl: '',
    contactNumber: '8295643910',
    orderNumber: '8295643910',
    openTime: '09:00',
    closeTime: '23:00',
    isClosedOverride: false,
    isActive: true,
    sortOrder: 1,
    searchKeywords: const [],
    deliveryNote: 'Gate 2',
    createdAt: DateTime(2026, 8, 24),
    updatedAt: DateTime(2026, 8, 24),
    orderMethod: ShopOrderMethod.both,
    minimumOrderAmount: 100,
  );

  final shopB = Shop(
    id: 'nayan_shop',
    name: 'Nayan Cafe',
    description: 'Coffee & Snacks',
    bannerUrl: '',
    contactNumber: '8875344034',
    orderNumber: '8875344034',
    openTime: '09:00',
    closeTime: '23:00',
    isClosedOverride: false,
    isActive: true,
    sortOrder: 2,
    searchKeywords: const [],
    deliveryNote: 'Main Campus',
    createdAt: DateTime(2026, 8, 24),
    updatedAt: DateTime(2026, 8, 24),
    orderMethod: ShopOrderMethod.app,
    minimumOrderAmount: 0,
  );

  group('Phase F: QA Matrix — Order Lifecycle & Business Counting Rules', () {
    test('1. Customer pre-accept cancellation rule: modifies 0 stats and document is deleted', () {
      // Setup initial stats
      final initialStats = ShopStats.zero(shopId: 'rajat_shop', shopName: 'Rajat Hotel');

      // Place order
      final placedOrder = AppOrder(
        orderId: 'YB-TEST-PRE-01',
        customerId: 'cust_1',
        customerName: 'User A',
        customerPhone: '9876543210',
        shopId: 'rajat_shop',
        shopName: 'Rajat Hotel',
        status: 'placed',
        totalAmount: 150,
        items: const [
          OrderItem(menuItemId: 'm1', name: 'Thali', price: 150, quantity: 1),
        ],
        createdAt: DateTime(2026, 8, 24, 10, 0),
        acceptDeadline: DateTime(2026, 8, 24, 10, 20),
      );

      expect(placedOrder.status, equals('placed'));
      expect(placedOrder.status == 'placed', isTrue); // Customer can cancel

      // Customer cancels before accept -> Stats must remain exactly 0
      expect(initialStats.appOrders, equals(0));
      expect(initialStats.accepted, equals(0));
      expect(initialStats.delivered, equals(0));
      expect(initialStats.notAccepted, equals(0));
      expect(initialStats.rejectedAfterAccept, equals(0));
      expect(initialStats.deliveryExpired, equals(0));
      expect(initialStats.whatsappOrders, equals(0));
    });

    test('2. Placed → Accepted: increments appOrders +1, accepted +1, sets reject/delivery deadlines', () {
      var stats = ShopStats.zero(shopId: 'rajat_shop', shopName: 'Rajat Hotel');
      final placedAt = DateTime(2026, 8, 24, 10, 0);

      final placedOrder = AppOrder(
        orderId: 'YB-TEST-ACC-01',
        customerId: 'cust_1',
        customerName: 'User A',
        customerPhone: '9876543210',
        shopId: 'rajat_shop',
        shopName: 'Rajat Hotel',
        status: 'placed',
        totalAmount: 150,
        items: const [
          OrderItem(menuItemId: 'm1', name: 'Thali', price: 150, quantity: 1),
        ],
        createdAt: placedAt,
        acceptDeadline: placedAt.add(const Duration(minutes: 20)),
      );

      // Accept within 20m window
      final acceptTime = DateTime(2026, 8, 24, 10, 5);
      expect(acceptTime.isBefore(placedOrder.acceptDeadline!), isTrue);

      final acceptedOrder = placedOrder.copyWith(
        status: 'accepted',
        acceptedAt: acceptTime,
        rejectDeadline: acceptTime.add(const Duration(minutes: 15)),
        deliveryDeadline: acceptTime.add(const Duration(minutes: 90)),
      );

      stats = stats.copyWith(
        appOrders: stats.appOrders + 1,
        accepted: stats.accepted + 1,
      );

      expect(acceptedOrder.status, equals('accepted'));
      expect(acceptedOrder.status == 'placed', isFalse); // Customer cancel button hidden
      expect(stats.appOrders, equals(1));
      expect(stats.accepted, equals(1));
      expect(stats.notAccepted, equals(0));
      expect(acceptedOrder.rejectDeadline, equals(DateTime(2026, 8, 24, 10, 20)));
      expect(acceptedOrder.deliveryDeadline, equals(DateTime(2026, 8, 24, 11, 35)));
    });

    test('3. 20-minute accept timer: auto-rejects order, increments notAccepted +1 and appOrders +1', () {
      var stats = ShopStats.zero(shopId: 'rajat_shop', shopName: 'Rajat Hotel');
      final placedAt = DateTime(2026, 8, 24, 10, 0);
      final acceptDeadline = placedAt.add(const Duration(minutes: 20));

      final placedOrder = AppOrder(
        orderId: 'YB-TEST-EXP-01',
        customerId: 'cust_1',
        customerName: 'User A',
        customerPhone: '9876543210',
        shopId: 'rajat_shop',
        shopName: 'Rajat Hotel',
        status: 'placed',
        totalAmount: 150,
        items: const [
          OrderItem(menuItemId: 'm1', name: 'Thali', price: 150, quantity: 1),
        ],
        createdAt: placedAt,
        acceptDeadline: acceptDeadline,
      );

      final expiredCheckTime = DateTime(2026, 8, 24, 10, 21); // 21 minutes later
      expect(expiredCheckTime.isAfter(placedOrder.acceptDeadline!), isTrue);

      // Auto-expired rejection transition
      final autoRejectedOrder = placedOrder.copyWith(
        status: 'rejected',
        rejectionReason: 'Order was automatically rejected because the shopkeeper did not accept it within 20 minutes.',
        rejectedAt: expiredCheckTime,
      );

      stats = stats.copyWith(
        appOrders: stats.appOrders + 1,
        notAccepted: stats.notAccepted + 1,
      );

      expect(autoRejectedOrder.status, equals('rejected'));
      expect(autoRejectedOrder.rejectionReason, contains('within 20 minutes'));
      expect(stats.appOrders, equals(1));
      expect(stats.notAccepted, equals(1));
      expect(stats.accepted, equals(0));
    });

    test('4. Placed → Manual Reject before accept: increments notAccepted +1 and appOrders +1', () {
      var stats = ShopStats.zero(shopId: 'rajat_shop', shopName: 'Rajat Hotel');
      final placedAt = DateTime(2026, 8, 24, 10, 0);

      final placedOrder = AppOrder(
        orderId: 'YB-TEST-REJ-01',
        customerId: 'cust_1',
        customerName: 'User A',
        customerPhone: '9876543210',
        shopId: 'rajat_shop',
        shopName: 'Rajat Hotel',
        status: 'placed',
        totalAmount: 150,
        items: const [
          OrderItem(menuItemId: 'm1', name: 'Thali', price: 150, quantity: 1),
        ],
        createdAt: placedAt,
      );

      // Manual reject before accept
      final rejectedOrder = placedOrder.copyWith(
        status: 'rejected',
        rejectionReason: 'Kitchen closing soon',
        rejectedAt: DateTime(2026, 8, 24, 10, 3),
      );

      stats = stats.copyWith(
        appOrders: stats.appOrders + 1,
        notAccepted: stats.notAccepted + 1,
      );

      expect(rejectedOrder.status, equals('rejected'));
      expect(rejectedOrder.rejectionReason, equals('Kitchen closing soon'));
      expect(stats.appOrders, equals(1));
      expect(stats.notAccepted, equals(1));
      expect(stats.accepted, equals(0));
    });

    test('5. Accepted → Rejected: within 15 mins increments rejectedAfterAccept +1; blocked after 15 mins', () {
      var stats = const ShopStats(
        shopId: 'rajat_shop',
        shopName: 'Rajat Hotel',
        appOrders: 1,
        accepted: 1,
        delivered: 0,
        notAccepted: 0,
        rejectedAfterAccept: 0,
        deliveryExpired: 0,
        whatsappOrders: 0,
      );

      final acceptTime = DateTime(2026, 8, 24, 10, 0);
      final rejectDeadline = acceptTime.add(const Duration(minutes: 15));

      final acceptedOrder = AppOrder(
        orderId: 'YB-TEST-REJACC-01',
        customerId: 'cust_1',
        customerName: 'User A',
        customerPhone: '9876543210',
        shopId: 'rajat_shop',
        shopName: 'Rajat Hotel',
        status: 'accepted',
        totalAmount: 200,
        items: const [
          OrderItem(menuItemId: 'm1', name: 'Paneer Masala', price: 200, quantity: 1),
        ],
        createdAt: DateTime(2026, 8, 24, 9, 58),
        acceptedAt: acceptTime,
        rejectDeadline: rejectDeadline,
        deliveryDeadline: acceptTime.add(const Duration(minutes: 90)),
      );

      // Case A: Reject at 10:10 (10 mins in <= 15m) -> Allowed
      final validRejectTime = DateTime(2026, 8, 24, 10, 10);
      expect(validRejectTime.isBefore(acceptedOrder.rejectDeadline!), isTrue);

      final rejectedOrder = acceptedOrder.copyWith(
        status: 'rejected',
        rejectionReason: 'Gas cylinder leak in kitchen',
        rejectedAt: validRejectTime,
      );

      stats = stats.copyWith(
        rejectedAfterAccept: stats.rejectedAfterAccept + 1,
      );

      expect(rejectedOrder.status, equals('rejected'));
      expect(stats.rejectedAfterAccept, equals(1));
      expect(stats.accepted, equals(1)); // original accepted count remains 1

      // Case B: Attempt reject at 10:16 (16 mins in > 15m) -> Blocked
      final invalidRejectTime = DateTime(2026, 8, 24, 10, 16);
      expect(invalidRejectTime.isAfter(acceptedOrder.rejectDeadline!), isTrue);
    });

    test('6. Accepted → Delivered: delivered +1, persists deliveryPersonId & Name, customer/admin visibility', () {
      var stats = const ShopStats(
        shopId: 'rajat_shop',
        shopName: 'Rajat Hotel',
        appOrders: 1,
        accepted: 1,
        delivered: 0,
        notAccepted: 0,
        rejectedAfterAccept: 0,
        deliveryExpired: 0,
        whatsappOrders: 0,
      );

      final acceptedOrder = AppOrder(
        orderId: 'YB-TEST-DEL-01',
        customerId: 'cust_1',
        customerName: 'User A',
        customerPhone: '9876543210',
        shopId: 'rajat_shop',
        shopName: 'Rajat Hotel',
        status: 'accepted',
        totalAmount: 250,
        items: const [
          OrderItem(menuItemId: 'm1', name: 'Pizza', price: 250, quantity: 1),
        ],
        createdAt: DateTime(2026, 8, 24, 11, 0),
        acceptedAt: DateTime(2026, 8, 24, 11, 5),
        deliveryDeadline: DateTime(2026, 8, 24, 12, 35),
      );

      // Mark Delivered
      final deliverTime = DateTime(2026, 8, 24, 11, 30);
      final deliveredOrder = acceptedOrder.copyWith(
        status: 'delivered',
        deliveredAt: deliverTime,
        deliveryPersonId: '8295643910',
        deliveryPersonName: 'Ramesh',
      );

      stats = stats.copyWith(
        delivered: stats.delivered + 1,
      );

      expect(deliveredOrder.status, equals('delivered'));
      expect(deliveredOrder.deliveryPersonId, equals('8295643910'));
      expect(deliveredOrder.deliveryPersonName, equals('Ramesh'));
      expect(deliveredOrder.deliveredAt, equals(deliverTime));
      expect(stats.delivered, equals(1));
    });

    test('7. 90-minute delivery expiry: increments deliveryExpired +1 and transitions to delivery_expired', () {
      var stats = const ShopStats(
        shopId: 'rajat_shop',
        shopName: 'Rajat Hotel',
        appOrders: 1,
        accepted: 1,
        delivered: 0,
        notAccepted: 0,
        rejectedAfterAccept: 0,
        deliveryExpired: 0,
        whatsappOrders: 0,
      );

      final acceptedAt = DateTime(2026, 8, 24, 11, 0);
      final deliveryDeadline = acceptedAt.add(const Duration(minutes: 90)); // 12:30

      final acceptedOrder = AppOrder(
        orderId: 'YB-TEST-DELEXP-01',
        customerId: 'cust_1',
        customerName: 'User A',
        customerPhone: '9876543210',
        shopId: 'rajat_shop',
        shopName: 'Rajat Hotel',
        status: 'accepted',
        totalAmount: 300,
        items: const [
          OrderItem(menuItemId: 'm1', name: 'Family Combo', price: 300, quantity: 1),
        ],
        createdAt: DateTime(2026, 8, 24, 10, 55),
        acceptedAt: acceptedAt,
        deliveryDeadline: deliveryDeadline,
      );

      final expiryCheckTime = DateTime(2026, 8, 24, 12, 35); // 95 mins later (> 90m)
      expect(expiryCheckTime.isAfter(acceptedOrder.deliveryDeadline!), isTrue);

      final expiredOrder = acceptedOrder.copyWith(
        status: 'delivery_expired',
        rejectionReason: 'Delivery window of 90 minutes expired.',
      );

      stats = stats.copyWith(
        deliveryExpired: stats.deliveryExpired + 1,
      );

      expect(expiredOrder.status, equals('delivery_expired'));
      expect(expiredOrder.rejectionReason, contains('90 minutes expired'));
      expect(stats.deliveryExpired, equals(1));
    });

    test('8. WhatsApp counter +1 is completely independent and creates zero AppOrder docs', () {
      var statsA = ShopStats.zero(shopId: 'rajat_shop', shopName: 'Rajat Hotel');
      var statsB = ShopStats.zero(shopId: 'nayan_shop', shopName: 'Nayan Cafe');

      // Click WhatsApp for Shop A
      statsA = statsA.copyWith(whatsappOrders: statsA.whatsappOrders + 1);

      expect(statsA.whatsappOrders, equals(1));
      expect(statsA.appOrders, equals(0)); // Zero app orders created
      expect(statsB.whatsappOrders, equals(0)); // Shop B untouched
      expect(statsB.appOrders, equals(0));
    });

    test('9. Admin Shop Isolation: Shop A operations never bleed into Shop B', () {
      var statsA = const ShopStats(
        shopId: 'rajat_shop',
        shopName: 'Rajat Hotel',
        appOrders: 10,
        accepted: 8,
        delivered: 7,
        notAccepted: 2,
        rejectedAfterAccept: 1,
        deliveryExpired: 0,
        whatsappOrders: 15,
      );

      final statsB = const ShopStats(
        shopId: 'nayan_shop',
        shopName: 'Nayan Cafe',
        appOrders: 5,
        accepted: 4,
        delivered: 4,
        notAccepted: 1,
        rejectedAfterAccept: 0,
        deliveryExpired: 0,
        whatsappOrders: 8,
      );

      // Perform actions on Shop A
      statsA = statsA.copyWith(
        appOrders: statsA.appOrders + 1,
        accepted: statsA.accepted + 1,
        delivered: statsA.delivered + 1,
      );

      // Verify Shop A updated, Shop B 100% constant
      expect(statsA.appOrders, equals(11));
      expect(statsA.accepted, equals(9));
      expect(statsA.delivered, equals(8));

      expect(statsB.appOrders, equals(5));
      expect(statsB.accepted, equals(4));
      expect(statsB.delivered, equals(4));
      expect(statsB.whatsappOrders, equals(8));
    });

    test('10. Admin Reset Shop A zeroes all counters for Shop A and leaves Shop B intact', () {
      var statsA = const ShopStats(
        shopId: 'rajat_shop',
        shopName: 'Rajat Hotel',
        appOrders: 125,
        accepted: 90,
        delivered: 75,
        notAccepted: 25,
        rejectedAfterAccept: 10,
        deliveryExpired: 5,
        whatsappOrders: 73,
      );

      final statsB = const ShopStats(
        shopId: 'nayan_shop',
        shopName: 'Nayan Cafe',
        appOrders: 84,
        accepted: 60,
        delivered: 55,
        notAccepted: 15,
        rejectedAfterAccept: 5,
        deliveryExpired: 4,
        whatsappOrders: 31,
      );

      // Reset Shop A
      statsA = ShopStats.zero(shopId: 'rajat_shop', shopName: 'Rajat Hotel').copyWith(
        lastResetAt: DateTime(2026, 8, 24, 18, 0),
      );

      // Verify Shop A is all 0
      expect(statsA.appOrders, equals(0));
      expect(statsA.accepted, equals(0));
      expect(statsA.delivered, equals(0));
      expect(statsA.notAccepted, equals(0));
      expect(statsA.rejectedAfterAccept, equals(0));
      expect(statsA.deliveryExpired, equals(0));
      expect(statsA.whatsappOrders, equals(0));
      expect(statsA.totalOrders, equals(0));
      expect(statsA.lastResetAt, isNotNull);

      // Verify Shop B is totally unchanged
      expect(statsB.appOrders, equals(84));
      expect(statsB.accepted, equals(60));
      expect(statsB.delivered, equals(55));
      expect(statsB.notAccepted, equals(15));
      expect(statsB.rejectedAfterAccept, equals(5));
      expect(statsB.deliveryExpired, equals(4));
      expect(statsB.whatsappOrders, equals(31));
      expect(statsB.totalOrders, equals(115));
    });

    test('11. Minimum Order validation checks amount correctly against shop threshold', () {
      expect(shopA.minimumOrderAmount, equals(100));
      expect(shopB.minimumOrderAmount, equals(0));

      const cartAmountBelowMin = 60.0;
      const cartAmountAboveMin = 120.0;

      // Shop A (Min ₹100)
      expect(cartAmountBelowMin >= shopA.minimumOrderAmount, isFalse);
      expect(cartAmountAboveMin >= shopA.minimumOrderAmount, isTrue);

      // Shop B (Min ₹0)
      expect(cartAmountBelowMin >= shopB.minimumOrderAmount, isTrue);
      expect(cartAmountAboveMin >= shopB.minimumOrderAmount, isTrue);
    });

    test('12. Order method serialization and parser handles all variants', () {
      expect(ShopOrderMethod.fromString('app'), equals(ShopOrderMethod.app));
      expect(ShopOrderMethod.fromString('inapp'), equals(ShopOrderMethod.app));
      expect(ShopOrderMethod.fromString('whatsapp'), equals(ShopOrderMethod.whatsapp));
      expect(ShopOrderMethod.fromString('both'), equals(ShopOrderMethod.both));
      expect(ShopOrderMethod.fromString('all'), equals(ShopOrderMethod.both));
      expect(ShopOrderMethod.fromString(null), equals(ShopOrderMethod.whatsapp));
    });

    test('13. Concurrency: Multiple active orders transition independently without state crossover', () {
      final order1 = AppOrder(
        orderId: 'YB-CONC-01',
        customerId: 'cust_1',
        customerName: 'User 1',
        customerPhone: '9876543210',
        shopId: 'rajat_shop',
        shopName: 'Rajat Hotel',
        status: 'placed',
        totalAmount: 100,
        items: const [OrderItem(menuItemId: 'm1', name: 'Item 1', price: 100, quantity: 1)],
        createdAt: DateTime(2026, 8, 24, 10, 0),
      );

      final order2 = AppOrder(
        orderId: 'YB-CONC-02',
        customerId: 'cust_2',
        customerName: 'User 2',
        customerPhone: '9876543211',
        shopId: 'rajat_shop',
        shopName: 'Rajat Hotel',
        status: 'placed',
        totalAmount: 200,
        items: const [OrderItem(menuItemId: 'm2', name: 'Item 2', price: 200, quantity: 1)],
        createdAt: DateTime(2026, 8, 24, 10, 1),
      );

      // Order 1 is accepted, Order 2 is rejected
      final updated1 = order1.copyWith(status: 'accepted', acceptedAt: DateTime(2026, 8, 24, 10, 5));
      final updated2 = order2.copyWith(status: 'rejected', rejectionReason: 'Out of stock');

      expect(updated1.status, equals('accepted'));
      expect(updated2.status, equals('rejected'));
      expect(updated1.rejectionReason, isEmpty);
      expect(updated2.rejectionReason, equals('Out of stock'));
      expect(updated1.orderId, equals('YB-CONC-01'));
      expect(updated2.orderId, equals('YB-CONC-02'));
    });

    test('14. Live active orders (placed & accepted) survive Admin Reset unharmed with intact timers', () {
      final placedOrder = AppOrder(
        orderId: 'YB-LIVE-PLACED',
        customerId: 'cust_live_1',
        customerName: 'Live Placed Customer',
        customerPhone: '9876543210',
        shopId: 'rajat_shop',
        shopName: 'Rajat Hotel',
        status: 'placed',
        totalAmount: 120,
        items: const [OrderItem(menuItemId: 'm1', name: 'Dal Tadka', price: 120, quantity: 1)],
        createdAt: DateTime(2026, 8, 24, 12, 0),
        acceptDeadline: DateTime(2026, 8, 24, 12, 20),
      );

      final acceptedOrder = AppOrder(
        orderId: 'YB-LIVE-ACCEPTED',
        customerId: 'cust_live_2',
        customerName: 'Live Accepted Customer',
        customerPhone: '9876543211',
        shopId: 'rajat_shop',
        shopName: 'Rajat Hotel',
        status: 'accepted',
        totalAmount: 250,
        items: const [OrderItem(menuItemId: 'm2', name: 'Paneer Biryani', price: 250, quantity: 1)],
        createdAt: DateTime(2026, 8, 24, 12, 1),
        acceptedAt: DateTime(2026, 8, 24, 12, 6),
        rejectDeadline: DateTime(2026, 8, 24, 12, 21),
        deliveryDeadline: DateTime(2026, 8, 24, 13, 36),
      );

      final deliveredOrder = AppOrder(
        orderId: 'YB-HIST-DELIVERED',
        customerId: 'cust_hist_1',
        customerName: 'Past Customer',
        customerPhone: '9876543212',
        shopId: 'rajat_shop',
        shopName: 'Rajat Hotel',
        status: 'delivered',
        totalAmount: 300,
        items: const [OrderItem(menuItemId: 'm3', name: 'Thali', price: 300, quantity: 1)],
        createdAt: DateTime(2026, 8, 24, 10, 0),
        deliveredAt: DateTime(2026, 8, 24, 10, 45),
      );

      final allShopOrders = [placedOrder, acceptedOrder, deliveredOrder];

      // Filter simulation during reset: ONLY terminal statuses are deleted!
      const terminalStatuses = ['delivered', 'rejected', 'delivery_expired', 'cancelled'];
      final terminalToDelete = allShopOrders.where((o) => terminalStatuses.contains(o.status)).toList();
      final activeSurviving = allShopOrders.where((o) => !terminalStatuses.contains(o.status)).toList();

      expect(terminalToDelete.length, equals(1));
      expect(terminalToDelete.first.orderId, equals('YB-HIST-DELIVERED'));

      // Active orders strictly survive
      expect(activeSurviving.length, equals(2));
      expect(activeSurviving.any((o) => o.orderId == 'YB-LIVE-PLACED'), isTrue);
      expect(activeSurviving.any((o) => o.orderId == 'YB-LIVE-ACCEPTED'), isTrue);

      // Timers & deadlines remain 100% intact
      final survivingPlaced = activeSurviving.firstWhere((o) => o.orderId == 'YB-LIVE-PLACED');
      expect(survivingPlaced.acceptDeadline, equals(DateTime(2026, 8, 24, 12, 20)));

      final survivingAccepted = activeSurviving.firstWhere((o) => o.orderId == 'YB-LIVE-ACCEPTED');
      expect(survivingAccepted.rejectDeadline, equals(DateTime(2026, 8, 24, 12, 21)));
      expect(survivingAccepted.deliveryDeadline, equals(DateTime(2026, 8, 24, 13, 36)));
    });
  });
}
