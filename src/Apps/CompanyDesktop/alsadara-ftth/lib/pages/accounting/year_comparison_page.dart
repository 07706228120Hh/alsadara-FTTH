import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:fl_chart/fl_chart.dart';
import '../../theme/accounting_theme.dart';
import '../../theme/accounting_responsive.dart';
import '../../services/accounting_service.dart';

/// صفحة المقارنة السنوية - مقارنة الإيرادات والمصروفات بين سنتين
class YearComparisonPage extends StatefulWidget {
  final String? companyId;

  const YearComparisonPage({super.key, this.companyId});

  @override
  State<YearComparisonPage> createState() => _YearComparisonPageState();
}

class _YearComparisonPageState extends State<YearComparisonPage> {
  int _year1 = DateTime.now().year - 1; // السنة السابقة
  int _year2 = DateTime.now().year; // السنة الحالية
  bool _isLoading = true;
  String? _errorMessage;
  List<Map<String, dynamic>> _comparisonData = []; // 12 شهر من البيانات

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

  static const _clrYear1 = Color(0xFF27AE60); // أخضر - السنة الأولى
  static const _clrYear2 = Color(0xFF2980B9); // أزرق - السنة الثانية
  static const _clrExpenses = Color(0xFFE74C3C); // أحمر - للمصروفات
  static const _clrPositive = Color(0xFF27AE60);
  static const _clrNegative = Color(0xFFE74C3C);

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
      // جلب المصروفات والتحصيلات لكلا السنتين بالتوازي
      final results = await Future.wait([
        AccountingService.instance.getExpenses(
          companyId: widget.companyId,
          fromDate: '$_year1-01-01',
          toDate: '$_year1-12-31',
        ),
        AccountingService.instance.getCollections(
          companyId: widget.companyId,
          isDelivered: true,
          fromDate: '$_year1-01-01',
          toDate: '$_year1-12-31',
        ),
        AccountingService.instance.getExpenses(
          companyId: widget.companyId,
          fromDate: '$_year2-01-01',
          toDate: '$_year2-12-31',
        ),
        AccountingService.instance.getCollections(
          companyId: widget.companyId,
          isDelivered: true,
          fromDate: '$_year2-01-01',
          toDate: '$_year2-12-31',
        ),
      ]);

      if (!mounted) return;

      final expensesY1 = results[0];
      final collectionsY1 = results[1];
      final expensesY2 = results[2];
      final collectionsY2 = results[3];

      // تجميع المصروفات والتحصيلات حسب الشهر لكل سنة
      final expensesByMonthY1 = _groupByMonth(
        (expensesY1['success'] == true && expensesY1['data'] is List)
            ? expensesY1['data'] as List
            : [],
        'ExpenseDate',
      );
      final collectionsByMonthY1 = _groupByMonth(
        (collectionsY1['success'] == true && collectionsY1['data'] is List)
            ? collectionsY1['data'] as List
            : [],
        'CollectionDate',
      );
      final expensesByMonthY2 = _groupByMonth(
        (expensesY2['success'] == true && expensesY2['data'] is List)
            ? expensesY2['data'] as List
            : [],
        'ExpenseDate',
      );
      final collectionsByMonthY2 = _groupByMonth(
        (collectionsY2['success'] == true && collectionsY2['data'] is List)
            ? collectionsY2['data'] as List
            : [],
        'CollectionDate',
      );

      // بناء بيانات المقارنة لكل شهر
      _comparisonData = List.generate(12, (i) {
        final month = i + 1;
        final monthKey = month.toString().padLeft(2, '0');
        final monthName = _arabicMonths[i];

        final revenue1 = collectionsByMonthY1[monthKey] ?? 0.0;
        final revenue2 = collectionsByMonthY2[monthKey] ?? 0.0;
        final expenses1 = expensesByMonthY1[monthKey] ?? 0.0;
        final expenses2 = expensesByMonthY2[monthKey] ?? 0.0;

        double revenueChange = 0;
        if (revenue1 != 0) {
          revenueChange = ((revenue2 - revenue1) / revenue1.abs()) * 100;
        }

        double expenseChange = 0;
        if (expenses1 != 0) {
          expenseChange = ((expenses2 - expenses1) / expenses1.abs()) * 100;
        }

        return {
          'month': month,
          'monthName': monthName,
          'revenue1': revenue1,
          'revenue2': revenue2,
          'expenses1': expenses1,
          'expenses2': expenses2,
          'revenueChange': revenueChange,
          'expenseChange': expenseChange,
        };
      });

      setState(() {
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

  /// تجميع المبالغ حسب الشهر
  Map<String, double> _groupByMonth(List items, String dateField) {
    final result = <String, double>{};
    for (final item in items) {
      final dateStr =
          (item[dateField] ?? item['DeliveryDate'] ?? item['CreatedAt'] ?? '')
              .toString();
      final monthKey = _extractMonth(dateStr);
      if (monthKey != null) {
        result[monthKey] = (result[monthKey] ?? 0) + _toDouble(item['Amount']);
      }
    }
    return result;
  }

  String? _extractMonth(String dateStr) {
    if (dateStr.isEmpty) return null;
    try {
      final date = DateTime.parse(dateStr);
      return date.month.toString().padLeft(2, '0');
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

  // ═══════════════════════════════════════════════════════════════
  // البناء الرئيسي
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
                            color: AccountingTheme.neonGreen))
                    : _errorMessage != null
                        ? AccountingTheme.errorView(_errorMessage!, _loadData)
                        : _buildContent(),
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

  Widget _buildToolbar() {
    final ar = context.accR;
    final isMob = ar.isMobile;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isMob ? 8 : ar.spaceXL,
        vertical: isMob ? 6 : ar.spaceL,
      ),
      decoration: const BoxDecoration(
        color: AccountingTheme.bgCard,
        border: Border(bottom: BorderSide(color: AccountingTheme.borderColor)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: Icon(Icons.arrow_forward_rounded,
                    size: isMob ? 20 : 24),
                tooltip: 'رجوع',
                style: IconButton.styleFrom(
                    foregroundColor: AccountingTheme.textSecondary),
              ),
              SizedBox(width: isMob ? 4 : ar.spaceS),
              Container(
                padding: EdgeInsets.all(isMob ? 4 : ar.spaceS),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF8E44AD), Color(0xFF7D3C98)],
                  ),
                  borderRadius: BorderRadius.circular(isMob ? 6 : 8),
                ),
                child: Icon(Icons.calendar_view_month_rounded,
                    color: Colors.white, size: isMob ? 16 : ar.iconM),
              ),
              SizedBox(width: isMob ? 6 : ar.spaceM),
              Expanded(
                child: Text(
                  'المقارنة السنوية',
                  style: GoogleFonts.cairo(
                    fontSize: isMob ? 14 : ar.headingMedium,
                    fontWeight: FontWeight.bold,
                    color: AccountingTheme.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (!isMob) ...[
                _buildYearDropdowns(ar, isMob),
                SizedBox(width: ar.spaceM),
              ],
              IconButton(
                onPressed: _loadData,
                icon: Icon(Icons.refresh, size: isMob ? 18 : ar.iconM),
                tooltip: 'تحديث',
                style: IconButton.styleFrom(
                    foregroundColor: AccountingTheme.textSecondary),
              ),
            ],
          ),
          if (isMob) ...[
            const SizedBox(height: 6),
            _buildYearDropdowns(ar, isMob),
          ],
        ],
      ),
    );
  }

  Widget _buildYearDropdowns(AccountingResponsive ar, bool isMob) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _yearDropdown(
          label: 'السنة 1',
          value: _year1,
          color: _clrYear1,
          isMob: isMob,
          ar: ar,
          onChanged: (v) {
            if (v != null && v != _year1) {
              setState(() => _year1 = v);
              _loadData();
            }
          },
        ),
        SizedBox(width: isMob ? 8 : 12),
        Icon(Icons.compare_arrows_rounded,
            color: AccountingTheme.textMuted,
            size: isMob ? 16 : 20),
        SizedBox(width: isMob ? 8 : 12),
        _yearDropdown(
          label: 'السنة 2',
          value: _year2,
          color: _clrYear2,
          isMob: isMob,
          ar: ar,
          onChanged: (v) {
            if (v != null && v != _year2) {
              setState(() => _year2 = v);
              _loadData();
            }
          },
        ),
      ],
    );
  }

  Widget _yearDropdown({
    required String label,
    required int value,
    required Color color,
    required bool isMob,
    required AccountingResponsive ar,
    required ValueChanged<int?> onChanged,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isMob ? 8 : 12,
        vertical: isMob ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(isMob ? 6 : 8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: GoogleFonts.cairo(
              fontSize: isMob ? 10 : ar.small,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(width: isMob ? 4 : 6),
          DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: value,
              isDense: true,
              style: GoogleFonts.cairo(
                fontSize: isMob ? 12 : ar.body,
                fontWeight: FontWeight.bold,
                color: color,
              ),
              icon: Icon(Icons.arrow_drop_down, color: color, size: 18),
              items: List.generate(11, (i) => 2020 + i)
                  .map((y) => DropdownMenuItem(
                        value: y,
                        child: Text('$y'),
                      ))
                  .toList(),
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // المحتوى الرئيسي
  // ═══════════════════════════════════════════════════════════════

  Widget _buildContent() {
    if (_comparisonData.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.bar_chart_rounded,
                size: 64, color: AccountingTheme.textMuted.withOpacity(0.4)),
            const SizedBox(height: 16),
            Text(
              'لا توجد بيانات للفترة المحددة',
              style: GoogleFonts.cairo(
                fontSize: 14,
                color: AccountingTheme.textMuted,
              ),
            ),
          ],
        ),
      );
    }

    final isMob = context.accR.isMobile;

    return SingleChildScrollView(
      padding: EdgeInsets.all(isMob ? 10 : 20),
      child: Column(
        children: [
          _buildSummaryCards(),
          SizedBox(height: isMob ? 12 : 20),
          _buildBarChart(),
          SizedBox(height: isMob ? 12 : 20),
          _buildDataTable(),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // بطاقات الملخص
  // ═══════════════════════════════════════════════════════════════

  Widget _buildSummaryCards() {
    final ar = context.accR;
    final isMob = ar.isMobile;

    double totalRevY1 = 0, totalRevY2 = 0;
    double totalExpY1 = 0, totalExpY2 = 0;

    for (final m in _comparisonData) {
      totalRevY1 += m['revenue1'] as double;
      totalRevY2 += m['revenue2'] as double;
      totalExpY1 += m['expenses1'] as double;
      totalExpY2 += m['expenses2'] as double;
    }

    final revChange =
        totalRevY1 != 0 ? ((totalRevY2 - totalRevY1) / totalRevY1.abs()) * 100 : 0.0;
    final expChange =
        totalExpY1 != 0 ? ((totalExpY2 - totalExpY1) / totalExpY1.abs()) * 100 : 0.0;
    final netY1 = totalRevY1 - totalExpY1;
    final netY2 = totalRevY2 - totalExpY2;
    final netChange =
        netY1 != 0 ? ((netY2 - netY1) / netY1.abs()) * 100 : 0.0;

    if (isMob) {
      return Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _summaryCard(
                  'إيرادات $_year1',
                  totalRevY1,
                  _clrYear1,
                  Icons.trending_up_rounded,
                  ar,
                  isMob,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _summaryCard(
                  'إيرادات $_year2',
                  totalRevY2,
                  _clrYear2,
                  Icons.trending_up_rounded,
                  ar,
                  isMob,
                  changePercent: revChange,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _summaryCard(
                  'صافي $_year1',
                  netY1,
                  netY1 >= 0 ? _clrPositive : _clrNegative,
                  Icons.account_balance_wallet_rounded,
                  ar,
                  isMob,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _summaryCard(
                  'صافي $_year2',
                  netY2,
                  netY2 >= 0 ? _clrPositive : _clrNegative,
                  Icons.account_balance_wallet_rounded,
                  ar,
                  isMob,
                  changePercent: netChange,
                ),
              ),
            ],
          ),
        ],
      );
    }

    return Row(
      children: [
        Expanded(
          child: _summaryCard(
            'إيرادات $_year1',
            totalRevY1,
            _clrYear1,
            Icons.trending_up_rounded,
            ar,
            isMob,
          ),
        ),
        SizedBox(width: ar.spaceM),
        Expanded(
          child: _summaryCard(
            'إيرادات $_year2',
            totalRevY2,
            _clrYear2,
            Icons.trending_up_rounded,
            ar,
            isMob,
            changePercent: revChange,
          ),
        ),
        SizedBox(width: ar.spaceM),
        Expanded(
          child: _summaryCard(
            'صافي $_year1',
            netY1,
            netY1 >= 0 ? _clrPositive : _clrNegative,
            Icons.account_balance_wallet_rounded,
            ar,
            isMob,
          ),
        ),
        SizedBox(width: ar.spaceM),
        Expanded(
          child: _summaryCard(
            'صافي $_year2',
            netY2,
            netY2 >= 0 ? _clrPositive : _clrNegative,
            Icons.account_balance_wallet_rounded,
            ar,
            isMob,
            changePercent: netChange,
          ),
        ),
      ],
    );
  }

  Widget _summaryCard(
    String title,
    double value,
    Color color,
    IconData icon,
    AccountingResponsive ar,
    bool isMob, {
    double? changePercent,
  }) {
    return Container(
      padding: EdgeInsets.all(isMob ? 10 : ar.cardPad),
      decoration: BoxDecoration(
        color: AccountingTheme.bgCard,
        borderRadius: BorderRadius.circular(ar.cardRadius),
        boxShadow: AccountingTheme.cardShadow,
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
                  style: GoogleFonts.cairo(
                    fontSize: isMob ? 10 : ar.small,
                    color: AccountingTheme.textMuted,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (changePercent != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: changePercent >= 0
                        ? _clrPositive.withOpacity(0.1)
                        : _clrNegative.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        changePercent >= 0
                            ? Icons.arrow_upward_rounded
                            : Icons.arrow_downward_rounded,
                        size: isMob ? 10 : 12,
                        color: changePercent >= 0
                            ? _clrPositive
                            : _clrNegative,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        '${changePercent.abs().toStringAsFixed(1)}%',
                        style: GoogleFonts.cairo(
                          fontSize: isMob ? 9 : 10,
                          fontWeight: FontWeight.bold,
                          color: changePercent >= 0
                              ? _clrPositive
                              : _clrNegative,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          SizedBox(height: isMob ? 4 : 8),
          Text(
            _fmtCurrency(value),
            style: GoogleFonts.cairo(
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
  // مخطط الأعمدة المجمع
  // ═══════════════════════════════════════════════════════════════

  Widget _buildBarChart() {
    final ar = context.accR;
    final isMob = ar.isMobile;
    final chartHeight = isMob ? 220.0 : 280.0;

    // حساب القيمة القصوى للمحور Y
    double maxValue = 0;
    for (final m in _comparisonData) {
      final r1 = (m['revenue1'] as double).abs();
      final r2 = (m['revenue2'] as double).abs();
      if (r1 > maxValue) maxValue = r1;
      if (r2 > maxValue) maxValue = r2;
    }
    if (maxValue == 0) maxValue = 1000;
    final maxY = maxValue * 1.2;

    final barWidth = isMob ? 6.0 : 10.0;

    return Container(
      padding: EdgeInsets.all(isMob ? 10 : 16),
      decoration: BoxDecoration(
        color: AccountingTheme.bgCard,
        borderRadius: BorderRadius.circular(ar.cardRadius),
        boxShadow: AccountingTheme.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // عنوان المخطط ومفتاح الألوان
          Row(
            children: [
              Text(
                'مقارنة الإيرادات الشهرية',
                style: GoogleFonts.cairo(
                  fontSize: isMob ? 13 : ar.headingSmall,
                  fontWeight: FontWeight.bold,
                  color: AccountingTheme.textPrimary,
                ),
              ),
              const Spacer(),
              _legendDot(_clrYear1, '$_year1', ar, isMob),
              SizedBox(width: isMob ? 8 : 14),
              _legendDot(_clrYear2, '$_year2', ar, isMob),
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
                    tooltipPadding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    tooltipMargin: 6,
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      final year = rodIndex == 0 ? '$_year1' : '$_year2';
                      final monthName = _arabicMonths[group.x];
                      return BarTooltipItem(
                        '$monthName - $year\n${_fmtCurrency(rod.toY)}',
                        GoogleFonts.cairo(
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
                          style: GoogleFonts.cairo(
                            fontSize: isMob ? 8 : 10,
                            color: AccountingTheme.textMuted,
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
                        if (idx < 0 || idx >= 12) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            _arabicMonths[idx],
                            style: GoogleFonts.cairo(
                              fontSize: isMob ? 7 : 9,
                              color: AccountingTheme.textMuted,
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
                barGroups: List.generate(12, (i) {
                  final data = _comparisonData[i];
                  final r1 = (data['revenue1'] as double).abs();
                  final r2 = (data['revenue2'] as double).abs();
                  return BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: r1,
                        color: _clrYear1,
                        width: barWidth,
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(3)),
                      ),
                      BarChartRodData(
                        toY: r2,
                        color: _clrYear2,
                        width: barWidth,
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(3)),
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
          style: GoogleFonts.cairo(
            fontSize: isMob ? 10 : ar.small,
            color: AccountingTheme.textSecondary,
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // جدول البيانات
  // ═══════════════════════════════════════════════════════════════

  Widget _buildDataTable() {
    final ar = context.accR;
    final isMob = ar.isMobile;

    // حساب الإجماليات
    double totalRevY1 = 0, totalRevY2 = 0;
    double totalExpY1 = 0, totalExpY2 = 0;
    for (final m in _comparisonData) {
      totalRevY1 += m['revenue1'] as double;
      totalRevY2 += m['revenue2'] as double;
      totalExpY1 += m['expenses1'] as double;
      totalExpY2 += m['expenses2'] as double;
    }

    return Container(
      decoration: BoxDecoration(
        color: AccountingTheme.bgCard,
        borderRadius: BorderRadius.circular(ar.cardRadius),
        boxShadow: AccountingTheme.cardShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: isMob ? 700 : MediaQuery.of(context).size.width - 80,
          ),
          child: Column(
            children: [
              _buildTableHeader(ar, isMob),
              ...List.generate(12, (i) {
                return _buildTableRow(_comparisonData[i], i, ar, isMob);
              }),
              _buildTotalsRow(
                  totalRevY1, totalRevY2, totalExpY1, totalExpY2, ar, isMob),
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
        color: AccountingTheme.tableHeaderBg,
      ),
      child: Row(
        children: [
          _headerCell('الشهر', ar, isMob, flex: 2),
          _headerCell('إيرادات $_year1', ar, isMob),
          _headerCell('إيرادات $_year2', ar, isMob),
          _headerCell('التغيير %', ar, isMob),
          _headerCell('مصاريف $_year1', ar, isMob),
          _headerCell('مصاريف $_year2', ar, isMob),
          _headerCell('التغيير %', ar, isMob),
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
        style: GoogleFonts.cairo(
          fontSize: isMob ? 10 : ar.tableHeaderFont,
          fontWeight: FontWeight.bold,
          color: AccountingTheme.tableHeaderText,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildTableRow(
      Map<String, dynamic> data, int index, AccountingResponsive ar, bool isMob) {
    final revenue1 = data['revenue1'] as double;
    final revenue2 = data['revenue2'] as double;
    final expenses1 = data['expenses1'] as double;
    final expenses2 = data['expenses2'] as double;
    final revenueChange = data['revenueChange'] as double;
    final expenseChange = data['expenseChange'] as double;
    final isEven = index % 2 == 0;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isMob ? 8 : ar.tableCellPadH,
        vertical: isMob ? 8 : ar.tableCellPadV + 2,
      ),
      decoration: BoxDecoration(
        color: isEven ? Colors.transparent : AccountingTheme.tableRowAlt,
        border: const Border(
          bottom: BorderSide(color: AccountingTheme.borderColor, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          // الشهر
          Expanded(
            flex: 2,
            child: Text(
              data['monthName'] as String,
              style: GoogleFonts.cairo(
                fontSize: isMob ? 10 : ar.tableCellFont,
                fontWeight: FontWeight.w600,
                color: AccountingTheme.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          // إيرادات سنة 1
          Expanded(
            child: Text(
              _fmtCurrency(revenue1),
              style: GoogleFonts.cairo(
                fontSize: isMob ? 10 : ar.tableCellFont,
                color: _clrYear1,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          // إيرادات سنة 2
          Expanded(
            child: Text(
              _fmtCurrency(revenue2),
              style: GoogleFonts.cairo(
                fontSize: isMob ? 10 : ar.tableCellFont,
                color: _clrYear2,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          // نسبة تغيير الإيرادات
          Expanded(
            child: _changeCell(revenueChange, ar, isMob),
          ),
          // مصاريف سنة 1
          Expanded(
            child: Text(
              _fmtCurrency(expenses1),
              style: GoogleFonts.cairo(
                fontSize: isMob ? 10 : ar.tableCellFont,
                color: _clrExpenses.withOpacity(0.7),
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          // مصاريف سنة 2
          Expanded(
            child: Text(
              _fmtCurrency(expenses2),
              style: GoogleFonts.cairo(
                fontSize: isMob ? 10 : ar.tableCellFont,
                color: _clrExpenses,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          // نسبة تغيير المصاريف
          Expanded(
            child: _changeCell(expenseChange, ar, isMob, invertColor: true),
          ),
        ],
      ),
    );
  }

  /// خلية نسبة التغيير مع تلوين
  Widget _changeCell(double change, AccountingResponsive ar, bool isMob,
      {bool invertColor = false}) {
    if (change == 0) {
      return Text(
        '-',
        style: GoogleFonts.cairo(
          fontSize: isMob ? 10 : ar.tableCellFont,
          color: AccountingTheme.textMuted,
        ),
        textAlign: TextAlign.center,
      );
    }

    // للمصاريف: الزيادة سلبية (أحمر)، النقصان إيجابي (أخضر)
    final isPositive = invertColor ? change < 0 : change > 0;
    final displayColor = isPositive ? _clrPositive : _clrNegative;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: displayColor.withOpacity(0.08),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            change > 0
                ? Icons.arrow_upward_rounded
                : Icons.arrow_downward_rounded,
            size: isMob ? 10 : 14,
            color: displayColor,
          ),
          const SizedBox(width: 2),
          Flexible(
            child: Text(
              '${change.abs().toStringAsFixed(1)}%',
              style: GoogleFonts.cairo(
                fontSize: isMob ? 9 : ar.tableCellFont,
                fontWeight: FontWeight.w600,
                color: displayColor,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTotalsRow(double totalRevY1, double totalRevY2,
      double totalExpY1, double totalExpY2, AccountingResponsive ar, bool isMob) {
    final revChange =
        totalRevY1 != 0 ? ((totalRevY2 - totalRevY1) / totalRevY1.abs()) * 100 : 0.0;
    final expChange =
        totalExpY1 != 0 ? ((totalExpY2 - totalExpY1) / totalExpY1.abs()) * 100 : 0.0;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isMob ? 8 : ar.tableCellPadH,
        vertical: isMob ? 10 : ar.tableCellPadV + 4,
      ),
      decoration: BoxDecoration(
        color: AccountingTheme.bgSecondary,
        border: const Border(
          top: BorderSide(color: AccountingTheme.borderColor, width: 1.5),
        ),
      ),
      child: Row(
        children: [
          // المجموع
          Expanded(
            flex: 2,
            child: Text(
              'الإجمالي',
              style: GoogleFonts.cairo(
                fontSize: isMob ? 11 : ar.tableCellFont + 1,
                fontWeight: FontWeight.bold,
                color: AccountingTheme.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          // إجمالي إيرادات سنة 1
          Expanded(
            child: Text(
              _fmtCurrency(totalRevY1),
              style: GoogleFonts.cairo(
                fontSize: isMob ? 10 : ar.tableCellFont,
                fontWeight: FontWeight.bold,
                color: _clrYear1,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          // إجمالي إيرادات سنة 2
          Expanded(
            child: Text(
              _fmtCurrency(totalRevY2),
              style: GoogleFonts.cairo(
                fontSize: isMob ? 10 : ar.tableCellFont,
                fontWeight: FontWeight.bold,
                color: _clrYear2,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          // تغيير الإيرادات الإجمالي
          Expanded(
            child: _changeCell(revChange, ar, isMob),
          ),
          // إجمالي مصاريف سنة 1
          Expanded(
            child: Text(
              _fmtCurrency(totalExpY1),
              style: GoogleFonts.cairo(
                fontSize: isMob ? 10 : ar.tableCellFont,
                fontWeight: FontWeight.bold,
                color: _clrExpenses.withOpacity(0.7),
              ),
              textAlign: TextAlign.center,
            ),
          ),
          // إجمالي مصاريف سنة 2
          Expanded(
            child: Text(
              _fmtCurrency(totalExpY2),
              style: GoogleFonts.cairo(
                fontSize: isMob ? 10 : ar.tableCellFont,
                fontWeight: FontWeight.bold,
                color: _clrExpenses,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          // تغيير المصاريف الإجمالي
          Expanded(
            child: _changeCell(expChange, ar, isMob, invertColor: true),
          ),
        ],
      ),
    );
  }
}
