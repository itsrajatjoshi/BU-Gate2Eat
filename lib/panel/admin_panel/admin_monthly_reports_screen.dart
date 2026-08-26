// BU Gate2Eat — Admin Panel
// Shop Vendor Statements & Export Screen (Feature #2)
// Generates professional PDF vendor statements & real XLSX workbooks based on exact reset-to-export intervals.
// Strict admin-only access, shop isolation, and read-only data guarantees.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/constants/app_constants.dart';
import '../../core/providers.dart';
import '../../models/order_model.dart';
import '../../models/shop_model.dart';
import '../../models/shop_stats_model.dart';
import '../../services/report_service.dart';

class AdminMonthlyReportsScreen extends ConsumerStatefulWidget {
  const AdminMonthlyReportsScreen({
    this.initialShopId,
    super.key,
  });

  final String? initialShopId;

  @override
  ConsumerState<AdminMonthlyReportsScreen> createState() =>
      _AdminMonthlyReportsScreenState();
}

class _AdminMonthlyReportsScreenState
    extends ConsumerState<AdminMonthlyReportsScreen> {
  String? _selectedShopId;
  late DateTime _exportTimestamp;
  bool _isExportingPdf = false;
  bool _isExportingXlsx = false;

  @override
  void initState() {
    super.initState();
    _selectedShopId = widget.initialShopId;
    _exportTimestamp = DateTime.now();
  }

  void _refreshTimestamp() {
    setState(() {
      _exportTimestamp = DateTime.now();
    });
  }

  Future<void> _handleExportPdf(MonthlyReportData data) async {
    if (_isExportingPdf) return;
    setState(() => _isExportingPdf = true);

    try {
      final reportService = ref.read(reportServiceProvider);
      await reportService.exportPdf(data: data, context: context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to export PDF: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isExportingPdf = false);
    }
  }

  Future<void> _handleExportXlsx(MonthlyReportData data) async {
    if (_isExportingXlsx) return;
    setState(() => _isExportingXlsx = true);

    try {
      final reportService = ref.read(reportServiceProvider);
      await reportService.exportXlsx(data: data, context: context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to export Excel workbook: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isExportingXlsx = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final shopsAsync = ref.watch(shopsProvider);

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : AppColors.background,
      appBar: AppBar(
        title: const Text(
          'Shop Vendor Statements',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh Statement Window (Now)',
            onPressed: _refreshTimestamp,
          ),
        ],
        elevation: 0,
      ),
      body: shopsAsync.when(
        data: (shops) {
          if (shops.isEmpty) {
            return const Center(child: Text('No shops found in system.'));
          }

          if (_selectedShopId == null || !shops.any((s) => s.id == _selectedShopId)) {
            _selectedShopId = shops.first.id;
          }

          final selectedShop = shops.firstWhere((s) => s.id == _selectedShopId);
          final statsAsync = ref.watch(shopStatsStreamProvider(selectedShop.id));
          final stats = statsAsync.valueOrNull;

          final statementStart = stats?.lastResetAt ?? selectedShop.createdAt;

          final reportAsync = ref.watch(
            shopStatementDataProvider((
              shopId: selectedShop.id,
              shopName: selectedShop.name,
              statementStart: statementStart,
              statementEnd: _exportTimestamp,
              fallbackCreatedAt: selectedShop.createdAt,
            )),
          );

          return Column(
            children: [
              _buildFilterHeader(shops, selectedShop, stats, statementStart, isDark),
              Expanded(
                child: reportAsync.when(
                  data: (data) => _buildReportContent(data, isDark),
                  loading: () => const Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  ),
                  error: (err, _) => Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.error_outline, size: 48, color: AppColors.error),
                          const SizedBox(height: 12),
                          Text('Failed to load statement: $err'),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
        error: (err, _) => Center(child: Text('Error loading shops: $err')),
      ),
    );
  }

  Widget _buildFilterHeader(
    List<Shop> shops,
    Shop selectedShop,
    ShopStats? stats,
    DateTime? statementStart,
    bool isDark,
  ) {
    String startLabel;
    if (stats?.lastResetAt != null) {
      startLabel = DateFormat('dd MMM yyyy, hh:mm a').format(stats!.lastResetAt!);
    } else {
      startLabel = '${DateFormat('dd MMM yyyy, hh:mm a').format(selectedShop.createdAt)} (Shop Created)';
    }

    final endLabel = DateFormat('dd MMM yyyy, hh:mm a').format(_exportTimestamp);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.surface,
        border: Border(
          bottom: BorderSide(
            color: isDark ? AppColors.darkDivider : AppColors.divider,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.storefront_rounded,
                size: 20,
                color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
              ),
              const SizedBox(width: 10),
              const Text(
                'Shop:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.darkBackground : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isDark ? AppColors.darkDivider : AppColors.divider,
                    ),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedShopId,
                      isExpanded: true,
                      dropdownColor: isDark ? AppColors.darkSurface : AppColors.surface,
                      items: shops.map((s) {
                        return DropdownMenuItem<String>(
                          value: s.id,
                          child: Text(
                            s.name,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        );
                      }).toList(),
                      onChanged: (newShopId) {
                        if (newShopId != null) {
                          setState(() {
                            _selectedShopId = newShopId;
                            _exportTimestamp = DateTime.now();
                          });
                        }
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkBackground : Colors.orange.shade50.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isDark ? AppColors.darkDivider : Colors.orange.shade200,
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.history_toggle_off_rounded, size: 20, color: AppColors.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text(
                            'Period Start: ',
                            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                          ),
                          Expanded(
                            child: Text(
                              startLabel,
                              style: TextStyle(
                                fontSize: 11.5,
                                color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          const Text(
                            'Export Window: ',
                            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                          ),
                          Expanded(
                            child: Text(
                              endLabel,
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: AppColors.primary,
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReportContent(MonthlyReportData data, bool isDark) {
    if (!data.hasValidPeriod) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.warning_amber_rounded, size: 48, color: Colors.orange),
              const SizedBox(height: 12),
              const Text(
                'No Reset or Creation Timestamp Available',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'A formal vendor statement requires an authoritative reset timestamp or shop creation date.',
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isExportingPdf ? null : () => _handleExportPdf(data),
                  icon: _isExportingPdf
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.picture_as_pdf_rounded, size: 18),
                  label: const Text(
                    'EXPORT PDF',
                    style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isExportingXlsx ? null : () => _handleExportXlsx(data),
                  icon: _isExportingXlsx
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.table_chart_rounded, size: 18),
                  label: const Text(
                    'EXPORT EXCEL',
                    style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF107C41),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _buildKpiSummaryCard(data, isDark),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Orders Breakdown',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              Text(
                '${data.totalOrdersCount} closed orders',
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (data.orders.isEmpty)
            _buildEmptyOrdersState(isDark)
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: data.orders.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final order = data.orders[index];
                return _buildOrderPreviewCard(order, isDark);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildKpiSummaryCard(MonthlyReportData data, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? AppColors.darkDivider : AppColors.divider,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'STATEMENT PERFORMANCE',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                  color: AppColors.primary,
                ),
              ),
              Expanded(
                child: Text(
                  data.formattedPeriod,
                  textAlign: TextAlign.end,
                  style: TextStyle(
                    fontSize: 10.5,
                    color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _buildCounterBox('Total Closed', '${data.totalOrdersCount}', Icons.receipt_long_rounded, AppColors.primary, isDark),
              const SizedBox(width: 10),
              _buildCounterBox('Delivered', '${data.deliveredOrdersCount}', Icons.check_circle_rounded, AppColors.success, isDark),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _buildCounterBox('Rejected', '${data.rejectedOrdersCount}', Icons.cancel_rounded, AppColors.error, isDark),
              const SizedBox(width: 10),
              _buildCounterBox('Expired', '${data.expiredOrdersCount}', Icons.hourglass_disabled_rounded, Colors.orange, isDark),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _buildCounterBox('WhatsApp Orders', '${data.whatsappOrdersCount}', Icons.chat_rounded, const Color(0xFF25D366), isDark),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Delivered Sales Value:',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
              Text(
                '₹${data.deliveredSalesValue.toStringAsFixed(0)}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: AppColors.success,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Closed Order Value:',
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
                ),
              ),
              Text(
                '₹${data.closedOrderValue.toStringAsFixed(0)}',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCounterBox(String label, String count, IconData icon, Color color, bool isDark) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: isDark ? 0.15 : 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 22, color: color),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  count,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: color,
                  ),
                ),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderPreviewCard(AppOrder order, bool isDark) {
    final statusColor = switch (order.status.toLowerCase()) {
      'delivered' => AppColors.success,
      'rejected' => AppColors.error,
      'cancelled' => AppColors.error,
      'delivery_expired' => Colors.orange,
      _ => AppColors.primary,
    };

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? AppColors.darkDivider : AppColors.divider,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '#${order.orderId.length > 8 ? order.orderId.substring(order.orderId.length - 8).toUpperCase() : order.orderId.toUpperCase()}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  order.status.toString().toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${order.customerName} • ${order.customerPhone}',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
                ),
              ),
              Text(
                '₹${order.totalAmount.toStringAsFixed(0)}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            DateFormat('dd MMM yyyy, hh:mm a').format(order.createdAt),
            style: TextStyle(
              fontSize: 10.5,
              color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyOrdersState(bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? AppColors.darkDivider : AppColors.divider,
        ),
      ),
      child: Column(
        children: [
          Icon(
            Icons.receipt_long_outlined,
            size: 48,
            color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
          ),
          const SizedBox(height: 12),
          const Text(
            'No closed orders recorded for this shop in the statement period.',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          const SizedBox(height: 6),
          Text(
            'New completed orders will appear here automatically.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
