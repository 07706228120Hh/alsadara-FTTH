import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:fl_chart/fl_chart.dart';
import '../../theme/accounting_theme.dart';
import '../../theme/accounting_responsive.dart';
import '../../services/accounting_service.dart';
import '../../services/accounting_cache_service.dart';

/// صفحة النسب المالية - تحليل 7 نسب مالية أساسية مع رسم بياني
class FinancialRatiosPage extends StatefulWidget {
  final String? companyId;
  const FinancialRatiosPage({super.key, this.companyId});

  @override
  State<FinancialRatiosPage> createState() => _FinancialRatiosPageState();
}

class _FinancialRatiosPageState extends State<FinancialRatiosPage> {
  bool _isLoading = true;
  String? _errorMessage;
  Map<String, dynamic>? _dashboardData;
  List<dynamic> _accounts = [];

  final _numFmt = NumberFormat('#,##0.##', 'en');

  @override
  void initState() {
    super.initState();
    _loadAllData();
  }

  Future<void> _loadAllData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      // محاولة التحميل من الكاش أولاً
      final cachedAccounts = await AccountingCacheService.loadAccounts();

      late final Map<String, dynamic> dashResult;
      late final Map<String, dynamic> accountsResult;

      if (cachedAccounts != null) {
        // الحسابات موجودة في الكاش — جلب الداشبورد فقط
        final results = await Future.wait([
          AccountingService.instance.getDashboard(companyId: widget.companyId),
        ]);
        dashResult = results[0];
        accountsResult = {'success': true, 'data': cachedAccounts};
      } else {
        // لا يوجد كاش — جلب الكل بالتوازي
        final results = await Future.wait([
          AccountingService.instance.getDashboard(companyId: widget.companyId),
          AccountingService.instance.getAccounts(companyId: widget.companyId),
        ]);
        dashResult = results[0];
        accountsResult = results[1];
        // حفظ الحسابات في الكاش
        if (accountsResult['success'] == true) {
          final accountsList = (accountsResult['data'] as List?) ?? [];
          AccountingCacheService.saveAccounts(accountsList);
        }
      }

      if (!mounted) return;

      if (dashResult['success'] == true) {
        final data = dashResult['data'] is Map<String, dynamic>
            ? dashResult['data']
            : <String, dynamic>{};
        setState(() {
          _dashboardData = data;
          _accounts = accountsResult['success'] == true
              ? (accountsResult['data'] as List? ?? [])
              : [];
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage = dashResult['message'] ?? 'خطأ في جلب البيانات';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'خطأ في الاتصال';
        _isLoading = false;
      });
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // حساب النسب المالية
  // ═══════════════════════════════════════════════════════════════

  double _sumByType(String type) {
    return _accounts
        .where(
            (a) => (a['AccountType'] ?? a['Type'])?.toString() == type)
        .fold(
            0.0,
            (sum, a) =>
                sum +
                ((a['CurrentBalance'] ?? a['Balance'] ?? 0) as num)
                    .toDouble()
                    .abs());
  }

  List<_RatioData> _calculateRatios() {
    final totalAssets = _sumByType('Assets');
    final totalLiabilities = _sumByType('Liabilities');
    final totalEquity = _sumByType('Equity');
    final totalRevenue = _sumByType('Revenue');
    final totalExpenses = _sumByType('Expenses');
    final netIncome = totalRevenue - totalExpenses;

    // Cash balance from dashboard AccountBalances.CashRegisterBalance
    double cashBalance = 0;
    if (_dashboardData != null) {
      final balances =
          _dashboardData!['AccountBalances'] as Map<String, dynamic>? ?? {};
      cashBalance =
          ((balances['CashRegisterBalance'] ?? 0) as num).toDouble().abs();
    }
    // Fallback: look for account 11101 in accounts list
    if (cashBalance == 0) {
      for (final acct in _accounts) {
        if (acct is Map && acct['Code']?.toString() == '11101') {
          cashBalance =
              ((acct['CurrentBalance'] ?? acct['Balance'] ?? 0) as num)
                  .toDouble()
                  .abs();
          break;
        }
      }
    }

    // 1. نسبة التداول (Current Ratio)
    final currentRatio =
        totalLiabilities > 0 ? totalAssets / totalLiabilities : 0.0;

    // 2. نسبة المديونية (Debt Ratio)
    final debtRatio =
        totalAssets > 0 ? totalLiabilities / totalAssets : 0.0;

    // 3. هامش صافي الربح (Net Profit Margin)
    final profitMargin =
        totalRevenue > 0 ? netIncome / totalRevenue * 100 : 0.0;

    // 4. نسبة النقدية (Cash Ratio)
    final cashRatio =
        totalLiabilities > 0 ? cashBalance / totalLiabilities : 0.0;

    // 5. نسبة حقوق الملكية (Equity Ratio)
    final equityRatio =
        totalAssets > 0 ? totalEquity / totalAssets * 100 : 0.0;

    // 6. نسبة المصاريف التشغيلية (Operating Expense Ratio)
    final expenseRatio =
        totalRevenue > 0 ? totalExpenses / totalRevenue * 100 : 0.0;

    // 7. العائد على الأصول (ROA)
    final roa = totalAssets > 0 ? netIncome / totalAssets * 100 : 0.0;

    return [
      _RatioData(
        name: 'نسبة التداول',
        englishName: 'Current Ratio',
        value: currentRatio,
        formatted: _numFmt.format(currentRatio),
        suffix: '',
        description: 'الأصول / الالتزامات — قدرة الشركة على سداد التزاماتها',
        statusColor: _statusCurrentRatio(currentRatio),
      ),
      _RatioData(
        name: 'نسبة المديونية',
        englishName: 'Debt Ratio',
        value: debtRatio,
        formatted: _numFmt.format(debtRatio),
        suffix: '',
        description: 'الالتزامات / الأصول — مستوى الاعتماد على الديون',
        statusColor: _statusDebtRatio(debtRatio),
      ),
      _RatioData(
        name: 'هامش صافي الربح',
        englishName: 'Net Profit Margin',
        value: profitMargin,
        formatted: '${_numFmt.format(profitMargin)}%',
        suffix: '%',
        description: 'صافي الدخل / الإيرادات — كفاءة تحقيق الأرباح',
        statusColor: _statusProfitMargin(profitMargin),
      ),
      _RatioData(
        name: 'نسبة النقدية',
        englishName: 'Cash Ratio',
        value: cashRatio,
        formatted: _numFmt.format(cashRatio),
        suffix: '',
        description: 'النقد / الالتزامات — القدرة على السداد الفوري',
        statusColor: _statusCashRatio(cashRatio),
      ),
      _RatioData(
        name: 'نسبة حقوق الملكية',
        englishName: 'Equity Ratio',
        value: equityRatio,
        formatted: '${_numFmt.format(equityRatio)}%',
        suffix: '%',
        description: 'حقوق الملكية / الأصول — نسبة التمويل الذاتي',
        statusColor: _statusEquityRatio(equityRatio),
      ),
      _RatioData(
        name: 'نسبة المصاريف التشغيلية',
        englishName: 'Operating Expense Ratio',
        value: expenseRatio,
        formatted: '${_numFmt.format(expenseRatio)}%',
        suffix: '%',
        description: 'المصاريف / الإيرادات — كفاءة التحكم بالتكاليف',
        statusColor: _statusExpenseRatio(expenseRatio),
      ),
      _RatioData(
        name: 'العائد على الأصول',
        englishName: 'ROA',
        value: roa,
        formatted: '${_numFmt.format(roa)}%',
        suffix: '%',
        description: 'صافي الدخل / الأصول — فعالية استخدام الأصول',
        statusColor: _statusROA(roa),
      ),
    ];
  }

  // ═══════════════════════════════════════════════════════════════
  // ألوان الحالة لكل نسبة
  // ═══════════════════════════════════════════════════════════════

  Color _statusCurrentRatio(double v) {
    if (v >= 1.5) return AccountingTheme.success;
    if (v >= 1.0) return AccountingTheme.warning;
    return AccountingTheme.danger;
  }

  Color _statusDebtRatio(double v) {
    if (v <= 0.4) return AccountingTheme.success;
    if (v <= 0.6) return AccountingTheme.warning;
    return AccountingTheme.danger;
  }

  Color _statusProfitMargin(double v) {
    if (v >= 20) return AccountingTheme.success;
    if (v >= 10) return AccountingTheme.warning;
    return AccountingTheme.danger;
  }

  Color _statusCashRatio(double v) {
    if (v >= 0.5) return AccountingTheme.success;
    if (v >= 0.2) return AccountingTheme.warning;
    return AccountingTheme.danger;
  }

  Color _statusEquityRatio(double v) {
    if (v >= 50) return AccountingTheme.success;
    if (v >= 30) return AccountingTheme.warning;
    return AccountingTheme.danger;
  }

  Color _statusExpenseRatio(double v) {
    if (v <= 70) return AccountingTheme.success;
    if (v <= 85) return AccountingTheme.warning;
    return AccountingTheme.danger;
  }

  Color _statusROA(double v) {
    if (v >= 10) return AccountingTheme.success;
    if (v >= 5) return AccountingTheme.warning;
    return AccountingTheme.danger;
  }

  // ═══════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════

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
              Expanded(
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(
                            color: AccountingTheme.neonBlue))
                    : _errorMessage != null
                        ? AccountingTheme.errorView(
                            _errorMessage!, _loadAllData)
                        : _buildContent(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ══════════════════════ TOOLBAR ══════════════════════

  Widget _buildToolbar() {
    final isMobile = context.accR.isMobile;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 8 : context.accR.paddingH,
        vertical: isMobile ? 4 : context.accR.spaceS,
      ),
      decoration: AccountingTheme.toolbar,
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: Icon(Icons.arrow_forward_rounded,
                size: isMobile ? 20 : context.accR.iconM),
            tooltip: 'رجوع',
            style: IconButton.styleFrom(foregroundColor: Colors.white70),
          ),
          SizedBox(width: context.accR.spaceXS),
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              gradient: AccountingTheme.neonPurpleGradient,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.analytics_rounded,
                color: Colors.white, size: isMobile ? 16 : context.accR.iconM),
          ),
          SizedBox(width: context.accR.spaceS),
          Expanded(
            child: Text(
              isMobile ? 'النسب المالية' : 'النسب المالية',
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.cairo(
                fontSize: isMobile ? 14 : context.accR.headingSmall,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
          IconButton(
            onPressed: _loadAllData,
            icon:
                Icon(Icons.refresh, size: isMobile ? 18 : context.accR.iconM),
            tooltip: 'تحديث',
            style: IconButton.styleFrom(foregroundColor: Colors.white70),
          ),
        ],
      ),
    );
  }

  // ══════════════════════ CONTENT ══════════════════════

  Widget _buildContent() {
    final ratios = _calculateRatios();
    final isMobile = context.accR.isMobile;
    final crossAxisCount = isMobile ? 2 : 4;

    return SingleChildScrollView(
      padding: context.accR.contentPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: context.accR.spaceM),
          // شبكة بطاقات النسب
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              crossAxisSpacing: context.accR.spaceM,
              mainAxisSpacing: context.accR.spaceM,
              childAspectRatio: isMobile ? 1.1 : 1.4,
            ),
            itemCount: ratios.length,
            itemBuilder: (context, index) => _buildRatioCard(ratios[index]),
          ),
          SizedBox(height: context.accR.spaceXL),
          // الرسم البياني
          _buildBarChart(ratios),
          SizedBox(height: context.accR.spaceXL),
        ],
      ),
    );
  }

  // ══════════════════════ RATIO CARD ══════════════════════

  Widget _buildRatioCard(_RatioData ratio) {
    final isMobile = context.accR.isMobile;
    return Container(
      padding: EdgeInsets.all(context.accR.spaceL),
      decoration: BoxDecoration(
        color: AccountingTheme.bgCard,
        borderRadius: BorderRadius.circular(AccountingTheme.radiusMedium),
        boxShadow: AccountingTheme.cardShadow,
        border: Border(
          right: BorderSide(color: ratio.statusColor, width: 4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // الاسم العربي
          Text(
            ratio.name,
            style: GoogleFonts.cairo(
              fontSize: isMobile ? 11 : context.accR.body,
              fontWeight: FontWeight.bold,
              color: AccountingTheme.textPrimary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          SizedBox(height: context.accR.spaceXS),
          // الاسم الإنجليزي
          Text(
            ratio.englishName,
            style: GoogleFonts.cairo(
              fontSize: isMobile ? 9 : context.accR.caption,
              color: AccountingTheme.textMuted,
            ),
          ),
          const Spacer(),
          // القيمة الكبيرة
          Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                ratio.formatted,
                style: GoogleFonts.cairo(
                  fontSize: isMobile ? 22 : context.accR.financialLarge,
                  fontWeight: FontWeight.w800,
                  color: ratio.statusColor,
                ),
              ),
            ),
          ),
          const Spacer(),
          // مؤشر الحالة
          Row(
            children: [
              Container(
                width: context.accR.statusDotSize,
                height: context.accR.statusDotSize,
                decoration: BoxDecoration(
                  color: ratio.statusColor,
                  shape: BoxShape.circle,
                ),
              ),
              SizedBox(width: context.accR.spaceXS),
              Expanded(
                child: Text(
                  _statusLabel(ratio.statusColor),
                  style: GoogleFonts.cairo(
                    fontSize: isMobile ? 9 : context.accR.caption,
                    color: ratio.statusColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: context.accR.spaceXS),
          // الوصف
          Text(
            ratio.description,
            style: GoogleFonts.cairo(
              fontSize: isMobile ? 8 : context.accR.caption,
              color: AccountingTheme.textMuted,
              height: 1.3,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  String _statusLabel(Color color) {
    if (color == AccountingTheme.success) return 'جيد';
    if (color == AccountingTheme.warning) return 'تحذير';
    return 'خطر';
  }

  // ══════════════════════ BAR CHART ══════════════════════

  Widget _buildBarChart(List<_RatioData> ratios) {
    final isMobile = context.accR.isMobile;

    // Normalize values for chart display
    // Ratios (currentRatio, debtRatio, cashRatio) stay as-is
    // Percentages are already 0-100 scale
    final normalizedValues = ratios.map((r) {
      // For non-percentage ratios, multiply by 100 for visual comparison
      if (r.suffix.isEmpty) {
        return r.value * 100;
      }
      return r.value;
    }).toList();

    final maxVal = normalizedValues.fold<double>(
        1, (m, v) => v.abs() > m ? v.abs() : m);

    return Container(
      padding: EdgeInsets.all(context.accR.spaceL),
      decoration: BoxDecoration(
        color: AccountingTheme.bgCard,
        borderRadius: BorderRadius.circular(AccountingTheme.radiusMedium),
        boxShadow: AccountingTheme.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'مقارنة النسب المالية',
            style: GoogleFonts.cairo(
              fontSize: isMobile ? 13 : context.accR.headingSmall,
              fontWeight: FontWeight.bold,
              color: AccountingTheme.textPrimary,
            ),
          ),
          SizedBox(height: context.accR.spaceL),
          SizedBox(
            height: isMobile ? 280 : 350,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: maxVal * 1.15,
                minY: normalizedValues.any((v) => v < 0) ? -maxVal * 0.3 : 0,
                barTouchData: BarTouchData(
                  enabled: true,
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (_) => AccountingTheme.bgSidebar,
                    tooltipRoundedRadius: 8,
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      final ratio = ratios[group.x];
                      return BarTooltipItem(
                        '${ratio.name}\n${ratio.formatted}',
                        GoogleFonts.cairo(
                          color: Colors.white,
                          fontSize: isMobile ? 10 : 12,
                          fontWeight: FontWeight.w600,
                        ),
                      );
                    },
                  ),
                ),
                titlesData: FlTitlesData(
                  show: true,
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: isMobile ? 35 : 45,
                      getTitlesWidget: (value, meta) {
                        return Text(
                          _numFmt.format(value),
                          style: GoogleFonts.cairo(
                            fontSize: isMobile ? 8 : 10,
                            color: AccountingTheme.textMuted,
                          ),
                        );
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: isMobile ? 50 : 60,
                      getTitlesWidget: (value, meta) {
                        final index = value.toInt();
                        if (index < 0 || index >= ratios.length) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: RotatedBox(
                            quarterTurns: 1,
                            child: Text(
                              ratios[index].name,
                              style: GoogleFonts.cairo(
                                fontSize: isMobile ? 8 : 10,
                                color: AccountingTheme.textSecondary,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: maxVal / 4,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: AccountingTheme.borderColor,
                    strokeWidth: 0.8,
                  ),
                ),
                barGroups: List.generate(ratios.length, (i) {
                  return BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: normalizedValues[i],
                        color: ratios[i].statusColor,
                        width: isMobile ? 16 : 24,
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(6)),
                        backDrawRodData: BackgroundBarChartRodData(
                          show: true,
                          toY: maxVal * 1.1,
                          color: AccountingTheme.bgSecondary,
                        ),
                      ),
                    ],
                  );
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// نموذج بيانات النسبة المالية
// ═══════════════════════════════════════════════════════════════

class _RatioData {
  final String name;
  final String englishName;
  final double value;
  final String formatted;
  final String suffix;
  final String description;
  final Color statusColor;

  const _RatioData({
    required this.name,
    required this.englishName,
    required this.value,
    required this.formatted,
    required this.suffix,
    required this.description,
    required this.statusColor,
  });
}
