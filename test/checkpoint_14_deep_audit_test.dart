// BU Gate2Eat — Bug #14 Deep Architecture & Data-Integrity Regression Suite
// Comprehensive verification of Session Isolation, Role Mappings, Order Lifecycle, Cart Math & Gate 3 Invariants

import 'package:bugate2eat_app/core/constants/app_constants.dart';
import 'package:bugate2eat_app/models/cart_item_model.dart';
import 'package:bugate2eat_app/models/menu_item_model.dart';
import 'package:bugate2eat_app/services/local_storage_service.dart';
import 'package:bugate2eat_app/services/order_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Bug #14 — Identity & Session Isolation', () {
    test('1. Customer ID is deterministically derived from userPhone and persisted', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final storage = LocalStorageService(prefs);

      // Onboard User A
      await storage.saveUserProfile(name: 'Rajat Student', phone: '9876543210');
      expect(storage.userName, 'Rajat Student');
      expect(storage.userPhone, '9876543210');
      expect(storage.customerId, 'cust_9876543210');

      // Update phone to User A prime
      await storage.updatePhone('9123456780');
      expect(storage.userPhone, '9123456780');
      expect(storage.customerId, 'cust_9123456780');
    });

    test('2. Logout completely purges customerId so next user session never bleeds', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final storage = LocalStorageService(prefs);

      // User A logs in
      await storage.saveUserProfile(name: 'User A', phone: '9876543210');
      expect(storage.customerId, 'cust_9876543210');
      expect(storage.isOnboarded, isTrue);

      // User A logs out
      await storage.logout();
      expect(storage.isOnboarded, isFalse);
      expect(storage.userName, '');
      expect(storage.userPhone, '');
      expect(prefs.getString('customer_id'), isNull);

      // User B logs in on same device
      await storage.saveUserProfile(name: 'User B', phone: '9988776655');
      expect(storage.customerId, 'cust_9988776655');
      expect(storage.customerId, isNot('cust_9876543210'));
    });

    test('3. Anonymous session gets stable anonymous customerId if phone is empty', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final storage = LocalStorageService(prefs);

      final anonId1 = storage.customerId;
      expect(anonId1, startsWith('cust_anon_'));

      final anonId2 = storage.customerId;
      expect(anonId2, equals(anonId1)); // Stable across reads

      // Converting anon to authenticated session
      await storage.saveUserProfile(name: 'New User', phone: '9811223344');
      expect(storage.customerId, 'cust_9811223344');
    });
  });

  group('Bug #14 — Centralized Auth Role & Shop Mapping', () {
    test('4. Admin phone correctly recognized with and without prefix', () {
      expect(AppAuthRoles.isAdminPhone('8078643910'), isTrue);
      expect(AppAuthRoles.isAdminPhone('+91 8078643910'), isTrue);
      expect(AppAuthRoles.isAdminPhone('08078643910'), isTrue);
      expect(AppAuthRoles.isAdminPhone('9876543210'), isFalse);
    });

    test('5. All registered Shopkeepers correctly recognized and mapped to shopId', () {
      // Rajat Shop
      expect(AppAuthRoles.isShopkeeperPhone('8000383993'), isTrue);
      expect(AppAuthRoles.getShopIdForPhone('+91 8000383993'), 'rajat_shop');

      // Nayan Shop
      expect(AppAuthRoles.isShopkeeperPhone('8295643910'), isTrue);
      expect(AppAuthRoles.getShopIdForPhone('8295643910'), 'nayan_shop');

      // Kivisha Shop
      expect(AppAuthRoles.isShopkeeperPhone('8875344034'), isTrue);
      expect(AppAuthRoles.getShopIdForPhone('+91 8875344034'), 'kivisha_shop');

      // UP 16 Junction Fast Food (multiple lines)
      expect(AppAuthRoles.isShopkeeperPhone('8745007244'), isTrue);
      expect(AppAuthRoles.getShopIdForPhone('8745007244'), 'up16_junction_fast_food');
      expect(AppAuthRoles.isShopkeeperPhone('8745950335'), isTrue);
      expect(AppAuthRoles.getShopIdForPhone('8745950335'), 'up16_junction_fast_food');
      expect(AppAuthRoles.isShopkeeperPhone('8079065843'), isTrue);
      expect(AppAuthRoles.getShopIdForPhone('8079065843'), 'up16_junction_fast_food');

      // Raja Hotel & UP16 Queens
      expect(AppAuthRoles.isShopkeeperPhone('8888822222'), isTrue);
      expect(AppAuthRoles.getShopIdForPhone('8888822222'), 'raja_hotel');
      expect(AppAuthRoles.isShopkeeperPhone('9999922222'), isTrue);
      expect(AppAuthRoles.getShopIdForPhone('9999922222'), 'up16_coffee_queen');

      // Regular customer
      expect(AppAuthRoles.isShopkeeperPhone('9876543210'), isFalse);
      expect(AppAuthRoles.getShopIdForPhone('9876543210'), isNull);
    });
  });

  group('Bug #14 — Order Lifecycle & Status Invariants', () {
    test('6. OrderStatusRules allows valid transitions and blocks invalid', () {
      // Valid transitions
      expect(OrderStatusRules.isValidTransition('placed', 'accepted'), isTrue);
      expect(OrderStatusRules.isValidTransition('placed', 'rejected'), isTrue);
      expect(OrderStatusRules.isValidTransition('placed', 'cancelled'), isTrue);
      expect(OrderStatusRules.isValidTransition('accepted', 'delivered'), isTrue);
      expect(OrderStatusRules.isValidTransition('accepted', 'rejected'), isTrue);
      expect(OrderStatusRules.isValidTransition('accepted', 'delivery_expired'), isTrue);

      // Terminal state transitions MUST be blocked
      expect(OrderStatusRules.isValidTransition('delivered', 'accepted'), isFalse);
      expect(OrderStatusRules.isValidTransition('rejected', 'placed'), isFalse);
      expect(OrderStatusRules.isValidTransition('cancelled', 'accepted'), isFalse);
      expect(OrderStatusRules.isValidTransition('delivery_expired', 'delivered'), isFalse);

      // Invalid jump
      expect(OrderStatusRules.isValidTransition('placed', 'delivered'), isFalse);
    });

    test('7. Order deletion allowed only for cancellable and terminal states', () {
      // Physical deletion of placed order (customer pre-accept cancel)
      expect(OrderStatusRules.isTerminal('delivered'), isTrue);
      expect(OrderStatusRules.isTerminal('rejected'), isTrue);
      expect(OrderStatusRules.isTerminal('cancelled'), isTrue);
      expect(OrderStatusRules.isTerminal('delivery_expired'), isTrue);

      // Active state
      expect(OrderStatusRules.isActive('placed'), isTrue);
      expect(OrderStatusRules.isActive('accepted'), isTrue);
    });
  });

  group('Bug #14 — Pricing, Cart & Operational Gate Invariants', () {
    test('8. MenuItem starting price reflects minimum price without optional additions', () {
      const itemWithOptionalAndRequired = MenuItem(
        id: 'test_item',
        name: 'Veg Roll',
        price: 60,
        details: 'Tasty roll',
        imageUrl: '',
        isVeg: true,
        isAvailable: true,
        isRecommended: true,
        categoryId: 'rolls',
        sortOrder: 1,
        optionGroups: [
          MenuItemOptionGroup(
            id: 'size',
            name: 'Size',
            groupType: OptionGroupType.fixed,
            required: true,
            options: [
              MenuItemOption(id: 'half', name: 'Half', price: 60, pricingType: OptionPricingType.fixedPrice),
              MenuItemOption(id: 'full', name: 'Full', price: 100, pricingType: OptionPricingType.fixedPrice),
            ],
          ),
          MenuItemOptionGroup(
            id: 'cheese',
            name: 'Add Cheese',
            groupType: OptionGroupType.choice,
            required: false,
            options: [
              MenuItemOption(id: 'extra_cheese', name: 'Extra Cheese', price: 25, pricingType: OptionPricingType.priceAdjustment),
            ],
          ),
        ],
      );

      // Starting price must be minimum fixed price (60), and extra cheese (25) must NOT inflate it
      expect(itemWithOptionalAndRequired.startingPrice, equals(60));
    });

    test('9. CartItem builds deterministic cartKey regardless of option ordering', () {
      const opt1 = SelectedMenuItemOption(
        groupId: 'a_size',
        groupName: 'Size',
        optionId: 'half',
        optionName: 'Half',
        pricingType: OptionPricingType.fixedPrice,
        price: 60,
      );
      const opt2 = SelectedMenuItemOption(
        groupId: 'b_extra',
        groupName: 'Extra',
        optionId: 'cheese',
        optionName: 'Cheese',
        pricingType: OptionPricingType.priceAdjustment,
        price: 20,
      );

      final key1 = CartItem.buildCartKey('item_1', [opt1, opt2]);
      final key2 = CartItem.buildCartKey('item_1', [opt2, opt1]);

      expect(key1, equals(key2));
      expect(key1, 'item_1|a_size:half|b_extra:cheese');
    });

    test('10. App operational location invariant is Gate 3', () {
      expect(AppConfig.pickupLocation, equals('Bennett Gate No. 3'));
    });
  });
}
