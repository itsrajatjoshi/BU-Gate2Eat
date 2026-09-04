import 'package:bugate2eat_app/core/providers.dart';
import 'package:bugate2eat_app/models/shop_model.dart';
import 'package:bugate2eat_app/models/shop_stats_model.dart';
import 'package:bugate2eat_app/panel/admin_panel/admin_home_screen.dart';
import 'package:bugate2eat_app/panel/admin_panel/admin_main_shell.dart';
import 'package:bugate2eat_app/panel/admin_panel/admin_order_stats_screen.dart';
import 'package:bugate2eat_app/panel/admin_panel/admin_profile_screen.dart';
import 'package:bugate2eat_app/services/local_storage_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final mockShops = [
    Shop(
      id: 'shop_1',
      name: 'Campus Treats',
      description: 'Snacks and beverages',
      bannerUrl: '',
      contactNumber: '9876543210',
      orderNumber: '9876543210',
      openTime: '08:00',
      closeTime: '22:00',
      isClosedOverride: false,
      isActive: true,
      sortOrder: 1,
      searchKeywords: const ['snacks', 'tea'],
      deliveryNote: 'Delivery at Gate 1',
      createdAt: DateTime(2025),
      updatedAt: DateTime(2025),
    ),
  ];

  Widget buildAdminApp(LocalStorageService localStorage) {
    return ProviderScope(
      overrides: [
        localStorageServiceProvider.overrideWithValue(localStorage),
        shopsProvider.overrideWith((ref) async => mockShops),
        allShopStatsStreamProvider.overrideWith(
          (ref) => Stream.value([
            ShopStats.zero(shopId: 'shop_1', shopName: 'Campus Treats'),
          ]),
        ),
      ],
      child: const MaterialApp(
        home: AdminMainShell(),
      ),
    );
  }

  group('Admin Navigation & PopScope Tests', () {
    testWidgets('1. Tab switching & Android system back returns to Home tab',
        (tester) async {
      SharedPreferences.setMockInitialValues({
        'user_phone': '8078643910',
        'user_name': 'Rajat Joshi',
        'is_onboarded': true,
      });
      final prefs = await SharedPreferences.getInstance();
      final localStorage = LocalStorageService(prefs);

      await tester.binding.setSurfaceSize(const Size(450, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(buildAdminApp(localStorage));
      await tester.pumpAndSettle();

      // Initially on Tab 0 (AdminHomeScreen)
      expect(find.byType(AdminHomeScreen), findsOneWidget);
      expect(find.text('Add Shop'), findsOneWidget);

      // Tap on Tab 1: Order Stats
      await tester.tap(find.byIcon(Icons.analytics_outlined));
      await tester.pumpAndSettle();

      expect(find.byType(AdminOrderStatsScreen), findsOneWidget);
      expect(find.text('Order Statistics'), findsOneWidget);

      // Simulate Android physical back button on Tab 1
      final popHandledTab1 = await tester.binding.handlePopRoute();
      expect(
        popHandledTab1,
        isTrue,
        reason: 'PopScope must intercept back press on Tab 1',
      );
      await tester.pumpAndSettle();

      // Should return to Tab 0 (Home)
      final bottomNavAfterBack1 =
          tester.widget<BottomNavigationBar>(find.byType(BottomNavigationBar));
      expect(bottomNavAfterBack1.currentIndex, 0);

      // Tap on Tab 2: Profile
      await tester.tap(find.byIcon(Icons.person_outline_rounded));
      await tester.pumpAndSettle();

      expect(find.byType(AdminProfileScreen), findsOneWidget);
      expect(find.text('Customer Queries'), findsOneWidget);

      // Simulate Android physical back button on Tab 2
      final popHandledTab2 = await tester.binding.handlePopRoute();
      expect(
        popHandledTab2,
        isTrue,
        reason: 'PopScope must intercept back press on Tab 2',
      );
      await tester.pumpAndSettle();

      // Should return to Tab 0 (Home)
      final bottomNavAfterBack2 =
          tester.widget<BottomNavigationBar>(find.byType(BottomNavigationBar));
      expect(bottomNavAfterBack2.currentIndex, 0);

      // Simulate Android back on Tab 0 (Home) -> should allow pop/exit
      final popHandledTab0 = await tester.binding.handlePopRoute();
      expect(
        popHandledTab0,
        isFalse,
        reason: 'PopScope allows pop when currentIndex is 0',
      );
    });

    testWidgets(
        '2. Profile avatar on AdminHomeScreen switches to Admin Profile tab',
        (tester) async {
      SharedPreferences.setMockInitialValues({
        'user_phone': '8078643910',
        'user_name': 'Rajat Joshi',
        'is_onboarded': true,
      });
      final prefs = await SharedPreferences.getInstance();
      final localStorage = LocalStorageService(prefs);

      await tester.binding.setSurfaceSize(const Size(450, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(buildAdminApp(localStorage));
      await tester.pumpAndSettle();

      // On Tab 0, locate profile avatar in HomeTabContent AppBar
      final avatarFinder = find.byWidgetPredicate((widget) {
        return widget is InkWell &&
            widget.child is Container &&
            (widget.child as Container).decoration is BoxDecoration &&
            ((widget.child as Container).decoration as BoxDecoration).shape ==
                BoxShape.circle;
      });

      expect(avatarFinder, findsOneWidget);
      await tester.tap(avatarFinder);
      await tester.pumpAndSettle();

      // Bottom bar index should have switched to Tab 2 (Profile)
      final bottomNav =
          tester.widget<BottomNavigationBar>(find.byType(BottomNavigationBar));
      expect(bottomNav.currentIndex, 2);
      expect(find.byType(AdminProfileScreen), findsOneWidget);
      expect(find.text('Customer Queries'), findsOneWidget);

      // Android back returns to Tab 0
      final popHandled = await tester.binding.handlePopRoute();
      expect(popHandled, isTrue);
      await tester.pumpAndSettle();

      final bottomNavReturned =
          tester.widget<BottomNavigationBar>(find.byType(BottomNavigationBar));
      expect(bottomNavReturned.currentIndex, 0);
    });
  });
}
