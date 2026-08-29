// BU Gate2Eat — Checkpoint 3.4 Unit & Widget Tests
// Tests for Dynamic Food Type Indicators and Shop Details Bottom Sheet

import 'package:bugate2eat_app/core/constants/app_constants.dart';
import 'package:bugate2eat_app/features/shop/widgets/shop_detail_bottom_sheet.dart';
import 'package:bugate2eat_app/models/menu_item_model.dart';
import 'package:bugate2eat_app/models/shop_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final testShop = Shop(
    id: 'rajat_shop',
    name: 'Rajat Shop',
    description: 'At Rajat Shop, we serve a wide variety of delicious food prepared with fresh ingredients and authentic flavours. Great taste, best quality and royal experience!',
    bannerUrl: 'https://example.com/banner.jpg',
    contactNumber: '9910707219',
    orderNumber: '9319566645',
    openTime: '08:00',
    closeTime: '23:30',
    isClosedOverride: false,
    isActive: true,
    sortOrder: 1,
    searchKeywords: ['rajat', 'food', 'momo'],
    deliveryNote: 'Pickup from Gate 3',
    createdAt: DateTime(2025, 1, 1),
    updatedAt: DateTime(2025, 1, 1),
  );

  final up16CoffeeQueen = Shop(
    id: 'up16_coffee_queen',
    name: 'UP16 Coffee Queen',
    description: 'Sip Happiness, Stay Awesome',
    bannerUrl: '',
    contactNumber: '8295643910',
    orderNumber: '8295643910',
    openTime: '08:00',
    closeTime: '01:30',
    isClosedOverride: false,
    isActive: true,
    sortOrder: 2,
    searchKeywords: ['coffee', 'tea', 'shake'],
    deliveryNote: 'Pickup from Gate 3',
    createdAt: DateTime(2025, 1, 1),
    updatedAt: DateTime(2025, 1, 1),
  );

  MenuItem createItem({
    required String id,
    required String name,
    required bool isVeg,
    int price = 100,
  }) {
    return MenuItem(
      id: id,
      name: name,
      details: 'Test description',
      price: price,
      imageUrl: '',
      categoryId: 'cat_1',
      isVeg: isVeg,
      isAvailable: true,
      isRecommended: false,
      sortOrder: 1,
      optionGroups: const [],
    );
  }

  group('Checkpoint 3.4 — Dynamic Food Type Indicator Tests', () {
    testWidgets('1. Pure Veg shop (e.g. UP16 Coffee Queen) displays ONLY Veg', (tester) async {
      final vegItems = [
        createItem(id: 'c1', name: 'Cold Coffee', isVeg: true),
        createItem(id: 'c2', name: 'Hot Chocolate', isVeg: true),
        createItem(id: 'c3', name: 'Oreo Shake', isVeg: true),
      ];

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: ThemeData.light(),
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => showShopDetailBottomSheet(
                    context: context,
                    shop: up16CoffeeQueen,
                    menuItems: vegItems,
                  ),
                  child: const Text('Open UP16'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open UP16'));
      await tester.pumpAndSettle();

      expect(find.text('UP16 Coffee Queen'), findsOneWidget);
      expect(find.text('Veg'), findsOneWidget);
      expect(find.text('Non-Veg'), findsNothing);
      expect(find.text('|'), findsNothing);
    });

    testWidgets('2. Pure Non-Veg shop displays ONLY Non-Veg', (tester) async {
      final nonVegItems = [
        createItem(id: 'n1', name: 'Chicken Biryani', isVeg: false),
        createItem(id: 'n2', name: 'Mutton Curry', isVeg: false),
      ];

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: ThemeData.light(),
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => showShopDetailBottomSheet(
                    context: context,
                    shop: testShop,
                    menuItems: nonVegItems,
                  ),
                  child: const Text('Open NonVeg Shop'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open NonVeg Shop'));
      await tester.pumpAndSettle();

      expect(find.text('Non-Veg'), findsOneWidget);
      expect(find.text('Veg'), findsNothing);
      expect(find.text('|'), findsNothing);
    });

    testWidgets('3. Mixed shop with both Veg and Non-Veg displays BOTH', (tester) async {
      final mixedItems = [
        createItem(id: 'm1', name: 'Veg Chowmein', isVeg: true),
        createItem(id: 'm2', name: 'Chicken Chowmein', isVeg: false),
      ];

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: ThemeData.light(),
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => showShopDetailBottomSheet(
                    context: context,
                    shop: testShop,
                    menuItems: mixedItems,
                  ),
                  child: const Text('Open Mixed Shop'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Mixed Shop'));
      await tester.pumpAndSettle();

      expect(find.text('Veg'), findsOneWidget);
      expect(find.text('Non-Veg'), findsOneWidget);
      expect(find.text('|'), findsOneWidget);
    });

    testWidgets('4. Third food type choices (Chinese, Egg, etc.) NEVER exist', (tester) async {
      final mixedItems = [
        createItem(id: 'm1', name: 'Veg Momo', isVeg: true),
        createItem(id: 'm2', name: 'Chicken Momo', isVeg: false),
      ];

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: ThemeData.light(),
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => showShopDetailBottomSheet(
                    context: context,
                    shop: testShop,
                    menuItems: mixedItems,
                  ),
                  child: const Text('Open Sheet'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Sheet'));
      await tester.pumpAndSettle();

      expect(find.text('Chinese'), findsNothing);
      expect(find.text('Egg'), findsNothing);
      expect(find.text('Mixed'), findsNothing);
      expect(find.text('All'), findsNothing);
    });

    testWidgets('5. Menu Categories and Pickup Information are completely absent', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: ThemeData.light(),
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => showShopDetailBottomSheet(
                    context: context,
                    shop: testShop,
                  ),
                  child: const Text('Open Sheet'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Sheet'));
      await tester.pumpAndSettle();

      expect(find.text('Categories'), findsNothing);
      expect(find.text('Ande Ka Fanda'), findsNothing);
      expect(find.text('Pickup Information'), findsNothing);
      expect(find.text('Pickup from Gate 3'), findsNothing);
      expect(find.textContaining('Where cravings get royal treatment'), findsNothing);
    });

    testWidgets('6. Top-right call button exists and Back button dismisses cleanly', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: ThemeData.light(),
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => showShopDetailBottomSheet(
                    context: context,
                    shop: testShop,
                  ),
                  child: const Text('Open Sheet'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Sheet'));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.call_rounded), findsOneWidget);
      expect(find.text('Rajat Shop'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.arrow_back_rounded));
      await tester.pumpAndSettle();

      expect(find.text('Rajat Shop'), findsNothing);
      expect(find.text('Open Sheet'), findsOneWidget);
    });
  });
}
