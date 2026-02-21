import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../services/accounting_service.dart';
import 'chart_of_accounts_page.dart';

/// صفحة الإحصائيات - داشبورد محاسبي بمخططات بيانية (شاشة واحدة بدون تمرير)
class StatisticsPage extends StatefulWidget {
  final String? companyId;
  const StatisticsPage({super.key, this.companyId});

  @override
  State<StatisticsPage> createState() => _StatisticsPageState();
}

class _StatisticsPageState extends State<StatisticsPage>
    with TickerProviderStateMixin {
  bool _isLoading = true;
  String? _errorMessage;
  Map<String, dynamic>? _dashboardData;
  Map<String, dynamic>? _fundsData;
  List<dynamic>? _accountsList;

  // خلفية متحركة
  late AnimationController _bgAnimController;
  late AnimationController _particleController;
  late List<_Particle> _particles;

  // ألوان
  static const _bgCard = Color(0xE6FFFFFF); // شفافية خفيفة
  static const _bgToolbar = Color(0xFF1E2A38);
  static const _textDark = Color(0xFFE8ECF1);
  static const _textMuted = Color(0xFF8899AA);

  // ألوان المخططات
  static const _clrGreen = Color(0xFF27AE60);
  static const _clrRed = Color(0xFFE74C3C);
  static const _clrBlue = Color(0xFF2980B9);
  static const _clrOrange = Color(0xFFE67E22);
  static const _clrPurple = Color(0xFF8E44AD);
  static const _clrTeal = Color(0xFF16A085);
  static const _clrPink = Color(0xFFE91E63);
  static const _clrDark = Color(0xFF2C3E50);
  static const _clrIndigo = Color(0xFF5C6BC0);

  @override
  void initState() {
    super.initState();

    // تحريك التدرج اللوني
    _bgAnimController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();

    // تحريك الجسيمات العائمة
    _particleController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat();

    // إنشاء جسيمات عشوائية
    final rng = Random();
    _particles = List.generate(30, (_) => _Particle.random(rng));

    _loadAllData();
  }

  @override
  void dispose() {
    _bgAnimController.dispose();
    _particleController.dispose();
    super.dispose();
  }

  Future<void> _loadAllData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final results = await Future.wait([
        AccountingService.instance.getDashboard(companyId: widget.companyId),
        AccountingService.instance.getAccounts(companyId: widget.companyId),
        AccountingService.instance
            .getFundsOverview(companyId: widget.companyId),
      ]);
      if (!mounted) return;

      final dashResult = results[0];
      final accountsResult = results[1];
      final fundsResult = results[2];

      if (dashResult['success'] == true) {
        final data = dashResult['data'] is Map<String, dynamic>
            ? dashResult['data']
            : <String, dynamic>{};
        final balances = data['AccountBalances'] as Map<String, dynamic>? ?? {};
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
        _errorMessage = 'خطأ في الاتصال: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: Stack(
          children: [
            // الخلفية المتحركة
            AnimatedBuilder(
              animation:
                  Listenable.merge([_bgAnimController, _particleController]),
              builder: (context, _) {
                return CustomPaint(
                  painter: _AnimatedBgPainter(
                    progress: _bgAnimController.value,
                    particles: _particles,
                    particleProgress: _particleController.value,
                  ),
                  size: Size.infinite,
                );
              },
            ),
            // المحتوى
            Column(
              children: [
                _buildToolbar(),
                Expanded(
                  child: _isLoading
                      ? const Center(
                          child: CircularProgressIndicator(color: Colors.white))
                      : _errorMessage != null
                          ? _buildErrorView()
                          : _buildDashboard(),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ══════════════════════ TOOLBAR ══════════════════════

  Widget _buildToolbar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xCC0D1B2A),
        border: Border(
          bottom: BorderSide(color: Colors.white.withOpacity(0.08)),
        ),
        boxShadow: const [
          BoxShadow(
              color: Color(0x40000000), blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_forward_rounded, size: 20),
            tooltip: 'رجوع',
            style: IconButton.styleFrom(foregroundColor: Colors.white70),
          ),
          const SizedBox(width: 6),
          const Icon(Icons.dashboard_rounded, color: Colors.white70, size: 18),
          const SizedBox(width: 8),
          Text('لوحة الإحصائيات المالية',
              style: GoogleFonts.cairo(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white)),
          const Spacer(),
          _toolbarBtn(Icons.account_tree_rounded, 'شجرة الحسابات', () {
            Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => ChartOfAccountsPage(companyId: widget.companyId),
            ));
          }),
          const SizedBox(width: 6),
          IconButton(
            onPressed: _loadAllData,
            icon: const Icon(Icons.refresh, size: 18),
            tooltip: 'تحديث',
            style: IconButton.styleFrom(foregroundColor: Colors.white70),
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
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white24),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white70, size: 14),
            const SizedBox(width: 4),
            Text(label,
                style: GoogleFonts.cairo(fontSize: 11, color: Colors.white70)),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, color: _clrRed, size: 48),
          const SizedBox(height: 12),
          Text(_errorMessage!,
              style: GoogleFonts.cairo(color: _textMuted, fontSize: 14)),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: _loadAllData,
            icon: const Icon(Icons.refresh, color: Colors.white, size: 16),
            label: Text('إعادة المحاولة',
                style: GoogleFonts.cairo(color: Colors.white, fontSize: 12)),
            style: ElevatedButton.styleFrom(
              backgroundColor: _clrBlue,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6)),
            ),
          ),
        ],
      ),
    );
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
      padding: const EdgeInsets.all(10),
      child: Column(
        children: [
          // ══ الصف الأول: مؤشرات KPI مصغرة ══
          SizedBox(
            height: 62,
            child: Row(
              children: [
                _kpi('القاصة', balances['CashRegisterBalance'], _clrTeal,
                    Icons.point_of_sale),
                const SizedBox(width: 6),
                _kpi('الصندوق الرئيسي', balances['MainCashBoxBalance'],
                    _clrDark, Icons.account_balance),
                const SizedBox(width: 6),
                _kpi('رصيد الصفحة', balances['PageBalance'], _clrBlue,
                    Icons.account_balance_wallet),
                const SizedBox(width: 6),
                _kpi('الصندوق النقدي', balances['CashAccountBalance'],
                    _clrGreen, Icons.savings),
                const SizedBox(width: 6),
                _kpiHighlight('صافي الدخل', balances['NetIncome']),
                const SizedBox(width: 6),
                _kpi('مستحقات المشغلين', balances['OperatorReceivables'],
                    _clrPurple, Icons.people),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // ══ الصف الثاني: 3 مخططات رئيسية ══
          Expanded(
            flex: 5,
            child: Row(
              children: [
                // المخطط 1: الميزانية العمومية - Donut
                Expanded(
                  child: _chartPanel(
                    'الميزانية العمومية',
                    Icons.balance,
                    _clrPurple,
                    _buildBalanceSheetChart(balances),
                  ),
                ),
                const SizedBox(width: 8),
                // المخطط 2: الإيرادات والمصروفات - Bar
                Expanded(
                  child: _chartPanel(
                    'الإيرادات vs المصروفات',
                    Icons.bar_chart,
                    _clrBlue,
                    _buildRevenueExpenseChart(balances, collections, expenses),
                  ),
                ),
                const SizedBox(width: 8),
                // المخطط 3: إحصائيات الشهر - Bar
                Expanded(
                  child: _chartPanel(
                    'إحصائيات الشهر',
                    Icons.calendar_today,
                    _clrOrange,
                    _buildMonthlyChart(collections, expenses, salaries, data),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // ══ الصف الثالث: المعلقات + الإجماليات + الصناديق ══
          Expanded(
            flex: 3,
            child: Row(
              children: [
                // المعلقات والذمم
                Expanded(
                  flex: 3,
                  child: _chartPanel(
                    'المعلقات والذمم',
                    Icons.pending_actions,
                    _clrPurple,
                    _buildPendingChart(
                        collections, salaries, agentNet, techNet),
                  ),
                ),
                const SizedBox(width: 8),
                // الإجماليات الكلية
                Expanded(
                  flex: 3,
                  child: _chartPanel(
                    'الإجماليات الكلية',
                    Icons.summarize,
                    _clrTeal,
                    _buildTotalsView(collections, expenses, salaries, journal),
                  ),
                ),
                const SizedBox(width: 8),
                // الصناديق النقدية
                Expanded(
                  flex: 2,
                  child: _chartPanel(
                    'الصناديق النقدية',
                    Icons.inventory_2,
                    _clrDark,
                    _buildCashBoxesList(cashBoxes, balances),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════ KPI TILES ══════════════════════

  Widget _kpi(String label, dynamic value, Color color, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xCC1A2332),
          borderRadius: BorderRadius.circular(8),
          border: Border(
            bottom: BorderSide(color: color, width: 3),
          ),
          boxShadow: const [
            BoxShadow(
                color: Color(0x20000000), blurRadius: 4, offset: Offset(0, 1)),
          ],
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 6),
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
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.cairo(
                          fontSize: 9, color: Colors.white60)),
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
    final color = isPos ? _clrGreen : _clrRed;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [color, color.withOpacity(0.8)],
          ),
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
                color: color.withOpacity(0.3),
                blurRadius: 6,
                offset: const Offset(0, 2)),
          ],
        ),
        child: Row(
          children: [
            Icon(isPos ? Icons.trending_up : Icons.trending_down,
                color: Colors.white, size: 18),
            const SizedBox(width: 6),
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
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  Text('$label (${isPos ? 'ربح' : 'خسارة'})',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.cairo(
                          fontSize: 9, color: Colors.white70)),
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
        color: const Color(0xCC1A2332),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
        boxShadow: const [
          BoxShadow(
              color: Color(0x20000000), blurRadius: 6, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: color.withOpacity(0.08),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(8)),
            ),
            child: Row(
              children: [
                Icon(icon, color: color, size: 14),
                const SizedBox(width: 6),
                Text(title,
                    style: GoogleFonts.cairo(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.white)),
              ],
            ),
          ),
          // Body
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(8),
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
              style: GoogleFonts.cairo(color: _textMuted, fontSize: 12)));
    }

    final items = [
      _PieItem('الأصول', assets, _clrBlue),
      _PieItem('الالتزامات', liabilities, _clrOrange),
      _PieItem('حقوق الملكية', equity, _clrPurple),
    ];

    return Row(
      children: [
        // Donut chart
        Expanded(
          flex: 3,
          child: PieChart(
            PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: 28,
              sections: items
                  .map((e) => PieChartSectionData(
                        value: e.value.abs(),
                        color: e.color,
                        radius: 32,
                        title: '',
                      ))
                  .toList(),
            ),
          ),
        ),
        const SizedBox(width: 6),
        // Legend
        Expanded(
          flex: 2,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: items
                .map((e) => _legendRow(e.label, e.value, e.color))
                .toList(),
          ),
        ),
      ],
    );
  }

  Widget _legendRow(String label, double value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
                color: color, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: GoogleFonts.cairo(fontSize: 9, color: _textMuted),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(_fmtShort(value),
                      style: GoogleFonts.cairo(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: _textDark)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════ CHART 2: REVENUE vs EXPENSE (BAR) ══════════════════════

  Widget _buildRevenueExpenseChart(
    Map<String, dynamic> balances,
    Map<String, dynamic> collections,
    Map<String, dynamic> expenses,
  ) {
    final totalRevenue = _num(balances['TotalRevenue']);
    final totalExpenses = _num(balances['TotalExpenses']);
    final monthCollections = _num(collections['MonthlyTotal']);
    final monthExpenses = _num(expenses['MonthlyTotal']);

    final maxVal = [
      totalRevenue,
      totalExpenses,
      monthCollections,
      monthExpenses
    ].fold<double>(0, (a, b) => b.abs() > a ? b.abs() : a);

    return Column(
      children: [
        Expanded(
          child: BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceAround,
              maxY: maxVal * 1.2,
              minY: 0,
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  tooltipPadding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  tooltipMargin: 4,
                  getTooltipItem: (group, gI, rod, rI) {
                    return BarTooltipItem(
                      _fmtShort(rod.toY),
                      GoogleFonts.cairo(
                          fontSize: 9,
                          color: Colors.white,
                          fontWeight: FontWeight.bold),
                    );
                  },
                ),
              ),
              titlesData: FlTitlesData(
                leftTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (val, meta) {
                      final labels = [
                        'إيرادات\nإجمالي',
                        'مصروفات\nإجمالي',
                        'تحصيل\nالشهر',
                        'صرف\nالشهر'
                      ];
                      final idx = val.toInt();
                      if (idx < 0 || idx >= labels.length)
                        return const SizedBox();
                      return Text(labels[idx],
                          textAlign: TextAlign.center,
                          style: GoogleFonts.cairo(
                              fontSize: 7, color: _textMuted));
                    },
                    reservedSize: 28,
                  ),
                ),
              ),
              borderData: FlBorderData(show: false),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: maxVal > 0 ? maxVal / 4 : 1,
                getDrawingHorizontalLine: (v) =>
                    FlLine(color: const Color(0x15000000), strokeWidth: 1),
              ),
              barGroups: [
                _bar(0, totalRevenue.abs(), _clrGreen),
                _bar(1, totalExpenses.abs(), _clrRed),
                _bar(2, monthCollections.abs(), _clrBlue),
                _bar(3, monthExpenses.abs(), _clrOrange),
              ],
            ),
          ),
        ),
      ],
    );
  }

  BarChartGroupData _bar(int x, double val, Color color) {
    return BarChartGroupData(
      x: x,
      barRods: [
        BarChartRodData(
          toY: val,
          color: color,
          width: 18,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
        ),
      ],
    );
  }

  // ══════════════════════ CHART 3: MONTHLY STATS (BAR) ══════════════════════

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
    final maxVal =
        [c, e, s, n].fold<double>(0, (a, b) => b.abs() > a ? b.abs() : a);

    return Column(
      children: [
        Expanded(
          child: BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceAround,
              maxY: maxVal * 1.2,
              minY: 0,
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  tooltipPadding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  tooltipMargin: 4,
                  getTooltipItem: (group, gI, rod, rI) {
                    return BarTooltipItem(
                      _fmtShort(rod.toY),
                      GoogleFonts.cairo(
                          fontSize: 9,
                          color: Colors.white,
                          fontWeight: FontWeight.bold),
                    );
                  },
                ),
              ),
              titlesData: FlTitlesData(
                leftTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (val, meta) {
                      final labels = ['تحصيلات', 'مصروفات', 'رواتب', 'صافي'];
                      final idx = val.toInt();
                      if (idx < 0 || idx >= labels.length)
                        return const SizedBox();
                      return Text(labels[idx],
                          style: GoogleFonts.cairo(
                              fontSize: 8, color: _textMuted));
                    },
                    reservedSize: 20,
                  ),
                ),
              ),
              borderData: FlBorderData(show: false),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: maxVal > 0 ? maxVal / 4 : 1,
                getDrawingHorizontalLine: (v) =>
                    FlLine(color: const Color(0x15000000), strokeWidth: 1),
              ),
              barGroups: [
                _bar(0, c.abs(), _clrTeal),
                _bar(1, e.abs(), _clrOrange),
                _bar(2, s.abs(), _clrPink),
                _bar(3, n.abs(), n >= 0 ? _clrGreen : _clrRed),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        // عدادات تحت المخطط
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _countBadge('${collections['MonthlyCount'] ?? 0}', _clrTeal),
            _countBadge('${expenses['MonthlyCount'] ?? 0}', _clrOrange),
            _countBadge('${salaries['MonthlyCount'] ?? 0}', _clrPink),
            const SizedBox(width: 18),
          ],
        ),
      ],
    );
  }

  Widget _countBadge(String count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(count,
          style: GoogleFonts.cairo(
              fontSize: 8, fontWeight: FontWeight.bold, color: color)),
    );
  }

  // ══════════════════════ CHART 4: PENDING (HORIZONTAL BAR) ══════════════════════

  Widget _buildPendingChart(
    Map<String, dynamic> collections,
    Map<String, dynamic> salaries,
    num agentNet,
    num techNet,
  ) {
    final items = [
      _HBarItem('تحصيلات غير مسلمة', _num(collections['PendingDelivery']),
          _clrPurple),
      _HBarItem('رواتب غير مصروفة', _num(salaries['UnpaidTotal']), _clrRed),
      _HBarItem(agentNet < 0 ? 'وكلاء (مدينون)' : 'وكلاء (دائنون)',
          agentNet.toDouble().abs(), agentNet < 0 ? _clrRed : _clrGreen),
      _HBarItem(techNet < 0 ? 'فنيين (مدينون)' : 'فنيين (دائنون)',
          techNet.toDouble().abs(), techNet < 0 ? _clrPurple : _clrGreen),
    ];

    final maxVal = items.fold<double>(0, (a, b) => b.value > a ? b.value : a);

    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: items.map((item) => _hBar(item, maxVal)).toList(),
    );
  }

  Widget _hBar(_HBarItem item, double maxVal) {
    final pct = maxVal > 0 ? (item.value / maxVal).clamp(0.0, 1.0) : 0.0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          SizedBox(
            width: 85,
            child: Text(item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.cairo(fontSize: 9, color: _textMuted)),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: LayoutBuilder(
              builder: (ctx, constraints) {
                return Stack(
                  children: [
                    Container(
                      height: 14,
                      decoration: BoxDecoration(
                        color: item.color.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 600),
                      height: 14,
                      width: constraints.maxWidth * pct,
                      decoration: BoxDecoration(
                        color: item.color.withOpacity(0.7),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(width: 4),
          SizedBox(
            width: 65,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerEnd,
              child: Text(_fmtShort(item.value),
                  style: GoogleFonts.cairo(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      color: _textDark)),
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
    final items = [
      _TotalItem(
          'إجمالي التحصيلات',
          _num(collections['TotalCollected']),
          '${collections['TotalCount'] ?? 0}',
          _clrGreen,
          Icons.monetization_on),
      _TotalItem('إجمالي المصروفات', _num(expenses['TotalExpenses']),
          '${expenses['TotalCount'] ?? 0}', _clrRed, Icons.receipt),
      _TotalItem('إجمالي الرواتب', _num(salaries['TotalSalaries']),
          '${salaries['TotalCount'] ?? 0}', _clrPink, Icons.payments),
      _TotalItem('عدد القيود', _num(journal['TotalCount']),
          'شهري: ${journal['MonthlyCount'] ?? 0}', _clrIndigo, Icons.menu_book),
    ];

    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: items.map((item) {
        return Row(
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: item.color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Icon(item.icon, color: item.color, size: 13),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.label,
                      style: GoogleFonts.cairo(fontSize: 9, color: _textMuted),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      item.label == 'عدد القيود'
                          ? item.value.toStringAsFixed(0)
                          : _fmtShort(item.value),
                      style: GoogleFonts.cairo(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: _textDark),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: item.color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(item.count,
                  style: GoogleFonts.cairo(
                      fontSize: 8,
                      fontWeight: FontWeight.bold,
                      color: item.color)),
            ),
          ],
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
          child: Text('لا توجد صناديق',
              style: GoogleFonts.cairo(color: _textMuted, fontSize: 10)));
    }

    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: boxes.length,
      separatorBuilder: (_, __) =>
          Divider(height: 1, color: Colors.white.withOpacity(0.08)),
      itemBuilder: (_, i) {
        final b = boxes[i];
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              Icon(Icons.inventory_2_outlined, color: _clrTeal, size: 14),
              const SizedBox(width: 4),
              Expanded(
                child: Text(b.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.cairo(fontSize: 10, color: _textDark)),
              ),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(_fmtShort(b.balance),
                    style: GoogleFonts.cairo(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: b.balance >= 0 ? _clrGreen : _clrRed)),
              ),
            ],
          ),
        );
      },
    );
  }

  // ══════════════════════ HELPERS ══════════════════════

  double _num(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0;
  }

  bool _isPositive(dynamic value) {
    return _num(value) >= 0;
  }

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

// ══════════════════════ ANIMATED BACKGROUND ══════════════════════

/// جسيمة عائمة في الخلفية
class _Particle {
  double x, y, radius, speed, opacity;
  Color color;
  double angle;

  _Particle({
    required this.x,
    required this.y,
    required this.radius,
    required this.speed,
    required this.opacity,
    required this.color,
    required this.angle,
  });

  factory _Particle.random(Random rng) {
    const colors = [
      Color(0xFF3498DB),
      Color(0xFF1ABC9C),
      Color(0xFF9B59B6),
      Color(0xFF2ECC71),
      Color(0xFFE67E22),
      Color(0xFF5C6BC0),
      Color(0xFF00BCD4),
    ];
    return _Particle(
      x: rng.nextDouble(),
      y: rng.nextDouble(),
      radius: rng.nextDouble() * 40 + 10,
      speed: rng.nextDouble() * 0.0003 + 0.0001,
      opacity: rng.nextDouble() * 0.08 + 0.03,
      color: colors[rng.nextInt(colors.length)],
      angle: rng.nextDouble() * 2 * pi,
    );
  }
}

/// رسام الخلفية المتحركة
class _AnimatedBgPainter extends CustomPainter {
  final double progress;
  final List<_Particle> particles;
  final double particleProgress;

  _AnimatedBgPainter({
    required this.progress,
    required this.particles,
    required this.particleProgress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // === التدرج الرئيسي المتحرك ===
    final angle = progress * 2 * pi;
    final shiftX = cos(angle) * 0.15;
    final shiftY = sin(angle * 0.7) * 0.1;

    final gradient = LinearGradient(
      begin: Alignment(-0.8 + shiftX, -1.0 + shiftY),
      end: Alignment(0.8 - shiftX, 1.0 - shiftY),
      colors: const [
        Color(0xFF0F1923), // أزرق داكن جداً
        Color(0xFF162A3A), // أزرق ليلي
        Color(0xFF1A2940), // أزرق غامق
        Color(0xFF0F2027), // أخضر مائي داكن
      ],
      stops: const [0.0, 0.35, 0.7, 1.0],
    );

    final bgPaint = Paint()
      ..shader =
          gradient.createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    // === موجات خفيفة ===
    _drawWave(canvas, size, progress, 0.4, const Color(0x08FFFFFF));
    _drawWave(canvas, size, progress * 1.3 + 0.5, 0.6, const Color(0x06FFFFFF));

    // === الجسيمات العائمة (فقاعات) ===
    for (final p in particles) {
      final t = (progress * 360 * p.speed + p.angle) % (2 * pi);
      final px = (p.x + sin(t) * 0.04) * size.width;
      final py = (p.y + cos(t * 0.8) * 0.03) * size.height;

      final particlePaint = Paint()
        ..color = p.color.withOpacity(p.opacity)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, p.radius * 0.6);
      canvas.drawCircle(Offset(px, py), p.radius, particlePaint);
    }

    // === وهج خفيف في الزاوية ===
    final glowX = size.width * (0.8 + cos(angle * 0.5) * 0.1);
    final glowY = size.height * (0.2 + sin(angle * 0.3) * 0.1);
    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0x0C3498DB),
          const Color(0x003498DB),
        ],
      ).createShader(
          Rect.fromCircle(center: Offset(glowX, glowY), radius: 250));
    canvas.drawCircle(Offset(glowX, glowY), 250, glowPaint);
  }

  void _drawWave(Canvas canvas, Size size, double t, double yPos, Color color) {
    final path = Path();
    path.moveTo(0, size.height);
    for (double x = 0; x <= size.width; x += 4) {
      final nx = x / size.width;
      final y = size.height * yPos +
          sin((nx * 4 * pi) + (t * 2 * pi)) * 15 +
          cos((nx * 2 * pi) + (t * 3 * pi)) * 8;
      if (x == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.lineTo(size.width, size.height);
    path.lineTo(0, size.height);
    path.close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _AnimatedBgPainter old) => true;
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
  _HBarItem(this.label, this.value, this.color);
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
