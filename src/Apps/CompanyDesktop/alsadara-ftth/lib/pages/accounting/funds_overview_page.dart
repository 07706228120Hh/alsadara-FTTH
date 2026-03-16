import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/accounting_responsive.dart';
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
      _error = 'خطأ';
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
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.error_outline,
                            size: context.accR.iconXL,
                            color: Colors.red.shade400),
                        SizedBox(height: context.accR.spaceS),
                        Text(_error!,
                            style: TextStyle(color: Colors.red.shade700)),
                        SizedBox(height: context.accR.spaceM),
                        ElevatedButton.icon(
                          onPressed: _loadData,
                          icon: const Icon(Icons.refresh),
                          label: const Text('إعادة المحاولة'),
                        ),
                      ],
                    ),
                  )
                : _buildContent(),
      ),
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

    final isMobile = context.accR.isMobile;
    final pad = isMobile ? context.accR.spaceM : context.accR.spaceXL;

    return SingleChildScrollView(
      padding: EdgeInsets.all(pad),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ═══════ الملخص الإجمالي ═══════
          _buildSummaryGrid(summary, electronic, revenue, isMobile),
          SizedBox(
              height: isMobile ? context.accR.spaceM : context.accR.spaceXL),

          // ═══════ صناديق المشغلين (نقد) ═══════
          _buildCategoryCard(
            title: 'صناديق المشغلين (نقد)',
            icon: Icons.account_balance_wallet,
            color: Colors.green,
            total: _toDouble(cashBoxes['total']),
            items: cashBoxes['items'] as List? ?? [],
            accountCode: '1110',
          ),
          SizedBox(height: context.accR.spaceM),

          // ═══════ ذمم المشغلين (آجل) ═══════
          _buildCategoryCard(
            title: 'ذمم المشغلين (آجل)',
            icon: Icons.schedule,
            color: Colors.orange,
            total: _toDouble(operatorDebts['total']),
            items: operatorDebts['items'] as List? ?? [],
            accountCode: '1160',
          ),
          SizedBox(height: context.accR.spaceM),

          // ═══════ ذمم الوكلاء ═══════
          _buildCategoryCard(
            title: 'ذمم الوكلاء',
            icon: Icons.store,
            color: Colors.blue,
            total: _toDouble(agentDebts['total']),
            items: agentDebts['items'] as List? ?? [],
            accountCode: '1150',
          ),
          SizedBox(height: context.accR.spaceM),

          // ═══════ ذمم الفنيين ═══════
          _buildCategoryCard(
            title: 'ذمم الفنيين',
            icon: Icons.engineering,
            color: Colors.brown,
            total: _toDouble(techDebs['total']),
            items: techDebs['items'] as List? ?? [],
            accountCode: '1140',
          ),
          SizedBox(height: context.accR.spaceM),

          // ═══════ الدفع الإلكتروني (ماستر) ═══════
          _buildCategoryCard(
            title: 'الدفع الإلكتروني (ماستر)',
            icon: Icons.credit_card,
            color: Colors.purple,
            total: _toDouble(electronic['total']),
            items: electronic['items'] as List? ?? [],
            accountCode: '1170',
          ),
          SizedBox(height: context.accR.spaceM),

          // ═══════ نشاط آخر 30 يوم (مخفي) ═══════
        ],
      ),
    );
  }

  /// ═══ شبكة الملخص العلوي (responsive grid) ═══
  Widget _buildSummaryGrid(
      Map summary, Map electronic, Map revenue, bool isMobile) {
    final cards = <_SummaryData>[
      _SummaryData('النقد', _toDouble(summary['totalCash']), Colors.green,
          Icons.attach_money),
      _SummaryData('الآجل', _toDouble(summary['totalOperatorDebt']),
          Colors.orange, Icons.schedule),
      _SummaryData('الوكلاء', _toDouble(summary['totalAgentDebt']), Colors.blue,
          Icons.store),
      _SummaryData('الفنيين', _toDouble(summary['totalTechDebt']), Colors.brown,
          Icons.engineering),
      _SummaryData('الإلكتروني', _toDouble(summary['totalElectronic']),
          Colors.purple, Icons.credit_card),
      _SummaryData('التجديد', _toDouble(revenue['renewal']), Colors.teal,
          Icons.autorenew),
      _SummaryData('الشراء', _toDouble(revenue['purchase']), Colors.indigo,
          Icons.shopping_cart),
      _SummaryData('الإجمالي', _toDouble(summary['grandTotal']),
          Colors.red.shade700, Icons.account_balance),
    ];

    final crossCount = isMobile ? 4 : 4;
    final spacing = isMobile ? 6.0 : 10.0;

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossCount,
        crossAxisSpacing: spacing,
        mainAxisSpacing: spacing,
        childAspectRatio: isMobile ? 0.82 : 1.6,
      ),
      itemCount: cards.length,
      itemBuilder: (_, i) => _summaryCard(cards[i], isMobile),
    );
  }

  Widget _summaryCard(_SummaryData d, bool isMobile) {
    final iconSize = isMobile ? 16.0 : 24.0;
    final valueSize = isMobile ? 12.0 : 18.0;
    final labelSize = isMobile ? 9.0 : context.accR.small;

    return Card(
      elevation: 1,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius:
            BorderRadius.circular(isMobile ? 8 : context.accR.cardRadius),
        side: BorderSide(color: d.color.withOpacity(0.3)),
      ),
      child: InkWell(
        borderRadius:
            BorderRadius.circular(isMobile ? 8 : context.accR.cardRadius),
        onTap: () {
          Clipboard.setData(ClipboardData(text: _formatNumber(d.value)));
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('تم نسخ: ${_formatNumber(d.value)}'),
                duration: const Duration(seconds: 1)),
          );
        },
        child: Padding(
          padding: EdgeInsets.symmetric(
              horizontal: isMobile ? 4 : 16, vertical: isMobile ? 4 : 10),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(d.icon, color: d.color, size: iconSize),
              SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(_formatNumber(d.value),
                    style: GoogleFonts.cairo(
                        fontSize: valueSize,
                        fontWeight: FontWeight.w800,
                        color: d.color)),
              ),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(d.title,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.cairo(
                        fontSize: labelSize, color: Colors.grey.shade700)),
              ),
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
    final isMobile = context.accR.isMobile;
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(context.accR.cardRadius),
        side: BorderSide(color: color.withOpacity(0.4), width: 1.5),
      ),
      child: ExpansionTile(
        initiallyExpanded: false,
        tilePadding: EdgeInsets.symmetric(
            horizontal: isMobile ? 8 : context.accR.paddingH),
        leading: Container(
          padding: EdgeInsets.all(isMobile ? 6 : context.accR.spaceS),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon,
              color: color, size: isMobile ? 20 : context.accR.iconM),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(title,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.cairo(
                      fontSize: isMobile ? 13 : context.accR.body,
                      fontWeight: FontWeight.w700)),
            ),
            Container(
              padding: EdgeInsets.symmetric(
                  horizontal: isMobile ? 8 : context.accR.spaceM,
                  vertical: context.accR.spaceXS),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: color.withOpacity(0.3)),
              ),
              child: Text(
                _formatNumber(total),
                style: GoogleFonts.cairo(
                    fontSize: isMobile ? 13 : context.accR.body,
                    fontWeight: FontWeight.w800,
                    color: color),
              ),
            ),
            SizedBox(width: 4),
            Container(
              padding: EdgeInsets.symmetric(
                  horizontal: isMobile ? 6 : 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(context.accR.cardRadius),
              ),
              child: Text('${items.length}',
                  style: TextStyle(
                      fontSize: isMobile ? 11 : context.accR.small,
                      fontWeight: FontWeight.w600)),
            ),
          ],
        ),
        children: [
          if (items.isEmpty)
            Padding(
              padding: EdgeInsets.all(context.accR.spaceXL),
              child: Text('لا توجد حسابات فرعية',
                  style: TextStyle(color: Colors.grey.shade500)),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                    minWidth: MediaQuery.of(context).size.width - 48),
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
                      fontSize: context.accR.small,
                      color: color.shade700),
                  columns: const [
                    DataColumn(
                        label: Expanded(child: Center(child: Text('#')))),
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
                                style:
                                    TextStyle(fontSize: context.accR.small)))),
                        DataCell(Center(
                            child: Text(
                          (item['Code'] ?? item['code'] ?? '').toString(),
                          style: TextStyle(
                              fontSize: context.accR.small,
                              color: Colors.grey.shade600),
                        ))),
                        DataCell(Center(
                            child: Text(
                          (item['Name'] ?? item['name'] ?? '-').toString(),
                          style: TextStyle(
                              fontSize: context.accR.small,
                              fontWeight: FontWeight.w600),
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
                              fontSize: context.accR.financialSmall,
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
        borderRadius: BorderRadius.circular(context.accR.cardRadius),
        side: BorderSide(color: Colors.indigo.shade200),
      ),
      child: Padding(
        padding: EdgeInsets.all(context.accR.spaceXL),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.trending_up, color: Colors.indigo.shade700),
                SizedBox(width: context.accR.spaceS),
                Text('نشاط آخر 30 يوم',
                    style: GoogleFonts.cairo(
                        fontSize: context.accR.body,
                        fontWeight: FontWeight.w700)),
              ],
            ),
            SizedBox(height: context.accR.spaceM),
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
                  padding: EdgeInsets.symmetric(
                      horizontal: context.accR.spaceL,
                      vertical: context.accR.spaceS),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.08),
                    borderRadius:
                        BorderRadius.circular(context.accR.cardRadius),
                    border: Border.all(color: color.withOpacity(0.3)),
                  ),
                  child: Column(
                    children: [
                      Text(name,
                          style: GoogleFonts.cairo(
                              fontSize: context.accR.small,
                              fontWeight: FontWeight.w600,
                              color: color.shade700)),
                      Text('$count عملية',
                          style: TextStyle(
                              fontSize: context.accR.small,
                              color: Colors.grey.shade600)),
                      Text(_formatNumber(total),
                          style: GoogleFonts.cairo(
                              fontSize: context.accR.body,
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
    return v.round().toString();
  }
}

/// بيانات بطاقة ملخص
class _SummaryData {
  final String title;
  final double value;
  final Color color;
  final IconData icon;
  const _SummaryData(this.title, this.value, this.color, this.icon);
}

extension _ColorShade on Color {
  Color get shade700 {
    final hsl = HSLColor.fromColor(this);
    return hsl.withLightness((hsl.lightness * 0.6).clamp(0.0, 1.0)).toColor();
  }
}
