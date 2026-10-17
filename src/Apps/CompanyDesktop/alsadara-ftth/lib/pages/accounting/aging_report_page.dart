import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../../services/accounting_service.dart';
import '../../services/accounting_export_service.dart';
import '../../theme/accounting_responsive.dart';
import '../../utils/responsive_helper.dart';
import '../../frontend/frontend.dart';
import '../../frontend/components/sd_ui_kit.dart';

/// صفحة تقرير أعمار الديون - Aging Report
/// تعرض تحصيلات الفنيين غير المسلّمة مصنّفة حسب العمر الزمني
class AgingReportPage extends StatefulWidget {
  final String? companyId;

  const AgingReportPage({super.key, this.companyId});

  @override
  State<AgingReportPage> createState() => _AgingReportPageState();
}

class _AgingReportPageState extends State<AgingReportPage> {
  bool _isLoading = true;
  String? _errorMessage;
  List<Map<String, dynamic>> _allDebts = [];
  String? _filterTechnician;

  final _currencyFmt = NumberFormat('#,##0', 'ar');

  // ═══════════════════════════════════════════════════════════════
  //  ألوان وتسميات الفئات
  // ═══════════════════════════════════════════════════════════════

  static const _categoryColors = <int, Color>{
    0: SdColors.success, // حالي
    1: SdColors.warning, // متأخر
    2: SdColors.warning, // متأخر جداً
    3: SdColors.danger, // خطر
  };

  static const _categoryLabels = <int, String>{
    0: 'حالي',
    1: 'متأخر',
    2: 'متأخر جداً',
    3: 'خطر',
  };

  static const _categoryIcons = <int, IconData>{
    0: Icons.check_circle_outline,
    1: Icons.warning_amber_rounded,
    2: Icons.error_outline,
    3: Icons.dangerous_outlined,
  };

  // ═══════════════════════════════════════════════════════════════
  //  دورة الحياة
  // ═══════════════════════════════════════════════════════════════

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  // ═══════════════════════════════════════════════════════════════
  //  تحميل البيانات
  // ═══════════════════════════════════════════════════════════════

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final result = await AccountingService.instance.getCollections(
        companyId: widget.companyId,
        isDelivered: false,
      );

      if (result['success'] != true) {
        if (!mounted) return;
        setState(() {
          _errorMessage = result['message']?.toString() ?? 'خطأ في جلب البيانات';
          _isLoading = false;
        });
        return;
      }

      final items = result['data'] is List ? result['data'] as List : [];
      final now = DateTime.now();
      final debts = <Map<String, dynamic>>[];

      for (final item in items) {
        final dateStr =
            (item['CreatedAt'] ?? item['CollectionDate'] ?? '').toString();
        final parsedDate = DateTime.tryParse(dateStr);
        final daysDiff =
            parsedDate != null ? now.difference(parsedDate).inDays : 0;

        int categoryIndex;
        if (daysDiff <= 30) {
          categoryIndex = 0;
        } else if (daysDiff <= 60) {
          categoryIndex = 1;
        } else if (daysDiff <= 90) {
          categoryIndex = 2;
        } else {
          categoryIndex = 3;
        }

        debts.add({
          'technician': item['TechnicianName'] ??
              item['Technician']?['Name'] ??
              'غير محدد',
          'amount': (item['Amount'] as num?)?.toDouble() ?? 0,
          'date': dateStr,
          'ageDays': daysDiff,
          'category': _categoryLabels[categoryIndex]!,
          'categoryIndex': categoryIndex,
        });
      }

      if (!mounted) return;
      setState(() {
        _allDebts = debts;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'خطأ';
        _isLoading = false;
      });
    }
  }

  // ═══════════════════════════════════════════════════════════════
  //  بيانات محسوبة (Computed Getters)
  // ═══════════════════════════════════════════════════════════════

  List<Map<String, dynamic>> get _filteredDebts {
    if (_filterTechnician == null || _filterTechnician == 'الكل') {
      return _allDebts;
    }
    return _allDebts
        .where((d) => d['technician'] == _filterTechnician)
        .toList();
  }

  Map<String, double> get _categoryTotals {
    final totals = <String, double>{};
    for (final d in _filteredDebts) {
      final cat = d['category'] as String;
      totals[cat] = (totals[cat] ?? 0) + (d['amount'] as double);
    }
    return totals;
  }

  List<String> get _technicianNames {
    final names = <String>{};
    for (final d in _allDebts) {
      names.add(d['technician'] as String);
    }
    final sorted = names.toList()..sort();
    return sorted;
  }

  double get _totalDebt =>
      _filteredDebts.fold(0.0, (sum, d) => sum + (d['amount'] as double));

  int _categoryCount(int index) => _filteredDebts
      .where((d) => d['categoryIndex'] == index)
      .length;

  double _categoryAmount(int index) => _filteredDebts
      .where((d) => d['categoryIndex'] == index)
      .fold(0.0, (sum, d) => sum + (d['amount'] as double));

  String _fmtCurrency(double value) =>
      '${_currencyFmt.format(value.round())} د.ع';

  // ═══════════════════════════════════════════════════════════════
  //  البناء الرئيسي
  // ═══════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: SdColors.ground,
        appBar: SdAppBar(
          title: 'أعمار الديون',
          actions: [
            SdAppBarAction(
              icon: Icons.file_download_outlined,
              label: 'تصدير Excel',
              onPressed: _isLoading ? null : _exportReport,
            ),
            SdAppBarAction(
              icon: Icons.refresh_rounded,
              label: 'تحديث',
              onPressed: _isLoading ? null : _loadData,
            ),
          ],
        ),
        body: SafeArea(top: false, child: _buildBody()),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  جسم الصفحة
  // ═══════════════════════════════════════════════════════════════

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMessage != null) {
      return Center(
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
      );
    }
    if (_allDebts.isEmpty) {
      return const Center(
        child: SdEmptyState(
          title: 'لا توجد ديون غير مسلّمة',
          icon: Icons.check_circle_outline,
          status: SdStatus.success,
        ),
      );
    }

    final ar = context.accR;
    return SingleChildScrollView(
      padding: EdgeInsets.all(ar.paddingH),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSummaryCards(),
          SizedBox(height: ar.spaceL),
          _buildFilterBar(),
          SizedBox(height: ar.spaceL),
          _buildDataTable(),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  بطاقات الملخص (4 فئات)
  // ═══════════════════════════════════════════════════════════════

  Widget _buildSummaryCards() {
    final ar = context.accR;
    final isMobile = context.responsive.isMobile;
    final crossAxisCount = isMobile ? 2 : 4;
    final spacing = ar.spaceM;

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: spacing,
        mainAxisSpacing: spacing,
        childAspectRatio: isMobile ? 1.5 : 2.0,
      ),
      itemCount: 4,
      itemBuilder: (context, index) {
        final color = _categoryColors[index]!;
        final label = _categoryLabels[index]!;
        final icon = _categoryIcons[index]!;
        final amount = _categoryAmount(index);
        final count = _categoryCount(index);

        return Container(
          decoration: BoxDecoration(
            color: SdColors.surface,
            borderRadius: BorderRadius.circular(ar.cardRadius),
            boxShadow: SdUiKit.cardShadow,
            border: Border(
              right: BorderSide(color: color, width: 4),
            ),
          ),
          padding: EdgeInsets.all(ar.cardPad),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                children: [
                  Icon(icon, color: color, size: ar.iconS),
                  SizedBox(width: ar.spaceXS),
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: ar.small,
                        fontWeight: FontWeight.w600,
                        color: color,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: ar.spaceXS + 2,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(ar.badgeRadius),
                    ),
                    child: Text(
                      '$count',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: ar.caption,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: ar.spaceXS),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Text(
                  _fmtCurrency(amount),
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: ar.financialMedium,
                    fontWeight: FontWeight.bold,
                    color: SdColors.ink,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  شريط الفلترة
  // ═══════════════════════════════════════════════════════════════

  Widget _buildFilterBar() {
    final ar = context.accR;
    final isMobile = context.responsive.isMobile;
    final names = _technicianNames;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ar.cardPad,
        vertical: ar.spaceS,
      ),
      decoration: BoxDecoration(
        color: SdColors.surface,
        borderRadius: BorderRadius.circular(ar.cardRadius),
        boxShadow: SdUiKit.cardShadow,
      ),
      child: Row(
        children: [
          Icon(Icons.filter_alt_outlined,
              color: SdColors.faint, size: ar.iconS),
          SizedBox(width: ar.spaceS),
          Text(
            'الفني:',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: ar.body,
              fontWeight: FontWeight.w600,
              color: SdColors.muted,
            ),
          ),
          SizedBox(width: ar.spaceS),
          Expanded(
            child: Container(
              height: ar.btnHeight,
              padding: EdgeInsets.symmetric(horizontal: ar.spaceS),
              decoration: BoxDecoration(
                color: SdColors.ground,
                borderRadius: BorderRadius.circular(ar.btnRadius),
                border: Border.all(color: SdColors.divider),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _filterTechnician ?? 'الكل',
                  isExpanded: true,
                  icon: Icon(Icons.keyboard_arrow_down,
                      size: ar.iconS, color: SdColors.faint),
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: isMobile ? ar.small : ar.body,
                    color: SdColors.ink,
                  ),
                  items: [
                    DropdownMenuItem(
                      value: 'الكل',
                      child: Text('الكل',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: isMobile ? ar.small : ar.body,
                          )),
                    ),
                    ...names.map((name) => DropdownMenuItem(
                          value: name,
                          child: Text(name,
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: isMobile ? ar.small : ar.body,
                              )),
                        )),
                  ],
                  onChanged: (v) {
                    setState(() {
                      _filterTechnician = v == 'الكل' ? null : v;
                    });
                  },
                ),
              ),
            ),
          ),
          SizedBox(width: ar.spaceM),
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: ar.spaceM,
              vertical: ar.spaceXS,
            ),
            decoration: BoxDecoration(
              color: SdColors.groundAlt,
              borderRadius: BorderRadius.circular(ar.btnRadius),
            ),
            child: Text(
              'الإجمالي: ${_fmtCurrency(_totalDebt)}',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: isMobile ? ar.small : ar.body,
                fontWeight: FontWeight.bold,
                color: SdColors.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  جدول البيانات
  // ═══════════════════════════════════════════════════════════════

  Widget _buildDataTable() {
    final ar = context.accR;
    final debts = _filteredDebts;

    if (debts.isEmpty) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: ar.spaceXXL * 2),
        child: const SdEmptyState(
          title: 'لا توجد نتائج مطابقة للفلتر',
          icon: Icons.search_off,
        ),
      );
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
            minWidth: context.responsive.isMobile ? 550 : MediaQuery.of(context).size.width - ar.paddingH * 2,
          ),
          child: Column(
            children: [
              _buildTableHeader(),
              ...List.generate(debts.length, (i) => _buildTableRow(debts[i], i)),
              _buildTableFooter(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTableHeader() {
    final ar = context.accR;
    return Container(
      decoration: SdUiKit.tableHeader,
      padding: EdgeInsets.symmetric(
        horizontal: ar.tableCellPadH,
        vertical: ar.tableCellPadV + 2,
      ),
      child: Row(
        children: [
          _headerCell('#', width: ar.colNumW),
          _headerCell('الفني', flex: 2),
          _headerCell('المبلغ', width: ar.colAmountW + 10),
          _headerCell('التاريخ', width: ar.colDateW + 10),
          _headerCell('العمر (أيام)', width: ar.colAmountW),
          _headerCell('الفئة', width: ar.colStatusW + 10),
        ],
      ),
    );
  }

  Widget _headerCell(String label, {double? width, int flex = 0}) {
    final ar = context.accR;
    final child = Text(
      label,
      style: TextStyle(
        fontFamily: 'Cairo',
        fontSize: ar.tableHeaderFont,
        fontWeight: FontWeight.bold,
        color: SdColors.surface,
      ),
      textAlign: TextAlign.center,
    );

    if (width != null) {
      return SizedBox(width: width, child: child);
    }
    return Expanded(flex: flex, child: child);
  }

  Widget _buildTableRow(Map<String, dynamic> debt, int index) {
    final ar = context.accR;
    final catIndex = debt['categoryIndex'] as int;
    final color = _categoryColors[catIndex]!;
    final isEven = index.isEven;
    final amount = debt['amount'] as double;
    final dateStr = debt['date'] as String;
    final ageDays = debt['ageDays'] as int;
    final category = debt['category'] as String;
    final technician = debt['technician'] as String;

    // تنسيق التاريخ
    String formattedDate = '';
    final parsed = DateTime.tryParse(dateStr);
    if (parsed != null) {
      formattedDate = DateFormat('yyyy-MM-dd').format(parsed);
    }

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ar.tableCellPadH,
        vertical: ar.tableCellPadV,
      ),
      decoration: BoxDecoration(
        color: isEven
            ? color.withOpacity(0.04)
            : SdColors.surface,
        border: const Border(
          bottom: BorderSide(color: SdColors.divider, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          // #
          SizedBox(
            width: ar.colNumW,
            child: Text(
              '${index + 1}',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: ar.tableCellFont,
                color: SdColors.faint,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          // الفني
          Expanded(
            flex: 2,
            child: Text(
              technician,
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: ar.tableCellFont,
                fontWeight: FontWeight.w600,
                color: SdColors.ink,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // المبلغ
          SizedBox(
            width: ar.colAmountW + 10,
            child: Text(
              _fmtCurrency(amount),
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: ar.tableCellFont,
                fontWeight: FontWeight.bold,
                color: SdColors.ink,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          // التاريخ
          SizedBox(
            width: ar.colDateW + 10,
            child: Text(
              formattedDate,
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: ar.tableCellFont,
                color: SdColors.muted,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          // العمر (أيام)
          SizedBox(
            width: ar.colAmountW,
            child: Text(
              '$ageDays',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: ar.tableCellFont,
                fontWeight: FontWeight.w600,
                color: color,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          // الفئة
          SizedBox(
            width: ar.colStatusW + 10,
            child: Center(
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: ar.spaceS,
                  vertical: ar.spaceXS - 1,
                ),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(ar.badgeRadius + 2),
                  border: Border.all(color: color.withOpacity(0.3)),
                ),
                child: Text(
                  category,
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: ar.badgeFont,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTableFooter() {
    final ar = context.accR;
    final debts = _filteredDebts;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ar.tableCellPadH,
        vertical: ar.tableCellPadV + 4,
      ),
      decoration: BoxDecoration(
        color: SdColors.groundAlt,
        border: const Border(
          top: BorderSide(color: SdColors.divider, width: 1.5),
        ),
      ),
      child: Row(
        children: [
          // #
          SizedBox(width: ar.colNumW),
          // الفني
          Expanded(
            flex: 2,
            child: Text(
              'الإجمالي (${debts.length} سجل)',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: ar.tableCellFont,
                fontWeight: FontWeight.bold,
                color: SdColors.ink,
              ),
            ),
          ),
          // المبلغ
          SizedBox(
            width: ar.colAmountW + 10,
            child: Text(
              _fmtCurrency(_totalDebt),
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: ar.tableCellFont,
                fontWeight: FontWeight.bold,
                color: SdColors.danger,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          // التاريخ
          SizedBox(width: ar.colDateW + 10),
          // العمر
          SizedBox(width: ar.colAmountW),
          // الفئة
          SizedBox(width: ar.colStatusW + 10),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  تصدير التقرير
  // ═══════════════════════════════════════════════════════════════

  Future<void> _exportReport() async {
    try {
      final path = await AccountingExportService.exportAgingReport(
        debts: _filteredDebts,
        categoryTotals: _categoryTotals,
      );
      if (!mounted) return;
      SdUiKit.showSnack(
        context,
        'تم التصدير: $path',
        SdColors.success,
      );
    } catch (e) {
      if (!mounted) return;
      SdUiKit.showSnack(
        context,
        'خطأ في التصدير',
        SdColors.danger,
      );
    }
  }
}
