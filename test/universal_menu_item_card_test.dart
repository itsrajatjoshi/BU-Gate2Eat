// BU Gate2Eat — Tests
// Universal Menu Item Card Comprehensive Invariant Test Suite
// Verifies single source of truth across Customer, Shopkeeper, and Admin perspectives.

import 'package:bugate2eat_app/core/constants/app_constants.dart';
import 'package:bugate2eat_app/core/providers.dart';
import 'package:bugate2eat_app/features/shop/widgets/universal_menu_item_card.dart';
import 'package:bugate2eat_app/models/category_model.dart';
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
    id: 'shop_test_1',
    name: 'UP16 Kitchen',
    description: 'Fresh Food',
    bannerUrl: 'https://cdn.yummbu.com/shops/up16.jpg',
    contactNumber: '9876543210',
    orderNumber: '9876543210',
    openTime: '10:00',
    closeTime: '22:00',
    isClosedOverride: false,
    isActive: true,
    sortOrder: 1,
    searchKeywords: ['up16'],
    deliveryNote: 'Gate 2',
    createdAt: DateTime(2025, 1, 1),
    updatedAt: DateTime(2025, 1, 1),
  );

  const vegItem = MenuItem(
    id: 'item_veg_momo',
    name: 'Steamed Veg Momos',
    price: 90,
    imageUrl: 'https://cdn.yummbu.com/items/momo.jpg',
    isVeg: true,
    isAvailable: true,
    isRecommended: false,
    sortOrder: 1,
    categoryId: 'cat_momo',
    details: 'Delicious steamed vegetable dumplings',
  );

  const nonVegItem = MenuItem(
    id: 'item_chicken_burger',
    name: 'Crispy Chicken Burger',
    price: 150,
    imageUrl: 'https://cdn.yummbu.com/items/burger.jpg',
    isVeg: false,
    isAvailable: true,
    isRecommended: false,
    sortOrder: 2,
    categoryId: 'cat_burger',
    details: 'Juicy chicken patty with spicy mayo',
  );

  const outOfStockItem = MenuItem(
    id: 'item_paneer_roll',
    name: 'Paneer Tikka Roll',
    price: 120,
    imageUrl: 'https://cdn.yummbu.com/items/roll.jpg',
    isVeg: true,
    isAvailable: false,
    isRecommended: false,
    sortOrder: 3,
    categoryId: 'cat_roll',
    details: 'Grilled paneer wrapped in flaky paratha',
  );

  final testCategories = [
    const Category(id: 'cat_momo', name: 'Momos', shopId: 'shop_test_1', sortOrder: 1),
    const Category(id: 'cat_burger', name: 'Burgers', shopId: 'shop_test_1', sortOrder: 2),
  ];

  Widget buildTestCard({
    required MenuItem item,
    Shop? shop,
    bool isShopOpen = true,
    ItemCardPerspective perspective = ItemCardPerspective.customer,
    VoidCallback? onTap,
    VoidCallback? onAction,
    String? actionButtonText,
    bool? showFavorite,
    List<Category>? categories,
  }) {
    return ProviderScope(
      overrides: [
        localStorageServiceProvider.overrideWithValue(localStorage),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 180,
              height: 260,
              child: UniversalMenuItemCard(
                item: item,
                shop: shop ?? testShop,
                isShopOpen: isShopOpen,
                perspective: perspective,
                onTap: onTap,
                onAction: onAction,
                actionButtonText: actionButtonText,
                showFavorite: showFavorite,
                categories: categories ?? testCategories,
              ),
            ),
          ),
        ),
      ),
    );
  }

  group('UniversalMenuItemCard — Perspective & Behavior Suite', () {
    testWidgets('1. Customer perspective renders item name, price, Veg icon, and ADD button', (tester) async {
      bool tapped = false;
      await tester.pumpWidget(
        buildTestCard(
          item: vegItem,
          perspective: ItemCardPerspective.customer,
          onTap: () => tapped = true,
        ),
      );

      expect(find.text('Steamed Veg Momos'), findsOneWidget);
      expect(find.text('₹90'), findsOneWidget);
      expect(find.text('Add'), findsOneWidget);
      expect(find.byIcon(Icons.favorite_outline_rounded), findsOneWidget);

      await tester.tap(find.text('Add'));
      await tester.pump();
      expect(tapped, isTrue);
    });

    testWidgets('2. Shopkeeper perspective renders item name, price, and EDIT button without favorite heart', (tester) async {
      bool editTapped = false;
      await tester.pumpWidget(
        buildTestCard(
          item: vegItem,
          perspective: ItemCardPerspective.shopkeeper,
          onAction: () => editTapped = true,
        ),
      );

      expect(find.text('Steamed Veg Momos'), findsOneWidget);
      expect(find.text('₹90'), findsOneWidget);
      expect(find.text('Edit'), findsOneWidget);
      expect(find.byIcon(Icons.favorite_outline_rounded), findsNothing);

      await tester.tap(find.text('Edit'));
      await tester.pump();
      expect(editTapped, isTrue);
    });

    testWidgets('3. Admin perspective renders item name, price, and EDIT button without favorite heart', (tester) async {
      bool editTapped = false;
      await tester.pumpWidget(
        buildTestCard(
          item: nonVegItem,
          perspective: ItemCardPerspective.admin,
          onAction: () => editTapped = true,
        ),
      );

      expect(find.text('Crispy Chicken Burger'), findsOneWidget);
      expect(find.text('₹150'), findsOneWidget);
      expect(find.text('Edit'), findsOneWidget);
      expect(find.byIcon(Icons.favorite_outline_rounded), findsNothing);

      await tester.tap(find.text('Edit'));
      await tester.pump();
      expect(editTapped, isTrue);
    });

    testWidgets('4. Veg indicator renders green circle and non-veg renders red circle', (tester) async {
      // Veg
      await tester.pumpWidget(buildTestCard(item: vegItem));
      final vegContainer = tester.widget<Container>(
        find.descendant(
          of: find.byType(UniversalMenuItemCard),
          matching: find.byWidgetPredicate(
            (w) =>
                w is Container &&
                w.decoration is BoxDecoration &&
                (w.decoration as BoxDecoration).shape == BoxShape.circle &&
                (w.decoration as BoxDecoration).color == AppColors.vegGreen,
          ),
        ),
      );
      expect(vegContainer, isNotNull);

      // Non-Veg
      await tester.pumpWidget(buildTestCard(item: nonVegItem));
      final nonVegContainer = tester.widget<Container>(
        find.descendant(
          of: find.byType(UniversalMenuItemCard),
          matching: find.byWidgetPredicate(
            (w) =>
                w is Container &&
                w.decoration is BoxDecoration &&
                (w.decoration as BoxDecoration).shape == BoxShape.circle &&
                (w.decoration as BoxDecoration).color == AppColors.nonVegRed,
          ),
        ),
      );
      expect(nonVegContainer, isNotNull);
    });

    testWidgets('5. Out of stock item in Customer perspective renders with reduced opacity and no Add button', (tester) async {
      await tester.pumpWidget(
        buildTestCard(
          item: outOfStockItem,
          perspective: ItemCardPerspective.customer,
        ),
      );

      expect(find.text('Paneer Tikka Roll'), findsOneWidget);
      expect(find.text('Add'), findsNothing);

      final Opacity opacityWidget = tester.widget(
        find.descendant(
          of: find.byType(UniversalMenuItemCard),
          matching: find.byType(Opacity),
        ).first,
      );
      expect(opacityWidget.opacity, equals(0.55));
    });

    testWidgets('6. Out of stock item in Shopkeeper perspective renders OUT OF STOCK badge and EDIT button', (tester) async {
      await tester.pumpWidget(
        buildTestCard(
          item: outOfStockItem,
          perspective: ItemCardPerspective.shopkeeper,
        ),
      );

      expect(find.text('Paneer Tikka Roll'), findsOneWidget);
      expect(find.text('OUT OF STOCK'), findsOneWidget);
      expect(find.text('Edit'), findsOneWidget);
    });

    testWidgets('7. Out of stock item in Admin perspective renders OUT OF STOCK badge and EDIT button', (tester) async {
      await tester.pumpWidget(
        buildTestCard(
          item: outOfStockItem,
          perspective: ItemCardPerspective.admin,
        ),
      );

      expect(find.text('Paneer Tikka Roll'), findsOneWidget);
      expect(find.text('OUT OF STOCK'), findsOneWidget);
      expect(find.text('Edit'), findsOneWidget);
    });

    testWidgets('8. Custom actionButtonText, onAction, and onTap callbacks work seamlessly', (tester) async {
      bool cardTapped = false;
      bool actionTapped = false;

      await tester.pumpWidget(
        buildTestCard(
          item: vegItem,
          actionButtonText: 'Custom',
          onTap: () => cardTapped = true,
          onAction: () => actionTapped = true,
        ),
      );

      expect(find.text('Custom'), findsOneWidget);

      await tester.tap(find.text('Custom'));
      await tester.pump();
      expect(actionTapped, isTrue);

      await tester.tap(find.text('Steamed Veg Momos'));
      await tester.pump();
      expect(cardTapped, isTrue);
    });

    testWidgets('9. Typography invariant: Text uses Gideon Roman for item name and Noto Sans JP for price', (tester) async {
      await tester.pumpWidget(buildTestCard(item: vegItem));

      final Text nameText = tester.widget(find.text('Steamed Veg Momos'));
      expect(nameText.style?.fontFamily, contains('GideonRoman'));
      expect(nameText.style?.fontWeight, equals(FontWeight.w900));

      final Text priceText = tester.widget(find.text('₹90'));
      expect(priceText.style?.fontFamily, contains('NotoSansJP'));
      expect(priceText.style?.fontWeight, equals(FontWeight.w800));
    });
  });
}
