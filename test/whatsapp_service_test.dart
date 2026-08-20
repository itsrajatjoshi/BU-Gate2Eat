// BU Gate2Eat — Tests
// WhatsApp Service & Shop-Specific Ordering Unit Tests

import 'package:bugate2eat_app/models/cart_item_model.dart';
import 'package:bugate2eat_app/models/menu_item_model.dart';
import 'package:bugate2eat_app/models/shop_model.dart';
import 'package:bugate2eat_app/services/whatsapp_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WhatsAppService Phone Number Normalization Tests', () {
    test('Case A: 10-digit Indian number is prepended with 91', () {
      expect(WhatsAppService.normalizePhoneNumber('8295643910'),
          equals('918295643910'));
      expect(WhatsAppService.normalizePhoneNumber('9999999999'),
          equals('919999999999'));
    });

    test('Case B: +91 number is cleaned to 91XXXXXXXXXX', () {
      expect(WhatsAppService.normalizePhoneNumber('+918295643910'),
          equals('918295643910'));
      expect(WhatsAppService.normalizePhoneNumber('+919999999999'),
          equals('919999999999'));
    });

    test('Case C: Number with spaces is cleaned and normalized', () {
      expect(WhatsAppService.normalizePhoneNumber('+91 82956 43910'),
          equals('918295643910'));
      expect(WhatsAppService.normalizePhoneNumber('91 99999 99999'),
          equals('919999999999'));
      expect(WhatsAppService.normalizePhoneNumber('82956 43910'),
          equals('918295643910'));
    });

    test('Case D: Number with dashes and brackets is cleaned and normalized', () {
      expect(WhatsAppService.normalizePhoneNumber('+91-82956-43910'),
          equals('918295643910'));
      expect(WhatsAppService.normalizePhoneNumber('(999) 999-9999'),
          equals('919999999999'));
      expect(WhatsAppService.normalizePhoneNumber('09876543210'),
          equals('919876543210'));
    });

    test('Case E: Number already having 91 prefix is preserved', () {
      expect(WhatsAppService.normalizePhoneNumber('918295643910'),
          equals('918295643910'));
      expect(WhatsAppService.normalizePhoneNumber('919999999999'),
          equals('919999999999'));
    });

    test('Case F: Missing or invalid numbers return empty string', () {
      expect(WhatsAppService.normalizePhoneNumber(''), equals(''));
      expect(WhatsAppService.normalizePhoneNumber('   '), equals(''));
      expect(WhatsAppService.normalizePhoneNumber('12345'), equals(''));
      expect(WhatsAppService.normalizePhoneNumber('abc'), equals(''));
    });
  });

  group('Shop-Specific WhatsApp URL Generation Tests', () {
    final now = DateTime.now();

    final shopA = Shop(
      id: 'rajat_shop',
      name: 'Rajat Shop',
      description: 'Chinese and Fast Food',
      bannerUrl: '',
      contactNumber: '8295643910',
      orderNumber: '8295643910',
      openTime: '08:00',
      closeTime: '23:30',
      isClosedOverride: false,
      isActive: true,
      sortOrder: 1,
      searchKeywords: const [],
      deliveryNote: 'Gate 2',
      createdAt: now,
      updatedAt: now,
    );

    final shopB = Shop(
      id: 'test_cafe_99',
      name: 'Test Cafe 99',
      description: 'Snacks & Chai',
      bannerUrl: '',
      contactNumber: '9999999999',
      orderNumber: '9999999999',
      openTime: '08:00',
      closeTime: '23:30',
      isClosedOverride: false,
      isActive: true,
      sortOrder: 2,
      searchKeywords: const [],
      deliveryNote: 'Gate 2',
      createdAt: now,
      updatedAt: now,
    );

    const testItem = MenuItem(
      id: 'item_1',
      name: 'Veg Momos',
      price: 60,
      details: 'Steamed momos',
      categoryId: 'momos',
      isVeg: true,
      isAvailable: true,
      isRecommended: false,
      sortOrder: 1,
      imageUrl: '',
    );

    final cartItems = [
      const CartItem(
        menuItem: testItem,
        quantity: 2,
        shopId: 'test_cafe_99',
        shopName: 'Test Cafe 99',
      ),
    ];

    test('Case G: Shop A generates WhatsApp URL targeting 918295643910', () {
      final message = WhatsAppService.generateOrderMessage(
        shopName: shopA.name,
        userName: 'Rajat',
        userPhone: '8078643910',
        cartItems: cartItems,
      );

      final uri = WhatsAppService.buildWhatsAppUri(
        whatsappNumber: shopA.contactNumber,
        message: message,
      );

      expect(uri, isNotNull);
      expect(uri!.host, equals('wa.me'));
      expect(uri.path, equals('/918295643910'));
      expect(uri.queryParameters['text'], contains('Hello Rajat Shop,'));
      expect(uri.queryParameters['text'], contains('2 × Veg Momos — ₹120'));
    });

    test('Case G: Shop B generates WhatsApp URL targeting 919999999999', () {
      final message = WhatsAppService.generateOrderMessage(
        shopName: shopB.name,
        userName: 'Rajat',
        userPhone: '8078643910',
        cartItems: cartItems,
      );

      final uri = WhatsAppService.buildWhatsAppUri(
        whatsappNumber: shopB.contactNumber,
        message: message,
      );

      expect(uri, isNotNull);
      expect(uri!.host, equals('wa.me'));
      expect(uri.path, equals('/919999999999'));
      expect(uri.queryParameters['text'], contains('Hello Test Cafe 99,'));
      expect(uri.queryParameters['text'], contains('2 × Veg Momos — ₹120'));
    });
  });
}
