// BU Gate2Eat — Data Models
// MenuItem model for individual food items

import 'package:cloud_firestore/cloud_firestore.dart';

/// Represents a single menu item within a shop.
class MenuItem {
  /// Creates a MenuItem instance.
  const MenuItem({
    required this.id,
    required this.name,
    required this.description,
    required this.price,
    required this.imageUrl,
    required this.categoryId,
    required this.isVeg,
    required this.isAvailable,
    required this.sortOrder,
  });

  /// Creates a MenuItem from a Firestore document snapshot.
  factory MenuItem.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data()! as Map<String, dynamic>;
    return MenuItem(
      id: doc.id,
      name: (data['name'] as String?) ?? '',
      description: (data['description'] as String?) ?? '',
      price: ((data['price'] as num?) ?? 0).toDouble(),
      imageUrl: (data['imageUrl'] as String?) ?? '',
      categoryId: (data['categoryId'] as String?) ?? '',
      isVeg: (data['isVeg'] as bool?) ?? true,
      isAvailable: (data['isAvailable'] as bool?) ?? true,
      sortOrder: (data['sortOrder'] as int?) ?? 0,
    );
  }

  final String id;
  final String name;
  final String description;
  final double price;
  final String imageUrl;
  final String categoryId;
  final bool isVeg;
  final bool isAvailable;
  final int sortOrder;

  /// Converts MenuItem to a Firestore-compatible map.
  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'description': description,
      'price': price,
      'imageUrl': imageUrl,
      'categoryId': categoryId,
      'isVeg': isVeg,
      'isAvailable': isAvailable,
      'sortOrder': sortOrder,
    };
  }

  /// Formatted price string with rupee symbol.
  String get formattedPrice => '₹${price.toStringAsFixed(0)}';
}
