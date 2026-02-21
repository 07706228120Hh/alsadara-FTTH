import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/accounting_service.dart';

/// لوحة مراقبة الأموال الموحدة
/// تعرض أرصدة جميع الصناديق والذمم مع تفصيل لكل مشغل/وكيل/فني
class FundsOverviewPage extends StatefulWidget {
  final String? companyId;
  const FundsOverviewPage({super.key, this.companyId});

  @override
  State<FundsOverviewPage> createState() => _FundsOverviewPageState();
}

class _FundsOverviewPageState extends State<FundsOverviewPage> {
  bool _isLoading = true;
  String? _error;
  Map<String, dynamic> _data = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final result = await AccountingService.instance
          .getFundsOverview(companyId: widget.companyId);

      if (result['success'] == true) {
        final raw = result['data'];
        if (raw is Map) {
          _data = Map<String, dynamic>.from(raw);
        } else {
          _error = 'بيانات غير صحيحة';
        }
      } else {
        _error = result['message'] ?? 'خطأ في جلب البيانات';
      }
    } catch (e) {
      _error = 'خطأ: $e';
    }

    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('مراقبة الأموال',
            style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
        backgroundColor: Colors.indigo.shade700,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
            tooltip: 'تحديث',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error_outline,
                          size: 48, color: Colors.red.shade400),
                      const SizedBox(height: 8),
                      Text(_error!,
                          style: TextStyle(color: Colors.red.shade700)),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        onPressed: _loadData,
                        icon: const Icon(Icons.refresh),
                        label: const Text('إعادة المحاولة'),
                      ),
                    ],
                  ),
                )
              : _buildContent(),
    );
  }

  Widget _buildContent() {
    final summary = _data['summary'] as Map? ?? {};
    final cashBoxes = _data['cashBoxes'] as Map? ?? {};
    final operatorDebts = _data['operatorDebts'] as Map? ?? {};
    final agentDebts = _data['agentDebts'] as Map? ?? {};
    final techDebs = _data['technicianDebts'] as Map? ?? {};
    final electronic = _data['electronic'] as Map? ?? {};
    final revenue = _data['revenue'] as Map? ?? {};
    final recentActivity = _data['recentActivity'] as List? ?? [];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ═══════ الملخص الإجمالي ═══════
          _buildSummaryRow(summary, electronic, revenue),
          const SizedBox(height: 16),

          // ═══════ صناديق المشغلين (نقد) ═══════
          _buildCategoryCard(
            title: 'صناديق المشغلين (نقد)',
            icon: Icons.account_balance_wallet,
            color: Colors.green,
            total: _toDouble(cashBoxes['total']),
            items: cashBoxes['items'] as List? ?? [],
            accountCode: '1110',
          ),
          const SizedBox(height: 12),

          // ═══════ ذمم المشغلين (آجل) ═══════
          _buildCategoryCard(
            title: 'ذمم المشغلين (آجل)',
            icon: Icons.schedule,
            color: Colors.orange,
            total: _toDouble(operatorDebts['total']),
            items: operatorDebts['items'] as List? ?? [],
            accountCode: '1160',
          ),
          const SizedBox(height: 12),

          // ═══════ ذمم الوكلاء ═══════
          _buildCategoryCard(
            title: 'ذمم الوكلاء',
            icon: Icons.store,
            color: Colors.blue,
            total: _toDouble(agentDebts['total']),
            items: agentDebts['items'] as List? ?? [],
            accountCode: '1150',
          ),
          const SizedBox(height: 12),

          // ═══════ ذمم الفنيين ═══════
          _buildCategoryCard(
            title: 'ذمم الفنيين',
            icon: Icons.engineering,
            color: Colors.brown,
            total: _toDouble(techDebs['total']),
            items: techDebs['items'] as List? ?? [],
            accountCode: '1140',
          ),
          const SizedBox(height: 12),

          // ═══════ الدفع الإلكتروني (ماستر) ═══════
          _buildCategoryCard(
            title: 'الدفع الإلكتروني (ماستر)',
            icon: Icons.credit_card,
            color: Colors.purple,
            total: _toDouble(electronic['total']),
            items: electronic['items'] as List? ?? [],
            accountCode: '1170',
          ),
          const SizedBox(height: 12),

          // ═══════ نشاط آخر 30 يوم (مخفي) ═══════
        ],
      ),
    );
  }

  /// ═══ صف الملخص العلوي ═══
  Widget _buildSummaryRow(Map summary, Map electronic, Map revenue) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _summaryCard('إجمالي النقد', _toDouble(summary['totalCash']),
            Colors.green, Icons.attach_money),
        _summaryCard(
            'إجمالي الآجل (مشغلين)',
            _toDouble(summary['totalOperatorDebt']),
            Colors.orange,
            Icons.schedule),
        _summaryCard('إجمالي الوكلاء', _toDouble(summary['totalAgentDebt']),
            Colors.blue, Icons.store),
        _summaryCard('إجمالي الفنيين', _toDouble(summary['totalTechDebt']),
            Colors.brown, Icons.engineering),
        _summaryCard('الدفع الإلكتروني', _toDouble(summary['totalElectronic']),
            Colors.purple, Icons.credit_card),
        _summaryCard('إيرادات التجديد', _toDouble(revenue['renewal']),
            Colors.teal, Icons.autorenew),
        _summaryCard('إيرادات الشراء', _toDouble(revenue['purchase']),
            Colors.indigo, Icons.shopping_cart),
        _summaryCard('الإجمالي الكلي', _toDouble(summary['grandTotal']),
            Colors.red.shade700, Icons.account_balance,
            isBig: true),
      ],
    );
  }

  Widget _summaryCard(String title, double value, Color color, IconData icon,
      {bool isBig = false}) {
    return Card(
      elevation: isBig ? 3 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
            color: color.withOpacity(isBig ? 0.6 : 0.3), width: isBig ? 2 : 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () {
          Clipboard.setData(ClipboardData(text: _formatNumber(value)));
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('تم نسخ: ${_formatNumber(value)}'),
                duration: const Duration(seconds: 1)),
          );
        },
        child: Padding(
          padding: EdgeInsets.symmetric(
              horizontal: isBig ? 24 : 16, vertical: isBig ? 14 : 10),
          child: Column(
            children: [
              Icon(icon, color: color, size: isBig ? 28 : 20),
              const SizedBox(height: 4),
              Text(_formatNumber(value),
                  style: GoogleFonts.cairo(
                      fontSize: isBig ? 22 : 18,
                      fontWeight: FontWeight.w800,
                      color: color)),
              Text(title,
                  style: GoogleFonts.cairo(
                      fontSize: 11, color: Colors.grey.shade700)),
            ],
          ),
        ),
      ),
    );
  }

  /// ═══ بطاقة فئة مع جدول تفصيلي ═══
  Widget _buildCategoryCard({
    required String title,
    required IconData icon,
    required Color color,
    required double total,
    required List items,
    required String accountCode,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color.withOpacity(0.4), width: 1.5),
      ),
      child: ExpansionTile(
        initiallyExpanded: false,
        tilePadding: const EdgeInsets.symmetric(horizontal: 16),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 22),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(title,
                  style: GoogleFonts.cairo(
                      fontSize: 14, fontWeight: FontWeight.w700)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: color.withOpacity(0.3)),
              ),
              child: Text(
                _formatNumber(total),
                style: GoogleFonts.cairo(
                    fontSize: 15, fontWeight: FontWeight.w800, color: color),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text('${items.length}',
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
        children: [
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('لا توجد حسابات فرعية',
                  style: TextStyle(color: Colors.grey.shade500)),
            )
          else
            SizedBox(
              width: double.infinity,
              child: DataTable(
                border:
                    TableBorder.all(color: Colors.grey.shade300, width: 0.5),
                headingRowColor:
                    WidgetStateProperty.all(color.withOpacity(0.05)),
                dataRowMinHeight: 32,
                dataRowMaxHeight: 42,
                headingRowHeight: 36,
                columnSpacing: 12,
                horizontalMargin: 16,
                headingTextStyle: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: color.shade700),
                columns: const [
                  DataColumn(label: Expanded(child: Center(child: Text('#')))),
                  DataColumn(
                      label: Expanded(child: Center(child: Text('الكود')))),
                  DataColumn(
                      label: Expanded(child: Center(child: Text('الاسم')))),
                  DataColumn(
                      label: Expanded(child: Center(child: Text('الرصيد')))),
                ],
                rows: items.asMap().entries.map((entry) {
                  final i = entry.key;
                  final item = entry.value as Map;
                  final balance = _toDouble(
                      item['CurrentBalance'] ?? item['currentBalance']);
                  final isNegative = balance < 0;

                  return DataRow(
                    color: WidgetStateProperty.resolveWith((states) {
                      if (isNegative) return Colors.red.shade50;
                      if (balance > 0) return color.withOpacity(0.03);
                      return null;
                    }),
                    cells: [
                      DataCell(Center(
                          child: Text('${i + 1}',
                              style: const TextStyle(fontSize: 11)))),
                      DataCell(Center(
                          child: Text(
                        (item['Code'] ?? item['code'] ?? '').toString(),
                        style: TextStyle(
                            fontSize: 11, color: Colors.grey.shade600),
                      ))),
                      DataCell(Center(
                          child: Text(
                        (item['Name'] ?? item['name'] ?? '-').toString(),
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600),
                      ))),
                      DataCell(Center(
                          child: InkWell(
                        onTap: () {
                          Clipboard.setData(
                              ClipboardData(text: _formatNumber(balance)));
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                                content:
                                    Text('تم نسخ: ${_formatNumber(balance)}'),
                                duration: const Duration(seconds: 1)),
                          );
                        },
                        child: Text(
                          _formatNumber(balance),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: isNegative
                                ? Colors.red.shade700
                                : color.shade700,
                          ),
                        ),
                      ))),
                    ],
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  /// ═══ بطاقة نشاط آخر 30 يوم ═══
  Widget _buildRecentActivityCard(List activity) {
    final typeNames = {
      'cash': 'نقد',
      'credit': 'آجل',
      'master': 'ماستر',
      'agent': 'وكيل',
      'technician': 'فني',
      'unknown': 'غير محدد',
    };
    final typeColors = {
      'cash': Colors.green,
      'credit': Colors.orange,
      'master': Colors.purple,
      'agent': Colors.blue,
      'technician': Colors.brown,
      'unknown': Colors.grey,
    };

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.indigo.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.trending_up, color: Colors.indigo.shade700),
                const SizedBox(width: 8),
                Text('نشاط آخر 30 يوم',
                    style: GoogleFonts.cairo(
                        fontSize: 14, fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: activity.map((a) {
                final item = a as Map;
                final type = (item['type'] ?? 'unknown').toString();
                final count = item['count'] ?? 0;
                final total = _toDouble(item['total']);
                final color = typeColors[type] ?? Colors.grey;
                final name = typeNames[type] ?? type;

                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: color.withOpacity(0.3)),
                  ),
                  child: Column(
                    children: [
                      Text(name,
                          style: GoogleFonts.cairo(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: color.shade700)),
                      Text('$count عملية',
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey.shade600)),
                      Text(_formatNumber(total),
                          style: GoogleFonts.cairo(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: color.shade700)),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  // ═══ أدوات مساعدة ═══

  double _toDouble(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

  String _formatNumber(double v) {
    if (v == 0) return '0';
    final isNeg = v < 0;
    final abs = v.abs();
    final parts = abs.toStringAsFixed(0).split('');
    final buffer = StringBuffer();
    for (int i = 0; i < parts.length; i++) {
      if (i > 0 && (parts.length - i) % 3 == 0) buffer.write(',');
      buffer.write(parts[i]);
    }
    return '${isNeg ? '-' : ''}${buffer.toString()}';
  }
}

extension _ColorShade on Color {
  Color get shade700 {
    final hsl = HSLColor.fromColor(this);
    return hsl.withLightness((hsl.lightness * 0.6).clamp(0.0, 1.0)).toColor();
  }
}
