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
    this.lifetimeWhatsappOrders = 0,
    this.monthlyWhatsappOrders = const {},
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

  /// WhatsApp order initiation count for the current statement period (since lastResetAt).
  /// Resets to 0 when admin performs a shop statistics reset.
  final int whatsappOrders;

  /// Cumulative lifetime WhatsApp order initiations across all time.
  /// Preserved across admin resets.
  final int lifetimeWhatsappOrders;

  /// Month-by-month WhatsApp order counters keyed by "YYYY-MM" (legacy support).
  final Map<String, int> monthlyWhatsappOrders;

  // ─── Period & Timestamps ─────────────────────────────────────────────────

  /// Optional label for the current billing period.
  final String currentPeriod;

  /// When admin last reset this shop's stats.
  final DateTime? lastResetAt;

  /// Last time any counter was modified.
  final DateTime? updatedAt;

  // ─── Computed ────────────────────────────────────────────────────────────

  /// Total orders across app + WhatsApp for quick admin display in the current statement period.
  int get totalOrders => appOrders + whatsappOrders;

  /// Returns the WhatsApp orders for a specific month (e.g. "2026-08").
  /// If explicit month key exists, returns that count.
  /// If not set yet and queried month is the current active month, falls back to rolling [whatsappOrders].
  int getWhatsappOrdersForMonth(DateTime month) {
    final key =
        '${month.year.toString().padLeft(4, '0')}-${month.month.toString().padLeft(2, '0')}';
    if (monthlyWhatsappOrders.containsKey(key)) {
      return monthlyWhatsappOrders[key]!;
    }
    final now = DateTime.now();
    final currentKey =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}';
    if (key == currentKey) {
      return whatsappOrders;
    }
    return 0;
  }

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
      'lifetimeWhatsappOrders': lifetimeWhatsappOrders > 0 ? lifetimeWhatsappOrders : whatsappOrders,
      if (monthlyWhatsappOrders.isNotEmpty)
        'monthlyWhatsappOrders': monthlyWhatsappOrders,
      'currentPeriod': currentPeriod,
      if (lastResetAt != null) 'lastResetAt': Timestamp.fromDate(lastResetAt!),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  factory ShopStats.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? {};
    final rawMonthly = data['monthlyWhatsappOrders'];
    Map<String, int> monthlyMap = const {};
    if (rawMonthly is Map) {
      monthlyMap = rawMonthly.map(
        (k, v) => MapEntry(k.toString(), (v as num).toInt()),
      );
    }

    final rawWhatsapp = (data['whatsappOrders'] as num?)?.toInt() ?? 0;
    final rawLifetime = (data['lifetimeWhatsappOrders'] as num?)?.toInt() ?? rawWhatsapp;

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
      whatsappOrders: rawWhatsapp,
      lifetimeWhatsappOrders: rawLifetime,
      monthlyWhatsappOrders: monthlyMap,
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
    int? lifetimeWhatsappOrders,
    Map<String, int>? monthlyWhatsappOrders,
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
      lifetimeWhatsappOrders:
          lifetimeWhatsappOrders ?? this.lifetimeWhatsappOrders,
      monthlyWhatsappOrders:
          monthlyWhatsappOrders ?? this.monthlyWhatsappOrders,
      currentPeriod: currentPeriod ?? this.currentPeriod,
      lastResetAt: lastResetAt ?? this.lastResetAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  String toString() =>
      'ShopStats($shopId: app=$appOrders, wa=$whatsappOrders, lifetimeWa=$lifetimeWhatsappOrders, '
      'accepted=$accepted, delivered=$delivered, '
      'notAccepted=$notAccepted, rejAfterAccept=$rejectedAfterAccept, '
      'deliveryExpired=$deliveryExpired)';
}
