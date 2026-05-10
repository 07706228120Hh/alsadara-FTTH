import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/accounting_responsive.dart';
import '../../theme/accounting_theme.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../services/accounting_service.dart';
import '../../services/accounting_cache_service.dart';
import 'chart_of_accounts_page.dart';

/// صفحة الإحصائيات - داشبورد محاسبي بمخططات بيانية (شاشة واحدة بدون تمرير)
class StatisticsPage extends StatefulWidget {
  final String? companyId;
  const StatisticsPage({super.key, this.companyId});

  @override
  State<StatisticsPage> createState() => _StatisticsPageState();
}

class _StatisticsPageState extends State<StatisticsPage> {
  bool _isLoading = true;
  String? _errorMessage;
  Map<String, dynamic>? _dashboardData;
  Map<String, dynamic>? _fundsData;
  List<dynamic>? _accountsList;

  @override
  void initState() {
    super.initState();
    _loadAllData();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _loadAllData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final cachedAccounts = await AccountingCacheService.loadAccounts();

      late final Map<String, dynamic> dashResult;
      late final Map<String, dynamic> accountsResult;
      late final Map<String, dynamic> fundsResult;

      if (cachedAccounts != null) {
        final results = await Future.wait([
          AccountingService.instance.getDashboard(companyId: widget.companyId),
          AccountingService.instance
              .getFundsOverview(companyId: widget.companyId),
        ]);
        dashResult = results[0];
        accountsResult = {'success': true, 'data': cachedAccounts};
        fundsResult = results[1];
      } else {
        final results = await Future.wait([
          AccountingService.instance.getDashboard(companyId: widget.companyId),
          AccountingService.instance.getAccounts(companyId: widget.companyId),
          AccountingService.instance
              .getFundsOverview(companyId: widget.companyId),
        ]);
        dashResult = results[0];
        accountsResult = results[1];
        fundsResult = results[2];
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
        final balances =
            data['AccountBalances'] as Map<String, dynamic>? ?? {};
        if (balances['CashRegisterBalance'] == null &&
            accountsResult['success'] == true) {
          final accounts = accountsResult['data'] as List? ?? [];
          for (final acct in accounts) {
            if (acct is Map && acct['Code']?.toString() == '11101') {
              balances['CashRegisterBalance'] = acct['CurrentBalance'] ?? 0;
              break;
            }
          }
          data['AccountBalances'] = balances;
        }
        setState(() {
          _dashboardData = data;
          _accountsList = accountsResult['success'] == true
              ? (accountsResult['data'] as List? ?? [])
              : [];
          _fundsData = fundsResult['success'] == true
              ? (fundsResult['data'] is Map<String, dynamic>
                  ? fundsResult['data']
                  : {})
              : {};
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
                        ? _buildErrorView()
                        : _buildDashboard(),
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
          vertical: isMobile ? 4 : context.accR.spaceS),
      decoration: AccountingTheme.toolbar,
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: Icon(Icons.arrow_forward_rounded,
                size: isMobile ? 20 : context.accR.iconM),
            tooltip: 'رجوع',
            style: IconButton.styleFrom(
                foregroundColor: AccountingTheme.textOnDarkSecondary),
          ),
          SizedBox(width: context.accR.spaceXS),
          Icon(Icons.dashboard_rounded,
              color: AccountingTheme.textOnDarkSecondary,
              size: isMobile ? 16 : context.accR.iconM),
          SizedBox(width: context.accR.spaceS),
          Expanded(
            child: Text(
                isMobile ? 'الإحصائيات' : 'لوحة الإحصائيات المالية',
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.cairo(
                    fontSize: isMobile ? 14 : context.accR.headingSmall,
                    fontWeight: FontWeight.bold,
                    color: AccountingTheme.textOnDark)),
          ),
          if (!isMobile)
            _toolbarBtn(Icons.account_tree_rounded, 'شجرة الحسابات', () {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) =>
                    ChartOfAccountsPage(companyId: widget.companyId),
              ));
            }),
          SizedBox(width: context.accR.spaceXS),
          IconButton(
            onPressed: _loadAllData,
            icon:
                Icon(Icons.refresh, size: isMobile ? 18 : context.accR.iconM),
            tooltip: 'تحديث',
            style: IconButton.styleFrom(
                foregroundColor: AccountingTheme.textOnDarkSecondary),
          ),
        ],
      ),
    );
  }

  Widget _toolbarBtn(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: EdgeInsets.symmetric(
            horizontal: context.accR.spaceM, vertical: context.accR.spaceXS),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white24),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                color: AccountingTheme.textOnDarkSecondary,
                size: context.accR.iconXS),
            SizedBox(width: context.accR.spaceXS),
            Text(label,
                style: GoogleFonts.cairo(
                    fontSize: context.accR.small,
                    color: AccountingTheme.textOnDarkSecondary)),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorView() {
    return AccountingTheme.errorView(_errorMessage!, _loadAllData);
  }

  // ══════════════════════ DASHBOARD BODY ══════════════════════

  Widget _buildDashboard() {
    final data = _dashboardData ?? {};
    final collections = data['Collections'] as Map<String, dynamic>? ?? {};
    final expenses = data['Expenses'] as Map<String, dynamic>? ?? {};
    final salaries = data['Salaries'] as Map<String, dynamic>? ?? {};
    final balances = data['AccountBalances'] as Map<String, dynamic>? ?? {};
    final pending = data['PendingDetails'] as Map<String, dynamic>? ?? {};
    final journal = data['JournalEntries'] as Map<String, dynamic>? ?? {};
    final funds = _fundsData ?? {};
    final cashBoxes = funds['CashBoxes'] as List? ?? [];

    final agentNet = (pending['AgentNet'] ?? 0) as num;
    final techNet = (pending['TechnicianNet'] ?? 0) as num;

    return Padding(
      padding: EdgeInsets.all(context.accR.spaceM),
      child: context.accR.isMobile
          ? _buildMobileLayout(collections, expenses, salaries, balances,
              pending, journal, cashBoxes, agentNet, techNet, data)
          : _buildDesktopLayout(collections, expenses, salaries, balances,
              pending, journal, cashBoxes, agentNet, techNet, data),
    );
  }

  Widget _buildMobileLayout(
    Map<String, dynamic> collections,
    Map<String, dynamic> expenses,
    Map<String, dynamic> salaries,
    Map<String, dynamic> balances,
    Map<String, dynamic> pending,
    Map<String, dynamic> journal,
    List<dynamic> cashBoxes,
    num agentNet,
    num techNet,
    Map<String, dynamic> data,
  ) {
    return SingleChildScrollView(
      child: Column(
        children: [
          GridView.count(
            crossAxisCount: 2,
            childAspectRatio: 2.4,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: _buildKpiList(balances),
          ),
          SizedBox(height: context.accR.spaceS),
          SizedBox(
              height: 280,
              child: _chartPanel('الميزانية العمومية', Icons.pie_chart_rounded,
                  AccountingTheme.neonPurple, _buildBalanceSheetChart(balances))),
          SizedBox(height: context.accR.spaceS),
          SizedBox(
              height: 300,
              child: _chartPanel(
                  'الإيرادات vs المصروفات',
                  Icons.bar_chart_rounded,
                  AccountingTheme.neonBlue,
                  _buildRevenueExpenseChart(balances, collections, expenses))),
          SizedBox(height: context.accR.spaceS),
          SizedBox(
              height: 300,
              child: _chartPanel(
                  'إحصائيات الشهر',
                  Icons.calendar_month_rounded,
                  AccountingTheme.neonOrange,
                  _buildMonthlyChart(collections, expenses, salaries, data))),
          SizedBox(height: context.accR.spaceS),
          SizedBox(
              height: 240,
              child: _chartPanel(
                  'المعلقات والذمم',
                  Icons.pending_actions_rounded,
                  AccountingTheme.neonPurple,
                  _buildPendingChart(
                      collections, salaries, agentNet, techNet))),
          SizedBox(height: context.accR.spaceS),
          SizedBox(
              height: 260,
              child: _chartPanel(
                  'الإجماليات الكلية',
                  Icons.analytics_rounded,
                  AccountingTheme.neonBlue,
                  _buildTotalsView(collections, expenses, salaries, journal))),
          SizedBox(height: context.accR.spaceS),
          SizedBox(
              height: 220,
              child: _chartPanel(
                  'الصناديق النقدية',
                  Icons.account_balance_wallet_rounded,
                  AccountingTheme.neonOrange,
                  _buildCashBoxesList(cashBoxes, balances))),
        ],
      ),
    );
  }

  Widget _buildDesktopLayout(
    Map<String, dynamic> collections,
    Map<String, dynamic> expenses,
    Map<String, dynamic> salaries,
    Map<String, dynamic> balances,
    Map<String, dynamic> pending,
    Map<String, dynamic> journal,
    List<dynamic> cashBoxes,
    num agentNet,
    num techNet,
    Map<String, dynamic> data,
  ) {
    return Column(
      children: [
        // KPI row
        SizedBox(
          height: 72,
          child: Row(
              children: _buildKpiList(balances)
                  .expand((w) => [w, SizedBox(width: context.accR.spaceS)])
                  .toList()
                ..removeLast()),
        ),
        SizedBox(height: context.accR.spaceS),
        // Charts row (top)
        Expanded(
          flex: 5,
          child: Row(
            children: [
              Expanded(
                  flex: 3,
                  child: _chartPanel(
                      'الميزانية العمومية',
                      Icons.pie_chart_rounded,
                      AccountingTheme.neonPurple,
                      _buildBalanceSheetChart(balances))),
              SizedBox(width: context.accR.spaceS),
              Expanded(
                  flex: 4,
                  child: _chartPanel(
                      'الإيرادات vs المصروفات',
                      Icons.bar_chart_rounded,
                      AccountingTheme.neonBlue,
                      _buildRevenueExpenseChart(
                          balances, collections, expenses))),
              SizedBox(width: context.accR.spaceS),
              Expanded(
                  flex: 4,
                  child: _chartPanel(
                      'إحصائيات الشهر',
                      Icons.calendar_month_rounded,
                      AccountingTheme.neonOrange,
                      _buildMonthlyChart(
                          collections, expenses, salaries, data))),
            ],
          ),
        ),
        SizedBox(height: context.accR.spaceS),
        // Bottom row
        Expanded(
          flex: 3,
          child: Row(
            children: [
              Expanded(
                  flex: 3,
                  child: _chartPanel(
                      'المعلقات والذمم',
                      Icons.pending_actions_rounded,
                      AccountingTheme.neonPurple,
                      _buildPendingChart(
                          collections, salaries, agentNet, techNet))),
              SizedBox(width: context.accR.spaceS),
              Expanded(
                  flex: 3,
                  child: _chartPanel(
                      'الإجماليات الكلية',
                      Icons.analytics_rounded,
                      AccountingTheme.neonBlue,
                      _buildTotalsView(
                          collections, expenses, salaries, journal))),
              SizedBox(width: context.accR.spaceS),
              Expanded(
                  flex: 2,
                  child: _chartPanel(
                      'الصناديق النقدية',
                      Icons.account_balance_wallet_rounded,
                      AccountingTheme.neonOrange,
                      _buildCashBoxesList(cashBoxes, balances))),
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _buildKpiList(Map<String, dynamic> balances) {
    return [
      _kpi('القاصة', balances['CashRegisterBalance'],
          AccountingTheme.neonBlue, Icons.point_of_sale_rounded),
      _kpi('الصندوق الرئيسي', balances['MainCashBoxBalance'],
          const Color(0xFF34495E), Icons.account_balance_rounded),
      _kpi('رصيد الصفحة', balances['PageBalance'], AccountingTheme.info,
          Icons.account_balance_wallet_rounded),
      _kpi('الصندوق النقدي', balances['CashAccountBalance'],
          AccountingTheme.success, Icons.savings_rounded),
      _kpiHighlight('صافي الدخل', balances['NetIncome']),
      _kpi('مستحقات المشغلين', balances['OperatorReceivables'],
          AccountingTheme.neonPurple, Icons.people_rounded),
    ];
  }

  // ══════════════════════ KPI TILES ══════════════════════

  Widget _kpi(String label, dynamic value, Color color, IconData icon) {
    return Expanded(
      child: Container(
        padding: EdgeInsets.symmetric(
            horizontal: context.accR.spaceS, vertical: context.accR.spaceXS),
        decoration: BoxDecoration(
          color: AccountingTheme.bgCard,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.15)),
          boxShadow: AccountingTheme.cardShadow,
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: context.accR.iconS),
            ),
            SizedBox(width: context.accR.spaceXS),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      _fmt(value),
                      style: GoogleFonts.cairo(
                        fontSize: context.accR.financialSmall,
                        fontWeight: FontWeight.bold,
                        color: AccountingTheme.textPrimary,
                      ),
                    ),
                  ),
                  Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.cairo(
                          fontSize: context.accR.caption,
                          color: AccountingTheme.textMuted)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _kpiHighlight(String label, dynamic value) {
    final isPos = _isPositive(value);
    final color = isPos ? AccountingTheme.success : AccountingTheme.danger;
    return Expanded(
      child: Container(
        padding: EdgeInsets.symmetric(
            horizontal: context.accR.spaceS, vertical: context.accR.spaceXS),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [color, color.withOpacity(0.85)],
          ),
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
                color: color.withOpacity(0.25),
                blurRadius: 8,
                offset: const Offset(0, 3)),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(isPos ? Icons.trending_up : Icons.trending_down,
                  color: Colors.white, size: context.accR.iconS),
            ),
            SizedBox(width: context.accR.spaceXS),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      _fmt(value),
                      style: GoogleFonts.cairo(
                        fontSize: context.accR.financialSmall,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  Text('$label (${isPos ? 'ربح' : 'خسارة'})',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.cairo(
                          fontSize: context.accR.caption,
                          color: Colors.white.withOpacity(0.85))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ══════════════════════ CHART PANEL WRAPPER ══════════════════════

  Widget _chartPanel(String title, IconData icon, Color color, Widget child) {
    return Container(
      decoration: BoxDecoration(
        color: AccountingTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AccountingTheme.borderColor),
        boxShadow: AccountingTheme.cardShadow,
      ),
      child: Column(
        children: [
          Container(
            padding: EdgeInsets.symmetric(
                horizontal: context.accR.spaceM,
                vertical: context.accR.spaceXS + 2),
            decoration: BoxDecoration(
              color: color.withOpacity(0.05),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
              border: Border(
                bottom: BorderSide(color: color.withOpacity(0.1)),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(icon, color: color, size: context.accR.iconXS),
                ),
                SizedBox(width: context.accR.spaceXS),
                Text(title,
                    style: GoogleFonts.cairo(
                        fontSize: context.accR.small,
                        fontWeight: FontWeight.bold,
                        color: AccountingTheme.textPrimary)),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.all(context.accR.spaceS),
              child: child,
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════ CHART 1: BALANCE SHEET (DONUT) ══════════════════════

  Widget _buildBalanceSheetChart(Map<String, dynamic> balances) {
    final assets = _num(balances['TotalAssets']);
    final liabilities = _num(balances['TotalLiabilities']);
    final equity = _num(balances['TotalEquity']);
    final total = assets.abs() + liabilities.abs() + equity.abs();

    if (total == 0) {
      return Center(
          child: Text('لا توجد بيانات',
              style: GoogleFonts.cairo(
                  color: AccountingTheme.textMuted,
                  fontSize: context.accR.small)));
    }

    final items = [
      _PieItem('الأصول', assets, AccountingTheme.neonBlue),
      _PieItem('الالتزامات', liabilities, AccountingTheme.neonOrange),
      _PieItem('حقوق الملكية', equity, AccountingTheme.neonPurple),
    ];

    return Row(
      children: [
        // Donut chart with center total
        Expanded(
          flex: 3,
          child: Stack(
            alignment: Alignment.center,
            children: [
              PieChart(
                PieChartData(
                  sectionsSpace: 3,
                  centerSpaceRadius: 36,
                  sections: items
                      .map((e) {
                        final pct = total > 0
                            ? (e.value.abs() / total * 100)
                            : 0.0;
                        return PieChartSectionData(
                          value: e.value.abs(),
                          color: e.color,
                          radius: 34,
                          title: pct >= 5 ? '${pct.toStringAsFixed(0)}%' : '',
                          titleStyle: GoogleFonts.cairo(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                          titlePositionPercentageOffset: 0.55,
                        );
                      })
                      .toList(),
                ),
              ),
              // Center total
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('الإجمالي',
                      style: GoogleFonts.cairo(
                          fontSize: 7, color: AccountingTheme.textMuted)),
                  Text(_fmtShort(total),
                      style: GoogleFonts.cairo(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: AccountingTheme.textPrimary)),
                ],
              ),
            ],
          ),
        ),
        SizedBox(width: context.accR.spaceS),
        // Legend with background rows
        Expanded(
          flex: 2,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: items.map((e) {
              final pct =
                  total > 0 ? (e.value.abs() / total * 100) : 0.0;
              return _legendRow(e.label, e.value, e.color, pct);
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _legendRow(String label, double value, Color color, double pct) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
                color: color, borderRadius: BorderRadius.circular(3)),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: GoogleFonts.cairo(
                        fontSize: 9, color: AccountingTheme.textMuted),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                Text(_fmtShort(value),
                    style: GoogleFonts.cairo(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: AccountingTheme.textPrimary)),
              ],
            ),
          ),
          Text('${pct.toStringAsFixed(0)}%',
              style: GoogleFonts.cairo(
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  color: color)),
        ],
      ),
    );
  }

  // ══════════════════════ CHART 2: REVENUE vs EXPENSE ══════════════════════

  Widget _buildRevenueExpenseChart(
    Map<String, dynamic> balances,
    Map<String, dynamic> collections,
    Map<String, dynamic> expenses,
  ) {
    final totalRevenue = _num(balances['TotalRevenue']);
    final totalExpenses = _num(balances['TotalExpenses']);
    final monthCollections = _num(collections['MonthlyTotal']);
    final monthExpenses = _num(expenses['MonthlyTotal']);

    final maxVal = [totalRevenue, totalExpenses, monthCollections, monthExpenses]
        .fold<double>(0, (a, b) => b.abs() > a ? b.abs() : a);

    return Column(
      children: [
        // Legend row
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _chartLegendDot('إجمالي الإيرادات', AccountingTheme.success),
              const SizedBox(width: 12),
              _chartLegendDot('إجمالي المصروفات', AccountingTheme.danger),
              const SizedBox(width: 12),
              _chartLegendDot('تحصيل الشهر', AccountingTheme.neonBlue),
              const SizedBox(width: 12),
              _chartLegendDot('صرف الشهر', AccountingTheme.neonOrange),
            ],
          ),
        ),
        Expanded(
          child: BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceAround,
              maxY: maxVal * 1.25,
              minY: 0,
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  tooltipPadding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  tooltipMargin: 8,
                  tooltipRoundedRadius: 8,
                  getTooltipColor: (_) => const Color(0xF02C3E50),
                  getTooltipItem: (group, gI, rod, rI) {
                    final labels = [
                      'إجمالي الإيرادات',
                      'إجمالي المصروفات',
                      'تحصيل الشهر',
                      'صرف الشهر'
                    ];
                    final idx = group.x;
                    return BarTooltipItem(
                      '${idx < labels.length ? labels[idx] : ''}\n${_fmt(rod.toY)}',
                      GoogleFonts.cairo(
                          fontSize: 10,
                          color: Colors.white,
                          fontWeight: FontWeight.bold),
                    );
                  },
                ),
              ),
              titlesData: FlTitlesData(
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 42,
                    getTitlesWidget: (val, meta) {
                      if (val == 0) return const SizedBox();
                      return Padding(
                        padding: const EdgeInsetsDirectional.only(end: 4),
                        child: Text(_fmtShort(val),
                            style: GoogleFonts.cairo(
                                fontSize: 8,
                                color: AccountingTheme.textMuted)),
                      );
                    },
                    interval: maxVal > 0 ? maxVal / 3 : 1,
                  ),
                ),
                rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false)),
                topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (val, meta) {
                      final labels = ['إيرادات', 'مصروفات', 'تحصيل', 'صرف'];
                      final idx = val.toInt();
                      if (idx < 0 || idx >= labels.length)
                        return const SizedBox();
                      return Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(labels[idx],
                            textAlign: TextAlign.center,
                            style: GoogleFonts.cairo(
                                fontSize: 9,
                                color: AccountingTheme.textSecondary)),
                      );
                    },
                    reservedSize: 22,
                  ),
                ),
              ),
              borderData: FlBorderData(show: false),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: maxVal > 0 ? maxVal / 3 : 1,
                getDrawingHorizontalLine: (v) => FlLine(
                    color: const Color(0x18000000),
                    strokeWidth: 0.8,
                    dashArray: [4, 3]),
              ),
              barGroups: [
                _styledBar(0, totalRevenue.abs(), AccountingTheme.success),
                _styledBar(1, totalExpenses.abs(), AccountingTheme.danger),
                _styledBar(2, monthCollections.abs(), AccountingTheme.neonBlue),
                _styledBar(3, monthExpenses.abs(), AccountingTheme.neonOrange),
              ],
            ),
          ),
        ),
        // Summary under chart
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: AccountingTheme.bgSecondary,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _summaryChip('صافي إجمالي',
                  totalRevenue.abs() - totalExpenses.abs(), null),
              Container(width: 1, height: 16, color: AccountingTheme.borderColor),
              _summaryChip('صافي الشهر',
                  monthCollections.abs() - monthExpenses.abs(), null),
            ],
          ),
        ),
      ],
    );
  }

  Widget _summaryChip(String label, double value, Color? overrideColor) {
    final color = overrideColor ??
        (value >= 0 ? AccountingTheme.success : AccountingTheme.danger);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(value >= 0 ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
            size: 12, color: color),
        const SizedBox(width: 3),
        Text(label,
            style: GoogleFonts.cairo(
                fontSize: 9, color: AccountingTheme.textMuted)),
        const SizedBox(width: 4),
        Text(_fmtShort(value.abs()),
            style: GoogleFonts.cairo(
                fontSize: 10, fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }

  Widget _chartLegendDot(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration:
              BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(width: 3),
        Text(label,
            style:
                GoogleFonts.cairo(fontSize: 8, color: AccountingTheme.textMuted)),
      ],
    );
  }

  BarChartGroupData _styledBar(int x, double val, Color color) {
    return BarChartGroupData(
      x: x,
      barRods: [
        BarChartRodData(
          toY: val,
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [color.withOpacity(0.85), color],
          ),
          width: 22,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
          backDrawRodData: BackgroundBarChartRodData(
            show: true,
            color: color.withOpacity(0.04),
          ),
        ),
      ],
      showingTooltipIndicators: [],
    );
  }

  // ══════════════════════ CHART 3: MONTHLY STATS ══════════════════════

  Widget _buildMonthlyChart(
    Map<String, dynamic> collections,
    Map<String, dynamic> expenses,
    Map<String, dynamic> salaries,
    Map<String, dynamic> data,
  ) {
    final c = _num(collections['MonthlyTotal']);
    final e = _num(expenses['MonthlyTotal']);
    final s = _num(salaries['MonthlyTotal']);
    final n = _num(data['NetMonthly']);
    final cCount = collections['MonthlyCount'] ?? 0;
    final eCount = expenses['MonthlyCount'] ?? 0;
    final sCount = salaries['MonthlyCount'] ?? 0;

    final items = [
      _MonthlyItem('تحصيلات', c, cCount, const Color(0xFF1ABC9C),
          Icons.arrow_downward_rounded),
      _MonthlyItem('مصروفات', e, eCount, AccountingTheme.neonOrange,
          Icons.arrow_upward_rounded),
      _MonthlyItem('رواتب', s, sCount, AccountingTheme.neonPink,
          Icons.people_rounded),
    ];

    final maxVal = [c, e, s].fold<double>(0, (a, b) => b.abs() > a ? b.abs() : a);

    return Column(
      children: [
        // Net income banner
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: (n >= 0 ? AccountingTheme.success : AccountingTheme.danger)
                .withOpacity(0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: (n >= 0 ? AccountingTheme.success : AccountingTheme.danger)
                  .withOpacity(0.15),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                  n >= 0
                      ? Icons.trending_up_rounded
                      : Icons.trending_down_rounded,
                  size: 16,
                  color: n >= 0
                      ? AccountingTheme.success
                      : AccountingTheme.danger),
              const SizedBox(width: 6),
              Text('صافي الشهر',
                  style: GoogleFonts.cairo(
                      fontSize: 10, color: AccountingTheme.textSecondary)),
              const SizedBox(width: 8),
              Text(_fmt(n),
                  style: GoogleFonts.cairo(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: n >= 0
                          ? AccountingTheme.success
                          : AccountingTheme.danger)),
            ],
          ),
        ),
        // Monthly items as detailed rows with inline bar
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: items.map((item) {
              final pct = maxVal > 0
                  ? (item.value.abs() / maxVal).clamp(0.0, 1.0)
                  : 0.0;
              return Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: item.color.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Label + value + count
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: item.color.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Icon(item.icon,
                              size: 12, color: item.color),
                        ),
                        const SizedBox(width: 6),
                        Text(item.label,
                            style: GoogleFonts.cairo(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: AccountingTheme.textSecondary)),
                        const Spacer(),
                        Text(_fmtShort(item.value.abs()),
                            style: GoogleFonts.cairo(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: AccountingTheme.textPrimary)),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: item.color.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text('${item.count}',
                              style: GoogleFonts.cairo(
                                  fontSize: 8,
                                  fontWeight: FontWeight.bold,
                                  color: item.color)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    // Progress bar
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: pct,
                        minHeight: 5,
                        backgroundColor: item.color.withOpacity(0.08),
                        valueColor:
                            AlwaysStoppedAnimation<Color>(item.color),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  // ══════════════════════ CHART 4: PENDING ══════════════════════

  Widget _buildPendingChart(
    Map<String, dynamic> collections,
    Map<String, dynamic> salaries,
    num agentNet,
    num techNet,
  ) {
    final items = [
      _HBarItem('تحصيلات غير مسلمة', _num(collections['PendingDelivery']),
          AccountingTheme.neonPurple, Icons.local_shipping_rounded),
      _HBarItem('رواتب غير مصروفة', _num(salaries['UnpaidTotal']),
          AccountingTheme.danger, Icons.payments_rounded),
      _HBarItem(
          agentNet < 0 ? 'وكلاء (مدينون)' : 'وكلاء (دائنون)',
          agentNet.toDouble().abs(),
          agentNet < 0 ? AccountingTheme.danger : AccountingTheme.success,
          Icons.support_agent_rounded),
      _HBarItem(
          techNet < 0 ? 'فنيين (مدينون)' : 'فنيين (دائنون)',
          techNet.toDouble().abs(),
          techNet < 0 ? AccountingTheme.neonPurple : AccountingTheme.success,
          Icons.engineering_rounded),
    ];

    final maxVal = items.fold<double>(0, (a, b) => b.value > a ? b.value : a);

    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: items.map((item) => _hBar(item, maxVal)).toList(),
    );
  }

  Widget _hBar(_HBarItem item, double maxVal) {
    final pct = maxVal > 0 ? (item.value / maxVal).clamp(0.0, 1.0) : 0.0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: item.color.withOpacity(0.03),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: item.color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(item.icon, size: 14, color: item.color),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Text(item.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.cairo(
                              fontSize: 10,
                              color: AccountingTheme.textSecondary)),
                    ),
                    Text(_fmtShort(item.value),
                        style: GoogleFonts.cairo(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: AccountingTheme.textPrimary)),
                  ],
                ),
                const SizedBox(height: 3),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: pct,
                    minHeight: 6,
                    backgroundColor: item.color.withOpacity(0.08),
                    valueColor: AlwaysStoppedAnimation<Color>(
                        item.color.withOpacity(0.75)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════ TOTALS VIEW ══════════════════════

  Widget _buildTotalsView(
    Map<String, dynamic> collections,
    Map<String, dynamic> expenses,
    Map<String, dynamic> salaries,
    Map<String, dynamic> journal,
  ) {
    final totalCollected = _num(collections['TotalCollected']);
    final totalExpenses = _num(expenses['TotalExpenses']);
    final totalSalaries = _num(salaries['TotalSalaries']);
    final grandTotal = totalCollected.abs() + totalExpenses.abs() + totalSalaries.abs();

    final items = [
      _TotalItem(
          'إجمالي التحصيلات',
          totalCollected,
          '${collections['TotalCount'] ?? 0}',
          AccountingTheme.success,
          Icons.monetization_on_rounded),
      _TotalItem(
          'إجمالي المصروفات',
          totalExpenses,
          '${expenses['TotalCount'] ?? 0}',
          AccountingTheme.danger,
          Icons.receipt_long_rounded),
      _TotalItem(
          'إجمالي الرواتب',
          totalSalaries,
          '${salaries['TotalCount'] ?? 0}',
          AccountingTheme.neonPink,
          Icons.payments_rounded),
      _TotalItem(
          'القيود المحاسبية',
          _num(journal['TotalCount']),
          'شهري: ${journal['MonthlyCount'] ?? 0}',
          const Color(0xFF5C6BC0),
          Icons.menu_book_rounded),
    ];

    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: items.map((item) {
        // For the first 3 items, compute percentage of grand total
        final showPct = item.label != 'القيود المحاسبية' && grandTotal > 0;
        final pct = showPct ? (item.value.abs() / grandTotal * 100) : 0.0;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: item.color.withOpacity(0.04),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              // Mini circular indicator
              SizedBox(
                width: 32,
                height: 32,
                child: CustomPaint(
                  painter: _MiniRingPainter(
                    progress: showPct ? pct / 100 : 0,
                    color: item.color,
                    bgColor: item.color.withOpacity(0.12),
                  ),
                  child: Center(
                    child: Icon(item.icon,
                        color: item.color, size: 13),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.label,
                        style: GoogleFonts.cairo(
                            fontSize: 10,
                            color: AccountingTheme.textMuted),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    Text(
                      item.label == 'القيود المحاسبية'
                          ? item.value.toStringAsFixed(0)
                          : _fmtShort(item.value),
                      style: GoogleFonts.cairo(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: AccountingTheme.textPrimary),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (showPct)
                    Text('${pct.toStringAsFixed(0)}%',
                        style: GoogleFonts.cairo(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: item.color)),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                    decoration: BoxDecoration(
                      color: item.color.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(item.count,
                        style: GoogleFonts.cairo(
                            fontSize: 8,
                            fontWeight: FontWeight.bold,
                            color: item.color)),
                  ),
                ],
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  // ══════════════════════ CASH BOXES ══════════════════════

  Widget _buildCashBoxesList(
      List<dynamic> cashBoxes, Map<String, dynamic> balances) {
    final List<_CashBox> boxes = [];
    for (final box in cashBoxes) {
      final m = box is Map<String, dynamic> ? box : <String, dynamic>{};
      boxes.add(_CashBox(
        m['Name']?.toString() ?? m['name']?.toString() ?? 'صندوق',
        _num(m['Balance'] ?? m['balance'] ?? m['CurrentBalance']),
      ));
    }
    if (boxes.isEmpty) {
      return Center(
          child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inventory_2_outlined,
              color: AccountingTheme.textMuted.withOpacity(0.4), size: 32),
          const SizedBox(height: 6),
          Text('لا توجد صناديق',
              style: GoogleFonts.cairo(
                  color: AccountingTheme.textMuted,
                  fontSize: context.accR.caption)),
        ],
      ));
    }

    final totalBalance = boxes.fold<double>(0, (a, b) => a + b.balance);

    return Column(
      children: [
        // Total row
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          margin: const EdgeInsets.only(bottom: 6),
          decoration: BoxDecoration(
            color: AccountingTheme.bgSecondary,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(Icons.account_balance_rounded,
                  size: 14, color: AccountingTheme.textSecondary),
              const SizedBox(width: 6),
              Text('إجمالي الصناديق',
                  style: GoogleFonts.cairo(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: AccountingTheme.textSecondary)),
              const Spacer(),
              Text(_fmtShort(totalBalance),
                  style: GoogleFonts.cairo(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: totalBalance >= 0
                          ? AccountingTheme.success
                          : AccountingTheme.danger)),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: EdgeInsets.zero,
            itemCount: boxes.length,
            separatorBuilder: (_, __) => const SizedBox(height: 4),
            itemBuilder: (_, i) {
              final b = boxes[i];
              final maxBal = boxes
                  .fold<double>(0, (a, x) => x.balance.abs() > a ? x.balance.abs() : a);
              final pct = maxBal > 0
                  ? (b.balance.abs() / maxBal).clamp(0.0, 1.0)
                  : 0.0;
              return Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: (b.balance >= 0
                          ? AccountingTheme.success
                          : AccountingTheme.danger)
                      .withOpacity(0.04),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Icon(Icons.inventory_2_outlined,
                            color: AccountingTheme.neonBlue, size: 14),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(b.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.cairo(
                                  fontSize: 10,
                                  color: AccountingTheme.textPrimary)),
                        ),
                        Text(_fmtShort(b.balance),
                            style: GoogleFonts.cairo(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: b.balance >= 0
                                    ? AccountingTheme.success
                                    : AccountingTheme.danger)),
                      ],
                    ),
                    const SizedBox(height: 3),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: pct,
                        minHeight: 3,
                        backgroundColor: AccountingTheme.borderColor,
                        valueColor: AlwaysStoppedAnimation<Color>(
                            b.balance >= 0
                                ? AccountingTheme.success
                                : AccountingTheme.danger),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ══════════════════════ HELPERS ══════════════════════

  double _num(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0;
  }

  bool _isPositive(dynamic value) => _num(value) >= 0;

  String _fmt(dynamic value) {
    final n = _num(value);
    final abs = n.abs();
    final parts = abs.toStringAsFixed(0).split('');
    final buf = StringBuffer();
    for (int i = 0; i < parts.length; i++) {
      if (i > 0 && (parts.length - i) % 3 == 0) buf.write(',');
      buf.write(parts[i]);
    }
    return '${n < 0 ? '-' : ''}${buf.toString()} د.ع';
  }

  String _fmtShort(double value) {
    final abs = value.abs();
    final sign = value < 0 ? '-' : '';
    if (abs >= 1000000) {
      return '$sign${(abs / 1000000).toStringAsFixed(1)}M';
    } else if (abs >= 1000) {
      return '$sign${(abs / 1000).toStringAsFixed(1)}K';
    }
    return '$sign${abs.toStringAsFixed(0)}';
  }
}

// ══════════════════════ MINI RING PAINTER ══════════════════════

class _MiniRingPainter extends CustomPainter {
  final double progress;
  final Color color;
  final Color bgColor;

  _MiniRingPainter({
    required this.progress,
    required this.color,
    required this.bgColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 2;
    const strokeWidth = 3.0;

    // Background ring
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = bgColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth,
    );

    // Progress arc
    if (progress > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        2 * math.pi * progress,
        false,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MiniRingPainter old) =>
      old.progress != progress || old.color != color;
}

// ══════════════════════ DATA MODELS ══════════════════════

class _PieItem {
  final String label;
  final double value;
  final Color color;
  _PieItem(this.label, this.value, this.color);
}

class _HBarItem {
  final String label;
  final double value;
  final Color color;
  final IconData icon;
  _HBarItem(this.label, this.value, this.color, this.icon);
}

class _MonthlyItem {
  final String label;
  final double value;
  final dynamic count;
  final Color color;
  final IconData icon;
  _MonthlyItem(this.label, this.value, this.count, this.color, this.icon);
}

class _TotalItem {
  final String label;
  final double value;
  final String count;
  final Color color;
  final IconData icon;
  _TotalItem(this.label, this.value, this.count, this.color, this.icon);
}

class _CashBox {
  final String name;
  final double balance;
  _CashBox(this.name, this.balance);
}
