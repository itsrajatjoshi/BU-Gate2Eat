// BU Gate2Eat — Services
// Firestore Order Service & Repository Layer (Phase 3 — Part 3.1)
// Handles order creation, retrieval, real-time streams, status transitions, and lifecycle validation.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
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
  static const String statusDeliveryExpired = 'delivery_expired';

  static const Set<String> activeStatuses = {
    statusPlaced,
    statusAccepted,
  };

  static const Set<String> terminalStatuses = {
    statusDelivered,
    statusRejected,
    statusCancelled,
    statusDeliveryExpired,
  };

  /// Map of allowed transitions for each status.
  static const Map<String, Set<String>> _allowedTransitions = {
    statusPlaced: {statusAccepted, statusRejected, statusCancelled},
    statusAccepted: {statusDelivered, statusRejected, statusDeliveryExpired},
    statusDelivered: {}, // Terminal: No further transitions allowed
    statusRejected: {}, // Terminal: No further transitions allowed
    statusCancelled: {}, // Terminal: No further transitions allowed
    statusDeliveryExpired: {}, // Terminal: No further transitions allowed
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

/// Service class for Firestore `orders` collection operations and lifecycle transitions.
class OrderService {
  OrderService({FirebaseFirestore? firestore}) : _customFirestore = firestore;

  final FirebaseFirestore? _customFirestore;

  /// Checks if Firebase is initialized or custom firestore instance is provided.
  bool get isAvailable {
    try {
      if (_customFirestore != null) return true;
      return Firebase.apps.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  FirebaseFirestore get _firestore =>
      _customFirestore ?? FirebaseFirestore.instance;

  static const String collectionName = 'orders';
  static const String statsCollectionName = 'shopStats';

  CollectionReference<Map<String, dynamic>> get _ordersRef =>
      _firestore.collection(collectionName);

  CollectionReference<Map<String, dynamic>> get _statsRef =>
      _firestore.collection(statsCollectionName);

  // ─── Create Order ──────────────────────────────────────────────────────────

  /// Creates a new order document in Firestore.
  /// Sets [acceptDeadline] to createdAt + 20 minutes.
  /// NOTE: Does NOT increment any shopStats counter yet — pre-accept cancel deletes the order completely.
  Future<void> createOrder(AppOrder order, {DateTime? customNow}) async {
    try {
      final docRef = _ordersRef.doc(order.orderId);
      final data = order.toFirestore();
      final now = customNow ?? DateTime.now();

      // Use server timestamp for precision on creation
      data['createdAt'] = FieldValue.serverTimestamp();
      data['updatedAt'] = FieldValue.serverTimestamp();

      if (!data.containsKey('acceptDeadline') || data['acceptDeadline'] == null) {
        data['acceptDeadline'] = Timestamp.fromDate(now.add(const Duration(minutes: 20)));
      }

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
    if (!isAvailable) return const Stream.empty();
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
    if (!isAvailable) return const Stream.empty();
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
    if (!isAvailable) return const Stream.empty();
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
    if (!isAvailable) return const Stream.empty();
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
    if (!isAvailable) return const Stream.empty();
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

  /// Real-time stream of all in-app orders for a specific shop (newest first).
  /// Strictly isolated by [shopId]. Used by Admin Panel.
  Stream<List<AppOrder>> watchShopOrders(String shopId) {
    if (!isAvailable) return const Stream.empty();
    return _ordersRef
        .where('shopId', isEqualTo: shopId)
        .snapshots()
        .map((snapshot) {
      final orders =
          snapshot.docs.map((doc) => AppOrder.fromFirestore(doc)).toList();
      orders.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return orders;
    });
  }

  // ─── Status Update with Atomic Transaction & ShopStats Hooks ──────────────

  /// Updates the order status to [newStatus] with strict validation and atomic shopStats counter updates.
  Future<void> updateOrderStatus(
    String orderId,
    String newStatus, {
    String? rejectionReason,
    String? deliveryPersonId,
    String? deliveryPersonName,
    DateTime? customNow,
  }) async {
    if (!isAvailable) return;
    try {
      await _firestore.runTransaction((transaction) async {
        final orderDocRef = _ordersRef.doc(orderId);
        final doc = await transaction.get(orderDocRef);

        if (!doc.exists || doc.data() == null) {
          throw OrderNotFoundException(orderId);
        }

        final data = doc.data()!;
        final currentStatus = (data['status'] as String?) ?? 'placed';
        final shopId = (data['shopId'] as String?) ?? '';
        final statsDocRef = _statsRef.doc(shopId);
        final now = customNow ?? DateTime.now();

        // ── Idempotency Check ──
        if (currentStatus == newStatus) {
          return; // No-op on duplicate request
        }

        if (!OrderStatusRules.isValidTransition(currentStatus, newStatus)) {
          throw InvalidOrderTransitionException(
            currentStatus: currentStatus,
            targetStatus: newStatus,
          );
        }

        // ── Transition: PLACED → ACCEPTED ──
        if (currentStatus == OrderStatusRules.statusPlaced &&
            newStatus == OrderStatusRules.statusAccepted) {
          // Check 20-minute acceptance deadline
          final acceptDeadlineRaw = data['acceptDeadline'];
          DateTime? acceptDeadline;
          if (acceptDeadlineRaw is Timestamp) {
            acceptDeadline = acceptDeadlineRaw.toDate();
          } else if (acceptDeadlineRaw is String) {
            acceptDeadline = DateTime.tryParse(acceptDeadlineRaw);
          }

          if (acceptDeadline != null && now.isAfter(acceptDeadline)) {
            // Auto-expired: Transition to rejected and increment notAccepted + appOrders
            transaction.update(orderDocRef, {
              'status': OrderStatusRules.statusRejected,
              'rejectionReason':
                  'Order was automatically rejected because the shopkeeper did not accept it within 20 minutes.',
              'rejectedAt': FieldValue.serverTimestamp(),
              'updatedAt': FieldValue.serverTimestamp(),
            });
            transaction.set(statsDocRef, {
              'shopId': shopId,
              'appOrders': FieldValue.increment(1),
              'notAccepted': FieldValue.increment(1),
              'updatedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
            throw const OrderServiceException(
                'Order acceptance deadline (20 mins) has expired.',);
          }

          final rejectDeadline = now.add(const Duration(minutes: 15));
          final deliveryDeadline = now.add(const Duration(minutes: 90));

          transaction.update(orderDocRef, {
            'status': OrderStatusRules.statusAccepted,
            'acceptedAt': FieldValue.serverTimestamp(),
            'rejectDeadline': Timestamp.fromDate(rejectDeadline),
            'deliveryDeadline': Timestamp.fromDate(deliveryDeadline),
            'updatedAt': FieldValue.serverTimestamp(),
          });

          transaction.set(statsDocRef, {
            'shopId': shopId,
            'appOrders': FieldValue.increment(1),
            'accepted': FieldValue.increment(1),
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }
        // ── Transition: PLACED → REJECTED (Shopkeeper manual reject before accept) ──
        else if (currentStatus == OrderStatusRules.statusPlaced &&
            newStatus == OrderStatusRules.statusRejected) {
          transaction.update(orderDocRef, {
            'status': OrderStatusRules.statusRejected,
            'rejectedAt': FieldValue.serverTimestamp(),
            'rejectionReason': rejectionReason ?? 'Rejected by shopkeeper',
            'updatedAt': FieldValue.serverTimestamp(),
          });

          transaction.set(statsDocRef, {
            'shopId': shopId,
            'appOrders': FieldValue.increment(1),
            'notAccepted': FieldValue.increment(1),
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }
        // ── Transition: ACCEPTED → REJECTED (15-min rejection window) ──
        else if (currentStatus == OrderStatusRules.statusAccepted &&
            newStatus == OrderStatusRules.statusRejected) {
          final rejectDeadlineRaw = data['rejectDeadline'];
          final acceptedAtRaw = data['acceptedAt'];
          DateTime? rejectDeadline;
          if (rejectDeadlineRaw is Timestamp) {
            rejectDeadline = rejectDeadlineRaw.toDate();
          } else if (acceptedAtRaw is Timestamp) {
            rejectDeadline = acceptedAtRaw.toDate().add(const Duration(minutes: 15));
          }

          if (rejectDeadline != null && now.isAfter(rejectDeadline)) {
            throw const OrderServiceException(
              'Rejection window of 15 minutes has expired. Order cannot be rejected.',
            );
          }

          transaction.update(orderDocRef, {
            'status': OrderStatusRules.statusRejected,
            'rejectedAt': FieldValue.serverTimestamp(),
            'rejectionReason': rejectionReason ?? 'Rejected by shopkeeper',
            'updatedAt': FieldValue.serverTimestamp(),
          });

          transaction.set(statsDocRef, {
            'shopId': shopId,
            'rejectedAfterAccept': FieldValue.increment(1),
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }
        // ── Transition: ACCEPTED → DELIVERED ──
        else if (currentStatus == OrderStatusRules.statusAccepted &&
            newStatus == OrderStatusRules.statusDelivered) {
          final deliveryDeadlineRaw = data['deliveryDeadline'];
          final acceptedAtRaw = data['acceptedAt'];
          DateTime? deliveryDeadline;
          if (deliveryDeadlineRaw is Timestamp) {
            deliveryDeadline = deliveryDeadlineRaw.toDate();
          } else if (acceptedAtRaw is Timestamp) {
            deliveryDeadline = acceptedAtRaw.toDate().add(const Duration(minutes: 90));
          }

          if (deliveryDeadline != null && now.isAfter(deliveryDeadline)) {
            // Expired 90-min delivery attempt
            transaction.update(orderDocRef, {
              'status': OrderStatusRules.statusDeliveryExpired,
              'rejectionReason': 'Delivery window of 90 minutes expired.',
              'updatedAt': FieldValue.serverTimestamp(),
            });
            transaction.set(statsDocRef, {
              'shopId': shopId,
              'deliveryExpired': FieldValue.increment(1),
              'updatedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
            throw const OrderServiceException(
              'Delivery window of 90 minutes has expired.',
            );
          }

          final Map<String, dynamic> updates = {
            'status': OrderStatusRules.statusDelivered,
            'deliveredAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          };

          if (deliveryPersonId != null && deliveryPersonId.trim().isNotEmpty) {
            updates['deliveryPersonId'] = deliveryPersonId.trim();
          }
          if (deliveryPersonName != null && deliveryPersonName.trim().isNotEmpty) {
            updates['deliveryPersonName'] = deliveryPersonName.trim();
          }

          transaction.update(orderDocRef, updates);

          transaction.set(statsDocRef, {
            'shopId': shopId,
            'delivered': FieldValue.increment(1),
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }
        // ── Transition: PLACED → CANCELLED (Direct update fallback if called) ──
        else if (currentStatus == OrderStatusRules.statusPlaced &&
            newStatus == OrderStatusRules.statusCancelled) {
          // Rule 1: Delete completely!
          transaction.delete(orderDocRef);
        } else {
          final Map<String, dynamic> updates = {
            'status': newStatus,
            'updatedAt': FieldValue.serverTimestamp(),
          };
          transaction.update(orderDocRef, updates);
        }
      });
    } on OrderServiceException {
      rethrow;
    } catch (e) {
      debugPrint('❌ OrderService updateOrderStatus error: $e');
      throw OrderServiceException('Failed to update order status: $e');
    }
  }

  // ─── Customer Cancellation (Rule 1: Complete Disappearance) ────────────────

  /// Cancels a placed order by completely deleting its Firestore document.
  /// Zero shopStats counters are modified.
  /// Throws [OrderServiceException] if the order is not in 'placed' status.
  Future<void> cancelOrder(String orderId) async {
    if (!isAvailable) return;
    try {
      final docRef = _ordersRef.doc(orderId);
      final doc = await docRef.get();

      if (!doc.exists || doc.data() == null) {
        return; // Already deleted or not found
      }

      final status = (doc.data()!['status'] as String?) ?? 'placed';
      if (status != OrderStatusRules.statusPlaced) {
        throw OrderServiceException(
          'Cannot cancel order in "$status" status. Orders can only be cancelled while in placed status.',
        );
      }

      // Complete disappearance from database
      await docRef.delete();
      debugPrint('✅ OrderService: Placed order #$orderId completely deleted');
    } on OrderServiceException {
      rethrow;
    } catch (e) {
      debugPrint('❌ OrderService cancelOrder error: $e');
      throw OrderServiceException('Failed to cancel order: $e');
    }
  }

  // ─── Timer Expiration Check ────────────────────────────────────────────────

  /// Checks if an active order has exceeded its 20-min accept deadline or 90-min delivery deadline.
  /// If expired, executes the atomic expiration transition.
  Future<bool> checkAndExpireOrder(String orderId, {DateTime? customNow}) async {
    if (!isAvailable) return false;
    try {
      final doc = await _ordersRef.doc(orderId).get();
      if (!doc.exists || doc.data() == null) return false;

      final data = doc.data()!;
      final status = (data['status'] as String?) ?? '';
      final now = customNow ?? DateTime.now();

      if (status == OrderStatusRules.statusPlaced) {
        final acceptDeadlineRaw = data['acceptDeadline'];
        DateTime? acceptDeadline;
        if (acceptDeadlineRaw is Timestamp) {
          acceptDeadline = acceptDeadlineRaw.toDate();
        } else if (acceptDeadlineRaw is String) {
          acceptDeadline = DateTime.tryParse(acceptDeadlineRaw);
        }

        if (acceptDeadline != null && now.isAfter(acceptDeadline)) {
          await updateOrderStatus(
            orderId,
            OrderStatusRules.statusRejected,
            rejectionReason:
                'Order was automatically rejected because the shopkeeper did not accept it within 20 minutes.',
            customNow: now,
          );
          return true;
        }
      } else if (status == OrderStatusRules.statusAccepted) {
        final deliveryDeadlineRaw = data['deliveryDeadline'];
        final acceptedAtRaw = data['acceptedAt'];
        DateTime? deliveryDeadline;
        if (deliveryDeadlineRaw is Timestamp) {
          deliveryDeadline = deliveryDeadlineRaw.toDate();
        } else if (acceptedAtRaw is Timestamp) {
          deliveryDeadline = acceptedAtRaw.toDate().add(const Duration(minutes: 90));
        }

        if (deliveryDeadline != null && now.isAfter(deliveryDeadline)) {
          final shopId = (data['shopId'] as String?) ?? '';
          await _firestore.runTransaction((transaction) async {
            transaction.update(_ordersRef.doc(orderId), {
              'status': OrderStatusRules.statusDeliveryExpired,
              'rejectionReason': 'Delivery window of 90 minutes expired.',
              'updatedAt': FieldValue.serverTimestamp(),
            });
            transaction.set(_statsRef.doc(shopId), {
              'shopId': shopId,
              'deliveryExpired': FieldValue.increment(1),
              'updatedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
          });
          return true;
        }
      }

      return false;
    } catch (e) {
      debugPrint('❌ OrderService checkAndExpireOrder error: $e');
      return false;
    }
  }
}
