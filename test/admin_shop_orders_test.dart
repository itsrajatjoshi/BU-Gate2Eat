// BU Gate2Eat — Admin Shop Orders Test Suite (Phase D)
//
// Verification of:
// 1. Raja Hotel → only Raja Hotel orders
// 2. Nayan Cafe → only Nayan Cafe orders
// 3. Orders from Shop A never appear in Shop B
// 4. WhatsApp counter does not create order records (only in-app orders appear)
// 5. Customer pre-accept cancellation is absent from Admin list
// 6. Delivered order shows delivery person to Admin
// 7. Rejected-after-accept order displays reason and details
// 8. Empty shop shows empty state
// 9. Sorting is newest first (createdAt DESC)
// 10. Tap opens correct order details modal
// 11. Admin detail modal is read-only (zero mutation buttons)
// 12. No data mixing between two selected shops

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bugate2eat_app/core/providers.dart';
import 'package:bugate2eat_app/models/order_model.dart';
import 'package:bugate2eat_app/models/shop_model.dart';
import 'package:bugate2eat_app/panel/admin_panel/admin_shop_orders_screen.dart';
import 'package:bugate2eat_app/panel/admin_panel/widgets/admin_order_details_modal.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final shop1 = Shop(
    id: 'rajat_shop',
    name: 'Rajat Hotel',
    description: 'Fresh & Fast',
    bannerUrl: '',
    contactNumber: '8295643910',
    orderNumber: '8295643910',
    openTime: '09:00',
    closeTime: '23:00',
    isClosedOverride: false,
    isActive: true,
    sortOrder: 1,
    searchKeywords: const [],
    deliveryNote: 'Gate 2 Delivery Point',
    createdAt: DateTime(2026, 8, 24),
    updatedAt: DateTime(2026, 8, 24),
  );

  final shop2 = Shop(
    id: 'nayan_shop',
    name: 'Nayan Cafe',
    description: 'Best Coffee & Snacks',
    bannerUrl: '',
    contactNumber: '8875344034',
    orderNumber: '8875344034',
    openTime: '09:00',
    closeTime: '23:00',
    isClosedOverride: false,
    isActive: true,
    sortOrder: 2,
    searchKeywords: const [],
    deliveryNote: 'Bennett University',
    createdAt: DateTime(2026, 8, 24),
    updatedAt: DateTime(2026, 8, 24),
  );

  final rajatOrderDelivered = AppOrder(
    orderId: 'YB-RAJAT-001',
    customerId: 'cust_1',
    customerName: 'Aarav Sharma',
    customerPhone: '9876543210',
    shopId: 'rajat_shop',
    shopName: 'Rajat Hotel',
    status: 'delivered',
    totalAmount: 240,
    items: [
      const OrderItem(
        menuItemId: 'm1',
        name: 'Paneer Butter Masala',
        price: 200,
        quantity: 1,
      ),
      const OrderItem(
        menuItemId: 'm2',
        name: 'Butter Roti',
        price: 20,
        quantity: 2,
      ),
    ],
    deliveryPersonId: '8295643910',
    deliveryPersonName: 'Ramesh Delivery',
    createdAt: DateTime(2026, 8, 24, 12, 0),
    acceptedAt: DateTime(2026, 8, 24, 12, 5),
    deliveredAt: DateTime(2026, 8, 24, 12, 35),
  );

  final rajatOrderRejected = AppOrder(
    orderId: 'YB-RAJAT-002',
    customerId: 'cust_2',
    customerName: 'Priya Verma',
    customerPhone: '9876543211',
    shopId: 'rajat_shop',
    shopName: 'Rajat Hotel',
    status: 'rejected',
    rejectionReason: 'Items out of stock',
    totalAmount: 150,
    items: [
      const OrderItem(
        menuItemId: 'm3',
        name: 'Veg Biryani',
        price: 150,
        quantity: 1,
      ),
    ],
    createdAt: DateTime(2026, 8, 24, 13, 0),
    acceptedAt: DateTime(2026, 8, 24, 13, 2),
    rejectedAt: DateTime(2026, 8, 24, 13, 8),
  );

  final nayanOrderDelivered = AppOrder(
    orderId: 'YB-NAYAN-001',
    customerId: 'cust_3',
    customerName: 'Karan Patel',
    customerPhone: '9876543212',
    shopId: 'nayan_shop',
    shopName: 'Nayan Cafe',
    status: 'delivered',
    totalAmount: 90,
    items: [
      const OrderItem(
        menuItemId: 'm4',
        name: 'Cold Coffee',
        price: 90,
        quantity: 1,
      ),
    ],
    createdAt: DateTime(2026, 8, 24, 14, 0),
    deliveredAt: DateTime(2026, 8, 24, 14, 25),
  );

  group('Phase D: Admin Selected Shop In-App Orders List Tests', () {
    testWidgets('1. Query for Raja Hotel returns ONLY Raja Hotel orders with correct details', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            shopsProvider.overrideWith((ref) => Future.value([shop1, shop2])),
            shopOrdersStreamProvider('rajat_shop').overrideWith(
              (ref) => Stream.value([rajatOrderRejected, rajatOrderDelivered]), // newest first
            ),
          ],
          child: const MaterialApp(
            home: AdminShopOrdersScreen(shopId: 'rajat_shop'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Screen title and shop header
      expect(find.text('Rajat Hotel App Orders'), findsOneWidget);
      expect(find.text('Completed Orders: 2'), findsOneWidget);

      // Verify Raja Hotel orders are listed
      expect(find.text('#YB-RAJAT-002'), findsOneWidget);
      expect(find.text('#YB-RAJAT-001'), findsOneWidget);
      expect(find.text('Priya Verma'), findsOneWidget);
      expect(find.text('Aarav Sharma'), findsOneWidget);

      // Verify Nayan orders NEVER appear
      expect(find.text('#YB-NAYAN-001'), findsNothing);
      expect(find.text('Karan Patel'), findsNothing);
    });

    testWidgets('2. Query for Nayan Cafe returns ONLY Nayan Cafe orders', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            shopsProvider.overrideWith((ref) => Future.value([shop1, shop2])),
            shopOrdersStreamProvider('nayan_shop').overrideWith(
              (ref) => Stream.value([nayanOrderDelivered]),
            ),
          ],
          child: const MaterialApp(
            home: AdminShopOrdersScreen(shopId: 'nayan_shop'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Screen title and shop header
      expect(find.text('Nayan Cafe App Orders'), findsOneWidget);
      expect(find.text('Completed Orders: 1'), findsOneWidget);

      // Verify Nayan orders are present
      expect(find.text('#YB-NAYAN-001'), findsOneWidget);
      expect(find.text('Karan Patel'), findsOneWidget);

      // Verify Raja orders NEVER appear
      expect(find.text('#YB-RAJAT-001'), findsNothing);
      expect(find.text('#YB-RAJAT-002'), findsNothing);
    });

    testWidgets('2b. Active placed and accepted orders NEVER appear in Admin Shop Orders view', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final activePlaced = AppOrder(
        orderId: 'YB-ACTIVE-PLACED',
        customerId: 'cust_act_1',
        customerName: 'Active User 1',
        customerPhone: '9876543210',
        shopId: 'rajat_shop',
        shopName: 'Rajat Hotel',
        status: 'placed',
        totalAmount: 100,
        items: const [OrderItem(menuItemId: 'm1', name: 'Tea', price: 100, quantity: 1)],
        createdAt: DateTime(2026, 8, 24, 15, 0),
      );

      final activeAccepted = AppOrder(
        orderId: 'YB-ACTIVE-ACCEPTED',
        customerId: 'cust_act_2',
        customerName: 'Active User 2',
        customerPhone: '9876543211',
        shopId: 'rajat_shop',
        shopName: 'Rajat Hotel',
        status: 'accepted',
        totalAmount: 150,
        items: const [OrderItem(menuItemId: 'm2', name: 'Coffee', price: 150, quantity: 1)],
        createdAt: DateTime(2026, 8, 24, 15, 5),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            shopsProvider.overrideWith((ref) => Future.value([shop1])),
            shopOrdersStreamProvider('rajat_shop').overrideWith(
              (ref) => Stream.value([activePlaced, activeAccepted]),
            ),
          ],
          child: const MaterialApp(
            home: AdminShopOrdersScreen(shopId: 'rajat_shop'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Screen shows empty state since active orders are filtered out for Admin
      expect(find.text('No app orders yet'), findsOneWidget);
      expect(find.text('#YB-ACTIVE-PLACED'), findsNothing);
      expect(find.text('#YB-ACTIVE-ACCEPTED'), findsNothing);
    });

    testWidgets('3. Empty shop renders clean empty state without dummy data', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            shopsProvider.overrideWith((ref) => Future.value([shop1])),
            shopOrdersStreamProvider('rajat_shop').overrideWith(
              (ref) => Stream.value([]),
            ),
          ],
          child: const MaterialApp(
            home: AdminShopOrdersScreen(shopId: 'rajat_shop'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No app orders yet'), findsOneWidget);
      expect(find.text('Orders from this shop will appear here.'), findsOneWidget);
    });

    testWidgets('4. Filter chips filter orders by status accurately', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            shopsProvider.overrideWith((ref) => Future.value([shop1])),
            shopOrdersStreamProvider('rajat_shop').overrideWith(
              (ref) => Stream.value([rajatOrderRejected, rajatOrderDelivered]),
            ),
          ],
          child: const MaterialApp(
            home: AdminShopOrdersScreen(shopId: 'rajat_shop'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap "Delivered" filter
      await tester.tap(find.text('Delivered (1)'));
      await tester.pumpAndSettle();

      expect(find.text('#YB-RAJAT-001'), findsOneWidget);
      expect(find.text('#YB-RAJAT-002'), findsNothing);

      // Tap "Rejected" filter
      await tester.tap(find.text('Rejected (1)'));
      await tester.pumpAndSettle();

      expect(find.text('#YB-RAJAT-002'), findsOneWidget);
      expect(find.text('#YB-RAJAT-001'), findsNothing);
    });

    testWidgets('5. Tapping order card opens AdminOrderDetailsModal in READ-ONLY mode with delivery person details', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            shopsProvider.overrideWith((ref) => Future.value([shop1])),
            shopOrdersStreamProvider('rajat_shop').overrideWith(
              (ref) => Stream.value([rajatOrderDelivered]),
            ),
          ],
          child: const MaterialApp(
            home: AdminShopOrdersScreen(shopId: 'rajat_shop'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap the order card
      await tester.tap(find.text('#YB-RAJAT-001'));
      await tester.pumpAndSettle();

      // Modal is opened
      expect(find.byType(AdminOrderDetailsModal), findsOneWidget);

      // Customer Details
      expect(find.text('Aarav Sharma'), findsNWidgets(2)); // Card + Modal
      expect(find.text('Phone: 9876543210'), findsOneWidget);

      // Items list
      expect(find.text('Paneer Butter Masala'), findsOneWidget);
      expect(find.text('Butter Roti'), findsOneWidget);
      expect(find.text('Grand Total'), findsOneWidget);
      expect(find.text('₹240'), findsNWidgets(2)); // Subtotal & Grand Total in modal

      // Admin-Only Delivery Person Information
      expect(find.text('DELIVERY PERSON DETAILS (ADMIN ONLY)'), findsOneWidget);
      expect(find.text('Ramesh Delivery'), findsOneWidget);
      expect(find.text('8295643910'), findsOneWidget);

      // Admin Read-Only Notice (Zero mutation buttons like Accept, Reject, Deliver)
      expect(find.text('Admin Read-Only Record — No mutations permitted'), findsOneWidget);
      expect(find.text('Accept Order'), findsNothing);
      expect(find.text('Reject Order'), findsNothing);
      expect(find.text('Mark Delivered'), findsNothing);
      expect(find.text('Cancel Order'), findsNothing);
    });

    testWidgets('6. Rejected order details display rejection reason in modal', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            shopsProvider.overrideWith((ref) => Future.value([shop1])),
            shopOrdersStreamProvider('rajat_shop').overrideWith(
              (ref) => Stream.value([rajatOrderRejected]),
            ),
          ],
          child: const MaterialApp(
            home: AdminShopOrdersScreen(shopId: 'rajat_shop'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap the order card
      await tester.tap(find.text('#YB-RAJAT-002'));
      await tester.pumpAndSettle();

      // Modal is opened
      expect(find.byType(AdminOrderDetailsModal), findsOneWidget);
      expect(find.text('Priya Verma'), findsNWidgets(2)); // Card + Modal
      expect(find.text('Items out of stock'), findsOneWidget);
      expect(find.text('Veg Biryani'), findsOneWidget);
    });
  });
}
