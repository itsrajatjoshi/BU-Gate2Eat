// BU Gate2Eat — OrderTimerHelper Unit Tests
// Tests exact 20m, 15m, 90m boundaries, countdown formatting, and clamping

import 'package:flutter_test/flutter_test.dart';

import 'package:bugate2eat_app/core/utils/order_timer_helper.dart';
import 'package:bugate2eat_app/models/order_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final baseTime = DateTime(2026, 8, 26, 12, 0, 0);

  AppOrder createTestOrder({
    String status = 'placed',
    DateTime? createdAt,
    DateTime? acceptDeadline,
    DateTime? acceptedAt,
    DateTime? rejectDeadline,
    DateTime? deliveryDeadline,
  }) {
    final created = createdAt ?? baseTime;
    return AppOrder(
      orderId: 'ORD_TEST_001',
      customerId: 'CUST_1',
      customerName: 'Test Student',
      customerPhone: '9876543210',
      shopId: 'shop_1',
      shopName: 'Test Shop',
      items: const [
        OrderItem(
          menuItemId: 'item_1',
          name: 'Burger',
          price: 100,
          quantity: 1,
        ),
      ],
      totalAmount: 100,
      status: status,
      createdAt: created,
      acceptDeadline: acceptDeadline ?? created.add(const Duration(minutes: 20)),
      acceptedAt: acceptedAt,
      rejectDeadline: rejectDeadline,
      deliveryDeadline: deliveryDeadline,
    );
  }

  group('OrderTimerHelper: 20-min Acceptance Window Tests', () {
    test('Calculates accept deadline from createdAt if acceptDeadline not provided', () {
      final order = createTestOrder(createdAt: baseTime);
      final deadline = OrderTimerHelper.getAcceptDeadline(order);
      expect(deadline, equals(baseTime.add(const Duration(minutes: 20))));
    });

    test('Remaining accept duration at 0 min elapsed is exactly 20 minutes', () {
      final order = createTestOrder(createdAt: baseTime);
      final remaining = OrderTimerHelper.getRemainingAcceptDuration(order, baseTime);
      expect(remaining, equals(const Duration(minutes: 20)));
      expect(OrderTimerHelper.formatCountdown(remaining), equals('20:00'));
      expect(OrderTimerHelper.isAcceptExpired(order, baseTime), isFalse);
    });

    test('Remaining accept duration at 10 min elapsed is 10:00', () {
      final order = createTestOrder(createdAt: baseTime);
      final now = baseTime.add(const Duration(minutes: 10));
      final remaining = OrderTimerHelper.getRemainingAcceptDuration(order, now);
      expect(remaining, equals(const Duration(minutes: 10)));
      expect(OrderTimerHelper.formatCountdown(remaining), equals('10:00'));
      expect(OrderTimerHelper.isAcceptExpired(order, now), isFalse);
    });

    test('Remaining accept duration at 19m 59s elapsed is 00:01', () {
      final order = createTestOrder(createdAt: baseTime);
      final now = baseTime.add(const Duration(minutes: 19, seconds: 59));
      final remaining = OrderTimerHelper.getRemainingAcceptDuration(order, now);
      expect(remaining, equals(const Duration(seconds: 1)));
      expect(OrderTimerHelper.formatCountdown(remaining), equals('00:01'));
      expect(OrderTimerHelper.isAcceptExpired(order, now), isFalse);
    });

    test('At exactly 20 minutes elapsed, remaining is 00:00 and isAcceptExpired is true', () {
      final order = createTestOrder(createdAt: baseTime);
      final now = baseTime.add(const Duration(minutes: 20));
      final remaining = OrderTimerHelper.getRemainingAcceptDuration(order, now);
      expect(remaining, equals(Duration.zero));
      expect(OrderTimerHelper.formatCountdown(remaining), equals('00:00'));
      expect(OrderTimerHelper.isAcceptExpired(order, now), isTrue);
    });

    test('Past 20 minutes (e.g. 25 min elapsed), remaining clamps to 00:00 and isAcceptExpired is true', () {
      final order = createTestOrder(createdAt: baseTime);
      final now = baseTime.add(const Duration(minutes: 25));
      final remaining = OrderTimerHelper.getRemainingAcceptDuration(order, now);
      expect(remaining, equals(Duration.zero));
      expect(OrderTimerHelper.formatCountdown(remaining), equals('00:00'));
      expect(OrderTimerHelper.isAcceptExpired(order, now), isTrue);
    });
  });

  group('OrderTimerHelper: 15-min Rejection Window Tests', () {
    final acceptedTime = baseTime.add(const Duration(minutes: 5));

    test('Reject deadline is exactly acceptedAt + 15 minutes', () {
      final order = createTestOrder(
        status: 'accepted',
        createdAt: baseTime,
        acceptedAt: acceptedTime,
        rejectDeadline: acceptedTime.add(const Duration(minutes: 15)),
      );
      final deadline = OrderTimerHelper.getRejectDeadline(order);
      expect(deadline, equals(acceptedTime.add(const Duration(minutes: 15))));
    });

    test('Within 15-min window (e.g. 7 min after accept), isRejectExpired is false', () {
      final order = createTestOrder(
        status: 'accepted',
        createdAt: baseTime,
        acceptedAt: acceptedTime,
        rejectDeadline: acceptedTime.add(const Duration(minutes: 15)),
      );
      final now = acceptedTime.add(const Duration(minutes: 7));
      final remaining = OrderTimerHelper.getRemainingRejectDuration(order, now);
      expect(remaining, equals(const Duration(minutes: 8)));
      expect(OrderTimerHelper.formatCountdown(remaining), equals('08:00'));
      expect(OrderTimerHelper.isRejectExpired(order, now), isFalse);
    });

    test('At exactly 15 minutes after accept, isRejectExpired is true', () {
      final order = createTestOrder(
        status: 'accepted',
        createdAt: baseTime,
        acceptedAt: acceptedTime,
        rejectDeadline: acceptedTime.add(const Duration(minutes: 15)),
      );
      final now = acceptedTime.add(const Duration(minutes: 15));
      final remaining = OrderTimerHelper.getRemainingRejectDuration(order, now);
      expect(remaining, equals(Duration.zero));
      expect(OrderTimerHelper.isRejectExpired(order, now), isTrue);
    });

    test('After 15 minutes after accept (e.g. 16 min), isRejectExpired is true', () {
      final order = createTestOrder(
        status: 'accepted',
        createdAt: baseTime,
        acceptedAt: acceptedTime,
        rejectDeadline: acceptedTime.add(const Duration(minutes: 15)),
      );
      final now = acceptedTime.add(const Duration(minutes: 16));
      expect(OrderTimerHelper.isRejectExpired(order, now), isTrue);
    });
  });

  group('OrderTimerHelper: 90-min Delivery Window Tests', () {
    final acceptedTime = baseTime.add(const Duration(minutes: 5));

    test('Delivery deadline is acceptedAt + 90 minutes', () {
      final order = createTestOrder(
        status: 'accepted',
        createdAt: baseTime,
        acceptedAt: acceptedTime,
        deliveryDeadline: acceptedTime.add(const Duration(minutes: 90)),
      );
      final deadline = OrderTimerHelper.getDeliveryDeadline(order);
      expect(deadline, equals(acceptedTime.add(const Duration(minutes: 90))));
    });

    test('Within 90-min window (e.g. 30 min after accept), isDeliveryExpired is false', () {
      final order = createTestOrder(
        status: 'accepted',
        createdAt: baseTime,
        acceptedAt: acceptedTime,
        deliveryDeadline: acceptedTime.add(const Duration(minutes: 90)),
      );
      final now = acceptedTime.add(const Duration(minutes: 30));
      final remaining = OrderTimerHelper.getRemainingDeliveryDuration(order, now);
      expect(remaining, equals(const Duration(minutes: 60)));
      expect(OrderTimerHelper.formatCountdown(remaining), equals('60:00'));
      expect(OrderTimerHelper.isDeliveryExpired(order, now), isFalse);
    });

    test('At exactly 90 minutes after accept, isDeliveryExpired is true', () {
      final order = createTestOrder(
        status: 'accepted',
        createdAt: baseTime,
        acceptedAt: acceptedTime,
        deliveryDeadline: acceptedTime.add(const Duration(minutes: 90)),
      );
      final now = acceptedTime.add(const Duration(minutes: 90));
      final remaining = OrderTimerHelper.getRemainingDeliveryDuration(order, now);
      expect(remaining, equals(Duration.zero));
      expect(OrderTimerHelper.isDeliveryExpired(order, now), isTrue);
    });

    test('After 90 minutes after accept (e.g. 91 min), isDeliveryExpired is true', () {
      final order = createTestOrder(
        status: 'accepted',
        createdAt: baseTime,
        acceptedAt: acceptedTime,
        deliveryDeadline: acceptedTime.add(const Duration(minutes: 90)),
      );
      final now = acceptedTime.add(const Duration(minutes: 91));
      expect(OrderTimerHelper.isDeliveryExpired(order, now), isTrue);
    });
  });

  group('OrderTimerHelper: formatCountdown formatting tests', () {
    test('Formats zero and negative durations as 00:00', () {
      expect(OrderTimerHelper.formatCountdown(Duration.zero), equals('00:00'));
      expect(OrderTimerHelper.formatCountdown(const Duration(seconds: -10)), equals('00:00'));
    });

    test('Formats single digit seconds with leading zero', () {
      expect(OrderTimerHelper.formatCountdown(const Duration(minutes: 5, seconds: 3)), equals('05:03'));
      expect(OrderTimerHelper.formatCountdown(const Duration(seconds: 9)), equals('00:09'));
    });

    test('Formats large minute counts correctly', () {
      expect(OrderTimerHelper.formatCountdown(const Duration(minutes: 89, seconds: 59)), equals('89:59'));
    });
  });
}
