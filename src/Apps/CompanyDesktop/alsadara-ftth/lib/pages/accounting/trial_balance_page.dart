import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../../services/accounting_service.dart';
import '../../services/accounting_cache_service.dart';
import '../../services/accounting_export_service.dart';
import '../../services/accounting_pdf_export_service.dart';
import '../../theme/accounting_responsive.dart';
import '../../widgets/accounting_skeleton.dart';
import '../../frontend/frontend.dart';

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
  String _filterType =
      'الكل'; // الكل، أصول، التزامات، حقوق ملكية، إيرادات، مصروفات

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
    'Assets': SdColors.primary,
    'Liabilities': SdColors.warning,
    'Equity': SdColors.platformBase,
    'Revenue': SdColors.success,
    'Expenses': SdColors.danger,
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

  bool _isNaturalDebit(dynamic a) {
    final type = (a['AccountType'] ?? a['Type'] ?? '').toString();
    // Assets=0, Expenses=4 → طبيعة مدينة | Liabilities=1, Equity=2, Revenue=3 → طبيعة دائنة
    return type == '0' ||
        type == '4' ||
        type.toLowerCase() == 'assets' ||
        type.toLowerCase() == 'expenses';
  }

  double get _totalDebit {
    double sum = 0;
    for (final a in _filteredAccounts) {
      final b = _balance(a);
      if (_isNaturalDebit(a)) {
        sum += b.abs(); // حسابات مدينة بطبيعتها
      } else if (b > 0) {
        sum += b; // حساب دائن برصيد مدين (عكسي)
      }
    }
    return sum;
  }

  double get _totalCredit {
    double sum = 0;
    for (final a in _filteredAccounts) {
      final b = _balance(a);
      if (!_isNaturalDebit(a)) {
        sum += b.abs(); // حسابات دائنة بطبيعتها
      } else if (b < 0) {
        sum += b.abs(); // حساب مدين برصيد دائن (عكسي)
      }
    }
    return sum;
  }

  double get _difference => (_totalDebit - _totalCredit).abs();

  bool get _isBalanced => _difference < 0.01;

  @override
  Widget build(BuildContext context) {
    final ar = context.accR;
    return SdPage(
      scrollable: false,
      padding: EdgeInsets.zero,
      maxWidth: double.infinity,
      appBar: SdAppBar(
        title: 'ميزان المراجعة',
        actions: [
          SdAppBarAction(
            icon: Icons.file_download_outlined,
            label: 'تصدير Excel',
            onPressed: _isLoading
                ? null
                : () async {
                    try {
                      final path =
                          await AccountingExportService.exportTrialBalance(
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
          ),
          SdAppBarAction(
            icon: Icons.picture_as_pdf,
            label: 'تصدير PDF',
            onPressed: _isLoading
                ? null
                : () async {
                    await AccountingPdfExportService.exportTrialBalance(
                        _filteredAccounts);
                  },
          ),
          SdAppBarAction(
            icon: Icons.refresh_rounded,
            label: 'تحديث',
            onPressed: _loadData,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildSummaryBar(ar),
          _buildFilterBar(ar),
          Expanded(
            child: _isLoading
                ? const AccountingSkeleton(rows: 8, columns: 4)
                : _errorMessage != null
                    ? SdUiKit.errorView(_errorMessage!, _loadData)
                    : _buildTable(ar),
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
      color: SdColors.surface,
      child: Row(
        children: [
          _summaryChip(
            'إجمالي مدين',
            _fmt.format(_totalDebit),
            SdColors.success,
            SdColors.successTint,
            ar,
          ),
          SizedBox(width: isMob ? 6 : ar.spaceM),
          _summaryChip(
            'إجمالي دائن',
            _fmt.format(_totalCredit),
            SdColors.danger,
            SdColors.dangerTint,
            ar,
          ),
          SizedBox(width: isMob ? 6 : ar.spaceM),
          _summaryChip(
            'الفرق',
            _fmt.format(_difference),
            _isBalanced ? SdColors.success : SdColors.danger,
            _isBalanced
                ? SdColors.success.withOpacity(0.1)
                : SdColors.danger.withOpacity(0.1),
            ar,
          ),
          SizedBox(width: isMob ? 6 : ar.spaceM),
          Container(
            padding: EdgeInsets.symmetric(
                horizontal: isMob ? 8 : 12, vertical: isMob ? 4 : 6),
            decoration: BoxDecoration(
              color: _isBalanced
                  ? SdColors.success.withOpacity(0.15)
                  : SdColors.danger.withOpacity(0.15),
              borderRadius: BorderRadius.circular(ar.badgeRadius + 4),
              border: Border.all(
                color: _isBalanced ? SdColors.success : SdColors.danger,
                width: 1.5,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _isBalanced ? Icons.check_circle : Icons.warning_rounded,
                  size: isMob ? 14 : 18,
                  color: _isBalanced ? SdColors.success : SdColors.danger,
                ),
                SizedBox(width: 4),
                Text(
                  _isBalanced ? 'متوازن' : 'غير متوازن',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: isMob ? 10 : ar.small,
                    fontWeight: FontWeight.bold,
                    color: _isBalanced ? SdColors.success : SdColors.danger,
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          Text(
            '${_filteredAccounts.length} حساب',
            style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: isMob ? 10 : ar.small,
                color: SdColors.faint),
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
              style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: isMob ? 8 : ar.caption,
                  color: SdColors.faint)),
          Text(value,
              style: TextStyle(
                  fontFamily: 'Cairo',
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
        color: SdColors.surface,
        border: Border(bottom: BorderSide(color: SdColors.divider)),
      ),
      child: Row(
        children: [
          // بحث
          SizedBox(
            width: isMob ? 140 : ar.searchFieldW,
            height: isMob ? 30 : ar.searchBarH,
            child: TextField(
              onChanged: (v) => setState(() => _searchQuery = v),
              style: TextStyle(
                  fontFamily: 'Cairo', fontSize: isMob ? 11 : ar.inputText),
              decoration: InputDecoration(
                hintText: 'بحث بالاسم أو الكود...',
                hintStyle: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: isMob ? 10 : ar.hintText,
                    color: SdColors.faint),
                prefixIcon: Icon(Icons.search, size: isMob ? 14 : 18),
                isDense: true,
                contentPadding: EdgeInsets.symmetric(
                    horizontal: 8, vertical: isMob ? 4 : 6),
                filled: true,
                fillColor: SdColors.groundAlt,
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
                        ? SdColors.primary.withOpacity(0.15)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(ar.badgeRadius + 4),
                    border: Border.all(
                      color: isSelected ? SdColors.primary : SdColors.divider,
                    ),
                  ),
                  child: Text(label,
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: isMob ? 9 : ar.small,
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.normal,
                        color: isSelected ? SdColors.primary : SdColors.faint,
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
      return SdUiKit.emptyState('لا توجد حسابات',
          icon: Icons.account_balance_wallet);
    }

    final isMob = ar.isMobile;
    return SingleChildScrollView(
      padding: EdgeInsets.all(isMob ? 8 : ar.spaceXL),
      child: Container(
        decoration: SdUiKit.card,
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            // رأس الجدول
            Container(
              decoration: SdUiKit.tableHeader,
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
              final typeColor = _typeColors[type] ?? SdColors.faint;

              return Container(
                color: i.isEven ? Colors.transparent : SdColors.surfaceAlt,
                padding: EdgeInsets.symmetric(
                    horizontal: ar.tableCellPadH, vertical: ar.tableCellPadV),
                child: Row(
                  children: [
                    SizedBox(
                        width: ar.colNumW,
                        child: Text('${i + 1}',
                            style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: ar.tableCellFont,
                                color: SdColors.faint))),
                    SizedBox(
                        width: isMob ? 50 : 80,
                        child: Text(acc['Code']?.toString() ?? '',
                            style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: ar.tableCellFont,
                                fontWeight: FontWeight.w600,
                                color: SdColors.ink))),
                    Expanded(
                        child: Text(acc['Name']?.toString() ?? '',
                            style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: ar.tableCellFont,
                                color: SdColors.muted))),
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
                          style: TextStyle(
                              fontFamily: 'Cairo',
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
                        style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: ar.tableCellFont,
                            fontWeight: FontWeight.w600,
                            color: SdColors.success),
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
                        style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: ar.tableCellFont,
                            fontWeight: FontWeight.w600,
                            color: SdColors.danger),
                      ),
                    ),
                  ],
                ),
              );
            }),
            // صف الإجمالي
            Container(
              decoration: BoxDecoration(
                color: SdColors.primary,
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
                          style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: ar.tableCellFont + 1,
                              fontWeight: FontWeight.bold,
                              color: Colors.white))),
                  SizedBox(width: isMob ? 50 : 80),
                  SizedBox(
                    width: ar.colAmountW,
                    child: Text(
                      _fmt.format(_totalDebit),
                      textAlign: TextAlign.left,
                      style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: ar.tableCellFont + 1,
                          fontWeight: FontWeight.bold,
                          color: SdColors.fieldLight),
                    ),
                  ),
                  SizedBox(
                    width: ar.colAmountW,
                    child: Text(
                      _fmt.format(_totalCredit),
                      textAlign: TextAlign.left,
                      style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: ar.tableCellFont + 1,
                          fontWeight: FontWeight.bold,
                          color: SdColors.dangerLight),
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
        style: TextStyle(
          fontFamily: 'Cairo',
          fontSize: ar.tableHeaderFont,
          fontWeight: FontWeight.bold,
          color: SdColors.surface,
        ));
    return width != null ? SizedBox(width: width, child: child) : child;
  }
}
