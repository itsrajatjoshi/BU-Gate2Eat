// BU Gate2Eat — Data Models
// Shop model for Firestore documents

import 'package:cloud_firestore/cloud_firestore.dart';

/// Available ordering channels for a shop.
enum ShopOrderMethod {
  whatsapp,
  app,
  both;

  static ShopOrderMethod fromString(dynamic val) {
    if (val == null) return ShopOrderMethod.whatsapp;
    final str = val.toString().trim().toLowerCase();
    if (str == 'app' || str == 'inapp' || str == 'yummbu') {
      return ShopOrderMethod.app;
    }
    if (str == 'both' || str == 'all') {
      return ShopOrderMethod.both;
    }
    return ShopOrderMethod.whatsapp;
  }
}

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
    this.address = '',
    this.shopLogoImageUrl = '',
    this.orderMethod = ShopOrderMethod.whatsapp,
    this.minimumOrderAmount = 0,
    this.deliveryCharges = 0,
  });

  /// Creates a Shop from a Map and optional document ID.
  factory Shop.fromMap(Map<String, dynamic> data, [String id = '']) {
    final rawKeywords = data['searchKeywords'] as List<dynamic>?;
    final keywords =
        rawKeywords != null ? rawKeywords.map((e) => e.toString()).toList() : <String>[];

    return Shop(
      id: id,
      name: (data['name'] as String?) ?? '',
      description: (data['description'] as String?) ?? '',
      address: (data['address'] as String?) ?? '',
      bannerUrl: (data['bannerUrl'] as String?) ?? (data['imageUrl'] as String?) ?? '',
      shopLogoImageUrl: (data['shopLogoImageUrl'] as String?) ?? '',
      contactNumber: (data['contactNumber'] as String?) ?? (data['phoneNumber'] as String?) ?? '',
      orderNumber: (data['orderNumber'] as String?) ?? (data['whatsappNumber'] as String?) ?? '',
      openTime: (data['openTime'] as String?) ?? '08:00',
      closeTime: (data['closeTime'] as String?) ?? '23:30',
      isClosedOverride: (data['isClosedOverride'] as bool?) ?? false,
      isActive: (data['isActive'] as bool?) ?? true,
      sortOrder: (data['sortOrder'] as num?)?.toInt() ?? 0,
      searchKeywords: keywords,
      deliveryNote: (data['deliveryNote'] as String?) ?? 'Pickup from Gate 3',
      createdAt: _parseDateTime(data['createdAt']),
      updatedAt: _parseDateTime(data['updatedAt']),
      orderMethod: ShopOrderMethod.fromString(data['orderMethod']),
      minimumOrderAmount: (data['minimumOrderAmount'] as num?)?.toInt() ?? 0,
      deliveryCharges: ((data['deliveryCharges'] as num?)?.toInt() ??
              (data['deliveryCharge'] as num?)?.toInt() ??
              (data['deliveryFee'] as num?)?.toInt() ??
              0)
          .clamp(0, 100000),
    );
  }

  static DateTime _parseDateTime(dynamic value) {
    if (value is Timestamp) {
      return value.toDate();
    } else if (value is DateTime) {
      return value;
    } else if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value);
    } else if (value is String) {
      final parsed = DateTime.tryParse(value);
      if (parsed != null) return parsed;
    }
    return DateTime.now();
  }

  /// Creates a Shop from a Firestore document snapshot.
  factory Shop.fromFirestore(DocumentSnapshot doc) {
    return Shop.fromMap((doc.data() as Map<String, dynamic>?) ?? {}, doc.id);
  }

  final String id;
  final String name;
  final String description;
  final String address;
  final String bannerUrl;
  final String shopLogoImageUrl;
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
  final ShopOrderMethod orderMethod;
  final int minimumOrderAmount;
  final int deliveryCharges;

  Shop copyWith({
    String? id,
    String? name,
    String? description,
    String? address,
    String? bannerUrl,
    String? shopLogoImageUrl,
    String? contactNumber,
    String? orderNumber,
    String? openTime,
    String? closeTime,
    bool? isClosedOverride,
    bool? isActive,
    int? sortOrder,
    List<String>? searchKeywords,
    String? deliveryNote,
    DateTime? createdAt,
    DateTime? updatedAt,
    ShopOrderMethod? orderMethod,
    int? minimumOrderAmount,
    int? deliveryCharges,
  }) {
    return Shop(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      address: address ?? this.address,
      bannerUrl: bannerUrl ?? this.bannerUrl,
      shopLogoImageUrl: shopLogoImageUrl ?? this.shopLogoImageUrl,
      contactNumber: contactNumber ?? this.contactNumber,
      orderNumber: orderNumber ?? this.orderNumber,
      openTime: openTime ?? this.openTime,
      closeTime: closeTime ?? this.closeTime,
      isClosedOverride: isClosedOverride ?? this.isClosedOverride,
      isActive: isActive ?? this.isActive,
      sortOrder: sortOrder ?? this.sortOrder,
      searchKeywords: searchKeywords ?? this.searchKeywords,
      deliveryNote: deliveryNote ?? this.deliveryNote,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      orderMethod: orderMethod ?? this.orderMethod,
      minimumOrderAmount: minimumOrderAmount ?? this.minimumOrderAmount,
      deliveryCharges: deliveryCharges ?? this.deliveryCharges,
    );
  }

  /// Converts any time string ("08:00", "8:00 AM", "23:30", "11:30 PM") into minutes from midnight (0..1439).
  static int parseTimeToMinutes(String timeStr, {int defaultMinutes = 0}) {
    if (timeStr.trim().isEmpty) return defaultMinutes;
    final trimmed = timeStr.trim().toUpperCase();

    final isPM = trimmed.contains('PM');
    final isAM = trimmed.contains('AM');
    final cleanTime =
        trimmed.replaceAll('AM', '').replaceAll('PM', '').replaceAll('.', '').trim();

    final parts = cleanTime.split(':');
    if (parts.isEmpty) return defaultMinutes;

    int hour = int.tryParse(parts[0].trim()) ?? 0;
    final int minute = parts.length > 1 ? (int.tryParse(parts[1].trim()) ?? 0) : 0;

    if (isPM && hour < 12) {
      hour += 12;
    } else if (isAM && hour == 12) {
      hour = 0;
    }

    return (hour * 60 + minute).clamp(0, 1439);
  }

  /// Converts any time string into standard 12-hour AM/PM format (e.g. "8:00 AM" or "11:30 PM").
  static String format12hr(String timeStr) {
    if (timeStr.trim().isEmpty) return '';
    final minutes = parseTimeToMinutes(timeStr);
    final hour24 = minutes ~/ 60;
    final minute = (minutes % 60).toString().padLeft(2, '0');
    final period = hour24 >= 12 ? 'PM' : 'AM';
    final hour12 = hour24 == 0 ? 12 : (hour24 > 12 ? hour24 - 12 : hour24);
    return '$hour12:$minute $period';
  }

  /// 12-hour formatted open time (e.g. "8:00 AM").
  String get formattedOpenTime => format12hr(openTime);

  /// 12-hour formatted close time (e.g. "11:30 PM").
  String get formattedCloseTime => format12hr(closeTime);

  /// Combined formatted timing (e.g. "8:00 AM – 11:30 PM").
  String get formattedTimings => '$formattedOpenTime – $formattedCloseTime';

  /// Converts Shop to a Firestore-compatible map.
  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'description': description,
      'address': address,
      'bannerUrl': bannerUrl,
      'shopLogoImageUrl': shopLogoImageUrl,
      'contactNumber': contactNumber,
      'orderNumber': orderNumber,
      'openTime': openTime,
      'closeTime': closeTime,
      'isClosedOverride': isClosedOverride,
      'isActive': isActive,
      'sortOrder': sortOrder,
      'searchKeywords': searchKeywords,
      'deliveryNote': deliveryNote,
      'orderMethod': orderMethod.name,
      'minimumOrderAmount': minimumOrderAmount,
      'deliveryCharges': deliveryCharges,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  /// Checks if a shop is open at a specific DateTime [time].
  static bool isShopOpenAt({
    required String openTime,
    required String closeTime,
    required DateTime time,
    bool isClosedOverride = false,
    bool isActive = true,
  }) {
    if (isClosedOverride || !isActive) return false;

    final currentMinutes = time.hour * 60 + time.minute;
    final openMinutes = parseTimeToMinutes(openTime, defaultMinutes: 8 * 60);
    final closeMinutes = parseTimeToMinutes(closeTime, defaultMinutes: 23 * 60 + 30);

    if (openMinutes == closeMinutes) {
      return false;
    }

    if (closeMinutes < openMinutes) {
      // Midnight-crossing (e.g. 20:00 -> 02:00)
      return currentMinutes >= openMinutes || currentMinutes < closeMinutes;
    }

    return currentMinutes >= openMinutes && currentMinutes < closeMinutes;
  }

  /// Checks if the shop is currently open based on device time and override.
  bool get isOpen => isShopOpenAt(
        openTime: openTime,
        closeTime: closeTime,
        time: DateTime.now(),
        isClosedOverride: isClosedOverride,
        isActive: isActive,
      );
}
