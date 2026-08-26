// BU Gate2Eat — Services
// Shop Statistics Service for Admin Order Statistics
// Handles Firestore `shopStats/{shopId}` CRUD, atomic counter increments, and reset.
// Every operation is strictly shop-wise — no global/cross-shop mutations.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../models/shop_stats_model.dart';

/// Service class for Firestore `shopStats` collection operations.
///
/// All counter operations use [FieldValue.increment] for atomic safety.
/// Every method requires an explicit [shopId] — no implicit global state.
class ShopStatsService {
  ShopStatsService({FirebaseFirestore? firestore}) : _customFirestore = firestore;

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

  static const String collectionName = 'shopStats';

  CollectionReference<Map<String, dynamic>> get _statsRef =>
      _firestore.collection(collectionName);

  // ─── Initialize ─────────────────────────────────────────────────────────────

  /// Creates a shopStats document with all counters at 0 if it doesn't exist.
  /// If it already exists, does nothing (no overwrite).
  Future<void> initializeShopStats({
    required String shopId,
    required String shopName,
  }) async {
    if (!isAvailable) return;
    try {
      final docRef = _statsRef.doc(shopId);
      final doc = await docRef.get();
      if (!doc.exists) {
        final stats = ShopStats.zero(shopId: shopId, shopName: shopName);
        await docRef.set(stats.toFirestore());
        debugPrint('✅ ShopStatsService: Initialized stats for $shopId');
      }
    } catch (e) {
      debugPrint('❌ ShopStatsService initializeShopStats error: $e');
    }
  }

  // ─── Read ───────────────────────────────────────────────────────────────────

  /// Returns a real-time stream of a single shop's stats.
  Stream<ShopStats?> watchShopStats(String shopId) {
    if (!isAvailable) return const Stream.empty();
    return _statsRef.doc(shopId).snapshots().map((doc) {
      if (!doc.exists || doc.data() == null) return null;
      return ShopStats.fromFirestore(doc);
    });
  }

  /// Returns a real-time stream of all shops' stats.
  Stream<List<ShopStats>> watchAllShopStats() {
    if (!isAvailable) return const Stream.empty();
    return _statsRef.snapshots().map((snapshot) {
      return snapshot.docs
          .map((doc) => ShopStats.fromFirestore(doc))
          .toList()
        ..sort((a, b) => a.shopName.compareTo(b.shopName));
    });
  }

  /// Fetches a single shop's stats document (one-shot).
  Future<ShopStats?> getShopStats(String shopId) async {
    if (!isAvailable) return null;
    try {
      final doc = await _statsRef.doc(shopId).get();
      if (!doc.exists || doc.data() == null) return null;
      return ShopStats.fromFirestore(doc);
    } catch (e) {
      debugPrint('❌ ShopStatsService getShopStats error: $e');
      return null;
    }
  }

  // ─── Atomic Counter Increments ──────────────────────────────────────────────
  //
  // Each method updates ONLY the specified shop's document.
  // Uses FieldValue.increment(1) for atomic, concurrent-safe updates.

  /// Increments `appOrders` when a new in-app order is successfully created.
  /// Called only after Firestore `orders/{orderId}` is confirmed created.
  Future<void> incrementAppOrders(String shopId) async {
    await _incrementField(shopId, 'appOrders');
  }

  /// Increments `accepted` when shopkeeper presses "Accept Order".
  Future<void> incrementAccepted(String shopId) async {
    await _incrementField(shopId, 'accepted');
  }

  /// Increments `delivered` when order is marked as delivered.
  Future<void> incrementDelivered(String shopId) async {
    await _incrementField(shopId, 'delivered');
  }

  /// Increments `notAccepted` when:
  /// - Shopkeeper rejects a `placed` order, OR
  /// - 20-minute accept timer expires.
  Future<void> incrementNotAccepted(String shopId) async {
    await _incrementField(shopId, 'notAccepted');
  }

  /// Increments `rejectedAfterAccept` when shopkeeper rejects an `accepted`
  /// order within the 15-minute rejection window.
  Future<void> incrementRejectedAfterAccept(String shopId) async {
    await _incrementField(shopId, 'rejectedAfterAccept');
  }

  /// Increments `deliveryExpired` when an accepted order is not delivered
  /// within the 90-minute delivery window.
  Future<void> incrementDeliveryExpired(String shopId) async {
    await _incrementField(shopId, 'deliveryExpired');
  }

  /// Increments `whatsappOrders` (statement counter) and `lifetimeWhatsappOrders`
  /// when WhatsApp order button is successfully clicked for this shop.
  /// No order document is created.
  Future<void> incrementWhatsappOrders(
    String shopId, {
    DateTime? orderTime,
  }) async {
    if (!isAvailable) return;
    final time = orderTime ?? DateTime.now();
    final monthKey = DateFormat('yyyy-MM').format(time);

    try {
      // 1. Atomically increment statement counter, lifetime counter, and month map on shopStats/{shopId}
      await _statsRef.doc(shopId).set(
        {
          'shopId': shopId,
          'whatsappOrders': FieldValue.increment(1),
          'lifetimeWhatsappOrders': FieldValue.increment(1),
          'monthlyWhatsappOrders': {
            monthKey: FieldValue.increment(1),
          },
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      // 2. Also record in subcollection shopStats/{shopId}/monthlyStats/{monthKey} for future analytics
      await _statsRef
          .doc(shopId)
          .collection('monthlyStats')
          .doc(monthKey)
          .set(
        {
          'shopId': shopId,
          'monthKey': monthKey,
          'whatsappOrders': FieldValue.increment(1),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      debugPrint(
        '✅ ShopStatsService: Atomically incremented WhatsApp orders (+1 statement, +1 lifetime) for shop $shopId',
      );
    } catch (e) {
      debugPrint('❌ ShopStatsService incrementWhatsappOrders error for $shopId: $e');
      rethrow;
    }
  }

  /// Fetches the current statement WhatsApp order count for a specific shop.
  /// Returns the WhatsApp orders since lastResetAt.
  Future<int> getStatementWhatsappOrders(String shopId) async {
    if (!isAvailable) return 0;

    try {
      final parentDoc = await _statsRef.doc(shopId).get();
      if (parentDoc.exists && parentDoc.data() != null) {
        final stats = ShopStats.fromFirestore(parentDoc);
        return stats.whatsappOrders;
      }
    } catch (e) {
      debugPrint('⚠️ ShopStatsService getStatementWhatsappOrders error: $e');
    }
    return 0;
  }

  /// Fetches the monthly WhatsApp order count for a specific shop and month (legacy/bridge support).
  Future<int> getMonthlyWhatsappOrders(String shopId, DateTime month) async {
    if (!isAvailable) return 0;

    try {
      final parentDoc = await _statsRef.doc(shopId).get();
      if (parentDoc.exists && parentDoc.data() != null) {
        final stats = ShopStats.fromFirestore(parentDoc);
        return stats.getWhatsappOrdersForMonth(month);
      }
    } catch (e) {
      debugPrint('⚠️ ShopStatsService getMonthlyWhatsappOrders error: $e');
    }
    return 0;
  }

  /// Internal helper: atomically increments a single numeric field.
  /// Uses `.set(..., SetOptions(merge: true))` so that if the document does not
  /// exist yet, it is created with the field set to 1, and if it exists, the field
  /// is atomically incremented by 1 without overwriting any other counters.
  Future<void> _incrementField(String shopId, String field) async {
    if (!isAvailable) return;
    try {
      await _statsRef.doc(shopId).set(
        {
          'shopId': shopId,
          field: FieldValue.increment(1),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      debugPrint('✅ ShopStatsService: Atomically incremented $field (+1) for shop $shopId');
    } catch (e) {
      debugPrint('❌ ShopStatsService _incrementField error ($field) for $shopId: $e');
      rethrow;
    }
  }

  // ─── Reset ──────────────────────────────────────────────────────────────────

  /// Resets all current statement counters to 0 for a specific shop.
  /// Also sets `lastResetAt` to server timestamp.
  ///
  /// CRITICAL INVARIANT:
  /// `lifetimeWhatsappOrders` is NEVER wiped on reset! It preserves cumulative metrics.
  /// Only statement counters (`whatsappOrders`, `appOrders`, etc.) reset to 0.
  Future<void> resetShopStats(String shopId) async {
    if (!isAvailable) return;
    try {
      await _statsRef.doc(shopId).set(
        {
          'shopId': shopId,
          'appOrders': 0,
          'accepted': 0,
          'delivered': 0,
          'notAccepted': 0,
          'rejectedAfterAccept': 0,
          'deliveryExpired': 0,
          'whatsappOrders': 0,
          'lastResetAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      debugPrint('✅ ShopStatsService: Reset statement stats for $shopId (lifetime WA preserved)');
    } catch (e) {
      debugPrint('❌ ShopStatsService resetShopStats error: $e');
      rethrow;
    }
  }

  /// Deletes ONLY TERMINAL (historical) order documents belonging to a specific shop.
  /// Terminal statuses: 'delivered', 'rejected', 'delivery_expired', 'cancelled'.
  ///
  /// CRITICAL SAFETY RULE:
  /// ACTIVE orders ('placed', 'accepted') MUST NEVER BE DELETED or touched during reset!
  /// Live customer & shopkeeper orders, active timers, and pending food preparation
  /// must continue completely unharmed.
  ///
  /// Uses single-field shopId query to guarantee immediate execution without requiring
  /// composite Firestore indexes.
  Future<int> deleteTerminalShopOrders(String shopId) async {
    if (!isAvailable) return 0;
    int totalDeleted = 0;
    try {
      final snapshot = await _firestore
          .collection('orders')
          .where('shopId', isEqualTo: shopId)
          .get();

      if (snapshot.docs.isEmpty) return 0;

      // Filter only terminal orders (never placed or accepted)
      final terminalDocs = snapshot.docs.where((doc) {
        final status =
            ((doc.data()['status'] as String?) ?? '').trim().toLowerCase();
        return status != 'placed' && status != 'accepted';
      }).toList();

      if (terminalDocs.isEmpty) return 0;

      // Commit in chunks of 400 (Firestore maximum batch size is 500)
      const chunkSize = 400;
      for (int i = 0; i < terminalDocs.length; i += chunkSize) {
        final end = (i + chunkSize < terminalDocs.length)
            ? i + chunkSize
            : terminalDocs.length;
        final chunk = terminalDocs.sublist(i, end);

        final batch = _firestore.batch();
        for (final doc in chunk) {
          batch.delete(doc.reference);
        }
        await batch.commit();
        totalDeleted += chunk.length;
      }

      debugPrint(
        '✅ ShopStatsService: Deleted $totalDeleted terminal orders for $shopId from Firestore (Active placed/accepted orders preserved)',
      );
      return totalDeleted;
    } catch (e) {
      debugPrint('❌ ShopStatsService deleteTerminalShopOrders error: $e');
      rethrow;
    }
  }

  /// Deprecated alias kept for backwards compatibility; delegates to [deleteTerminalShopOrders].
  Future<int> deleteShopOrders(String shopId) => deleteTerminalShopOrders(shopId);

  /// Full monthly reset: zeroes stats AND deletes ONLY terminal historical orders for a shop.
  /// ACTIVE orders ('placed', 'accepted') are strictly preserved.
  /// Returns the number of deleted terminal order documents.
  Future<int> fullShopReset(String shopId) async {
    final deletedCount = await deleteTerminalShopOrders(shopId);
    await resetShopStats(shopId);
    return deletedCount;
  }
}
