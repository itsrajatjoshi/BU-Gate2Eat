// BU Gate2Eat — Data Models
// MenuItem model for individual food items

import 'package:cloud_firestore/cloud_firestore.dart';

/// Represents a single menu item within a shop.
class MenuItem {
  /// Creates a MenuItem instance.
  const MenuItem({
    required this.id,
    required this.name,
    required this.details,
    required this.price,
    required this.imageUrl,
    required this.categoryId,
    required this.isVeg,
    required this.isAvailable,
    required this.isRecommended,
    required this.sortOrder,
  });

  /// Creates a MenuItem from a Firestore document snapshot.
  factory MenuItem.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data()! as Map<String, dynamic>;
    return MenuItem(
      id: doc.id,
      name: (data['name'] as String?) ?? '',
      details: (data['details'] as String?) ?? (data['description'] as String?) ?? '',
      price: ((data['price'] as num?) ?? 0).toInt(),
      imageUrl: (data['imageUrl'] as String?) ?? '',
      categoryId: (data['categoryId'] as String?) ?? '',
      isVeg: (data['isVeg'] as bool?) ?? true,
      isAvailable: (data['isAvailable'] as bool?) ?? true,
      isRecommended: (data['isRecommended'] as bool?) ?? false,
      sortOrder: (data['sortOrder'] as int?) ?? 0,
    );
  }

  final String id;
  final String name;
  final String details;
  final int price;
  final String imageUrl;
  final String categoryId;
  final bool isVeg;
  final bool isAvailable;
  final bool isRecommended;
  final int sortOrder;

  /// Converts MenuItem to a Firestore-compatible map.
  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'details': details,
      'price': price,
      'imageUrl': imageUrl,
      'categoryId': categoryId,
      'isVeg': isVeg,
      'isAvailable': isAvailable,
      'isRecommended': isRecommended,
      'sortOrder': sortOrder,
    };
  }

  /// Formatted price string with rupee symbol.
  String get formattedPrice => '₹$price';
}

