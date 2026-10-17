import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../../services/accounting_service.dart';
import '../../services/accounting_cache_service.dart';
import '../../services/accounting_export_service.dart';
import '../../services/accounting_pdf_export_service.dart';
import '../../theme/accounting_theme.dart';
import '../../theme/accounting_responsive.dart';
import '../../widgets/accounting_skeleton.dart';
import '../../frontend/frontend.dart';

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

  /// تحذيرات: حسابات بأرصدة معكوسة (أصول سالبة أو خصوم موجبة بشكل غير طبيعي)
  List<String> get _balanceWarnings {
    final warnings = <String>[];
    for (final a in _assets) {
      if (_balance(a) < -0.01) {
        warnings.add('${a['Name'] ?? a['Code']}: رصيد سالب (${_balance(a).toStringAsFixed(0)})');
      }
    }
    for (final a in _liabilities) {
      if (_balance(a) > 0.01) {
        warnings.add('${a['Name'] ?? a['Code']}: رصيد موجب غير طبيعي (${_balance(a).toStringAsFixed(0)})');
      }
    }
    return warnings;
  }

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
    return SdPage(
      scrollable: false,
      padding: EdgeInsets.zero,
      maxWidth: double.infinity,
      appBar: SdAppBar(
        title: 'الميزانية العمومية',
        actions: [
          SdAppBarAction(
            icon: Icons.file_download_outlined,
            label: 'تصدير Excel',
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
          ),
          SdAppBarAction(
            icon: Icons.picture_as_pdf,
            label: 'تصدير PDF',
            onPressed: _isLoading
                ? null
                : () async {
                    await AccountingPdfExportService.exportBalanceSheet(
                      assets: _assets,
                      liabilities: _liabilities,
                      equity: _equity,
                      totalAssets: _totalAssets,
                      totalLiabilities: _totalLiabilities,
                      totalEquity: _totalEquity,
                    );
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
          _buildStatusBar(ar),
          Expanded(
            child: _isLoading
                ? const AccountingSkeleton(rows: 8, columns: 4)
                : _errorMessage != null
                    ? AccountingTheme.errorView(_errorMessage!, _loadData)
                    : _buildContent(ar),
          ),
        ],
      ),
    );
  }

  /// شريط حالة التوازن (نُقل من شريط الأدوات القديم — نفس المنطق والقيم)
  Widget _buildStatusBar(AccountingResponsive ar) {
    final isMob = ar.isMobile;
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: isMob ? 8 : ar.spaceXL, vertical: isMob ? 6 : ar.spaceS),
      decoration: const BoxDecoration(
        color: SdColors.surface,
        border: Border(bottom: BorderSide(color: SdColors.divider)),
      ),
      child: Row(
        children: [
          // حالة التوازن
          Container(
            padding: EdgeInsets.symmetric(
                horizontal: isMob ? 8 : 12, vertical: isMob ? 4 : 6),
            decoration: BoxDecoration(
              color: _isBalanced
                  ? SdColors.success.withOpacity(0.15)
                  : SdColors.danger.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _isBalanced
                    ? SdColors.success
                    : SdColors.danger,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _isBalanced ? Icons.check_circle : Icons.warning_rounded,
                  size: isMob ? 14 : 18,
                  color: _isBalanced
                      ? SdColors.success
                      : SdColors.danger,
                ),
                const SizedBox(width: 4),
                Text(
                  _isBalanced ? 'متوازنة' : 'غير متوازنة',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: isMob ? 10 : ar.small,
                    fontWeight: FontWeight.bold,
                    color: _isBalanced
                        ? SdColors.success
                        : SdColors.danger,
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
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
                color: SdColors.primary,
                gradient: AccountingTheme.neonBlueGradient,
                accounts: _assets,
                total: _totalAssets,
                ar: ar,
              ),
              SizedBox(height: ar.spaceM),
              _buildSectionCard(
                title: 'الالتزامات',
                icon: Icons.receipt_long,
                color: SdColors.warning,
                gradient: AccountingTheme.neonOrangeGradient,
                accounts: _liabilities,
                total: _totalLiabilities,
                ar: ar,
              ),
              SizedBox(height: ar.spaceM),
              _buildSectionCard(
                title: 'حقوق الملكية',
                icon: Icons.business_center,
                color: SdColors.platformBase,
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
                    color: SdColors.primary,
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
                        color: SdColors.warning,
                        gradient: AccountingTheme.neonOrangeGradient,
                        accounts: _liabilities,
                        total: _totalLiabilities,
                        ar: ar,
                      ),
                      SizedBox(height: ar.spaceM),
                      _buildSectionCard(
                        title: 'حقوق الملكية',
                        icon: Icons.business_center,
                        color: SdColors.platformBase,
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
                          color: SdColors.primary,
                          borderRadius: BorderRadius.circular(ar.cardRadius),
                        ),
                        child: Row(
                          children: [
                            Text('إجمالي الالتزامات + حقوق الملكية',
                                style: TextStyle(
                                    fontFamily: 'Cairo',
                                    fontSize: ar.body,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white)),
                            const Spacer(),
                            Text(_fmt.format(_totalLiabilitiesAndEquity),
                                style: TextStyle(
                                    fontFamily: 'Cairo',
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
        color: SdColors.surface,
        borderRadius: BorderRadius.circular(ar.cardRadius + 4),
        boxShadow: AccountingTheme.cardShadow,
        border: Border.all(color: SdColors.divider),
      ),
      child: Column(
        children: [
          Text('المعادلة المحاسبية',
              style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: isMob ? 12 : ar.headingSmall,
                  fontWeight: FontWeight.bold,
                  color: SdColors.ink)),
          SizedBox(height: isMob ? 8 : 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _equationItem('الأصول', _totalAssets, SdColors.primary, ar),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: isMob ? 6 : 14),
                child: Text('=',
                    style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: isMob ? 18 : 24,
                        fontWeight: FontWeight.w900,
                        color: SdColors.ink)),
              ),
              _equationItem(
                  'الالتزامات', _totalLiabilities, SdColors.warning, ar),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: isMob ? 6 : 14),
                child: Text('+',
                    style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: isMob ? 18 : 24,
                        fontWeight: FontWeight.w900,
                        color: SdColors.ink)),
              ),
              _equationItem('حقوق الملكية', _totalEquity + _retainedEarnings,
                  SdColors.platformBase, ar),
            ],
          ),
          if (!_isBalanced) ...[
            SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: SdColors.danger.withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'فرق: ${_fmt.format(_difference)}',
                style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: isMob ? 10 : ar.small,
                    fontWeight: FontWeight.bold,
                    color: SdColors.danger),
              ),
            ),
          ],
          if (_balanceWarnings.isNotEmpty) ...[
            SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: SdColors.warning.withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: SdColors.warningTintEdge),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('تحذيرات أرصدة:', style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: isMob ? 10 : ar.small, fontWeight: FontWeight.bold, color: SdColors.warning)),
                  ..._balanceWarnings.map((w) => Text('• $w', style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: isMob ? 9 : ar.small - 1, color: SdColors.warning))),
                ],
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
            style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: isMob ? 9 : ar.small,
                color: SdColors.faint)),
        SizedBox(height: 2),
        Text(_fmt.format(value),
            style: TextStyle(
                fontFamily: 'Cairo',
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
                    style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: isMob ? 13 : ar.headingSmall,
                        fontWeight: FontWeight.bold,
                        color: SdColors.ink)),
                const Spacer(),
                Text(_fmt.format(grandTotal ?? total),
                    style: TextStyle(
                        fontFamily: 'Cairo',
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
                  style: TextStyle(fontFamily: 'Cairo', color: SdColors.faint)),
            )
          else
            ...List.generate(accounts.length, (i) {
              final acc = accounts[i];
              final balance = _balance(acc).abs();
              return Container(
                color: i.isEven
                    ? Colors.transparent
                    : SdColors.surfaceAlt,
                padding: EdgeInsets.symmetric(
                    horizontal: isMob ? 10 : ar.spaceL,
                    vertical: isMob ? 5 : ar.spaceXS),
                child: Row(
                  children: [
                    SizedBox(
                        width: isMob ? 40 : 60,
                        child: Text(acc['Code']?.toString() ?? '',
                            style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: ar.tableCellFont,
                                fontWeight: FontWeight.w600,
                                color: SdColors.faint))),
                    Expanded(
                        child: Text(acc['Name']?.toString() ?? '',
                            style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: ar.tableCellFont,
                                color: SdColors.muted))),
                    Text(_fmt.format(balance),
                        style: TextStyle(
                            fontFamily: 'Cairo',
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
                color: SdColors.success.withOpacity(0.06),
                border: Border(
                    top: BorderSide(
                        color: SdColors.success.withOpacity(0.2))),
              ),
              child: Row(
                children: [
                  SizedBox(width: isMob ? 40 : 60),
                  Icon(Icons.trending_up,
                      size: isMob ? 12 : 16,
                      color: extraRow.value >= 0
                          ? SdColors.success
                          : SdColors.danger),
                  SizedBox(width: 4),
                  Expanded(
                      child: Text(extraRow.label,
                          style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: ar.tableCellFont,
                              fontWeight: FontWeight.w600,
                              color: SdColors.muted))),
                  Text(_fmt.format(extraRow.value),
                      style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: ar.tableCellFont,
                          fontWeight: FontWeight.bold,
                          color: extraRow.value >= 0
                              ? SdColors.success
                              : SdColors.danger)),
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
                    style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: isMob ? 11 : ar.body,
                        fontWeight: FontWeight.bold,
                        color: SdColors.ink)),
                const Spacer(),
                Text(_fmt.format(grandTotal ?? total),
                    style: TextStyle(
                        fontFamily: 'Cairo',
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
