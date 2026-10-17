import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../services/api/api_config.dart';
import '../../frontend/frontend.dart';

/// تقرير ربحية التفعيلات — يعرض تكلفة المحفظة وربح الخصم وإيراد الصيانة
class ActivationProfitabilityPage extends StatefulWidget {
  final String? companyId;
  const ActivationProfitabilityPage({super.key, this.companyId});

  @override
  State<ActivationProfitabilityPage> createState() => _ActivationProfitabilityPageState();
}

class _ActivationProfitabilityPageState extends State<ActivationProfitabilityPage> {
  static String get _baseUrl =>
      '${ApiConfig.vpsBaseUrl}/api/internal/subscriptionlogs/profitability';
  static const _apiKey = 'sadara-internal-2024-secure-key';

  bool _isLoading = true;
  Map<String, dynamic>? _summary;
  List<Map<String, dynamic>> _details = [];
  DateTime? _fromDate;
  DateTime? _toDate;

  @override
  void initState() {
    super.initState();
    // افتراضي: اليوم
    final now = DateTime.now();
    _fromDate = DateTime(now.year, now.month, now.day);
    _toDate = _fromDate;
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      String url = '$_baseUrl?';
      if (widget.companyId != null) url += 'companyId=${widget.companyId}&';
      if (_fromDate != null) url += 'fromDate=${_fromDate!.toIso8601String().split('T')[0]}&';
      if (_toDate != null) url += 'toDate=${_toDate!.toIso8601String().split('T')[0]}&';

      final res = await http.get(Uri.parse(url), headers: {'X-Api-Key': _apiKey});
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        if (body['success'] == true) {
          _summary = body['summary'] as Map<String, dynamic>?;
          _details = ((body['data'] ?? []) as List).cast<Map<String, dynamic>>();
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _isLoading = false);
  }

  String _fmt(dynamic v) {
    if (v == null) return '0';
    final n = v is num ? v : (double.tryParse(v.toString()) ?? 0);
    return n.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
  }

  String _fmtDate(dynamic d) {
    if (d == null) return '';
    try {
      final dt = DateTime.parse(d.toString()).toLocal();
      return '${dt.year}/${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')}';
    } catch (_) { return ''; }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: SdColors.ground,
        appBar: SdAppBar(
          title: 'تقرير ربحية التفعيلات',
          subtitle: '${_details.length} سجل',
          actions: [
            SdAppBarAction(
              icon: Icons.refresh,
              label: 'تحديث',
              onPressed: _isLoading ? null : _load,
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              _buildDateFilter(),
              if (_summary != null) _buildSummaryCards(),
              Expanded(child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _details.isEmpty
                      ? const Center(
                          child: SdEmptyState(
                            title: 'لا توجد بيانات',
                            icon: Icons.analytics_outlined,
                          ),
                        )
                      : _buildTable()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDateFilter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      color: SdColors.surface,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _dateChip('اليوم', 0),
            const SizedBox(width: 6),
            _dateChip('أمس', 1),
            const SizedBox(width: 6),
            _dateChip('هذا الأسبوع', 7),
            const SizedBox(width: 6),
            _dateChip('هذا الشهر', 30),
            const SizedBox(width: 6),
            _dateChip('الكل', -1),
            const SizedBox(width: 12),
            TextButton.icon(
              onPressed: () async {
                final picked = await showDateRangePicker(
                  context: context,
                  firstDate: DateTime(2024),
                  lastDate: DateTime.now().add(const Duration(days: 1)),
                  initialDateRange: _fromDate != null && _toDate != null ? DateTimeRange(start: _fromDate!, end: _toDate!) : null,
                );
                if (picked != null) {
                  setState(() { _fromDate = picked.start; _toDate = picked.end; });
                  _load();
                }
              },
              icon: const Icon(Icons.date_range, size: 16),
              label: Text('مخصص', style: TextStyle(fontFamily: 'Cairo', fontSize: 11.5)),
              style: TextButton.styleFrom(foregroundColor: SdColors.info),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dateChip(String label, int days) {
    return ChoiceChip(
      label: Text(label, style: TextStyle(fontFamily: 'Cairo', fontSize: 11.5, color: SdColors.muted)),
      selected: false,
      backgroundColor: SdColors.surfaceAlt,
      side: const BorderSide(color: SdColors.divider),
      onSelected: (_) {
        final now = DateTime.now();
        if (days == -1) {
          _fromDate = null; _toDate = null;
        } else if (days == 0) {
          _fromDate = DateTime(now.year, now.month, now.day); _toDate = _fromDate;
        } else if (days == 1) {
          _fromDate = DateTime(now.year, now.month, now.day - 1); _toDate = _fromDate;
        } else {
          _fromDate = DateTime(now.year, now.month, now.day - days); _toDate = DateTime(now.year, now.month, now.day);
        }
        _load();
      },
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _buildSummaryCards() {
    final s = _summary!;
    return Container(
      padding: const EdgeInsets.all(12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _summaryCard('ما دفعه المشتركون', _fmt(s['TotalPaidBySubscribers'] ?? s['totalPaidBySubscribers']), SdColors.primary),
          _summaryCard('تكلفة المحفظة', _fmt(s['TotalWalletCost'] ?? s['totalWalletCost']), SdColors.warning),
          _summaryCard('إيراد الاشتراكات', _fmt(s['TotalSubscriptionRevenue'] ?? s['totalSubscriptionRevenue']), SdColors.info),
          _summaryCard('إيراد الصيانة', _fmt(s['TotalMaintenanceRevenue'] ?? s['totalMaintenanceRevenue']), SdColors.warning),
          _summaryCard('ربح الخصم', _fmt(s['TotalDiscountProfit'] ?? s['totalDiscountProfit']), SdColors.success),
          _summaryCard('إجمالي الربح', _fmt(s['TotalProfit'] ?? s['totalProfit']), SdColors.success),
        ],
      ),
    );
  }

  Widget _summaryCard(String label, String value, Color color) {
    final screenWidth = MediaQuery.of(context).size.width;
    final cardWidth = screenWidth < 600 ? (screenWidth - 48) / 2 : 180.0;
    return Container(
      width: cardWidth,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: SdColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontFamily: 'Cairo', color: SdColors.faint, fontSize: 11.5)),
          const SizedBox(height: 4),
          Text('$value د.ع', style: TextStyle(fontFamily: 'Cairo', color: color, fontSize: 16, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildTable() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(SdColors.surfaceAlt),
          dataRowColor: WidgetStateProperty.all(SdColors.surface),
          columnSpacing: 16,
          horizontalMargin: 12,
          headingTextStyle: TextStyle(fontFamily: 'Cairo', color: SdColors.ink, fontSize: 11.5, fontWeight: FontWeight.bold),
          dataTextStyle: TextStyle(fontFamily: 'Cairo', color: SdColors.muted, fontSize: 11.5),
          columns: const [
            DataColumn(label: Text('التاريخ')),
            DataColumn(label: Text('العميل')),
            DataColumn(label: Text('الباقة')),
            DataColumn(label: Text('المشغّل')),
            DataColumn(label: Text('الزون')),
            DataColumn(label: Text('النوع')),
            DataColumn(label: Text('دفع المشترك'), numeric: true),
            DataColumn(label: Text('تكلفة المحفظة'), numeric: true),
            DataColumn(label: Text('صيانة'), numeric: true),
            DataColumn(label: Text('ربح الخصم'), numeric: true),
            DataColumn(label: Text('إجمالي الربح'), numeric: true),
          ],
          rows: _details.map((d) {
            final profit = ((d['TotalProfit'] ?? d['totalProfit'] ?? 0) as num).toDouble();
            return DataRow(cells: [
              DataCell(Text(_fmtDate(d['ActivationDate'] ?? d['activationDate']))),
              DataCell(Text(d['CustomerName'] ?? d['customerName'] ?? '', overflow: TextOverflow.ellipsis)),
              DataCell(Text(d['PlanName'] ?? d['planName'] ?? '')),
              DataCell(Text(d['ActivatedBy'] ?? d['activatedBy'] ?? '')),
              DataCell(Text(d['ZoneName'] ?? d['zoneName'] ?? '')),
              DataCell(Text(_opType(d['OperationType'] ?? d['operationType'] ?? ''))),
              DataCell(Text(_fmt(d['PaidBySubscriber'] ?? d['paidBySubscriber']))),
              DataCell(Text(_fmt(d['WalletCost'] ?? d['walletCost']), style: TextStyle(color: SdColors.warning))),
              DataCell(Text(_fmt(d['MaintenanceFee'] ?? d['maintenanceFee']), style: const TextStyle(color: SdColors.warning))),
              DataCell(Text(_fmt(d['DiscountProfit'] ?? d['discountProfit']),
                  style: TextStyle(color: profit >= 0 ? SdColors.success : SdColors.danger))),
              DataCell(Text(_fmt(d['TotalProfit'] ?? d['totalProfit']),
                  style: TextStyle(color: profit >= 0 ? SdColors.success : SdColors.danger, fontWeight: FontWeight.bold))),
            ]);
          }).toList(),
        ),
      ),
    );
  }

  String _opType(String t) {
    switch (t.toLowerCase()) {
      case 'renewal': return 'تجديد';
      case 'purchase': return 'شراء';
      case 'change': return 'تغيير';
      default: return t;
    }
  }
}
