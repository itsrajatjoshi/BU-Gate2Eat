// BU Gate2Eat — Data Models
// Order model for In-App Orders & Firestore Documents

import 'package:cloud_firestore/cloud_firestore.dart';

/// Represents an individual item snapshot within an order.
class OrderItem {
  const OrderItem({
    required this.menuItemId,
    required this.name,
    required this.price,
    required this.quantity,
    this.imageUrl = '',
  });

  final String menuItemId;
  final String name;
  final int price;
  final int quantity;
  final String imageUrl;

  double get totalPrice => (price * quantity).toDouble();

  Map<String, dynamic> toMap() {
    return {
      'itemId': menuItemId,
      'menuItemId': menuItemId,
      'name': name,
      'price': price,
      'quantity': quantity,
      'subtotal': totalPrice,
      'imageUrl': imageUrl,
    };
  }

  factory OrderItem.fromMap(Map<String, dynamic> map) {
    return OrderItem(
      menuItemId: (map['itemId'] as String?) ??
          (map['menuItemId'] as String?) ??
          '',
      name: (map['name'] as String?) ?? '',
      price: (map['price'] as num?)?.toInt() ?? 0,
      quantity: (map['quantity'] as num?)?.toInt() ?? 1,
      imageUrl: (map['imageUrl'] as String?) ?? '',
    );
  }
}

/// Represents a customer order with complete Firestore lifecycle timestamps.
class AppOrder {
  const AppOrder({
    required this.orderId,
    required this.shopId,
    required this.shopName,
    required this.customerName,
    required this.customerPhone,
    required this.items,
    required this.totalAmount,
    required this.createdAt,
    this.customerId = '',
    this.specialInstructions = '',
    this.deliveryNote = 'Bennett University',
    this.status = 'placed',
    this.rejectionReason = '',
    this.deliveryPersonId = '',
    this.deliveryPersonName = '',
    this.updatedAt,
    this.acceptedAt,
    this.deliveredAt,
    this.rejectedAt,
    this.cancelledAt,
    this.acceptDeadline,
    this.rejectDeadline,
    this.deliveryDeadline,
  });

  final String orderId;
  final String shopId;
  final String shopName;
  final String customerId;
  final String customerName;
  final String customerPhone;
  final List<OrderItem> items;
  final double totalAmount;
  final String specialInstructions;
  final String deliveryNote;
  final String status;
  final String rejectionReason;
  /// Delivery person identity (testing: phone, production: Firebase UID).
  /// Not exposed to Customer UI — only visible to Shopkeeper and Admin.
  final String deliveryPersonId;
  final String deliveryPersonName;

  final DateTime createdAt;
  final DateTime? updatedAt;
  final DateTime? acceptedAt;
  final DateTime? deliveredAt;
  final DateTime? rejectedAt;
  final DateTime? cancelledAt;

  /// Timer deadlines (set via server timestamps at order creation / acceptance).
  final DateTime? acceptDeadline;
  final DateTime? rejectDeadline;
  final DateTime? deliveryDeadline;

  int get totalItemCount =>
      items.fold<int>(0, (acc, item) => acc + item.quantity);

  String get formattedTotal => '₹${totalAmount.toStringAsFixed(0)}';

  double get subtotal =>
      items.fold<double>(0.0, (acc, item) => acc + item.totalPrice);

  AppOrder copyWith({
    String? orderId,
    String? shopId,
    String? shopName,
    String? customerId,
    String? customerName,
    String? customerPhone,
    List<OrderItem>? items,
    double? totalAmount,
    String? specialInstructions,
    String? deliveryNote,
    String? status,
    String? rejectionReason,
    String? deliveryPersonId,
    String? deliveryPersonName,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? acceptedAt,
    DateTime? deliveredAt,
    DateTime? rejectedAt,
    DateTime? cancelledAt,
    DateTime? acceptDeadline,
    DateTime? rejectDeadline,
    DateTime? deliveryDeadline,
  }) {
    return AppOrder(
      orderId: orderId ?? this.orderId,
      shopId: shopId ?? this.shopId,
      shopName: shopName ?? this.shopName,
      customerId: customerId ?? this.customerId,
      customerName: customerName ?? this.customerName,
      customerPhone: customerPhone ?? this.customerPhone,
      items: items ?? this.items,
      totalAmount: totalAmount ?? this.totalAmount,
      specialInstructions: specialInstructions ?? this.specialInstructions,
      deliveryNote: deliveryNote ?? this.deliveryNote,
      status: status ?? this.status,
      rejectionReason: rejectionReason ?? this.rejectionReason,
      deliveryPersonId: deliveryPersonId ?? this.deliveryPersonId,
      deliveryPersonName: deliveryPersonName ?? this.deliveryPersonName,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      acceptedAt: acceptedAt ?? this.acceptedAt,
      deliveredAt: deliveredAt ?? this.deliveredAt,
      rejectedAt: rejectedAt ?? this.rejectedAt,
      cancelledAt: cancelledAt ?? this.cancelledAt,
      acceptDeadline: acceptDeadline ?? this.acceptDeadline,
      rejectDeadline: rejectDeadline ?? this.rejectDeadline,
      deliveryDeadline: deliveryDeadline ?? this.deliveryDeadline,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'orderId': orderId,
      'shopId': shopId,
      'shopName': shopName,
      'customerId': customerId,
      'customerName': customerName,
      'customerPhone': customerPhone,
      'items': items.map((i) => i.toMap()).toList(),
      'subtotal': subtotal,
      'totalItems': totalItemCount,
      'grandTotal': totalAmount,
      'totalAmount': totalAmount,
      'specialInstructions': specialInstructions,
      'deliveryNote': deliveryNote,
      'status': status,
      'rejectionReason': rejectionReason,
      if (deliveryPersonId.isNotEmpty) 'deliveryPersonId': deliveryPersonId,
      if (deliveryPersonName.isNotEmpty) 'deliveryPersonName': deliveryPersonName,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt ?? createdAt),
      if (acceptedAt != null) 'acceptedAt': Timestamp.fromDate(acceptedAt!),
      if (deliveredAt != null) 'deliveredAt': Timestamp.fromDate(deliveredAt!),
      if (rejectedAt != null) 'rejectedAt': Timestamp.fromDate(rejectedAt!),
      if (cancelledAt != null) 'cancelledAt': Timestamp.fromDate(cancelledAt!),
      if (acceptDeadline != null) 'acceptDeadline': Timestamp.fromDate(acceptDeadline!),
      if (rejectDeadline != null) 'rejectDeadline': Timestamp.fromDate(rejectDeadline!),
      if (deliveryDeadline != null) 'deliveryDeadline': Timestamp.fromDate(deliveryDeadline!),
    };
  }

  Map<String, dynamic> toFirestore() => toMap();

  static DateTime _parseDateTime(dynamic value) {
    if (value is Timestamp) {
      return value.toDate();
    } else if (value is String) {
      return DateTime.tryParse(value) ?? DateTime.now();
    } else if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value);
    }
    return DateTime.now();
  }

  static DateTime? _parseNullableDateTime(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) {
      return value.toDate();
    } else if (value is String) {
      return DateTime.tryParse(value);
    } else if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value);
    }
    return null;
  }

  factory AppOrder.fromMap(Map<String, dynamic> map, [String? docId]) {
    final rawItems = map['items'] as List<dynamic>? ?? [];
    final items = rawItems
        .map((item) =>
            OrderItem.fromMap(Map<String, dynamic>.from(item as Map)))
        .toList();

    return AppOrder(
      orderId: (map['orderId'] as String?) ?? docId ?? '',
      shopId: (map['shopId'] as String?) ?? '',
      shopName: (map['shopName'] as String?) ?? '',
      customerId: (map['customerId'] as String?) ?? '',
      customerName: (map['customerName'] as String?) ?? '',
      customerPhone: (map['customerPhone'] as String?) ?? '',
      items: items,
      totalAmount: (map['grandTotal'] as num?)?.toDouble() ??
          (map['totalAmount'] as num?)?.toDouble() ??
          0.0,
      specialInstructions: (map['specialInstructions'] as String?) ?? '',
      deliveryNote: (map['deliveryNote'] as String?) ?? 'Bennett University',
      status: (map['status'] as String?) ?? 'placed',
      rejectionReason: (map['rejectionReason'] as String?) ?? '',
      deliveryPersonId: (map['deliveryPersonId'] as String?) ?? '',
      deliveryPersonName: (map['deliveryPersonName'] as String?) ?? '',
      createdAt: _parseDateTime(map['createdAt']),
      updatedAt: _parseNullableDateTime(map['updatedAt']),
      acceptedAt: _parseNullableDateTime(map['acceptedAt']),
      deliveredAt: _parseNullableDateTime(map['deliveredAt']),
      rejectedAt: _parseNullableDateTime(map['rejectedAt']),
      cancelledAt: _parseNullableDateTime(map['cancelledAt']),
      acceptDeadline: _parseNullableDateTime(map['acceptDeadline']),
      rejectDeadline: _parseNullableDateTime(map['rejectDeadline']),
      deliveryDeadline: _parseNullableDateTime(map['deliveryDeadline']),
    );
  }

  factory AppOrder.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return AppOrder.fromMap(data, doc.id);
  }
}
