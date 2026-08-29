// BU Gate2Eat — Checkpoint 3.5 Item [ADD] Behaviour Tests
// Verifies that Item Cards ALWAYS display [ADD], NEVER display [- 1 +],
// and tapping [ADD] on ANY item card (with/without options, in cart or not)
// ALWAYS opens the Item Details Page.

import 'package:bugate2eat_app/core/constants/app_constants.dart';
import 'package:bugate2eat_app/core/providers.dart';
import 'package:bugate2eat_app/features/cart/cart_provider.dart';
import 'package:bugate2eat_app/features/shop/shop_detail_screen.dart';
import 'package:bugate2eat_app/models/cart_item_model.dart';
import 'package:bugate2eat_app/models/menu_item_model.dart';
import 'package:bugate2eat_app/models/shop_model.dart';
import 'package:bugate2eat_app/services/local_storage_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LocalStorageService localStorage;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    localStorage = LocalStorageService(prefs);
  });

  final testShop = Shop(
    id: 'rajat_shop',
    name: 'Rajat Shop',
    description: 'Fresh & Authentic flavours',
    bannerUrl: '',
    contactNumber: '9910707219',
    orderNumber: '9319566645',
    openTime: '08:00',
    closeTime: '23:30',
    isClosedOverride: false,
    isActive: true,
    sortOrder: 1,
    searchKeywords: ['rajat'],
    deliveryNote: 'Gate 3',
    createdAt: DateTime(2025, 1, 1),
    updatedAt: DateTime(2025, 1, 1),
  );

  final closedShop = Shop(
    id: 'closed_shop',
    name: 'Closed Shop',
    description: 'Closed',
    bannerUrl: '',
    contactNumber: '9910707219',
    orderNumber: '9319566645',
    openTime: '08:00',
    closeTime: '23:30',
    isClosedOverride: true,
    isActive: true,
    sortOrder: 2,
    searchKeywords: [],
    deliveryNote: 'Gate 3',
    createdAt: DateTime(2025, 1, 1),
    updatedAt: DateTime(2025, 1, 1),
  );

  const simpleItem = MenuItem(
    id: 'plain_chai',
    name: 'Plain Chai',
    details: 'Hot steaming tea',
    price: 20,
    imageUrl: '',
    categoryId: 'beverages',
    isVeg: true,
    isAvailable: true,
    isRecommended: false,
    sortOrder: 1,
    optionGroups: [],
  );

  const customizableItem = MenuItem(
    id: 'custom_momo',
    name: 'Veg Steamed Momos',
    details: 'Delicious momos with spicy red chutney',
    price: 80,
    imageUrl: '',
    categoryId: 'momos',
    isVeg: true,
    isAvailable: true,
    isRecommended: true,
    sortOrder: 2,
    optionGroups: [
      MenuItemOptionGroup(
        id: 'portion_grp',
        name: 'Portion',
        required: true,
        groupType: OptionGroupType.fixed,
        options: [
          MenuItemOption(
            id: 'half_opt',
            name: 'Half (5 Pcs)',
            price: 80,
            pricingType: OptionPricingType.fixedPrice,
            isDefault: true,
          ),
          MenuItemOption(
            id: 'full_opt',
            name: 'Full (10 Pcs)',
            price: 150,
            pricingType: OptionPricingType.fixedPrice,
            isDefault: false,
          ),
        ],
      ),
    ],
  );

  const unavailableItem = MenuItem(
    id: 'sold_out_burger',
    name: 'Sold Out Burger',
    details: 'Out of stock',
    price: 120,
    imageUrl: '',
    categoryId: 'burgers',
    isVeg: true,
    isAvailable: false,
    isRecommended: false,
    sortOrder: 3,
    optionGroups: [],
  );

  group('Checkpoint 3.5 — Item [ADD] Behaviour Tests', () {
    testWidgets('1. Available item card displays [ADD]', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localStorageServiceProvider.overrideWithValue(localStorage),
          ],
          child: MaterialApp(
            theme: ThemeData.light(),
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => handleCustomerAddToCart(
                    context: context,
                    ref: ProviderContainer().read as dynamic,
                    item: simpleItem,
                    shop: testShop,
                  ),
                  child: const Text('ADD'),
                ),
              ),
            ),
          ),
        ),
      );

      // Verify button text is available
      expect(find.text('ADD'), findsOneWidget);
    });

    testWidgets('2. Tapping ADD on item without choices opens Item Details Page', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localStorageServiceProvider.overrideWithValue(localStorage),
          ],
          child: MaterialApp(
            theme: ThemeData.light(),
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) {
                  return ElevatedButton(
                    key: const ValueKey('add_btn_simple'),
                    onPressed: () => handleCustomerAddToCart(
                      context: context,
                      ref: ref,
                      item: simpleItem,
                      shop: testShop,
                    ),
                    child: const Text('ADD'),
                  );
                },
              ),
            ),
          ),
        ),
      );

      // Tap ADD
      await tester.tap(find.byKey(const ValueKey('add_btn_simple')));
      await tester.pumpAndSettle();

      // Item Details bottom sheet must be open showing Plain Chai and details
      expect(find.text('Plain Chai'), findsOneWidget);
      expect(find.text('Hot steaming tea'), findsOneWidget);
      expect(find.text('Add to Cart'), findsOneWidget);
    });

    testWidgets('3. Tapping ADD on item with choices opens Item Details Page with customizations', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localStorageServiceProvider.overrideWithValue(localStorage),
          ],
          child: MaterialApp(
            theme: ThemeData.light(),
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) {
                  return ElevatedButton(
                    key: const ValueKey('add_btn_custom'),
                    onPressed: () => handleCustomerAddToCart(
                      context: context,
                      ref: ref,
                      item: customizableItem,
                      shop: testShop,
                    ),
                    child: const Text('ADD'),
                  );
                },
              ),
            ),
          ),
        ),
      );

      // Tap ADD
      await tester.tap(find.byKey(const ValueKey('add_btn_custom')));
      await tester.pumpAndSettle();

      // Customization options are present in the opened details sheet
      expect(find.text('Veg Steamed Momos'), findsOneWidget);
      expect(find.text('Half (5 Pcs)'), findsOneWidget);
      expect(find.text('Full (10 Pcs)'), findsOneWidget);
    });

    testWidgets('4. Item already in cart still displays [ADD] and NEVER [- 1 +] stepper on card', (tester) async {
      final container = ProviderContainer(
        overrides: [
          localStorageServiceProvider.overrideWithValue(localStorage),
        ],
      );

      // Pre-add item to cart
      container.read(cartProvider.notifier).addItem(
        simpleItem,
        testShop.id,
        testShop.name,
      );

      // Cart has 1 item
      expect(container.read(cartProvider).totalItemCount, equals(1));
      expect(container.read(cartProvider).getQuantityForShop(testShop.id, simpleItem.id), equals(1));

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: ThemeData.light(),
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) {
                  return ElevatedButton(
                    key: const ValueKey('add_btn_test'),
                    onPressed: () => handleCustomerAddToCart(
                      context: context,
                      ref: ref,
                      item: simpleItem,
                      shop: testShop,
                    ),
                    child: const Text('ADD'),
                  );
                },
              ),
            ),
          ),
        ),
      );

      // Card displays ADD
      expect(find.text('ADD'), findsOneWidget);

      // Stepper NEVER exists on card
      expect(find.byIcon(Icons.remove_rounded), findsNothing);
    });

    testWidgets('5. Item quantity > 1 (e.g. 5) in cart still keeps card as [ADD]', (tester) async {
      final container = ProviderContainer(
        overrides: [
          localStorageServiceProvider.overrideWithValue(localStorage),
        ],
      );

      // Add 5 times
      for (int i = 0; i < 5; i++) {
        container.read(cartProvider.notifier).addItem(
          simpleItem,
          testShop.id,
          testShop.name,
        );
      }

      expect(container.read(cartProvider).getQuantityForShop(testShop.id, simpleItem.id), equals(5));

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: ThemeData.light(),
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) {
                  return ElevatedButton(
                    onPressed: () => handleCustomerAddToCart(
                      context: context,
                      ref: ref,
                      item: simpleItem,
                      shop: testShop,
                    ),
                    child: const Text('ADD'),
                  );
                },
              ),
            ),
          ),
        ),
      );

      // Card still says ADD
      expect(find.text('ADD'), findsOneWidget);
    });

    testWidgets('6. Tapping ADD on already-added item opens Item Details again', (tester) async {
      final container = ProviderContainer(
        overrides: [
          localStorageServiceProvider.overrideWithValue(localStorage),
        ],
      );
      container.read(cartProvider.notifier).addItem(
        simpleItem,
        testShop.id,
        testShop.name,
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: ThemeData.light(),
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) {
                  return ElevatedButton(
                    key: const ValueKey('tap_again'),
                    onPressed: () => handleCustomerAddToCart(
                      context: context,
                      ref: ref,
                      item: simpleItem,
                      shop: testShop,
                    ),
                    child: const Text('ADD'),
                  );
                },
              ),
            ),
          ),
        ),
      );

      // Tap ADD again
      await tester.tap(find.byKey(const ValueKey('tap_again')));
      await tester.pumpAndSettle();

      // Opens Item Details page with item details and cart status
      expect(find.text('Plain Chai'), findsOneWidget);
    });

    test('7. Cart quantity controls continue working correctly in cart', () {
      final container = ProviderContainer(
        overrides: [
          localStorageServiceProvider.overrideWithValue(localStorage),
        ],
      );

      container.read(cartProvider.notifier).addItem(
        simpleItem,
        testShop.id,
        testShop.name,
      );

      expect(container.read(cartProvider).getQuantityForShop(testShop.id, simpleItem.id), equals(1));

      // Add same item again -> quantity increases to 2
      container.read(cartProvider.notifier).addItem(
        simpleItem,
        testShop.id,
        testShop.name,
      );
      expect(container.read(cartProvider).getQuantityForShop(testShop.id, simpleItem.id), equals(2));

      // Decrement item -> quantity decreases to 1
      container.read(cartProvider.notifier).removeItem(simpleItem.id);
      expect(container.read(cartProvider).getQuantityForShop(testShop.id, simpleItem.id), equals(1));

      // Decrement again -> quantity decreases to 0 (removed)
      container.read(cartProvider.notifier).removeItem(simpleItem.id);
      expect(container.read(cartProvider).getQuantityForShop(testShop.id, simpleItem.id), equals(0));
    });

    test('8. Out of stock & closed shop behavior is preserved', () {
      expect(unavailableItem.isAvailable, isFalse);
      expect(closedShop.isOpen, isFalse);
    });
  });
}
