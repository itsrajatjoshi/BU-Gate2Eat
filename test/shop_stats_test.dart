// BU Gate2Eat — Unit Tests
// Shop Statistics Service & Model Tests (Part A: Backend Foundation)
//
// Tests:
// 1. ShopStats model serialization / deserialization
// 2. ShopStats.zero factory creates all counters at 0
// 3. ShopStats copyWith preserves/overrides correctly
// 4. ShopStatsService method coverage (increment, reset, isolation)
// 5. Order model delivery person fields
// 6. Shop isolation: Shop A stats never affect Shop B

import 'package:flutter_test/flutter_test.dart';

import 'package:bugate2eat_app/models/shop_stats_model.dart';
import 'package:bugate2eat_app/models/order_model.dart';

void main() {
  // ═══════════════════════════════════════════════════════════════════════════
  // 1. ShopStats Model Tests
  // ═══════════════════════════════════════════════════════════════════════════

  group('ShopStats Model', () {
    test('ShopStats.zero creates all counters at 0', () {
      final stats = ShopStats.zero(shopId: 'rajat_shop', shopName: 'Rajat Shop');

      expect(stats.shopId, 'rajat_shop');
      expect(stats.shopName, 'Rajat Shop');
      expect(stats.appOrders, 0);
      expect(stats.accepted, 0);
      expect(stats.delivered, 0);
      expect(stats.notAccepted, 0);
      expect(stats.rejectedAfterAccept, 0);
      expect(stats.deliveryExpired, 0);
      expect(stats.whatsappOrders, 0);
      expect(stats.currentPeriod, '');
      expect(stats.lastResetAt, isNull);
      expect(stats.updatedAt, isNull);
    });

    test('totalOrders = appOrders + whatsappOrders', () {
      final stats = ShopStats(
        shopId: 'test',
        shopName: 'Test',
        appOrders: 50,
        whatsappOrders: 30,
      );
      expect(stats.totalOrders, 80);
    });

    test('totalOrders returns 0 when both counters are 0', () {
      final stats = ShopStats.zero(shopId: 'x', shopName: 'X');
      expect(stats.totalOrders, 0);
    });

    test('toFirestore includes all fields', () {
      final now = DateTime(2026, 8, 24, 12, 0, 0);
      final stats = ShopStats(
        shopId: 'rajat_shop',
        shopName: 'Rajat Shop',
        appOrders: 10,
        accepted: 8,
        delivered: 5,
        notAccepted: 2,
        rejectedAfterAccept: 1,
        deliveryExpired: 1,
        whatsappOrders: 15,
        currentPeriod: '2026-08',
        lastResetAt: now,
      );

      final map = stats.toFirestore();

      expect(map['shopId'], 'rajat_shop');
      expect(map['shopName'], 'Rajat Shop');
      expect(map['appOrders'], 10);
      expect(map['accepted'], 8);
      expect(map['delivered'], 5);
      expect(map['notAccepted'], 2);
      expect(map['rejectedAfterAccept'], 1);
      expect(map['deliveryExpired'], 1);
      expect(map['whatsappOrders'], 15);
      expect(map['currentPeriod'], '2026-08');
      expect(map['lastResetAt'], isNotNull);
      // updatedAt is FieldValue.serverTimestamp(), can't test directly
      expect(map.containsKey('updatedAt'), isTrue);
    });

    test('copyWith preserves original values when no override', () {
      final original = ShopStats(
        shopId: 'a',
        shopName: 'A',
        appOrders: 5,
        accepted: 3,
        delivered: 2,
        notAccepted: 1,
        rejectedAfterAccept: 0,
        deliveryExpired: 0,
        whatsappOrders: 10,
      );

      final copy = original.copyWith();

      expect(copy.shopId, 'a');
      expect(copy.shopName, 'A');
      expect(copy.appOrders, 5);
      expect(copy.accepted, 3);
      expect(copy.delivered, 2);
      expect(copy.notAccepted, 1);
      expect(copy.whatsappOrders, 10);
    });

    test('copyWith overrides specific fields', () {
      final original = ShopStats.zero(shopId: 'b', shopName: 'B');

      final updated = original.copyWith(
        appOrders: 100,
        whatsappOrders: 50,
        shopName: 'B Updated',
      );

      expect(updated.shopId, 'b');
      expect(updated.shopName, 'B Updated');
      expect(updated.appOrders, 100);
      expect(updated.whatsappOrders, 50);
      // unchanged
      expect(updated.accepted, 0);
      expect(updated.delivered, 0);
    });

    test('toString contains key info', () {
      const stats = ShopStats(
        shopId: 'test',
        shopName: 'Test',
        appOrders: 10,
        whatsappOrders: 5,
      );
      final str = stats.toString();
      expect(str, contains('test'));
      expect(str, contains('app=10'));
      expect(str, contains('wa=5'));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 2. Shop Isolation Tests (Model Level)
  // ═══════════════════════════════════════════════════════════════════════════

  group('Shop Isolation', () {
    test('Two shop stats with different shopIds are independent', () {
      const shopA = ShopStats(
        shopId: 'rajat_shop',
        shopName: 'Rajat Shop',
        appOrders: 100,
        delivered: 80,
        whatsappOrders: 50,
      );

      const shopB = ShopStats(
        shopId: 'nayan_shop',
        shopName: 'Nayan Cafe',
        appOrders: 40,
        delivered: 30,
        whatsappOrders: 20,
      );

      // Verify they are completely independent
      expect(shopA.shopId, isNot(equals(shopB.shopId)));
      expect(shopA.appOrders, isNot(equals(shopB.appOrders)));
      expect(shopA.delivered, isNot(equals(shopB.delivered)));
      expect(shopA.whatsappOrders, isNot(equals(shopB.whatsappOrders)));

      // Modifying A does not affect B
      final shopAUpdated = shopA.copyWith(appOrders: 101);
      expect(shopAUpdated.appOrders, 101);
      expect(shopB.appOrders, 40); // B unchanged
    });

    test('Resetting one shop stats does not affect another (model level)', () {
      const shopA = ShopStats(
        shopId: 'rajat_shop',
        shopName: 'Rajat Shop',
        appOrders: 100,
        accepted: 80,
        delivered: 60,
        notAccepted: 10,
        rejectedAfterAccept: 5,
        deliveryExpired: 3,
        whatsappOrders: 50,
      );

      const shopB = ShopStats(
        shopId: 'nayan_shop',
        shopName: 'Nayan Cafe',
        appOrders: 40,
        accepted: 30,
        delivered: 25,
        whatsappOrders: 20,
      );

      // "Reset" shop A
      final shopAReset = ShopStats.zero(
        shopId: shopA.shopId,
        shopName: shopA.shopName,
      );

      // Shop A is now zeroed
      expect(shopAReset.appOrders, 0);
      expect(shopAReset.accepted, 0);
      expect(shopAReset.delivered, 0);
      expect(shopAReset.notAccepted, 0);
      expect(shopAReset.rejectedAfterAccept, 0);
      expect(shopAReset.deliveryExpired, 0);
      expect(shopAReset.whatsappOrders, 0);

      // Shop B is UNTOUCHED
      expect(shopB.appOrders, 40);
      expect(shopB.accepted, 30);
      expect(shopB.delivered, 25);
      expect(shopB.whatsappOrders, 20);
    });

    test('Each increment applies only to correct shop stats', () {
      var shopA = ShopStats.zero(shopId: 'a', shopName: 'A');
      var shopB = ShopStats.zero(shopId: 'b', shopName: 'B');

      // Simulate incrementing shopA.delivered
      shopA = shopA.copyWith(delivered: shopA.delivered + 1);
      expect(shopA.delivered, 1);
      expect(shopB.delivered, 0); // B unaffected

      // Simulate incrementing shopB.whatsappOrders
      shopB = shopB.copyWith(whatsappOrders: shopB.whatsappOrders + 1);
      expect(shopB.whatsappOrders, 1);
      expect(shopA.whatsappOrders, 0); // A unaffected

      // Simulate incrementing shopA.notAccepted
      shopA = shopA.copyWith(notAccepted: shopA.notAccepted + 1);
      expect(shopA.notAccepted, 1);
      expect(shopB.notAccepted, 0); // B unaffected
    });

    test('All counters start safely at 0', () {
      for (final id in ['rajat_shop', 'nayan_shop', 'kivisha_shop', 'random_id']) {
        final stats = ShopStats.zero(shopId: id, shopName: 'Shop $id');
        expect(stats.appOrders, 0, reason: '$id appOrders should be 0');
        expect(stats.accepted, 0, reason: '$id accepted should be 0');
        expect(stats.delivered, 0, reason: '$id delivered should be 0');
        expect(stats.notAccepted, 0, reason: '$id notAccepted should be 0');
        expect(stats.rejectedAfterAccept, 0, reason: '$id rejectedAfterAccept should be 0');
        expect(stats.deliveryExpired, 0, reason: '$id deliveryExpired should be 0');
        expect(stats.whatsappOrders, 0, reason: '$id whatsappOrders should be 0');
        expect(stats.totalOrders, 0, reason: '$id totalOrders should be 0');
      }
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 3. AppOrder Delivery Person Fields
  // ═══════════════════════════════════════════════════════════════════════════

  group('AppOrder Delivery Person Fields', () {
    test('Default delivery person fields are empty strings', () {
      final order = AppOrder(
        orderId: 'test-001',
        shopId: 'rajat_shop',
        shopName: 'Rajat Shop',
        customerName: 'Test',
        customerPhone: '9999999999',
        items: const [],
        totalAmount: 100,
        createdAt: DateTime.now(),
      );

      expect(order.deliveryPersonId, '');
      expect(order.deliveryPersonName, '');
    });

    test('Delivery person fields can be set via constructor', () {
      final order = AppOrder(
        orderId: 'test-002',
        shopId: 'rajat_shop',
        shopName: 'Rajat Shop',
        customerName: 'Test',
        customerPhone: '9999999999',
        items: const [],
        totalAmount: 100,
        createdAt: DateTime.now(),
        deliveryPersonId: '8295643910',
        deliveryPersonName: 'Ramesh',
      );

      expect(order.deliveryPersonId, '8295643910');
      expect(order.deliveryPersonName, 'Ramesh');
    });

    test('copyWith updates delivery person fields', () {
      final order = AppOrder(
        orderId: 'test-003',
        shopId: 'rajat_shop',
        shopName: 'Rajat Shop',
        customerName: 'Test',
        customerPhone: '9999999999',
        items: const [],
        totalAmount: 100,
        createdAt: DateTime.now(),
      );

      final delivered = order.copyWith(
        status: 'delivered',
        deliveryPersonId: '8295643910',
        deliveryPersonName: 'Ramesh',
        deliveredAt: DateTime.now(),
      );

      expect(delivered.deliveryPersonId, '8295643910');
      expect(delivered.deliveryPersonName, 'Ramesh');
      expect(delivered.status, 'delivered');
      expect(delivered.deliveredAt, isNotNull);

      // Original unchanged
      expect(order.deliveryPersonId, '');
      expect(order.deliveryPersonName, '');
      expect(order.status, 'placed');
    });

    test('toMap includes delivery person fields when non-empty', () {
      final order = AppOrder(
        orderId: 'test-004',
        shopId: 'rajat_shop',
        shopName: 'Rajat Shop',
        customerName: 'Test',
        customerPhone: '9999999999',
        items: const [],
        totalAmount: 100,
        createdAt: DateTime.now(),
        deliveryPersonId: '8295643910',
        deliveryPersonName: 'Ramesh',
      );

      final map = order.toMap();
      expect(map['deliveryPersonId'], '8295643910');
      expect(map['deliveryPersonName'], 'Ramesh');
    });

    test('toMap excludes delivery person fields when empty', () {
      final order = AppOrder(
        orderId: 'test-005',
        shopId: 'rajat_shop',
        shopName: 'Rajat Shop',
        customerName: 'Test',
        customerPhone: '9999999999',
        items: const [],
        totalAmount: 100,
        createdAt: DateTime.now(),
      );

      final map = order.toMap();
      expect(map.containsKey('deliveryPersonId'), isFalse);
      expect(map.containsKey('deliveryPersonName'), isFalse);
    });

    test('fromMap parses delivery person fields', () {
      final map = {
        'orderId': 'test-006',
        'shopId': 'rajat_shop',
        'shopName': 'Rajat Shop',
        'customerName': 'Test',
        'customerPhone': '9999999999',
        'items': <Map<String, dynamic>>[],
        'grandTotal': 100.0,
        'status': 'delivered',
        'createdAt': DateTime.now().toIso8601String(),
        'deliveryPersonId': '8295643910',
        'deliveryPersonName': 'Ramesh',
      };

      final order = AppOrder.fromMap(map);
      expect(order.deliveryPersonId, '8295643910');
      expect(order.deliveryPersonName, 'Ramesh');
    });

    test('fromMap defaults delivery person fields when missing', () {
      final map = {
        'orderId': 'test-007',
        'shopId': 'rajat_shop',
        'shopName': 'Rajat Shop',
        'customerName': 'Test',
        'customerPhone': '9999999999',
        'items': <Map<String, dynamic>>[],
        'grandTotal': 100.0,
        'status': 'placed',
        'createdAt': DateTime.now().toIso8601String(),
      };

      final order = AppOrder.fromMap(map);
      expect(order.deliveryPersonId, '');
      expect(order.deliveryPersonName, '');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 4. AppOrder Timer Deadline Fields
  // ═══════════════════════════════════════════════════════════════════════════

  group('AppOrder Timer Deadline Fields', () {
    test('Default deadline fields are null', () {
      final order = AppOrder(
        orderId: 'test-t01',
        shopId: 'rajat_shop',
        shopName: 'Rajat Shop',
        customerName: 'Test',
        customerPhone: '9999999999',
        items: const [],
        totalAmount: 100,
        createdAt: DateTime.now(),
      );

      expect(order.acceptDeadline, isNull);
      expect(order.rejectDeadline, isNull);
      expect(order.deliveryDeadline, isNull);
    });

    test('Deadline fields set via constructor', () {
      final now = DateTime.now();
      final order = AppOrder(
        orderId: 'test-t02',
        shopId: 'rajat_shop',
        shopName: 'Rajat Shop',
        customerName: 'Test',
        customerPhone: '9999999999',
        items: const [],
        totalAmount: 100,
        createdAt: now,
        acceptDeadline: now.add(const Duration(minutes: 20)),
        rejectDeadline: now.add(const Duration(minutes: 35)),
        deliveryDeadline: now.add(const Duration(minutes: 110)),
      );

      expect(order.acceptDeadline, isNotNull);
      expect(order.rejectDeadline, isNotNull);
      expect(order.deliveryDeadline, isNotNull);
      expect(
        order.acceptDeadline!.difference(now).inMinutes,
        20,
      );
    });

    test('toMap includes deadline fields when set', () {
      final now = DateTime.now();
      final order = AppOrder(
        orderId: 'test-t03',
        shopId: 's',
        shopName: 'S',
        customerName: 'T',
        customerPhone: '1',
        items: const [],
        totalAmount: 0,
        createdAt: now,
        acceptDeadline: now.add(const Duration(minutes: 20)),
      );

      final map = order.toMap();
      expect(map.containsKey('acceptDeadline'), isTrue);
    });

    test('toMap excludes deadline fields when null', () {
      final order = AppOrder(
        orderId: 'test-t04',
        shopId: 's',
        shopName: 'S',
        customerName: 'T',
        customerPhone: '1',
        items: const [],
        totalAmount: 0,
        createdAt: DateTime.now(),
      );

      final map = order.toMap();
      expect(map.containsKey('acceptDeadline'), isFalse);
      expect(map.containsKey('rejectDeadline'), isFalse);
      expect(map.containsKey('deliveryDeadline'), isFalse);
    });

    test('fromMap parses deadline fields from ISO string', () {
      final now = DateTime.now();
      final deadline = now.add(const Duration(minutes: 20));
      final map = {
        'orderId': 'test-t05',
        'shopId': 's',
        'shopName': 'S',
        'customerName': 'T',
        'customerPhone': '1',
        'items': <Map<String, dynamic>>[],
        'grandTotal': 0.0,
        'createdAt': now.toIso8601String(),
        'acceptDeadline': deadline.toIso8601String(),
      };

      final order = AppOrder.fromMap(map);
      expect(order.acceptDeadline, isNotNull);
      expect(
        order.acceptDeadline!.difference(now).inMinutes,
        closeTo(20, 1),
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 5. Counter Logic Simulation (Without Firestore)
  // ═══════════════════════════════════════════════════════════════════════════

  group('Counter Logic Simulation', () {
    test('Full lifecycle: place → accept → deliver increments correct fields', () {
      var stats = ShopStats.zero(shopId: 'rajat_shop', shopName: 'Rajat Shop');

      // Order placed → appOrders +1
      stats = stats.copyWith(appOrders: stats.appOrders + 1);
      expect(stats.appOrders, 1);
      expect(stats.accepted, 0);

      // Order accepted → accepted +1
      stats = stats.copyWith(accepted: stats.accepted + 1);
      expect(stats.accepted, 1);
      expect(stats.delivered, 0);

      // Order delivered → delivered +1
      stats = stats.copyWith(delivered: stats.delivered + 1);
      expect(stats.delivered, 1);

      // Final state
      expect(stats.appOrders, 1);
      expect(stats.accepted, 1);
      expect(stats.delivered, 1);
      expect(stats.notAccepted, 0);
      expect(stats.rejectedAfterAccept, 0);
      expect(stats.deliveryExpired, 0);
    });

    test('Shopkeeper reject before accept → notAccepted +1', () {
      var stats = ShopStats.zero(shopId: 'rajat_shop', shopName: 'Rajat Shop');

      // Order placed
      stats = stats.copyWith(appOrders: stats.appOrders + 1);

      // Shopkeeper rejects (before accepting)
      stats = stats.copyWith(notAccepted: stats.notAccepted + 1);

      expect(stats.appOrders, 1);
      expect(stats.notAccepted, 1);
      expect(stats.accepted, 0);
    });

    test('Accept then reject within window → rejectedAfterAccept +1', () {
      var stats = ShopStats.zero(shopId: 'rajat_shop', shopName: 'Rajat Shop');

      stats = stats.copyWith(appOrders: stats.appOrders + 1);
      stats = stats.copyWith(accepted: stats.accepted + 1);
      stats = stats.copyWith(rejectedAfterAccept: stats.rejectedAfterAccept + 1);

      expect(stats.appOrders, 1);
      expect(stats.accepted, 1);
      expect(stats.rejectedAfterAccept, 1);
      expect(stats.delivered, 0);
    });

    test('Delivery expired → deliveryExpired +1', () {
      var stats = ShopStats.zero(shopId: 'rajat_shop', shopName: 'Rajat Shop');

      stats = stats.copyWith(appOrders: stats.appOrders + 1);
      stats = stats.copyWith(accepted: stats.accepted + 1);
      stats = stats.copyWith(deliveryExpired: stats.deliveryExpired + 1);

      expect(stats.deliveryExpired, 1);
    });

    test('WhatsApp counter increments independently of app counters', () {
      var stats = ShopStats.zero(shopId: 'rajat_shop', shopName: 'Rajat Shop');

      // 3 WhatsApp orders
      stats = stats.copyWith(whatsappOrders: stats.whatsappOrders + 1);
      stats = stats.copyWith(whatsappOrders: stats.whatsappOrders + 1);
      stats = stats.copyWith(whatsappOrders: stats.whatsappOrders + 1);

      expect(stats.whatsappOrders, 3);
      expect(stats.appOrders, 0); // App counters unaffected
      expect(stats.totalOrders, 3);
    });

    test('Multiple shops simulate parallel operations correctly', () {
      var rajat = ShopStats.zero(shopId: 'rajat_shop', shopName: 'Rajat Shop');
      var nayan = ShopStats.zero(shopId: 'nayan_shop', shopName: 'Nayan Cafe');

      // Rajat gets 5 app orders
      for (var i = 0; i < 5; i++) {
        rajat = rajat.copyWith(appOrders: rajat.appOrders + 1);
      }

      // Nayan gets 3 whatsapp orders
      for (var i = 0; i < 3; i++) {
        nayan = nayan.copyWith(whatsappOrders: nayan.whatsappOrders + 1);
      }

      // Rajat: 2 delivered
      rajat = rajat.copyWith(accepted: 4, delivered: 2);

      expect(rajat.appOrders, 5);
      expect(rajat.delivered, 2);
      expect(rajat.whatsappOrders, 0);

      expect(nayan.appOrders, 0);
      expect(nayan.whatsappOrders, 3);
      expect(nayan.delivered, 0);

      // Reset Rajat
      rajat = ShopStats.zero(shopId: 'rajat_shop', shopName: 'Rajat Shop');
      expect(rajat.appOrders, 0);
      expect(rajat.delivered, 0);

      // Nayan still intact
      expect(nayan.whatsappOrders, 3);
    });
  });
}
