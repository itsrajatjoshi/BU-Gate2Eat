// BU Gate2Eat — Comprehensive 18-Case Cart Logic & Invariant Test Suite
// Verifies every business rule, edge case, and cross-shop item ID collision prevention.

import 'package:bugate2eat_app/features/cart/cart_provider.dart';
import 'package:bugate2eat_app/models/menu_item_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late CartNotifier cartNotifier;

  const itemA1 = MenuItem(
    id: 'veg_steam_momos',
    name: 'Veg Momos',
    price: 60,
    details: 'Delicious Veg Steam Momos',
    imageUrl: '',
    isVeg: true,
    isAvailable: true,
    isRecommended: false,
    categoryId: 'momos',
    sortOrder: 1,
  );

  const itemA2 = MenuItem(
    id: 'chowmein',
    name: 'Chowmein',
    price: 80,
    details: 'Fresh Chowmein',
    imageUrl: '',
    isVeg: true,
    isAvailable: true,
    isRecommended: false,
    categoryId: 'fast_food',
    sortOrder: 2,
  );

  const itemB1 = MenuItem(
    id: 'burger',
    name: 'Burger',
    price: 70,
    details: 'Juicy Veg Burger',
    imageUrl: '',
    isVeg: true,
    isAvailable: true,
    isRecommended: false,
    categoryId: 'burgers',
    sortOrder: 1,
  );

  // Item with IDENTICAL itemId in a different shop (Cross-shop item ID collision test)
  const itemBSameIdAsA1 = MenuItem(
    id: 'veg_steam_momos',
    name: 'Nayan Veg Steam Momos',
    price: 65,
    details: 'Nayan Special Steam Momos',
    imageUrl: '',
    isVeg: true,
    isAvailable: true,
    isRecommended: false,
    categoryId: 'momos',
    sortOrder: 1,
  );

  const shopAId = 'rajat_shop';
  const shopAName = 'Rajat Shop';
  const shopBId = 'nayan_shop';
  const shopBName = 'Nayan Shop';

  setUp(() {
    cartNotifier = CartNotifier();
  });

  group('BU Gate2Eat — 18 Explicit Cart Case Tests & Regression Suite', () {
    test('CASE 1: Empty cart -> add Shop A item -> added directly without prompt', () {
      expect(cartNotifier.state.isEmpty, isTrue);
      expect(cartNotifier.state.shopId, isNull);

      final success = cartNotifier.addItem(itemA1, shopAId, shopAName);

      expect(success, isTrue);
      expect(cartNotifier.state.items.length, equals(1));
      expect(cartNotifier.state.shopId, equals(shopAId));
      expect(cartNotifier.state.shopName, equals(shopAName));
      expect(cartNotifier.state.items.first.quantity, equals(1));
    });

    test('CASE 2: Shop A item -> add another Shop A item -> both items in cart', () {
      cartNotifier.addItem(itemA1, shopAId, shopAName);
      final success = cartNotifier.addItem(itemA2, shopAId, shopAName);

      expect(success, isTrue);
      expect(cartNotifier.state.items.length, equals(2));
      expect(cartNotifier.state.shopId, equals(shopAId));
      expect(cartNotifier.state.totalItemCount, equals(2));
      expect(cartNotifier.state.grandTotal, equals(140.0));
    });

    test('CASE 3: Shop A item -> add same Shop A item again -> quantity increases to 2', () {
      cartNotifier.addItem(itemA1, shopAId, shopAName);
      final success = cartNotifier.addItem(itemA1, shopAId, shopAName);

      expect(success, isTrue);
      expect(cartNotifier.state.items.length, equals(1));
      expect(cartNotifier.state.items.first.quantity, equals(2));
      expect(cartNotifier.state.grandTotal, equals(120.0));
    });

    test('CASE 4: Shop A item -> add Shop B item -> conflict returned (false)', () {
      cartNotifier.addItem(itemA1, shopAId, shopAName);

      final success = cartNotifier.addItem(itemB1, shopBId, shopBName);

      expect(success, isFalse); // Conflict detected
    });

    test('CASE 5: Shop A cart -> choose KEEP CART -> Shop A cart unchanged', () {
      cartNotifier.addItem(itemA1, shopAId, shopAName);

      final success = cartNotifier.addItem(itemB1, shopBId, shopBName);
      expect(success, isFalse);

      // User chose KEEP CART (no action taken)
      expect(cartNotifier.state.shopId, equals(shopAId));
      expect(cartNotifier.state.items.length, equals(1));
      expect(cartNotifier.state.items.first.menuItem.id, equals(itemA1.id));
    });

    test('CASE 6: Shop A cart -> choose CLEAR & ADD -> Shop A items removed, Shop B item added atomically', () {
      cartNotifier.addItem(itemA1, shopAId, shopAName);
      cartNotifier.addItem(itemA2, shopAId, shopAName);

      cartNotifier.clearAndAddItem(itemB1, shopBId, shopBName);

      expect(cartNotifier.state.shopId, equals(shopBId));
      expect(cartNotifier.state.shopName, equals(shopBName));
      expect(cartNotifier.state.items.length, equals(1));
      expect(cartNotifier.state.items.first.menuItem.id, equals(itemB1.id));
      expect(cartNotifier.state.totalItemCount, equals(1));
    });

    test('CASE 7: Shop A cart -> remove all items -> completely empty cart (shopId=null, shopName=null)', () {
      cartNotifier.addItem(itemA1, shopAId, shopAName);
      expect(cartNotifier.state.shopId, equals(shopAId));

      cartNotifier.removeItem(itemA1.id);

      expect(cartNotifier.state.isEmpty, isTrue);
      expect(cartNotifier.state.shopId, isNull);
      expect(cartNotifier.state.shopName, isNull);
      expect(cartNotifier.state.items, isEmpty);
    });

    test('CASE 8: After empty cart -> add Shop B item -> added directly without dialog', () {
      cartNotifier.addItem(itemA1, shopAId, shopAName);
      cartNotifier.removeItem(itemA1.id);
      expect(cartNotifier.state.isEmpty, isTrue);

      final success = cartNotifier.addItem(itemB1, shopBId, shopBName);

      expect(success, isTrue);
      expect(cartNotifier.state.shopId, equals(shopBId));
      expect(cartNotifier.state.items.first.menuItem.id, equals(itemB1.id));
    });

    test('CASE 9: Add from Menu Card -> getQuantityForShop helper returns correct quantity for Item Detail', () {
      cartNotifier.addItem(itemA1, shopAId, shopAName);
      expect(cartNotifier.state.getQuantityForShop(shopAId, itemA1.id), equals(1));
      expect(cartNotifier.state.getQuantityForShop(shopAId, 'unknown_id'), equals(0));
    });

    test('CASE 10: Change quantity from Item Detail -> updates cartState immediately', () {
      cartNotifier.addItem(itemA1, shopAId, shopAName);
      expect(cartNotifier.state.getQuantityForShop(shopAId, itemA1.id), equals(1));

      cartNotifier.addItem(itemA1, shopAId, shopAName);
      expect(cartNotifier.state.getQuantityForShop(shopAId, itemA1.id), equals(2));

      cartNotifier.removeItem(itemA1.id);
      expect(cartNotifier.state.getQuantityForShop(shopAId, itemA1.id), equals(1));
    });

    test('CASE 11: Total Item Count = SUM of all item quantities (Momos x 2 + Burger x 1 = 3 items)', () {
      cartNotifier.addItem(itemA1, shopAId, shopAName);
      cartNotifier.addItem(itemA1, shopAId, shopAName); // Momos x 2
      cartNotifier.addItem(itemA2, shopAId, shopAName); // Chowmein x 1

      expect(cartNotifier.state.items.length, equals(2)); // 2 unique rows
      expect(cartNotifier.state.totalItemCount, equals(3)); // 3 total quantity sum
    });

    test('CASE 12: Remove final item -> cart becomes completely empty and floating cart disappears', () {
      cartNotifier.addItem(itemA1, shopAId, shopAName);
      expect(cartNotifier.state.isNotEmpty, isTrue);

      cartNotifier.removeItem(itemA1.id);

      expect(cartNotifier.state.isNotEmpty, isFalse);
      expect(cartNotifier.state.isEmpty, isTrue);
      expect(cartNotifier.state.shopId, isNull);
    });

    test('CASE 13: Delete item directly via deleteItem -> removes row and resets shop if empty', () {
      cartNotifier.addItem(itemA1, shopAId, shopAName);
      cartNotifier.deleteItem(itemA1.id);

      expect(cartNotifier.state.isEmpty, isTrue);
      expect(cartNotifier.state.shopId, isNull);
    });

    test('CASE 14: Update quantity to 0 via updateQuantity -> removes item completely', () {
      cartNotifier.addItem(itemA1, shopAId, shopAName);
      cartNotifier.updateQuantity(itemA1.id, 0);

      expect(cartNotifier.state.isEmpty, isTrue);
      expect(cartNotifier.state.shopId, isNull);
    });

    test('CASE 15: Grand total calculation = SUM(price * quantity)', () {
      cartNotifier.addItem(itemA1, shopAId, shopAName); // ₹60 x 1
      cartNotifier.addItem(itemA1, shopAId, shopAName); // ₹60 x 2 = ₹120
      cartNotifier.addItem(itemA2, shopAId, shopAName); // ₹80 x 1 = ₹80

      expect(cartNotifier.state.grandTotal, equals(200.0));
      expect(cartNotifier.state.formattedGrandTotal, equals('₹200'));
    });

    test('CASE 16: Cross-Shop Item ID Collision Fix — Rajat veg_steam_momos does NOT show as added in Nayan Shop', () {
      // Step 1: Add Rajat Shop's veg_steam_momos
      cartNotifier.addItem(itemA1, shopAId, shopAName);

      // Rajat Shop card lookup: returns 1
      expect(cartNotifier.state.getQuantityForShop(shopAId, 'veg_steam_momos'), equals(1));

      // Nayan Shop card lookup for identical item ID 'veg_steam_momos': MUST RETURN 0!
      expect(cartNotifier.state.getQuantityForShop(shopBId, 'veg_steam_momos'), equals(0));
    });

    test('CASE 17: Switching to Nayan Shop with CLEAR & ADD resets quantity of Rajat item in Nayan view', () {
      cartNotifier.addItem(itemA1, shopAId, shopAName); // Rajat veg_steam_momos
      expect(cartNotifier.state.getQuantityForShop(shopAId, 'veg_steam_momos'), equals(1));

      // Switch to Nayan Shop with itemB1 (burger)
      cartNotifier.clearAndAddItem(itemB1, shopBId, shopBName);

      // Cart now belongs to Nayan Shop
      expect(cartNotifier.state.shopId, equals(shopBId));

      // Nayan burger quantity = 1
      expect(cartNotifier.state.getQuantityForShop(shopBId, 'burger'), equals(1));

      // Nayan veg_steam_momos quantity = 0 (not added)
      expect(cartNotifier.state.getQuantityForShop(shopBId, 'veg_steam_momos'), equals(0));

      // Rajat veg_steam_momos quantity = 0 (cart cleared)
      expect(cartNotifier.state.getQuantityForShop(shopAId, 'veg_steam_momos'), equals(0));
    });

    test('CASE 18: Complete Real-User Flow & Regression (Shop A + veg_steam_momos x1 -> Nayan lookup=0 -> Rajat lookup=1)', () {
      // Cart: Rajat Shop + veg_steam_momos x 1
      final ok = cartNotifier.addItem(itemA1, shopAId, shopAName);
      expect(ok, isTrue);

      // Nayan Shop + veg_steam_momos (itemBSameIdAsA1) -> quantity MUST BE 0 (shows Add button)
      expect(cartNotifier.state.getQuantityForShop(shopBId, itemBSameIdAsA1.id), equals(0));

      // Rajat Shop + veg_steam_momos -> quantity MUST BE 1 (shows - 1 + stepper)
      expect(cartNotifier.state.getQuantityForShop(shopAId, itemA1.id), equals(1));
    });
  });
}
