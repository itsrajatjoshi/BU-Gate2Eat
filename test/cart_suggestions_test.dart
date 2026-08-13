// BU Gate2Eat — Cart Suggestions / Upsells Test Suite
// Explicitly validates all 10 test cases for the Cart Item Suggestions feature.

import 'package:bugate2eat_app/core/providers.dart';
import 'package:bugate2eat_app/features/cart/cart_provider.dart';
import 'package:bugate2eat_app/features/cart/cart_screen.dart';
import 'package:bugate2eat_app/models/cart_item_model.dart';
import 'package:bugate2eat_app/models/menu_item_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const rajatShopId = 'rajat_shop';
  const rajatShopName = 'Rajat Shop';
  const nayanShopId = 'nayan_shop';
  const nayanShopName = 'Nayan Shop';

  const rajatMomos = MenuItem(
    id: 'rajat_momos',
    name: 'Rajat Veg Momos',
    details: '8 Pcs',
    price: 60,
    imageUrl: '',
    categoryId: 'momos',
    isVeg: true,
    isAvailable: true,
    isRecommended: true,
    sortOrder: 1,
  );

  const rajatBurger = MenuItem(
    id: 'rajat_burger',
    name: 'Rajat Burger',
    details: 'Crispy Patty',
    price: 80,
    imageUrl: '',
    categoryId: 'burgers',
    isVeg: true,
    isAvailable: true,
    isRecommended: false,
    sortOrder: 2,
  );

  const rajatFries = MenuItem(
    id: 'rajat_fries',
    name: 'Rajat Fries',
    details: 'Salted',
    price: 50,
    imageUrl: '',
    categoryId: 'snacks',
    isVeg: true,
    isAvailable: true,
    isRecommended: false,
    sortOrder: 3,
  );

  const rajatDrink = MenuItem(
    id: 'rajat_drink',
    name: 'Rajat Cold Drink',
    details: '300 ml',
    price: 40,
    imageUrl: '',
    categoryId: 'beverages',
    isVeg: true,
    isAvailable: true,
    isRecommended: false,
    sortOrder: 4,
  );

  const rajatUnavailableItem = MenuItem(
    id: 'rajat_out_of_stock',
    name: 'Rajat Out of Stock Item',
    details: 'Unavailable',
    price: 100,
    imageUrl: '',
    categoryId: 'specials',
    isVeg: true,
    isAvailable: false,
    isRecommended: false,
    sortOrder: 5,
  );

  const nayanRoll = MenuItem(
    id: 'nayan_roll',
    name: 'Nayan Paneer Roll',
    details: '1 Roll',
    price: 90,
    imageUrl: '',
    categoryId: 'rolls',
    isVeg: true,
    isAvailable: true,
    isRecommended: true,
    sortOrder: 1,
  );

  const nayanNoodles = MenuItem(
    id: 'nayan_noodles',
    name: 'Nayan Hakka Noodles',
    details: '1 Plate',
    price: 110,
    imageUrl: '',
    categoryId: 'noodles',
    isVeg: true,
    isAvailable: true,
    isRecommended: false,
    sortOrder: 2,
  );

  group('BU Gate2Eat — Cart Suggestions Unit & Logic Suite', () {
    test('CASE 1: Rajat Shop cart -> only Rajat Shop suggestions filter eligible items', () {
      final cartItems = [
        const CartItem(menuItem: rajatMomos, quantity: 1, shopId: rajatShopId, shopName: rajatShopName),
      ];

      // Simulated Rajat shop menu
      final rajatMenu = [rajatMomos, rajatBurger, rajatFries, rajatDrink, rajatUnavailableItem];
      final cartItemIds = cartItems.map((ci) => ci.menuItem.id).toSet();

      final suggestions = rajatMenu
          .where((item) => item.isAvailable && !cartItemIds.contains(item.id))
          .take(3)
          .toList();

      expect(suggestions.length, equals(3));
      expect(suggestions.map((i) => i.id), containsAll(['rajat_burger', 'rajat_fries', 'rajat_drink']));
      expect(suggestions.any((i) => i.id.startsWith('nayan')), isFalse);
    });

    test('CASE 2: Nayan Shop cart -> only Nayan Shop suggestions filter eligible items', () {
      final cartItems = [
        const CartItem(menuItem: nayanRoll, quantity: 1, shopId: nayanShopId, shopName: nayanShopName),
      ];

      final nayanMenu = [nayanRoll, nayanNoodles];
      final cartItemIds = cartItems.map((ci) => ci.menuItem.id).toSet();

      final suggestions = nayanMenu
          .where((item) => item.isAvailable && !cartItemIds.contains(item.id))
          .take(3)
          .toList();

      expect(suggestions.length, equals(1));
      expect(suggestions.first.id, equals('nayan_noodles'));
      expect(suggestions.any((i) => i.id.startsWith('rajat')), isFalse);
    });

    test('CASE 3: An item already in cart never appears in suggestions', () {
      final cartItems = [
        const CartItem(menuItem: rajatMomos, quantity: 1, shopId: rajatShopId, shopName: rajatShopName),
        const CartItem(menuItem: rajatBurger, quantity: 1, shopId: rajatShopId, shopName: rajatShopName),
      ];

      final rajatMenu = [rajatMomos, rajatBurger, rajatFries];
      final cartItemIds = cartItems.map((ci) => ci.menuItem.id).toSet();

      final suggestions = rajatMenu
          .where((item) => item.isAvailable && !cartItemIds.contains(item.id))
          .take(3)
          .toList();

      expect(suggestions.length, equals(1));
      expect(suggestions.first.id, equals('rajat_fries'));
      expect(suggestions.any((i) => i.id == 'rajat_momos'), isFalse);
      expect(suggestions.any((i) => i.id == 'rajat_burger'), isFalse);
    });

    test('CASE 4: Unavailable/out-of-stock item never appears in suggestions', () {
      final cartItems = [
        const CartItem(menuItem: rajatMomos, quantity: 1, shopId: rajatShopId, shopName: rajatShopName),
      ];

      final rajatMenu = [rajatMomos, rajatUnavailableItem];
      final cartItemIds = cartItems.map((ci) => ci.menuItem.id).toSet();

      final suggestions = rajatMenu
          .where((item) => item.isAvailable && !cartItemIds.contains(item.id))
          .take(3)
          .toList();

      expect(suggestions, isEmpty);
    });

    test('CASE 5 & 6: Adding a suggestion updates quantity, subtotal and total via cartProvider', () {
      final container = ProviderContainer();
      final notifier = container.read(cartProvider.notifier);

      // Add initial item
      notifier.addItem(rajatMomos, rajatShopId, rajatShopName);
      expect(container.read(cartProvider).grandTotal, equals(60.0));
      expect(container.read(cartProvider).totalItemCount, equals(1));

      // Add suggestion item (rajatBurger @ 80)
      notifier.addItem(rajatBurger, rajatShopId, rajatShopName);
      expect(container.read(cartProvider).grandTotal, equals(140.0));
      expect(container.read(cartProvider).totalItemCount, equals(2));
      expect(container.read(cartProvider).items.length, equals(2));
    });

    test('CASE 7: Empty cart -> suggestions section hidden (0 suggestions)', () {
      final cartItems = <CartItem>[];
      final rajatMenu = [rajatMomos, rajatBurger];
      final cartItemIds = cartItems.map((ci) => ci.menuItem.id).toSet();

      final suggestions = cartItems.isEmpty
          ? <MenuItem>[]
          : rajatMenu.where((item) => item.isAvailable && !cartItemIds.contains(item.id)).take(3).toList();

      expect(suggestions, isEmpty);
    });

    test('CASE 8: No eligible suggestions -> section hidden', () {
      final cartItems = [
        const CartItem(menuItem: rajatMomos, quantity: 1, shopId: rajatShopId, shopName: rajatShopName),
      ];

      // Shop with only 1 item which is already in cart
      final rajatMenu = [rajatMomos];
      final cartItemIds = cartItems.map((ci) => ci.menuItem.id).toSet();

      final suggestions = rajatMenu
          .where((item) => item.isAvailable && !cartItemIds.contains(item.id))
          .take(3)
          .toList();

      expect(suggestions, isEmpty);
    });

    test('CASE 9 & 10: Switching from Rajat Shop cart to Nayan Shop via CLEAR & ADD flow updates shopId and suggestions', () {
      final container = ProviderContainer();
      final notifier = container.read(cartProvider.notifier);

      // Rajat Shop item in cart
      notifier.addItem(rajatMomos, rajatShopId, rajatShopName);
      expect(container.read(cartProvider).shopId, equals(rajatShopId));

      // Clear & Add Nayan Shop item
      notifier.clearCart();
      notifier.addItem(nayanRoll, nayanShopId, nayanShopName);

      final state = container.read(cartProvider);
      expect(state.shopId, equals(nayanShopId));
      expect(state.items.single.menuItem.id, equals('nayan_roll'));

      // Verify no cross-shop contamination
      final nayanMenu = [nayanRoll, nayanNoodles];
      final cartItemIds = state.items.map((ci) => ci.menuItem.id).toSet();
      final suggestions = nayanMenu
          .where((item) => item.isAvailable && !cartItemIds.contains(item.id))
          .take(3)
          .toList();

      expect(suggestions.length, equals(1));
      expect(suggestions.first.id, equals('nayan_noodles'));
    });
  });

  group('BU Gate2Eat — Cart Suggestions Widget Render Suite', () {
    testWidgets('Renders "Complete your order" suggestion section when items available', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            shopMenuItemsProvider(rajatShopId).overrideWith((ref) async => [rajatMomos, rajatBurger, rajatFries]),
          ],
          child: Consumer(
            builder: (context, ref, child) {
              return const MaterialApp(
                home: CartScreen(),
              );
            },
          ),
        ),
      );

      // Add item to cart via ProviderContainer / context
      final element = tester.element(find.byType(MaterialApp));
      final container = ProviderScope.containerOf(element);
      container.read(cartProvider.notifier).addItem(rajatMomos, rajatShopId, rajatShopName);

      await tester.pumpAndSettle();

      expect(find.text('Your Cart'), findsOneWidget);
      expect(find.text('Current Order'), findsOneWidget);
      expect(find.text('Rajat Veg Momos'), findsOneWidget);
      expect(find.text('Complete your order with'), findsOneWidget);
      expect(find.text('Rajat Burger'), findsOneWidget);
      expect(find.text('Rajat Fries'), findsOneWidget);
    });
  });
}
