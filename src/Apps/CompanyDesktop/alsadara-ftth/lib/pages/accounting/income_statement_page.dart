import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../../services/accounting_service.dart';
import '../../services/accounting_cache_service.dart';
import '../../services/accounting_export_service.dart';
import '../../services/accounting_pdf_export_service.dart';
import '../../theme/accounting_theme.dart';
import '../../theme/accounting_responsive.dart';
import '../../widgets/accounting_skeleton.dart';

/// صفحة قائمة الدخل - Income Statement (الأرباح والخسائر)
class IncomeStatementPage extends StatefulWidget {
  final String? companyId;

  const IncomeStatementPage({super.key, this.companyId});

  @override
  State<IncomeStatementPage> createState() => _IncomeStatementPageState();
}

class _IncomeStatementPageState extends State<IncomeStatementPage> {
  bool _isLoading = true;
  String? _errorMessage;
  List<dynamic> _allAccounts = [];

  final _fmt = NumberFormat('#,##0.00', 'en');

  // فلتر التاريخ
  DateTime _dateFrom = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _dateTo = DateTime.now();

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
      // محاولة التحميل من الكاش أولاً
      final cachedAccounts = await AccountingCacheService.loadAccounts();
      if (cachedAccounts != null) {
        _allAccounts = cachedAccounts;
        _allAccounts.sort((a, b) => (a['Code']?.toString() ?? '')
            .compareTo(b['Code']?.toString() ?? ''));
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final result = await AccountingService.instance
          .getAccounts(companyId: widget.companyId);
      if (result['success'] == true) {
        _allAccounts = (result['data'] is List) ? result['data'] : [];
        _allAccounts.sort((a, b) => (a['Code']?.toString() ?? '')
            .compareTo(b['Code']?.toString() ?? ''));
        // حفظ في الكاش
        AccountingCacheService.saveAccounts(_allAccounts);
      } else {
        _errorMessage = result['message'] ?? 'خطأ في جلب البيانات';
      }
    } catch (e) {
      _errorMessage = 'خطأ في الاتصال';
    }
    if (mounted) setState(() => _isLoading = false);
  }

  double _balance(dynamic acc) =>
      ((acc['Balance'] ?? acc['CurrentBalance'] ?? 0) as num).toDouble();

  /// حسابات الإيرادات (كود يبدأ بـ 4 أو نوع Revenue)
  List<dynamic> get _revenueAccounts => _allAccounts
      .where((a) =>
          a['IsLeaf'] == true &&
          (a['AccountType']?.toString() == 'Revenue' ||
              a['Type']?.toString() == 'Revenue' ||
              (a['Code']?.toString() ?? '').startsWith('4')))
      .toList();

  /// حسابات المصروفات (كود يبدأ بـ 5 أو نوع Expenses)
  List<dynamic> get _expenseAccounts => _allAccounts
      .where((a) =>
          a['IsLeaf'] == true &&
          (a['AccountType']?.toString() == 'Expenses' ||
              a['Type']?.toString() == 'Expenses' ||
              (a['Code']?.toString() ?? '').startsWith('5')))
      .toList();

  double get _totalRevenue {
    double sum = 0;
    for (final a in _revenueAccounts) {
      sum += _balance(a).abs();
    }
    return sum;
  }

  double get _totalExpenses {
    double sum = 0;
    for (final a in _expenseAccounts) {
      sum += _balance(a).abs();
    }
    return sum;
  }

  double get _netIncome => _totalRevenue - _totalExpenses;

  bool get _isProfit => _netIncome >= 0;

  @override
  Widget build(BuildContext context) {
    final ar = context.accR;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AccountingTheme.bgPrimary,
        body: SafeArea(
          child: Column(
            children: [
              _buildToolbar(ar),
              Expanded(
                child: _isLoading
                    ? const AccountingSkeleton(rows: 8, columns: 4)
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
            style:
                IconButton.styleFrom(foregroundColor: AccountingTheme.textSecondary),
          ),
          SizedBox(width: isMob ? 4 : ar.spaceS),
          Container(
            padding: EdgeInsets.all(isMob ? 4 : ar.spaceS),
            decoration: BoxDecoration(
              gradient: AccountingTheme.neonGreenGradient,
              borderRadius: BorderRadius.circular(isMob ? 6 : 8),
            ),
            child: Icon(Icons.trending_up_rounded,
                color: Colors.white, size: isMob ? 16 : ar.iconM),
          ),
          SizedBox(width: isMob ? 6 : ar.spaceM),
          Text('قائمة الدخل',
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
                  SizedBox(width: 4),
                  Text(
                    '${DateFormat('yyyy/MM/dd').format(_dateFrom)} - ${DateFormat('yyyy/MM/dd').format(_dateTo)}',
                    style: GoogleFonts.cairo(
                        fontSize: isMob ? 9 : ar.small,
                        color: AccountingTheme.textSecondary),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(width: isMob ? 4 : 8),
          IconButton(
            onPressed: _isLoading
                ? null
                : () async {
                    try {
                      final dateRange =
                          '${DateFormat('yyyy/MM/dd').format(_dateFrom)} - ${DateFormat('yyyy/MM/dd').format(_dateTo)}';
                      final path =
                          await AccountingExportService.exportIncomeStatement(
                        revenue: _revenueAccounts,
                        expenses: _expenseAccounts,
                        totalRevenue: _totalRevenue,
                        totalExpenses: _totalExpenses,
                        netIncome: _netIncome,
                        dateRange: dateRange,
                      );
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('تم التصدير: $path')),
                        );
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('خطأ في التصدير')),
                        );
                      }
                    }
                  },
            icon: Icon(Icons.file_download_outlined, size: isMob ? 18 : 22),
            tooltip: 'تصدير Excel',
            style:
                IconButton.styleFrom(foregroundColor: AccountingTheme.neonGreen),
          ),
          IconButton(
            onPressed: _isLoading ? null : () async {
              await AccountingPdfExportService.exportIncomeStatement(
                revenue: _revenueAccounts,
                expenses: _expenseAccounts,
                totalRevenue: _totalRevenue,
                totalExpenses: _totalExpenses,
                netIncome: _netIncome,
              );
            },
            icon: const Icon(Icons.picture_as_pdf),
            tooltip: 'تصدير PDF',
            style: IconButton.styleFrom(foregroundColor: AccountingTheme.textSecondary),
          ),
          IconButton(
            onPressed: _loadData,
            icon: Icon(Icons.refresh_rounded, size: isMob ? 18 : 22),
            tooltip: 'تحديث',
            style:
                IconButton.styleFrom(foregroundColor: AccountingTheme.neonBlue),
          ),
        ],
      ),
    );
  }

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

  Widget _buildContent(AccountingResponsive ar) {
    final isMob = ar.isMobile;
    return SingleChildScrollView(
      padding: EdgeInsets.all(isMob ? 8 : ar.spaceXL),
      child: Column(
        children: [
          // بطاقة ملخص صافي الدخل
          _buildNetIncomeCard(ar),
          SizedBox(height: isMob ? 12 : ar.spaceXL),

          // قسم الإيرادات
          _buildSection(
            title: 'الإيرادات',
            icon: Icons.arrow_downward_rounded,
            iconColor: AccountingTheme.neonGreen,
            gradient: AccountingTheme.neonGreenGradient,
            accounts: _revenueAccounts,
            total: _totalRevenue,
            totalLabel: 'إجمالي الإيرادات',
            ar: ar,
          ),
          SizedBox(height: isMob ? 12 : ar.spaceXL),

          // قسم المصروفات
          _buildSection(
            title: 'المصروفات',
            icon: Icons.arrow_upward_rounded,
            iconColor: AccountingTheme.danger,
            gradient: AccountingTheme.neonPinkGradient,
            accounts: _expenseAccounts,
            total: _totalExpenses,
            totalLabel: 'إجمالي المصروفات',
            ar: ar,
          ),
        ],
      ),
    );
  }

  Widget _buildNetIncomeCard(AccountingResponsive ar) {
    final isMob = ar.isMobile;
    return Container(
      padding: EdgeInsets.all(isMob ? 12 : ar.spaceXL),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: _isProfit
              ? [const Color(0xFF1ABC9C), const Color(0xFF16A085)]
              : [const Color(0xFFE74C3C), const Color(0xFFC0392B)],
        ),
        borderRadius: BorderRadius.circular(ar.cardRadius + 4),
        boxShadow: [
          BoxShadow(
            color: (_isProfit ? const Color(0xFF1ABC9C) : const Color(0xFFE74C3C))
                .withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          // أيقونة
          Container(
            padding: EdgeInsets.all(isMob ? 8 : 14),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              _isProfit ? Icons.trending_up : Icons.trending_down,
              color: Colors.white,
              size: isMob ? 24 : 36,
            ),
          ),
          SizedBox(width: isMob ? 10 : 20),
          // المعلومات
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isProfit ? 'صافي الربح' : 'صافي الخسارة',
                  style: GoogleFonts.cairo(
                    fontSize: isMob ? 12 : ar.headingSmall,
                    color: Colors.white.withOpacity(0.9),
                  ),
                ),
                Text(
                  _fmt.format(_netIncome.abs()),
                  style: GoogleFonts.cairo(
                    fontSize: isMob ? 20 : ar.financialLarge,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          // التفاصيل
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _miniStat('الإيرادات', _fmt.format(_totalRevenue), ar),
              SizedBox(height: 4),
              _miniStat('المصروفات', _fmt.format(_totalExpenses), ar),
              SizedBox(height: 4),
              if (_totalRevenue > 0)
                _miniStat(
                  'هامش الربح',
                  '${(_netIncome / _totalRevenue * 100).toStringAsFixed(1)}%',
                  ar,
                ),
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
        SizedBox(width: 6),
        Text(value,
            style: GoogleFonts.cairo(
                fontSize: isMob ? 10 : ar.small,
                fontWeight: FontWeight.bold,
                color: Colors.white)),
      ],
    );
  }

  Widget _buildSection({
    required String title,
    required IconData icon,
    required Color iconColor,
    required LinearGradient gradient,
    required List<dynamic> accounts,
    required double total,
    required String totalLabel,
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
              color: iconColor.withOpacity(0.08),
              border:
                  Border(bottom: BorderSide(color: iconColor.withOpacity(0.2))),
            ),
            child: Row(
              children: [
                Container(
                  padding: EdgeInsets.all(isMob ? 4 : 6),
                  decoration: BoxDecoration(
                    gradient: gradient,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(icon, color: Colors.white, size: isMob ? 14 : 18),
                ),
                SizedBox(width: isMob ? 6 : 10),
                Text(title,
                    style: GoogleFonts.cairo(
                      fontSize: isMob ? 13 : ar.headingSmall,
                      fontWeight: FontWeight.bold,
                      color: AccountingTheme.textPrimary,
                    )),
                const Spacer(),
                Text('${accounts.length} حساب',
                    style: GoogleFonts.cairo(
                        fontSize: isMob ? 10 : ar.small,
                        color: AccountingTheme.textMuted)),
              ],
            ),
          ),
          // الحسابات
          if (accounts.isEmpty)
            Padding(
              padding: EdgeInsets.all(isMob ? 16 : 24),
              child: Text('لا توجد حسابات',
                  style: GoogleFonts.cairo(color: AccountingTheme.textMuted)),
            )
          else
            ...List.generate(accounts.length, (i) {
              final acc = accounts[i];
              final balance = _balance(acc).abs();
              final percentage =
                  total > 0 ? (balance / total * 100) : 0.0;

              return Container(
                color: i.isEven
                    ? Colors.transparent
                    : AccountingTheme.tableRowAlt,
                padding: EdgeInsets.symmetric(
                    horizontal: isMob ? 10 : ar.spaceL,
                    vertical: isMob ? 6 : ar.spaceS),
                child: Row(
                  children: [
                    SizedBox(
                        width: isMob ? 40 : 60,
                        child: Text(acc['Code']?.toString() ?? '',
                            style: GoogleFonts.cairo(
                                fontSize: ar.tableCellFont,
                                fontWeight: FontWeight.w600,
                                color: AccountingTheme.textMuted))),
                    Expanded(
                        child: Text(acc['Name']?.toString() ?? '',
                            style: GoogleFonts.cairo(
                                fontSize: ar.tableCellFont,
                                color: AccountingTheme.textSecondary))),
                    // نسبة مئوية
                    SizedBox(
                      width: isMob ? 35 : 50,
                      child: Text(
                        '${percentage.toStringAsFixed(1)}%',
                        textAlign: TextAlign.left,
                        style: GoogleFonts.cairo(
                            fontSize: isMob ? 9 : ar.caption,
                            color: AccountingTheme.textMuted),
                      ),
                    ),
                    // المبلغ
                    SizedBox(
                      width: ar.colAmountW,
                      child: Text(
                        _fmt.format(balance),
                        textAlign: TextAlign.left,
                        style: GoogleFonts.cairo(
                            fontSize: ar.tableCellFont,
                            fontWeight: FontWeight.w600,
                            color: iconColor),
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
              color: iconColor.withOpacity(0.08),
              border:
                  Border(top: BorderSide(color: iconColor.withOpacity(0.3))),
            ),
            child: Row(
              children: [
                Text(totalLabel,
                    style: GoogleFonts.cairo(
                        fontSize: isMob ? 12 : ar.body,
                        fontWeight: FontWeight.bold,
                        color: AccountingTheme.textPrimary)),
                const Spacer(),
                Text(_fmt.format(total),
                    style: GoogleFonts.cairo(
                        fontSize: isMob ? 14 : ar.financialMedium,
                        fontWeight: FontWeight.w900,
                        color: iconColor)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
