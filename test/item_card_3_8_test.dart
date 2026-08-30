import 'package:bugate2eat_app/core/constants/app_constants.dart';
import 'package:bugate2eat_app/core/providers.dart';
import 'package:bugate2eat_app/features/cart/cart_provider.dart';
import 'package:bugate2eat_app/features/shop/shop_detail_screen.dart';
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
    id: 'raja_hotel',
    name: 'Raja Hotel',
    description: 'Fresh & Authentic flavours',
    bannerUrl: 'https://cdn.yummbu.com/shops/raja.jpg',
    contactNumber: '9910707219',
    orderNumber: '9319566645',
    openTime: '08:00',
    closeTime: '23:30',
    isClosedOverride: false,
    isActive: true,
    sortOrder: 1,
    searchKeywords: ['raja'],
    deliveryNote: 'Gate 3',
    createdAt: DateTime(2025, 1, 1),
    updatedAt: DateTime(2025, 1, 1),
  );

  const rotiItem = MenuItem(
    id: 'plain_tawa_roti',
    name: 'Plain Tawa Roti',
    details: 'Whole wheat chapati prepared fresh',
    price: 13,
    imageUrl: 'https://cdn.yummbu.com/items/roti.jpg',
    categoryId: 'breads',
    isVeg: true,
    isAvailable: true,
    isRecommended: true,
    sortOrder: 1,
    optionGroups: [],
  );

  const customItem = MenuItem(
    id: 'paneer_butter_masala',
    name: 'Paneer Butter Masala',
    details: 'Rich creamy paneer curry in butter gravy',
    price: 180,
    imageUrl: 'https://cdn.yummbu.com/items/paneer.jpg',
    categoryId: 'curries',
    isVeg: true,
    isAvailable: true,
    isRecommended: true,
    sortOrder: 2,
    optionGroups: [
      MenuItemOptionGroup(
        id: 'portion',
        name: 'Portion',
        required: true,
        groupType: OptionGroupType.fixed,
        options: [
          MenuItemOption(id: 'half', name: 'Half', price: 0),
          MenuItemOption(id: 'full', name: 'Full', price: 100),
        ],
      ),
    ],
  );

  const testCategory = Category(
    id: 'breads',
    name: 'Breads',
    sortOrder: 1,
    imageUrl: '',
    isActive: true,
  );

  group('Checkpoint 3.8 & 3.8.1 — Customer Item Card UI/UX & Typography Tests', () {
    testWidgets('1. Item description is NOT rendered anywhere inside the customer Item Card',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localStorageServiceProvider.overrideWithValue(localStorage),
            shopDetailProvider(testShop.id).overrideWith(
              (ref) => Future.value(testShop),
            ),
            shopMenuItemsProvider(testShop.id).overrideWith(
              (ref) => Future.value([rotiItem]),
            ),
            shopCategoriesProvider(testShop.id).overrideWith(
              (ref) => Future.value([testCategory]),
            ),
          ],
          child: MaterialApp(
            theme: ThemeData.light(),
            home: ShopDetailScreen(shopId: testShop.id),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Item Name, Veg icon, Price and ADD button are rendered
      expect(find.text('Plain Tawa Roti'), findsWidgets);
      expect(find.text('₹13'), findsWidgets);
      expect(find.text('Add'), findsWidgets);

      // Description is completely removed from Item Card
      expect(find.text('Whole wheat chapati prepared fresh'), findsNothing);
      expect(find.text('more'), findsNothing);
    });

    testWidgets('2. Item description remains fully present inside Item Details Bottom Sheet',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localStorageServiceProvider.overrideWithValue(localStorage),
            shopDetailProvider(testShop.id).overrideWith(
              (ref) => Future.value(testShop),
            ),
            shopMenuItemsProvider(testShop.id).overrideWith(
              (ref) => Future.value([rotiItem]),
            ),
            shopCategoriesProvider(testShop.id).overrideWith(
              (ref) => Future.value([testCategory]),
            ),
          ],
          child: MaterialApp(
            theme: ThemeData.light(),
            home: ShopDetailScreen(shopId: testShop.id),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Tap on item card Add button to open Item Details
      final addBtnFinder = find.byKey(const ValueKey('add_btn')).first;
      await tester.tap(addBtnFinder);
      await tester.pumpAndSettle();

      // Description MUST appear inside Item Details Bottom Sheet
      expect(find.text('Whole wheat chapati prepared fresh'), findsOneWidget);
      expect(find.text('Add to Cart'), findsOneWidget);
    });

    testWidgets('3. Item Card always displays [Add] button and NEVER [- 1 +] quantity stepper',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final container = ProviderContainer(
        overrides: [
          localStorageServiceProvider.overrideWithValue(localStorage),
          shopDetailProvider(testShop.id).overrideWith(
            (ref) => Future.value(testShop),
          ),
          shopMenuItemsProvider(testShop.id).overrideWith(
            (ref) => Future.value([rotiItem]),
          ),
          shopCategoriesProvider(testShop.id).overrideWith(
            (ref) => Future.value([testCategory]),
          ),
        ],
      );

      // Add item to cart beforehand
      container.read(cartProvider.notifier).addItem(
        rotiItem,
        testShop.id,
        testShop.name,
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: ThemeData.light(),
            home: ShopDetailScreen(shopId: testShop.id),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // [Add] must remain visible
      expect(find.text('Add'), findsWidgets);
      // Stepper icons or buttons must not appear on the card
      expect(find.byIcon(Icons.remove), findsNothing);
    });

    testWidgets('4. Tapping [Add] on customizable item opens Item Details with option choices',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localStorageServiceProvider.overrideWithValue(localStorage),
            shopDetailProvider(testShop.id).overrideWith(
              (ref) => Future.value(testShop),
            ),
            shopMenuItemsProvider(testShop.id).overrideWith(
              (ref) => Future.value([customItem]),
            ),
            shopCategoriesProvider(testShop.id).overrideWith(
              (ref) => Future.value([
                const Category(id: 'curries', name: 'Curries', sortOrder: 1, imageUrl: '', isActive: true),
              ]),
            ),
          ],
          child: MaterialApp(
            theme: ThemeData.light(),
            home: ShopDetailScreen(shopId: testShop.id),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Description is absent from card
      expect(find.text('Rich creamy paneer curry in butter gravy'), findsNothing);

      // Tap Add
      final addBtnFinder = find.byKey(const ValueKey('add_btn')).first;
      await tester.tap(addBtnFinder);
      await tester.pumpAndSettle();

      // Description & options are shown in details sheet
      expect(find.text('Rich creamy paneer curry in butter gravy'), findsOneWidget);
      expect(find.text('Half'), findsOneWidget);
      expect(find.text('Full'), findsOneWidget);
    });

    testWidgets('5. Step 3.8.1 — Item Name uses Gideon Roman & Price uses Noto Sans JP typography',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localStorageServiceProvider.overrideWithValue(localStorage),
            shopDetailProvider(testShop.id).overrideWith(
              (ref) => Future.value(testShop),
            ),
            shopMenuItemsProvider(testShop.id).overrideWith(
              (ref) => Future.value([rotiItem]),
            ),
            shopCategoriesProvider(testShop.id).overrideWith(
              (ref) => Future.value([testCategory]),
            ),
          ],
          child: MaterialApp(
            theme: ThemeData.light(),
            home: ShopDetailScreen(shopId: testShop.id),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Find Item Name Text widget
      final nameTextFinder = find.text('Plain Tawa Roti');
      expect(nameTextFinder, findsWidgets);
      final Text nameText = tester.widget(nameTextFinder.first);
      expect(
        nameText.style?.fontFamily?.toLowerCase().contains('gideon') ?? false,
        isTrue,
        reason: 'Item Name must use Gideon Roman font family',
      );
      expect(nameText.style?.fontWeight, equals(FontWeight.w900));

      // Find Price Text widget
      final priceTextFinder = find.text('₹13');
      expect(priceTextFinder, findsWidgets);
      final Text priceText = tester.widget(priceTextFinder.first);
      expect(
        priceText.style?.fontFamily?.toLowerCase().contains('notosansjp') ?? false,
        isTrue,
        reason: 'Price must use Noto Sans JP font family',
      );
      expect(priceText.style?.fontWeight, equals(FontWeight.w800));
    });
  });
}
