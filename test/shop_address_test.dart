// BU Gate2Eat — Shop Address Tests
// Tests for Shop-Specific Mandatory Address in Model, Add/Edit Modals, and Customer Shop Details

import 'dart:typed_data';

import 'package:bugate2eat_app/core/providers.dart';
import 'package:bugate2eat_app/features/shop/widgets/shop_detail_bottom_sheet.dart';
import 'package:bugate2eat_app/models/shop_model.dart';
import 'package:bugate2eat_app/panel/admin_panel/widgets/add_shop_modal.dart';
import 'package:bugate2eat_app/panel/shopkeeper_panel/widgets/edit_shop_modal.dart';
import 'package:bugate2eat_app/services/firestore_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeFirestoreService extends Fake implements FirestoreService {
  Shop? createdShop;
  Map<String, dynamic>? updatedShopData;
  String? updatedShopId;

  @override
  Future<String> createShop(
    Shop shop, {
    Uint8List? bannerBytes,
    Uint8List? logoBytes,
  }) async {
    createdShop = shop;
    return shop.id;
  }

  @override
  Future<void> updateShop(String shopId, Map<String, dynamic> data) async {
    updatedShopId = shopId;
    updatedShopData = data;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final shopA = Shop(
    id: 'raja_hotel',
    name: 'Raja Hotel',
    description: 'North Indian & Mughlai Delicacies',
    address: 'Shop 101, Gate 2 Commercial Complex, Dabra',
    bannerUrl: '',
    contactNumber: '9910707219',
    orderNumber: '9319566645',
    openTime: '08:00',
    closeTime: '23:30',
    isClosedOverride: false,
    isActive: true,
    sortOrder: 1,
    searchKeywords: const ['raja', 'hotel'],
    deliveryNote: 'Gate 3',
    createdAt: DateTime(2025, 1, 1),
    updatedAt: DateTime(2025, 1, 1),
  );

  final shopB = Shop(
    id: 'nayan_shop',
    name: 'Nayan Shop',
    description: 'Momos & Fast Food',
    address: 'Plot 45, Dabra Village Market',
    bannerUrl: '',
    contactNumber: '8295643910',
    orderNumber: '8295643910',
    openTime: '08:00',
    closeTime: '23:30',
    isClosedOverride: false,
    isActive: true,
    sortOrder: 2,
    searchKeywords: const ['nayan'],
    deliveryNote: 'Gate 3',
    createdAt: DateTime(2025, 1, 1),
    updatedAt: DateTime(2025, 1, 1),
  );

  group('Shop Model — Address Serialization & Integrity', () {
    test('1. Shop.toFirestore includes address field', () {
      final firestoreMap = shopA.toFirestore();
      expect(firestoreMap['address'], 'Shop 101, Gate 2 Commercial Complex, Dabra');
      expect(firestoreMap['name'], 'Raja Hotel');
    });

    test('2. Shop.copyWith properly updates address', () {
      final updated = shopA.copyWith(address: 'New Location Lane 4');
      expect(updated.address, 'New Location Lane 4');
      expect(updated.name, shopA.name);
    });

    test('3. Backward compatibility: missing address defaults safely to empty string', () {
      final emptyShop = Shop(
        id: 'legacy_shop',
        name: 'Legacy Shop',
        description: 'Legacy description',
        bannerUrl: '',
        contactNumber: '1234567890',
        orderNumber: '1234567890',
        openTime: '08:00',
        closeTime: '22:00',
        isClosedOverride: false,
        isActive: true,
        sortOrder: 1,
        searchKeywords: const [],
        deliveryNote: 'Gate 3',
        createdAt: DateTime(2025),
        updatedAt: DateTime(2025),
      );
      expect(emptyShop.address, '');
    });
  });

  group('Customer Shop Details — Dynamic Address Rendering', () {
    testWidgets('4. Shop Details displays shop.address dynamically for Shop A', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => showShopDetailBottomSheet(
                    context: context,
                    shop: shopA,
                    menuItems: const [],
                  ),
                  child: const Text('Open Shop A'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Shop A'));
      await tester.pumpAndSettle();

      // Verify Shop A unique address is displayed
      expect(find.text('Shop 101, Gate 2 Commercial Complex, Dabra'), findsOneWidget);
      // Verify hardcoded address is NOT displayed
      expect(find.text('Near Bennett University, Dabra'), findsNothing);
    });

    testWidgets('5. Shop Details displays distinct unique address for Shop B (No leakage)', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => showShopDetailBottomSheet(
                    context: context,
                    shop: shopB,
                    menuItems: const [],
                  ),
                  child: const Text('Open Shop B'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Shop B'));
      await tester.pumpAndSettle();

      // Verify Shop B unique address is displayed
      expect(find.text('Plot 45, Dabra Village Market'), findsOneWidget);
      // Verify Shop A address does not leak
      expect(find.text('Shop 101, Gate 2 Commercial Complex, Dabra'), findsNothing);
      expect(find.text('Near Bennett University, Dabra'), findsNothing);
    });
  });

  group('Admin Add Shop Modal — Address Validation', () {
    testWidgets('6. Add Shop blocks creation if address is empty', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final fakeFirestore = _FakeFirestoreService();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            firestoreServiceProvider.overrideWithValue(fakeFirestore),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: AddShopModal(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Enter shop name
      final nameField = find.widgetWithText(TextField, 'Shop Name *');
      expect(nameField, findsOneWidget);
      await tester.enterText(nameField, 'Test New Shop');

      // Tap Create Shop with address left empty
      final createBtn = find.text('Create Shop');
      expect(createBtn, findsOneWidget);
      await tester.ensureVisible(createBtn);
      await tester.tap(createBtn);
      await tester.pumpAndSettle();

      // Verify error snackbar is shown and creation was blocked
      expect(find.text('Shop Address cannot be empty.'), findsOneWidget);
      expect(fakeFirestore.createdShop, isNull);
    });

    testWidgets('7. Add Shop creates shop successfully when mandatory address is provided', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final fakeFirestore = _FakeFirestoreService();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            firestoreServiceProvider.overrideWithValue(fakeFirestore),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: AddShopModal(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Enter shop name
      final nameField = find.widgetWithText(TextField, 'Shop Name *');
      await tester.enterText(nameField, 'Test New Shop');

      // Enter shop address
      final addressField = find.widgetWithText(TextField, 'Shop Address *');
      expect(addressField, findsOneWidget);
      await tester.enterText(addressField, 'Opposite Gate 1, BU Road');

      final createBtn = find.text('Create Shop');
      await tester.ensureVisible(createBtn);
      await tester.tap(createBtn);
      await tester.pumpAndSettle();

      // Verify creation succeeded with the provided address
      expect(fakeFirestore.createdShop, isNotNull);
      expect(fakeFirestore.createdShop!.address, 'Opposite Gate 1, BU Road');
    });
  });

  group('Shopkeeper / Admin Edit Shop Modal — Address Validation', () {
    testWidgets('8. Edit Shop preloads existing address and blocks saving if address is cleared', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final fakeFirestore = _FakeFirestoreService();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            firestoreServiceProvider.overrideWithValue(fakeFirestore),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: EditShopModal(shop: shopA),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Preloaded address must match shopA.address
      expect(find.text('Shop 101, Gate 2 Commercial Complex, Dabra'), findsOneWidget);

      // Clear the address field
      final addressField = find.widgetWithText(TextField, 'Shop 101, Gate 2 Commercial Complex, Dabra');
      await tester.enterText(addressField, '   ');

      final saveBtn = find.text('Save Shop Details');
      expect(saveBtn, findsOneWidget);
      await tester.ensureVisible(saveBtn);
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();

      // Verify error snackbar is shown and update was blocked
      expect(find.text('Shop Address cannot be empty.'), findsOneWidget);
      expect(fakeFirestore.updatedShopData, isNull);
    });

    testWidgets('9. Edit Shop successfully updates address in Firestore', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final fakeFirestore = _FakeFirestoreService();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            firestoreServiceProvider.overrideWithValue(fakeFirestore),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: EditShopModal(shop: shopA),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Update address
      final addressField = find.widgetWithText(TextField, 'Shop 101, Gate 2 Commercial Complex, Dabra');
      await tester.enterText(addressField, 'Updated Address Near Gate 2');

      final saveBtn = find.text('Save Shop Details');
      await tester.ensureVisible(saveBtn);
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();

      // Verify updateShop was called with new address
      expect(fakeFirestore.updatedShopId, 'raja_hotel');
      expect(fakeFirestore.updatedShopData?['address'], 'Updated Address Near Gate 2');
    });

    testWidgets('10. Edit Shop writes updated address to Firestore updateShop payload', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final fakeFirestore = _FakeFirestoreService();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            firestoreServiceProvider.overrideWithValue(fakeFirestore),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: EditShopModal(shop: shopA),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      const newlyEnteredAddress = 'Block B, Gate 2 Commercial Hub, Bennett Univ, Greater Noida';
      final addressField = find.widgetWithText(TextField, 'Shop 101, Gate 2 Commercial Complex, Dabra');
      await tester.enterText(addressField, newlyEnteredAddress);

      final saveBtn = find.text('Save Shop Details');
      await tester.ensureVisible(saveBtn);
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();

      // Verify Firestore mutation
      expect(fakeFirestore.updatedShopId, 'raja_hotel');
      expect(fakeFirestore.updatedShopData?['address'], newlyEnteredAddress);
    });

    testWidgets('11. Customer Shop Details dynamically reads and displays mutated Firestore address', (tester) async {
      const updatedAddress = 'Block B, Gate 2 Commercial Hub, Bennett Univ, Greater Noida';
      final shopFromFirestore = shopA.copyWith(address: updatedAddress);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => showShopDetailBottomSheet(
                    context: context,
                    shop: shopFromFirestore,
                    menuItems: const [],
                  ),
                  child: const Text('Open Customer Shop Details'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Customer Shop Details'));
      await tester.pumpAndSettle();

      // Verify customer sees the updated Firestore address
      expect(find.text(updatedAddress), findsOneWidget);
      expect(find.text('Shop 101, Gate 2 Commercial Complex, Dabra'), findsNothing);
      expect(find.text('Near Bennett University, Dabra'), findsNothing);
    });
  });
}
