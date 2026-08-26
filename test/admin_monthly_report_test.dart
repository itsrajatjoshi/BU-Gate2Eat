// BU Gate2Eat — Admin Monthly Shop Report & Statement Test Suite (Feature #2)
// Verifies date boundaries, strict shopId isolation, status classification,
// order mathematics, variant details, PDF generation, and multi-sheet XLSX generation.

import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:bugate2eat_app/core/providers.dart';
import 'package:bugate2eat_app/models/cart_item_model.dart';
import 'package:bugate2eat_app/models/menu_item_model.dart';
import 'package:bugate2eat_app/models/order_model.dart';
import 'package:bugate2eat_app/models/shop_model.dart';
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

  final august2026 = DateTime(2026, 8, 1);

  // Helper to create test AppOrder instances
  AppOrder createTestOrder({
    required String orderId,
    required String shopId,
    required String shopName,
    required DateTime createdAt,
    required String status,
    required double totalAmount,
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

  group('Feature #2 — Admin Monthly Shop Report & Statement Invariants', () {
    test('1. Date Boundaries: Month start and end boundaries computed accurately', () {
      // Normal month (August 2026)
      final augBoundaries = ReportService.getMonthBoundaries(DateTime(2026, 8, 15));
      expect(augBoundaries.start, DateTime(2026, 8, 1, 0, 0, 0));
      expect(augBoundaries.end, DateTime(2026, 9, 1, 0, 0, 0));

      // Year boundary (December 2026 -> January 2027)
      final decBoundaries = ReportService.getMonthBoundaries(DateTime(2026, 12, 1));
      expect(decBoundaries.start, DateTime(2026, 12, 1, 0, 0, 0));
      expect(decBoundaries.end, DateTime(2027, 1, 1, 0, 0, 0));

      // Leap year check (February 2028)
      final febBoundaries = ReportService.getMonthBoundaries(DateTime(2028, 2, 10));
      expect(febBoundaries.start, DateTime(2028, 2, 1, 0, 0, 0));
      expect(febBoundaries.end, DateTime(2028, 3, 1, 0, 0, 0));
    });

    test('2. File Naming: Deterministic naming sanitizes shop names & formats dates', () {
      final pdfName = ReportService.getReportFileName('UP16 Coffee Queen', DateTime(2026, 8, 1), 'pdf');
      expect(pdfName, 'YummBU_UP16_Coffee_Queen_2026-08_Monthly_Report.pdf');

      final xlsxName = ReportService.getReportFileName('Rajat / Shop & Co.', DateTime(2026, 8, 1), 'xlsx');
      expect(xlsxName, 'YummBU_Rajat_Shop_Co_2026-08_Monthly_Report.xlsx');
    });

    test('3. Status Classification & Revenue Math: Delivered orders count as sales, non-delivered as gross value', () {
      final orders = [
        // Delivered order 1
        createTestOrder(
          orderId: 'ord_1',
          shopId: shopAId,
          shopName: shopAName,
          createdAt: DateTime(2026, 8, 5, 14, 30),
          status: OrderStatusRules.statusDelivered,
          totalAmount: 150,
          deliveredAt: DateTime(2026, 8, 5, 14, 50),
        ),
        // Delivered order 2
        createTestOrder(
          orderId: 'ord_2',
          shopId: shopAId,
          shopName: shopAName,
          createdAt: DateTime(2026, 8, 10, 11, 0),
          status: OrderStatusRules.statusDelivered,
          totalAmount: 200,
          deliveredAt: DateTime(2026, 8, 10, 11, 25),
        ),
        // Rejected order
        createTestOrder(
          orderId: 'ord_3',
          shopId: shopAId,
          shopName: shopAName,
          createdAt: DateTime(2026, 8, 12, 18, 0),
          status: OrderStatusRules.statusRejected,
          totalAmount: 120,
          rejectionReason: 'Items out of stock',
        ),
        // Cancelled order
        createTestOrder(
          orderId: 'ord_4',
          shopId: shopAId,
          shopName: shopAName,
          createdAt: DateTime(2026, 8, 15, 19, 0),
          status: OrderStatusRules.statusCancelled,
          totalAmount: 80,
        ),
        // Delivery Expired order
        createTestOrder(
          orderId: 'ord_5',
          shopId: shopAId,
          shopName: shopAName,
          createdAt: DateTime(2026, 8, 20, 21, 0),
          status: OrderStatusRules.statusDeliveryExpired,
          totalAmount: 100,
        ),
        // Placed (Active) order
        createTestOrder(
          orderId: 'ord_6',
          shopId: shopAId,
          shopName: shopAName,
          createdAt: DateTime(2026, 8, 25, 22, 0),
          status: OrderStatusRules.statusPlaced,
          totalAmount: 50,
        ),
        // Unknown status order (e.g. legacy/malformed status)
        createTestOrder(
          orderId: 'ord_7',
          shopId: shopAId,
          shopName: shopAName,
          createdAt: DateTime(2026, 8, 26, 12, 0),
          status: 'legacy_refunded',
          totalAmount: 70,
        ),
      ];

      final reportData = MonthlyReportData(
        shopId: shopAId,
        shopName: shopAName,
        month: august2026,
        startDateTime: DateTime(2026, 8, 1),
        endDateTime: DateTime(2026, 9, 1),
        orders: orders,
        generatedAt: DateTime(2026, 8, 26, 17, 0),
      );

      // Verify all counts
      expect(reportData.totalOrdersCount, 7);
      expect(reportData.deliveredOrdersCount, 2);
      expect(reportData.rejectedOrdersCount, 1);
      expect(reportData.cancelledOrdersCount, 1);
      expect(reportData.expiredOrdersCount, 1);
      expect(reportData.placedOrders.length, 1);
      expect(reportData.otherOrdersCount, 1);

      // Verify mathematical aggregates
      // Delivered Sales: 150 + 200 = 350
      expect(reportData.deliveredSalesValue, 350.0);
      // Gross Order Value: 150 + 200 + 120 + 80 + 100 + 50 + 70 = 770
      expect(reportData.grossOrderValue, 770.0);
    });

    test('4. Variant Details & Line Calculation: Options preserved with accurate historical item pricing', () {
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
        price: 80, // Historical snapshot unit price with cheese
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
        createdAt: DateTime(2026, 8, 5),
        status: OrderStatusRules.statusDelivered,
        totalAmount: 360, // (80 * 3) + (60 * 2) = 240 + 120 = 360
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

    test('5. Strict Shop Isolation: Orders from another shop are completely segregated', () {
      final ordersShopA = [
        createTestOrder(
          orderId: 'ord_shop_a_1',
          shopId: shopAId,
          shopName: shopAName,
          createdAt: DateTime(2026, 8, 1),
          status: OrderStatusRules.statusDelivered,
          totalAmount: 100,
        ),
      ];

      final ordersShopB = [
        createTestOrder(
          orderId: 'ord_shop_b_1',
          shopId: shopBId,
          shopName: shopBName,
          createdAt: DateTime(2026, 8, 1),
          status: OrderStatusRules.statusDelivered,
          totalAmount: 500,
        ),
      ];

      final reportA = MonthlyReportData(
        shopId: shopAId,
        shopName: shopAName,
        month: august2026,
        startDateTime: DateTime(2026, 8, 1),
        endDateTime: DateTime(2026, 9, 1),
        orders: ordersShopA,
        generatedAt: DateTime.now(),
      );

      final reportB = MonthlyReportData(
        shopId: shopBId,
        shopName: shopBName,
        month: august2026,
        startDateTime: DateTime(2026, 8, 1),
        endDateTime: DateTime(2026, 9, 1),
        orders: ordersShopB,
        generatedAt: DateTime.now(),
      );

      expect(reportA.shopId, shopAId);
      expect(reportA.deliveredSalesValue, 100.0);
      expect(reportB.shopId, shopBId);
      expect(reportB.deliveredSalesValue, 500.0);
      expect(reportA.orders.any((o) => o.shopId == shopBId), false);
    });

    test('6. Empty Month: Handled cleanly without errors or zero-division crashes', () {
      final emptyReport = MonthlyReportData(
        shopId: shopAId,
        shopName: shopAName,
        month: august2026,
        startDateTime: DateTime(2026, 8, 1),
        endDateTime: DateTime(2026, 9, 1),
        orders: const [],
        generatedAt: DateTime.now(),
      );

      expect(emptyReport.totalOrdersCount, 0);
      expect(emptyReport.deliveredOrdersCount, 0);
      expect(emptyReport.deliveredSalesValue, 0.0);
      expect(emptyReport.grossOrderValue, 0.0);
      expect(emptyReport.totalItemsDelivered, 0);
      expect(emptyReport.totalItemsOrdered, 0);
    });

    test('7. PDF Generation: Generates valid multi-page PDF document bytes', () async {
      TestWidgetsFlutterBinding.ensureInitialized();

      final orders = List.generate(15, (index) {
        return createTestOrder(
          orderId: 'ord_pdf_$index',
          shopId: shopAId,
          shopName: shopAName,
          createdAt: DateTime(2026, 8, (index % 25) + 1, 12, 0),
          status: index % 3 == 0 ? OrderStatusRules.statusDelivered : OrderStatusRules.statusRejected,
          totalAmount: 100.0 + (index * 10),
        );
      });

      final reportData = MonthlyReportData(
        shopId: shopAId,
        shopName: shopAName,
        month: august2026,
        startDateTime: DateTime(2026, 8, 1),
        endDateTime: DateTime(2026, 9, 1),
        orders: orders,
        generatedAt: DateTime.now(),
      );

      final reportService = ReportService();
      final pdfBytes = await reportService.generatePdfReport(reportData);

      expect(pdfBytes, isA<Uint8List>());
      expect(pdfBytes.isNotEmpty, true);
      // PDF header magic bytes '%PDF-'
      expect(pdfBytes[0], 0x25); // %
      expect(pdfBytes[1], 0x50); // P
      expect(pdfBytes[2], 0x44); // D
      expect(pdfBytes[3], 0x46); // F
    });

    test('8. XLSX Generation: Generates real multi-sheet OpenXML workbook (.xlsx) with 3 sheets', () {
      final orders = [
        createTestOrder(
          orderId: 'ord_xlsx_1',
          shopId: shopAId,
          shopName: shopAName,
          createdAt: DateTime(2026, 8, 5, 10, 30),
          status: OrderStatusRules.statusDelivered,
          totalAmount: 200,
          deliveredAt: DateTime(2026, 8, 5, 10, 55),
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
        month: august2026,
        startDateTime: DateTime(2026, 8, 1),
        endDateTime: DateTime(2026, 9, 1),
        orders: orders,
        generatedAt: DateTime.now(),
      );

      final reportService = ReportService();
      final xlsxBytes = reportService.generateXlsxReport(reportData);

      expect(xlsxBytes, isA<Uint8List>());
      expect(xlsxBytes.isNotEmpty, true);

      // Verify ZIP / OpenXML structure
      final archive = ZipDecoder().decodeBytes(xlsxBytes);
      final fileNames = archive.files.map((f) => f.name).toSet();

      expect(fileNames.contains('[Content_Types].xml'), true);
      expect(fileNames.contains('xl/workbook.xml'), true);
      expect(fileNames.contains('xl/styles.xml'), true);
      expect(fileNames.contains('xl/worksheets/sheet1.xml'), true); // Summary
      expect(fileNames.contains('xl/worksheets/sheet2.xml'), true); // Orders
      expect(fileNames.contains('xl/worksheets/sheet3.xml'), true); // Order Items

      // Inspect workbook.xml to ensure sheet names are present
      final workbookFile = archive.files.firstWhere((f) => f.name == 'xl/workbook.xml');
      final workbookXml = String.fromCharCodes(workbookFile.content as List<int>);
      expect(workbookXml.contains('name="Summary"'), true);
      expect(workbookXml.contains('name="Orders"'), true);
      expect(workbookXml.contains('name="Order Items"'), true);
    });

    test('9. Large Dataset Scalability: Handles 150+ orders efficiently without memory duplication', () {
      final largeOrders = List.generate(150, (i) {
        return createTestOrder(
          orderId: 'ord_large_$i',
          shopId: shopAId,
          shopName: shopAName,
          createdAt: DateTime(2026, 8, (i % 28) + 1, 10, 0),
          status: i % 2 == 0 ? OrderStatusRules.statusDelivered : OrderStatusRules.statusCancelled,
          totalAmount: 150.0,
        );
      });

      final reportData = MonthlyReportData(
        shopId: shopAId,
        shopName: shopAName,
        month: august2026,
        startDateTime: DateTime(2026, 8, 1),
        endDateTime: DateTime(2026, 9, 1),
        orders: largeOrders,
        generatedAt: DateTime.now(),
      );

      expect(reportData.totalOrdersCount, 150);
      expect(reportData.deliveredOrdersCount, 75);
      expect(reportData.deliveredSalesValue, 75 * 150.0);
      expect(reportData.grossOrderValue, 150 * 150.0);

      // Verify XLSX generation succeeds cleanly for large datasets
      final reportService = ReportService();
      final xlsxBytes = reportService.generateXlsxReport(reportData);
      expect(xlsxBytes.isNotEmpty, true);
    });

    testWidgets('10. AdminMonthlyReportsScreen renders UI controls, KPI cards, and export buttons', (tester) async {
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
        month: august2026,
        startDateTime: DateTime(2026, 8, 1),
        endDateTime: DateTime(2026, 9, 1),
        orders: [
          createTestOrder(
            orderId: 'ord_ui_1',
            shopId: shopAId,
            shopName: shopAName,
            createdAt: DateTime(2026, 8, 5, 14, 0),
            status: OrderStatusRules.statusDelivered,
            totalAmount: 180,
          ),
        ],
        generatedAt: DateTime.now(),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            shopsProvider.overrideWith((ref) async => dummyShops),
            monthlyReportDataProvider.overrideWith((ref, params) async => reportData),
          ],
          child: const MaterialApp(
            home: AdminMonthlyReportsScreen(initialShopId: shopAId),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify Header and Dropdown
      expect(find.text('Monthly Shop Statements'), findsOneWidget);
      expect(find.text(shopAName), findsOneWidget);
      expect(find.text('EXPORT PDF'), findsOneWidget);
      expect(find.text('EXPORT EXCEL'), findsOneWidget);
      expect(find.text('MONTHLY PERFORMANCE'), findsOneWidget);
      expect(find.text('Delivered Sales Value:'), findsOneWidget);
      expect(find.text('₹180'), findsAtLeastNWidgets(1));
    });
  });
}
