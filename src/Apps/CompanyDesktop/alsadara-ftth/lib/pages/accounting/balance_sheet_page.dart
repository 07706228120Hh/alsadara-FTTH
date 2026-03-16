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

/// صفحة الميزانية العمومية - Balance Sheet
/// أصول = التزامات + حقوق ملكية
class BalanceSheetPage extends StatefulWidget {
  final String? companyId;

  const BalanceSheetPage({super.key, this.companyId});

  @override
  State<BalanceSheetPage> createState() => _BalanceSheetPageState();
}

class _BalanceSheetPageState extends State<BalanceSheetPage> {
  bool _isLoading = true;
  String? _errorMessage;
  List<dynamic> _allAccounts = [];

  final _fmt = NumberFormat('#,##0.00', 'en');

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

  List<dynamic> _leafByType(String type) => _allAccounts
      .where((a) =>
          a['IsLeaf'] == true &&
          (a['AccountType']?.toString() == type ||
              a['Type']?.toString() == type))
      .toList();

  // الأصول (كود يبدأ بـ 1)
  List<dynamic> get _assets => _leafByType('Assets');

  // الالتزامات (كود يبدأ بـ 2)
  List<dynamic> get _liabilities => _leafByType('Liabilities');

  // حقوق الملكية (كود يبدأ بـ 3)
  List<dynamic> get _equity => _leafByType('Equity');

  // الإيرادات والمصروفات — لحساب الأرباح المحتجزة
  List<dynamic> get _revenueAccounts => _leafByType('Revenue');
  List<dynamic> get _expenseAccounts => _leafByType('Expenses');

  double _sumBalances(List<dynamic> accounts) {
    double sum = 0;
    for (final a in accounts) {
      sum += _balance(a).abs();
    }
    return sum;
  }

  double get _totalAssets => _sumBalances(_assets);
  double get _totalLiabilities => _sumBalances(_liabilities);
  double get _totalEquity => _sumBalances(_equity);

  // صافي الدخل (الأرباح المحتجزة للفترة الحالية)
  double get _retainedEarnings {
    final rev = _sumBalances(_revenueAccounts);
    final exp = _sumBalances(_expenseAccounts);
    return rev - exp;
  }

  // إجمالي الالتزامات + حقوق الملكية + الأرباح المحتجزة
  double get _totalLiabilitiesAndEquity =>
      _totalLiabilities + _totalEquity + _retainedEarnings;

  double get _difference => (_totalAssets - _totalLiabilitiesAndEquity).abs();
  bool get _isBalanced => _difference < 0.01;

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
              gradient: AccountingTheme.neonPurpleGradient,
              borderRadius: BorderRadius.circular(isMob ? 6 : 8),
            ),
            child: Icon(Icons.account_balance_rounded,
                color: Colors.white, size: isMob ? 16 : ar.iconM),
          ),
          SizedBox(width: isMob ? 6 : ar.spaceM),
          Text('الميزانية العمومية',
              style: GoogleFonts.cairo(
                fontSize: isMob ? 14 : ar.headingMedium,
                fontWeight: FontWeight.bold,
                color: AccountingTheme.textPrimary,
              )),
          const Spacer(),
          // حالة التوازن
          Container(
            padding: EdgeInsets.symmetric(
                horizontal: isMob ? 8 : 12, vertical: isMob ? 4 : 6),
            decoration: BoxDecoration(
              color: _isBalanced
                  ? AccountingTheme.success.withOpacity(0.15)
                  : AccountingTheme.danger.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _isBalanced
                    ? AccountingTheme.success
                    : AccountingTheme.danger,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _isBalanced ? Icons.check_circle : Icons.warning_rounded,
                  size: isMob ? 14 : 18,
                  color: _isBalanced
                      ? AccountingTheme.success
                      : AccountingTheme.danger,
                ),
                SizedBox(width: 4),
                Text(
                  _isBalanced ? 'متوازنة' : 'غير متوازنة',
                  style: GoogleFonts.cairo(
                    fontSize: isMob ? 10 : ar.small,
                    fontWeight: FontWeight.bold,
                    color: _isBalanced
                        ? AccountingTheme.success
                        : AccountingTheme.danger,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: isMob ? 4 : 8),
          IconButton(
            onPressed: _isLoading
                ? null
                : () async {
                    try {
                      final path =
                          await AccountingExportService.exportBalanceSheet(
                        assets: _assets,
                        liabilities: _liabilities,
                        equity: _equity,
                        totalAssets: _totalAssets,
                        totalLiabilities: _totalLiabilities,
                        totalEquity: _totalEquity,
                        retainedEarnings: _retainedEarnings,
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
              await AccountingPdfExportService.exportBalanceSheet(
                assets: _assets,
                liabilities: _liabilities,
                equity: _equity,
                totalAssets: _totalAssets,
                totalLiabilities: _totalLiabilities,
                totalEquity: _totalEquity,
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

  Widget _buildContent(AccountingResponsive ar) {
    final isMob = ar.isMobile;
    return SingleChildScrollView(
      padding: EdgeInsets.all(isMob ? 8 : ar.spaceXL),
      child: Column(
        children: [
          // بطاقة المعادلة المحاسبية
          _buildEquationCard(ar),
          SizedBox(height: isMob ? 12 : ar.spaceXL),

          // الأقسام الثلاثة
          if (isMob)
            // عمود واحد في الموبايل
            Column(children: [
              _buildSectionCard(
                title: 'الأصول',
                icon: Icons.account_balance_wallet,
                color: AccountingTheme.neonBlue,
                gradient: AccountingTheme.neonBlueGradient,
                accounts: _assets,
                total: _totalAssets,
                ar: ar,
              ),
              SizedBox(height: ar.spaceM),
              _buildSectionCard(
                title: 'الالتزامات',
                icon: Icons.receipt_long,
                color: AccountingTheme.neonOrange,
                gradient: AccountingTheme.neonOrangeGradient,
                accounts: _liabilities,
                total: _totalLiabilities,
                ar: ar,
              ),
              SizedBox(height: ar.spaceM),
              _buildSectionCard(
                title: 'حقوق الملكية',
                icon: Icons.business_center,
                color: AccountingTheme.neonPurple,
                gradient: AccountingTheme.neonPurpleGradient,
                accounts: _equity,
                total: _totalEquity,
                ar: ar,
                extraRow: _retainedEarnings != 0
                    ? _ExtraRow('الأرباح المحتجزة', _retainedEarnings)
                    : null,
                grandTotal: _totalEquity + _retainedEarnings,
              ),
            ])
          else
            // عمودين في الديسكتوب: أصول | التزامات + حقوق ملكية
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // الجانب الأيسر: الأصول
                Expanded(
                  child: _buildSectionCard(
                    title: 'الأصول',
                    icon: Icons.account_balance_wallet,
                    color: AccountingTheme.neonBlue,
                    gradient: AccountingTheme.neonBlueGradient,
                    accounts: _assets,
                    total: _totalAssets,
                    ar: ar,
                  ),
                ),
                SizedBox(width: ar.spaceXL),
                // الجانب الأيمن: التزامات + حقوق ملكية
                Expanded(
                  child: Column(
                    children: [
                      _buildSectionCard(
                        title: 'الالتزامات',
                        icon: Icons.receipt_long,
                        color: AccountingTheme.neonOrange,
                        gradient: AccountingTheme.neonOrangeGradient,
                        accounts: _liabilities,
                        total: _totalLiabilities,
                        ar: ar,
                      ),
                      SizedBox(height: ar.spaceM),
                      _buildSectionCard(
                        title: 'حقوق الملكية',
                        icon: Icons.business_center,
                        color: AccountingTheme.neonPurple,
                        gradient: AccountingTheme.neonPurpleGradient,
                        accounts: _equity,
                        total: _totalEquity,
                        ar: ar,
                        extraRow: _retainedEarnings != 0
                            ? _ExtraRow('الأرباح المحتجزة', _retainedEarnings)
                            : null,
                        grandTotal: _totalEquity + _retainedEarnings,
                      ),
                      SizedBox(height: ar.spaceM),
                      // إجمالي الالتزامات + حقوق الملكية
                      Container(
                        padding: EdgeInsets.all(ar.spaceL),
                        decoration: BoxDecoration(
                          color: AccountingTheme.bgSidebar,
                          borderRadius: BorderRadius.circular(ar.cardRadius),
                        ),
                        child: Row(
                          children: [
                            Text('إجمالي الالتزامات + حقوق الملكية',
                                style: GoogleFonts.cairo(
                                    fontSize: ar.body,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white)),
                            const Spacer(),
                            Text(_fmt.format(_totalLiabilitiesAndEquity),
                                style: GoogleFonts.cairo(
                                    fontSize: ar.financialMedium,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.white)),
                          ],
                        ),
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

  Widget _buildEquationCard(AccountingResponsive ar) {
    final isMob = ar.isMobile;
    return Container(
      padding: EdgeInsets.all(isMob ? 12 : ar.spaceXL),
      decoration: BoxDecoration(
        color: AccountingTheme.bgCard,
        borderRadius: BorderRadius.circular(ar.cardRadius + 4),
        boxShadow: AccountingTheme.cardShadow,
        border: Border.all(color: AccountingTheme.borderColor),
      ),
      child: Column(
        children: [
          Text('المعادلة المحاسبية',
              style: GoogleFonts.cairo(
                  fontSize: isMob ? 12 : ar.headingSmall,
                  fontWeight: FontWeight.bold,
                  color: AccountingTheme.textPrimary)),
          SizedBox(height: isMob ? 8 : 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _equationItem('الأصول', _totalAssets, AccountingTheme.neonBlue, ar),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: isMob ? 6 : 14),
                child: Text('=',
                    style: GoogleFonts.cairo(
                        fontSize: isMob ? 18 : 24,
                        fontWeight: FontWeight.w900,
                        color: AccountingTheme.textPrimary)),
              ),
              _equationItem(
                  'الالتزامات', _totalLiabilities, AccountingTheme.neonOrange, ar),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: isMob ? 6 : 14),
                child: Text('+',
                    style: GoogleFonts.cairo(
                        fontSize: isMob ? 18 : 24,
                        fontWeight: FontWeight.w900,
                        color: AccountingTheme.textPrimary)),
              ),
              _equationItem('حقوق الملكية', _totalEquity + _retainedEarnings,
                  AccountingTheme.neonPurple, ar),
            ],
          ),
          if (!_isBalanced) ...[
            SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AccountingTheme.danger.withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'فرق: ${_fmt.format(_difference)}',
                style: GoogleFonts.cairo(
                    fontSize: isMob ? 10 : ar.small,
                    fontWeight: FontWeight.bold,
                    color: AccountingTheme.danger),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _equationItem(
      String label, double value, Color color, AccountingResponsive ar) {
    final isMob = ar.isMobile;
    return Column(
      children: [
        Text(label,
            style: GoogleFonts.cairo(
                fontSize: isMob ? 9 : ar.small,
                color: AccountingTheme.textMuted)),
        SizedBox(height: 2),
        Text(_fmt.format(value),
            style: GoogleFonts.cairo(
                fontSize: isMob ? 13 : ar.financialMedium,
                fontWeight: FontWeight.w900,
                color: color)),
      ],
    );
  }

  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required Color color,
    required LinearGradient gradient,
    required List<dynamic> accounts,
    required double total,
    required AccountingResponsive ar,
    _ExtraRow? extraRow,
    double? grandTotal,
  }) {
    final isMob = ar.isMobile;
    return Container(
      decoration: AccountingTheme.card,
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // عنوان
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
                  child: Icon(icon, color: Colors.white, size: isMob ? 14 : 18),
                ),
                SizedBox(width: isMob ? 6 : 10),
                Text(title,
                    style: GoogleFonts.cairo(
                        fontSize: isMob ? 13 : ar.headingSmall,
                        fontWeight: FontWeight.bold,
                        color: AccountingTheme.textPrimary)),
                const Spacer(),
                Text(_fmt.format(grandTotal ?? total),
                    style: GoogleFonts.cairo(
                        fontSize: isMob ? 13 : ar.financialSmall,
                        fontWeight: FontWeight.w900,
                        color: color)),
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
              return Container(
                color: i.isEven
                    ? Colors.transparent
                    : AccountingTheme.tableRowAlt,
                padding: EdgeInsets.symmetric(
                    horizontal: isMob ? 10 : ar.spaceL,
                    vertical: isMob ? 5 : ar.spaceXS),
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
                    Text(_fmt.format(balance),
                        style: GoogleFonts.cairo(
                            fontSize: ar.tableCellFont,
                            fontWeight: FontWeight.w600,
                            color: color)),
                  ],
                ),
              );
            }),
          // صف إضافي (الأرباح المحتجزة)
          if (extraRow != null)
            Container(
              padding: EdgeInsets.symmetric(
                  horizontal: isMob ? 10 : ar.spaceL,
                  vertical: isMob ? 5 : ar.spaceXS),
              decoration: BoxDecoration(
                color: AccountingTheme.neonGreen.withOpacity(0.06),
                border: Border(
                    top: BorderSide(
                        color: AccountingTheme.neonGreen.withOpacity(0.2))),
              ),
              child: Row(
                children: [
                  SizedBox(width: isMob ? 40 : 60),
                  Icon(Icons.trending_up,
                      size: isMob ? 12 : 16,
                      color: extraRow.value >= 0
                          ? AccountingTheme.neonGreen
                          : AccountingTheme.danger),
                  SizedBox(width: 4),
                  Expanded(
                      child: Text(extraRow.label,
                          style: GoogleFonts.cairo(
                              fontSize: ar.tableCellFont,
                              fontWeight: FontWeight.w600,
                              color: AccountingTheme.textSecondary))),
                  Text(_fmt.format(extraRow.value),
                      style: GoogleFonts.cairo(
                          fontSize: ar.tableCellFont,
                          fontWeight: FontWeight.bold,
                          color: extraRow.value >= 0
                              ? AccountingTheme.neonGreen
                              : AccountingTheme.danger)),
                ],
              ),
            ),
          // صف الإجمالي
          Container(
            padding: EdgeInsets.symmetric(
                horizontal: isMob ? 10 : ar.spaceL,
                vertical: isMob ? 6 : ar.spaceS),
            decoration: BoxDecoration(
              color: color.withOpacity(0.08),
              border: Border(top: BorderSide(color: color.withOpacity(0.3))),
            ),
            child: Row(
              children: [
                Text('الإجمالي',
                    style: GoogleFonts.cairo(
                        fontSize: isMob ? 11 : ar.body,
                        fontWeight: FontWeight.bold,
                        color: AccountingTheme.textPrimary)),
                const Spacer(),
                Text(_fmt.format(grandTotal ?? total),
                    style: GoogleFonts.cairo(
                        fontSize: isMob ? 13 : ar.financialSmall,
                        fontWeight: FontWeight.w900,
                        color: color)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ExtraRow {
  final String label;
  final double value;
  const _ExtraRow(this.label, this.value);
}
