// BU Gate2Eat — Services
// Shop Statistics Service for Admin Order Statistics
// Handles Firestore `shopStats/{shopId}` CRUD, atomic counter increments, and reset.
// Every operation is strictly shop-wise — no global/cross-shop mutations.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

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

  /// Increments `whatsappOrders` when WhatsApp order button is successfully
  /// launched for this shop. No order document is created.
  Future<void> incrementWhatsappOrders(String shopId) async {
    await _incrementField(shopId, 'whatsappOrders');
  }

  /// Internal helper: atomically increments a single numeric field.
  Future<void> _incrementField(String shopId, String field) async {
    if (!isAvailable) return;
    try {
      await _statsRef.doc(shopId).update({
        field: FieldValue.increment(1),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      // Document may not exist yet — create it with the field set to 1
      if (e is FirebaseException && e.code == 'not-found') {
        try {
          await _statsRef.doc(shopId).set({
            'shopId': shopId,
            field: 1,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true),);
        } catch (innerError) {
          debugPrint(
              '❌ ShopStatsService _incrementField create fallback error: $innerError',);
        }
      } else {
        debugPrint('❌ ShopStatsService _incrementField error ($field): $e');
      }
    }
  }

  // ─── Reset ──────────────────────────────────────────────────────────────────

  /// Resets all counters to 0 for a specific shop.
  /// Also sets `lastResetAt` to server timestamp.
  ///
  /// This does NOT delete the stats document itself — it zeroes it out.
  /// Order document deletion is handled separately by [deleteShopOrders].
  Future<void> resetShopStats(String shopId) async {
    if (!isAvailable) return;
    try {
      await _statsRef.doc(shopId).set({
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
      }, SetOptions(merge: true));
      debugPrint('✅ ShopStatsService: Reset stats for $shopId');
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
  Future<int> deleteTerminalShopOrders(String shopId) async {
    if (!isAvailable) return 0;
    int totalDeleted = 0;
    try {
      const terminalStatuses = [
        'delivered',
        'rejected',
        'delivery_expired',
        'cancelled',
      ];

      const batchSize = 100;
      while (true) {
        final snapshot = await _firestore
            .collection('orders')
            .where('shopId', isEqualTo: shopId)
            .where('status', whereIn: terminalStatuses)
            .limit(batchSize)
            .get();

        if (snapshot.docs.isEmpty) break;

        final batch = _firestore.batch();
        int batchDeleteCount = 0;
        for (final doc in snapshot.docs) {
          final status = (doc.data()['status'] as String?) ?? '';
          // Hard backend guard: NEVER delete placed or accepted orders
          if (status != 'placed' && status != 'accepted') {
            batch.delete(doc.reference);
            batchDeleteCount++;
          }
        }

        if (batchDeleteCount > 0) {
          await batch.commit();
          totalDeleted += batchDeleteCount;
        }

        if (snapshot.docs.length < batchSize) break;
      }
      debugPrint(
        '✅ ShopStatsService: Deleted $totalDeleted terminal orders for $shopId (Active orders preserved)',
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
