// BU Gate2Eat — Test Suite
// Checkpoint 1B: Item #5 (Shopkeeper → Direct Call Customer Test)

import 'package:bugate2eat_app/models/order_model.dart';
import 'package:bugate2eat_app/panel/shopkeeper_panel/widgets/shopkeeper_order_details_modal.dart';
import 'package:bugate2eat_app/services/whatsapp_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  AppOrder createTestOrder({
    required String orderId,
    required String shopId,
    required String customerName,
    required String customerPhone,
    String status = 'placed',
  }) {
    return AppOrder(
      orderId: orderId,
      shopId: shopId,
      shopName: 'Rajat Shop',
      customerName: customerName,
      customerPhone: customerPhone,
      totalAmount: 244,
      createdAt: DateTime.now(),
      status: status,
      items: const [
        OrderItem(
          menuItemId: 'item_1',
          name: 'Paneer Roll',
          price: 122,
          quantity: 2,
        ),
      ],
    );
  }

  group('Checkpoint 1B — Item #5: Shopkeeper → Direct Call Customer Logic & Isolation', () {
    test('1. Customer phone normalization preserves valid 10-digit phone', () {
      expect(WhatsAppService.normalizePhoneNumber('9876543210'), '919876543210');
      expect(WhatsAppService.normalizePhoneNumber('+91 9876543210'), '919876543210');
      expect(WhatsAppService.normalizePhoneNumber('9123456780'), '919123456780');
      expect(WhatsAppService.normalizePhoneNumber(''), '');
    });

    test('2. Strict customer phone isolation across multiple orders', () {
      final order1 = createTestOrder(
        orderId: 'ORD-A',
        shopId: 'rajat_shop',
        customerName: 'Customer A',
        customerPhone: '9876543210',
      );
      final order2 = createTestOrder(
        orderId: 'ORD-B',
        shopId: 'rajat_shop',
        customerName: 'Customer B',
        customerPhone: '9123456780',
      );

      expect(order1.customerPhone, '9876543210');
      expect(order2.customerPhone, '9123456780');
      expect(order1.customerPhone, isNot(equals(order2.customerPhone)));
    });
  });

  group('Checkpoint 1B — Item #5: ShopkeeperOrderDetailsModal Call Action UI & Safety', () {
    testWidgets('1. Displays circular call icon button next to phone number inside Customer Details card', (tester) async {
      final order = createTestOrder(
        orderId: 'ORD-101',
        shopId: 'rajat_shop',
        customerName: 'Rajat Customer',
        customerPhone: '9876543210',
        status: 'placed',
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: ShopkeeperOrderDetailsModal(order: order),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify order details header and customer information
      expect(find.text('Order #ORD-101'), findsOneWidget);
      expect(find.text('Rajat Customer'), findsOneWidget);
      expect(find.text('9876543210'), findsOneWidget);

      // Verify call button icon
      final callButton = find.byIcon(Icons.call_outlined);
      expect(callButton, findsOneWidget);

      // Verify existing action buttons are present and not covered
      expect(find.text('Reject'), findsOneWidget);
      expect(find.text('Accept Order'), findsOneWidget);
    });

    testWidgets('2. Displays call button for accepted orders and history orders', (tester) async {
      final acceptedOrder = createTestOrder(
        orderId: 'ORD-102',
        shopId: 'rajat_shop',
        customerName: 'Kivisha',
        customerPhone: '9876543210',
        status: 'accepted',
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: ShopkeeperOrderDetailsModal(order: acceptedOrder),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.call_outlined), findsOneWidget);
      expect(find.text('Mark as Delivered'), findsOneWidget);
    });

    testWidgets('3. Read-Only Safety: Tapping Call Customer does not mutate order status, timestamps or total', (tester) async {
      final order = createTestOrder(
        orderId: 'ORD-103',
        shopId: 'rajat_shop',
        customerName: 'Safe Customer',
        customerPhone: '9876543210',
        status: 'placed',
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: ShopkeeperOrderDetailsModal(order: order),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final callButton = find.byIcon(Icons.call_outlined);
      expect(callButton, findsOneWidget);

      await tester.tap(callButton);
      await tester.pumpAndSettle();

      // Zero mutation check
      expect(order.status, 'placed');
      expect(order.totalAmount, 244);
      expect(order.acceptedAt, isNull);
      expect(order.rejectedAt, isNull);
      expect(order.deliveredAt, isNull);
    });

    testWidgets('4. Missing customer phone displays user-friendly error snackbar', (tester) async {
      final order = createTestOrder(
        orderId: 'ORD-104',
        shopId: 'rajat_shop',
        customerName: 'No Phone Customer',
        customerPhone: '',
        status: 'placed',
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: ShopkeeperOrderDetailsModal(order: order),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final callButton = find.byIcon(Icons.call_outlined);
      expect(callButton, findsOneWidget);

      await tester.tap(callButton);
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Unable to call customer.'),
        findsOneWidget,
      );
    });
  });
}
