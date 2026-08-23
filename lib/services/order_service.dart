// BU Gate2Eat — Services
// Firestore Order Service & Repository Layer (Phase 3 — Part 3.1)
// Handles order creation, retrieval, real-time streams, status transitions, and lifecycle validation.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/order_model.dart';

/// Exceptions for Order Service operations.
class OrderServiceException implements Exception {
  const OrderServiceException(this.message);
  final String message;

  @override
  String toString() => 'OrderServiceException: $message';
}

class OrderNotFoundException extends OrderServiceException {
  const OrderNotFoundException(String orderId)
      : super('Order with ID "$orderId" was not found.');
}

class InvalidOrderTransitionException extends OrderServiceException {
  const InvalidOrderTransitionException({
    required this.currentStatus,
    required this.targetStatus,
  }) : super(
          'Invalid status transition from "$currentStatus" to "$targetStatus".',
        );

  final String currentStatus;
  final String targetStatus;
}

/// Centralized status transition validation rules for YummBU orders.
class OrderStatusRules {
  OrderStatusRules._();

  static const String statusPlaced = 'placed';
  static const String statusAccepted = 'accepted';
  static const String statusDelivered = 'delivered';
  static const String statusRejected = 'rejected';
  static const String statusCancelled = 'cancelled';

  static const Set<String> activeStatuses = {
    statusPlaced,
    statusAccepted,
  };

  static const Set<String> terminalStatuses = {
    statusDelivered,
    statusRejected,
    statusCancelled,
  };

  /// Map of allowed transitions for each status.
  static const Map<String, Set<String>> _allowedTransitions = {
    statusPlaced: {statusAccepted, statusRejected, statusCancelled},
    statusAccepted: {statusDelivered, statusRejected},
    statusDelivered: {}, // Terminal: No further transitions allowed
    statusRejected: {}, // Terminal: No further transitions allowed
    statusCancelled: {}, // Terminal: No further transitions allowed
  };

  /// Checks if transition from [fromStatus] to [toStatus] is permitted.
  static bool isValidTransition(String fromStatus, String toStatus) {
    if (fromStatus == toStatus) return true;
    final allowed = _allowedTransitions[fromStatus];
    if (allowed == null) return false;
    return allowed.contains(toStatus);
  }

  /// Verifies if a status is terminal.
  static bool isTerminal(String status) => terminalStatuses.contains(status);

  /// Verifies if a status is active.
  static bool isActive(String status) => activeStatuses.contains(status);
}

/// Service class for Firestore `orders` collection operations.
class OrderService {
  OrderService({FirebaseFirestore? firestore}) : _customFirestore = firestore;

  final FirebaseFirestore? _customFirestore;

  FirebaseFirestore get _firestore =>
      _customFirestore ?? FirebaseFirestore.instance;

  static const String collectionName = 'orders';

  CollectionReference<Map<String, dynamic>> get _ordersRef =>
      _firestore.collection(collectionName);

  // ─── Create Order ──────────────────────────────────────────────────────────

  /// Creates a new order document in Firestore.
  Future<void> createOrder(AppOrder order) async {
    try {
      final docRef = _ordersRef.doc(order.orderId);
      final data = order.toFirestore();
      // Use server timestamp for precision on creation
      data['createdAt'] = FieldValue.serverTimestamp();
      data['updatedAt'] = FieldValue.serverTimestamp();

      await docRef.set(data);
    } catch (e) {
      debugPrint('❌ OrderService createOrder error: $e');
      throw OrderServiceException('Failed to create order: $e');
    }
  }

  // ─── Get Single Order ──────────────────────────────────────────────────────

  /// Fetches a single order document by [orderId].
  Future<AppOrder?> getOrder(String orderId) async {
    try {
      final doc = await _ordersRef.doc(orderId).get();
      if (!doc.exists || doc.data() == null) {
        return null;
      }
      return AppOrder.fromFirestore(doc);
    } catch (e) {
      debugPrint('❌ OrderService getOrder error: $e');
      throw OrderServiceException('Failed to fetch order: $e');
    }
  }

  // ─── Real-Time Single Order Stream ─────────────────────────────────────────

  /// Watches a single order for real-time status and detail updates.
  Stream<AppOrder?> watchOrder(String orderId) {
    return _ordersRef.doc(orderId).snapshots().map((doc) {
      if (!doc.exists || doc.data() == null) return null;
      return AppOrder.fromFirestore(doc);
    });
  }

  // ─── Customer Streams ──────────────────────────────────────────────────────

  /// Real-time stream of a customer's active orders (placed, accepted).
  Stream<List<AppOrder>> watchCustomerActiveOrders({
    String? customerId,
    String? customerPhone,
  }) {
    Query<Map<String, dynamic>> query = _ordersRef;

    if (customerId != null && customerId.isNotEmpty) {
      query = query.where('customerId', isEqualTo: customerId);
    } else if (customerPhone != null && customerPhone.isNotEmpty) {
      query = query.where('customerPhone', isEqualTo: customerPhone);
    }

    return query
        .where('status', whereIn: OrderStatusRules.activeStatuses.toList())
        .snapshots()
        .map((snapshot) {
      final orders =
          snapshot.docs.map((doc) => AppOrder.fromFirestore(doc)).toList();
      orders.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return orders;
    });
  }

  /// Real-time stream of a customer's completed/terminal order history.
  Stream<List<AppOrder>> watchCustomerOrderHistory({
    String? customerId,
    String? customerPhone,
  }) {
    Query<Map<String, dynamic>> query = _ordersRef;

    if (customerId != null && customerId.isNotEmpty) {
      query = query.where('customerId', isEqualTo: customerId);
    } else if (customerPhone != null && customerPhone.isNotEmpty) {
      query = query.where('customerPhone', isEqualTo: customerPhone);
    }

    return query
        .where('status', whereIn: OrderStatusRules.terminalStatuses.toList())
        .snapshots()
        .map((snapshot) {
      final orders =
          snapshot.docs.map((doc) => AppOrder.fromFirestore(doc)).toList();
      orders.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return orders;
    });
  }

  // ─── Shopkeeper Streams ────────────────────────────────────────────────────

  /// Real-time stream of a shop's active orders (placed, accepted).
  Stream<List<AppOrder>> watchShopActiveOrders(String shopId) {
    return _ordersRef
        .where('shopId', isEqualTo: shopId)
        .where('status', whereIn: OrderStatusRules.activeStatuses.toList())
        .snapshots()
        .map((snapshot) {
      final orders =
          snapshot.docs.map((doc) => AppOrder.fromFirestore(doc)).toList();
      orders.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return orders;
    });
  }

  /// Real-time stream of a shop's order history (delivered, rejected, cancelled).
  Stream<List<AppOrder>> watchShopOrderHistory(String shopId) {
    return _ordersRef
        .where('shopId', isEqualTo: shopId)
        .where('status', whereIn: OrderStatusRules.terminalStatuses.toList())
        .snapshots()
        .map((snapshot) {
      final orders =
          snapshot.docs.map((doc) => AppOrder.fromFirestore(doc)).toList();
      orders.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return orders;
    });
  }

  // ─── Status Update with Strict Lifecycle Validation ────────────────────────

  /// Updates the order status to [newStatus] after validating the transition rule.
  Future<void> updateOrderStatus(
    String orderId,
    String newStatus, {
    String? rejectionReason,
  }) async {
    try {
      final docRef = _ordersRef.doc(orderId);
      final doc = await docRef.get();

      if (!doc.exists || doc.data() == null) {
        throw OrderNotFoundException(orderId);
      }

      final currentStatus = (doc.data()!['status'] as String?) ?? 'placed';

      if (!OrderStatusRules.isValidTransition(currentStatus, newStatus)) {
        throw InvalidOrderTransitionException(
          currentStatus: currentStatus,
          targetStatus: newStatus,
        );
      }

      final Map<String, dynamic> updates = {
        'status': newStatus,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (newStatus == OrderStatusRules.statusAccepted) {
        updates['acceptedAt'] = FieldValue.serverTimestamp();
      } else if (newStatus == OrderStatusRules.statusDelivered) {
        updates['deliveredAt'] = FieldValue.serverTimestamp();
      } else if (newStatus == OrderStatusRules.statusRejected) {
        updates['rejectedAt'] = FieldValue.serverTimestamp();
        if (rejectionReason != null && rejectionReason.trim().isNotEmpty) {
          updates['rejectionReason'] = rejectionReason.trim();
        }
      } else if (newStatus == OrderStatusRules.statusCancelled) {
        updates['cancelledAt'] = FieldValue.serverTimestamp();
      }

      await docRef.update(updates);
    } on OrderServiceException {
      rethrow;
    } catch (e) {
      debugPrint('❌ OrderService updateOrderStatus error: $e');
      throw OrderServiceException('Failed to update order status: $e');
    }
  }

  /// Cancels an order if it is currently in 'placed' status.
  Future<void> cancelOrder(String orderId) async {
    await updateOrderStatus(orderId, OrderStatusRules.statusCancelled);
  }
}
