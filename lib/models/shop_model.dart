// BU Gate2Eat — Data Models
// Shop model for Firestore documents

import 'package:cloud_firestore/cloud_firestore.dart';

/// Represents a food shop near Bennett University.
class Shop {
  /// Creates a Shop instance.
  const Shop({
    required this.id,
    required this.name,
    required this.description,
    required this.bannerUrl,
    required this.contactNumber,
    required this.orderNumber,
    required this.openTime,
    required this.closeTime,
    required this.isClosedOverride,
    required this.isActive,
    required this.sortOrder,
    required this.searchKeywords,
    required this.deliveryNote,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Creates a Shop from a Firestore document snapshot.
  factory Shop.fromFirestore(DocumentSnapshot doc) {
    final data = (doc.data() as Map<String, dynamic>?) ?? {};
    final rawKeywords = data['searchKeywords'] as List<dynamic>?;
    final keywords =
        rawKeywords != null ? rawKeywords.map((e) => e.toString()).toList() : <String>[];

    return Shop(
      id: doc.id,
      name: (data['name'] as String?) ?? '',
      description: (data['description'] as String?) ?? '',
      bannerUrl: (data['bannerUrl'] as String?) ?? (data['imageUrl'] as String?) ?? '',
      contactNumber: (data['contactNumber'] as String?) ?? (data['phoneNumber'] as String?) ?? '',
      orderNumber: (data['orderNumber'] as String?) ?? (data['whatsappNumber'] as String?) ?? '',
      openTime: (data['openTime'] as String?) ?? '08:00',
      closeTime: (data['closeTime'] as String?) ?? '23:30',
      isClosedOverride: (data['isClosedOverride'] as bool?) ?? false,
      isActive: (data['isActive'] as bool?) ?? true,
      sortOrder: (data['sortOrder'] as int?) ?? 0,
      searchKeywords: keywords,
      deliveryNote: (data['deliveryNote'] as String?) ?? 'Pickup from Gate 2',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  final String id;
  final String name;
  final String description;
  final String bannerUrl;
  final String contactNumber;
  final String orderNumber;
  final String openTime;
  final String closeTime;
  final bool isClosedOverride;
  final bool isActive;
  final int sortOrder;
  final List<String> searchKeywords;
  final String deliveryNote;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Converts Shop to a Firestore-compatible map.
  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'description': description,
      'bannerUrl': bannerUrl,
      'contactNumber': contactNumber,
      'orderNumber': orderNumber,
      'openTime': openTime,
      'closeTime': closeTime,
      'isClosedOverride': isClosedOverride,
      'isActive': isActive,
      'sortOrder': sortOrder,
      'searchKeywords': searchKeywords,
      'deliveryNote': deliveryNote,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  /// Checks if the shop is currently open based on device time and override.
  bool get isOpen {
    if (isClosedOverride) return false;

    final now = DateTime.now();
    final currentMinutes = now.hour * 60 + now.minute;

    final openParts = openTime.split(':');
    final closeParts = closeTime.split(':');
    final openMinutes = int.parse(openParts[0]) * 60 + int.parse(openParts[1]);
    final closeMinutes =
        int.parse(closeParts[0]) * 60 + int.parse(closeParts[1]);

    if (closeMinutes < openMinutes) {
      return currentMinutes >= openMinutes || currentMinutes < closeMinutes;
    }

    return currentMinutes >= openMinutes && currentMinutes < closeMinutes;
  }
}

