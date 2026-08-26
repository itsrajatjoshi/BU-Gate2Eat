import 'package:flutter_test/flutter_test.dart';
import 'package:bugate2eat_app/models/shop_model.dart';
import 'package:bugate2eat_app/models/menu_item_model.dart';
import 'package:bugate2eat_app/models/category_model.dart';

void main() {
  group('Bug #4 — Homepage Search and Filter Logic Invariants', () {
    final shopA = Shop(
      id: 'shop_up16',
      name: 'UP16 Coffee Queen',
      description: 'Serving delicious hot momos and special spicy sauce in hostel 2',
      bannerUrl: '',
      contactNumber: '9876543210',
      orderNumber: '9876543210',
      openTime: '09:00',
      closeTime: '23:00',
      isClosedOverride: false,
      isActive: true,
      sortOrder: 1,
      searchKeywords: ['coffee', 'tea'],
      deliveryNote: '',
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

    final shopB = Shop(
      id: 'shop_nayan',
      name: 'Nayan Fast Food',
      description: 'Special cold coffee and beverages for students',
      bannerUrl: '',
      contactNumber: '9876543211',
      orderNumber: '9876543211',
      openTime: '18:00',
      closeTime: '03:00', // Overnight shop
      isClosedOverride: false,
      isActive: true,
      sortOrder: 2,
      searchKeywords: ['burger', 'fast food'],
      deliveryNote: '',
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

    final menuItemsA = [
      const MenuItem(
        id: 'item_1',
        categoryId: 'cat_coffee',
        name: 'Cold Coffee',
        details: 'Blended with ice cream and chocolate sauce',
        imageUrl: '',
        price: 90,
        isVeg: true,
        isAvailable: true,
        isRecommended: false,
        sortOrder: 1,
      ),
      const MenuItem(
        id: 'item_2',
        categoryId: 'cat_tea',
        name: 'Masala Tea',
        details: 'Hot ginger tea',
        imageUrl: '',
        price: 20,
        isVeg: true,
        isAvailable: true,
        isRecommended: false,
        sortOrder: 2,
      ),
    ];

    final menuItemsB = [
      const MenuItem(
        id: 'item_3',
        categoryId: 'cat_chinese',
        name: 'Chicken Momos',
        details: 'Steamed non-veg dumplings with spicy dip',
        imageUrl: '',
        price: 120,
        isVeg: false,
        isAvailable: true,
        isRecommended: false,
        sortOrder: 1,
      ),
      const MenuItem(
        id: 'item_4',
        categoryId: 'cat_fastfood',
        name: 'Veg Cheese Burger',
        details: 'Crispy patty with fresh cheese and sauce',
        imageUrl: '',
        price: 80,
        isVeg: true,
        isAvailable: true,
        isRecommended: false,
        sortOrder: 2,
      ),
    ];

    final categoriesA = [
      const Category(
        id: 'cat_coffee',
        name: 'Coffee & Shakes',
        sortOrder: 1,
        imageUrl: '',
        shopId: 'shop_up16',
      ),
    ];

    final categoriesB = [
      const Category(
        id: 'cat_chinese',
        name: 'Chinese',
        sortOrder: 1,
        imageUrl: '',
        shopId: 'shop_nayan',
      ),
      const Category(
        id: 'cat_fastfood',
        name: 'Fast Food',
        sortOrder: 2,
        imageUrl: '',
        shopId: 'shop_nayan',
      ),
    ];

    final allShops = [shopA, shopB];
    final menuItemsMap = {
      'shop_up16': menuItemsA,
      'shop_nayan': menuItemsB,
    };
    final categoriesMap = {
      'shop_up16': categoriesA,
      'shop_nayan': categoriesB,
    };

    List<Shop> filterShops({
      required String query,
      required String selectedFilter,
    }) {
      final q = query.trim().toLowerCase();
      return allShops.where((shop) {
        final items = menuItemsMap[shop.id] ?? const [];
        final cats = categoriesMap[shop.id] ?? const [];

        // 1. Search Query Filter (Matches shop.name OR actual menuItem.name — NEVER descriptions)
        if (q.isNotEmpty) {
          final nameMatches = shop.name.toLowerCase().contains(q);
          final foodMatches = items.any((item) => item.name.toLowerCase().contains(q));
          if (!nameMatches && !foodMatches) return false;
        }

        // 2. Category / Status Filter Pill
        switch (selectedFilter) {
          case 'Open Now':
            return shop.isOpen;
          case 'Fast Food':
            final catMatch = cats.any(
              (c) => c.name.toLowerCase().contains('fast food') || c.name.toLowerCase().contains('fastfood'),
            );
            final itemMatch = items.any(
              (i) =>
                  i.name.toLowerCase().contains('burger') ||
                  i.name.toLowerCase().contains('pizza') ||
                  i.name.toLowerCase().contains('sandwich') ||
                  i.name.toLowerCase().contains('wrap') ||
                  i.name.toLowerCase().contains('fast food'),
            );
            return catMatch || itemMatch;
          case 'Snacks':
            final catMatch = cats.any((c) => c.name.toLowerCase().contains('snack'));
            final itemMatch = items.any(
              (i) =>
                  i.name.toLowerCase().contains('snack') ||
                  i.name.toLowerCase().contains('fries') ||
                  i.name.toLowerCase().contains('maggi') ||
                  i.name.toLowerCase().contains('nugget'),
            );
            return catMatch || itemMatch;
          case 'Thalis':
            final catMatch = cats.any((c) => c.name.toLowerCase().contains('thali'));
            final itemMatch = items.any((i) => i.name.toLowerCase().contains('thali'));
            return catMatch || itemMatch;
          case 'Chinese':
            final catMatch = cats.any(
              (c) =>
                  c.name.toLowerCase().contains('chinese') ||
                  c.name.toLowerCase().contains('momo') ||
                  c.name.toLowerCase().contains('noodle'),
            );
            final itemMatch = items.any(
              (i) =>
                  i.name.toLowerCase().contains('chinese') ||
                  i.name.toLowerCase().contains('momo') ||
                  i.name.toLowerCase().contains('noodle') ||
                  i.name.toLowerCase().contains('manchurian') ||
                  i.name.toLowerCase().contains('chowmein'),
            );
            return catMatch || itemMatch;
          case 'Veg':
            return items.any((item) => item.isVeg);
          case 'Non-Veg':
            return items.any((item) => !item.isVeg);
          case 'All':
          default:
            return true;
        }
      }).toList();
    }

    test('1. Shop name search: "UP16" matches Shop A only', () {
      final res = filterShops(query: 'UP16', selectedFilter: 'All');
      expect(res.map((s) => s.id), ['shop_up16']);
    });

    test('2. Food item search: "momos" matches Shop B (has Chicken Momos)', () {
      final res = filterShops(query: 'momos', selectedFilter: 'All');
      expect(res.map((s) => s.id), ['shop_nayan']);
    });

    test('3. Description exclusion rule: Searching "sauce" returns 0 shops (only in description)', () {
      final res = filterShops(query: 'sauce', selectedFilter: 'All');
      expect(res, isEmpty);
    });

    test('4. Veg filter: Shop A (all veg) and Shop B (mixed) both offer veg items', () {
      final res = filterShops(query: '', selectedFilter: 'Veg');
      expect(res.map((s) => s.id), ['shop_up16', 'shop_nayan']);
    });

    test('5. Non-Veg filter: Only Shop B offers non-veg (Chicken Momos)', () {
      final res = filterShops(query: '', selectedFilter: 'Non-Veg');
      expect(res.map((s) => s.id), ['shop_nayan']);
    });

    test('6. Category filter Chinese: Only Shop B matches', () {
      final res = filterShops(query: '', selectedFilter: 'Chinese');
      expect(res.map((s) => s.id), ['shop_nayan']);
    });

    test('7. Search + Filter AND logic: Non-Veg + "burger" returns Shop B', () {
      final res = filterShops(query: 'burger', selectedFilter: 'Non-Veg');
      expect(res.map((s) => s.id), ['shop_nayan']);
    });

    test('8. Search + Filter AND logic: Non-Veg + "tea" returns 0 shops (Shop A is Veg-only)', () {
      final res = filterShops(query: 'tea', selectedFilter: 'Non-Veg');
      expect(res, isEmpty);
    });
  });
}
