// BU Gate2Eat — Shopkeeper Orders, Details, Rejection, Acceptance & Delivery Flow Test Suite (Phase 2 — Part 2.1 - 2.5)

import 'package:bugate2eat_app/core/providers.dart';
import 'package:bugate2eat_app/features/orders/active_orders_screen.dart';
import 'package:bugate2eat_app/features/orders/order_detail_screen.dart';
import 'package:bugate2eat_app/features/orders/order_history_screen.dart';
import 'package:bugate2eat_app/models/order_model.dart';
import 'package:bugate2eat_app/panel/shopkeeper_panel/shopkeeper_order_history_screen.dart';
import 'package:bugate2eat_app/panel/shopkeeper_panel/shopkeeper_orders_screen.dart';
import 'package:bugate2eat_app/panel/shopkeeper_panel/widgets/accept_order_dialog.dart';
import 'package:bugate2eat_app/panel/shopkeeper_panel/widgets/mark_delivered_dialog.dart';
import 'package:bugate2eat_app/panel/shopkeeper_panel/widgets/reject_order_dialog.dart';
import 'package:bugate2eat_app/panel/shopkeeper_panel/widgets/shopkeeper_order_details_modal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Shopkeeper Complete Orders Lifecycle Suite (Part 2.1 to 2.5)', () {
    late ProviderContainer container;
    final now = DateTime.now();

    final orderRajatPlaced = AppOrder(
      orderId: 'YB-RAJ-01',
      shopId: 'rajat_shop',
      shopName: 'Rajat Shop',
      customerName: 'Aarav Sharma',
      customerPhone: '9876543210',
      items: const [
        OrderItem(
          menuItemId: 'momos',
          name: 'Veg Steam Momos',
          price: 60,
          quantity: 2,
        ),
        OrderItem(
          menuItemId: 'chai',
          name: 'Masala Chai',
          price: 20,
          quantity: 1,
        ),
      ],
      totalAmount: 140,
      specialInstructions: 'Make it extra spicy please',
      status: 'placed',
      createdAt: now.subtract(const Duration(minutes: 5)),
    );

    final orderRajatAccepted = AppOrder(
      orderId: 'YB-RAJ-02',
      shopId: 'rajat_shop',
      shopName: 'Rajat Shop',
      customerName: 'Priya Singh',
      customerPhone: '9876543211',
      items: const [
        OrderItem(
          menuItemId: 'burger',
          name: 'Crispy Paneer Burger',
          price: 120,
          quantity: 1,
        ),
      ],
      totalAmount: 120,
      specialInstructions: '',
      status: 'accepted',
      createdAt: now.subtract(const Duration(minutes: 2)),
    );

    setUp(() {
      container = ProviderContainer();
    });

    testWidgets('Part 2.1 & 2.2: Lists active orders & opens bottom sheet',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      container.read(dummyOrdersProvider.notifier).addOrder(orderRajatPlaced);
      container.read(dummyOrdersProvider.notifier).addOrder(orderRajatAccepted);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: ShopkeeperOrdersScreen(shopId: 'rajat_shop'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Active Orders'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);

      // Tap Aarav's card
      await tester.tap(find.text('Aarav Sharma'));
      await tester.pumpAndSettle();

      expect(find.byType(ShopkeeperOrderDetailsModal), findsOneWidget);
      expect(find.text('Order #YB-RAJ-01'), findsWidgets);
      expect(find.text('9876543210'), findsOneWidget);
      expect(find.text('Special Instructions'), findsOneWidget);
    });

    testWidgets(
        'Part 2.3: Rejecting PLACED order with predefined reason updates state and removes order from active list',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      container.read(dummyOrdersProvider.notifier).addOrder(orderRajatPlaced);
      container.read(dummyOrdersProvider.notifier).addOrder(orderRajatAccepted);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: ShopkeeperOrdersScreen(shopId: 'rajat_shop'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open Aarav's bottom sheet
      await tester.tap(find.text('Aarav Sharma'));
      await tester.pumpAndSettle();

      // Tap Reject button in bottom sheet
      await tester.tap(find.widgetWithText(OutlinedButton, 'Reject'));
      await tester.pumpAndSettle();

      // Verify RejectOrderDialog is displayed
      expect(find.byType(RejectOrderDialog), findsOneWidget);
      expect(find.text('Reject Order?'), findsOneWidget);

      // Select 'Shop closed early'
      await tester.tap(find.text('Shop closed early'));
      await tester.pumpAndSettle();

      // Confirm rejection
      await tester.tap(find.widgetWithText(ElevatedButton, 'Reject Order'));
      await tester.pumpAndSettle();

      // Verify order is updated in state
      final updatedOrder =
          container.read(dummyOrdersProvider.notifier).getOrder('YB-RAJ-01');
      expect(updatedOrder?.status, equals('rejected'));
      expect(updatedOrder?.rejectionReason, equals('Shop closed early'));

      // Verify rejected order is removed from Active Orders list
      expect(find.text('Aarav Sharma'), findsNothing);
      expect(find.text('1'), findsOneWidget); // Only Priya remains active
      expect(find.text('Priya Singh'), findsOneWidget);
    });

    testWidgets(
        'Part 2.4: Accepting PLACED order transitions status to ACCEPTED, remains in Active Orders',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      container.read(dummyOrdersProvider.notifier).addOrder(orderRajatPlaced);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: ShopkeeperOrdersScreen(shopId: 'rajat_shop'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open Aarav's bottom sheet
      await tester.tap(find.text('Aarav Sharma'));
      await tester.pumpAndSettle();

      // Tap Accept Order
      await tester.tap(find.widgetWithText(ElevatedButton, 'Accept Order'));
      await tester.pumpAndSettle();

      // Confirm Accept in Dialog
      await tester.tap(
        find.descendant(
          of: find.byType(AcceptOrderDialog),
          matching: find.widgetWithText(ElevatedButton, 'Accept Order'),
        ),
      );
      await tester.pumpAndSettle();

      // Verify state in dummyOrdersProvider
      final updatedAarav =
          container.read(dummyOrdersProvider.notifier).getOrder('YB-RAJ-01');
      expect(updatedAarav?.status, equals('accepted'));

      // Verify still in Active Orders list
      expect(find.text('Active Orders'), findsOneWidget);
      expect(find.text('ACCEPTED'), findsOneWidget);
    });

    testWidgets(
        'Part 2.5: Marking ACCEPTED order as DELIVERED moves order to History and synchronizes with customer panel',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      container.read(dummyOrdersProvider.notifier).addOrder(orderRajatPlaced);
      container.read(dummyOrdersProvider.notifier).addOrder(orderRajatAccepted);

      // 1. Open Shopkeeper Active Orders Screen
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: ShopkeeperOrdersScreen(shopId: 'rajat_shop'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open Priya's accepted order modal
      await tester.tap(find.text('Priya Singh'));
      await tester.pumpAndSettle();

      // Verify Mark as Delivered button is present
      final markDeliveredBtn =
          find.widgetWithText(ElevatedButton, 'Mark as Delivered');
      expect(markDeliveredBtn, findsOneWidget);

      // Tap Mark as Delivered
      await tester.tap(markDeliveredBtn);
      await tester.pumpAndSettle();

      // Verify MarkDeliveredDialog opens
      expect(find.byType(MarkDeliveredDialog), findsOneWidget);
      expect(find.text('Mark as Delivered?'), findsOneWidget);
      expect(
        find.text(
            'Confirm that this order has been completed and delivered to the customer.'),
        findsOneWidget,
      );

      // Confirm delivery in dialog
      await tester.tap(
        find.descendant(
          of: find.byType(MarkDeliveredDialog),
          matching: find.widgetWithText(ElevatedButton, 'Mark as Delivered'),
        ),
      );
      await tester.pumpAndSettle();

      // Verify local state updated
      final updatedPriya =
          container.read(dummyOrdersProvider.notifier).getOrder('YB-RAJ-02');
      expect(updatedPriya?.status, equals('delivered'));

      // Verify Priya is now REMOVED from Shopkeeper Active Orders
      expect(find.text('Priya Singh'), findsNothing);
      expect(find.text('1'), findsOneWidget); // Aarav (placed) is still active
      expect(find.text('Aarav Sharma'), findsOneWidget);

      // 2. Open Shopkeeper Order History Screen
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: ShopkeeperOrderHistoryScreen(shopId: 'rajat_shop'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify Priya appears in Shopkeeper Order History with DELIVERED badge
      expect(find.text('Past Orders'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      expect(find.text('Priya Singh'), findsOneWidget);
      expect(find.text('DELIVERED'), findsOneWidget);
      expect(find.text('Order #YB-RAJ-02'), findsOneWidget);

      // Tap delivered order card in history to verify read-only modal
      await tester.tap(find.text('Priya Singh'));
      await tester.pumpAndSettle();

      expect(find.byType(ShopkeeperOrderDetailsModal), findsOneWidget);
      expect(find.text('DELIVERED'), findsWidgets);
      // Verify no action buttons (read-only)
      expect(find.widgetWithText(ElevatedButton, 'Accept Order'), findsNothing);
      expect(find.widgetWithText(ElevatedButton, 'Mark as Delivered'),
          findsNothing);
      expect(find.widgetWithText(OutlinedButton, 'Reject'), findsNothing);
      expect(find.widgetWithText(OutlinedButton, 'Reject Order'), findsNothing);

      // Close modal
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();

      // 3. Customer Side Synchronization Check
      // Customer Active Orders: Priya removed, Aarav still active
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: ActiveOrdersScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Priya Singh'), findsNothing);
      expect(find.text('Order #YB-RAJ-02'), findsNothing);
      expect(find.text('Order #YB-RAJ-01'), findsOneWidget);

      // Customer Order History: Priya appears with Reorder button
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: OrderHistoryScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Order #YB-RAJ-02'), findsOneWidget);
      expect(find.textContaining('DELIVERED'), findsOneWidget);
      expect(find.text('Reorder'), findsOneWidget);

      // Customer Order Detail: Stepper shows Delivered
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: OrderDetailScreen(orderId: 'YB-RAJ-02'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Delivered'), findsWidgets);
    });

    testWidgets('Part 2.5: Cancelling MarkDeliveredDialog leaves order accepted',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      container.read(dummyOrdersProvider.notifier).addOrder(orderRajatAccepted);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: ShopkeeperOrdersScreen(shopId: 'rajat_shop'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open bottom sheet
      await tester.tap(find.text('Priya Singh'));
      await tester.pumpAndSettle();

      // Tap Mark as Delivered
      await tester.tap(find.widgetWithText(ElevatedButton, 'Mark as Delivered'));
      await tester.pumpAndSettle();

      // Cancel dialog
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      // Order should remain accepted
      final order =
          container.read(dummyOrdersProvider.notifier).getOrder('YB-RAJ-02');
      expect(order?.status, equals('accepted'));

      // Bottom sheet is still open
      expect(find.byType(ShopkeeperOrderDetailsModal), findsOneWidget);
    });
  });
}
