// BU Gate2Eat — Core Utilities
// OrderTimerHelper (Authoritative deadline & countdown calculation for order lifecycle)

import '../../models/order_model.dart';

/// Centralized utility for computing authoritative order deadlines, remaining countdowns,
/// and expiration boundaries across Customer, Shopkeeper, and Admin panels.
class OrderTimerHelper {
  OrderTimerHelper._();

  /// 20-minute window for the shopkeeper to accept a placed order.
  static const int acceptWindowMinutes = 20;

  /// 15-minute window after acceptance during which the shopkeeper may still reject the order.
  static const int rejectWindowMinutes = 15;

  /// 90-minute window after acceptance to prepare and deliver the order.
  static const int deliveryWindowMinutes = 90;

  // ─── Authoritative Deadline Resolvers ─────────────────────────────────────

  /// Returns the authoritative deadline for a `placed` order to be accepted.
  static DateTime getAcceptDeadline(AppOrder order) {
    if (order.acceptDeadline != null) {
      return order.acceptDeadline!;
    }
    return order.createdAt.add(const Duration(minutes: acceptWindowMinutes));
  }

  /// Returns the authoritative deadline for an `accepted` order to be rejected (15 min after acceptedAt).
  static DateTime? getRejectDeadline(AppOrder order) {
    if (order.rejectDeadline != null) {
      return order.rejectDeadline!;
    }
    final acceptTime = order.acceptedAt ?? (order.isAccepted ? order.createdAt : null);
    if (acceptTime != null) {
      return acceptTime.add(const Duration(minutes: rejectWindowMinutes));
    }
    return null;
  }

  /// Returns the authoritative deadline for an `accepted` order to be delivered (90 min after acceptedAt).
  static DateTime? getDeliveryDeadline(AppOrder order) {
    if (order.deliveryDeadline != null) {
      return order.deliveryDeadline!;
    }
    final acceptTime = order.acceptedAt ?? (order.isAccepted ? order.createdAt : null);
    if (acceptTime != null) {
      return acceptTime.add(const Duration(minutes: deliveryWindowMinutes));
    }
    return null;
  }

  // ─── Remaining Duration Computations ──────────────────────────────────────

  /// Returns the remaining duration for accepting a `placed` order.
  /// Returns [Duration.zero] if the deadline has already passed.
  static Duration getRemainingAcceptDuration(AppOrder order, [DateTime? customNow]) {
    final now = customNow ?? DateTime.now();
    final deadline = getAcceptDeadline(order);
    final diff = deadline.difference(now);
    return diff.isNegative ? Duration.zero : diff;
  }

  /// Returns the remaining duration for rejecting an `accepted` order.
  /// Returns [Duration.zero] if the 15-minute window has expired or order is not accepted.
  static Duration getRemainingRejectDuration(AppOrder order, [DateTime? customNow]) {
    final deadline = getRejectDeadline(order);
    if (deadline == null) return Duration.zero;
    final now = customNow ?? DateTime.now();
    final diff = deadline.difference(now);
    return diff.isNegative ? Duration.zero : diff;
  }

  /// Returns the remaining duration for delivering an `accepted` order.
  /// Returns [Duration.zero] if the 90-minute window has expired or order is not accepted.
  static Duration getRemainingDeliveryDuration(AppOrder order, [DateTime? customNow]) {
    final deadline = getDeliveryDeadline(order);
    if (deadline == null) return Duration.zero;
    final now = customNow ?? DateTime.now();
    final diff = deadline.difference(now);
    return diff.isNegative ? Duration.zero : diff;
  }

  // ─── Expiration Predicates ────────────────────────────────────────────────

  /// Returns true if a `placed` order has exceeded its 20-minute acceptance window.
  static bool isAcceptExpired(AppOrder order, [DateTime? customNow]) {
    final now = customNow ?? DateTime.now();
    final deadline = getAcceptDeadline(order);
    return !now.isBefore(deadline); // now >= deadline
  }

  /// Returns true if an `accepted` order has passed its 15-minute rejection window.
  static bool isRejectExpired(AppOrder order, [DateTime? customNow]) {
    if (!order.isAccepted) return true;
    final deadline = getRejectDeadline(order);
    if (deadline == null) return false;
    final now = customNow ?? DateTime.now();
    return !now.isBefore(deadline); // now >= deadline
  }

  /// Returns true if an `accepted` order has exceeded its 90-minute delivery window.
  static bool isDeliveryExpired(AppOrder order, [DateTime? customNow]) {
    if (!order.isAccepted) return false;
    final deadline = getDeliveryDeadline(order);
    if (deadline == null) return false;
    final now = customNow ?? DateTime.now();
    return !now.isBefore(deadline); // now >= deadline
  }

  // ─── Formatting Helper ────────────────────────────────────────────────────

  /// Formats a duration into standard `mm:ss` countdown string (e.g. "19:42", "04:09", "00:00").
  /// Negative durations are safely clamped to `"00:00"`.
  static String formatCountdown(Duration duration) {
    if (duration <= Duration.zero) return '00:00';
    final totalSeconds = duration.inSeconds;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    final mStr = minutes.toString().padLeft(2, '0');
    final sStr = seconds.toString().padLeft(2, '0');
    return '$mStr:$sStr';
  }
}
