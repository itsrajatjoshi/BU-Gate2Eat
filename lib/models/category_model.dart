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
  });

  /// Creates a Category from a Firestore document snapshot.
  factory Category.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data()! as Map<String, dynamic>;
    return Category(
      id: doc.id,
      name: (data['name'] as String?) ?? '',
      sortOrder: (data['sortOrder'] as int?) ?? 0,
    );
  }

  final String id;
  final String name;
  final int sortOrder;

  /// Converts Category to a Firestore-compatible map.
  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'sortOrder': sortOrder,
    };
  }
}
