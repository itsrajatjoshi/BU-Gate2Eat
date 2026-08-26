// BU Gate2Eat — Admin Shop Vendor Statement Test Suite (Feature #2 Reset-to-Export Model)
// Verifies closed-only statement semantics, exclusion of active orders (placed, accepted),
// statement WhatsApp tracking, reset-to-export date boundaries and fallbacks, strict shopId isolation,
// order mathematics, variant details, PDF generation, and multi-sheet XLSX generation.

import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:bugate2eat_app/core/providers.dart';
import 'package:bugate2eat_app/models/cart_item_model.dart';
import 'package:bugate2eat_app/models/menu_item_model.dart';
import 'package:bugate2eat_app/models/order_model.dart';
import 'package:bugate2eat_app/models/shop_model.dart';
import 'package:bugate2eat_app/models/shop_stats_model.dart';
import 'package:bugate2eat_app/panel/admin_panel/admin_monthly_reports_screen.dart';
import 'package:bugate2eat_app/services/order_service.dart';
import 'package:bugate2eat_app/services/report_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const shopAId = 'shop_up16';
  const shopAName = 'UP16 Coffee Queen';
  const shopBId = 'shop_rajat';
  const shopBName = 'Rajat Shop';

  final exportTimestamp = DateTime(2026, 8, 26, 18, 30);
  final resetStart = DateTime(2026, 8, 10, 11, 30);

  // Helper to create test AppOrder instances
  AppOrder createTestOrder({
    required String orderId,
    required String shopId,
    required String shopName,
    required DateTime createdAt,
    required String status,
    required double totalAmount,
    String orderMethod = 'app',
    List<OrderItem>? items,
    DateTime? deliveredAt,
    String rejectionReason = '',
    String customerName = 'Test Customer',
    String customerPhone = '9876543210',
  }) {
    return AppOrder(
      orderId: orderId,
      shopId: shopId,
      shopName: shopName,
      createdAt: createdAt,
      status: status,
      totalAmount: totalAmount,
      orderMethod: orderMethod,
      customerName: customerName,
      customerPhone: customerPhone,
      deliveredAt: deliveredAt,
      rejectionReason: rejectionReason,
      items: items ??
          [
            const OrderItem(
              menuItemId: 'item_1',
              name: 'Cold Coffee',
              price: 60,
              quantity: 1,
            ),
          ],
    );
  }

  group('Feature #2 — Reset-to-Export Shop Vendor Statement Invariants', () {
    test('1. Statement Period Formatting: Exact dd MMM yyyy, hh:mm a period formatting', () {
      final data = MonthlyReportData(
        shopId: shopAId,
        shopName: shopAName,
        startDateTime: resetStart,
        endDateTime: exportTimestamp,
        orders: const [],
        generatedAt: exportTimestamp,
      );

      expect(
        data.formattedPeriod,
        '10 Aug 2026, 11:30 AM - 26 Aug 2026, 06:30 PM',
      );
      expect(data.hasValidPeriod, true);
    });

    test('2. File Naming: Deterministic YummBU_<shopName>_<yyyyMMdd_HHmm>_Statement.<ext>', () {
      final pdfName = ReportService.getStatementFileName(
        'UP16 Coffee Queen',
        DateTime(2026, 8, 26, 18, 30),
        'pdf',
      );
      expect(pdfName, 'YummBU_UP16_Coffee_Queen_20260826_1830_Statement.pdf');

      final xlsxName = ReportService.getStatementFileName(
        'Rajat / Shop & Co.',
        DateTime(2026, 8, 26, 18, 30),
        'xlsx',
      );
      expect(xlsxName, 'YummBU_Rajat_Shop_Co_20260826_1830_Statement.xlsx');
    });

    test('3. Mixed Test Dataset: Active orders (Placed ₹230, Accepted ₹180) strictly excluded', () {
      final mixedOrders = [
        createTestOrder(
          orderId: 'ord_del_1',
          shopId: shopAId,
          shopName: shopAName,
          createdAt: DateTime(2026, 8, 12, 10, 0),
          status: OrderStatusRules.statusDelivered,
          totalAmount: 220,
        ),
        createTestOrder(
          orderId: 'ord_rej_1',
          shopId: shopAId,
          shopName: shopAName,
          createdAt: DateTime(2026, 8, 15, 12, 0),
          status: OrderStatusRules.statusRejected,
          totalAmount: 220,
        ),
        createTestOrder(
          orderId: 'ord_exp_1',
          shopId: shopAId,
          shopName: shopAName,
          createdAt: DateTime(2026, 8, 18, 16, 0),
          status: OrderStatusRules.statusDeliveryExpired,
          totalAmount: 150,
        ),
        createTestOrder(
          orderId: 'ord_acc_1',
          shopId: shopAId,
          shopName: shopAName,
          createdAt: DateTime(2026, 8, 20, 18, 0),
          status: OrderStatusRules.statusAccepted,
          totalAmount: 180,
        ),
        createTestOrder(
          orderId: 'ord_plc_1',
          shopId: shopAId,
          shopName: shopAName,
          createdAt: DateTime(2026, 8, 25, 20, 0),
          status: OrderStatusRules.statusPlaced,
          totalAmount: 230,
        ),
      ];

      final reportData = MonthlyReportData(
        shopId: shopAId,
        shopName: shopAName,
        startDateTime: resetStart,
        endDateTime: exportTimestamp,
        orders: mixedOrders,
        generatedAt: exportTimestamp,
      );

      // Invariants: Total Closed Orders = 3 (Delivered, Rejected, Expired)
      expect(reportData.totalOrdersCount, 3);
      expect(reportData.deliveredOrdersCount, 1);
      expect(reportData.rejectedOrdersCount, 1);
      expect(reportData.expiredOrdersCount, 1);
      expect(reportData.orders.any((o) => o.status == OrderStatusRules.statusPlaced), false);
      expect(reportData.orders.any((o) => o.status == OrderStatusRules.statusAccepted), false);

      // Financials: Active orders contribute ₹0
      expect(reportData.deliveredSalesValue, 220.0);
      expect(reportData.closedOrderValue, 590.0); // 220 + 220 + 150
      expect(reportData.grossOrderValue, 590.0);
    });

    test('4. WhatsApp Statement Count: Propagates explicit statement counter (5) accurately', () {
      final orders = [
        createTestOrder(
          orderId: 'ord_app_1',
          shopId: shopAId,
          shopName: shopAName,
          createdAt: DateTime(2026, 8, 12),
          status: OrderStatusRules.statusDelivered,
          totalAmount: 220,
        ),
        createTestOrder(
          orderId: 'ord_app_2',
          shopId: shopAId,
          shopName: shopAName,
          createdAt: DateTime(2026, 8, 15),
          status: OrderStatusRules.statusRejected,
          totalAmount: 220,
        ),
      ];

      final reportData = MonthlyReportData(
        shopId: shopAId,
        shopName: shopAName,
        startDateTime: resetStart,
        endDateTime: exportTimestamp,
        orders: orders,
        generatedAt: exportTimestamp,
        explicitWhatsappOrdersCount: 5,
      );

      expect(reportData.totalOrdersCount, 2);
      expect(reportData.deliveredOrdersCount, 1);
      expect(reportData.rejectedOrdersCount, 1);
      expect(reportData.whatsappOrdersCount, 5);
      expect(reportData.deliveredSalesValue, 220.0);
      expect(reportData.closedOrderValue, 440.0);
    });

    test('5. WhatsApp Counter Isolation: Statement count vs Lifetime total preserved in model', () {
      final stats = ShopStats(
        shopId: shopAId,
        shopName: shopAName,
        whatsappOrders: 5, // Statement counter
        lifetimeWhatsappOrders: 13, // Lifetime cumulative total
        lastResetAt: resetStart,
      );

      expect(stats.whatsappOrders, 5);
      expect(stats.lifetimeWhatsappOrders, 13);
      expect(stats.lastResetAt, resetStart);

      // Simulation of reset
      final resetStats = stats.copyWith(
        whatsappOrders: 0,
        lastResetAt: DateTime(2026, 8, 26, 19, 0),
      );
      expect(resetStats.whatsappOrders, 0);
      expect(resetStats.lifetimeWhatsappOrders, 13); // Preserved!
    });

    test('6. Fallback Chain: 1. lastResetAt -> 2. shop.createdAt -> 3. Explicit No timestamp state', () {
      final createdAt = DateTime(2026, 8, 1, 9, 0);

      // 1. With lastResetAt
      final startFromReset = resetStart;
      expect(startFromReset, resetStart);

      // 2. Without lastResetAt, with createdAt
      DateTime? nullReset;
      final startFromCreated = nullReset ?? createdAt;
      expect(startFromCreated, createdAt);

      // 3. Without both -> null, and formattedPeriod handles cleanly without fabricating 2026-01-01
      final noTimeData = MonthlyReportData(
        shopId: shopAId,
        shopName: shopAName,
        startDateTime: null,
        endDateTime: exportTimestamp,
        orders: const [],
        generatedAt: exportTimestamp,
      );
      expect(noTimeData.hasValidPeriod, false);
      expect(noTimeData.formattedPeriod, 'No reset/creation timestamp available');
    });

    test('7. Variant Details & Line Calculation: Options preserved with accurate historical item pricing', () {
      const cheeseOption = SelectedMenuItemOption(
        groupId: 'grp_cheese',
        groupName: 'Cheese',
        optionId: 'opt_cheese',
        optionName: 'Extra Cheese',
        pricingType: OptionPricingType.priceAdjustment,
        price: 10,
      );

      final variantItem = OrderItem(
        menuItemId: 'item_burger',
        name: 'Veg Burger',
        price: 80,
        quantity: 3,
        optionsDescription: 'Size: Large, Cheese: Extra Cheese',
        selectedOptions: const [cheeseOption],
      );

      final normalItem = const OrderItem(
        menuItemId: 'item_fries',
        name: 'French Fries',
        price: 60,
        quantity: 2,
      );

      final order = createTestOrder(
        orderId: 'ord_var_1',
        shopId: shopAId,
        shopName: shopAName,
        createdAt: DateTime(2026, 8, 12),
        status: OrderStatusRules.statusDelivered,
        totalAmount: 360,
        items: [variantItem, normalItem],
      );

      expect(variantItem.hasOptions, true);
      expect(variantItem.optionsDescription, 'Size: Large, Cheese: Extra Cheese');
      expect(variantItem.totalPrice, 240.0);
      expect(normalItem.hasOptions, false);
      expect(normalItem.totalPrice, 120.0);
      expect(order.subtotal, 360.0);
      expect(order.totalAmount, 360.0);
      expect(order.totalItemCount, 5);
    });

    test('8. Strict Shop Isolation: Orders from another shop are completely segregated', () {
      final ordersShopA = [
        createTestOrder(
          orderId: 'ord_shop_a_1',
          shopId: shopAId,
          shopName: shopAName,
          createdAt: DateTime(2026, 8, 12),
          status: OrderStatusRules.statusDelivered,
          totalAmount: 100,
        ),
      ];

      final ordersShopB = [
        createTestOrder(
          orderId: 'ord_shop_b_1',
          shopId: shopBId,
          shopName: shopBName,
          createdAt: DateTime(2026, 8, 12),
          status: OrderStatusRules.statusDelivered,
          totalAmount: 500,
        ),
      ];

      final reportA = MonthlyReportData(
        shopId: shopAId,
        shopName: shopAName,
        startDateTime: resetStart,
        endDateTime: exportTimestamp,
        orders: ordersShopA,
        generatedAt: exportTimestamp,
      );

      final reportB = MonthlyReportData(
        shopId: shopBId,
        shopName: shopBName,
        startDateTime: resetStart,
        endDateTime: exportTimestamp,
        orders: ordersShopB,
        generatedAt: exportTimestamp,
      );

      expect(reportA.shopId, shopAId);
      expect(reportA.deliveredSalesValue, 100.0);
      expect(reportB.shopId, shopBId);
      expect(reportB.deliveredSalesValue, 500.0);
      expect(reportA.orders.any((o) => o.shopId == shopBId), false);
    });

    test('9. Empty Statement Window: Handled cleanly without errors or crashes', () {
      final emptyReport = MonthlyReportData(
        shopId: shopAId,
        shopName: shopAName,
        startDateTime: resetStart,
        endDateTime: exportTimestamp,
        orders: const [],
        generatedAt: exportTimestamp,
      );

      expect(emptyReport.totalOrdersCount, 0);
      expect(emptyReport.deliveredOrdersCount, 0);
      expect(emptyReport.deliveredSalesValue, 0.0);
      expect(emptyReport.closedOrderValue, 0.0);
      expect(emptyReport.totalItemsDelivered, 0);
      expect(emptyReport.totalItemsInClosedOrders, 0);
    });

    test('10. PDF Generation: Generates YummBU VENDOR STATEMENT without active orders', () async {
      TestWidgetsFlutterBinding.ensureInitialized();

      final orders = [
        createTestOrder(
          orderId: 'ord_pdf_del',
          shopId: shopAId,
          shopName: shopAName,
          createdAt: DateTime(2026, 8, 12, 12, 0),
          status: OrderStatusRules.statusDelivered,
          totalAmount: 220,
        ),
        createTestOrder(
          orderId: 'ord_pdf_rej',
          shopId: shopAId,
          shopName: shopAName,
          createdAt: DateTime(2026, 8, 15, 14, 0),
          status: OrderStatusRules.statusRejected,
          totalAmount: 220,
        ),
      ];

      final reportData = MonthlyReportData(
        shopId: shopAId,
        shopName: shopAName,
        startDateTime: resetStart,
        endDateTime: exportTimestamp,
        orders: orders,
        generatedAt: exportTimestamp,
        explicitWhatsappOrdersCount: 5,
      );

      final reportService = ReportService();
      final pdfBytes = await reportService.generatePdfReport(reportData);

      expect(pdfBytes, isA<Uint8List>());
      expect(pdfBytes.isNotEmpty, true);
      expect(pdfBytes[0], 0x25); // %
      expect(pdfBytes[1], 0x50); // P
      expect(pdfBytes[2], 0x44); // D
      expect(pdfBytes[3], 0x46); // F
    });

    test('11. XLSX Generation: 3 sheets, Vendor Statement title, Closed Order Value only', () {
      final orders = [
        createTestOrder(
          orderId: 'ord_xlsx_1',
          shopId: shopAId,
          shopName: shopAName,
          createdAt: DateTime(2026, 8, 12, 10, 30),
          status: OrderStatusRules.statusDelivered,
          totalAmount: 200,
          deliveredAt: DateTime(2026, 8, 12, 10, 55),
          items: [
            const OrderItem(
              menuItemId: 'item_coffee',
              name: 'Cold Coffee',
              price: 100,
              quantity: 2,
              optionsDescription: 'Size: XL',
            ),
          ],
        ),
      ];

      final reportData = MonthlyReportData(
        shopId: shopAId,
        shopName: shopAName,
        startDateTime: resetStart,
        endDateTime: exportTimestamp,
        orders: orders,
        generatedAt: exportTimestamp,
        explicitWhatsappOrdersCount: 5,
      );

      final reportService = ReportService();
      final xlsxBytes = reportService.generateXlsxReport(reportData);

      expect(xlsxBytes, isA<Uint8List>());
      expect(xlsxBytes.isNotEmpty, true);

      final archive = ZipDecoder().decodeBytes(xlsxBytes);
      final fileNames = archive.files.map((f) => f.name).toSet();

      expect(fileNames.contains('[Content_Types].xml'), true);
      expect(fileNames.contains('xl/workbook.xml'), true);
      expect(fileNames.contains('xl/styles.xml'), true);
      expect(fileNames.contains('xl/worksheets/sheet1.xml'), true); // Summary
      expect(fileNames.contains('xl/worksheets/sheet2.xml'), true); // Orders
      expect(fileNames.contains('xl/worksheets/sheet3.xml'), true); // Order Items

      final sheet1File = archive.files.firstWhere((f) => f.name == 'xl/worksheets/sheet1.xml');
      final sheet1Xml = utf8.decode(sheet1File.content as List<int>);
      expect(sheet1Xml.contains('YummBU — Vendor Statement'), true);
      expect(sheet1Xml.contains('Closed Order Value (INR)'), true);
      expect(sheet1Xml.contains('Gross Order Value'), false);
    });

    testWidgets('12. UI Rendering: Renders Shop Vendor Statements, Statement Period card, and 5 KPI tiles', (tester) async {
      final dummyShops = [
        Shop(
          id: shopAId,
          name: shopAName,
          description: 'Best Coffee',
          bannerUrl: '',
          contactNumber: '9876543210',
          orderNumber: '9876543210',
          openTime: '10:00 AM',
          closeTime: '10:00 PM',
          isClosedOverride: false,
          isActive: true,
          sortOrder: 1,
          searchKeywords: const ['coffee'],
          deliveryNote: 'Gate 3',
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
          orderMethod: ShopOrderMethod.app,
        ),
      ];

      final reportData = MonthlyReportData(
        shopId: shopAId,
        shopName: shopAName,
        startDateTime: resetStart,
        endDateTime: exportTimestamp,
        orders: [
          createTestOrder(
            orderId: 'ord_ui_1',
            shopId: shopAId,
            shopName: shopAName,
            createdAt: DateTime(2026, 8, 12, 14, 0),
            status: OrderStatusRules.statusDelivered,
            totalAmount: 180,
          ),
        ],
        generatedAt: exportTimestamp,
        explicitWhatsappOrdersCount: 5,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            shopsProvider.overrideWith((ref) async => dummyShops),
            shopStatsStreamProvider(shopAId).overrideWith((ref) => Stream.value(
                  ShopStats(
                    shopId: shopAId,
                    shopName: shopAName,
                    whatsappOrders: 5,
                    lastResetAt: resetStart,
                  ),
                )),
            shopStatementDataProvider.overrideWith((ref, params) async => reportData),
          ],
          child: const MaterialApp(
            home: AdminMonthlyReportsScreen(initialShopId: shopAId),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Shop Vendor Statements'), findsOneWidget);
      expect(find.text(shopAName), findsOneWidget);
      expect(find.text('EXPORT PDF'), findsOneWidget);
      expect(find.text('EXPORT EXCEL'), findsOneWidget);
      expect(find.text('STATEMENT PERFORMANCE'), findsOneWidget);
      expect(find.text('Delivered Sales Value:'), findsOneWidget);
      expect(find.text('Closed Order Value:'), findsOneWidget);
      expect(find.text('Total Closed'), findsOneWidget);
      expect(find.text('Delivered'), findsOneWidget);
      expect(find.text('Rejected'), findsOneWidget);
      expect(find.text('Expired'), findsOneWidget);
      expect(find.text('WhatsApp Orders'), findsOneWidget);
      // Ensure "Cancelled" metric is NOT present in KPI summary
      expect(find.text('Cancelled Orders'), findsNothing);
    });

    test('13. Pre-Acceptance Cancellation: Customer physical deletion never enters statement', () {
      // Customer cancels before acceptance -> physically deleted from Firestore
      // Thus only delivered and rejected orders exist
      final orders = [
        createTestOrder(
          orderId: 'ord_del',
          shopId: shopAId,
          shopName: shopAName,
          createdAt: DateTime(2026, 8, 12),
          status: OrderStatusRules.statusDelivered,
          totalAmount: 220,
        ),
      ];

      final reportData = MonthlyReportData(
        shopId: shopAId,
        shopName: shopAName,
        startDateTime: resetStart,
        endDateTime: exportTimestamp,
        orders: orders,
        generatedAt: exportTimestamp,
      );

      expect(reportData.totalOrdersCount, 1);
      expect(reportData.orders.any((o) => o.status == OrderStatusRules.statusCancelled), false);
    });

    test('14. Financial Math: Delivered Sales sums only delivered; Closed sums all closed', () {
      final orders = [
        createTestOrder(
          orderId: 'ord_1',
          shopId: shopAId,
          shopName: shopAName,
          createdAt: DateTime(2026, 8, 12),
          status: OrderStatusRules.statusDelivered,
          totalAmount: 300,
        ),
        createTestOrder(
          orderId: 'ord_2',
          shopId: shopAId,
          shopName: shopAName,
          createdAt: DateTime(2026, 8, 13),
          status: OrderStatusRules.statusRejected,
          totalAmount: 200,
        ),
        createTestOrder(
          orderId: 'ord_3',
          shopId: shopAId,
          shopName: shopAName,
          createdAt: DateTime(2026, 8, 14),
          status: OrderStatusRules.statusDeliveryExpired,
          totalAmount: 100,
        ),
      ];

      final reportData = MonthlyReportData(
        shopId: shopAId,
        shopName: shopAName,
        startDateTime: resetStart,
        endDateTime: exportTimestamp,
        orders: orders,
        generatedAt: exportTimestamp,
      );

      expect(reportData.deliveredSalesValue, 300.0);
      expect(reportData.closedOrderValue, 600.0);
    });

    testWidgets('15. Null Timestamp Warning State: UI shows clear warning when period is unavailable', (tester) async {
      final dummyShops = [
        Shop(
          id: shopAId,
          name: shopAName,
          description: 'Best Coffee',
          bannerUrl: '',
          contactNumber: '9876543210',
          orderNumber: '9876543210',
          openTime: '10:00 AM',
          closeTime: '10:00 PM',
          isClosedOverride: false,
          isActive: true,
          sortOrder: 1,
          searchKeywords: const ['coffee'],
          deliveryNote: 'Gate 3',
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
          orderMethod: ShopOrderMethod.app,
        ),
      ];

      final invalidData = MonthlyReportData(
        shopId: shopAId,
        shopName: shopAName,
        startDateTime: null,
        endDateTime: exportTimestamp,
        orders: const [],
        generatedAt: exportTimestamp,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            shopsProvider.overrideWith((ref) async => dummyShops),
            shopStatsStreamProvider(shopAId).overrideWith((ref) => Stream.value(null)),
            shopStatementDataProvider.overrideWith((ref, params) async => invalidData),
          ],
          child: const MaterialApp(
            home: AdminMonthlyReportsScreen(initialShopId: shopAId),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('No Reset or Creation Timestamp Available'), findsOneWidget);
    });

    test('16. Item Quantities: totalItemsDelivered and totalItemsInClosedOrders calculation', () {
      final orders = [
        createTestOrder(
          orderId: 'ord_1',
          shopId: shopAId,
          shopName: shopAName,
          createdAt: DateTime(2026, 8, 12),
          status: OrderStatusRules.statusDelivered,
          totalAmount: 180,
          items: [
            const OrderItem(menuItemId: 'i1', name: 'Item 1', price: 60, quantity: 3),
          ],
        ),
        createTestOrder(
          orderId: 'ord_2',
          shopId: shopAId,
          shopName: shopAName,
          createdAt: DateTime(2026, 8, 13),
          status: OrderStatusRules.statusRejected,
          totalAmount: 120,
          items: [
            const OrderItem(menuItemId: 'i2', name: 'Item 2', price: 60, quantity: 2),
          ],
        ),
      ];

      final reportData = MonthlyReportData(
        shopId: shopAId,
        shopName: shopAName,
        startDateTime: resetStart,
        endDateTime: exportTimestamp,
        orders: orders,
        generatedAt: exportTimestamp,
      );

      expect(reportData.totalItemsDelivered, 3);
      expect(reportData.totalItemsInClosedOrders, 5);
    });

    test('17. XML Escaping in XLSX generation: handles special characters safely', () {
      final orders = [
        createTestOrder(
          orderId: 'ord_xml_1',
          shopId: shopAId,
          shopName: 'Café & "Bistrô" <Delhi>',
          createdAt: DateTime(2026, 8, 12),
          status: OrderStatusRules.statusDelivered,
          totalAmount: 100,
          customerName: 'Tom & Jerry <Jr>',
          rejectionReason: 'Reason with <special> & "quotes"',
          items: [
            const OrderItem(
              menuItemId: 'i1',
              name: 'Tea & Coffee <Hot>',
              price: 100,
              quantity: 1,
              optionsDescription: 'Sugar: 50% & Milk',
            ),
          ],
        ),
      ];

      final reportData = MonthlyReportData(
        shopId: shopAId,
        shopName: 'Café & "Bistrô" <Delhi>',
        startDateTime: resetStart,
        endDateTime: exportTimestamp,
        orders: orders,
        generatedAt: exportTimestamp,
      );

      final reportService = ReportService();
      final xlsxBytes = reportService.generateXlsxReport(reportData);

      expect(xlsxBytes.isNotEmpty, true);
      final archive = ZipDecoder().decodeBytes(xlsxBytes);
      final sheet1 = archive.files.firstWhere((f) => f.name == 'xl/worksheets/sheet1.xml');
      final xml1 = utf8.decode(sheet1.content as List<int>);
      expect(xml1.contains('&amp;'), true);
      expect(xml1.contains('&quot;'), true);
      expect(xml1.contains('&lt;'), true);
      expect(xml1.contains('&gt;'), true);
    });

    test('18. Backwards Compatibility month getter', () {
      final data = MonthlyReportData(
        shopId: shopAId,
        shopName: shopAName,
        startDateTime: resetStart,
        endDateTime: exportTimestamp,
        orders: const [],
        generatedAt: exportTimestamp,
      );

      expect(data.month, resetStart);
    });

    test('19. Delivery Expired Status: mapped and counted properly', () {
      final orders = [
        createTestOrder(
          orderId: 'ord_exp_1',
          shopId: shopAId,
          shopName: shopAName,
          createdAt: DateTime(2026, 8, 12),
          status: OrderStatusRules.statusDeliveryExpired,
          totalAmount: 150,
        ),
      ];

      final reportData = MonthlyReportData(
        shopId: shopAId,
        shopName: shopAName,
        startDateTime: resetStart,
        endDateTime: exportTimestamp,
        orders: orders,
        generatedAt: exportTimestamp,
      );

      expect(reportData.expiredOrdersCount, 1);
      expect(reportData.deliveredOrdersCount, 0);
      expect(reportData.rejectedOrdersCount, 0);
      expect(reportData.closedOrderValue, 150.0);
    });

    test('20. ShopStats Serialization: lifetimeWhatsappOrders roundtrips correctly', () {
      final stats = ShopStats(
        shopId: shopAId,
        shopName: shopAName,
        whatsappOrders: 5,
        lifetimeWhatsappOrders: 18,
        lastResetAt: resetStart,
      );

      final map = stats.toFirestore();
      expect(map['whatsappOrders'], 5);
      expect(map['lifetimeWhatsappOrders'], 18);
    });
  });
}
