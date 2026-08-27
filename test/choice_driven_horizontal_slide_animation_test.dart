// BU Gate2Eat — Bug #3: Choice-Driven Horizontal List Slide Transition UI Tests
// Comprehensive verification of:
// 1. Choice buttons stay completely stationary at top.
// 2. The entire fixed-option list below them animates horizontally as ONE unit on EVERY choice tap.
// 3. Same-choice re-taps trigger the animation cycle again.
// 4. Optional choice ON/OFF each trigger animation.
// 5. Multiple Choice groups each trigger whole-list animation.
// 6. Manual horizontal swipe is impossible (programmatic transition only).
// 7. Pricing, variant generation, and cart integrity are 100% preserved.

import 'package:bugate2eat_app/core/providers.dart';
import 'package:bugate2eat_app/features/cart/cart_provider.dart';
import 'package:bugate2eat_app/features/shop/shop_detail_screen.dart';
import 'package:bugate2eat_app/models/menu_item_model.dart';
import 'package:bugate2eat_app/models/shop_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _TestFavoriteNotifier extends StateNotifier<Set<String>>
    implements FavoriteNotifier {
  _TestFavoriteNotifier() : super({});

  @override
  bool isFavorite(String itemId, [String? shopId]) {
    final key =
        (shopId != null && shopId.isNotEmpty) ? '$shopId:$itemId' : itemId;
    return state.contains(key);
  }

  @override
  Future<void> toggleFavorite(String itemId, [String? shopId]) async {
    final key =
        (shopId != null && shopId.isNotEmpty) ? '$shopId:$itemId' : itemId;
    if (state.contains(key)) {
      state = Set.from(state)..remove(key);
    } else {
      state = Set.from(state)..add(key);
    }
  }

  @override
  Future<void> clearFavorites() async {
    state = {};
  }
}

void main() {
  final now = DateTime.now();

  final dummyShop = Shop(
    id: 'up16_shop',
    name: 'UP16 Canteen',
    description: 'Campus Food & Beverages',
    bannerUrl: '',
    contactNumber: '9876543210',
    orderNumber: '9876543210',
    openTime: '08:00',
    closeTime: '23:30',
    isClosedOverride: false,
    isActive: true,
    sortOrder: 1,
    searchKeywords: const ['canteen', 'food'],
    deliveryNote: 'Gate 3',
    createdAt: now,
    updatedAt: now,
  );

  // UP16 Cold Coffee: Fixed Size options (Large ₹60, XL ₹80, Double XL ₹100) + Optional Choice (Ice Cream +₹10)
  const coldCoffee = MenuItem(
    id: 'item_cold_coffee',
    name: 'Normal Cold Coffee',
    price: 60,
    categoryId: 'cat_beverages',
    imageUrl: 'https://example.com/coffee.jpg',
    isVeg: true,
    isAvailable: true,
    isRecommended: true,
    sortOrder: 3,
    details: 'Rich chilled cold coffee',
    optionGroups: [
      MenuItemOptionGroup(
        id: 'grp_coffee_size',
        name: 'Size',
        options: [
          MenuItemOption(
            id: 'opt_coffee_large',
            name: 'Large',
            price: 60,
            isDefault: true,
          ),
          MenuItemOption(
            id: 'opt_coffee_xl',
            name: 'XL',
            price: 80,
          ),
          MenuItemOption(
            id: 'opt_coffee_xxl',
            name: 'Double XL',
            price: 100,
          ),
        ],
      ),
      MenuItemOptionGroup(
        id: 'grp_ice_cream',
        name: 'Ice Cream Addon',
        groupType: OptionGroupType.choice,
        required: false, // Optional
        options: [
          MenuItemOption(
            id: 'opt_with_ice_cream',
            name: 'With Ice Cream',
            pricingType: OptionPricingType.priceAdjustment,
            price: 10,
          ),
        ],
      ),
    ],
  );

  // Multi-Group Burger: Fixed Size options + Required Choice (Sauce) + Optional Choice (Cheese)
  const customizableBurger = MenuItem(
    id: 'item_burger',
    name: 'Veg Crisp Burger',
    price: 50,
    categoryId: 'cat_burgers',
    imageUrl: 'https://example.com/burger.jpg',
    isVeg: true,
    isAvailable: true,
    isRecommended: true,
    sortOrder: 2,
    details: 'Crispy patty with fresh veggies',
    optionGroups: [
      MenuItemOptionGroup(
        id: 'grp_size',
        name: 'Size',
        options: [
          MenuItemOption(
            id: 'opt_small',
            name: 'Small',
            price: 50,
            isDefault: true,
          ),
          MenuItemOption(
            id: 'opt_large',
            name: 'Large',
            price: 70,
          ),
        ],
      ),
      MenuItemOptionGroup(
        id: 'grp_sauce',
        name: 'Sauce',
        groupType: OptionGroupType.choice,
        options: [
          MenuItemOption(
            id: 'opt_with_sauce',
            name: 'With Sauce',
            pricingType: OptionPricingType.priceAdjustment,
            isDefault: true,
          ),
          MenuItemOption(
            id: 'opt_no_sauce',
            name: 'Without Sauce',
            pricingType: OptionPricingType.priceAdjustment,
          ),
        ],
      ),
      MenuItemOptionGroup(
        id: 'grp_cheese',
        name: 'Extra Cheese',
        groupType: OptionGroupType.choice,
        required: false,
        options: [
          MenuItemOption(
            id: 'opt_cheese',
            name: 'Cheese',
            pricingType: OptionPricingType.priceAdjustment,
            price: 10,
          ),
        ],
      ),
    ],
  );

  Widget createTestWidget(MenuItem item, {ProviderContainer? container}) {
    final app = MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) {
            return ElevatedButton(
              key: const ValueKey('open_sheet_btn'),
              onPressed: () {
                showItemDetailBottomSheet(
                  context: context,
                  item: item,
                  shop: dummyShop,
                  displayImageUrl: item.imageUrl,
                );
              },
              child: const Text('OPEN'),
            );
          },
        ),
      ),
    );

    if (container != null) {
      return UncontrolledProviderScope(
        container: container,
        child: app,
      );
    }

    return ProviderScope(
      overrides: [
        shopsProvider.overrideWith((ref) async => [dummyShop]),
        favoritesProvider.overrideWith((ref) => _TestFavoriteNotifier()),
      ],
      child: app,
    );
  }

  group('Bug #3 — Choice-Driven Horizontal Whole-List Slide Transition Suite', () {
    testWidgets('1. AnimatedSwitcher & SlideTransition present for fixed options list', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(createTestWidget(coldCoffee));
      await tester.tap(find.byKey(const ValueKey('open_sheet_btn')));
      await tester.pumpAndSettle();

      // Verify bottom sheet is open
      expect(find.text('Normal Cold Coffee'), findsOneWidget);
      expect(find.text('Large'), findsOneWidget);
      expect(find.text('XL'), findsOneWidget);
      expect(find.text('Double XL'), findsOneWidget);
      expect(find.text('With Ice Cream'), findsOneWidget);

      // Verify AnimatedSwitcher is present for the fixed options list
      expect(find.byType(AnimatedSwitcher), findsOneWidget);
    });

    testWidgets('2. Choice tap triggers horizontal slide animation on fixed list', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(createTestWidget(coldCoffee));
      await tester.tap(find.byKey(const ValueKey('open_sheet_btn')));
      await tester.pumpAndSettle();

      // Initial prices without ice cream: Large is ₹60 inside fixed option list
      expect(
        find.descendant(of: find.byType(AnimatedSwitcher), matching: find.text('₹60')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: find.byType(AnimatedSwitcher), matching: find.text('₹80')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: find.byType(AnimatedSwitcher), matching: find.text('₹100')),
        findsOneWidget,
      );

      // Tap 'With Ice Cream' (+₹10)
      await tester.tap(find.text('With Ice Cream'));
      // Pump mid-animation frame (100ms into 280ms duration)
      await tester.pump(const Duration(milliseconds: 100));

      // SlideTransition is actively animating
      expect(find.byType(SlideTransition), findsWidgets);

      // Settle animation
      await tester.pumpAndSettle();

      // New prices with Ice Cream: Large is ₹70, XL is ₹90, Double XL is ₹110
      expect(
        find.descendant(of: find.byType(AnimatedSwitcher), matching: find.text('₹70')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: find.byType(AnimatedSwitcher), matching: find.text('₹90')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: find.byType(AnimatedSwitcher), matching: find.text('₹110')),
        findsOneWidget,
      );
    });

    testWidgets('3. Same Choice re-tap MUST trigger the slide transition AGAIN', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(createTestWidget(coldCoffee));
      await tester.tap(find.byKey(const ValueKey('open_sheet_btn')));
      await tester.pumpAndSettle();

      // 1. Select 'With Ice Cream'
      await tester.tap(find.text('With Ice Cream'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: find.byType(AnimatedSwitcher), matching: find.text('₹70')),
        findsOneWidget,
      );

      // 2. Tap 'With Ice Cream' again (toggles optional off -> back to ₹60)
      await tester.tap(find.text('With Ice Cream'));
      await tester.pump(const Duration(milliseconds: 100));

      // Transition is active during deselect
      expect(find.byType(SlideTransition), findsWidgets);
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: find.byType(AnimatedSwitcher), matching: find.text('₹60')),
        findsOneWidget,
      );
    });

    testWidgets('4. Multi-Group Burger: Every choice tap triggers whole-list slide', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(createTestWidget(customizableBurger));
      await tester.tap(find.byKey(const ValueKey('open_sheet_btn')));
      await tester.pumpAndSettle();

      // Base without cheese: Small ₹50, Large ₹70
      expect(
        find.descendant(of: find.byType(AnimatedSwitcher), matching: find.text('₹50')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: find.byType(AnimatedSwitcher), matching: find.text('₹70')),
        findsOneWidget,
      );

      // Tap 'Cheese' (+₹10)
      await tester.tap(find.text('Cheese'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(SlideTransition), findsWidgets);
      await tester.pumpAndSettle();

      // Updated: Small ₹60, Large ₹80
      expect(
        find.descendant(of: find.byType(AnimatedSwitcher), matching: find.text('₹60')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: find.byType(AnimatedSwitcher), matching: find.text('₹80')),
        findsOneWidget,
      );

      // Tap 'Without Sauce'
      await tester.tap(find.text('Without Sauce'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(SlideTransition), findsWidgets);
      await tester.pumpAndSettle();

      // Tap 'Without Sauce' AGAIN (same choice)
      await tester.tap(find.text('Without Sauce'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(SlideTransition), findsWidgets);
      await tester.pumpAndSettle();

      // Prices remain consistent: Small ₹60, Large ₹80
      expect(
        find.descendant(of: find.byType(AnimatedSwitcher), matching: find.text('₹60')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: find.byType(AnimatedSwitcher), matching: find.text('₹80')),
        findsOneWidget,
      );
    });

    testWidgets('5. Choice controls remain stationary (outside AnimatedSwitcher)', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(createTestWidget(coldCoffee));
      await tester.tap(find.byKey(const ValueKey('open_sheet_btn')));
      await tester.pumpAndSettle();

      // Find the Choice button widget
      final choiceButton = find.text('With Ice Cream');
      expect(choiceButton, findsOneWidget);

      // Verify the Choice button is NOT a descendant of AnimatedSwitcher
      final choiceUnderAnimatedSwitcher = find.descendant(
        of: find.byType(AnimatedSwitcher),
        matching: find.text('With Ice Cream'),
      );
      expect(choiceUnderAnimatedSwitcher, findsNothing);
    });

    testWidgets('6. Manual horizontal swipe is disabled (No horizontal drag response)', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(createTestWidget(coldCoffee));
      await tester.tap(find.byKey(const ValueKey('open_sheet_btn')));
      await tester.pumpAndSettle();

      final initialPosition = tester.getTopLeft(find.text('Large'));

      // Attempt to drag horizontally left on the fixed list
      await tester.drag(find.text('Large'), const Offset(-200, 0));
      await tester.pump();

      final positionAfterDrag = tester.getTopLeft(find.text('Large'));
      // Position has NOT moved horizontally from manual swipe
      expect(positionAfterDrag.dx, initialPosition.dx);
    });

    testWidgets('7. Adding item from animated fixed row adds exact variant to cart', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final container = ProviderContainer(
        overrides: [
          shopsProvider.overrideWith((ref) async => [dummyShop]),
          favoritesProvider.overrideWith((ref) => _TestFavoriteNotifier()),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(createTestWidget(coldCoffee, container: container));
      await tester.tap(find.byKey(const ValueKey('open_sheet_btn')));
      await tester.pumpAndSettle();

      // 1. Select 'With Ice Cream'
      await tester.tap(find.text('With Ice Cream'));
      await tester.pumpAndSettle();

      // 2. Find the ADD button for Large (₹70)
      final addButtons = find.widgetWithText(InkWell, 'ADD');
      expect(addButtons, findsWidgets);

      // Tap first ADD button (Large + Ice Cream)
      await tester.tap(addButtons.first);
      await tester.pumpAndSettle();

      // Verify cart state
      final cart = container.read(cartProvider);
      expect(cart.items.length, 1);
      expect(cart.items.first.unitPrice, 70.0);
      expect(cart.items.first.optionsDescription, 'Large · With Ice Cream');
      expect(cart.grandTotal, 70.0);
    });

    testWidgets('8. Rapid consecutive choice taps update latest selection state safely', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(createTestWidget(customizableBurger));
      await tester.tap(find.byKey(const ValueKey('open_sheet_btn')));
      await tester.pumpAndSettle();

      // Rapid taps without pumpAndSettle between them
      await tester.tap(find.text('Cheese'));
      await tester.pump(const Duration(milliseconds: 20));
      await tester.tap(find.text('Without Sauce'));
      await tester.pump(const Duration(milliseconds: 20));
      await tester.tap(find.text('With Sauce'));
      await tester.pump(const Duration(milliseconds: 20));
      await tester.tap(find.text('Cheese')); // Toggles off
      await tester.pump(const Duration(milliseconds: 20));

      await tester.pumpAndSettle();

      // Final state: With Sauce, No Cheese -> Small is ₹50, Large is ₹70
      expect(
        find.descendant(of: find.byType(AnimatedSwitcher), matching: find.text('₹50')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: find.byType(AnimatedSwitcher), matching: find.text('₹70')),
        findsOneWidget,
      );
    });

    testWidgets('9. Required Choice group cannot become invalid on repeated taps', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(createTestWidget(customizableBurger));
      await tester.tap(find.byKey(const ValueKey('open_sheet_btn')));
      await tester.pumpAndSettle();

      // 'With Sauce' is selected by default in required group
      await tester.tap(find.text('With Sauce'));
      await tester.pumpAndSettle();

      // Selection must still be active and valid
      expect(
        find.descendant(of: find.byType(AnimatedSwitcher), matching: find.text('₹50')),
        findsOneWidget,
      );
    });

    testWidgets('10. Multi-variant cart coexistence is preserved after choice animation transitions', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final container = ProviderContainer(
        overrides: [
          shopsProvider.overrideWith((ref) async => [dummyShop]),
          favoritesProvider.overrideWith((ref) => _TestFavoriteNotifier()),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(createTestWidget(customizableBurger, container: container));
      await tester.tap(find.byKey(const ValueKey('open_sheet_btn')));
      await tester.pumpAndSettle();

      // 1. Add Small + With Sauce (No Cheese) = ₹50
      final addButtons = find.widgetWithText(InkWell, 'ADD');
      await tester.tap(addButtons.first); // Small
      await tester.pumpAndSettle();

      // 2. Select Cheese (+₹10) -> Fixed list animates
      await tester.tap(find.text('Cheese'));
      await tester.pumpAndSettle();

      // 3. Add Large + With Sauce + Cheese = ₹80
      final updatedAddButtons = find.widgetWithText(InkWell, 'ADD');
      await tester.tap(updatedAddButtons.last); // Large
      await tester.pumpAndSettle();

      // Verify cart contains 2 distinct variant rows
      final cart = container.read(cartProvider);
      expect(cart.items.length, 2);
      expect(cart.items[0].unitPrice, 50.0);
      expect(cart.items[0].optionsDescription, 'Small · With Sauce');
      expect(cart.items[1].unitPrice, 80.0);
      expect(cart.items[1].optionsDescription, 'Large · With Sauce · Cheese');
      expect(cart.grandTotal, 130.0);
    });
  });
}
