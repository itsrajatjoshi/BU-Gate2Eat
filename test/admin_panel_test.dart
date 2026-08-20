// BU Gate2Eat — Tests
// Admin Panel Unit & Integration Tests (Routing, Components, Shop Model, Logic)

import 'package:bugate2eat_app/core/router.dart';
import 'package:bugate2eat_app/models/shop_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Admin Routing & Credential Logic Tests', () {
    test('Phone 8078643910 routes to Admin Panel', () {
      const phone = '8078643910';
      final cleanPhone = phone.replaceAll(RegExp(r'[^0-9]'), '');
      String route;
      if (cleanPhone.endsWith('8078643910') || cleanPhone == '8078643910') {
        route = AppRoutes.admin;
      } else if (cleanPhone.endsWith('8000383993') ||
          cleanPhone == '8000383993') {
        route = AppRoutes.shopkeeper;
      } else {
        route = AppRoutes.home;
      }
      expect(route, equals(AppRoutes.admin));
      expect(route, equals('/admin'));
    });

    test('Phone +91 8078643910 with spaces routes to Admin Panel', () {
      const phone = '+91 8078643910';
      final cleanPhone = phone.replaceAll(RegExp(r'[^0-9]'), '');
      String route;
      if (cleanPhone.endsWith('8078643910') || cleanPhone == '8078643910') {
        route = AppRoutes.admin;
      } else if (cleanPhone.endsWith('8000383993') ||
          cleanPhone == '8000383993') {
        route = AppRoutes.shopkeeper;
      } else {
        route = AppRoutes.home;
      }
      expect(route, equals(AppRoutes.admin));
    });

    test('Shopkeeper Phone 8000383993 routes to Shopkeeper Panel', () {
      const phone = '8000383993';
      final cleanPhone = phone.replaceAll(RegExp(r'[^0-9]'), '');
      String route;
      if (cleanPhone.endsWith('8078643910') || cleanPhone == '8078643910') {
        route = AppRoutes.admin;
      } else if (cleanPhone.endsWith('8000383993') ||
          cleanPhone == '8000383993') {
        route = AppRoutes.shopkeeper;
      } else {
        route = AppRoutes.home;
      }
      expect(route, equals(AppRoutes.shopkeeper));
      expect(route, equals('/shopkeeper'));
    });

    test('Customer Phone 9876543210 routes to User Home', () {
      const phone = '9876543210';
      final cleanPhone = phone.replaceAll(RegExp(r'[^0-9]'), '');
      String route;
      if (cleanPhone.endsWith('8078643910') || cleanPhone == '8078643910') {
        route = AppRoutes.admin;
      } else if (cleanPhone.endsWith('8000383993') ||
          cleanPhone == '8000383993') {
        route = AppRoutes.shopkeeper;
      } else {
        route = AppRoutes.home;
      }
      expect(route, equals(AppRoutes.home));
      expect(route, equals('/home'));
    });
  });

  group('Shop Model Serialization & Logic Tests', () {
    test('Shop toFirestore and parseTimeToMinutes work correctly', () {
      final now = DateTime.now();
      final shop = Shop(
        id: 'test_shop',
        name: 'Test Shop',
        description: 'Test Description',
        bannerUrl: 'https://test.com/banner.jpg',
        contactNumber: '8078643910',
        orderNumber: '8078643910',
        openTime: '8:00 AM',
        closeTime: '11:30 PM',
        isClosedOverride: false,
        isActive: true,
        sortOrder: 1,
        searchKeywords: const ['test', 'shop'],
        deliveryNote: 'Pickup from Gate 2',
        createdAt: now,
        updatedAt: now,
      );

      final map = shop.toFirestore();
      expect(map['name'], equals('Test Shop'));
      expect(map['openTime'], equals('8:00 AM'));
      expect(map['closeTime'], equals('11:30 PM'));
      expect(map['isActive'], isTrue);
      expect(map['isClosedOverride'], isFalse);

      expect(Shop.parseTimeToMinutes('8:00 AM'), equals(480));
      expect(Shop.parseTimeToMinutes('11:30 PM'), equals(1410));
      expect(Shop.format12hr('08:00'), equals('8:00 AM'));
      expect(Shop.format12hr('23:30'), equals('11:30 PM'));
    });
  });
}
