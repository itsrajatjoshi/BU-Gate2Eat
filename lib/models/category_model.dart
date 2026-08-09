// BU Gate2Eat — Data Models
// Category model for menu categories within a shop

import 'package:cloud_firestore/cloud_firestore.dart';

/// Represents a menu category within a shop (e.g., Momos, Beverages, Snacks).
class Category {
  /// Creates a Category instance.
  const Category({
    required this.id,
    required this.name,
    required this.sortOrder,
    this.imageUrl = '',
    this.isActive = true,
    this.shopId = '',
  });

  /// Creates a Category from a Firestore document snapshot.
  factory Category.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data()! as Map<String, dynamic>;
    return Category(
      id: doc.id,
      name: (data['name'] as String?) ?? (data['categoryName'] as String?) ?? '',
      sortOrder: (data['sortOrder'] as int?) ?? (data['displayOrder'] as int?) ?? 0,
      imageUrl: (data['imageUrl'] as String?) ?? '',
      isActive: (data['isActive'] as bool?) ?? true,
      shopId: (data['shopId'] as String?) ?? '',
    );
  }

  final String id;
  final String name;
  final int sortOrder;
  final String imageUrl;
  final bool isActive;
  final String shopId;

  /// Convenience getters matching required interface
  String get categoryName => name;
  int get displayOrder => sortOrder;

  /// Converts Category to a Firestore-compatible map.
  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'sortOrder': sortOrder,
      'displayOrder': sortOrder,
      'imageUrl': imageUrl,
      'isActive': isActive,
      'shopId': shopId,
    };
  }
}
