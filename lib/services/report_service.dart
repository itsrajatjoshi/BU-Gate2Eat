// BU Gate2Eat — Services
// Admin Shop Vendor Statement Report Service (PDF & XLSX Generator)
// Generates isolated, strictly bounded reset-to-export vendor statements and multi-sheet Excel workbooks.
// 100% READ-ONLY: Never modifies, deletes, or resets Firestore order data.

import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../models/order_model.dart';
import '../models/shop_stats_model.dart';
import 'file_download_helper.dart';
import 'order_service.dart';
import 'shop_stats_service.dart';

/// Aggregated vendor statement data structure for a single shop.
/// Strictly represents a CLOSED/HISTORICAL statement between [startDateTime] and [endDateTime].
/// Active orders (placed, accepted, etc.) are excluded from all counts and financial totals.
class MonthlyReportData {
  MonthlyReportData({
    required this.shopId,
    required this.shopName,
    required this.startDateTime,
    required this.endDateTime,
    required List<AppOrder> orders,
    required this.generatedAt,
    DateTime? month,
    int? explicitWhatsappOrdersCount,
  })  : orders = orders
            .where(
              (o) => !OrderStatusRules.activeStatuses
                  .contains(o.status.toLowerCase()),
            )
            .toList(),
        _explicitMonth = month,
        _explicitWhatsappOrdersCount = explicitWhatsappOrdersCount;

  final String shopId;
  final String shopName;

  /// Authoritative statement start timestamp (shopStats.lastResetAt or shop.createdAt).
  /// Null if neither is available.
  final DateTime? startDateTime;

  /// Authoritative statement end timestamp (export timestamp / now).
  final DateTime endDateTime;

  final List<AppOrder> orders;
  final DateTime generatedAt;
  final DateTime? _explicitMonth;
  final int? _explicitWhatsappOrdersCount;

  /// Whether this statement has a valid authoritative start timestamp.
  bool get hasValidPeriod => startDateTime != null;

  /// Legacy month accessor for backwards compatibility with older tests.
  DateTime get month => _explicitMonth ?? startDateTime ?? endDateTime;

  int get totalOrdersCount => orders.length;

  List<AppOrder> get deliveredOrders => orders
      .where((o) => o.status.toLowerCase() == OrderStatusRules.statusDelivered)
      .toList();

  List<AppOrder> get rejectedOrders => orders
      .where((o) => o.status.toLowerCase() == OrderStatusRules.statusRejected)
      .toList();

  List<AppOrder> get cancelledOrders => orders
      .where((o) => o.status.toLowerCase() == OrderStatusRules.statusCancelled)
      .toList();

  List<AppOrder> get expiredOrders => orders
      .where(
        (o) =>
            o.status.toLowerCase() == OrderStatusRules.statusDeliveryExpired,
      )
      .toList();

  List<AppOrder> get whatsappOrders =>
      orders.where((o) => o.isWhatsAppOrder).toList();

  List<AppOrder> get otherOrders => orders.where((o) {
        final s = o.status.toLowerCase();
        return s != OrderStatusRules.statusDelivered &&
            s != OrderStatusRules.statusRejected &&
            s != OrderStatusRules.statusCancelled &&
            s != OrderStatusRules.statusDeliveryExpired;
      }).toList();

  int get deliveredOrdersCount => deliveredOrders.length;
  int get rejectedOrdersCount => rejectedOrders.length;
  int get cancelledOrdersCount => cancelledOrders.length;
  int get expiredOrdersCount => expiredOrders.length;
  int get whatsappOrdersCount =>
      _explicitWhatsappOrdersCount ?? whatsappOrders.length;
  int get otherOrdersCount => otherOrders.length;

  /// Total revenue from successfully delivered orders.
  double get deliveredSalesValue =>
      deliveredOrders.fold<double>(0.0, (acc, o) => acc + o.totalAmount);

  /// Total closed order value across all closed/historical orders in this statement.
  double get closedOrderValue =>
      orders.fold<double>(0.0, (acc, o) => acc + o.totalAmount);

  /// Standardized alias for closedOrderValue.
  double get grossOrderValue => closedOrderValue;

  int get totalItemsDelivered =>
      deliveredOrders.fold<int>(0, (acc, o) => acc + o.totalItemCount);

  int get totalItemsInClosedOrders =>
      orders.fold<int>(0, (acc, o) => acc + o.totalItemCount);

  /// Legacy alias for totalItemsInClosedOrders.
  int get totalItemsOrdered => totalItemsInClosedOrders;

  String get formattedPeriod {
    if (startDateTime == null) {
      return 'No reset/creation timestamp available';
    }
    final df = DateFormat('dd MMM yyyy, hh:mm a');
    return '${df.format(startDateTime!)} - ${df.format(endDateTime)}';
  }
}

/// Service class for fetching reset-to-export order records and generating PDF & XLSX vendor statements.
class ReportService {
  ReportService({FirebaseFirestore? firestore}) : _customFirestore = firestore;

  final FirebaseFirestore? _customFirestore;

  bool get _isAvailable {
    try {
      if (_customFirestore != null) return true;
      return Firebase.apps.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  FirebaseFirestore get _firestore =>
      _customFirestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _ordersRef =>
      _firestore.collection('orders');

  /// Computes month boundaries (legacy utility).
  static ({DateTime start, DateTime end}) getMonthBoundaries(DateTime month) {
    final start = DateTime(month.year, month.month);
    final end = (month.month == 12)
        ? DateTime(month.year + 1)
        : DateTime(month.year, month.month + 1);
    return (start: start, end: end);
  }

  /// Sanitizes a shop name for safe filenames across all operating systems.
  static String sanitizeFileName(String name) {
    return name
        .replaceAll(RegExp(r'[^\w\s-]'), '')
        .trim()
        .replaceAll(RegExp(r'\s+'), '_');
  }

  /// Generates a standardized, deterministic statement filename based on shop name and export timestamp.
  static String getStatementFileName(
    String shopName,
    DateTime endDateTime,
    String extension,
  ) {
    final sanitized = sanitizeFileName(shopName);
    final period = DateFormat('yyyyMMdd_HHmm').format(endDateTime);
    final cleanExt =
        extension.startsWith('.') ? extension.substring(1) : extension;
    return 'YummBU_${sanitized}_${period}_Statement.$cleanExt';
  }

  /// Legacy alias for backwards compatibility.
  static String getReportFileName(
    String shopName,
    DateTime monthOrEnd,
    String extension,
  ) {
    return getStatementFileName(shopName, monthOrEnd, extension);
  }

  /// Fetches closed/historical orders for a single shop within the authoritative reset-to-export statement window.
  ///
  /// Resolution order for statementStart:
  /// 1. `shopStats.lastResetAt`
  /// 2. `fallbackCreatedAt` (shop.createdAt)
  /// 3. If neither is available, returns a statement with `startDateTime: null` and empty orders.
  Future<MonthlyReportData> fetchShopStatementData({
    required String shopId,
    required String shopName,
    required DateTime endDateTime,
    DateTime? startDateTime,
    DateTime? fallbackCreatedAt,
  }) async {
    DateTime? resolvedStart = startDateTime;
    int whatsappCount = 0;

    if (_isAvailable) {
      final statsService = ShopStatsService(firestore: _customFirestore);

      // If startDateTime was not explicitly provided, resolve from Firestore shopStats
      if (resolvedStart == null) {
        try {
          final doc = await _firestore.collection('shopStats').doc(shopId).get();
          if (doc.exists && doc.data() != null) {
            final stats = ShopStats.fromFirestore(doc);
            resolvedStart = stats.lastResetAt ?? fallbackCreatedAt;
            whatsappCount = stats.whatsappOrders;
          } else {
            resolvedStart = fallbackCreatedAt;
          }
        } catch (e) {
          debugPrint('⚠️ ReportService fetchShopStatementData stats error: $e');
          resolvedStart = fallbackCreatedAt;
        }
      } else {
        whatsappCount = await statsService.getStatementWhatsappOrders(shopId);
      }
    }

    if (resolvedStart == null) {
      return MonthlyReportData(
        shopId: shopId,
        shopName: shopName,
        startDateTime: null,
        endDateTime: endDateTime,
        orders: const [],
        generatedAt: endDateTime,
        explicitWhatsappOrdersCount: 0,
      );
    }

    List<AppOrder> orders = [];

    if (_isAvailable) {
      // Query Firestore orders strictly isolated by shopId
      final snapshot = await _ordersRef
          .where('shopId', isEqualTo: shopId)
          .get();

      orders = snapshot.docs
          .map((doc) => AppOrder.fromFirestore(doc))
          .where((order) {
            final created = order.createdAt;
            final inDateRange = (created.isAtSameMomentAs(resolvedStart!) ||
                    created.isAfter(resolvedStart)) &&
                (created.isAtSameMomentAs(endDateTime) ||
                    created.isBefore(endDateTime));
            final isClosed = !OrderStatusRules.activeStatuses
                .contains(order.status.toLowerCase());
            return inDateRange && isClosed;
          })
          .toList();

      // Sort chronologically ascending
      orders.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    }

    return MonthlyReportData(
      shopId: shopId,
      shopName: shopName,
      startDateTime: resolvedStart,
      endDateTime: endDateTime,
      orders: orders,
      generatedAt: endDateTime,
      explicitWhatsappOrdersCount: whatsappCount,
    );
  }

  /// Legacy method kept for backwards compatibility.
  Future<MonthlyReportData> fetchMonthlyShopReportData({
    required String shopId,
    required String shopName,
    required DateTime month,
  }) async {
    final boundaries = getMonthBoundaries(month);
    return fetchShopStatementData(
      shopId: shopId,
      shopName: shopName,
      startDateTime: boundaries.start,
      endDateTime: boundaries.end,
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // ── PDF GENERATION (Professional Bill / Statement Style) ───────────────────
  // ════════════════════════════════════════════════════════════════════════════

  /// Generates a professional multi-page PDF statement for the selected shop and statement window.
  Future<Uint8List> generatePdfReport(MonthlyReportData data) async {
    final pdf = pw.Document(
      title: getStatementFileName(data.shopName, data.endDateTime, 'pdf'),
      author: 'YummBU Admin Panel',
    );

    pw.Font fontRegular;
    pw.Font fontBold;
    pw.Font fontSemiBold;

    try {
      fontRegular = await PdfGoogleFonts.interRegular();
      fontBold = await PdfGoogleFonts.interBold();
      fontSemiBold = await PdfGoogleFonts.interSemiBold();
    } catch (_) {
      fontRegular = pw.Font.helvetica();
      fontBold = pw.Font.helveticaBold();
      fontSemiBold = pw.Font.helveticaBold();
    }

    final theme = pw.ThemeData.withFont(
      base: fontRegular,
      bold: fontBold,
      fontFallback: [fontRegular],
    );

    final primaryColor = PdfColor.fromHex('FF5500'); // YummBU Orange
    final darkHeader = PdfColor.fromHex('1A1A1A');
    final subtleBg = PdfColor.fromHex('F8F9FA');
    final borderColor = PdfColor.fromHex('E0E0E0');
    final successColor = PdfColor.fromHex('16A34A');
    final errorColor = PdfColor.fromHex('DC2626');
    final amberColor = PdfColor.fromHex('D97706');
    final textMuted = PdfColor.fromHex('666666');

    pdf.addPage(
      pw.MultiPage(
        maxPages: 200,
        pageTheme: pw.PageTheme(
          theme: theme,
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.symmetric(horizontal: 22, vertical: 20),
        ),
        header: (pw.Context context) => _buildPdfHeader(
          data: data,
          primaryColor: primaryColor,
          darkHeader: darkHeader,
          textMuted: textMuted,
          fontBold: fontBold,
          fontSemiBold: fontSemiBold,
          pageNumber: context.pageNumber,
        ),
        footer: (pw.Context context) => _buildPdfFooter(
          context: context,
          textMuted: textMuted,
        ),
        build: (pw.Context context) => [
          pw.SizedBox(height: 8),

          // ── Executive Summary Box (Page 1 Top) ──
          _buildPdfSummaryCard(
            data: data,
            subtleBg: subtleBg,
            borderColor: borderColor,
            darkHeader: darkHeader,
            primaryColor: primaryColor,
            successColor: successColor,
            errorColor: errorColor,
            amberColor: amberColor,
            fontBold: fontBold,
            fontSemiBold: fontSemiBold,
          ),

          pw.SizedBox(height: 12),

          // ── Detailed Order Breakdown Header ──
          pw.Text(
            'DETAILED ORDERS BREAKDOWN (${data.orders.length} orders)',
            style: pw.TextStyle(
              font: fontBold,
              fontSize: 10.5,
              letterSpacing: 0.5,
              color: darkHeader,
            ),
          ),
          pw.SizedBox(height: 6),

          // ── Compact Scalable Orders Table (Repeat Header on Page Break) ──
          if (data.orders.isEmpty)
            pw.Container(
              padding: const pw.EdgeInsets.all(20),
              alignment: pw.Alignment.center,
              decoration: pw.BoxDecoration(
                color: subtleBg,
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                border: pw.Border.all(color: borderColor),
              ),
              child: pw.Text(
                'No orders recorded for this shop in the statement period.',
                style: pw.TextStyle(
                  color: textMuted,
                  fontSize: 10,
                  fontStyle: pw.FontStyle.italic,
                ),
              ),
            )
          else
            pw.Table(
              border: pw.TableBorder(
                horizontalInside: pw.BorderSide(color: borderColor, width: 0.4),
                bottom: pw.BorderSide(color: borderColor, width: 0.6),
              ),
              columnWidths: const {
                0: pw.FlexColumnWidth(1.2), // Order ID
                1: pw.FlexColumnWidth(1.4), // Date & Time
                2: pw.FlexColumnWidth(1.5), // Customer
                3: pw.FlexColumnWidth(2.8), // Items Summary
                4: pw.FlexColumnWidth(), // Total (INR)
                5: pw.FlexColumnWidth(1.1), // Status
              },
              children: [
                // Table Header Row (Repeats across pages automatically)
                pw.TableRow(
                  decoration: pw.BoxDecoration(color: subtleBg),
                  repeat: true,
                  children: [
                    _buildTableCell('Order ID', isHeader: true, fontBold: fontBold),
                    _buildTableCell('Date & Time', isHeader: true, fontBold: fontBold),
                    _buildTableCell('Customer', isHeader: true, fontBold: fontBold),
                    _buildTableCell('Items & Options', isHeader: true, fontBold: fontBold),
                    _buildTableCell('Total (INR)', isHeader: true, fontBold: fontBold, align: pw.TextAlign.right),
                    _buildTableCell('Status', isHeader: true, fontBold: fontBold, align: pw.TextAlign.center),
                  ],
                ),
                // Table Rows (Ultra-compact, scalable to 1000+ orders)
                ...data.orders.map((order) {
                  final itemsSummary = _formatCompactItemsSummary(order);

                  return pw.TableRow(
                    children: [
                      // Order ID
                      pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(vertical: 3.5, horizontal: 4),
                        child: pw.Text(
                          order.orderId.length > 8
                              ? '#${order.orderId.substring(order.orderId.length - 8).toUpperCase()}'
                              : '#${order.orderId.toUpperCase()}',
                          style: pw.TextStyle(font: fontSemiBold, fontSize: 8),
                        ),
                      ),
                      // Date & Time
                      pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(vertical: 3.5, horizontal: 4),
                        child: pw.Text(
                          DateFormat('dd MMM, h:mm a').format(order.createdAt),
                          style: const pw.TextStyle(fontSize: 7.5),
                        ),
                      ),
                      // Customer
                      pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(vertical: 3.5, horizontal: 4),
                        child: pw.Text(
                          order.customerName.isNotEmpty ? order.customerName : 'Customer',
                          style: pw.TextStyle(font: fontSemiBold, fontSize: 8),
                          maxLines: 1,
                        ),
                      ),
                      // Items & Options
                      pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(vertical: 3.5, horizontal: 4),
                        child: pw.Text(
                          itemsSummary,
                          style: const pw.TextStyle(fontSize: 7.5),
                          maxLines: 2,
                        ),
                      ),
                      // Total
                      pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(vertical: 3.5, horizontal: 4),
                        child: pw.Text(
                          'Rs.${order.totalAmount.toStringAsFixed(0)}',
                          textAlign: pw.TextAlign.right,
                          style: pw.TextStyle(font: fontBold, fontSize: 8),
                        ),
                      ),
                      // Status Badge
                      pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(vertical: 3.5, horizontal: 4),
                        child: _buildPdfStatusBadge(
                          order.status,
                          successColor: successColor,
                          errorColor: errorColor,
                          amberColor: amberColor,
                          textMuted: textMuted,
                          fontBold: fontBold,
                        ),
                      ),
                    ],
                  );
                }),
              ],
            ),

          pw.SizedBox(height: 14),

          // ── Final Statement Totals Box ──
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              color: subtleBg,
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
              border: pw.Border.all(color: borderColor),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'STATEMENT TOTALS',
                      style: pw.TextStyle(font: fontBold, fontSize: 9.5, color: darkHeader),
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text(
                      'Total Closed: ${data.totalOrdersCount}  |  Delivered: ${data.deliveredOrdersCount}  |  Rejected: ${data.rejectedOrdersCount}  |  Expired: ${data.expiredOrdersCount}  |  WhatsApp: ${data.whatsappOrdersCount}',
                      style: pw.TextStyle(fontSize: 7.5, color: textMuted),
                    ),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      'Delivered Revenue: Rs.${data.deliveredSalesValue.toStringAsFixed(0)}',
                      style: pw.TextStyle(font: fontBold, fontSize: 10.5, color: successColor),
                    ),
                    pw.SizedBox(height: 1.5),
                    pw.Text(
                      'Closed Order Value: Rs.${data.closedOrderValue.toStringAsFixed(0)}',
                      style: pw.TextStyle(fontSize: 8, color: textMuted),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );

    return pdf.save();
  }

  pw.Widget _buildPdfHeader({
    required MonthlyReportData data,
    required PdfColor primaryColor,
    required PdfColor darkHeader,
    required PdfColor textMuted,
    required pw.Font fontBold,
    required pw.Font fontSemiBold,
    required int pageNumber,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  children: [
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: pw.BoxDecoration(
                        color: primaryColor,
                        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                      ),
                      child: pw.Text(
                        'YummBU',
                        style: pw.TextStyle(
                          font: fontBold,
                          fontSize: 12,
                          color: PdfColors.white,
                        ),
                      ),
                    ),
                    pw.SizedBox(width: 8),
                    pw.Text(
                      'VENDOR STATEMENT',
                      style: pw.TextStyle(
                        font: fontBold,
                        fontSize: 13,
                        color: darkHeader,
                      ),
                    ),
                  ],
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  'Shop: ${data.shopName}',
                  style: pw.TextStyle(font: fontBold, fontSize: 11, color: primaryColor),
                ),
              ],
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text(
                  'Period: ${data.formattedPeriod}',
                  style: pw.TextStyle(font: fontSemiBold, fontSize: 9, color: darkHeader),
                ),
                pw.Text(
                  'Generated: ${DateFormat('dd MMM yyyy, hh:mm a').format(data.generatedAt)}',
                  style: pw.TextStyle(fontSize: 8, color: textMuted),
                ),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 8),
        pw.Divider(color: primaryColor, thickness: 1.5),
      ],
    );
  }

  pw.Widget _buildPdfFooter({
    required pw.Context context,
    required PdfColor textMuted,
  }) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 12),
      padding: const pw.EdgeInsets.only(top: 6),
      decoration: const pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(color: PdfColors.grey300, width: 0.5)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'YummBU Platform - Official Vendor Statement (Confidential)',
            style: pw.TextStyle(fontSize: 7.5, color: textMuted),
          ),
          pw.Text(
            'Page ${context.pageNumber} of ${context.pagesCount}',
            style: pw.TextStyle(fontSize: 7.5, color: textMuted),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildPdfSummaryCard({
    required MonthlyReportData data,
    required PdfColor subtleBg,
    required PdfColor borderColor,
    required PdfColor darkHeader,
    required PdfColor primaryColor,
    required PdfColor successColor,
    required PdfColor errorColor,
    required PdfColor amberColor,
    required pw.Font fontBold,
    required pw.Font fontSemiBold,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: subtleBg,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
        border: pw.Border.all(color: borderColor),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'STATEMENT PERFORMANCE SUMMARY',
            style: pw.TextStyle(
              font: fontBold,
              fontSize: 10,
              letterSpacing: 0.5,
              color: darkHeader,
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              _buildMetricTile('Total Closed', '${data.totalOrdersCount}', darkHeader, fontBold),
              _buildMetricTile('Delivered / Completed', '${data.deliveredOrdersCount}', successColor, fontBold),
              _buildMetricTile('Rejected', '${data.rejectedOrdersCount}', errorColor, fontBold),
              _buildMetricTile('Expired', '${data.expiredOrdersCount}', amberColor, fontBold),
              _buildMetricTile('WhatsApp Orders', '${data.whatsappOrdersCount}', primaryColor, fontBold),
            ],
          ),
          pw.SizedBox(height: 10),
          pw.Divider(color: borderColor, thickness: 0.5),
          pw.SizedBox(height: 6),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.RichText(
                text: pw.TextSpan(
                  children: [
                    pw.TextSpan(
                      text: 'Closed Order Value: ',
                      style: pw.TextStyle(font: fontSemiBold, fontSize: 9, color: darkHeader),
                    ),
                    pw.TextSpan(
                      text: 'Rs.${data.closedOrderValue.toStringAsFixed(0)}',
                      style: pw.TextStyle(font: fontBold, fontSize: 10, color: darkHeader),
                    ),
                    pw.TextSpan(
                      text: ' (${data.totalItemsInClosedOrders} items)',
                      style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
                    ),
                  ],
                ),
              ),
              pw.RichText(
                text: pw.TextSpan(
                  children: [
                    pw.TextSpan(
                      text: 'Delivered Sales: ',
                      style: pw.TextStyle(font: fontSemiBold, fontSize: 9, color: successColor),
                    ),
                    pw.TextSpan(
                      text: 'Rs.${data.deliveredSalesValue.toStringAsFixed(0)}',
                      style: pw.TextStyle(font: fontBold, fontSize: 11, color: successColor),
                    ),
                    pw.TextSpan(
                      text: ' (${data.totalItemsDelivered} items delivered)',
                      style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  pw.Widget _buildMetricTile(String label, String value, PdfColor color, pw.Font fontBold) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          value,
          style: pw.TextStyle(font: fontBold, fontSize: 14, color: color),
        ),
        pw.Text(
          label,
          style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700),
        ),
      ],
    );
  }

  pw.Widget _buildTableCell(
    String text, {
    required pw.Font fontBold,
    bool isHeader = false,
    pw.TextAlign align = pw.TextAlign.left,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 4),
      child: pw.Text(
        text,
        textAlign: align,
        style: pw.TextStyle(
          font: isHeader ? fontBold : null,
          fontSize: isHeader ? 8 : 8,
          color: isHeader ? PdfColors.black : PdfColors.grey800,
        ),
      ),
    );
  }

  pw.Widget _buildPdfStatusBadge(
    String status, {
    required PdfColor successColor,
    required PdfColor errorColor,
    required PdfColor amberColor,
    required PdfColor textMuted,
    required pw.Font fontBold,
  }) {
    PdfColor color;
    String label;

    switch (status.toLowerCase()) {
      case 'delivered':
        color = successColor;
        label = 'DELIVERED';
        break;
      case 'rejected':
        color = errorColor;
        label = 'REJECTED';
        break;
      case 'cancelled':
        color = errorColor;
        label = 'CANCELLED';
        break;
      case 'delivery_expired':
        color = amberColor;
        label = 'EXPIRED';
        break;
      case 'placed':
        color = amberColor;
        label = 'PLACED';
        break;
      case 'accepted':
        color = amberColor;
        label = 'ACCEPTED';
        break;
      default:
        color = textMuted;
        label = status.toUpperCase();
    }

    return pw.Container(
      alignment: pw.Alignment.center,
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: pw.BoxDecoration(
        color: color,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
      ),
      child: pw.Text(
        label,
        style: pw.TextStyle(
          font: fontBold,
          fontSize: 6.5,
          color: PdfColors.white,
        ),
      ),
    );
  }

  /// Formats items and option choices into a single compact line for high-density 1000-order PDF tables.
  static String _formatCompactItemsSummary(AppOrder order) {
    if (order.items.isEmpty) return '-';
    final parts = order.items.map((item) {
      final opt = item.optionsDescription.trim();
      final optStr = opt.isNotEmpty ? ' ($opt)' : '';
      return '${item.name}$optStr x${item.quantity}';
    }).join(', ');
    final totalCount = order.totalItemCount;
    return '$totalCount ${totalCount == 1 ? 'item' : 'items'}: $parts';
  }

  // ════════════════════════════════════════════════════════════════════════════
  // ── REAL XLSX WORKBOOK GENERATION (Multi-Sheet OpenXML) ───────────────────
  // ════════════════════════════════════════════════════════════════════════════

  /// Generates a standard Microsoft Excel OpenXML .xlsx workbook with 3 structured sheets:
  /// Sheet 1: Summary
  /// Sheet 2: Orders
  /// Sheet 3: Order Items
  Uint8List generateXlsxReport(MonthlyReportData data) {
    final archive = Archive();

    // 1. [Content_Types].xml
    const contentTypesXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
  <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
  <Override PartName="/xl/worksheets/sheet2.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
  <Override PartName="/xl/worksheets/sheet3.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
  <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
</Types>''';

    // 2. _rels/.rels
    const packageRelsXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
</Relationships>''';

    // 3. xl/workbook.xml
    const workbookXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <sheets>
    <sheet name="Summary" sheetId="1" r:id="rId1"/>
    <sheet name="Orders" sheetId="2" r:id="rId2"/>
    <sheet name="Order Items" sheetId="3" r:id="rId3"/>
  </sheets>
</workbook>''';

    // 4. xl/_rels/workbook.xml.rels
    const workbookRelsXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
  <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet2.xml"/>
  <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet3.xml"/>
  <Relationship Id="rId4" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
</Relationships>''';

    // 5. xl/styles.xml (Standard Fonts, Bold Headers, Number Formatting)
    const stylesXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <numFmts count="2">
    <numFmt numFmtId="164" formatCode="yyyy-mm-dd hh:mm:ss"/>
    <numFmt numFmtId="165" formatCode="₹#,##0"/>
  </numFmts>
  <fonts count="3">
    <font><name val="Calibri"/><sz val="11"/><color rgb="FF000000"/></font>
    <font><b/><name val="Calibri"/><sz val="11"/><color rgb="FF000000"/></font>
    <font><b/><name val="Calibri"/><sz val="13"/><color rgb="FFFF5500"/></font>
  </fonts>
  <fills count="3">
    <fill><patternFill patternType="none"/></fill>
    <fill><patternFill patternType="gray125"/></fill>
    <fill><patternFill patternType="solid"><fgColor rgb="FFF2F2F2"/></patternFill></fill>
  </fills>
  <borders count="2">
    <border><left/><right/><top/><bottom/><diagonal/></border>
    <border>
      <left style="thin"><color rgb="FFD3D3D3"/></left>
      <right style="thin"><color rgb="FFD3D3D3"/></right>
      <top style="thin"><color rgb="FFD3D3D3"/></top>
      <bottom style="thin"><color rgb="FFD3D3D3"/></bottom>
    </border>
  </borders>
  <cellStyleXfs count="1">
    <xf numFmtId="0" fontId="0" fillId="0" borderId="0"/>
  </cellStyleXfs>
  <cellXfs count="5">
    <xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>
    <xf numFmtId="0" fontId="1" fillId="2" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1"/>
    <xf numFmtId="0" fontId="2" fillId="0" borderId="0" xfId="0" applyFont="1"/>
    <xf numFmtId="0" fontId="0" fillId="0" borderId="1" xfId="0" applyBorder="1"/>
    <xf numFmtId="165" fontId="0" fillId="0" borderId="1" xfId="0" applyNumberFormat="1" applyBorder="1"/>
  </cellXfs>
</styleSheet>''';

    // 6. Build Sheet 1: Summary XML
    final sheet1Xml = _buildXlsxSummarySheet(data);

    // 7. Build Sheet 2: Orders XML
    final sheet2Xml = _buildXlsxOrdersSheet(data);

    // 8. Build Sheet 3: Order Items XML
    final sheet3Xml = _buildXlsxOrderItemsSheet(data);

    // Add all files to the zip archive
    void addFile(String path, String content) {
      final bytes = utf8.encode(content);
      archive.addFile(ArchiveFile(path, bytes.length, bytes));
    }

    addFile('[Content_Types].xml', contentTypesXml);
    addFile('_rels/.rels', packageRelsXml);
    addFile('xl/workbook.xml', workbookXml);
    addFile('xl/_rels/workbook.xml.rels', workbookRelsXml);
    addFile('xl/styles.xml', stylesXml);
    addFile('xl/worksheets/sheet1.xml', sheet1Xml);
    addFile('xl/worksheets/sheet2.xml', sheet2Xml);
    addFile('xl/worksheets/sheet3.xml', sheet3Xml);

    final zipData = ZipEncoder().encode(archive);
    return Uint8List.fromList(zipData);
  }

  static String _escapeXml(String value) {
    return value
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }

  static String _buildXlsxSummarySheet(MonthlyReportData data) {
    final rows = <String>[];
    int r = 1;

    void addRow(List<({String text, int style, bool isNum})> cells) {
      final cellXmls = <String>[];
      for (int c = 0; c < cells.length; c++) {
        final cell = cells[c];
        final colLetter = String.fromCharCode(65 + c);
        final ref = '$colLetter$r';
        if (cell.isNum) {
          cellXmls.add('<c r="$ref" s="${cell.style}"><v>${cell.text}</v></c>');
        } else {
          cellXmls.add('<c r="$ref" t="inlineStr" s="${cell.style}"><is><t>${_escapeXml(cell.text)}</t></is></c>');
        }
      }
      rows.add('<row r="$r">${cellXmls.join()}</row>');
      r++;
    }

    // Title
    addRow([(text: 'YummBU — Vendor Statement', style: 2, isNum: false)]);
    r++; // Empty row

    // Metadata
    addRow([(text: 'Shop Name', style: 1, isNum: false), (text: data.shopName, style: 3, isNum: false)]);
    addRow([(text: 'Shop ID', style: 1, isNum: false), (text: data.shopId, style: 3, isNum: false)]);
    addRow([(text: 'Statement Period', style: 1, isNum: false), (text: data.formattedPeriod, style: 3, isNum: false)]);
    addRow([(text: 'Report Generated At', style: 1, isNum: false), (text: DateFormat('yyyy-MM-dd HH:mm:ss').format(data.generatedAt), style: 3, isNum: false)]);
    r++; // Empty row

    // KPIs Table Header (No Cancelled, No Gross Order Value)
    addRow([(text: 'Performance Metric', style: 1, isNum: false), (text: 'Value', style: 1, isNum: false)]);
    addRow([(text: 'Total Closed Orders', style: 3, isNum: false), (text: '${data.totalOrdersCount}', style: 3, isNum: true)]);
    addRow([(text: 'Delivered / Completed Orders', style: 3, isNum: false), (text: '${data.deliveredOrdersCount}', style: 3, isNum: true)]);
    addRow([(text: 'Rejected Orders', style: 3, isNum: false), (text: '${data.rejectedOrdersCount}', style: 3, isNum: true)]);
    addRow([(text: 'Delivery Expired Orders', style: 3, isNum: false), (text: '${data.expiredOrdersCount}', style: 3, isNum: true)]);
    addRow([(text: 'WhatsApp Orders', style: 3, isNum: false), (text: '${data.whatsappOrdersCount}', style: 3, isNum: true)]);
    if (data.otherOrdersCount > 0) {
      addRow([(text: 'Other Closed Orders', style: 3, isNum: false), (text: '${data.otherOrdersCount}', style: 3, isNum: true)]);
    }
    addRow([(text: 'Total Items Delivered', style: 3, isNum: false), (text: '${data.totalItemsDelivered}', style: 3, isNum: true)]);
    addRow([(text: 'Total Items in Closed Orders', style: 3, isNum: false), (text: '${data.totalItemsInClosedOrders}', style: 3, isNum: true)]);
    addRow([(text: 'Delivered / Completed Sales (INR)', style: 1, isNum: false), (text: data.deliveredSalesValue.toStringAsFixed(0), style: 4, isNum: true)]);
    addRow([(text: 'Closed Order Value (INR)', style: 1, isNum: false), (text: data.closedOrderValue.toStringAsFixed(0), style: 4, isNum: true)]);

    return '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <cols>
    <col min="1" max="1" width="32" customWidth="1"/>
    <col min="2" max="2" width="32" customWidth="1"/>
  </cols>
  <sheetData>${rows.join()}</sheetData>
</worksheet>''';
  }

  static String _buildXlsxOrdersSheet(MonthlyReportData data) {
    final rows = <String>[];
    int r = 1;

    void addRow(List<({String text, int style, bool isNum})> cells) {
      final cellXmls = <String>[];
      for (int c = 0; c < cells.length; c++) {
        final cell = cells[c];
        final colLetter = String.fromCharCode(65 + c);
        final ref = '$colLetter$r';
        if (cell.isNum) {
          cellXmls.add('<c r="$ref" s="${cell.style}"><v>${cell.text}</v></c>');
        } else {
          cellXmls.add('<c r="$ref" t="inlineStr" s="${cell.style}"><is><t>${_escapeXml(cell.text)}</t></is></c>');
        }
      }
      rows.add('<row r="$r">${cellXmls.join()}</row>');
      r++;
    }

    // Header Row
    addRow([
      (text: 'Order ID', style: 1, isNum: false),
      (text: 'Order Date', style: 1, isNum: false),
      (text: 'Order Time', style: 1, isNum: false),
      (text: 'Customer Name', style: 1, isNum: false),
      (text: 'Customer Phone', style: 1, isNum: false),
      (text: 'Total Items', style: 1, isNum: false),
      (text: 'Order Total (INR)', style: 1, isNum: false),
      (text: 'Status', style: 1, isNum: false),
      (text: 'Delivered At', style: 1, isNum: false),
      (text: 'Rejection Reason', style: 1, isNum: false),
      (text: 'Special Instructions', style: 1, isNum: false),
      (text: 'Delivery Person', style: 1, isNum: false),
    ]);

    for (final o in data.orders) {
      addRow([
        (text: o.orderId, style: 3, isNum: false),
        (text: DateFormat('yyyy-MM-dd').format(o.createdAt), style: 3, isNum: false),
        (text: DateFormat('HH:mm:ss').format(o.createdAt), style: 3, isNum: false),
        (text: o.customerName.isNotEmpty ? o.customerName : '-', style: 3, isNum: false),
        (text: o.customerPhone.isNotEmpty ? o.customerPhone : '-', style: 3, isNum: false),
        (text: '${o.totalItemCount}', style: 3, isNum: true),
        (text: o.totalAmount.toStringAsFixed(0), style: 4, isNum: true),
        (text: o.status.toUpperCase(), style: 3, isNum: false),
        (text: o.deliveredAt != null ? DateFormat('yyyy-MM-dd HH:mm').format(o.deliveredAt!) : '-', style: 3, isNum: false),
        (text: o.rejectionReason.isNotEmpty ? o.rejectionReason : '-', style: 3, isNum: false),
        (text: o.specialInstructions.isNotEmpty ? o.specialInstructions : '-', style: 3, isNum: false),
        (text: o.deliveryPersonName.isNotEmpty ? o.deliveryPersonName : '-', style: 3, isNum: false),
      ]);
    }

    return '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <cols>
    <col min="1" max="1" width="22" customWidth="1"/>
    <col min="2" max="2" width="14" customWidth="1"/>
    <col min="3" max="3" width="14" customWidth="1"/>
    <col min="4" max="4" width="20" customWidth="1"/>
    <col min="5" max="5" width="16" customWidth="1"/>
    <col min="6" max="6" width="12" customWidth="1"/>
    <col min="7" max="7" width="18" customWidth="1"/>
    <col min="8" max="8" width="16" customWidth="1"/>
    <col min="9" max="9" width="18" customWidth="1"/>
    <col min="10" max="10" width="24" customWidth="1"/>
    <col min="11" max="11" width="24" customWidth="1"/>
    <col min="12" max="12" width="20" customWidth="1"/>
  </cols>
  <sheetData>${rows.join()}</sheetData>
</worksheet>''';
  }

  static String _buildXlsxOrderItemsSheet(MonthlyReportData data) {
    final rows = <String>[];
    int r = 1;

    void addRow(List<({String text, int style, bool isNum})> cells) {
      final cellXmls = <String>[];
      for (int c = 0; c < cells.length; c++) {
        final cell = cells[c];
        final colLetter = String.fromCharCode(65 + c);
        final ref = '$colLetter$r';
        if (cell.isNum) {
          cellXmls.add('<c r="$ref" s="${cell.style}"><v>${cell.text}</v></c>');
        } else {
          cellXmls.add('<c r="$ref" t="inlineStr" s="${cell.style}"><is><t>${_escapeXml(cell.text)}</t></is></c>');
        }
      }
      rows.add('<row r="$r">${cellXmls.join()}</row>');
      r++;
    }

    // Header Row
    addRow([
      (text: 'Order ID', style: 1, isNum: false),
      (text: 'Order Date', style: 1, isNum: false),
      (text: 'Item Name', style: 1, isNum: false),
      (text: 'Variant / Options', style: 1, isNum: false),
      (text: 'Quantity', style: 1, isNum: false),
      (text: 'Unit Price (INR)', style: 1, isNum: false),
      (text: 'Line Total (INR)', style: 1, isNum: false),
      (text: 'Order Status', style: 1, isNum: false),
    ]);

    for (final o in data.orders) {
      for (final item in o.items) {
        addRow([
          (text: o.orderId, style: 3, isNum: false),
          (text: DateFormat('yyyy-MM-dd HH:mm').format(o.createdAt), style: 3, isNum: false),
          (text: item.name, style: 3, isNum: false),
          (text: item.optionsDescription.isNotEmpty ? item.optionsDescription : '-', style: 3, isNum: false),
          (text: '${item.quantity}', style: 3, isNum: true),
          (text: '${item.price}', style: 4, isNum: true),
          (text: item.totalPrice.toStringAsFixed(0), style: 4, isNum: true),
          (text: o.status.toUpperCase(), style: 3, isNum: false),
        ]);
      }
    }

    return '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <cols>
    <col min="1" max="1" width="22" customWidth="1"/>
    <col min="2" max="2" width="18" customWidth="1"/>
    <col min="3" max="3" width="26" customWidth="1"/>
    <col min="4" max="4" width="26" customWidth="1"/>
    <col min="5" max="5" width="12" customWidth="1"/>
    <col min="6" max="6" width="16" customWidth="1"/>
    <col min="7" max="7" width="16" customWidth="1"/>
    <col min="8" max="8" width="16" customWidth="1"/>
  </cols>
  <sheetData>${rows.join()}</sheetData>
</worksheet>''';
  }

  // ════════════════════════════════════════════════════════════════════════════
  // ── EXPORT & SHARE ACTIONS ────────────────────────────────────────────────
  // ════════════════════════════════════════════════════════════════════════════

  /// Exports and opens the PDF statement via direct browser download on web, or native share sheet on mobile.
  Future<void> exportPdf({
    required MonthlyReportData data,
    required BuildContext context,
  }) async {
    final pdfBytes = await generatePdfReport(data);
    final filename = getStatementFileName(data.shopName, data.endDateTime, 'pdf');

    if (kIsWeb) {
      await downloadFileToBrowser(
        bytes: pdfBytes,
        fileName: filename,
        mimeType: 'application/pdf',
      );
      return;
    }

    await Printing.sharePdf(
      bytes: pdfBytes,
      filename: filename,
    );
  }

  /// Exports and shares the XLSX workbook file via direct browser download on web, or native share on mobile.
  Future<void> exportXlsx({
    required MonthlyReportData data,
    required BuildContext context,
  }) async {
    final xlsxBytes = generateXlsxReport(data);
    final filename = getStatementFileName(data.shopName, data.endDateTime, 'xlsx');

    if (kIsWeb) {
      await downloadFileToBrowser(
        bytes: xlsxBytes,
        fileName: filename,
        mimeType:
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      );
      return;
    }

    final xFile = XFile.fromData(
      xlsxBytes,
      name: filename,
      mimeType:
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    );

    await SharePlus.instance.share(
      ShareParams(
        files: [xFile],
        subject:
            'YummBU Vendor Statement - ${data.shopName} (${data.formattedPeriod})',
        text:
            'Attached is the vendor statement workbook for ${data.shopName}.',
      ),
    );
  }
}
