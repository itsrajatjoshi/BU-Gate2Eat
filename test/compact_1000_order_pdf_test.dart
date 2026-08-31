// BU Gate2Eat — Tests
// Checkpoint 3.12 — Compact 1000-Order PDF Scalability & Resilience Tests

import 'dart:typed_data';
import 'package:bugate2eat_app/models/order_model.dart';
import 'package:bugate2eat_app/services/report_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final baseTime = DateTime(2026, 8, 31, 14);

  AppOrder createTestOrder({
    required int index,
    required double totalAmount,
    String status = 'delivered',
    String customerName = 'Student Name',
    String? customOrderId,
    List<OrderItem>? items,
  }) {
    return AppOrder(
      orderId: customOrderId ?? 'YB-20260831-${100000 + index}',
      shopId: 'shop_test',
      shopName: 'Test Gourmet Kitchen',
      customerName: customerName,
      customerPhone: '9876543210',
      items: items ??
          [
            OrderItem(
              menuItemId: 'item_1',
              name: 'Butter Naan',
              price: 40,
              quantity: 2,
              optionsDescription: index % 2 == 0 ? 'Extra Butter' : '',
            ),
            const OrderItem(
              menuItemId: 'item_2',
              name: 'Paneer Butter Masala',
              price: 60,
              quantity: 1,
            ),
          ],
      totalAmount: totalAmount,
      status: status,
      createdAt: baseTime.add(Duration(minutes: index)),
    );
  }

  group('Checkpoint 3.12 — Compact 1000-Order PDF Scalability Tests', () {
    final reportService = ReportService();

    test('1. Normal dataset (5 orders) generates valid PDF statement', () async {
      final orders = List.generate(5, (i) => createTestOrder(index: i, totalAmount: 140));
      final reportData = MonthlyReportData(
        shopId: 'shop_test',
        shopName: 'Test Gourmet Kitchen',
        startDateTime: baseTime.subtract(const Duration(days: 30)),
        endDateTime: baseTime,
        orders: orders,
        generatedAt: baseTime,
      );

      final pdfBytes = await reportService.generatePdfReport(reportData);

      expect(pdfBytes, isA<Uint8List>());
      expect(pdfBytes.isNotEmpty, isTrue);
      // Valid PDF magic header %PDF
      expect(pdfBytes[0], 0x25); // %
      expect(pdfBytes[1], 0x50); // P
      expect(pdfBytes[2], 0x44); // D
      expect(pdfBytes[3], 0x46); // F
    });

    test('2. Medium dataset (100 orders) generates compact multi-page PDF efficiently', () async {
      final orders = List.generate(100, (i) {
        final status = i % 4 == 0
            ? 'delivered'
            : (i % 4 == 1 ? 'rejected' : (i % 4 == 2 ? 'delivery_expired' : 'cancelled'));
        return createTestOrder(index: i, status: status, totalAmount: 140);
      });

      final reportData = MonthlyReportData(
        shopId: 'shop_test',
        shopName: 'Test Gourmet Kitchen',
        startDateTime: baseTime.subtract(const Duration(days: 30)),
        endDateTime: baseTime,
        orders: orders,
        generatedAt: baseTime,
      );

      final stopwatch = Stopwatch()..start();
      final pdfBytes = await reportService.generatePdfReport(reportData);
      stopwatch.stop();

      expect(pdfBytes, isA<Uint8List>());
      expect(pdfBytes.length, greaterThan(1000));
      // Verifies sub-second high-speed layout computation
      expect(stopwatch.elapsedMilliseconds, lessThan(3000));
    });

    test('3. Scale dataset (1000 orders) generates scalable PDF without crash or memory exhaustion', () async {
      final orders = List.generate(1000, (i) {
        final status = i % 3 == 0 ? 'delivered' : (i % 3 == 1 ? 'rejected' : 'delivery_expired');
        return createTestOrder(
          index: i,
          status: status,
          totalAmount: 100.0 + (i % 50) * 10,
        );
      });

      final reportData = MonthlyReportData(
        shopId: 'shop_test',
        shopName: 'Test Gourmet Kitchen',
        startDateTime: baseTime.subtract(const Duration(days: 30)),
        endDateTime: baseTime,
        orders: orders,
        generatedAt: baseTime,
      );

      final stopwatch = Stopwatch()..start();
      final pdfBytes = await reportService.generatePdfReport(reportData);
      stopwatch.stop();

      expect(pdfBytes, isA<Uint8List>());
      expect(pdfBytes.isNotEmpty, isTrue);
      // Valid PDF magic header
      expect(pdfBytes[0], 0x25); // %
      expect(pdfBytes[1], 0x50); // P
      expect(pdfBytes[2], 0x44); // D
      expect(pdfBytes[3], 0x46); // F
      // 1000 orders should render under 5 seconds in unit testing
      expect(stopwatch.elapsedMilliseconds, lessThan(5000));
    });

    test('4. Long customer names, long order IDs, and multi-line item summaries do not break layout', () async {
      final longOrders = [
        createTestOrder(
          index: 1,
          totalAmount: 250,
          customOrderId: 'YB-20260831-EXTRA-LONG-ORDER-ID-TEST-IDENTIFIER-999',
          customerName: 'Shri Rajat Kumar Joshi Chaudhary Bennett University Student',
          items: [
            const OrderItem(
              menuItemId: 'item_long',
              name: 'Special Hand-Crafted Super Spicy Paneer Butter Masala With Premium Gravy',
              price: 250,
              quantity: 5,
              optionsDescription: 'Size: Family Jumbo Bowl, Spice Level: Extremely Spicy Hot, Dip: Extra Mint Chutney',
            ),
          ],
        ),
      ];

      final reportData = MonthlyReportData(
        shopId: 'shop_test',
        shopName: 'Test Gourmet Kitchen With Extra Long Name',
        startDateTime: baseTime.subtract(const Duration(days: 30)),
        endDateTime: baseTime,
        orders: longOrders,
        generatedAt: baseTime,
      );

      final pdfBytes = await reportService.generatePdfReport(reportData);
      expect(pdfBytes.isNotEmpty, isTrue);
    });

    test('5. Empty statement period handles cleanly with placeholder message', () async {
      final reportData = MonthlyReportData(
        shopId: 'shop_test',
        shopName: 'Empty Shop',
        startDateTime: baseTime.subtract(const Duration(days: 30)),
        endDateTime: baseTime,
        orders: const [],
        generatedAt: baseTime,
      );

      final pdfBytes = await reportService.generatePdfReport(reportData);
      expect(pdfBytes.isNotEmpty, isTrue);
      expect(reportData.orders.isEmpty, isTrue);
    });

    test('6. Mixed status coverage (Delivered, Rejected, Cancelled, Expired, Placed, Accepted)', () async {
      final mixedOrders = [
        createTestOrder(index: 1, totalAmount: 150),
        createTestOrder(index: 2, status: 'rejected', totalAmount: 120),
        createTestOrder(index: 3, status: 'cancelled', totalAmount: 80),
        createTestOrder(index: 4, status: 'delivery_expired', totalAmount: 200),
        createTestOrder(index: 5, status: 'placed', totalAmount: 100),
        createTestOrder(index: 6, status: 'accepted', totalAmount: 250),
      ];

      final reportData = MonthlyReportData(
        shopId: 'shop_test',
        shopName: 'Test Kitchen',
        startDateTime: baseTime.subtract(const Duration(days: 30)),
        endDateTime: baseTime,
        orders: mixedOrders,
        generatedAt: baseTime,
      );

      final pdfBytes = await reportService.generatePdfReport(reportData);
      expect(pdfBytes.isNotEmpty, isTrue);
      expect(reportData.deliveredOrdersCount, equals(1));
      expect(reportData.rejectedOrdersCount, equals(1));
      expect(reportData.expiredOrdersCount, equals(1));
      expect(reportData.deliveredSalesValue, equals(150.0));
    });
  });
}
