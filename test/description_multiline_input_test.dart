// BU Gate2Eat — Tests
// Checkpoint 3.10 — Description Multiline Keyboard Input Fix Tests

import 'package:bugate2eat_app/models/category_model.dart';
import 'package:bugate2eat_app/models/menu_item_model.dart';
import 'package:bugate2eat_app/models/shop_model.dart';
import 'package:bugate2eat_app/panel/admin_panel/widgets/add_shop_modal.dart';
import 'package:bugate2eat_app/panel/shopkeeper_panel/widgets/add_content_modal.dart';
import 'package:bugate2eat_app/panel/shopkeeper_panel/widgets/edit_menu_item_modal.dart';
import 'package:bugate2eat_app/panel/shopkeeper_panel/widgets/edit_shop_modal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final testShop = Shop(
    id: 'test_shop_1',
    name: 'Test Gourmet Kitchen',
    description: 'Fresh food near Bennett University\nOpen till late night\nAvailable for pickup',
    openTime: '08:00',
    closeTime: '23:00',
    bannerUrl: '',
    isClosedOverride: false,
    isActive: true,
    sortOrder: 1,
    searchKeywords: const ['food', 'rolls'],
    deliveryNote: '',
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
    contactNumber: '9876543210',
    orderNumber: '9876543210',
  );

  const testCategory = Category(
    id: 'cat_rolls',
    name: 'Rolls',
    sortOrder: 1,
    shopId: 'test_shop_1',
  );

  const testMenuItem = MenuItem(
    id: 'item_1',
    name: 'Special Paneer Roll',
    price: 120,
    categoryId: 'cat_rolls',
    imageUrl: '',
    isVeg: true,
    isAvailable: true,
    isRecommended: true,
    sortOrder: 1,
    details: 'Fresh handmade whole wheat paratha\nLoaded with spiced cottage cheese\nServed with mint chutney',
  );

  group('Checkpoint 3.10 — Description Multiline Keyboard Input Tests', () {
    testWidgets('1. EditShopModal description field supports multiline input and TextInputAction.newline', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: EditShopModal(shop: testShop),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Find the description TextField by its hint text
      final descFieldFinder = find.byWidgetPredicate((widget) {
        if (widget is TextField) {
          final decoration = widget.decoration;
          return decoration?.hintText == 'e.g. Chinese, Fast Food, Snacks & Special Thalis';
        }
        return false;
      });

      expect(descFieldFinder, findsOneWidget);

      final TextField descField = tester.widget(descFieldFinder);
      expect(descField.keyboardType, equals(TextInputType.multiline));
      expect(descField.textInputAction, equals(TextInputAction.newline));
      expect(descField.maxLines, greaterThan(1));

      // Verify existing multiline text is correctly populated
      expect(descField.controller?.text, contains('\n'));
      expect(descField.controller?.text, equals('Fresh food near Bennett University\nOpen till late night\nAvailable for pickup'));

      // Simulate typing additional multiline text
      const newMultilineText = 'Paragraph 1: Fresh ingredients\nParagraph 2: Fast delivery\nParagraph 3: Special discounts';
      await tester.enterText(descFieldFinder, newMultilineText);
      await tester.pumpAndSettle();

      expect(descField.controller?.text, equals(newMultilineText));
    });

    testWidgets('2. AddShopModal description field supports multiline input and TextInputAction.newline', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: AddShopModal(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final descFieldFinder = find.byWidgetPredicate((widget) {
        if (widget is TextField) {
          final decoration = widget.decoration;
          return decoration?.labelText == 'Description / Food Highlights';
        }
        return false;
      });

      expect(descFieldFinder, findsOneWidget);

      final TextField descField = tester.widget(descFieldFinder);
      expect(descField.keyboardType, equals(TextInputType.multiline));
      expect(descField.textInputAction, equals(TextInputAction.newline));
      expect(descField.maxLines, greaterThan(1));

      const newMultilineText = 'Line 1\nLine 2\nLine 3';
      await tester.enterText(descFieldFinder, newMultilineText);
      await tester.pumpAndSettle();

      expect(descField.controller?.text, equals(newMultilineText));
    });

    testWidgets('3. AddContentModal portion/description field supports multiline input and TextInputAction.newline', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: AddContentModal(
                shopId: 'test_shop_1',
                categories: [testCategory],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final detailsFieldFinder = find.byWidgetPredicate((widget) {
        if (widget is TextField) {
          final decoration = widget.decoration;
          return decoration?.hintText == 'e.g. 8 Pieces / Served fresh with special sauces';
        }
        return false;
      });

      expect(detailsFieldFinder, findsOneWidget);

      final TextField detailsField = tester.widget(detailsFieldFinder);
      expect(detailsField.keyboardType, equals(TextInputType.multiline));
      expect(detailsField.textInputAction, equals(TextInputAction.newline));
      expect(detailsField.maxLines, greaterThan(1));

      const newMultilineText = '8 Pieces per plate\nCooked fresh on order\nExtra spicy dip included';
      await tester.enterText(detailsFieldFinder, newMultilineText);
      await tester.pumpAndSettle();

      expect(detailsField.controller?.text, equals(newMultilineText));
    });

    testWidgets('4. EditMenuItemModal portion/description field supports multiline input and TextInputAction.newline', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: EditMenuItemModal(
                shopId: 'test_shop_1',
                item: testMenuItem,
                categories: [testCategory],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final detailsFieldFinder = find.byWidgetPredicate((widget) {
        if (widget is TextField) {
          final decoration = widget.decoration;
          return decoration?.hintText == 'e.g. 8 Pieces / Served fresh with spicy schezwan';
        }
        return false;
      });

      expect(detailsFieldFinder, findsOneWidget);

      final TextField detailsField = tester.widget(detailsFieldFinder);
      expect(detailsField.keyboardType, equals(TextInputType.multiline));
      expect(detailsField.textInputAction, equals(TextInputAction.newline));
      expect(detailsField.maxLines, greaterThan(1));

      // Verify existing multiline text is correctly populated
      expect(detailsField.controller?.text, contains('\n'));
      expect(detailsField.controller?.text, equals('Fresh handmade whole wheat paratha\nLoaded with spiced cottage cheese\nServed with mint chutney'));

      const newMultilineText = 'Updated line 1\nUpdated line 2';
      await tester.enterText(detailsFieldFinder, newMultilineText);
      await tester.pumpAndSettle();

      expect(detailsField.controller?.text, equals(newMultilineText));
    });

    test('5. Model serialization preserves multiline strings with newlines', () {
      const multilineShopDesc = 'Best food near Bennett University\nFreshly prepared\nAvailable for pickup';
      final shop = testShop.copyWith(description: multilineShopDesc);
      final shopFirestore = shop.toFirestore();

      expect(shopFirestore['description'], equals(multilineShopDesc));
      expect(shopFirestore['description'].toString().split('\n').length, equals(3));

      const multilineItemDetails = 'Paneer Butter Masala is our special dish.\nServed with fresh butter naan.\n\nExtra spicy version available.';
      const menuItem = MenuItem(
        id: 'item_2',
        name: 'Special Paneer Roll',
        price: 120,
        categoryId: 'cat_rolls',
        imageUrl: '',
        isVeg: true,
        isAvailable: true,
        isRecommended: true,
        sortOrder: 1,
        details: multilineItemDetails,
      );
      final itemFirestore = menuItem.toFirestore();

      expect(itemFirestore['details'], equals(multilineItemDetails));
      expect(itemFirestore['details'].toString().split('\n').length, equals(4));
    });
  });
}
