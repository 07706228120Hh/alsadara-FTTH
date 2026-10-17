import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:fl_chart/fl_chart.dart';
import '../../theme/accounting_responsive.dart';
import '../../utils/responsive_helper.dart';
import '../../services/accounting_service.dart';
import '../../services/budget_service.dart';
import '../../frontend/frontend.dart';
import '../../frontend/components/sd_ui_kit.dart';

/// صفحة إدارة الميزانية التقديرية
class BudgetPage extends StatefulWidget {
  final String? companyId;
  const BudgetPage({super.key, this.companyId});

  @override
  State<BudgetPage> createState() => _BudgetPageState();
}

class _BudgetPageState extends State<BudgetPage> {
  int _selectedYear = DateTime.now().year;
  int _selectedMonth = DateTime.now().month;
  bool _isLoading = true;
  bool _showVariance = false;
  String? _errorMessage;
  List<Map<String, dynamic>> _budgets = [];
  List<Map<String, dynamic>> _varianceData = [];
  List<dynamic> _accounts = [];

  static final _currencyFmt = NumberFormat('#,##0', 'ar');

  String get _companyId => widget.companyId ?? '';

  static const _arabicMonths = [
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
      final results = await Future.wait([
        BudgetService.instance.getBudgets(_companyId, _selectedYear),
        AccountingService.instance.getAccounts(companyId: widget.companyId),
      ]);
      _budgets = (results[0] as List<Map<String, dynamic>>)
          .where((b) => b['month'] == _selectedMonth)
          .toList();
      final accountsResult = results[1] as Map<String, dynamic>;
      if (accountsResult['success'] == true) {
        _accounts = accountsResult['data'] as List? ?? [];
      }
      if (_showVariance) {
        _varianceData = await BudgetService.instance.getVarianceReport(
          companyId: _companyId,
          year: _selectedYear,
          month: _selectedMonth,
          accounts: _accounts,
        );
      }
      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'حدث خطأ';
        _isLoading = false;
      });
    }
  }

  String _formatNumber(dynamic v) {
    if (v == null) return '0';
    final n = v is num ? v : double.tryParse(v.toString()) ?? 0;
    return _currencyFmt.format(n.round());
  }

  @override
  Widget build(BuildContext context) {
    final r = context.accR;
    return SdPage(
      scrollable: false,
      padding: EdgeInsets.zero,
      maxWidth: double.infinity,
      appBar: SdAppBar(
        title: 'الميزانية التقديرية',
        actions: [
          SdAppBarAction(
            icon: Icons.compare,
            label: _showVariance ? 'عرض الميزانيات' : 'عرض الانحراف',
            onPressed: () {
              setState(() => _showVariance = !_showVariance);
              _loadData();
            },
          ),
          SdAppBarAction(
            icon: Icons.refresh_rounded,
            label: 'تحديث',
            onPressed: _loadData,
          ),
        ],
      ),
      floatingActionButton: !_showVariance
          ? FloatingActionButton.extended(
              onPressed: _showAddBudgetDialog,
              icon: const Icon(Icons.add),
              label: Text('إضافة ميزانية',
                  style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
              backgroundColor: SdColors.primarySoft,
              foregroundColor: Colors.white,
            )
          : null,
      body: Column(
        children: [
          _buildMonthYearSelector(r),
          const Divider(height: 1, color: SdColors.divider),
          Expanded(child: _buildBody(r)),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  اختيار الشهر والسنة
  // ═══════════════════════════════════════════════════════════════

  Widget _buildMonthYearSelector(AccountingResponsive r) {
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: r.paddingH, vertical: r.spaceS),
      color: SdColors.groundAlt,
      child: Column(
        children: [
          // سطر السنة
          Row(
            children: [
              Icon(Icons.calendar_today,
                  size: r.iconS, color: SdColors.muted),
              SizedBox(width: r.spaceS),
              DropdownButton<int>(
                value: _selectedYear,
                style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: r.body, color: SdColors.ink),
                items: List.generate(11, (i) {
                  final y = 2020 + i;
                  return DropdownMenuItem(value: y, child: Text('$y'));
                }),
                onChanged: (v) {
                  if (v != null) {
                    setState(() => _selectedYear = v);
                    _loadData();
                  }
                },
              ),
              const Spacer(),
              if (_budgets.isNotEmpty && !_showVariance)
                Text(
                  '${_budgets.length} سجل',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: r.small,
                    color: SdColors.faint,
                  ),
                ),
            ],
          ),
          SizedBox(height: r.spaceXS),
          // سطر الأشهر
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: 12,
              separatorBuilder: (_, __) => SizedBox(width: r.spaceXS),
              itemBuilder: (_, i) {
                final m = i + 1;
                final selected = m == _selectedMonth;
                return ChoiceChip(
                  label: Text(
                    _arabicMonths[i],
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: r.small,
                      color: selected ? Colors.white : SdColors.muted,
                      fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  selected: selected,
                  selectedColor: SdColors.platformLight,
                  backgroundColor: SdColors.surface,
                  side: BorderSide(
                    color: selected
                        ? SdColors.platformLight
                        : SdColors.divider,
                  ),
                  onSelected: (_) {
                    setState(() => _selectedMonth = m);
                    _loadData();
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  المحتوى الرئيسي
  // ═══════════════════════════════════════════════════════════════

  Widget _buildBody(AccountingResponsive r) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMessage != null) {
      return SdUiKit.errorView(_errorMessage!, _loadData);
    }
    if (_showVariance) {
      return _buildVarianceView(r);
    }
    return _buildBudgetList(r);
  }

  // ═══════════════════════════════════════════════════════════════
  //  عرض قائمة الميزانيات
  // ═══════════════════════════════════════════════════════════════

  Widget _buildBudgetList(AccountingResponsive r) {
    if (_budgets.isEmpty) {
      return SdUiKit.emptyState(
        'لا توجد ميزانيات لهذا الشهر',
        icon: Icons.calculate_outlined,
      );
    }
    final isMob = context.responsive.isMobile;
    return SingleChildScrollView(
      padding: r.contentPadding,
      child: Container(
        decoration: SdUiKit.card,
        clipBehavior: Clip.antiAlias,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: isMob ? 550 : MediaQuery.of(context).size.width - r.paddingH * 2,
            ),
            child: Column(
              children: [
                // رأس الجدول
                Container(
                  decoration: SdUiKit.tableHeader,
                  padding: EdgeInsets.symmetric(
                      horizontal: r.tableCellPadH, vertical: r.tableCellPadV + 4),
                  child: Row(
                    children: [
                      _headerCell('كود الحساب', r, flex: 2),
                      _headerCell('اسم الحساب', r, flex: 3),
                      _headerCell('المبلغ المخطط', r, flex: 2),
                      _headerCell('ملاحظات', r, flex: 2),
                      _headerCell('إجراءات', r, flex: 2),
                    ],
                  ),
                ),
                // صفوف البيانات
                ...List.generate(_budgets.length, (i) {
                  final b = _budgets[i];
                  final isAlt = i.isOdd;
                  return Container(
                    color: isAlt
                        ? SdColors.surfaceAlt
                        : Colors.transparent,
                    padding: EdgeInsets.symmetric(
                        horizontal: r.tableCellPadH, vertical: r.tableCellPadV),
                    child: Row(
                      children: [
                        _dataCell(b['accountCode']?.toString() ?? '', r, flex: 2),
                        _dataCell(b['accountName']?.toString() ?? '', r, flex: 3),
                        _dataCell(_formatNumber(b['budgetAmount']), r,
                            flex: 2,
                            color: SdColors.primary,
                            bold: true),
                        _dataCell(b['notes']?.toString() ?? '', r, flex: 2),
                        Expanded(
                          flex: 2,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _actionBtn(
                                icon: Icons.edit,
                                color: SdColors.primary,
                                tooltip: 'تعديل',
                                r: r,
                                onTap: () => _showEditBudgetDialog(b),
                              ),
                              SizedBox(width: r.spaceXS),
                              _actionBtn(
                                icon: Icons.delete_outline,
                                color: SdColors.danger,
                                tooltip: 'حذف',
                                r: r,
                                onTap: () => _confirmDelete(b),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _headerCell(String text, AccountingResponsive r, {int flex = 1}) {
    return Expanded(
      flex: flex,
      child: Text(
        text,
        style: TextStyle(
          fontFamily: 'Cairo',
          color: SdColors.surface,
          fontSize: r.tableHeaderFont,
          fontWeight: FontWeight.bold,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _dataCell(String text, AccountingResponsive r,
      {int flex = 1, Color? color, bool bold = false}) {
    return Expanded(
      flex: flex,
      child: Text(
        text,
        style: TextStyle(
          fontFamily: 'Cairo',
          color: color ?? SdColors.ink,
          fontSize: r.tableCellFont,
          fontWeight: bold ? FontWeight.bold : FontWeight.normal,
        ),
        textAlign: TextAlign.center,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _actionBtn({
    required IconData icon,
    required Color color,
    required String tooltip,
    required AccountingResponsive r,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: EdgeInsets.all(r.spaceXS),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(icon, color: color, size: r.iconS),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  عرض الانحراف (Variance)
  // ═══════════════════════════════════════════════════════════════

  Widget _buildVarianceView(AccountingResponsive r) {
    if (_varianceData.isEmpty) {
      return SdUiKit.emptyState(
        'لا توجد بيانات انحراف لهذا الشهر',
        icon: Icons.compare,
      );
    }
    return SingleChildScrollView(
      padding: r.contentPadding,
      child: Column(
        children: [
          // جدول الانحراف
          Container(
            decoration: SdUiKit.card,
            clipBehavior: Clip.antiAlias,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minWidth: context.responsive.isMobile ? 550 : MediaQuery.of(context).size.width - r.paddingH * 2,
                ),
                child: Column(
                  children: [
                    Container(
                      decoration: SdUiKit.tableHeader,
                      padding: EdgeInsets.symmetric(
                          horizontal: r.tableCellPadH,
                          vertical: r.tableCellPadV + 4),
                      child: Row(
                        children: [
                          _headerCell('كود', r, flex: 1),
                          _headerCell('اسم الحساب', r, flex: 3),
                          _headerCell('المخطط', r, flex: 2),
                          _headerCell('الفعلي', r, flex: 2),
                          _headerCell('الانحراف', r, flex: 2),
                          _headerCell('النسبة %', r, flex: 1),
                        ],
                      ),
                    ),
                    ...List.generate(_varianceData.length, (i) {
                      final v = _varianceData[i];
                      final overBudget = v['overBudget'] == true;
                      final rowColor = overBudget
                          ? SdColors.danger.withValues(alpha: 0.06)
                          : SdColors.success.withValues(alpha: 0.06);
                      return Container(
                        color: rowColor,
                        padding: EdgeInsets.symmetric(
                            horizontal: r.tableCellPadH,
                            vertical: r.tableCellPadV),
                        child: Row(
                          children: [
                            _dataCell(v['accountCode']?.toString() ?? '', r,
                                flex: 1),
                            _dataCell(v['accountName']?.toString() ?? '', r,
                                flex: 3),
                            _dataCell(_formatNumber(v['budget']), r, flex: 2),
                            _dataCell(_formatNumber(v['actual']), r, flex: 2),
                            _dataCell(_formatNumber(v['variance']), r,
                                flex: 2,
                                color: overBudget
                                    ? SdColors.danger
                                    : SdColors.success,
                                bold: true),
                            _dataCell(
                              '${(v['variancePercent'] as num).toStringAsFixed(1)}%',
                              r,
                              flex: 1,
                              color: overBudget
                                  ? SdColors.danger
                                  : SdColors.success,
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
          ),
          SizedBox(height: r.spaceXL),
          // مخطط بياني
          _buildVarianceChart(r),
        ],
      ),
    );
  }

  Widget _buildVarianceChart(AccountingResponsive r) {
    if (_varianceData.isEmpty) return const SizedBox.shrink();

    final maxVal = _varianceData.fold<double>(0.0, (prev, v) {
      final budget = (v['budget'] as num).toDouble();
      final actual = (v['actual'] as num).toDouble();
      final m = budget > actual ? budget : actual;
      return m > prev ? m : prev;
    });

    return Container(
      decoration: SdUiKit.card,
      padding: r.cardPadding,
      height: 300,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'المخطط مقابل الفعلي',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: r.headingSmall,
              fontWeight: FontWeight.bold,
              color: SdColors.ink,
            ),
          ),
          SizedBox(height: r.spaceM),
          // مفتاح الألوان
          Row(
            children: [
              _legendDot(SdColors.primary, 'المخطط', r),
              SizedBox(width: r.spaceL),
              _legendDot(SdColors.warning, 'الفعلي', r),
            ],
          ),
          SizedBox(height: r.spaceM),
          Expanded(
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: maxVal * 1.2,
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      final label = rodIndex == 0 ? 'المخطط' : 'الفعلي';
                      return BarTooltipItem(
                        '$label\n${_formatNumber(rod.toY)}',
                        TextStyle(
                            fontFamily: 'Cairo',
                            color: Colors.white, fontSize: r.small),
                      );
                    },
                  ),
                ),
                titlesData: FlTitlesData(
                  show: true,
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        final idx = value.toInt();
                        if (idx < 0 || idx >= _varianceData.length) {
                          return const SizedBox.shrink();
                        }
                        final code =
                            _varianceData[idx]['accountCode']?.toString() ?? '';
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            code,
                            style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: r.caption,
                                color: SdColors.faint),
                          ),
                        );
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 50,
                      getTitlesWidget: (value, meta) {
                        return Text(
                          _formatNumber(value),
                          style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: r.caption,
                              color: SdColors.faint),
                        );
                      },
                    ),
                  ),
                  topTitles:
                      const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles:
                      const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (_) => FlLine(
                    color: SdColors.divider,
                    strokeWidth: 1,
                  ),
                ),
                borderData: FlBorderData(show: false),
                barGroups: List.generate(_varianceData.length, (i) {
                  final v = _varianceData[i];
                  return BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: (v['budget'] as num).toDouble(),
                        color: SdColors.primary,
                        width: 14,
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(4)),
                      ),
                      BarChartRodData(
                        toY: (v['actual'] as num).toDouble(),
                        color: SdColors.warning,
                        width: 14,
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(4)),
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

  Widget _legendDot(Color color, String label, AccountingResponsive r) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        SizedBox(width: r.spaceXS),
        Text(
          label,
          style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: r.small, color: SdColors.muted),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  حوار إضافة ميزانية
  // ═══════════════════════════════════════════════════════════════

  void _showAddBudgetDialog() {
    // تصفية الحسابات الورقية (leaf accounts) — الحسابات التي ليس لها أبناء
    final leafAccounts = _accounts.where((a) {
      final hasChildren = a['HasChildren'] ?? a['hasChildren'] ?? false;
      return hasChildren != true;
    }).toList();

    dynamic selectedAccount;
    final amountController = TextEditingController();
    final notesController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              backgroundColor: SdColors.surface,
              shape: RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(SdUiKit.radiusLarge)),
              title: Text(
                'إضافة ميزانية تقديرية',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  color: SdColors.ink,
                  fontWeight: FontWeight.bold,
                ),
              ),
              content: SizedBox(
                width: context.accR.dialogMediumW,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('الحساب',
                          style: TextStyle(
                              fontFamily: 'Cairo',
                              color: SdColors.muted,
                              fontSize: 13)),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<dynamic>(
                        value: selectedAccount,
                        isExpanded: true,
                        decoration: InputDecoration(
                          hintText: 'اختر الحساب',
                          hintStyle: TextStyle(
                              fontFamily: 'Cairo',
                              color: SdColors.faint),
                          filled: true,
                          fillColor: SdColors.groundAlt,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(
                                SdUiKit.radiusMedium),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                        ),
                        style: TextStyle(
                            fontFamily: 'Cairo',
                            color: SdColors.ink, fontSize: 13),
                        items: leafAccounts.map<DropdownMenuItem<dynamic>>((a) {
                          final code = a['Code'] ?? a['code'] ?? '';
                          final name = a['Name'] ?? a['name'] ?? '';
                          return DropdownMenuItem<dynamic>(
                            value: a,
                            child: Text('$code - $name',
                                overflow: TextOverflow.ellipsis),
                          );
                        }).toList(),
                        onChanged: (v) =>
                            setDialogState(() => selectedAccount = v),
                      ),
                      const SizedBox(height: 16),
                      Text('المبلغ المخطط',
                          style: TextStyle(
                              fontFamily: 'Cairo',
                              color: SdColors.muted,
                              fontSize: 13)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: amountController,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        style: TextStyle(
                            fontFamily: 'Cairo',
                            color: SdColors.ink),
                        decoration: InputDecoration(
                          hintText: '0',
                          hintStyle: TextStyle(
                              fontFamily: 'Cairo',
                              color: SdColors.faint),
                          filled: true,
                          fillColor: SdColors.groundAlt,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(
                                SdUiKit.radiusMedium),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text('ملاحظات',
                          style: TextStyle(
                              fontFamily: 'Cairo',
                              color: SdColors.muted,
                              fontSize: 13)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: notesController,
                        maxLines: 2,
                        style: TextStyle(
                            fontFamily: 'Cairo',
                            color: SdColors.ink),
                        decoration: InputDecoration(
                          hintText: 'ملاحظات اختيارية...',
                          hintStyle: TextStyle(
                              fontFamily: 'Cairo',
                              color: SdColors.faint),
                          filled: true,
                          fillColor: SdColors.groundAlt,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(
                                SdUiKit.radiusMedium),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('إلغاء',
                      style: TextStyle(fontFamily: 'Cairo', color: SdColors.faint)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: SdColors.primarySoft,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                            SdUiKit.radiusMedium)),
                  ),
                  onPressed: () async {
                    if (selectedAccount == null) {
                      SdUiKit.showSnack(
                          context, 'يرجى اختيار الحساب', SdColors.warning);
                      return;
                    }
                    final amount =
                        double.tryParse(amountController.text.trim());
                    if (amount == null || amount <= 0) {
                      SdUiKit.showSnack(
                          context, 'يرجى إدخال مبلغ صحيح', SdColors.warning);
                      return;
                    }
                    await BudgetService.instance.setBudget(
                      companyId: _companyId,
                      accountId: (selectedAccount['Id'] ??
                              selectedAccount['id'] ??
                              '')
                          .toString(),
                      accountCode: (selectedAccount['Code'] ??
                              selectedAccount['code'] ??
                              '')
                          .toString(),
                      accountName: (selectedAccount['Name'] ??
                              selectedAccount['name'] ??
                              '')
                          .toString(),
                      year: _selectedYear,
                      month: _selectedMonth,
                      budgetAmount: amount,
                      notes: notesController.text.trim().isNotEmpty
                          ? notesController.text.trim()
                          : null,
                    );
                    if (ctx.mounted) Navigator.pop(ctx);
                    SdUiKit.showSnack(
                        context, 'تم حفظ الميزانية بنجاح', SdColors.success);
                    _loadData();
                  },
                  child: Text('حفظ',
                      style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  حوار تعديل ميزانية
  // ═══════════════════════════════════════════════════════════════

  void _showEditBudgetDialog(Map<String, dynamic> budget) {
    final amountController = TextEditingController(
        text: (budget['budgetAmount'] as num?)?.toString() ?? '');
    final notesController =
        TextEditingController(text: budget['notes']?.toString() ?? '');

    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: SdColors.surface,
          shape: RoundedRectangleBorder(
              borderRadius:
                  BorderRadius.circular(SdUiKit.radiusLarge)),
          title: Text(
            'تعديل ميزانية: ${budget['accountName']}',
            style: TextStyle(
              fontFamily: 'Cairo',
              color: SdColors.ink,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          content: SizedBox(
            width: context.accR.dialogSmallW,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('المبلغ المخطط',
                    style: TextStyle(
                        fontFamily: 'Cairo',
                        color: SdColors.muted, fontSize: 13)),
                const SizedBox(height: 6),
                TextField(
                  controller: amountController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  style:
                      TextStyle(fontFamily: 'Cairo', color: SdColors.ink),
                  decoration: InputDecoration(
                    hintText: '0',
                    hintStyle:
                        TextStyle(fontFamily: 'Cairo', color: SdColors.faint),
                    filled: true,
                    fillColor: SdColors.groundAlt,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(
                          SdUiKit.radiusMedium),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                  ),
                ),
                const SizedBox(height: 16),
                Text('ملاحظات',
                    style: TextStyle(
                        fontFamily: 'Cairo',
                        color: SdColors.muted, fontSize: 13)),
                const SizedBox(height: 6),
                TextField(
                  controller: notesController,
                  maxLines: 2,
                  style:
                      TextStyle(fontFamily: 'Cairo', color: SdColors.ink),
                  decoration: InputDecoration(
                    hintText: 'ملاحظات اختيارية...',
                    hintStyle:
                        TextStyle(fontFamily: 'Cairo', color: SdColors.faint),
                    filled: true,
                    fillColor: SdColors.groundAlt,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(
                          SdUiKit.radiusMedium),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('إلغاء',
                  style: TextStyle(fontFamily: 'Cairo', color: SdColors.faint)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: SdColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(
                        SdUiKit.radiusMedium)),
              ),
              onPressed: () async {
                final amount =
                    double.tryParse(amountController.text.trim());
                if (amount == null || amount <= 0) {
                  SdUiKit.showSnack(
                      context, 'يرجى إدخال مبلغ صحيح', SdColors.warning);
                  return;
                }
                await BudgetService.instance.setBudget(
                  companyId: _companyId,
                  accountId: budget['accountId'].toString(),
                  accountCode: budget['accountCode'].toString(),
                  accountName: budget['accountName'].toString(),
                  year: _selectedYear,
                  month: _selectedMonth,
                  budgetAmount: amount,
                  notes: notesController.text.trim().isNotEmpty
                      ? notesController.text.trim()
                      : null,
                );
                if (ctx.mounted) Navigator.pop(ctx);
                SdUiKit.showSnack(
                    context, 'تم تحديث الميزانية بنجاح', SdColors.success);
                _loadData();
              },
              child: Text('تحديث',
                  style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  حذف ميزانية
  // ═══════════════════════════════════════════════════════════════

  Future<void> _confirmDelete(Map<String, dynamic> budget) async {
    final confirmed = await SdUiKit.confirmDialog(
      context,
      title: 'حذف ميزانية',
      message:
          'هل تريد حذف ميزانية "${budget['accountName']}" لشهر ${_arabicMonths[_selectedMonth - 1]}؟',
      confirmLabel: 'حذف',
      confirmColor: SdColors.danger,
    );
    if (confirmed == true) {
      await BudgetService.instance.deleteBudget(
        _companyId,
        _selectedYear,
        budget['accountId'].toString(),
        _selectedMonth,
      );
      if (mounted) {
        SdUiKit.showSnack(
            context, 'تم حذف الميزانية', SdColors.success);
      }
      _loadData();
    }
  }
}
