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
    required this.imageUrl,
    required this.whatsappNumber,
    required this.phoneNumber,
    required this.openTime,
    required this.closeTime,
    required this.isActive,
    required this.sortOrder,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Creates a Shop from a Firestore document snapshot.
  factory Shop.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data()! as Map<String, dynamic>;
    return Shop(
      id: doc.id,
      name: (data['name'] as String?) ?? '',
      description: (data['description'] as String?) ?? '',
      imageUrl: (data['imageUrl'] as String?) ?? '',
      whatsappNumber: (data['whatsappNumber'] as String?) ?? '',
      phoneNumber: (data['phoneNumber'] as String?) ?? '',
      openTime: (data['openTime'] as String?) ?? '08:00',
      closeTime: (data['closeTime'] as String?) ?? '23:00',
      isActive: (data['isActive'] as bool?) ?? true,
      sortOrder: (data['sortOrder'] as int?) ?? 0,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  final String id;
  final String name;
  final String description;
  final String imageUrl;
  final String whatsappNumber;
  final String phoneNumber;
  final String openTime;
  final String closeTime;
  final bool isActive;
  final int sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Converts Shop to a Firestore-compatible map.
  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'description': description,
      'imageUrl': imageUrl,
      'whatsappNumber': whatsappNumber,
      'phoneNumber': phoneNumber,
      'openTime': openTime,
      'closeTime': closeTime,
      'isActive': isActive,
      'sortOrder': sortOrder,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  /// Checks if the shop is currently open based on device time.
  bool get isOpen {
    final now = DateTime.now();
    final currentMinutes = now.hour * 60 + now.minute;

    final openParts = openTime.split(':');
    final closeParts = closeTime.split(':');
    final openMinutes = int.parse(openParts[0]) * 60 + int.parse(openParts[1]);
    final closeMinutes =
        int.parse(closeParts[0]) * 60 + int.parse(closeParts[1]);

    // Handle overnight shops (e.g., 18:00 to 02:00)
    if (closeMinutes < openMinutes) {
      return currentMinutes >= openMinutes || currentMinutes < closeMinutes;
    }

    return currentMinutes >= openMinutes && currentMinutes < closeMinutes;
  }
}
