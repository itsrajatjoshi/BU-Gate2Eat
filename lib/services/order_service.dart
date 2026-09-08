// BU Gate2Eat — Services
// Firestore Order Service & Repository Layer (Phase 3 — Part 3.1)
// Handles order creation, retrieval, real-time streams, status transitions, and lifecycle validation.

import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../core/auth/auth_status.dart';
import '../core/utils/order_timer_helper.dart';
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
  OrderService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    String? Function()? currentUserIdResolver,
    String? Function()? currentShopIdResolver,
    AuthRole Function()? currentUserRoleResolver,
    Future<Map<String, dynamic>?> Function(String orderId)? orderLoaderForTesting,
    Future<void> Function(String orderId, Map<String, dynamic> updates)? orderUpdaterForTesting,
    Future<Map<String, dynamic>> Function(Map<String, dynamic> payload)? orderCreatorForTesting,
  })  : _customFirestore = firestore,
        _customAuth = auth,
        _customUserIdResolver = currentUserIdResolver,
        _customShopIdResolver = currentShopIdResolver,
        _customUserRoleResolver = currentUserRoleResolver,
        _orderLoaderForTesting = orderLoaderForTesting,
        _orderUpdaterForTesting = orderUpdaterForTesting,
        _orderCreatorForTesting = orderCreatorForTesting;

  final FirebaseFirestore? _customFirestore;
  final FirebaseAuth? _customAuth;
  final String? Function()? _customUserIdResolver;
  final String? Function()? _customShopIdResolver;
  final AuthRole Function()? _customUserRoleResolver;
  final Future<Map<String, dynamic>?> Function(String orderId)? _orderLoaderForTesting;
  final Future<void> Function(String orderId, Map<String, dynamic> updates)? _orderUpdaterForTesting;
  final Future<Map<String, dynamic>> Function(Map<String, dynamic> payload)? _orderCreatorForTesting;

  /// Resolves the authoritative authenticated Firebase Auth UID.
  String? get _currentAuthUid {
    if (_customUserIdResolver != null) {
      return _customUserIdResolver!();
    }
    try {
      if (_customAuth != null) {
        return _customAuth!.currentUser?.uid;
      }
      if (Firebase.apps.isNotEmpty) {
        return FirebaseAuth.instance.currentUser?.uid;
      }
    } catch (_) {}
    return null;
  }

  /// Resolves the authoritative authenticated role.
  AuthRole get _currentAuthRole {
    if (_customUserRoleResolver != null) {
      return _customUserRoleResolver!();
    }
    if (_currentAuthUid == null) {
      return AuthRole.none;
    }
    return AuthRole.customer;
  }

  /// Resolves the authoritative authenticated shopId.
  String? get _currentAuthShopId {
    if (_customShopIdResolver != null) {
      return _customShopIdResolver!();
    }
    return null;
  }

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

  /// Creates a new order document via the server-authoritative creation path.
  /// Validates customer identity against authenticated session.
  static final Random _secureRandom = Random.secure();

  /// Generates a cryptographically random, collision-resistant idempotency key
  /// conforming strictly to the server format: 8-128 chars of [a-zA-Z0-9_-].
  /// Combines millisecond timestamp with 128 bits of CSPRNG entropy.
  static String generateSecureIdempotencyKey() {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final bytes = List<int>.generate(16, (_) => _secureRandom.nextInt(256));
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return 'idem_${nowMs}_$hex';
  }

  /// Creates a new order document via the server-authoritative creation path.
  /// Validates customer identity against authenticated session.
  /// When testing delegate is supplied, delegates directly.
  /// Sets [acceptDeadline] to createdAt + 20 minutes.
  /// NOTE: Does NOT increment any shopStats counter yet — pre-accept cancel deletes the order completely.
  Future<void> createOrder(
    AppOrder order, {
    DateTime? customNow,
    String? idempotencyKey,
  }) async {
    try {
      final authUid = _currentAuthUid;
      if (authUid != null && authUid.isNotEmpty) {
        if (order.customerId.isNotEmpty && order.customerId != authUid) {
          throw OrderServiceException(
            'Unauthorized: Cannot create order with customerId "${order.customerId}" as authenticated user "$authUid".',
          );
        }
      }

      final now = customNow ?? DateTime.now();
      final key = (idempotencyKey != null && idempotencyKey.trim().isNotEmpty)
          ? idempotencyKey.trim()
          : generateSecureIdempotencyKey();

      // 1. If testing delegate is provided, execute it directly (Server-Authoritative)
      // Client does NOT provide orderId — order identity is generated authoritatively by the backend.
      if (_orderCreatorForTesting != null) {
        final payload = {
          'idempotencyKey': key,
          'shopId': order.shopId,
          'customerId': authUid ?? order.customerId,
          'customerName': order.customerName,
          'customerPhone': order.customerPhone,
          'items': order.items.map((i) => i.toMap()).toList(),
          'specialInstructions': order.specialInstructions,
          'deliveryNote': order.deliveryNote,
          'orderMethod': order.orderMethod,
        };
        await _orderCreatorForTesting!(payload);
        return;
      }

      final docRef = _ordersRef.doc(order.orderId);
      final data = order.toFirestore();

      // Use server timestamp for precision on creation
      data['createdAt'] = FieldValue.serverTimestamp();
      data['updatedAt'] = FieldValue.serverTimestamp();

      if (!data.containsKey('acceptDeadline') || data['acceptDeadline'] == null) {
        data['acceptDeadline'] = Timestamp.fromDate(now.add(const Duration(minutes: 20)));
      }

      await _firestore.runTransaction((transaction) async {
        final existing = await transaction.get(docRef);
        if (existing.exists) {
          return; // Idempotent duplicate protection
        }
        transaction.set(docRef, data);
      }).timeout(const Duration(seconds: 15));
    } catch (e) {
      if (e is OrderServiceException) rethrow;
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
      final order = AppOrder.fromFirestore(doc);
      if ((order.isPlaced && OrderTimerHelper.isAcceptExpired(order)) ||
          (order.isAccepted && OrderTimerHelper.isDeliveryExpired(order))) {
        checkAndExpireOrder(order.orderId);
      }
      return order;
    });
  }

  // ─── Customer Streams ──────────────────────────────────────────────────────

  /// Real-time stream of the authenticated customer's own active orders (placed, accepted).
  /// Excludes expired orders immediately from active output and triggers atomic background expiry.
  /// Derives customer identity directly from authenticated Firebase Auth session.
  Stream<List<AppOrder>> watchMyActiveOrders() {
    final authUid = _currentAuthUid;
    if (authUid == null || authUid.isEmpty) {
      return const Stream.empty();
    }
    return watchCustomerActiveOrders(customerId: authUid);
  }

  /// Real-time stream of the authenticated customer's completed/terminal order history.
  /// Derives customer identity directly from authenticated Firebase Auth session.
  Stream<List<AppOrder>> watchMyOrderHistory() {
    final authUid = _currentAuthUid;
    if (authUid == null || authUid.isEmpty) {
      return const Stream.empty();
    }
    return watchCustomerOrderHistory(customerId: authUid);
  }

  /// Real-time stream of a customer's active orders (placed, accepted).
  /// Excludes expired orders immediately from active output and triggers atomic background expiry.
  Stream<List<AppOrder>> watchCustomerActiveOrders({
    String? customerId,
    String? customerPhone,
  }) {
    final authUid = _currentAuthUid;

    // Security Invariant: If caller is authenticated, enforce that query targets authenticated UID
    if (authUid != null && authUid.isNotEmpty) {
      if (customerId != null && customerId.isNotEmpty && customerId != authUid) {
        debugPrint(
          '⛔ [OrderService] Blocked unauthorized active orders query: Caller "$authUid" cannot access orders of "$customerId".',
        );
        return const Stream.empty();
      }
    }

    if (!isAvailable) return const Stream.empty();
    Query<Map<String, dynamic>> query = _ordersRef;

    if (customerId != null && customerId.isNotEmpty) {
      query = query.where('customerId', isEqualTo: customerId);
    } else if (customerPhone != null && customerPhone.isNotEmpty) {
      query = query.where('customerPhone', isEqualTo: customerPhone);
    } else {
      return const Stream.empty();
    }

    return query
        .where('status', whereIn: OrderStatusRules.activeStatuses.toList())
        .snapshots()
        .map((snapshot) {
      final now = DateTime.now();
      final activeList = <AppOrder>[];
      for (final doc in snapshot.docs) {
        final order = AppOrder.fromFirestore(doc);
        if (order.isPlaced && OrderTimerHelper.isAcceptExpired(order, now)) {
          checkAndExpireOrder(order.orderId, customNow: now);
          continue;
        }
        if (order.isAccepted && OrderTimerHelper.isDeliveryExpired(order, now)) {
          checkAndExpireOrder(order.orderId, customNow: now);
          continue;
        }
        activeList.add(order);
      }
      activeList.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return activeList;
    });
  }

  /// Real-time stream of a customer's completed/terminal order history.
  Stream<List<AppOrder>> watchCustomerOrderHistory({
    String? customerId,
    String? customerPhone,
  }) {
    final authUid = _currentAuthUid;

    // Security Invariant: If caller is authenticated, enforce that query targets authenticated UID
    if (authUid != null && authUid.isNotEmpty) {
      if (customerId != null && customerId.isNotEmpty && customerId != authUid) {
        debugPrint(
          '⛔ [OrderService] Blocked unauthorized order history query: Caller "$authUid" cannot access orders of "$customerId".',
        );
        return const Stream.empty();
      }
    }

    if (!isAvailable) return const Stream.empty();
    Query<Map<String, dynamic>> query = _ordersRef;

    if (customerId != null && customerId.isNotEmpty) {
      query = query.where('customerId', isEqualTo: customerId);
    } else if (customerPhone != null && customerPhone.isNotEmpty) {
      query = query.where('customerPhone', isEqualTo: customerPhone);
    } else {
      return const Stream.empty();
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

  /// Real-time stream of the authenticated shopkeeper's active orders (placed, accepted).
  Stream<List<AppOrder>> watchMyShopActiveOrders() {
    final role = _currentAuthRole;
    final trustedShopId = _currentAuthShopId;
    if (role != AuthRole.shopkeeper || trustedShopId == null || trustedShopId.isEmpty) {
      return const Stream.empty();
    }
    return watchShopActiveOrders(trustedShopId);
  }

  /// Real-time stream of the authenticated shopkeeper's order history (delivered, rejected, cancelled).
  Stream<List<AppOrder>> watchMyShopOrderHistory() {
    final role = _currentAuthRole;
    final trustedShopId = _currentAuthShopId;
    if (role != AuthRole.shopkeeper || trustedShopId == null || trustedShopId.isEmpty) {
      return const Stream.empty();
    }
    return watchShopOrderHistory(trustedShopId);
  }

  /// Real-time stream of all in-app orders for the authenticated shopkeeper's assigned shop.
  Stream<List<AppOrder>> watchMyShopOrders() {
    final role = _currentAuthRole;
    final trustedShopId = _currentAuthShopId;
    if (role != AuthRole.shopkeeper || trustedShopId == null || trustedShopId.isEmpty) {
      return const Stream.empty();
    }
    return watchShopOrders(trustedShopId);
  }

  /// Real-time stream of a shop's active orders (placed, accepted).
  /// Excludes expired orders immediately from active output and triggers atomic background expiry.
  Stream<List<AppOrder>> watchShopActiveOrders(String shopId) {
    // ── Security Check: Tenant Authorization ──
    final role = _currentAuthRole;
    final trustedShopId = _currentAuthShopId;
    if (role != AuthRole.admin && role != AuthRole.shopkeeper) {
      debugPrint('🚫 [SECURITY] Blocked unauthorized access to shop active orders for shopId: $shopId');
      return const Stream.empty();
    }
    if (role == AuthRole.shopkeeper) {
      if (trustedShopId == null || trustedShopId.isEmpty || trustedShopId != shopId) {
        debugPrint('🚫 [SECURITY] Blocked unauthorized shop active orders for shopId: $shopId by shopkeeper of: $trustedShopId');
        return const Stream.empty();
      }
    }

    if (!isAvailable) return const Stream.empty();
    return _ordersRef
        .where('shopId', isEqualTo: shopId)
        .where('status', whereIn: OrderStatusRules.activeStatuses.toList())
        .snapshots()
        .map((snapshot) {
      final now = DateTime.now();
      final activeList = <AppOrder>[];
      for (final doc in snapshot.docs) {
        final order = AppOrder.fromFirestore(doc);
        if (order.isPlaced && OrderTimerHelper.isAcceptExpired(order, now)) {
          checkAndExpireOrder(order.orderId, customNow: now);
          continue;
        }
        if (order.isAccepted && OrderTimerHelper.isDeliveryExpired(order, now)) {
          checkAndExpireOrder(order.orderId, customNow: now);
          continue;
        }
        activeList.add(order);
      }
      activeList.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return activeList;
    });
  }

  /// Real-time stream of a shop's order history (delivered, rejected, cancelled).
  Stream<List<AppOrder>> watchShopOrderHistory(String shopId) {
    // ── Security Check: Tenant Authorization ──
    final role = _currentAuthRole;
    final trustedShopId = _currentAuthShopId;
    if (role != AuthRole.admin && role != AuthRole.shopkeeper) {
      debugPrint('🚫 [SECURITY] Blocked unauthorized access to shop order history for shopId: $shopId');
      return const Stream.empty();
    }
    if (role == AuthRole.shopkeeper) {
      if (trustedShopId == null || trustedShopId.isEmpty || trustedShopId != shopId) {
        debugPrint('🚫 [SECURITY] Blocked unauthorized shop order history for shopId: $shopId by shopkeeper of: $trustedShopId');
        return const Stream.empty();
      }
    }

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
    // ── Security Check: Tenant Authorization ──
    final role = _currentAuthRole;
    final trustedShopId = _currentAuthShopId;
    if (role != AuthRole.admin && role != AuthRole.shopkeeper) {
      debugPrint('🚫 [SECURITY] Blocked unauthorized access to shop orders for shopId: $shopId');
      return const Stream.empty();
    }
    if (role == AuthRole.shopkeeper) {
      if (trustedShopId == null || trustedShopId.isEmpty || trustedShopId != shopId) {
        debugPrint('🚫 [SECURITY] Blocked unauthorized shop orders for shopId: $shopId by shopkeeper of: $trustedShopId');
        return const Stream.empty();
      }
    }

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
    // Check testing loader hook if set
    if (_orderLoaderForTesting != null) {
      final data = await _orderLoaderForTesting!(orderId);
      if (data == null) {
        throw OrderNotFoundException(orderId);
      }
      final orderShopId = data['shopId'] as String? ?? '';
      final role = _currentAuthRole;
      final trustedShopId = _currentAuthShopId;
      if (role != AuthRole.admin && role != AuthRole.shopkeeper) {
        throw const OrderServiceException(
          'Unauthorized: Caller cannot update shop order status',
        );
      }
      if (role == AuthRole.shopkeeper) {
        if (trustedShopId == null || trustedShopId.isEmpty || trustedShopId != orderShopId) {
          throw OrderServiceException(
            'Unauthorized: Shopkeeper of "$trustedShopId" cannot update order for shop "$orderShopId"',
          );
        }
      }
      if (_orderUpdaterForTesting != null) {
        await _orderUpdaterForTesting!(orderId, {
          'status': newStatus,
          if (rejectionReason != null) 'rejectionReason': rejectionReason,
        });
        return;
      }
    }

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

        // ── Security Check: Tenant Authorization ──
        final role = _currentAuthRole;
        final trustedShopId = _currentAuthShopId;
        if (role != AuthRole.admin && role != AuthRole.shopkeeper) {
          throw const OrderServiceException(
            'Unauthorized: Caller cannot update shop order status',
          );
        }
        if (role == AuthRole.shopkeeper) {
          if (trustedShopId == null || trustedShopId.isEmpty || trustedShopId != shopId) {
            throw OrderServiceException(
              'Unauthorized: Shopkeeper of "$trustedShopId" cannot update order for shop "$shopId"',
            );
          }
        }

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
            transaction.set(
              statsDocRef,
              {
                'shopId': shopId,
                'appOrders': FieldValue.increment(1),
                'notAccepted': FieldValue.increment(1),
                'updatedAt': FieldValue.serverTimestamp(),
              },
              SetOptions(merge: true),
            );
            throw const OrderServiceException(
              'Order acceptance deadline (20 mins) has expired.',
            );
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

          transaction.set(
            statsDocRef,
            {
              'shopId': shopId,
              'appOrders': FieldValue.increment(1),
              'accepted': FieldValue.increment(1),
              'updatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
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

          transaction.set(
            statsDocRef,
            {
              'shopId': shopId,
              'appOrders': FieldValue.increment(1),
              'notAccepted': FieldValue.increment(1),
              'updatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
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

          transaction.set(
            statsDocRef,
            {
              'shopId': shopId,
              'rejectedAfterAccept': FieldValue.increment(1),
              'updatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
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
            transaction.set(
              statsDocRef,
              {
                'shopId': shopId,
                'deliveryExpired': FieldValue.increment(1),
                'updatedAt': FieldValue.serverTimestamp(),
              },
              SetOptions(merge: true),
            );
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

          transaction.set(
            statsDocRef,
            {
              'shopId': shopId,
              'delivered': FieldValue.increment(1),
              'updatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
        }
        // ── Transition: PLACED → CANCELLED (Customer cancellation before accept) ──
        else if (currentStatus == OrderStatusRules.statusPlaced &&
            newStatus == OrderStatusRules.statusCancelled) {
          transaction.update(orderDocRef, {
            'status': OrderStatusRules.statusCancelled,
            'cancelledAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
          // Zero shopStats counters are modified
        } else {
          final Map<String, dynamic> updates = {
            'status': newStatus,
            'updatedAt': FieldValue.serverTimestamp(),
          };
          transaction.update(orderDocRef, updates);
        }
      }).timeout(const Duration(seconds: 15));
    } on OrderServiceException {
      rethrow;
    } catch (e) {
      debugPrint('❌ OrderService updateOrderStatus error: $e');
      throw OrderServiceException('Failed to update order status: $e');
    }
  }

  // ─── Customer Cancellation (Strictly before shopkeeper acceptance) ──────────

  /// Cancels a placed order before shopkeeper acceptance.
  /// Transitions order status to 'cancelled' with server timestamp.
  /// Zero shopStats counters are modified.
  /// Throws [OrderServiceException] if the order is not in 'placed' status.
  Future<void> cancelOrder(String orderId) async {
    // 1. Security Invariant: Order cancellation requires an authenticated session
    final authUid = _currentAuthUid;
    if (authUid == null || authUid.isEmpty) {
      throw const OrderServiceException(
        'Unauthorized: Order cancellation requires an authenticated customer session.',
      );
    }

    if (_orderLoaderForTesting != null) {
      final data = await _orderLoaderForTesting!(orderId);
      if (data == null) return;
      final orderCustomerId = (data['customerId'] as String?) ?? '';
      if (orderCustomerId.isNotEmpty && orderCustomerId != authUid) {
        throw OrderServiceException(
          'Unauthorized: Customer "$authUid" cannot cancel order owned by "$orderCustomerId".',
        );
      }
      final status = (data['status'] as String?) ?? 'placed';
      if (status != OrderStatusRules.statusPlaced) {
        throw OrderServiceException(
          'Cannot cancel order in "$status" status. Orders can only be cancelled while in placed status.',
        );
      }
      if (_orderUpdaterForTesting != null) {
        await _orderUpdaterForTesting!(orderId, {
          'status': OrderStatusRules.statusCancelled,
        });
      }
      return;
    }

    if (!isAvailable) return;

    try {
      final docRef = _ordersRef.doc(orderId);
      await _firestore.runTransaction((transaction) async {
        final doc = await transaction.get(docRef);

        if (!doc.exists || doc.data() == null) {
          return; // Already deleted or not found
        }

        final data = doc.data()!;

        // 2. Security Invariant: Verify order.customerId == authenticated UID
        final orderCustomerId = (data['customerId'] as String?) ?? '';
        if (orderCustomerId.isNotEmpty && orderCustomerId != authUid) {
          throw OrderServiceException(
            'Unauthorized: Customer "$authUid" cannot cancel order owned by "$orderCustomerId".',
          );
        }

        final status = (data['status'] as String?) ?? 'placed';
        if (status != OrderStatusRules.statusPlaced) {
          throw OrderServiceException(
            'Cannot cancel order in "$status" status. Orders can only be cancelled while in placed status.',
          );
        }

        // Transition status to cancelled with timestamp; preserve document for history
        transaction.update(docRef, {
          'status': OrderStatusRules.statusCancelled,
          'cancelledAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }).timeout(const Duration(seconds: 15));
      if (kDebugMode) {
        debugPrint('✅ OrderService: Placed order #$orderId cancelled successfully');
      }
    } on OrderServiceException {
      rethrow;
    } catch (e) {
      debugPrint('❌ OrderService cancelOrder error: $e');
      throw OrderServiceException('Failed to cancel order: $e');
    }
  }

  // ─── Timer Expiration Check ────────────────────────────────────────────────

  /// Checks if an active order has exceeded its 20-min accept deadline or 90-min delivery deadline.
  /// If expired, executes the atomic expiration transition and shopStats counter increments.
  Future<bool> checkAndExpireOrder(String orderId, {DateTime? customNow}) async {
    if (!isAvailable) return false;
    try {
      final now = customNow ?? DateTime.now();
      return await _firestore.runTransaction<bool>((transaction) async {
        final orderDocRef = _ordersRef.doc(orderId);
        final doc = await transaction.get(orderDocRef);
        if (!doc.exists || doc.data() == null) return false;

        final data = doc.data()!;
        final status = (data['status'] as String?) ?? '';
        final shopId = (data['shopId'] as String?) ?? '';
        final statsDocRef = _statsRef.doc(shopId);

        if (status == OrderStatusRules.statusPlaced) {
          final acceptDeadlineRaw = data['acceptDeadline'];
          final createdAtRaw = data['createdAt'];
          DateTime? acceptDeadline;
          if (acceptDeadlineRaw is Timestamp) {
            acceptDeadline = acceptDeadlineRaw.toDate();
          } else if (acceptDeadlineRaw is String) {
            acceptDeadline = DateTime.tryParse(acceptDeadlineRaw);
          } else if (createdAtRaw is Timestamp) {
            acceptDeadline = createdAtRaw.toDate().add(const Duration(minutes: OrderTimerHelper.acceptWindowMinutes));
          }

          if (acceptDeadline != null && !now.isBefore(acceptDeadline)) {
            transaction.update(orderDocRef, {
              'status': OrderStatusRules.statusRejected,
              'rejectionReason':
                  'Order was automatically rejected because the shopkeeper did not accept it within 20 minutes.',
              'rejectedAt': FieldValue.serverTimestamp(),
              'updatedAt': FieldValue.serverTimestamp(),
            });
            transaction.set(
              statsDocRef,
              {
                'shopId': shopId,
                'appOrders': FieldValue.increment(1),
                'notAccepted': FieldValue.increment(1),
                'updatedAt': FieldValue.serverTimestamp(),
              },
              SetOptions(merge: true),
            );
            if (kDebugMode) {
              debugPrint('⏱️ OrderService.checkAndExpireOrder: Order #$orderId auto-expired (placed 20m timeout)');
            }
            return true;
          }
        } else if (status == OrderStatusRules.statusAccepted) {
          final deliveryDeadlineRaw = data['deliveryDeadline'];
          final acceptedAtRaw = data['acceptedAt'];
          DateTime? deliveryDeadline;
          if (deliveryDeadlineRaw is Timestamp) {
            deliveryDeadline = deliveryDeadlineRaw.toDate();
          } else if (deliveryDeadlineRaw is String) {
            deliveryDeadline = DateTime.tryParse(deliveryDeadlineRaw);
          } else if (acceptedAtRaw is Timestamp) {
            deliveryDeadline = acceptedAtRaw.toDate().add(const Duration(minutes: OrderTimerHelper.deliveryWindowMinutes));
          }

          if (deliveryDeadline != null && !now.isBefore(deliveryDeadline)) {
            transaction.update(orderDocRef, {
              'status': OrderStatusRules.statusDeliveryExpired,
              'rejectionReason': 'Delivery window of 90 minutes expired.',
              'updatedAt': FieldValue.serverTimestamp(),
            });
            transaction.set(
              statsDocRef,
              {
                'shopId': shopId,
                'deliveryExpired': FieldValue.increment(1),
                'updatedAt': FieldValue.serverTimestamp(),
              },
              SetOptions(merge: true),
            );
            if (kDebugMode) {
              debugPrint('⏱️ OrderService.checkAndExpireOrder: Order #$orderId auto-expired (delivery 90m timeout)');
            }
            return true;
          }
        }

        return false;
      });
    } catch (e) {
      debugPrint('❌ OrderService checkAndExpireOrder error: $e');
      return false;
    }
  }
}
