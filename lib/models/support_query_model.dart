// BU Gate2Eat — Models
// Customer Support Query Model for Help & Support

import 'package:cloud_firestore/cloud_firestore.dart';

/// Represents a customer support query submitted via Help & Support.
class SupportQuery {
  const SupportQuery({
    required this.id,
    required this.name,
    required this.query,
    required this.phoneNumber,
    this.customerId = '',
    required this.createdAt,
    this.status = 'unread',
  });

  final String id;
  final String name;
  final String query;
  final String phoneNumber;
  final String customerId;
  final DateTime createdAt;
  final String status;

  /// Serialization to Firestore-compatible map.
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'query': query,
      'phoneNumber': phoneNumber,
      'phone': phoneNumber,
      'customerId': customerId,
      'createdAt': Timestamp.fromDate(createdAt),
      'status': status,
    };
  }

  Map<String, dynamic> toFirestore() => toMap();

  /// Deserialization from Firestore document map.
  factory SupportQuery.fromMap(Map<String, dynamic> map, [String? docId]) {
    final rawCreatedAt = map['createdAt'];
    DateTime parsedCreatedAt;
    if (rawCreatedAt is Timestamp) {
      parsedCreatedAt = rawCreatedAt.toDate();
    } else if (rawCreatedAt is String) {
      parsedCreatedAt = DateTime.tryParse(rawCreatedAt) ?? DateTime.now();
    } else if (rawCreatedAt is int) {
      parsedCreatedAt = DateTime.fromMillisecondsSinceEpoch(rawCreatedAt);
    } else {
      parsedCreatedAt = DateTime.now();
    }

    return SupportQuery(
      id: (map['id'] as String?) ?? docId ?? '',
      name: (map['name'] as String?) ?? '',
      query: (map['query'] as String?) ?? '',
      phoneNumber: (map['phoneNumber'] as String?) ??
          (map['phone'] as String?) ??
          (map['customerPhone'] as String?) ??
          '',
      customerId: (map['customerId'] as String?) ?? '',
      createdAt: parsedCreatedAt,
      status: (map['status'] as String?) ?? 'unread',
    );
  }

  factory SupportQuery.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return SupportQuery.fromMap(data, doc.id);
  }

  SupportQuery copyWith({
    String? id,
    String? name,
    String? query,
    String? phoneNumber,
    String? customerId,
    DateTime? createdAt,
    String? status,
  }) {
    return SupportQuery(
      id: id ?? this.id,
      name: name ?? this.name,
      query: query ?? this.query,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      customerId: customerId ?? this.customerId,
      createdAt: createdAt ?? this.createdAt,
      status: status ?? this.status,
    );
  }
}
