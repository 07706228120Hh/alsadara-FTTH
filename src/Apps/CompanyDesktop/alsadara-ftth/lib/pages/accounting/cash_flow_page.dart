import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../../services/accounting_service.dart';
import '../../services/accounting_export_service.dart';
import '../../services/accounting_pdf_export_service.dart';
import '../../theme/accounting_theme.dart';
import '../../theme/accounting_responsive.dart';

/// صفحة التدفقات النقدية - Cash Flow Statement
class CashFlowPage extends StatefulWidget {
  final String? companyId;

  const CashFlowPage({super.key, this.companyId});

  @override
  State<CashFlowPage> createState() => _CashFlowPageState();
}

class _CashFlowPageState extends State<CashFlowPage> {
  bool _isLoading = true;
  String? _errorMessage;

  DateTime _dateFrom = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _dateTo = DateTime.now();

  List<Map<String, dynamic>> _operatingItems = [];
  List<Map<String, dynamic>> _investingItems = [];
  List<Map<String, dynamic>> _financingItems = [];

  double _totalOperating = 0;
  double _totalInvesting = 0;
  double _totalFinancing = 0;

  final _fmt = NumberFormat('#,##0', 'ar');
  final _dateFmt = DateFormat('yyyy/MM/dd');

  // ألوان الأقسام
  static const _operatingColor = Color(0xFF3498DB);
  static const _investingColor = Color(0xFF8E44AD);
  static const _financingColor = Color(0xFFE67E22);
  static const _positiveColor = Color(0xFF27AE60);
  static const _negativeColor = Color(0xFFE74C3C);

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final fromStr = _dateFmt.format(_dateFrom);
      final toStr = _dateFmt.format(_dateTo);

      final results = await Future.wait([
        AccountingService.instance.getCollections(
          companyId: widget.companyId,
          isDelivered: true,
          fromDate: fromStr,
          toDate: toStr,
        ),
        AccountingService.instance.getExpenses(
          companyId: widget.companyId,
          fromDate: fromStr,
          toDate: toStr,
        ),
        AccountingService.instance.getSalaries(
          companyId: widget.companyId,
          month: _dateFrom.month,
          year: _dateFrom.year,
          status: 'Paid',
        ),
      ]);

      if (!mounted) return;

      final collectionsResult = results[0];
      final expensesResult = results[1];
      final salariesResult = results[2];

      final operating = <Map<String, dynamic>>[];
      double totalOp = 0;

      // --- التحصيلات (تدفق داخل) ---
      if (collectionsResult['success'] == true) {
        final collections =
            (collectionsResult['data'] is List) ? collectionsResult['data'] : [];
        for (final c in collections) {
          final amount =
              ((c['Amount'] ?? c['amount'] ?? 0) as num).toDouble();
          final desc = c['Description'] ??
              c['description'] ??
              c['TechnicianName'] ??
              'تحصيل';
          final date = c['CreatedAt'] ?? c['createdAt'] ?? '';
          operating.add({
            'description': desc.toString(),
            'amount': amount,
            'date': date.toString(),
            'referenceType': 'تحصيل',
          });
          totalOp += amount;
        }
      }

      // --- المصروفات (تدفق خارج) ---
      if (expensesResult['success'] == true) {
        final expenses =
            (expensesResult['data'] is List) ? expensesResult['data'] : [];
        for (final e in expenses) {
          final amount =
              ((e['Amount'] ?? e['amount'] ?? 0) as num).toDouble();
          final desc =
              e['Description'] ?? e['description'] ?? e['Category'] ?? 'مصروف';
          final date = e['CreatedAt'] ?? e['createdAt'] ?? '';
          operating.add({
            'description': desc.toString(),
            'amount': -amount,
            'date': date.toString(),
            'referenceType': 'مصروف',
          });
          totalOp -= amount;
        }
      }

      // --- الرواتب (تدفق خارج) ---
      if (salariesResult['success'] == true) {
        final salaries =
            (salariesResult['data'] is List) ? salariesResult['data'] : [];
        for (final s in salaries) {
          final netSalary =
              ((s['NetSalary'] ?? s['netSalary'] ?? 0) as num).toDouble();
          final empName =
              s['EmployeeName'] ?? s['employeeName'] ?? 'موظف';
          operating.add({
            'description': 'راتب - $empName',
            'amount': -netSalary,
            'date': '',
            'referenceType': 'راتب',
          });
          totalOp -= netSalary;
        }
      }

      // ترتيب حسب المبلغ (الأكبر أولاً)
      operating.sort(
          (a, b) => (b['amount'] as double).abs().compareTo((a['amount'] as double).abs()));

      setState(() {
        _operatingItems = operating;
        _investingItems = [];
        _financingItems = [];
        _totalOperating = totalOp;
        _totalInvesting = 0;
        _totalFinancing = 0;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'خطأ في الاتصال';
        _isLoading = false;
      });
    }
  }

  double get _netCashFlow => _totalOperating + _totalInvesting + _totalFinancing;

  bool get _isPositive => _netCashFlow >= 0;

  String _formatCurrency(double amount) {
    final prefix = amount < 0 ? '-' : '';
    return '$prefix${_fmt.format(amount.abs().round())} د.ع';
  }

  @override
  Widget build(BuildContext context) {
    final ar = context.accR;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F6FA),
        body: SafeArea(
          child: Column(
            children: [
              _buildToolbar(ar),
              Expanded(
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(
                            color: AccountingTheme.neonGreen))
                    : _errorMessage != null
                        ? AccountingTheme.errorView(_errorMessage!, _loadData)
                        : _buildContent(ar),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // شريط الأدوات
  // ═══════════════════════════════════════════════════════════════

  Widget _buildToolbar(AccountingResponsive ar) {
    final isMob = ar.isMobile;
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: isMob ? 8 : ar.spaceXL, vertical: isMob ? 6 : ar.spaceL),
      decoration: const BoxDecoration(
        color: AccountingTheme.bgCard,
        border: Border(bottom: BorderSide(color: AccountingTheme.borderColor)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: Icon(Icons.arrow_forward_rounded, size: isMob ? 20 : 24),
            tooltip: 'رجوع',
            style: IconButton.styleFrom(
                foregroundColor: AccountingTheme.textSecondary),
          ),
          SizedBox(width: isMob ? 4 : ar.spaceS),
          Container(
            padding: EdgeInsets.all(isMob ? 4 : ar.spaceS),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF00BCD4), Color(0xFF0097A7)],
              ),
              borderRadius: BorderRadius.circular(isMob ? 6 : 8),
            ),
            child: Icon(Icons.waterfall_chart_rounded,
                color: Colors.white, size: isMob ? 16 : ar.iconM),
          ),
          SizedBox(width: isMob ? 6 : ar.spaceM),
          Text('التدفقات النقدية',
              style: GoogleFonts.cairo(
                fontSize: isMob ? 14 : ar.headingMedium,
                fontWeight: FontWeight.bold,
                color: AccountingTheme.textPrimary,
              )),
          const Spacer(),
          // فلتر التاريخ
          InkWell(
            onTap: () => _pickDateRange(context),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: EdgeInsets.symmetric(
                  horizontal: isMob ? 6 : 10, vertical: isMob ? 3 : 5),
              decoration: BoxDecoration(
                color: AccountingTheme.bgSecondary,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AccountingTheme.borderColor),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.calendar_month,
                      size: isMob ? 12 : 16,
                      color: AccountingTheme.neonBlue),
                  const SizedBox(width: 4),
                  Text(
                    '${_dateFmt.format(_dateFrom)} - ${_dateFmt.format(_dateTo)}',
                    style: GoogleFonts.cairo(
                        fontSize: isMob ? 9 : ar.small,
                        color: AccountingTheme.textSecondary),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(width: isMob ? 4 : 8),
          // تصدير
          IconButton(
            onPressed: _isLoading ? null : _exportReport,
            icon: Icon(Icons.file_download_outlined, size: isMob ? 18 : 22),
            tooltip: 'تصدير Excel',
            style: IconButton.styleFrom(
                foregroundColor: AccountingTheme.neonGreen),
          ),
          IconButton(
            onPressed: _isLoading ? null : () async {
              await AccountingPdfExportService.exportCashFlow(
                operating: _operatingItems,
                investing: _investingItems,
                financing: _financingItems,
                totalOperating: _totalOperating,
                totalInvesting: _totalInvesting,
                totalFinancing: _totalFinancing,
              );
            },
            icon: const Icon(Icons.picture_as_pdf),
            tooltip: 'تصدير PDF',
            style: IconButton.styleFrom(foregroundColor: AccountingTheme.textSecondary),
          ),
          // تحديث
          IconButton(
            onPressed: _loadData,
            icon: Icon(Icons.refresh_rounded, size: isMob ? 18 : 22),
            tooltip: 'تحديث',
            style: IconButton.styleFrom(
                foregroundColor: AccountingTheme.neonBlue),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // اختيار التاريخ
  // ═══════════════════════════════════════════════════════════════

  Future<void> _pickDateRange(BuildContext context) async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _dateFrom, end: _dateTo),
      locale: const Locale('ar'),
    );
    if (picked != null && mounted) {
      setState(() {
        _dateFrom = picked.start;
        _dateTo = picked.end;
      });
      _loadData();
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // التصدير
  // ═══════════════════════════════════════════════════════════════

  Future<void> _exportReport() async {
    try {
      final dateRange =
          '${_dateFmt.format(_dateFrom)} - ${_dateFmt.format(_dateTo)}';
      final path = await AccountingExportService.exportCashFlow(
        operating: _operatingItems,
        investing: _investingItems,
        financing: _financingItems,
        totalOperating: _totalOperating,
        totalInvesting: _totalInvesting,
        totalFinancing: _totalFinancing,
        dateRange: dateRange,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم التصدير: $path',
              style: GoogleFonts.cairo(fontSize: 12)),
          backgroundColor: AccountingTheme.success,
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('خطأ في التصدير',
              style: GoogleFonts.cairo(fontSize: 12)),
          backgroundColor: AccountingTheme.danger,
        ),
      );
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // المحتوى الرئيسي
  // ═══════════════════════════════════════════════════════════════

  Widget _buildContent(AccountingResponsive ar) {
    final isMob = ar.isMobile;
    return SingleChildScrollView(
      padding: EdgeInsets.all(isMob ? 8 : ar.spaceXL),
      child: Column(
        children: [
          _buildNetCashFlowCard(ar),
          SizedBox(height: isMob ? 12 : ar.spaceXL),
          _buildSectionCard(
            title: 'الأنشطة التشغيلية',
            icon: Icons.settings_rounded,
            color: _operatingColor,
            gradient: const LinearGradient(
              colors: [Color(0xFF3498DB), Color(0xFF2980B9)],
            ),
            items: _operatingItems,
            total: _totalOperating,
            ar: ar,
          ),
          SizedBox(height: isMob ? 12 : ar.spaceXL),
          _buildSectionCard(
            title: 'الأنشطة الاستثمارية',
            icon: Icons.trending_up_rounded,
            color: _investingColor,
            gradient: const LinearGradient(
              colors: [Color(0xFF8E44AD), Color(0xFF7D3C98)],
            ),
            items: _investingItems,
            total: _totalInvesting,
            ar: ar,
          ),
          SizedBox(height: isMob ? 12 : ar.spaceXL),
          _buildSectionCard(
            title: 'الأنشطة التمويلية',
            icon: Icons.account_balance_rounded,
            color: _financingColor,
            gradient: const LinearGradient(
              colors: [Color(0xFFE67E22), Color(0xFFD35400)],
            ),
            items: _financingItems,
            total: _totalFinancing,
            ar: ar,
          ),
          SizedBox(height: isMob ? 16 : ar.spaceXL),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // بطاقة صافي التدفق النقدي
  // ═══════════════════════════════════════════════════════════════

  Widget _buildNetCashFlowCard(AccountingResponsive ar) {
    final isMob = ar.isMobile;
    return Container(
      padding: EdgeInsets.all(isMob ? 12 : ar.spaceXL),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: _isPositive
              ? [const Color(0xFF27AE60), const Color(0xFF1E8449)]
              : [const Color(0xFFE74C3C), const Color(0xFFC0392B)],
        ),
        borderRadius: BorderRadius.circular(ar.cardRadius + 4),
        boxShadow: [
          BoxShadow(
            color: (_isPositive
                    ? const Color(0xFF27AE60)
                    : const Color(0xFFE74C3C))
                .withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(isMob ? 8 : 14),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              _isPositive ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
              color: Colors.white,
              size: isMob ? 24 : 36,
            ),
          ),
          SizedBox(width: isMob ? 10 : 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'صافي التدفق النقدي',
                  style: GoogleFonts.cairo(
                    fontSize: isMob ? 12 : ar.headingSmall,
                    color: Colors.white.withOpacity(0.9),
                  ),
                ),
                Text(
                  _formatCurrency(_netCashFlow),
                  style: GoogleFonts.cairo(
                    fontSize: isMob ? 20 : ar.financialLarge,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _miniStat('تشغيلي', _formatCurrency(_totalOperating), ar),
              const SizedBox(height: 4),
              _miniStat('استثماري', _formatCurrency(_totalInvesting), ar),
              const SizedBox(height: 4),
              _miniStat('تمويلي', _formatCurrency(_totalFinancing), ar),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniStat(String label, String value, AccountingResponsive ar) {
    final isMob = ar.isMobile;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            style: GoogleFonts.cairo(
                fontSize: isMob ? 9 : ar.caption,
                color: Colors.white.withOpacity(0.7))),
        const SizedBox(width: 6),
        Text(value,
            style: GoogleFonts.cairo(
                fontSize: isMob ? 10 : ar.small,
                fontWeight: FontWeight.bold,
                color: Colors.white)),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // بطاقة قسم (تشغيلي / استثماري / تمويلي)
  // ═══════════════════════════════════════════════════════════════

  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required Color color,
    required LinearGradient gradient,
    required List<Map<String, dynamic>> items,
    required double total,
    required AccountingResponsive ar,
  }) {
    final isMob = ar.isMobile;
    return Container(
      decoration: AccountingTheme.card,
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // عنوان القسم
          Container(
            padding: EdgeInsets.symmetric(
                horizontal: isMob ? 10 : ar.spaceL,
                vertical: isMob ? 8 : ar.spaceM),
            decoration: BoxDecoration(
              color: color.withOpacity(0.08),
              border: Border(bottom: BorderSide(color: color.withOpacity(0.2))),
            ),
            child: Row(
              children: [
                Container(
                  padding: EdgeInsets.all(isMob ? 4 : 6),
                  decoration: BoxDecoration(
                    gradient: gradient,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child:
                      Icon(icon, color: Colors.white, size: isMob ? 14 : 18),
                ),
                SizedBox(width: isMob ? 6 : 10),
                Text(title,
                    style: GoogleFonts.cairo(
                      fontSize: isMob ? 13 : ar.headingSmall,
                      fontWeight: FontWeight.bold,
                      color: AccountingTheme.textPrimary,
                    )),
                const Spacer(),
                Text(
                  _formatCurrency(total),
                  style: GoogleFonts.cairo(
                    fontSize: isMob ? 12 : ar.financialSmall,
                    fontWeight: FontWeight.w900,
                    color: total >= 0 ? _positiveColor : _negativeColor,
                  ),
                ),
              ],
            ),
          ),
          // قائمة العناصر
          if (items.isEmpty)
            Padding(
              padding: EdgeInsets.all(isMob ? 16 : 24),
              child: Text('لا توجد بيانات',
                  style: GoogleFonts.cairo(
                      color: AccountingTheme.textMuted,
                      fontSize: isMob ? 12 : ar.body)),
            )
          else
            ...List.generate(items.length, (i) {
              final item = items[i];
              final amount = (item['amount'] as num).toDouble();
              final description = item['description']?.toString() ?? '';
              final refType = item['referenceType']?.toString() ?? '';

              return Container(
                color: i.isEven
                    ? Colors.transparent
                    : AccountingTheme.tableRowAlt,
                padding: EdgeInsets.symmetric(
                    horizontal: isMob ? 10 : ar.spaceL,
                    vertical: isMob ? 6 : ar.spaceS),
                child: Row(
                  children: [
                    // أيقونة الاتجاه
                    Icon(
                      amount >= 0
                          ? Icons.arrow_downward_rounded
                          : Icons.arrow_upward_rounded,
                      size: isMob ? 14 : 18,
                      color: amount >= 0 ? _positiveColor : _negativeColor,
                    ),
                    SizedBox(width: isMob ? 6 : 10),
                    // الوصف
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(description,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.cairo(
                                  fontSize: ar.tableCellFont,
                                  color: AccountingTheme.textSecondary)),
                          if (refType.isNotEmpty)
                            Text(refType,
                                style: GoogleFonts.cairo(
                                    fontSize: isMob ? 9 : ar.caption,
                                    color: AccountingTheme.textMuted)),
                        ],
                      ),
                    ),
                    // المبلغ
                    SizedBox(
                      width: ar.colAmountW + 20,
                      child: Text(
                        _formatCurrency(amount),
                        textAlign: TextAlign.left,
                        style: GoogleFonts.cairo(
                          fontSize: ar.tableCellFont,
                          fontWeight: FontWeight.w600,
                          color: amount >= 0 ? _positiveColor : _negativeColor,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          // صف الإجمالي
          Container(
            padding: EdgeInsets.symmetric(
                horizontal: isMob ? 10 : ar.spaceL,
                vertical: isMob ? 8 : ar.spaceM),
            decoration: BoxDecoration(
              color: color.withOpacity(0.08),
              border: Border(top: BorderSide(color: color.withOpacity(0.3))),
            ),
            child: Row(
              children: [
                Text('الإجمالي',
                    style: GoogleFonts.cairo(
                        fontSize: isMob ? 12 : ar.body,
                        fontWeight: FontWeight.bold,
                        color: AccountingTheme.textPrimary)),
                if (items.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Text(
                    '(${items.length} عنصر)',
                    style: GoogleFonts.cairo(
                        fontSize: isMob ? 9 : ar.caption,
                        color: AccountingTheme.textMuted),
                  ),
                ],
                const Spacer(),
                Text(
                  _formatCurrency(total),
                  style: GoogleFonts.cairo(
                    fontSize: isMob ? 14 : ar.financialMedium,
                    fontWeight: FontWeight.w900,
                    color: total >= 0 ? _positiveColor : _negativeColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
