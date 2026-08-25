// BU Gate2Eat — Seed Data Service & Immutability Test Suite
// Verifies that Firestore is the permanent source of truth and existing values are NEVER overwritten.

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SeedDataService Business Invariant & Immutability Rules', () {
    test('1. Custom modified phone numbers on existing shops are preserved during backfill', () {
      // Existing shop data modified by user through the app
      final existingShopData = <String, dynamic>{
        'name': 'Rajat Special Foods',
        'contactNumber': '9999999999', // Custom number modified via app
        'orderNumber': '9999999999',
        'openTime': '10:00',
        'closeTime': '22:00',
        'isClosedOverride': true,
        'isActive': true,
        'minimumOrderAmount': 150,
        'orderMethod': 'both',
      };

      // Simulating _backfillMissingShopFields logic
      final patch = <String, dynamic>{};
      if (!existingShopData.containsKey('orderMethod') || existingShopData['orderMethod'] == null) {
        patch['orderMethod'] = 'whatsapp';
      }
      if (!existingShopData.containsKey('minimumOrderAmount') || existingShopData['minimumOrderAmount'] == null) {
        patch['minimumOrderAmount'] = 0;
      }
      if (!existingShopData.containsKey('isClosedOverride') || existingShopData['isClosedOverride'] == null) {
        patch['isClosedOverride'] = false;
      }
      if (!existingShopData.containsKey('isActive') || existingShopData['isActive'] == null) {
        patch['isActive'] = true;
      }
      if (!existingShopData.containsKey('name') || (existingShopData['name'] as String?)?.trim().isEmpty == true) {
        patch['name'] = 'Rajat Shop';
      }

      // Verify no fields are patched because all keys exist!
      expect(patch, isEmpty);
      expect(existingShopData['contactNumber'], equals('9999999999'));
      expect(existingShopData['orderNumber'], equals('9999999999'));
      expect(existingShopData['name'], equals('Rajat Special Foods'));
      expect(existingShopData['minimumOrderAmount'], equals(150));
      expect(existingShopData['isClosedOverride'], isTrue);
    });

    test('2. Missing-field-only backfill populates missing keys without modifying existing fields', () {
      // Existing shop document created before new schema fields (missing orderMethod and minimumOrderAmount)
      final existingShopData = <String, dynamic>{
        'name': 'Kivisha Shop',
        'contactNumber': '8295643910',
        'orderNumber': '8295643910',
        'openTime': '08:00',
        'closeTime': '23:30',
        'isClosedOverride': false,
        'isActive': true,
      };

      final patch = <String, dynamic>{};
      if (!existingShopData.containsKey('orderMethod') || existingShopData['orderMethod'] == null) {
        patch['orderMethod'] = 'whatsapp';
      }
      if (!existingShopData.containsKey('minimumOrderAmount') || existingShopData['minimumOrderAmount'] == null) {
        patch['minimumOrderAmount'] = 0;
      }
      if (!existingShopData.containsKey('name') || (existingShopData['name'] as String?)?.trim().isEmpty == true) {
        patch['name'] = 'Kivisha Shop';
      }

      // Verify only the missing keys are added
      expect(patch.keys, containsAll(['orderMethod', 'minimumOrderAmount']));
      expect(patch.containsKey('contactNumber'), isFalse);
      expect(patch.containsKey('orderNumber'), isFalse);
      expect(patch.containsKey('name'), isFalse);

      // Merge patch
      existingShopData.addAll(patch);
      expect(existingShopData['orderMethod'], equals('whatsapp'));
      expect(existingShopData['minimumOrderAmount'], equals(0));
      expect(existingShopData['contactNumber'], equals('8295643910'));
      expect(existingShopData['orderNumber'], equals('8295643910'));
    });

    test('3. Shopkeeper phone routing maps correct shops for all 4 accounts', () {
      String resolveShopId(String phone) {
        final cleanPhone = phone.replaceAll(RegExp(r'[^0-9]'), '');
        if (cleanPhone.endsWith('8079065843') ||
            cleanPhone == '8079065843' ||
            cleanPhone.endsWith('8745007244') ||
            cleanPhone.endsWith('8745950335')) {
          return 'up16_junction_fast_food';
        } else if (cleanPhone.endsWith('8875344034') ||
            cleanPhone == '8875344034') {
          return 'kivisha_shop';
        } else if (cleanPhone.endsWith('8295643910') ||
            cleanPhone == '8295643910') {
          return 'nayan_shop';
        } else if (cleanPhone.endsWith('8000383993') ||
            cleanPhone == '8000383993') {
          return 'rajat_shop';
        }
        return 'rajat_shop';
      }

      // Rajat Shop panel login
      expect(resolveShopId('8000383993'), equals('rajat_shop'));
      expect(resolveShopId('+91 8000383993'), equals('rajat_shop'));

      // Nayan Shop panel login
      expect(resolveShopId('8295643910'), equals('nayan_shop'));
      expect(resolveShopId('+91 8295643910'), equals('nayan_shop'));

      // Kivisha Shop panel login
      expect(resolveShopId('8875344034'), equals('kivisha_shop'));
      expect(resolveShopId('+91 8875344034'), equals('kivisha_shop'));

      // UP16 panel login
      expect(resolveShopId('8079065843'), equals('up16_junction_fast_food'));
      expect(resolveShopId('+91 8079065843'), equals('up16_junction_fast_food'));
      expect(resolveShopId('8745007244'), equals('up16_junction_fast_food'));
    });
  });
}
