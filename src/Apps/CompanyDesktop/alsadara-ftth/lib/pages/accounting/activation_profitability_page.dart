import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import '../../theme/accounting_theme.dart';
import '../../theme/accounting_responsive.dart';

/// تقرير ربحية التفعيلات — يعرض تكلفة المحفظة وربح الخصم وإيراد الصيانة
class ActivationProfitabilityPage extends StatefulWidget {
  final String? companyId;
  const ActivationProfitabilityPage({super.key, this.companyId});

  @override
  State<ActivationProfitabilityPage> createState() => _ActivationProfitabilityPageState();
}

class _ActivationProfitabilityPageState extends State<ActivationProfitabilityPage> {
  static const _baseUrl = 'https://api.ramzalsadara.tech/api/internal/subscriptionlogs/profitability';
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
      final dt = DateTime.parse(d.toString());
      return '${dt.year}/${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')}';
    } catch (_) { return ''; }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AccountingTheme.bgPrimary,
        body: SafeArea(
          child: Column(
            children: [
              _buildToolbar(),
              _buildDateFilter(),
              if (_summary != null) _buildSummaryCards(),
              Expanded(child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _details.isEmpty
                      ? Center(child: Text('لا توجد بيانات', style: GoogleFonts.cairo(color: AccountingTheme.textMuted)))
                      : _buildTable()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildToolbar() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: context.accR.spaceXL, vertical: context.accR.spaceL),
      decoration: const BoxDecoration(
        color: AccountingTheme.bgCard,
        border: Border(bottom: BorderSide(color: AccountingTheme.borderColor)),
      ),
      child: Row(
        children: [
          IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_forward_rounded),
              style: IconButton.styleFrom(foregroundColor: AccountingTheme.textSecondary)),
          SizedBox(width: context.accR.spaceS),
          Container(
            padding: EdgeInsets.all(context.accR.spaceS),
            decoration: BoxDecoration(gradient: AccountingTheme.neonGreenGradient, borderRadius: BorderRadius.circular(8)),
            child: Icon(Icons.analytics_outlined, color: Colors.white, size: context.accR.iconM),
          ),
          SizedBox(width: context.accR.spaceM),
          Expanded(child: Text('تقرير ربحية التفعيلات',
              style: GoogleFonts.cairo(fontSize: context.accR.headingMedium, fontWeight: FontWeight.bold, color: AccountingTheme.textPrimary))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(color: AccountingTheme.neonPink.withOpacity(0.2), borderRadius: BorderRadius.circular(12)),
            child: Text('${_details.length}', style: GoogleFonts.cairo(fontSize: context.accR.small, fontWeight: FontWeight.bold, color: AccountingTheme.neonPink)),
          ),
          const SizedBox(width: 8),
          IconButton(onPressed: _load, icon: Icon(Icons.refresh, size: context.accR.iconM),
              style: IconButton.styleFrom(foregroundColor: AccountingTheme.textSecondary)),
        ],
      ),
    );
  }

  Widget _buildDateFilter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: AccountingTheme.bgCard,
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
          const Spacer(),
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
            label: Text('مخصص', style: GoogleFonts.cairo(fontSize: 11)),
            style: TextButton.styleFrom(foregroundColor: AccountingTheme.info),
          ),
        ],
      ),
    );
  }

  Widget _dateChip(String label, int days) {
    return ChoiceChip(
      label: Text(label, style: GoogleFonts.cairo(fontSize: 11, color: AccountingTheme.textSecondary)),
      selected: false,
      backgroundColor: AccountingTheme.bgCardHover,
      side: const BorderSide(color: AccountingTheme.borderColor),
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
          _summaryCard('ما دفعه المشتركون', _fmt(s['TotalPaidBySubscribers'] ?? s['totalPaidBySubscribers']), AccountingTheme.neonBlue),
          _summaryCard('تكلفة المحفظة', _fmt(s['TotalWalletCost'] ?? s['totalWalletCost']), AccountingTheme.warning),
          _summaryCard('إيراد الاشتراكات', _fmt(s['TotalSubscriptionRevenue'] ?? s['totalSubscriptionRevenue']), AccountingTheme.info),
          _summaryCard('إيراد الصيانة', _fmt(s['TotalMaintenanceRevenue'] ?? s['totalMaintenanceRevenue']), Colors.orange),
          _summaryCard('ربح الخصم', _fmt(s['TotalDiscountProfit'] ?? s['totalDiscountProfit']), AccountingTheme.neonGreen),
          _summaryCard('إجمالي الربح', _fmt(s['TotalProfit'] ?? s['totalProfit']), AccountingTheme.success),
        ],
      ),
    );
  }

  Widget _summaryCard(String label, String value, Color color) {
    return Container(
      width: 180,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AccountingTheme.bgCard,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: GoogleFonts.cairo(color: AccountingTheme.textMuted, fontSize: 11)),
          const SizedBox(height: 4),
          Text('$value د.ع', style: GoogleFonts.cairo(color: color, fontSize: 16, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildTable() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(AccountingTheme.bgCardHover),
          dataRowColor: WidgetStateProperty.all(AccountingTheme.bgCard),
          columnSpacing: 16,
          horizontalMargin: 12,
          headingTextStyle: GoogleFonts.cairo(color: AccountingTheme.textPrimary, fontSize: 11, fontWeight: FontWeight.bold),
          dataTextStyle: GoogleFonts.cairo(color: AccountingTheme.textSecondary, fontSize: 11),
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
              DataCell(Text(_fmt(d['WalletCost'] ?? d['walletCost']), style: TextStyle(color: AccountingTheme.warning))),
              DataCell(Text(_fmt(d['MaintenanceFee'] ?? d['maintenanceFee']), style: const TextStyle(color: Colors.orange))),
              DataCell(Text(_fmt(d['DiscountProfit'] ?? d['discountProfit']),
                  style: TextStyle(color: profit >= 0 ? AccountingTheme.neonGreen : AccountingTheme.danger))),
              DataCell(Text(_fmt(d['TotalProfit'] ?? d['totalProfit']),
                  style: TextStyle(color: profit >= 0 ? AccountingTheme.success : AccountingTheme.danger, fontWeight: FontWeight.bold))),
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
