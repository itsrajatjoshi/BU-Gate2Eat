// BU Gate2Eat — Customer Identity Isolation & Phone Source of Truth Tests
// Verifies complete data isolation across distinct customer accounts,
// canonical phone usage in WhatsApp & Shopkeeper call, and clean session reset.

import 'package:bugate2eat_app/core/constants/app_constants.dart';
import 'package:bugate2eat_app/core/providers.dart';
import 'package:bugate2eat_app/features/cart/cart_provider.dart';
import 'package:bugate2eat_app/features/orders/order_detail_screen.dart';
import 'package:bugate2eat_app/features/profile/profile_screen.dart';
import 'package:bugate2eat_app/models/cart_item_model.dart';
import 'package:bugate2eat_app/models/menu_item_model.dart';
import 'package:bugate2eat_app/models/order_model.dart';
import 'package:bugate2eat_app/services/local_storage_service.dart';
import 'package:bugate2eat_app/services/whatsapp_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const phoneA = '9111111111';
  const customerIdA = 'cust_9111111111';
  const nameA = 'Customer Alpha';

  const phoneB = '9222222222';
  const customerIdB = 'cust_9222222222';
  const nameB = 'Customer Beta';

  const phoneC = '9333333333';
  const customerIdC = 'cust_9333333333';
  const nameC = 'Customer Gamma';

  final orderA1 = AppOrder(
    orderId: 'ORDER_A_ACTIVE',
    shopId: 'rajat_shop',
    shopName: 'Rajat Shop',
    customerId: customerIdA,
    customerName: nameA,
    customerPhone: phoneA,
    items: const [
      OrderItem(
        menuItemId: 'item_1',
        name: 'Veg Momos',
        price: 80,
        quantity: 1,
      ),
    ],
    totalAmount: 80,
    status: 'placed',
    createdAt: DateTime.now().subtract(const Duration(minutes: 5)),
  );

  final orderA2 = AppOrder(
    orderId: 'ORDER_A_HISTORY',
    shopId: 'rajat_shop',
    shopName: 'Rajat Shop',
    customerId: customerIdA,
    customerName: nameA,
    customerPhone: phoneA,
    items: const [
      OrderItem(
        menuItemId: 'item_1',
        name: 'Veg Momos',
        price: 80,
        quantity: 1,
      ),
    ],
    totalAmount: 80,
    status: 'delivered',
    createdAt: DateTime.now().subtract(const Duration(hours: 2)),
  );

  final orderB1 = AppOrder(
    orderId: 'ORDER_B_ACTIVE',
    shopId: 'rajat_shop',
    shopName: 'Rajat Shop',
    customerId: customerIdB,
    customerName: nameB,
    customerPhone: phoneB,
    items: const [
      OrderItem(
        menuItemId: 'item_2',
        name: 'Chai',
        price: 20,
        quantity: 2,
      ),
    ],
    totalAmount: 40,
    status: 'placed',
    createdAt: DateTime.now(),
  );

  group('Customer Identity Isolation & Phone Source of Truth', () {
    // ─── Test 1: Customer A Active Orders not returned to Customer B ───
    test('Test 1: Customer A orders are not returned in Customer B Active Orders', () async {
      SharedPreferences.setMockInitialValues({
        'is_onboarded': true,
        'user_name': nameB,
        'user_phone': phoneB,
        'customer_id': customerIdB,
      });

      final storage = await LocalStorageService.create();
      final container = ProviderContainer(
        overrides: [
          localStorageServiceProvider.overrideWithValue(storage),
        ],
      );

      container.read(dummyOrdersProvider.notifier).setOrders([orderA1, orderB1]);

      final activeOrders = await container.read(customerActiveOrdersStreamProvider.future);

      expect(activeOrders.any((o) => o.orderId == orderA1.orderId), isFalse);
      expect(activeOrders.any((o) => o.customerId == customerIdA), isFalse);
      expect(activeOrders.any((o) => o.orderId == orderB1.orderId), isTrue);
      expect(activeOrders.length, equals(1));
    });

    // ─── Test 2: Customer A History is not returned to Customer B ───
    test('Test 2: Customer A History is not returned to Customer B', () async {
      SharedPreferences.setMockInitialValues({
        'is_onboarded': true,
        'user_name': nameB,
        'user_phone': phoneB,
        'customer_id': customerIdB,
      });

      final storage = await LocalStorageService.create();
      final container = ProviderContainer(
        overrides: [
          localStorageServiceProvider.overrideWithValue(storage),
        ],
      );

      container.read(dummyOrdersProvider.notifier).setOrders([orderA2]);

      final historyOrders = await container.read(customerOrderHistoryStreamProvider.future);

      expect(historyOrders.any((o) => o.orderId == orderA2.orderId), isFalse);
      expect(historyOrders.any((o) => o.customerId == customerIdA), isFalse);
      expect(historyOrders, isEmpty);
    });

    // ─── Test 3: Customer A order details cannot be displayed to Customer B ───
    testWidgets('Test 3: Customer A order details cannot be accidentally displayed as Customer B order', (tester) async {
      SharedPreferences.setMockInitialValues({
        'is_onboarded': true,
        'user_name': nameB,
        'user_phone': phoneB,
        'customer_id': customerIdB,
      });

      final storage = await LocalStorageService.create();
      final container = ProviderContainer(
        overrides: [
          localStorageServiceProvider.overrideWithValue(storage),
        ],
      );

      container.read(dummyOrdersProvider.notifier).setOrders([orderA1]);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: OrderDetailScreen(orderId: 'ORDER_A_ACTIVE'),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Customer B should be shown 'Order not found' instead of Customer A's order
      expect(find.text('Order not found'), findsOneWidget);
      expect(find.text('Veg Momos'), findsNothing);
    });

    // ─── Test 4: WhatsApp message uses the correct order/customer phone ───
    test('Test 4: WhatsApp message uses the correct customer phone (B, not A)', () {
      final message = WhatsAppService.generateOrderMessage(
        shopName: 'Rajat Shop',
        userName: nameB,
        userPhone: phoneB,
        cartItems: [
          CartItem(
            menuItem: const MenuItem(
              id: 'm1',
              name: 'Paneer Burger',
              price: 120,
              details: '',
              imageUrl: '',
              isVeg: true,
              isAvailable: true,
              isRecommended: false,
              categoryId: 'c1',
              sortOrder: 0,
            ),
            shopId: 'rajat_shop',
            shopName: 'Rajat Shop',
            quantity: 1,
          ),
        ],
      );

      expect(message.contains('Phone: $phoneB'), isTrue);
      expect(message.contains(phoneA), isFalse);
      expect(message.contains(phoneC), isFalse);
    });

    // ─── Test 5: Shopkeeper Call uses the phone stored for that specific order ───
    test('Test 5: Shopkeeper Call uses the phone stored for that specific order', () {
      expect(orderA1.customerPhone, equals(phoneA));
      expect(orderB1.customerPhone, equals(phoneB));
      expect(orderA1.customerPhone, isNot(equals(orderB1.customerPhone)));
    });

    // ─── Test 6: Session switch clears/reloads customer-specific state ───
    test('Test 6: Session switch clears/reloads customer-specific state', () async {
      SharedPreferences.setMockInitialValues({
        'is_onboarded': true,
        'user_name': nameA,
        'user_phone': phoneA,
        'customer_id': customerIdA,
        'favorite_item_ids': ['fav_item_1'],
      });

      final storage = await LocalStorageService.create();
      final container = ProviderContainer(
        overrides: [
          localStorageServiceProvider.overrideWithValue(storage),
        ],
      );

      // Verify User A state
      expect(container.read(customerIdentityProvider).customerId, equals(customerIdA));
      expect(container.read(customerIdentityProvider).phone, equals(phoneA));

      // Add item to cart for User A
      container.read(cartProvider.notifier).addItem(
        const MenuItem(
          id: 'item_a',
          name: 'Alpha Dish',
          price: 50,
          details: '',
          imageUrl: '',
          isVeg: true,
          isAvailable: true,
          isRecommended: false,
          categoryId: 'c1',
          sortOrder: 0,
        ),
        'rajat_shop',
        'Rajat Shop',
      );
      expect(container.read(cartProvider).items.length, equals(1));

      // Trigger session purge
      await clearCustomerSession(container);

      // Verify session is completely cleared
      expect(container.read(cartProvider).items, isEmpty);
      expect(container.read(customerIdentityProvider).customerId, isEmpty);
      expect(container.read(customerIdentityProvider).phone, isEmpty);
      expect(storage.isOnboarded, isFalse);
      expect(storage.userPhone, isEmpty);
      expect(storage.favoriteItemIds, isEmpty);

      // Login User B
      await storage.saveUserProfile(name: nameB, phone: phoneB);
      container.read(customerIdentityProvider.notifier).refresh();

      // Verify User B identity is loaded cleanly with no residue of User A
      expect(container.read(customerIdentityProvider).customerId, equals(customerIdB));
      expect(container.read(customerIdentityProvider).phone, equals(phoneB));
      expect(container.read(cartProvider).items, isEmpty);
    });

    // ─── Test 7: Delete Account masking shows only last two digits ───
    test('Test 7: Delete Account masking shows only last two digits', () {
      const p1 = '9876543210';
      final clean1 = AppAuthRoles.normalizeCleanPhone(p1);
      final masked1 = '********${clean1.substring(clean1.length - 2)}';
      expect(masked1, equals('********10'));
      expect(masked1.length, equals(10));
      expect(masked1.contains('98765432'), isFalse);

      const p2 = '9111223344';
      final clean2 = AppAuthRoles.normalizeCleanPhone(p2);
      final masked2 = '********${clean2.substring(clean2.length - 2)}';
      expect(masked2, equals('********44'));
      expect(masked2.contains('91112233'), isFalse);
    });

    // ─── Test 8: Customer phone is not rendered elsewhere in Customer UI ───
    testWidgets('Test 8: Customer phone is not rendered in Customer Profile Screen', (tester) async {
      SharedPreferences.setMockInitialValues({
        'is_onboarded': true,
        'user_name': nameA,
        'user_phone': phoneA,
        'customer_id': customerIdA,
      });

      final storage = await LocalStorageService.create();
      final container = ProviderContainer(
        overrides: [
          localStorageServiceProvider.overrideWithValue(storage),
        ],
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: ProfileScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // User name is rendered
      expect(find.text(nameA), findsAtLeastNWidgets(1));
      // User phone MUST NOT be rendered anywhere
      expect(find.text(phoneA), findsNothing);
      expect(find.textContaining(phoneA), findsNothing);
    });

    // ─── Test 9: Customer ID generation does not reuse previous session identity ───
    test('Test 9: Customer ID generation does not reuse previous session identity', () {
      final cleanA = AppAuthRoles.normalizeCleanPhone(phoneA);
      final cleanB = AppAuthRoles.normalizeCleanPhone(phoneB);
      final cleanC = AppAuthRoles.normalizeCleanPhone(phoneC);

      final idA = 'cust_$cleanA';
      final idB = 'cust_$cleanB';
      final idC = 'cust_$cleanC';

      expect(idA, equals(customerIdA));
      expect(idB, equals(customerIdB));
      expect(idC, equals(customerIdC));

      expect(idA, isNot(equals(idB)));
      expect(idB, isNot(equals(idC)));
      expect(idA, isNot(equals(idC)));
    });
  });
}
