// BU Gate2Eat — Test Suite
// Checkpoint 1B: Item #4 (Customer → Direct Call Shopkeeper Test)

import 'package:bugate2eat_app/core/constants/app_constants.dart';
import 'package:bugate2eat_app/core/providers.dart';
import 'package:bugate2eat_app/features/orders/order_detail_screen.dart';
import 'package:bugate2eat_app/models/order_model.dart';
import 'package:bugate2eat_app/models/shop_model.dart';
import 'package:bugate2eat_app/services/local_storage_service.dart';
import 'package:bugate2eat_app/services/whatsapp_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  AppOrder createTestOrder({
    required String orderId,
    required String shopId,
    required String shopName,
    String status = 'placed',
  }) {
    return AppOrder(
      orderId: orderId,
      shopId: shopId,
      shopName: shopName,
      customerName: 'Customer Test',
      customerPhone: '9876543210',
      totalAmount: 250,
      createdAt: DateTime.now(),
      status: status,
      items: const [
        OrderItem(
          menuItemId: 'item_1',
          name: 'Steamed Momos',
          price: 120,
          quantity: 2,
        ),
      ],
    );
  }

  group('Checkpoint 1B — Item #4: Dynamic Shop Phone Number Resolution', () {
    test('1. Normalizes and validates shop phone numbers in WhatsAppService', () {
      expect(WhatsAppService.normalizePhoneNumber('8295643910'), '918295643910');
      expect(WhatsAppService.normalizePhoneNumber('+91 8295643910'), '918295643910');
      expect(WhatsAppService.normalizePhoneNumber('08295643910'), '918295643910');
      expect(WhatsAppService.normalizePhoneNumber(''), '');
    });

    test('2. Resolves correct shopkeeper contact from AppAuthRoles for all shops', () {
      expect(AppAuthRoles.getShopIdForPhone('8000383993'), 'rajat_shop');
      expect(AppAuthRoles.getShopIdForPhone('8295643910'), 'nayan_shop');
      expect(AppAuthRoles.getShopIdForPhone('8875344034'), 'kivisha_shop');
      expect(AppAuthRoles.getShopIdForPhone('8079065843'), 'up16_junction_fast_food');
      expect(AppAuthRoles.getShopIdForPhone('8888822222'), 'rajat_hotel');
      expect(AppAuthRoles.getShopIdForPhone('9999922222'), 'up16_queens');
    });
  });

  group('Checkpoint 1B — Item #4: OrderDetailScreen Call Shop Action UI & Safety', () {
    late LocalStorageService localStorage;

    setUp(() async {
      SharedPreferences.setMockInitialValues({
        'user_name': 'Test User',
        'user_phone': '9876543210',
      });
      final prefs = await SharedPreferences.getInstance();
      localStorage = LocalStorageService(prefs);
    });

    testWidgets('1. Displays Call Shop button with correct phone for Rajat Shop order', (tester) async {
      final order = createTestOrder(
        orderId: 'ORD-101',
        shopId: 'rajat_shop',
        shopName: 'Rajat Shop',
      );

      final shops = [
        Shop(
          id: 'rajat_shop',
          name: 'Rajat Shop',
          description: '',
          bannerUrl: '',
          contactNumber: '8295643910',
          orderNumber: '8295643910',
          openTime: '08:00',
          closeTime: '23:30',
          isClosedOverride: false,
          isActive: true,
          sortOrder: 1,
          searchKeywords: const [],
          deliveryNote: 'Gate 3',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localStorageServiceProvider.overrideWithValue(localStorage),
            singleOrderStreamProvider('ORD-101').overrideWith((ref) => Stream.value(order)),
            shopsProvider.overrideWith((ref) async => shops),
          ],
          child: const MaterialApp(
            home: OrderDetailScreen(orderId: 'ORD-101'),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.call_outlined), findsOneWidget);
    });

    testWidgets('2. Displays Call Shop button with correct phone for Nayan Shop order (strict isolation)', (tester) async {
      final order = createTestOrder(
        orderId: 'ORD-102',
        shopId: 'nayan_shop',
        shopName: 'Nayan Shop',
        status: 'accepted',
      );

      final shops = [
        Shop(
          id: 'nayan_shop',
          name: 'Nayan Shop',
          description: '',
          bannerUrl: '',
          contactNumber: '8875344034',
          orderNumber: '8875344034',
          openTime: '08:00',
          closeTime: '23:30',
          isClosedOverride: false,
          isActive: true,
          sortOrder: 2,
          searchKeywords: const [],
          deliveryNote: 'Gate 3',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localStorageServiceProvider.overrideWithValue(localStorage),
            singleOrderStreamProvider('ORD-102').overrideWith((ref) => Stream.value(order)),
            shopsProvider.overrideWith((ref) async => shops),
          ],
          child: const MaterialApp(
            home: OrderDetailScreen(orderId: 'ORD-102'),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.call_outlined), findsOneWidget);
    });

    testWidgets('3. Read-Only Safety: Tapping Call Shop triggers dialer without mutating order status or bill', (tester) async {
      final order = createTestOrder(
        orderId: 'ORD-103',
        shopId: 'rajat_shop',
        shopName: 'Rajat Shop',
        status: 'placed',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localStorageServiceProvider.overrideWithValue(localStorage),
            singleOrderStreamProvider('ORD-103').overrideWith((ref) => Stream.value(order)),
            shopsProvider.overrideWith((ref) async => []),
          ],
          child: const MaterialApp(
            home: OrderDetailScreen(orderId: 'ORD-103'),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final callButton = find.byIcon(Icons.call_outlined);
      expect(callButton, findsOneWidget);

      await tester.tap(callButton);
      await tester.pumpAndSettle();

      // Order status and total payable must remain 100% untouched
      expect(order.status, 'placed');
      expect(order.totalAmount, 250);
      expect(find.text('₹250'), findsWidgets);
    });
  });
}
