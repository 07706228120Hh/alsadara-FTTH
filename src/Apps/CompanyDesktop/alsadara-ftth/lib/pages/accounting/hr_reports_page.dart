import 'package:flutter/material.dart';
import '../../frontend/frontend.dart'; // نظام تصميم الصدارة الموحّد (sd)
import '../../services/accounting_service.dart';

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

  bool _salLoading = true;
  List<dynamic> _salData = [];
  Map<String, dynamic> _salSummary = {};

  bool _leaveLoading = true;
  List<dynamic> _leaveData = [];

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
      }
    } catch (_) {}
    setState(() => _leaveLoading = false);
  }

  void _reloadCurrent() => _loadTab(_tabController.index);

  @override
  Widget build(BuildContext context) {
    return SdTheme.scope(
      child: Scaffold(
        backgroundColor: SdColors.ground,
        appBar: SdAppBar(
          title: 'تقارير الموارد البشرية',
          actions: [
            SdAppBarAction(
              icon: Icons.refresh,
              label: 'تحديث',
              onPressed: _reloadCurrent,
            ),
          ],
          bottom: SdTabBar(
            controller: _tabController,
            isScrollable: context.sd.isPhone,
            height: 72,
            tabs: const [
              Tab(text: 'لوحة عامة', icon: Icon(Icons.dashboard, size: 18)),
              Tab(text: 'الحضور', icon: Icon(Icons.schedule, size: 18)),
              Tab(text: 'الرواتب', icon: Icon(Icons.payments, size: 18)),
              Tab(text: 'الإجازات', icon: Icon(Icons.beach_access, size: 18)),
            ],
          ),
        ),
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              _buildMonthSelector(),
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

  Widget _buildMonthSelector() {
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: context.sd.gutter, vertical: SdSpace.sm),
      color: SdColors.surface,
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_right, color: SdColors.muted),
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
              style: SdText.titleSm,
              textAlign: TextAlign.center,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_left, color: SdColors.muted),
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
      padding: EdgeInsets.all(context.sd.gutter),
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
                  Icons.check_circle, SdStatus.success.tone),
              _statCard('متأخر', '${today['LateCount'] ?? 0}', Icons.timer,
                  SdStatus.warning.tone),
              _statCard('غائب', '${today['AbsentCount'] ?? 0}',
                  Icons.cancel, SdStatus.danger.tone),
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
                  Icons.check, SdStatus.success.tone),
              _statCard('تأخير', '${monthly['TotalLate'] ?? 0}',
                  Icons.timer, SdStatus.warning.tone),
              _statCard('غياب', '${monthly['TotalAbsent'] ?? 0}',
                  Icons.close, SdStatus.danger.tone),
              _statCard(
                  'نسبة الحضور',
                  '${((monthly['AttendanceRate'] ?? 0) as num).toStringAsFixed(1)}%',
                  Icons.percent,
                  SdStatus.info.tone),
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
                  Icons.payments, SdStatus.info.tone),
              _statCard('الخصومات', _fmt(salaries['TotalDeductions']),
                  Icons.remove_circle, SdStatus.danger.tone),
              _statCard('المكافآت', _fmt(salaries['TotalBonuses']),
                  Icons.card_giftcard, SdStatus.success.tone),
              _statCard('مصروفة', '${salaries['PaidCount'] ?? 0}',
                  Icons.done_all, SdStatus.success.tone),
              _statCard('معلقة', '${salaries['PendingCount'] ?? 0}',
                  Icons.pending, SdStatus.warning.tone),
            ],
          ),
          const SizedBox(height: 20),
          // أكثر تأخراً
          if (topLate.isNotEmpty) ...[
            _sectionTitle('الأكثر تأخراً'),
            ...topLate.take(5).map((e) => _rankTile(
                  e['EmployeeName'] ?? '',
                  '${e['TotalLateMinutes'] ?? 0} دقيقة',
                  SdStatus.danger.tone,
                )),
            const SizedBox(height: 16),
          ],
          // أكثر عملاً إضافياً
          if (topOvertime.isNotEmpty) ...[
            _sectionTitle('الأكثر عملاً إضافياً'),
            ...topOvertime.take(5).map((e) => _rankTile(
                  e['EmployeeName'] ?? '',
                  '${e['TotalOvertimeMinutes'] ?? 0} دقيقة',
                  SdStatus.success.tone,
                )),
          ],
        ],
      ),
    );
  }

  Widget _sectionTitle(String t) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(t, style: SdText.titleSm),
    );
  }

  Widget _statCard(String label, String value, IconData icon, SdTone tone) {
    return Container(
      width: context.sd.isPhone ? 100 : 150,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: SdColors.surface,
        borderRadius: BorderRadius.circular(SdRadius.md),
        boxShadow: SdDepth.raised(depth: SdDepth.small),
        border: Border(top: BorderSide(color: tone.base, width: 3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: tone.base, size: 22),
          const SizedBox(height: 4),
          Text(value,
              style: TextStyle(
                  fontFamily: SdText.family,
                  color: tone.text,
                  fontWeight: FontWeight.w900,
                  fontSize: 15)),
          const SizedBox(height: 2),
          Text(label,
              style: SdText.caption, textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _rankTile(String name, String detail, SdTone tone) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: SdColors.surface,
        borderRadius: BorderRadius.circular(SdRadius.xs),
        boxShadow: SdDepth.raised(depth: SdDepth.small),
      ),
      child: Row(
        children: [
          Expanded(child: Text(name, style: SdText.body)),
          Text(detail,
              style: TextStyle(
                  fontFamily: SdText.family,
                  color: tone.text,
                  fontWeight: FontWeight.w900,
                  fontSize: 12.5)),
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

    // الهاتف: صفوف كبطاقات عمودية (بدل التمرير الأفقي) — نفس القيم تماماً
    if (context.sd.isPhone) {
      return ListView.builder(
        padding: const EdgeInsets.all(8),
        itemCount: _attData.length,
        itemBuilder: (context, i) {
          final e = _attData[i];
          return _recordCard(
            title: '${e['EmployeeName'] ?? ''}',
            rows: [
              _mRow('حضور', '${e['PresentDays'] ?? 0}',
                  color: SdColors.success),
              _mRow('تأخير', '${e['LateDays'] ?? 0}',
                  color: SdColors.warningText),
              _mRow('غياب', '${e['AbsentDays'] ?? 0}', color: SdColors.danger),
              _mRow('نصف يوم', '${e['HalfDays'] ?? 0}'),
              _mRow('مغادرة مبكرة', '${e['EarlyDepartureDays'] ?? 0}'),
              _mRow('دقائق تأخير', '${e['TotalLateMinutes'] ?? 0}',
                  color: SdColors.danger),
              _mRow('دقائق إضافية', '${e['TotalOvertimeMinutes'] ?? 0}',
                  color: SdColors.success),
            ],
          );
        },
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(
              minWidth: MediaQuery.of(context).size.width - 16),
          child: _styledTable(
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
                    color: SdColors.success),
                _cell('${e['LateDays'] ?? 0}', color: SdColors.warningText),
                _cell('${e['AbsentDays'] ?? 0}', color: SdColors.danger),
                _cell('${e['HalfDays'] ?? 0}'),
                _cell('${e['EarlyDepartureDays'] ?? 0}'),
                _cell('${e['TotalLateMinutes'] ?? 0}', color: SdColors.danger),
                _cell('${e['TotalOvertimeMinutes'] ?? 0}',
                    color: SdColors.success),
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
              horizontal: context.sd.gutter, vertical: SdSpace.sm),
          child: Row(
            children: [
              Expanded(
                  child: _chipSummary('الأساسي',
                      _fmt(_salSummary['TotalBaseSalary']), SdStatus.info.tone)),
              const SizedBox(width: 6),
              Expanded(
                  child: _chipSummary('الصافي',
                      _fmt(_salSummary['TotalNetSalary']), SdStatus.success.tone)),
              const SizedBox(width: 6),
              Expanded(
                  child: _chipSummary('الخصومات',
                      _fmt(_salSummary['TotalDeductions']), SdStatus.danger.tone)),
              const SizedBox(width: 6),
              Expanded(
                  child: _chipSummary('الإضافي',
                      _fmt(_salSummary['TotalOvertimeBonus']), SdStatus.success.tone)),
            ],
          ),
        ),
        Expanded(
          child: context.sd.isPhone
              ? _buildSalaryCardsMobile()
              : SingleChildScrollView(
            padding: const EdgeInsets.all(8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                    minWidth: MediaQuery.of(context).size.width - 16),
                child: _styledTable(
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
                    final statusTone = _salaryStatusTone(status.toString());
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
                      _cell(_fmt(e['Deductions']), color: SdColors.danger),
                      _cell(_fmt(e['LateDeduction']), color: SdColors.danger),
                      _cell(_fmt(e['AbsentDeduction']), color: SdColors.danger),
                      _cell(_fmt(e['OvertimeBonus']), color: SdColors.success),
                      _cell(_fmt(e['NetSalary']), bold: true),
                      DataCell(Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: statusTone.tint,
                          borderRadius: BorderRadius.circular(SdRadius.xs),
                        ),
                        child: Text(statusAr[status] ?? status,
                            style: TextStyle(
                                fontFamily: SdText.family,
                                color: statusTone.text,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800)),
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

    // الهاتف: صفوف كبطاقات عمودية (بدل التمرير الأفقي) — نفس القيم تماماً
    if (context.sd.isPhone) {
      return ListView.builder(
        padding: const EdgeInsets.all(8),
        itemCount: _leaveData.length,
        itemBuilder: (context, i) {
          final e = _leaveData[i];
          return _recordCard(
            title: '${e['EmployeeName'] ?? ''}',
            rows: [
              _mRow('إجمالي الطلبات', '${e['TotalRequests'] ?? 0}'),
              _mRow('مقبولة', '${e['Approved'] ?? 0}',
                  color: SdColors.success),
              _mRow('مرفوضة', '${e['Rejected'] ?? 0}', color: SdColors.danger),
              _mRow('معلقة', '${e['Pending'] ?? 0}',
                  color: SdColors.warningText),
              _mRow('أيام مقبولة', '${e['TotalDaysApproved'] ?? 0}',
                  color: SdColors.info),
            ],
          );
        },
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(
              minWidth: MediaQuery.of(context).size.width - 16),
          child: _styledTable(
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
                _cell('${e['Approved'] ?? 0}', color: SdColors.success),
                _cell('${e['Rejected'] ?? 0}', color: SdColors.danger),
                _cell('${e['Pending'] ?? 0}', color: SdColors.warningText),
                _cell('${e['TotalDaysApproved'] ?? 0}', color: SdColors.info),
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

  // ═════════════════════════════
  // عرض الهاتف: بطاقات بدل الجداول العريضة
  // (نفس القيم/الصيغ تماماً — إعادة تقديم بصري فقط)
  // ═════════════════════════════

  /// بطاقة سجل واحد: عنوان (اسم الموظف) + صفوف تسمية/قيمة.
  Widget _recordCard({required String title, required List<Widget> rows}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SdCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: SdText.titleSm),
            const Divider(height: 14, color: SdColors.divider),
            ...rows,
          ],
        ),
      ),
    );
  }

  /// صف تسمية/قيمة داخل بطاقة الهاتف (يدعم لوناً اختيارياً).
  Widget _mRow(String label, String value, {Color? color, bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(child: Text(label, style: SdText.bodySm)),
          const SizedBox(width: 12),
          Text(
            value,
            textAlign: TextAlign.end,
            style: TextStyle(
              fontFamily: SdText.family,
              color: color ?? SdColors.ink,
              fontWeight: bold ? FontWeight.w900 : FontWeight.w700,
              fontSize: bold ? 15 : 13.5,
            ),
          ),
        ],
      ),
    );
  }

  /// قائمة بطاقات الرواتب على الهاتف — نفس القيم/الصيغ المستخدمة في الجدول.
  Widget _buildSalaryCardsMobile() {
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: _salData.length,
      itemBuilder: (context, i) {
        final e = _salData[i];
        final status = (e['Status'] ?? 'Pending').toString();
        final statusTone = _salaryStatusTone(status);
        const statusAr = {
          'Pending': 'معلق',
          'Paid': 'مدفوع',
          'PartiallyPaid': 'جزئي',
          'Cancelled': 'ملغي',
        };
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: SdCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text('${e['EmployeeName'] ?? ''}',
                          style: SdText.titleSm),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: statusTone.tint,
                        borderRadius: BorderRadius.circular(SdRadius.xs),
                      ),
                      child: Text(
                        statusAr[status] ?? status,
                        style: TextStyle(
                          fontFamily: SdText.family,
                          color: statusTone.text,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const Divider(height: 14, color: SdColors.divider),
                _mRow('الأساسي', _fmt(e['BaseSalary'])),
                _mRow('البدلات', _fmt(e['Allowances'])),
                _mRow('الخصومات', _fmt(e['Deductions']),
                    color: SdColors.danger),
                _mRow('خصم تأخير', _fmt(e['LateDeduction']),
                    color: SdColors.danger),
                _mRow('خصم غياب', _fmt(e['AbsentDeduction']),
                    color: SdColors.danger),
                _mRow('مكافأة إضافي', _fmt(e['OvertimeBonus']),
                    color: SdColors.success),
                const Divider(height: 14, color: SdColors.divider),
                _mRow('الصافي', _fmt(e['NetSalary']), bold: true),
              ],
            ),
          ),
        );
      },
    );
  }

  SdTone _salaryStatusTone(String status) {
    switch (status) {
      case 'Paid':
        return SdStatus.success.tone;
      case 'PartiallyPaid':
        return SdStatus.info.tone;
      case 'Cancelled':
        return SdStatus.danger.tone;
      case 'Pending':
        return SdStatus.warning.tone;
      default:
        return SdGroup.neutral.tone;
    }
  }

  DataTable _styledTable(
      {required List<DataColumn> columns, required List<DataRow> rows}) {
    return DataTable(
      headingRowColor: WidgetStateProperty.all(SdColors.primary),
      dataRowColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.hovered)) {
          return SdColors.surfaceAlt;
        }
        return SdColors.surface;
      }),
      border: TableBorder.all(color: SdColors.divider, width: 0.5),
      columnSpacing: 12,
      horizontalMargin: 10,
      headingRowHeight: 40,
      dataRowMinHeight: 36,
      dataRowMaxHeight: 40,
      columns: columns,
      rows: rows,
    );
  }

  DataColumn _col(String label, {bool numeric = false}) {
    return DataColumn(
      numeric: numeric,
      label: Text(label,
          style: const TextStyle(
              fontFamily: SdText.family,
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 12.5)),
    );
  }

  DataCell _cell(String text, {Color? color, bool bold = false}) {
    return DataCell(Text(text,
        style: TextStyle(
            fontFamily: SdText.family,
            color: color ?? SdColors.ink,
            fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
            fontSize: 12.5)));
  }

  Widget _chipSummary(String label, String value, SdTone tone) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: SdSpace.md, vertical: SdSpace.sm),
      decoration: BoxDecoration(
        color: tone.tint,
        borderRadius: BorderRadius.circular(SdRadius.xs),
        boxShadow: [BoxShadow(color: tone.tintEdge, offset: const Offset(0, SdDepth.chip))],
      ),
      child: Column(
        children: [
          Text(label,
              style: TextStyle(
                  fontFamily: SdText.family,
                  color: tone.text,
                  fontWeight: FontWeight.w700,
                  fontSize: 11.5)),
          const SizedBox(height: 2),
          Text(value,
              style: TextStyle(
                  fontFamily: SdText.family,
                  color: tone.text,
                  fontWeight: FontWeight.w900,
                  fontSize: 14)),
        ],
      ),
    );
  }

  Widget _loader() {
    return const Center(child: CircularProgressIndicator());
  }

  Widget _emptyState(String msg) {
    return Center(
      child: SdEmptyState(title: msg, icon: Icons.assessment_rounded),
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
