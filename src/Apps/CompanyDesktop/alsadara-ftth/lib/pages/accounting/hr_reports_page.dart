import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/accounting_service.dart';
import '../../theme/accounting_theme.dart';
import '../../theme/accounting_responsive.dart';

/// صفحة تقارير الموارد البشرية
class HrReportsPage extends StatefulWidget {
  final String? companyId;

  const HrReportsPage({super.key, this.companyId});

  @override
  State<HrReportsPage> createState() => _HrReportsPageState();
}

class _HrReportsPageState extends State<HrReportsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _selectedMonth = DateTime.now().month;
  int _selectedYear = DateTime.now().year;

  // بيانات التبويبات
  bool _dashLoading = true;
  Map<String, dynamic> _dashData = {};

  bool _attLoading = true;
  List<dynamic> _attData = [];
  Map<String, dynamic> _attSummary = {};

  bool _salLoading = true;
  List<dynamic> _salData = [];
  Map<String, dynamic> _salSummary = {};

  bool _leaveLoading = true;
  List<dynamic> _leaveData = [];
  Map<String, dynamic> _leaveSummary = {};

  final _months = [
    'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
    'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) _loadTab(_tabController.index);
    });
    _loadTab(0);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _loadTab(int index) {
    switch (index) {
      case 0:
        _loadDashboard();
        break;
      case 1:
        _loadAttendance();
        break;
      case 2:
        _loadSalaryReport();
        break;
      case 3:
        _loadLeaves();
        break;
    }
  }

  Future<void> _loadDashboard() async {
    setState(() => _dashLoading = true);
    try {
      final r = await AccountingService.instance.getHrDashboard(
        companyId: widget.companyId,
        month: _selectedMonth,
        year: _selectedYear,
      );
      if (r['success'] == true && r['data'] is Map) {
        _dashData = Map<String, dynamic>.from(r['data'] as Map);
      }
    } catch (_) {}
    setState(() => _dashLoading = false);
  }

  Future<void> _loadAttendance() async {
    setState(() => _attLoading = true);
    try {
      final r = await AccountingService.instance.getMonthlyAttendanceReport(
        companyId: widget.companyId,
        month: _selectedMonth,
        year: _selectedYear,
      );
      if (r['success'] == true) {
        _attData = (r['data'] is List) ? r['data'] : [];
        _attSummary = (r['summary'] is Map)
            ? Map<String, dynamic>.from(r['summary'] as Map)
            : {};
      }
    } catch (_) {}
    setState(() => _attLoading = false);
  }

  Future<void> _loadSalaryReport() async {
    setState(() => _salLoading = true);
    try {
      final r = await AccountingService.instance.getMonthlySalaryReport(
        companyId: widget.companyId,
        month: _selectedMonth,
        year: _selectedYear,
      );
      if (r['success'] == true) {
        _salData = (r['data'] is List) ? r['data'] : [];
        _salSummary = (r['summary'] is Map)
            ? Map<String, dynamic>.from(r['summary'] as Map)
            : {};
      }
    } catch (_) {}
    setState(() => _salLoading = false);
  }

  Future<void> _loadLeaves() async {
    setState(() => _leaveLoading = true);
    try {
      final r = await AccountingService.instance.getLeavesSummary(
        companyId: widget.companyId,
        month: _selectedMonth,
        year: _selectedYear,
      );
      if (r['success'] == true) {
        _leaveData = (r['data'] is List) ? r['data'] : [];
        _leaveSummary = (r['summary'] is Map)
            ? Map<String, dynamic>.from(r['summary'] as Map)
            : {};
      }
    } catch (_) {}
    setState(() => _leaveLoading = false);
  }

  void _reloadCurrent() => _loadTab(_tabController.index);

  @override
  Widget build(BuildContext context) {
    final isMobile = context.accR.isMobile;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AccountingTheme.bgPrimary,
        body: SafeArea(
          child: Column(
            children: [
              _buildToolbar(isMobile),
              _buildMonthSelector(),
              _buildTabs(),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildDashboardTab(),
                    _buildAttendanceTab(),
                    _buildSalaryReportTab(),
                    _buildLeavesTab(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildToolbar(bool isMobile) {
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: isMobile ? 8 : context.accR.spaceXL,
          vertical: isMobile ? 6 : context.accR.spaceL),
      decoration: const BoxDecoration(
        color: AccountingTheme.bgCard,
        border: Border(bottom: BorderSide(color: AccountingTheme.borderColor)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_forward_rounded),
            tooltip: 'رجوع',
            iconSize: isMobile ? 20 : 24,
            style: IconButton.styleFrom(
                foregroundColor: AccountingTheme.textSecondary),
          ),
          if (!isMobile) SizedBox(width: context.accR.spaceS),
          Container(
            padding: EdgeInsets.all(isMobile ? 4 : context.accR.spaceS),
            decoration: BoxDecoration(
              gradient: AccountingTheme.neonPinkGradient,
              borderRadius: BorderRadius.circular(isMobile ? 6 : 8),
            ),
            child: Icon(Icons.assessment_rounded,
                color: Colors.white, size: isMobile ? 16 : context.accR.iconM),
          ),
          SizedBox(width: isMobile ? 6 : context.accR.spaceM),
          Expanded(
            child: Text('تقارير الموارد البشرية',
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.cairo(
                    fontSize: isMobile ? 14 : context.accR.headingMedium,
                    fontWeight: FontWeight.bold,
                    color: AccountingTheme.textPrimary)),
          ),
          IconButton(
            onPressed: _reloadCurrent,
            icon: Icon(Icons.refresh, size: isMobile ? 18 : context.accR.iconM),
            tooltip: 'تحديث',
            style: IconButton.styleFrom(
                foregroundColor: AccountingTheme.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildMonthSelector() {
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: context.accR.paddingH, vertical: context.accR.spaceM),
      color: AccountingTheme.bgCard,
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_right,
                color: AccountingTheme.textSecondary),
            onPressed: () {
              setState(() {
                if (_selectedMonth == 12) {
                  _selectedMonth = 1;
                  _selectedYear++;
                } else {
                  _selectedMonth++;
                }
              });
              _reloadCurrent();
            },
          ),
          Expanded(
            child: Text(
              '${_months[_selectedMonth - 1]} $_selectedYear',
              style: TextStyle(
                  color: AccountingTheme.textPrimary,
                  fontSize: context.accR.headingSmall,
                  fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_left,
                color: AccountingTheme.textSecondary),
            onPressed: () {
              setState(() {
                if (_selectedMonth == 1) {
                  _selectedMonth = 12;
                  _selectedYear--;
                } else {
                  _selectedMonth--;
                }
              });
              _reloadCurrent();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTabs() {
    return Container(
      color: AccountingTheme.bgCard,
      child: TabBar(
        controller: _tabController,
        isScrollable: context.accR.isMobile,
        indicatorColor: AccountingTheme.neonGreen,
        labelColor: AccountingTheme.neonGreen,
        unselectedLabelColor: AccountingTheme.textMuted,
        labelStyle: TextStyle(
            fontWeight: FontWeight.bold, fontSize: context.accR.small),
        tabs: const [
          Tab(text: 'لوحة عامة', icon: Icon(Icons.dashboard, size: 18)),
          Tab(text: 'الحضور', icon: Icon(Icons.schedule, size: 18)),
          Tab(text: 'الرواتب', icon: Icon(Icons.payments, size: 18)),
          Tab(text: 'الإجازات', icon: Icon(Icons.beach_access, size: 18)),
        ],
      ),
    );
  }

  // ═════════════════════════════
  // تبويب 1: لوحة عامة
  // ═════════════════════════════

  Widget _buildDashboardTab() {
    if (_dashLoading) return _loader();
    if (_dashData.isEmpty) return _emptyState('لا توجد بيانات');

    final today = _dashData['Today'] is Map
        ? Map<String, dynamic>.from(_dashData['Today'] as Map)
        : <String, dynamic>{};
    final monthly = _dashData['MonthlyAttendance'] is Map
        ? Map<String, dynamic>.from(_dashData['MonthlyAttendance'] as Map)
        : <String, dynamic>{};
    final salaries = _dashData['Salaries'] is Map
        ? Map<String, dynamic>.from(_dashData['Salaries'] as Map)
        : <String, dynamic>{};
    final topLate = _dashData['TopLateEmployees'] is List
        ? _dashData['TopLateEmployees'] as List
        : [];
    final topOvertime = _dashData['TopOvertimeEmployees'] is List
        ? _dashData['TopOvertimeEmployees'] as List
        : [];

    return SingleChildScrollView(
      padding: EdgeInsets.all(context.accR.paddingH),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // إحصائيات اليوم
          _sectionTitle('اليوم'),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _statCard('حاضر', '${today['PresentCount'] ?? 0}',
                  Icons.check_circle, AccountingTheme.success),
              _statCard('متأخر', '${today['LateCount'] ?? 0}', Icons.timer,
                  const Color(0xFFF39C12)),
              _statCard('غائب', '${today['AbsentCount'] ?? 0}',
                  Icons.cancel, AccountingTheme.danger),
            ],
          ),
          const SizedBox(height: 20),
          // إحصائيات الشهر
          _sectionTitle('حضور الشهر'),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _statCard('حضور', '${monthly['TotalPresent'] ?? 0}',
                  Icons.check, AccountingTheme.success),
              _statCard('تأخير', '${monthly['TotalLate'] ?? 0}',
                  Icons.timer, const Color(0xFFF39C12)),
              _statCard('غياب', '${monthly['TotalAbsent'] ?? 0}',
                  Icons.close, AccountingTheme.danger),
              _statCard(
                  'نسبة الحضور',
                  '${((monthly['AttendanceRate'] ?? 0) as num).toStringAsFixed(1)}%',
                  Icons.percent,
                  AccountingTheme.info),
            ],
          ),
          const SizedBox(height: 20),
          // الرواتب
          _sectionTitle('ملخص الرواتب'),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _statCard('إجمالي صافي', _fmt(salaries['TotalNet']),
                  Icons.payments, const Color(0xFF2196F3)),
              _statCard('الخصومات', _fmt(salaries['TotalDeductions']),
                  Icons.remove_circle, AccountingTheme.danger),
              _statCard('المكافآت', _fmt(salaries['TotalBonuses']),
                  Icons.card_giftcard, AccountingTheme.success),
              _statCard('مصروفة', '${salaries['PaidCount'] ?? 0}',
                  Icons.done_all, AccountingTheme.success),
              _statCard('معلقة', '${salaries['PendingCount'] ?? 0}',
                  Icons.pending, const Color(0xFFF39C12)),
            ],
          ),
          const SizedBox(height: 20),
          // أكثر تأخراً
          if (topLate.isNotEmpty) ...[
            _sectionTitle('الأكثر تأخراً'),
            ...topLate.take(5).map((e) => _rankTile(
                  e['EmployeeName'] ?? '',
                  '${e['TotalLateMinutes'] ?? 0} دقيقة',
                  AccountingTheme.danger,
                )),
            const SizedBox(height: 16),
          ],
          // أكثر عملاً إضافياً
          if (topOvertime.isNotEmpty) ...[
            _sectionTitle('الأكثر عملاً إضافياً'),
            ...topOvertime.take(5).map((e) => _rankTile(
                  e['EmployeeName'] ?? '',
                  '${e['TotalOvertimeMinutes'] ?? 0} دقيقة',
                  AccountingTheme.success,
                )),
          ],
        ],
      ),
    );
  }

  Widget _sectionTitle(String t) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(t,
          style: TextStyle(
              color: AccountingTheme.textPrimary,
              fontWeight: FontWeight.bold,
              fontSize: context.accR.headingSmall)),
    );
  }

  Widget _statCard(String label, String value, IconData icon, Color color) {
    return Container(
      width: context.accR.isMobile ? 100 : 150,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AccountingTheme.bgCard,
        borderRadius: BorderRadius.circular(context.accR.cardRadius),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 4),
          Text(value,
              style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: context.accR.body)),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(
                  color: AccountingTheme.textMuted,
                  fontSize: context.accR.caption),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _rankTile(String name, String detail, Color color) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AccountingTheme.bgCard,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(name,
                style: TextStyle(
                    color: AccountingTheme.textPrimary,
                    fontSize: context.accR.body)),
          ),
          Text(detail,
              style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: context.accR.small)),
        ],
      ),
    );
  }

  // ═════════════════════════════
  // تبويب 2: الحضور
  // ═════════════════════════════

  Widget _buildAttendanceTab() {
    if (_attLoading) return _loader();
    if (_attData.isEmpty) return _emptyState('لا توجد سجلات حضور');

    return SingleChildScrollView(
      padding: const EdgeInsets.all(8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(
              minWidth: MediaQuery.of(context).size.width - 16),
          child: DataTable(
            headingRowColor:
                WidgetStateProperty.all(const Color(0xFF1E293B)),
            dataRowColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.hovered)) {
                return const Color(0xFF1E293B).withValues(alpha: 0.5);
              }
              return AccountingTheme.bgCard;
            }),
            border: TableBorder.all(
                color: AccountingTheme.borderColor.withValues(alpha: 0.3),
                width: 0.5),
            columnSpacing: 12,
            horizontalMargin: 10,
            headingRowHeight: 40,
            dataRowMinHeight: 36,
            dataRowMaxHeight: 40,
            columns: [
              _col('الموظف'),
              _col('حضور', numeric: true),
              _col('تأخير', numeric: true),
              _col('غياب', numeric: true),
              _col('نصف يوم', numeric: true),
              _col('مغادرة مبكرة', numeric: true),
              _col('دقائق تأخير', numeric: true),
              _col('دقائق إضافية', numeric: true),
            ],
            rows: _attData.map((e) {
              return DataRow(cells: [
                _cell(e['EmployeeName'] ?? '', bold: true),
                _cell('${e['PresentDays'] ?? 0}',
                    color: AccountingTheme.success),
                _cell('${e['LateDays'] ?? 0}',
                    color: const Color(0xFFF39C12)),
                _cell('${e['AbsentDays'] ?? 0}',
                    color: AccountingTheme.danger),
                _cell('${e['HalfDays'] ?? 0}'),
                _cell('${e['EarlyDepartureDays'] ?? 0}'),
                _cell('${e['TotalLateMinutes'] ?? 0}',
                    color: AccountingTheme.danger),
                _cell('${e['TotalOvertimeMinutes'] ?? 0}',
                    color: AccountingTheme.success),
              ]);
            }).toList(),
          ),
        ),
      ),
    );
  }

  // ═════════════════════════════
  // تبويب 3: الرواتب
  // ═════════════════════════════

  Widget _buildSalaryReportTab() {
    if (_salLoading) return _loader();
    if (_salData.isEmpty) return _emptyState('لا توجد بيانات رواتب');

    return Column(
      children: [
        // ملخص
        Container(
          padding: EdgeInsets.symmetric(
              horizontal: context.accR.paddingH,
              vertical: context.accR.spaceS),
          child: Row(
            children: [
              Expanded(
                  child: _chipSummary('الأساسي',
                      _fmt(_salSummary['TotalBaseSalary']), const Color(0xFF2196F3))),
              const SizedBox(width: 6),
              Expanded(
                  child: _chipSummary('الصافي',
                      _fmt(_salSummary['TotalNetSalary']), AccountingTheme.neonGreen)),
              const SizedBox(width: 6),
              Expanded(
                  child: _chipSummary('الخصومات',
                      _fmt(_salSummary['TotalDeductions']), AccountingTheme.danger)),
              const SizedBox(width: 6),
              Expanded(
                  child: _chipSummary('الإضافي',
                      _fmt(_salSummary['TotalOvertimeBonus']), AccountingTheme.success)),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                    minWidth: MediaQuery.of(context).size.width - 16),
                child: DataTable(
                  headingRowColor:
                      WidgetStateProperty.all(const Color(0xFF1E293B)),
                  dataRowColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.hovered)) {
                      return const Color(0xFF1E293B).withValues(alpha: 0.5);
                    }
                    return AccountingTheme.bgCard;
                  }),
                  border: TableBorder.all(
                      color: AccountingTheme.borderColor.withValues(alpha: 0.3),
                      width: 0.5),
                  columnSpacing: 12,
                  horizontalMargin: 10,
                  headingRowHeight: 40,
                  dataRowMinHeight: 36,
                  dataRowMaxHeight: 40,
                  columns: [
                    _col('الموظف'),
                    _col('الأساسي', numeric: true),
                    _col('البدلات', numeric: true),
                    _col('الخصومات', numeric: true),
                    _col('خصم تأخير', numeric: true),
                    _col('خصم غياب', numeric: true),
                    _col('مكافأة إضافي', numeric: true),
                    _col('الصافي', numeric: true),
                    _col('الحالة'),
                  ],
                  rows: _salData.map((e) {
                    final status = e['Status'] ?? 'Pending';
                    final statusColor =
                        AccountingTheme.salaryStatusColors[status] ??
                            AccountingTheme.textMuted;
                    final statusAr = {
                      'Pending': 'معلق',
                      'Paid': 'مدفوع',
                      'PartiallyPaid': 'جزئي',
                      'Cancelled': 'ملغي',
                    };
                    return DataRow(cells: [
                      _cell(e['EmployeeName'] ?? '', bold: true),
                      _cell(_fmt(e['BaseSalary'])),
                      _cell(_fmt(e['Allowances'])),
                      _cell(_fmt(e['Deductions']),
                          color: AccountingTheme.danger),
                      _cell(_fmt(e['LateDeduction']),
                          color: AccountingTheme.danger),
                      _cell(_fmt(e['AbsentDeduction']),
                          color: AccountingTheme.danger),
                      _cell(_fmt(e['OvertimeBonus']),
                          color: AccountingTheme.success),
                      _cell(_fmt(e['NetSalary']), bold: true),
                      DataCell(Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(statusAr[status] ?? status,
                            style: TextStyle(
                                color: statusColor,
                                fontSize: context.accR.caption,
                                fontWeight: FontWeight.bold)),
                      )),
                    ]);
                  }).toList(),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ═════════════════════════════
  // تبويب 4: الإجازات
  // ═════════════════════════════

  Widget _buildLeavesTab() {
    if (_leaveLoading) return _loader();
    if (_leaveData.isEmpty) return _emptyState('لا توجد بيانات إجازات');

    return SingleChildScrollView(
      padding: const EdgeInsets.all(8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(
              minWidth: MediaQuery.of(context).size.width - 16),
          child: DataTable(
            headingRowColor:
                WidgetStateProperty.all(const Color(0xFF1E293B)),
            dataRowColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.hovered)) {
                return const Color(0xFF1E293B).withValues(alpha: 0.5);
              }
              return AccountingTheme.bgCard;
            }),
            border: TableBorder.all(
                color: AccountingTheme.borderColor.withValues(alpha: 0.3),
                width: 0.5),
            columnSpacing: 12,
            horizontalMargin: 10,
            headingRowHeight: 40,
            dataRowMinHeight: 36,
            dataRowMaxHeight: 40,
            columns: [
              _col('الموظف'),
              _col('إجمالي الطلبات', numeric: true),
              _col('مقبولة', numeric: true),
              _col('مرفوضة', numeric: true),
              _col('معلقة', numeric: true),
              _col('أيام مقبولة', numeric: true),
            ],
            rows: _leaveData.map((e) {
              return DataRow(cells: [
                _cell(e['EmployeeName'] ?? '', bold: true),
                _cell('${e['TotalRequests'] ?? 0}'),
                _cell('${e['Approved'] ?? 0}',
                    color: AccountingTheme.success),
                _cell('${e['Rejected'] ?? 0}',
                    color: AccountingTheme.danger),
                _cell('${e['Pending'] ?? 0}',
                    color: const Color(0xFFF39C12)),
                _cell('${e['TotalDaysApproved'] ?? 0}',
                    color: AccountingTheme.info),
              ]);
            }).toList(),
          ),
        ),
      ),
    );
  }

  // ═════════════════════════════
  // Helpers
  // ═════════════════════════════

  DataColumn _col(String label, {bool numeric = false}) {
    return DataColumn(
      numeric: numeric,
      label: Text(label,
          style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: context.accR.small)),
    );
  }

  DataCell _cell(String text,
      {Color? color, bool bold = false}) {
    return DataCell(Text(text,
        style: TextStyle(
            color: color ?? AccountingTheme.textSecondary,
            fontWeight: bold ? FontWeight.bold : FontWeight.normal,
            fontSize: context.accR.small)));
  }

  Widget _chipSummary(String label, String value, Color color) {
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: context.accR.spaceL, vertical: context.accR.spaceS),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Column(
        children: [
          Text(label,
              style: TextStyle(
                  color: color.withValues(alpha: 0.8),
                  fontSize: context.accR.small)),
          const SizedBox(height: 2),
          Text(value,
              style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: context.accR.body)),
        ],
      ),
    );
  }

  Widget _loader() {
    return const Center(
        child:
            CircularProgressIndicator(color: AccountingTheme.neonGreen));
  }

  Widget _emptyState(String msg) {
    return Center(
      child: Text(msg,
          style: const TextStyle(color: AccountingTheme.textMuted)),
    );
  }

  String _fmt(dynamic value) {
    if (value == null || value == 0) return '0';
    final n = value is num ? value : double.tryParse(value.toString()) ?? 0;
    return n.toStringAsFixed(0).replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (m) => '${m[1]},',
        );
  }
}
