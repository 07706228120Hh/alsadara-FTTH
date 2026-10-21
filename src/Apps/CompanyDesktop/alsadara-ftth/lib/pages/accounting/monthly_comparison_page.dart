import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:fl_chart/fl_chart.dart';
import '../../services/accounting_service.dart';
import '../../services/accounting_export_service.dart';
import '../../theme/accounting_responsive.dart';
import '../../utils/responsive_helper.dart';
import '../../frontend/frontend.dart';

/// صفحة تقرير المقارنة الشهرية - مقارنة الإيرادات والمصروفات وصافي الربح عبر الأشهر
class MonthlyComparisonPage extends StatefulWidget {
  final String? companyId;

  const MonthlyComparisonPage({super.key, this.companyId});

  @override
  State<MonthlyComparisonPage> createState() => _MonthlyComparisonPageState();
}

class _MonthlyComparisonPageState extends State<MonthlyComparisonPage> {
  bool _isLoading = true;
  String? _errorMessage;
  int _monthCount = 6;
  List<Map<String, dynamic>> _monthlyData = [];

  final _currencyFmt = NumberFormat('#,##0', 'ar');

  static const List<String> _arabicMonths = [
    'يناير',
    'فبراير',
    'مارس',
    'أبريل',
    'مايو',
    'يونيو',
    'يوليو',
    'أغسطس',
    'سبتمبر',
    'أكتوبر',
    'نوفمبر',
    'ديسمبر',
  ];

  // ألوان دلالية موحّدة من نظام التصميم (إيراد=نجاح، مصروف=خطر، ربح=معلومة)
  static const _clrRevenue = SdColors.success;
  static const _clrExpenses = SdColors.danger;
  static const _clrProfit = SdColors.info;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  // ═══════════════════════════════════════════════════════════════
  // تحميل البيانات
  // ═══════════════════════════════════════════════════════════════

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final now = DateTime.now();
      final earliest = DateTime(now.year, now.month - _monthCount + 1, 1);
      final earliestStr =
          '${earliest.year}-${earliest.month.toString().padLeft(2, '0')}-01';
      final nowStr =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

      // جلب المصروفات والتحصيلات بالتوازي
      final results = await Future.wait([
        AccountingService.instance.getExpenses(
          companyId: widget.companyId,
          fromDate: earliestStr,
          toDate: nowStr,
        ),
        AccountingService.instance.getCollections(
          companyId: widget.companyId,
          isDelivered: true,
          fromDate: earliestStr,
          toDate: nowStr,
        ),
      ]);

      if (!mounted) return;

      final expensesResult = results[0];
      final collectionsResult = results[1];

      final expenses =
          (expensesResult['success'] == true && expensesResult['data'] is List)
              ? expensesResult['data'] as List
              : [];
      final collections = (collectionsResult['success'] == true &&
              collectionsResult['data'] is List)
          ? collectionsResult['data'] as List
          : [];

      // تجميع المصروفات حسب الشهر
      final expensesByMonth = <String, double>{};
      for (final e in expenses) {
        final dateStr = (e['ExpenseDate'] ?? e['CreatedAt'] ?? '').toString();
        final key = _extractMonthKey(dateStr);
        if (key != null) {
          expensesByMonth[key] =
              (expensesByMonth[key] ?? 0) + _toDouble(e['Amount']);
        }
      }

      // تجميع التحصيلات حسب الشهر (كبديل للإيرادات)
      final collectionsByMonth = <String, double>{};
      for (final c in collections) {
        final dateStr =
            (c['CollectionDate'] ?? c['DeliveryDate'] ?? c['CreatedAt'] ?? '')
                .toString();
        final key = _extractMonthKey(dateStr);
        if (key != null) {
          collectionsByMonth[key] =
              (collectionsByMonth[key] ?? 0) + _toDouble(c['Amount']);
        }
      }

      // بناء بيانات شهرية مرتبة
      final monthlyData = <Map<String, dynamic>>[];
      for (int i = 0; i < _monthCount; i++) {
        final month = DateTime(now.year, now.month - _monthCount + 1 + i, 1);
        final key = '${month.year}-${month.month.toString().padLeft(2, '0')}';
        final monthName = '${_arabicMonths[month.month - 1]} ${month.year}';
        final revenue = collectionsByMonth[key] ?? 0;
        final expense = expensesByMonth[key] ?? 0;
        final netIncome = revenue - expense;

        monthlyData.add({
          'month': monthName,
          'monthKey': key,
          'revenue': revenue,
          'expenses': expense,
          'netIncome': netIncome,
          'changePercent': null,
        });
      }

      // حساب نسبة التغير بين الأشهر
      for (int i = 1; i < monthlyData.length; i++) {
        final prev = monthlyData[i - 1]['netIncome'] as double;
        final curr = monthlyData[i]['netIncome'] as double;
        if (prev != 0) {
          monthlyData[i]['changePercent'] = ((curr - prev) / prev.abs()) * 100;
        }
      }

      setState(() {
        _monthlyData = monthlyData;
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

  String? _extractMonthKey(String dateStr) {
    if (dateStr.isEmpty) return null;
    try {
      final date = DateTime.parse(dateStr);
      return '${date.year}-${date.month.toString().padLeft(2, '0')}';
    } catch (_) {
      return null;
    }
  }

  double _toDouble(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0;
  }

  String _fmtCurrency(double value) {
    return '${_currencyFmt.format(value.abs())} د.ع';
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

  String _monthAbbrev(String monthKey) {
    try {
      final parts = monthKey.split('-');
      final monthIndex = int.parse(parts[1]) - 1;
      if (monthIndex >= 0 && monthIndex < _arabicMonths.length) {
        return _arabicMonths[monthIndex];
      }
    } catch (_) {}
    return monthKey;
  }

  // ═══════════════════════════════════════════════════════════════
  // التصدير
  // ═══════════════════════════════════════════════════════════════

  Future<void> _handleExport() async {
    if (_monthlyData.isEmpty) return;
    try {
      await AccountingExportService.exportMonthlyComparison(
        monthlyData: _monthlyData,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text('خطأ في التصدير', style: TextStyle(fontFamily: 'Cairo')),
          backgroundColor: SdColors.danger,
        ),
      );
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // البناء الرئيسي
  // ═══════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: SdColors.ground,
        appBar: SdAppBar(
          title: 'المقارنة الشهرية',
          actions: [
            SdAppBarAction(
              icon: Icons.file_download_outlined,
              label: 'تصدير Excel',
              onPressed: _handleExport,
            ),
            SdAppBarAction(
              icon: Icons.refresh,
              label: 'تحديث',
              onPressed: _isLoading ? null : _loadData,
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              _buildFilterBar(),
              Expanded(
                child: _isLoading
                    ? const Center(
                        child:
                            CircularProgressIndicator(color: SdColors.success))
                    : _errorMessage != null
                        ? Center(
                            child: SdEmptyState(
                              title: _errorMessage!,
                              icon: Icons.error_outline,
                              status: SdStatus.danger,
                              action: SdButton(
                                label: 'إعادة المحاولة',
                                icon: Icons.refresh,
                                onPressed: _loadData,
                              ),
                            ),
                          )
                        : _buildContent(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // شريط فلتر عدد الأشهر
  // ═══════════════════════════════════════════════════════════════

  Widget _buildFilterBar() {
    final ar = context.accR;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: ar.isMobile ? 10 : ar.spaceXL,
        vertical: 10,
      ),
      decoration: const BoxDecoration(
        color: SdColors.surface,
        border: Border(bottom: BorderSide(color: SdColors.divider)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: _buildMonthChips(ar),
      ),
    );
  }

  Widget _buildMonthChips(AccountingResponsive ar) {
    final isMob = ar.isMobile;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _monthChip(3, '3 أشهر', ar, isMob),
        SizedBox(width: isMob ? 4 : 6),
        _monthChip(6, '6 أشهر', ar, isMob),
        SizedBox(width: isMob ? 4 : 6),
        _monthChip(12, '12 شهر', ar, isMob),
      ],
    );
  }

  Widget _monthChip(
      int count, String label, AccountingResponsive ar, bool isMob) {
    final isSelected = _monthCount == count;
    return InkWell(
      onTap: () {
        if (_monthCount != count) {
          setState(() => _monthCount = count);
          _loadData();
        }
      },
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: isMob ? 10 : 14,
          vertical: isMob ? 4 : 6,
        ),
        decoration: BoxDecoration(
          color: isSelected ? SdColors.primary : SdColors.groundAlt,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? SdColors.primary : SdColors.divider,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'Cairo',
            fontSize: isMob ? 11 : ar.small,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? Colors.white : SdColors.muted,
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // المحتوى الرئيسي
  // ═══════════════════════════════════════════════════════════════

  Widget _buildContent() {
    if (_monthlyData.isEmpty) {
      return const Center(
        child: SdEmptyState(
          title: 'لا توجد بيانات للفترة المحددة',
          icon: Icons.bar_chart_rounded,
        ),
      );
    }

    final isMob = context.responsive.isMobile;

    return SingleChildScrollView(
      padding: EdgeInsets.all(isMob ? 10 : 20),
      child: Column(
        children: [
          _buildBarChart(),
          SizedBox(height: isMob ? 12 : 20),
          _buildSummaryRow(),
          SizedBox(height: isMob ? 12 : 20),
          _buildDataTable(),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // مخطط الأعمدة
  // ═══════════════════════════════════════════════════════════════

  Widget _buildBarChart() {
    final ar = context.accR;
    final isMob = ar.isMobile;
    final chartHeight = isMob ? 200.0 : 250.0;

    // حساب القيمة القصوى للمحور Y
    double maxValue = 0;
    for (final m in _monthlyData) {
      final rev = (m['revenue'] as double).abs();
      final exp = (m['expenses'] as double).abs();
      if (rev > maxValue) maxValue = rev;
      if (exp > maxValue) maxValue = exp;
    }
    if (maxValue == 0) maxValue = 1000;
    final maxY = maxValue * 1.2;

    final barWidth = isMob
        ? (120 / _monthlyData.length).clamp(6.0, 14.0)
        : (200 / _monthlyData.length).clamp(10.0, 22.0);

    return Container(
      padding: EdgeInsets.all(isMob ? 10 : 16),
      decoration: BoxDecoration(
        color: SdColors.surface,
        borderRadius: BorderRadius.circular(ar.cardRadius),
        boxShadow: SdUiKit.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // عنوان المخطط ومفتاح الألوان
          Row(
            children: [
              Text(
                'مقارنة الإيرادات والمصروفات',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: isMob ? 13 : ar.headingSmall,
                  fontWeight: FontWeight.bold,
                  color: SdColors.ink,
                ),
              ),
              const Spacer(),
              _legendDot(_clrRevenue, 'إيرادات', ar, isMob),
              SizedBox(width: isMob ? 8 : 14),
              _legendDot(_clrExpenses, 'مصروفات', ar, isMob),
            ],
          ),
          SizedBox(height: isMob ? 10 : 16),
          SizedBox(
            height: chartHeight,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: maxY,
                minY: 0,
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    tooltipPadding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    tooltipMargin: 6,
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      final label = rodIndex == 0 ? 'إيرادات' : 'مصروفات';
                      return BarTooltipItem(
                        '$label\n${_fmtCurrency(rod.toY)}',
                        TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: ar.caption,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      );
                    },
                  ),
                ),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: isMob ? 45 : 60,
                      getTitlesWidget: (value, meta) {
                        if (value == meta.max || value == meta.min) {
                          return const SizedBox.shrink();
                        }
                        return Text(
                          _fmtShort(value),
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: isMob ? 8 : 10,
                            color: SdColors.faint,
                          ),
                        );
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: isMob ? 24 : 30,
                      getTitlesWidget: (value, meta) {
                        final idx = value.toInt();
                        if (idx < 0 || idx >= _monthlyData.length) {
                          return const SizedBox.shrink();
                        }
                        final key = _monthlyData[idx]['monthKey'] as String;
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            _monthAbbrev(key),
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: isMob ? 8 : 10,
                              color: SdColors.faint,
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
                  horizontalInterval: maxValue > 0 ? maxValue / 4 : 1,
                  getDrawingHorizontalLine: (v) => FlLine(
                    color: const Color(0x15000000),
                    strokeWidth: 1,
                  ),
                ),
                barGroups: _monthlyData.asMap().entries.map((e) {
                  final rev = (e.value['revenue'] as double).abs();
                  final exp = (e.value['expenses'] as double).abs();
                  return BarChartGroupData(
                    x: e.key,
                    barRods: [
                      BarChartRodData(
                        toY: rev,
                        color: _clrRevenue,
                        width: barWidth,
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(4)),
                      ),
                      BarChartRodData(
                        toY: exp,
                        color: _clrExpenses,
                        width: barWidth,
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(4)),
                      ),
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

  Widget _legendDot(
      Color color, String label, AccountingResponsive ar, bool isMob) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: isMob ? 8 : 10,
          height: isMob ? 8 : 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontFamily: 'Cairo',
            fontSize: isMob ? 10 : ar.small,
            color: SdColors.muted,
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // صف الملخص
  // ═══════════════════════════════════════════════════════════════

  Widget _buildSummaryRow() {
    final ar = context.accR;
    final isMob = ar.isMobile;

    double totalRevenue = 0;
    double totalExpenses = 0;
    int countWithData = 0;
    double totalNetIncome = 0;

    for (final m in _monthlyData) {
      totalRevenue += m['revenue'] as double;
      totalExpenses += m['expenses'] as double;
      totalNetIncome += m['netIncome'] as double;
      if ((m['revenue'] as double) > 0 || (m['expenses'] as double) > 0) {
        countWithData++;
      }
    }

    final avgNetIncome =
        countWithData > 0 ? totalNetIncome / countWithData : 0.0;

    if (isMob) {
      return Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _summaryCard(
                  'إجمالي الإيرادات',
                  totalRevenue,
                  _clrRevenue,
                  Icons.trending_up_rounded,
                  ar,
                  isMob,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _summaryCard(
                  'إجمالي المصروفات',
                  totalExpenses,
                  _clrExpenses,
                  Icons.trending_down_rounded,
                  ar,
                  isMob,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _summaryCard(
            'متوسط صافي الربح',
            avgNetIncome,
            avgNetIncome >= 0 ? _clrProfit : _clrExpenses,
            Icons.analytics_rounded,
            ar,
            isMob,
          ),
        ],
      );
    }

    return Row(
      children: [
        Expanded(
          child: _summaryCard(
            'إجمالي الإيرادات',
            totalRevenue,
            _clrRevenue,
            Icons.trending_up_rounded,
            ar,
            isMob,
          ),
        ),
        SizedBox(width: ar.spaceM),
        Expanded(
          child: _summaryCard(
            'إجمالي المصروفات',
            totalExpenses,
            _clrExpenses,
            Icons.trending_down_rounded,
            ar,
            isMob,
          ),
        ),
        SizedBox(width: ar.spaceM),
        Expanded(
          child: _summaryCard(
            'متوسط صافي الربح',
            avgNetIncome,
            avgNetIncome >= 0 ? _clrProfit : _clrExpenses,
            Icons.analytics_rounded,
            ar,
            isMob,
          ),
        ),
      ],
    );
  }

  Widget _summaryCard(String title, double value, Color color, IconData icon,
      AccountingResponsive ar, bool isMob) {
    return Container(
      padding: EdgeInsets.all(isMob ? 10 : ar.cardPad),
      decoration: BoxDecoration(
        color: SdColors.surface,
        borderRadius: BorderRadius.circular(ar.cardRadius),
        boxShadow: SdUiKit.cardShadow,
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: isMob ? 16 : ar.iconS),
              SizedBox(width: isMob ? 4 : 6),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: isMob ? 10 : ar.small,
                    color: SdColors.faint,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          SizedBox(height: isMob ? 4 : 8),
          Text(
            _fmtCurrency(value),
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: isMob ? 14 : ar.financialMedium,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // جدول البيانات
  // ═══════════════════════════════════════════════════════════════

  Widget _buildDataTable() {
    final ar = context.accR;
    final isMob = ar.isMobile;

    // حساب الإجماليات
    double totalRevenue = 0;
    double totalExpenses = 0;
    double totalNetIncome = 0;
    for (final m in _monthlyData) {
      totalRevenue += m['revenue'] as double;
      totalExpenses += m['expenses'] as double;
      totalNetIncome += m['netIncome'] as double;
    }

    return Container(
      decoration: BoxDecoration(
        color: SdColors.surface,
        borderRadius: BorderRadius.circular(ar.cardRadius),
        boxShadow: SdUiKit.cardShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: isMob ? 400 : MediaQuery.of(context).size.width - 40,
          ),
          child: Column(
            children: [
              // رأس الجدول
              _buildTableHeader(ar, isMob),
              // صفوف البيانات
              ...List.generate(_monthlyData.length, (i) {
                return _buildTableRow(_monthlyData[i], i, ar, isMob);
              }),
              // صف الإجماليات
              _buildTotalsRow(
                  totalRevenue, totalExpenses, totalNetIncome, ar, isMob),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTableHeader(AccountingResponsive ar, bool isMob) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isMob ? 8 : ar.tableCellPadH,
        vertical: isMob ? 8 : ar.tableCellPadV + 4,
      ),
      decoration: const BoxDecoration(
        color: SdColors.primary,
      ),
      child: Row(
        children: [
          _headerCell('الشهر', ar, isMob, flex: 2),
          _headerCell('الإيرادات', ar, isMob),
          _headerCell('المصروفات', ar, isMob),
          _headerCell('صافي الربح', ar, isMob),
          if (!isMob) _headerCell('التغير %', ar, isMob),
        ],
      ),
    );
  }

  Widget _headerCell(String text, AccountingResponsive ar, bool isMob,
      {int flex = 1}) {
    return Expanded(
      flex: flex,
      child: Text(
        text,
        style: TextStyle(
          fontFamily: 'Cairo',
          fontSize: isMob ? 10 : ar.tableHeaderFont,
          fontWeight: FontWeight.bold,
          color: SdColors.surface,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildTableRow(Map<String, dynamic> data, int index,
      AccountingResponsive ar, bool isMob) {
    final revenue = data['revenue'] as double;
    final expenses = data['expenses'] as double;
    final netIncome = data['netIncome'] as double;
    final changePercent = data['changePercent'] as double?;
    final isEven = index % 2 == 0;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isMob ? 8 : ar.tableCellPadH,
        vertical: isMob ? 8 : ar.tableCellPadV + 2,
      ),
      decoration: BoxDecoration(
        color: isEven ? Colors.transparent : SdColors.surfaceAlt,
        border: const Border(
          bottom: BorderSide(color: SdColors.divider, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          // الشهر
          Expanded(
            flex: 2,
            child: Text(
              data['month'] as String,
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: isMob ? 10 : ar.tableCellFont,
                fontWeight: FontWeight.w600,
                color: SdColors.ink,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          // الإيرادات
          Expanded(
            child: Text(
              _fmtCurrency(revenue),
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: isMob ? 10 : ar.tableCellFont,
                color: _clrRevenue,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          // المصروفات
          Expanded(
            child: Text(
              _fmtCurrency(expenses),
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: isMob ? 10 : ar.tableCellFont,
                color: _clrExpenses,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          // صافي الربح
          Expanded(
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: isMob ? 4 : 8,
                vertical: 2,
              ),
              decoration: BoxDecoration(
                color: netIncome >= 0
                    ? _clrRevenue.withOpacity(0.08)
                    : _clrExpenses.withOpacity(0.08),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                _fmtCurrency(netIncome),
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: isMob ? 10 : ar.tableCellFont,
                  fontWeight: FontWeight.bold,
                  color: netIncome >= 0 ? _clrRevenue : _clrExpenses,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          // التغير %
          if (!isMob)
            Expanded(
              child: changePercent != null
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          changePercent >= 0
                              ? Icons.arrow_upward_rounded
                              : Icons.arrow_downward_rounded,
                          size: 14,
                          color:
                              changePercent >= 0 ? _clrRevenue : _clrExpenses,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          '${changePercent.abs().toStringAsFixed(1)}%',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: ar.tableCellFont,
                            fontWeight: FontWeight.w600,
                            color:
                                changePercent >= 0 ? _clrRevenue : _clrExpenses,
                          ),
                        ),
                      ],
                    )
                  : Text(
                      '-',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: ar.tableCellFont,
                        color: SdColors.faint,
                      ),
                      textAlign: TextAlign.center,
                    ),
            ),
        ],
      ),
    );
  }

  Widget _buildTotalsRow(double totalRevenue, double totalExpenses,
      double totalNetIncome, AccountingResponsive ar, bool isMob) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isMob ? 8 : ar.tableCellPadH,
        vertical: isMob ? 10 : ar.tableCellPadV + 4,
      ),
      decoration: BoxDecoration(
        color: SdColors.groundAlt,
        border: const Border(
          top: BorderSide(color: SdColors.divider, width: 1.5),
        ),
      ),
      child: Row(
        children: [
          // المجموع
          Expanded(
            flex: 2,
            child: Text(
              'الإجمالي',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: isMob ? 11 : ar.tableCellFont + 1,
                fontWeight: FontWeight.bold,
                color: SdColors.ink,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          // إجمالي الإيرادات
          Expanded(
            child: Text(
              _fmtCurrency(totalRevenue),
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: isMob ? 10 : ar.tableCellFont,
                fontWeight: FontWeight.bold,
                color: _clrRevenue,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          // إجمالي المصروفات
          Expanded(
            child: Text(
              _fmtCurrency(totalExpenses),
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: isMob ? 10 : ar.tableCellFont,
                fontWeight: FontWeight.bold,
                color: _clrExpenses,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          // إجمالي صافي الربح
          Expanded(
            child: Text(
              _fmtCurrency(totalNetIncome),
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: isMob ? 10 : ar.tableCellFont,
                fontWeight: FontWeight.bold,
                color: totalNetIncome >= 0 ? _clrRevenue : _clrExpenses,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          // عمود فارغ للتغير %
          if (!isMob)
            Expanded(
              child: Text(
                '-',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: ar.tableCellFont,
                  color: SdColors.faint,
                ),
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
    );
  }
}
