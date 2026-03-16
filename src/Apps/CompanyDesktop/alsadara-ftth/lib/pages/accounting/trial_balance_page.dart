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

/// صفحة ميزان المراجعة - Trial Balance
class TrialBalancePage extends StatefulWidget {
  final String? companyId;

  const TrialBalancePage({super.key, this.companyId});

  @override
  State<TrialBalancePage> createState() => _TrialBalancePageState();
}

class _TrialBalancePageState extends State<TrialBalancePage> {
  bool _isLoading = true;
  String? _errorMessage;
  List<dynamic> _accounts = [];
  String _searchQuery = '';
  String _filterType = 'الكل'; // الكل، أصول، التزامات، حقوق ملكية، إيرادات، مصروفات

  final _fmt = NumberFormat('#,##0.00', 'en');

  static const _typeLabels = {
    'الكل': null,
    'أصول': 'Assets',
    'التزامات': 'Liabilities',
    'حقوق ملكية': 'Equity',
    'إيرادات': 'Revenue',
    'مصروفات': 'Expenses',
  };

  static const _typeColors = {
    'Assets': AccountingTheme.neonBlue,
    'Liabilities': AccountingTheme.neonOrange,
    'Equity': AccountingTheme.neonPurple,
    'Revenue': AccountingTheme.neonGreen,
    'Expenses': AccountingTheme.danger,
  };

  static const _typeLabelsAr = {
    'Assets': 'أصول',
    'Liabilities': 'التزامات',
    'Equity': 'حقوق ملكية',
    'Revenue': 'إيرادات',
    'Expenses': 'مصروفات',
  };

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
        _accounts = cachedAccounts;
        _accounts.sort((a, b) => (a['Code']?.toString() ?? '')
            .compareTo(b['Code']?.toString() ?? ''));
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final result = await AccountingService.instance
          .getAccounts(companyId: widget.companyId);
      if (result['success'] == true) {
        _accounts = (result['data'] is List) ? result['data'] : [];
        // ترتيب حسب الكود
        _accounts.sort((a, b) => (a['Code']?.toString() ?? '')
            .compareTo(b['Code']?.toString() ?? ''));
        // حفظ في الكاش
        AccountingCacheService.saveAccounts(_accounts);
      } else {
        _errorMessage = result['message'] ?? 'خطأ في جلب البيانات';
      }
    } catch (e) {
      _errorMessage = 'خطأ في الاتصال';
    }
    if (mounted) setState(() => _isLoading = false);
  }

  /// الحسابات النهائية فقط (IsLeaf) — المفلترة
  List<dynamic> get _filteredAccounts {
    var list = _accounts.where((a) => a['IsLeaf'] == true).toList();

    // فلتر النوع
    final typeEn = _typeLabels[_filterType];
    if (typeEn != null) {
      list = list
          .where((a) =>
              a['AccountType']?.toString() == typeEn ||
              a['Type']?.toString() == typeEn)
          .toList();
    }

    // فلتر البحث
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list.where((a) {
        final name = (a['Name'] ?? '').toString().toLowerCase();
        final code = (a['Code'] ?? '').toString().toLowerCase();
        return name.contains(q) || code.contains(q);
      }).toList();
    }

    return list;
  }

  double _balance(dynamic acc) =>
      ((acc['Balance'] ?? acc['CurrentBalance'] ?? 0) as num).toDouble();

  double get _totalDebit {
    double sum = 0;
    for (final a in _filteredAccounts) {
      final b = _balance(a);
      if (b > 0) sum += b;
    }
    return sum;
  }

  double get _totalCredit {
    double sum = 0;
    for (final a in _filteredAccounts) {
      final b = _balance(a);
      if (b < 0) sum += b.abs();
    }
    return sum;
  }

  double get _difference => (_totalDebit - _totalCredit).abs();

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
              _buildSummaryBar(ar),
              _buildFilterBar(ar),
              Expanded(
                child: _isLoading
                    ? const AccountingSkeleton(rows: 8, columns: 4)
                    : _errorMessage != null
                        ? AccountingTheme.errorView(_errorMessage!, _loadData)
                        : _buildTable(ar),
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
              gradient: AccountingTheme.neonBlueGradient,
              borderRadius: BorderRadius.circular(isMob ? 6 : 8),
            ),
            child: Icon(Icons.balance_rounded,
                color: Colors.white, size: isMob ? 16 : ar.iconM),
          ),
          SizedBox(width: isMob ? 6 : ar.spaceM),
          Text('ميزان المراجعة',
              style: GoogleFonts.cairo(
                fontSize: isMob ? 14 : ar.headingMedium,
                fontWeight: FontWeight.bold,
                color: AccountingTheme.textPrimary,
              )),
          const Spacer(),
          IconButton(
            onPressed: _isLoading
                ? null
                : () async {
                    try {
                      final path = await AccountingExportService.exportTrialBalance(
                          _filteredAccounts);
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
              await AccountingPdfExportService.exportTrialBalance(_filteredAccounts);
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

  Widget _buildSummaryBar(AccountingResponsive ar) {
    if (_isLoading) return const SizedBox.shrink();
    final isMob = ar.isMobile;
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: isMob ? 8 : ar.spaceXL, vertical: isMob ? 8 : ar.spaceM),
      color: AccountingTheme.bgCard,
      child: Row(
        children: [
          _summaryChip(
            'إجمالي مدين',
            _fmt.format(_totalDebit),
            AccountingTheme.debitText,
            AccountingTheme.debitFill,
            ar,
          ),
          SizedBox(width: isMob ? 6 : ar.spaceM),
          _summaryChip(
            'إجمالي دائن',
            _fmt.format(_totalCredit),
            AccountingTheme.creditText,
            AccountingTheme.creditFill,
            ar,
          ),
          SizedBox(width: isMob ? 6 : ar.spaceM),
          _summaryChip(
            'الفرق',
            _fmt.format(_difference),
            _isBalanced ? AccountingTheme.success : AccountingTheme.danger,
            _isBalanced
                ? AccountingTheme.success.withOpacity(0.1)
                : AccountingTheme.danger.withOpacity(0.1),
            ar,
          ),
          SizedBox(width: isMob ? 6 : ar.spaceM),
          Container(
            padding: EdgeInsets.symmetric(
                horizontal: isMob ? 8 : 12, vertical: isMob ? 4 : 6),
            decoration: BoxDecoration(
              color: _isBalanced
                  ? AccountingTheme.success.withOpacity(0.15)
                  : AccountingTheme.danger.withOpacity(0.15),
              borderRadius: BorderRadius.circular(ar.badgeRadius + 4),
              border: Border.all(
                color: _isBalanced
                    ? AccountingTheme.success
                    : AccountingTheme.danger,
                width: 1.5,
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
                  _isBalanced ? 'متوازن' : 'غير متوازن',
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
          const Spacer(),
          Text(
            '${_filteredAccounts.length} حساب',
            style: GoogleFonts.cairo(
                fontSize: isMob ? 10 : ar.small,
                color: AccountingTheme.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _summaryChip(String label, String value, Color textColor,
      Color bgColor, AccountingResponsive ar) {
    final isMob = ar.isMobile;
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: isMob ? 8 : 14, vertical: isMob ? 4 : 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(ar.cardRadius),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: GoogleFonts.cairo(
                  fontSize: isMob ? 8 : ar.caption,
                  color: AccountingTheme.textMuted)),
          Text(value,
              style: GoogleFonts.cairo(
                  fontSize: isMob ? 11 : ar.financialSmall,
                  fontWeight: FontWeight.bold,
                  color: textColor)),
        ],
      ),
    );
  }

  Widget _buildFilterBar(AccountingResponsive ar) {
    if (_isLoading) return const SizedBox.shrink();
    final isMob = ar.isMobile;
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: isMob ? 8 : ar.spaceXL, vertical: isMob ? 4 : ar.spaceS),
      decoration: const BoxDecoration(
        color: AccountingTheme.bgCard,
        border: Border(bottom: BorderSide(color: AccountingTheme.borderColor)),
      ),
      child: Row(
        children: [
          // بحث
          SizedBox(
            width: isMob ? 140 : ar.searchFieldW,
            height: isMob ? 30 : ar.searchBarH,
            child: TextField(
              onChanged: (v) => setState(() => _searchQuery = v),
              style: GoogleFonts.cairo(fontSize: isMob ? 11 : ar.inputText),
              decoration: InputDecoration(
                hintText: 'بحث بالاسم أو الكود...',
                hintStyle: GoogleFonts.cairo(
                    fontSize: isMob ? 10 : ar.hintText,
                    color: AccountingTheme.textMuted),
                prefixIcon: Icon(Icons.search, size: isMob ? 14 : 18),
                isDense: true,
                contentPadding: EdgeInsets.symmetric(
                    horizontal: 8, vertical: isMob ? 4 : 6),
                filled: true,
                fillColor: AccountingTheme.bgSecondary,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(ar.btnRadius),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          SizedBox(width: isMob ? 6 : ar.spaceM),
          // فلتر النوع
          ..._typeLabels.keys.map((label) {
            final isSelected = _filterType == label;
            return Padding(
              padding: EdgeInsets.only(left: isMob ? 2 : 4),
              child: InkWell(
                onTap: () => setState(() => _filterType = label),
                borderRadius: BorderRadius.circular(ar.badgeRadius + 4),
                child: Container(
                  padding: EdgeInsets.symmetric(
                      horizontal: isMob ? 6 : 10, vertical: isMob ? 3 : 5),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AccountingTheme.neonBlue.withOpacity(0.15)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(ar.badgeRadius + 4),
                    border: Border.all(
                      color: isSelected
                          ? AccountingTheme.neonBlue
                          : AccountingTheme.borderColor,
                    ),
                  ),
                  child: Text(label,
                      style: GoogleFonts.cairo(
                        fontSize: isMob ? 9 : ar.small,
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.normal,
                        color: isSelected
                            ? AccountingTheme.neonBlue
                            : AccountingTheme.textMuted,
                      )),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildTable(AccountingResponsive ar) {
    final accounts = _filteredAccounts;
    if (accounts.isEmpty) {
      return AccountingTheme.emptyState('لا توجد حسابات',
          icon: Icons.account_balance_wallet);
    }

    final isMob = ar.isMobile;
    return SingleChildScrollView(
      padding: EdgeInsets.all(isMob ? 8 : ar.spaceXL),
      child: Container(
        decoration: AccountingTheme.card,
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            // رأس الجدول
            Container(
              decoration: AccountingTheme.tableHeader,
              padding: EdgeInsets.symmetric(
                  horizontal: ar.tableCellPadH, vertical: ar.tableCellPadV + 2),
              child: Row(
                children: [
                  _headerCell('#', ar.colNumW, ar),
                  _headerCell('الكود', isMob ? 50 : 80, ar),
                  Expanded(child: _headerCell('اسم الحساب', null, ar)),
                  _headerCell('النوع', isMob ? 50 : 80, ar),
                  _headerCell('مدين', ar.colAmountW, ar, align: TextAlign.left),
                  _headerCell('دائن', ar.colAmountW, ar, align: TextAlign.left),
                ],
              ),
            ),
            // صفوف البيانات
            ...List.generate(accounts.length, (i) {
              final acc = accounts[i];
              final balance = _balance(acc);
              final isDebit = balance > 0;
              final type = acc['AccountType']?.toString() ??
                  acc['Type']?.toString() ??
                  '';
              final typeColor = _typeColors[type] ?? AccountingTheme.textMuted;

              return Container(
                color: i.isEven
                    ? Colors.transparent
                    : AccountingTheme.tableRowAlt,
                padding: EdgeInsets.symmetric(
                    horizontal: ar.tableCellPadH, vertical: ar.tableCellPadV),
                child: Row(
                  children: [
                    SizedBox(
                        width: ar.colNumW,
                        child: Text('${i + 1}',
                            style: GoogleFonts.cairo(
                                fontSize: ar.tableCellFont,
                                color: AccountingTheme.textMuted))),
                    SizedBox(
                        width: isMob ? 50 : 80,
                        child: Text(acc['Code']?.toString() ?? '',
                            style: GoogleFonts.cairo(
                                fontSize: ar.tableCellFont,
                                fontWeight: FontWeight.w600,
                                color: AccountingTheme.textPrimary))),
                    Expanded(
                        child: Text(acc['Name']?.toString() ?? '',
                            style: GoogleFonts.cairo(
                                fontSize: ar.tableCellFont,
                                color: AccountingTheme.textSecondary))),
                    SizedBox(
                      width: isMob ? 50 : 80,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: typeColor.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          _typeLabelsAr[type] ?? type,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.cairo(
                              fontSize: isMob ? 8 : ar.caption,
                              fontWeight: FontWeight.w600,
                              color: typeColor),
                        ),
                      ),
                    ),
                    // مدين
                    SizedBox(
                      width: ar.colAmountW,
                      child: Text(
                        isDebit ? _fmt.format(balance) : '',
                        textAlign: TextAlign.left,
                        style: GoogleFonts.cairo(
                            fontSize: ar.tableCellFont,
                            fontWeight: FontWeight.w600,
                            color: AccountingTheme.debitText),
                      ),
                    ),
                    // دائن
                    SizedBox(
                      width: ar.colAmountW,
                      child: Text(
                        !isDebit && balance != 0
                            ? _fmt.format(balance.abs())
                            : '',
                        textAlign: TextAlign.left,
                        style: GoogleFonts.cairo(
                            fontSize: ar.tableCellFont,
                            fontWeight: FontWeight.w600,
                            color: AccountingTheme.creditText),
                      ),
                    ),
                  ],
                ),
              );
            }),
            // صف الإجمالي
            Container(
              decoration: BoxDecoration(
                color: AccountingTheme.bgSidebar,
                borderRadius:
                    const BorderRadius.vertical(bottom: Radius.circular(10)),
              ),
              padding: EdgeInsets.symmetric(
                  horizontal: ar.tableCellPadH, vertical: ar.tableCellPadV + 4),
              child: Row(
                children: [
                  SizedBox(width: ar.colNumW),
                  SizedBox(width: isMob ? 50 : 80),
                  Expanded(
                      child: Text('الإجمالي',
                          style: GoogleFonts.cairo(
                              fontSize: ar.tableCellFont + 1,
                              fontWeight: FontWeight.bold,
                              color: Colors.white))),
                  SizedBox(width: isMob ? 50 : 80),
                  SizedBox(
                    width: ar.colAmountW,
                    child: Text(
                      _fmt.format(_totalDebit),
                      textAlign: TextAlign.left,
                      style: GoogleFonts.cairo(
                          fontSize: ar.tableCellFont + 1,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF82E0AA)),
                    ),
                  ),
                  SizedBox(
                    width: ar.colAmountW,
                    child: Text(
                      _fmt.format(_totalCredit),
                      textAlign: TextAlign.left,
                      style: GoogleFonts.cairo(
                          fontSize: ar.tableCellFont + 1,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFFF1948A)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _headerCell(String label, double? width, AccountingResponsive ar,
      {TextAlign align = TextAlign.start}) {
    final child = Text(label,
        textAlign: align,
        style: GoogleFonts.cairo(
          fontSize: ar.tableHeaderFont,
          fontWeight: FontWeight.bold,
          color: AccountingTheme.tableHeaderText,
        ));
    return width != null ? SizedBox(width: width, child: child) : child;
  }
}
