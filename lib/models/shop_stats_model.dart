// BU Gate2Eat — Data Models
// ShopStats model for Admin Order Statistics (shop-wise isolated counters)

import 'package:cloud_firestore/cloud_firestore.dart';

/// Represents shop-wise order statistics for admin vendor billing.
///
/// Each shop has exactly one [ShopStats] document in `shopStats/{shopId}`.
/// No global counters — every stat is strictly tied to one shop.
class ShopStats {
  const ShopStats({
    required this.shopId,
    required this.shopName,
    this.appOrders = 0,
    this.accepted = 0,
    this.delivered = 0,
    this.notAccepted = 0,
    this.rejectedAfterAccept = 0,
    this.deliveryExpired = 0,
    this.whatsappOrders = 0,
    this.currentPeriod = '',
    this.lastResetAt,
    this.updatedAt,
  });

  /// The shop this statistics document belongs to.
  final String shopId;

  /// Human-readable shop name for admin display.
  final String shopName;

  // ─── App Order Counters ──────────────────────────────────────────────────

  /// Total in-app orders where shopkeeper acted.
  /// Excludes customer pre-accept cancellations (those are deleted entirely).
  final int appOrders;

  /// Shopkeeper pressed "Accept Order".
  final int accepted;

  /// Order successfully delivered.
  final int delivered;

  /// Shopkeeper rejected before accepting, OR 20-min timer expired.
  final int notAccepted;

  /// Shopkeeper accepted then rejected within the 15-min window.
  final int rejectedAfterAccept;

  /// Accepted order not delivered within 90-min window.
  final int deliveryExpired;

  // ─── WhatsApp Counter ────────────────────────────────────────────────────

  /// WhatsApp button initiation count. No order documents stored.
  final int whatsappOrders;

  // ─── Period & Timestamps ─────────────────────────────────────────────────

  /// Optional label for the current billing period (e.g. "2026-08").
  final String currentPeriod;

  /// When admin last reset this shop's stats.
  final DateTime? lastResetAt;

  /// Last time any counter was modified.
  final DateTime? updatedAt;

  // ─── Computed ────────────────────────────────────────────────────────────

  /// Total orders across app + WhatsApp for quick admin display.
  int get totalOrders => appOrders + whatsappOrders;

  // ─── Firestore Serialization ─────────────────────────────────────────────

  Map<String, dynamic> toFirestore() {
    return {
      'shopId': shopId,
      'shopName': shopName,
      'appOrders': appOrders,
      'accepted': accepted,
      'delivered': delivered,
      'notAccepted': notAccepted,
      'rejectedAfterAccept': rejectedAfterAccept,
      'deliveryExpired': deliveryExpired,
      'whatsappOrders': whatsappOrders,
      'currentPeriod': currentPeriod,
      if (lastResetAt != null) 'lastResetAt': Timestamp.fromDate(lastResetAt!),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  factory ShopStats.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc,) {
    final data = doc.data() ?? {};
    return ShopStats(
      shopId: (data['shopId'] as String?) ?? doc.id,
      shopName: (data['shopName'] as String?) ?? '',
      appOrders: (data['appOrders'] as num?)?.toInt() ?? 0,
      accepted: (data['accepted'] as num?)?.toInt() ?? 0,
      delivered: (data['delivered'] as num?)?.toInt() ?? 0,
      notAccepted: (data['notAccepted'] as num?)?.toInt() ?? 0,
      rejectedAfterAccept:
          (data['rejectedAfterAccept'] as num?)?.toInt() ?? 0,
      deliveryExpired: (data['deliveryExpired'] as num?)?.toInt() ?? 0,
      whatsappOrders: (data['whatsappOrders'] as num?)?.toInt() ?? 0,
      currentPeriod: (data['currentPeriod'] as String?) ?? '',
      lastResetAt: _parseNullableDateTime(data['lastResetAt']),
      updatedAt: _parseNullableDateTime(data['updatedAt']),
    );
  }

  static DateTime? _parseNullableDateTime(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is String) return DateTime.tryParse(value);
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    return null;
  }

  /// Creates a zeroed-out stats document for a new or reset shop.
  factory ShopStats.zero({
    required String shopId,
    required String shopName,
  }) {
    return ShopStats(
      shopId: shopId,
      shopName: shopName,
    );
  }

  ShopStats copyWith({
    String? shopId,
    String? shopName,
    int? appOrders,
    int? accepted,
    int? delivered,
    int? notAccepted,
    int? rejectedAfterAccept,
    int? deliveryExpired,
    int? whatsappOrders,
    String? currentPeriod,
    DateTime? lastResetAt,
    DateTime? updatedAt,
  }) {
    return ShopStats(
      shopId: shopId ?? this.shopId,
      shopName: shopName ?? this.shopName,
      appOrders: appOrders ?? this.appOrders,
      accepted: accepted ?? this.accepted,
      delivered: delivered ?? this.delivered,
      notAccepted: notAccepted ?? this.notAccepted,
      rejectedAfterAccept: rejectedAfterAccept ?? this.rejectedAfterAccept,
      deliveryExpired: deliveryExpired ?? this.deliveryExpired,
      whatsappOrders: whatsappOrders ?? this.whatsappOrders,
      currentPeriod: currentPeriod ?? this.currentPeriod,
      lastResetAt: lastResetAt ?? this.lastResetAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  String toString() =>
      'ShopStats($shopId: app=$appOrders, wa=$whatsappOrders, '
      'accepted=$accepted, delivered=$delivered, '
      'notAccepted=$notAccepted, rejAfterAccept=$rejectedAfterAccept, '
      'deliveryExpired=$deliveryExpired)';
}
