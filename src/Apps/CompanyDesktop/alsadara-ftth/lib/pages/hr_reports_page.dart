// ignore_for_file: use_build_context_synchronously
import 'dart:io';
import 'package:flutter/material.dart';
import '../services/attendance_api_service.dart';
import '../services/vps_auth_service.dart';

class HrReportsPage extends StatefulWidget {
  final String? companyId;

  const HrReportsPage({super.key, this.companyId});

  @override
  State<HrReportsPage> createState() => _HrReportsPageState();
}

class _HrReportsPageState extends State<HrReportsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _api = AttendanceApiService.instance;

  String? get _companyId =>
      widget.companyId ?? VpsAuthService.instance.currentCompanyId;

  // Dashboard
  Map<String, dynamic>? _dashboardData;
  bool _loadingDashboard = false;

  // Attendance Report
  List<dynamic> _attendanceReport = [];
  Map<String, dynamic>? _attendanceSummary;
  bool _loadingAttendance = false;

  // Salary Report
  List<dynamic> _salaryReport = [];
  Map<String, dynamic>? _salarySummary;
  bool _loadingSalary = false;

  // Leaves Report
  List<dynamic> _leavesReport = [];
  Map<String, dynamic>? _leavesSummary;
  bool _loadingLeaves = false;

  // Filters
  int _selectedMonth = DateTime.now().month;
  int _selectedYear = DateTime.now().year;

  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        _loadTabData(_tabController.index);
      }
    });
    _loadDashboard();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _loadTabData(int index) {
    switch (index) {
      case 0:
        if (_dashboardData == null) _loadDashboard();
        break;
      case 1:
        if (_attendanceReport.isEmpty) _loadAttendanceReport();
        break;
      case 2:
        if (_salaryReport.isEmpty) _loadSalaryReport();
        break;
      case 3:
        if (_leavesReport.isEmpty) _loadLeavesReport();
        break;
    }
  }

  Future<void> _loadDashboard() async {
    if (_companyId == null) return;
    setState(() => _loadingDashboard = true);
    try {
      final res = await _api.getHrDashboard(_companyId!);
      if (res['success'] == true) {
        setState(() => _dashboardData = res['data']);
      }
    } catch (e) {
      _showError('خطأ في تحميل الداشبورد: $e');
    } finally {
      setState(() => _loadingDashboard = false);
    }
  }

  Future<void> _loadAttendanceReport() async {
    if (_companyId == null) return;
    setState(() => _loadingAttendance = true);
    try {
      final res = await _api.getAttendanceReport(
        companyId: _companyId!,
        month: _selectedMonth,
        year: _selectedYear,
      );
      if (res['success'] == true) {
        setState(() {
          _attendanceReport = res['data'] ?? [];
          _attendanceSummary = res['summary'];
        });
      }
    } catch (e) {
      _showError('خطأ في تحميل تقرير الحضور: $e');
    } finally {
      setState(() => _loadingAttendance = false);
    }
  }

  Future<void> _loadSalaryReport() async {
    if (_companyId == null) return;
    setState(() => _loadingSalary = true);
    try {
      final res = await _api.getSalaryReport(
        companyId: _companyId!,
        month: _selectedMonth,
        year: _selectedYear,
      );
      if (res['success'] == true) {
        setState(() {
          _salaryReport = res['data'] ?? [];
          _salarySummary = res['summary'];
        });
      }
    } catch (e) {
      _showError('خطأ في تحميل تقرير الرواتب: $e');
    } finally {
      setState(() => _loadingSalary = false);
    }
  }

  Future<void> _loadLeavesReport() async {
    if (_companyId == null) return;
    setState(() => _loadingLeaves = true);
    try {
      final res = await _api.getLeavesReport(
        companyId: _companyId!,
        year: _selectedYear,
        month: _selectedMonth,
      );
      if (res['success'] == true) {
        setState(() {
          _leavesReport = res['data'] ?? [];
          _leavesSummary = res['summary'];
        });
      }
    } catch (e) {
      _showError('خطأ في تحميل تقرير الإجازات: $e');
    } finally {
      setState(() => _loadingLeaves = false);
    }
  }

  void _refreshCurrentTab() {
    switch (_tabController.index) {
      case 0:
        _loadDashboard();
        break;
      case 1:
        _loadAttendanceReport();
        break;
      case 2:
        _loadSalaryReport();
        break;
      case 3:
        _loadLeavesReport();
        break;
    }
  }

  Future<void> _exportCsv(String type) async {
    if (_companyId == null) return;
    setState(() => _exporting = true);
    try {
      List<int> bytes;
      String fileName;
      switch (type) {
        case 'attendance':
          bytes = await _api.exportAttendanceCsv(
            companyId: _companyId!,
            month: _selectedMonth,
            year: _selectedYear,
          );
          fileName =
              'attendance_${_selectedYear}_${_selectedMonth.toString().padLeft(2, '0')}.csv';
          break;
        case 'salaries':
          bytes = await _api.exportSalariesCsv(
            companyId: _companyId!,
            month: _selectedMonth,
            year: _selectedYear,
          );
          fileName =
              'salaries_${_selectedYear}_${_selectedMonth.toString().padLeft(2, '0')}.csv';
          break;
        case 'leaves':
          bytes = await _api.exportLeavesCsv(
            companyId: _companyId!,
            year: _selectedYear,
          );
          fileName = 'leaves_$_selectedYear.csv';
          break;
        default:
          return;
      }

      // Save to Desktop
      final desktopPath = '${Platform.environment['USERPROFILE']}\\Desktop';
      final file = File('$desktopPath\\$fileName');
      await file.writeAsBytes(bytes);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم حفظ الملف في: ${file.path}'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      _showError('خطأ في تصدير الملف: $e');
    } finally {
      setState(() => _exporting = false);
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('تقارير الموارد البشرية',
              style: TextStyle(fontWeight: FontWeight.bold)),
          backgroundColor: const Color(0xFF1A237E),
          foregroundColor: Colors.white,
          bottom: TabBar(
            controller: _tabController,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white60,
            indicatorColor: Colors.amber,
            tabs: const [
              Tab(icon: Icon(Icons.dashboard), text: 'الداشبورد'),
              Tab(icon: Icon(Icons.access_time), text: 'الحضور'),
              Tab(icon: Icon(Icons.payments), text: 'الرواتب'),
              Tab(icon: Icon(Icons.event_busy), text: 'الإجازات'),
            ],
          ),
        ),
        body: Column(
          children: [
            // Month/Year selector
            _buildMonthYearSelector(),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildDashboardTab(),
                  _buildAttendanceTab(),
                  _buildSalaryTab(),
                  _buildLeavesTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMonthYearSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.grey.shade100,
      child: Row(
        children: [
          const Icon(Icons.calendar_today, size: 20, color: Color(0xFF1A237E)),
          const SizedBox(width: 8),
          const Text('الفترة:', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(width: 12),
          // Month dropdown
          DropdownButton<int>(
            value: _selectedMonth,
            items: List.generate(12, (i) {
              final m = i + 1;
              return DropdownMenuItem(
                value: m,
                child: Text(_arabicMonth(m)),
              );
            }),
            onChanged: (v) {
              if (v != null) {
                setState(() => _selectedMonth = v);
                _refreshCurrentTab();
              }
            },
          ),
          const SizedBox(width: 16),
          // Year dropdown
          DropdownButton<int>(
            value: _selectedYear,
            items: List.generate(5, (i) {
              final y = DateTime.now().year - i;
              return DropdownMenuItem(value: y, child: Text('$y'));
            }),
            onChanged: (v) {
              if (v != null) {
                setState(() => _selectedYear = v);
                _refreshCurrentTab();
              }
            },
          ),
          const Spacer(),
          // Refresh button
          IconButton(
            icon: const Icon(Icons.refresh, color: Color(0xFF1A237E)),
            onPressed: _refreshCurrentTab,
            tooltip: 'تحديث',
          ),
        ],
      ),
    );
  }

  // ==================== Dashboard Tab ====================

  Widget _buildDashboardTab() {
    if (_loadingDashboard) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_dashboardData == null) {
      return const Center(child: Text('لا توجد بيانات'));
    }

    final data = _dashboardData!;
    final today = data['Today'] ?? {};
    final monthly = data['MonthlyAttendance'] ?? {};
    final leaves = data['Leaves'] ?? {};
    final salaries = data['Salaries'] ?? {};
    final topLate = (data['TopLateEmployees'] as List?) ?? [];
    final topOvertime = (data['TopOvertimeEmployees'] as List?) ?? [];

    return Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        children: [
          // ===== الصف الأول: نظرة عامة (4) + الحضور الشهري (5) =====
          Row(
            children: [
              _compactStat('الموظفين', '${data['TotalEmployees'] ?? 0}',
                  Icons.people, Colors.blue),
              _compactStat('حضور اليوم', '${today['CheckedInCount'] ?? 0}',
                  Icons.check_circle, Colors.green),
              _compactStat('متأخرون', '${today['LateCount'] ?? 0}',
                  Icons.schedule, Colors.orange),
              _compactStat('غائبون', '${today['AbsentCount'] ?? 0}',
                  Icons.person_off, Colors.red),
              const SizedBox(width: 8),
              Container(width: 1, height: 40, color: Colors.grey.shade300),
              const SizedBox(width: 8),
              _compactStat('حضور شهري', '${monthly['TotalPresent'] ?? 0}',
                  Icons.thumb_up, Colors.green),
              _compactStat('تأخير', '${monthly['TotalLate'] ?? 0}',
                  Icons.warning, Colors.orange),
              _compactStat('دقائق تأخير', '${monthly['TotalLateMinutes'] ?? 0}',
                  Icons.timer_off, Colors.red),
              _compactStat(
                  'ساعات إضافية',
                  '${((monthly['TotalOvertimeMinutes'] ?? 0) / 60).round()}',
                  Icons.more_time,
                  Colors.teal),
              _compactStat('نسبة الحضور', '${monthly['AttendanceRate'] ?? 0}%',
                  Icons.analytics, Colors.indigo),
            ],
          ),
          const SizedBox(height: 10),

          // ===== الصف الثاني: الإجازات + الرواتب + أعلى تأخراً + أعلى ساعات إضافية =====
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // الإجازات
                Expanded(
                  flex: 2,
                  child: _dashSection(
                      'الإجازات', Icons.event_busy, Colors.purple, [
                    _compactInfoRow(
                        'إجازات معتمدة', '${leaves['ApprovedThisMonth'] ?? 0}'),
                    _compactInfoRow(
                        'أيام الإجازة', '${leaves['TotalDaysThisMonth'] ?? 0}'),
                    _compactInfoRow(
                        'طلبات معلقة', '${leaves['PendingRequests'] ?? 0}'),
                  ]),
                ),
                const SizedBox(width: 8),
                // الرواتب
                Expanded(
                  flex: 3,
                  child: _dashSection(
                      'الرواتب', Icons.payments, const Color(0xFF1A237E), [
                    _compactInfoRow('صافي (حسب الحضور)',
                        _formatNumber(salaries['TotalNet'])),
                    _compactInfoRow('الأساسي (مرجعي)',
                        _formatNumber(salaries['TotalBaseSalary'])),
                    _compactInfoRow(
                        'أيام حضور', '${salaries['TotalAttendanceDays'] ?? 0}'),
                    _compactInfoRow(
                        'الخصومات', _formatNumber(salaries['TotalDeductions'])),
                    _compactInfoRow(
                        'المكافآت', _formatNumber(salaries['TotalBonuses'])),
                    _compactInfoRow('مصروفة', '${salaries['PaidCount'] ?? 0}'),
                    _compactInfoRow(
                        'معلقة', '${salaries['PendingCount'] ?? 0}'),
                  ]),
                ),
                const SizedBox(width: 8),
                // أكثر تأخراً
                Expanded(
                  flex: 3,
                  child: _dashSection(
                    'أكثر الموظفين تأخراً',
                    Icons.schedule,
                    Colors.orange,
                    topLate.isEmpty
                        ? [
                            const Padding(
                                padding: EdgeInsets.all(8),
                                child: Text('لا يوجد',
                                    style: TextStyle(color: Colors.grey)))
                          ]
                        : topLate
                            .map((e) => _compactRankRow(
                                  e['EmployeeName'] ?? '',
                                  '${e['TotalLateMinutes'] ?? 0} د (${e['LateDays'] ?? 0} يوم)',
                                  Colors.orange,
                                ))
                            .toList(),
                  ),
                ),
                const SizedBox(width: 8),
                // أكثر ساعات إضافية
                Expanded(
                  flex: 3,
                  child: _dashSection(
                    'أكثر ساعات إضافية',
                    Icons.more_time,
                    Colors.teal,
                    topOvertime.isEmpty
                        ? [
                            const Padding(
                                padding: EdgeInsets.all(8),
                                child: Text('لا يوجد',
                                    style: TextStyle(color: Colors.grey)))
                          ]
                        : topOvertime
                            .map((e) => _compactRankRow(
                                  e['EmployeeName'] ?? '',
                                  '${((e['TotalOvertimeMinutes'] ?? 0) / 60).round()} ساعة',
                                  Colors.teal,
                                ))
                            .toList(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// بطاقة إحصائية مدمجة صغيرة (تتمدد لتملأ الصف)
  Widget _compactStat(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 2),
            Text(value,
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold, color: color)),
            Text(label,
                style: TextStyle(fontSize: 10, color: Colors.grey.shade700),
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }

  /// قسم داشبورد (بطاقة مع عنوان وقائمة بيانات)
  Widget _dashSection(
      String title, IconData icon, Color color, List<Widget> children) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // العنوان
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            color: color.withValues(alpha: 0.1),
            child: Row(
              children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(title,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: color),
                      overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),
          // المحتوى
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: children,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// صف معلومات مدمج (label: value)
  Widget _compactInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(label,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                overflow: TextOverflow.ellipsis),
          ),
          Text(value,
              style:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  /// صف ترتيب موظف مدمج
  Widget _compactRankRow(String name, String detail, Color color) {
    return Container(
      margin: const EdgeInsets.only(bottom: 3),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(name,
                style: const TextStyle(fontSize: 12),
                overflow: TextOverflow.ellipsis),
          ),
          Text(detail,
              style: TextStyle(
                  fontSize: 11, color: color, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  // ==================== Attendance Tab ====================

  Widget _buildAttendanceTab() {
    return Column(
      children: [
        // Action bar
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              if (_attendanceSummary != null) ...[
                _miniStat(
                    'موظفين', '${_attendanceSummary!['TotalEmployees'] ?? 0}'),
                _miniStat('نسبة الحضور',
                    '${_attendanceSummary!['AverageAttendanceRate'] ?? 0}%'),
                _miniStat('إجمالي التأخير',
                    '${_attendanceSummary!['TotalLateMinutes'] ?? 0} د'),
              ],
              const Spacer(),
              _exportButton('attendance'),
            ],
          ),
        ),
        Expanded(
          child: _loadingAttendance
              ? const Center(child: CircularProgressIndicator())
              : _attendanceReport.isEmpty
                  ? const Center(child: Text('لا توجد بيانات'))
                  : _buildAttendanceDataTable(),
        ),
      ],
    );
  }

  Widget _buildAttendanceDataTable() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(const Color(0xFFE8EAF6)),
              columnSpacing: 20,
              columns: const [
                DataColumn(
                    label: Text('الموظف',
                        style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(
                    label: Text('حضور',
                        style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(
                    label: Text('تأخير',
                        style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(
                    label: Text('غياب',
                        style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(
                    label: Text('نصف يوم',
                        style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(
                    label: Text('مغادرة مبكرة',
                        style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(
                    label: Text('دقائق تأخير',
                        style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(
                    label: Text('ساعات إضافية',
                        style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(
                    label: Text('ساعات عمل',
                        style: TextStyle(fontWeight: FontWeight.bold))),
              ],
              rows: _attendanceReport.map((emp) {
                return DataRow(cells: [
                  DataCell(
                    InkWell(
                      onTap: () => _showEmployeeDetail(emp),
                      child: Text(
                        emp['EmployeeName'] ?? '',
                        style: const TextStyle(
                          color: Color(0xFF1A237E),
                          fontWeight: FontWeight.bold,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ),
                  DataCell(
                      _statusBadge('${emp['PresentDays'] ?? 0}', Colors.green)),
                  DataCell(
                      _statusBadge('${emp['LateDays'] ?? 0}', Colors.orange)),
                  DataCell(
                      _statusBadge('${emp['AbsentDays'] ?? 0}', Colors.red)),
                  DataCell(Text('${emp['HalfDays'] ?? 0}')),
                  DataCell(Text('${emp['EarlyDepartureDays'] ?? 0}')),
                  DataCell(Text('${emp['TotalLateMinutes'] ?? 0}')),
                  DataCell(Text(
                      '${((emp['TotalOvertimeMinutes'] ?? 0) / 60).toStringAsFixed(1)}')),
                  DataCell(Text(
                      '${((emp['TotalWorkedMinutes'] ?? 0) / 60).toStringAsFixed(1)}')),
                ]);
              }).toList(),
            ),
          ),
        );
      },
    );
  }

  /// عرض تفاصيل حضور الموظف اليومية
  Future<void> _showEmployeeDetail(Map<String, dynamic> emp) async {
    final userId = emp['UserId'];
    if (userId == null) return;

    // عرض dialog فوراً مع مؤشر تحميل
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => _EmployeeDetailDialog(
        employeeName: emp['EmployeeName'] ?? '',
        userId: userId.toString(),
        month: _selectedMonth,
        year: _selectedYear,
        api: _api,
        arabicMonth: _arabicMonth,
      ),
    );
  }

  // ==================== Salary Tab ====================

  Widget _buildSalaryTab() {
    return Column(
      children: [
        // Action bar
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              if (_salarySummary != null) ...[
                _miniStat('إجمالي صافي',
                    _formatNumber(_salarySummary!['TotalNetSalary'])),
                _miniStat('الخصومات',
                    _formatNumber(_salarySummary!['TotalDeductions'])),
                _miniStat('مصروفة', '${_salarySummary!['PaidCount'] ?? 0}'),
                _miniStat('معلقة', '${_salarySummary!['PendingCount'] ?? 0}'),
              ],
              const Spacer(),
              _exportButton('salaries'),
            ],
          ),
        ),
        Expanded(
          child: _loadingSalary
              ? const Center(child: CircularProgressIndicator())
              : _salaryReport.isEmpty
                  ? const Center(child: Text('لا توجد بيانات'))
                  : _buildSalaryDataTable(),
        ),
      ],
    );
  }

  Widget _buildSalaryDataTable() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(const Color(0xFFE8EAF6)),
          columnSpacing: 16,
          columns: const [
            DataColumn(
                label: Text('الموظف',
                    style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(
                label: Text('الأساسي',
                    style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(
                label: Text('البدلات',
                    style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(
                label: Text('المكافآت',
                    style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(
                label: Text('الخصومات',
                    style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(
                label: Text('الصافي',
                    style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(
                label: Text('الحالة',
                    style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(
                label: Text('أيام حضور',
                    style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(
                label: Text('غياب',
                    style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(
                label: Text('خصم تأخير',
                    style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(
                label: Text('خصم غياب',
                    style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(
                label: Text('مكافأة إضافي',
                    style: TextStyle(fontWeight: FontWeight.bold))),
          ],
          rows: _salaryReport.map((s) {
            final status = s['Status'] ?? 'Pending';
            final isPaid = status == 'Paid';
            return DataRow(cells: [
              DataCell(Text(s['EmployeeName'] ?? '')),
              DataCell(Text(_formatNumber(s['BaseSalary']))),
              DataCell(Text(_formatNumber(s['Allowances']))),
              DataCell(Text(_formatNumber(s['Bonuses']))),
              DataCell(Text(_formatNumber(s['Deductions']),
                  style: const TextStyle(color: Colors.red))),
              DataCell(Text(_formatNumber(s['NetSalary']),
                  style: const TextStyle(fontWeight: FontWeight.bold))),
              DataCell(_statusBadge(isPaid ? 'مصروف' : 'معلق',
                  isPaid ? Colors.green : Colors.orange)),
              DataCell(Text('${s['AttendanceDays'] ?? 0}')),
              DataCell(Text('${s['AbsentDays'] ?? 0}')),
              DataCell(Text(_formatNumber(s['LateDeduction']))),
              DataCell(Text(_formatNumber(s['AbsentDeduction']))),
              DataCell(Text(_formatNumber(s['OvertimeBonus']))),
            ]);
          }).toList(),
        ),
      ),
    );
  }

  // ==================== Leaves Tab ====================

  Widget _buildLeavesTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              if (_leavesSummary != null) ...[
                _miniStat('إجمالي الطلبات',
                    '${_leavesSummary!['TotalRequests'] ?? 0}'),
                _miniStat('معتمدة', '${_leavesSummary!['TotalApproved'] ?? 0}'),
                _miniStat('مرفوضة', '${_leavesSummary!['TotalRejected'] ?? 0}'),
                _miniStat('معلقة', '${_leavesSummary!['TotalPending'] ?? 0}'),
              ],
              const Spacer(),
              _exportButton('leaves'),
            ],
          ),
        ),
        Expanded(
          child: _loadingLeaves
              ? const Center(child: CircularProgressIndicator())
              : _leavesReport.isEmpty
                  ? const Center(child: Text('لا توجد بيانات'))
                  : _buildLeavesDataTable(),
        ),
      ],
    );
  }

  Widget _buildLeavesDataTable() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(const Color(0xFFE8EAF6)),
          columnSpacing: 20,
          columns: const [
            DataColumn(
                label: Text('الموظف',
                    style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(
                label: Text('إجمالي طلبات',
                    style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(
                label: Text('معتمدة',
                    style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(
                label: Text('مرفوضة',
                    style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(
                label: Text('معلقة',
                    style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(
                label: Text('أيام معتمدة',
                    style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(
                label: Text('سنوية',
                    style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(
                label: Text('مرضية',
                    style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(
                label: Text('بدون راتب',
                    style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(
                label: Text('طارئة',
                    style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(
                label: Text('أخرى',
                    style: TextStyle(fontWeight: FontWeight.bold))),
          ],
          rows: _leavesReport.map((emp) {
            final byType = emp['ByType'] ?? {};
            return DataRow(cells: [
              DataCell(Text(emp['EmployeeName'] ?? '')),
              DataCell(Text('${emp['TotalRequests'] ?? 0}')),
              DataCell(_statusBadge('${emp['Approved'] ?? 0}', Colors.green)),
              DataCell(_statusBadge('${emp['Rejected'] ?? 0}', Colors.red)),
              DataCell(_statusBadge('${emp['Pending'] ?? 0}', Colors.orange)),
              DataCell(Text('${emp['TotalDaysApproved'] ?? 0}',
                  style: const TextStyle(fontWeight: FontWeight.bold))),
              DataCell(Text('${byType['Annual'] ?? 0}')),
              DataCell(Text('${byType['Sick'] ?? 0}')),
              DataCell(Text('${byType['Unpaid'] ?? 0}')),
              DataCell(Text('${byType['Emergency'] ?? 0}')),
              DataCell(Text('${byType['Other'] ?? 0}')),
            ]);
          }).toList(),
        ),
      ),
    );
  }

  // ==================== Helper Widgets ====================

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: Color(0xFF1A237E),
      ),
    );
  }

  Widget _statCard(String label, String value, IconData icon, Color color) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: 180,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 8),
            Text(value,
                style: TextStyle(
                    fontSize: 24, fontWeight: FontWeight.bold, color: color)),
            const SizedBox(height: 4),
            Text(label,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _infoCard(List<Widget> children) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: children),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey.shade700)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _rankItem(String name, String detail, IconData icon, Color color) {
    return Card(
      margin: const EdgeInsets.only(bottom: 4),
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text(name, style: const TextStyle(fontSize: 14)),
        trailing: Text(detail,
            style: TextStyle(
                fontSize: 12, color: color, fontWeight: FontWeight.bold)),
        dense: true,
      ),
    );
  }

  Widget _miniStat(String label, String value) {
    return Container(
      margin: const EdgeInsets.only(left: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFE8EAF6),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Text(value,
              style:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _statusBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(text,
          style: TextStyle(
              color: color, fontWeight: FontWeight.bold, fontSize: 13)),
    );
  }

  Widget _exportButton(String type) {
    return ElevatedButton.icon(
      onPressed: _exporting ? null : () => _exportCsv(type),
      icon: _exporting
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.white))
          : const Icon(Icons.download),
      label: const Text('تصدير CSV'),
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF1A237E),
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  String _formatNumber(dynamic value) {
    if (value == null) return '0';
    if (value is int) return value.toString();
    if (value is double) return value.round().toString();
    final n = double.tryParse(value.toString());
    if (n != null) return n.round().toString();
    return value.toString();
  }

  String _arabicMonth(int m) {
    const months = [
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
    return months[m - 1];
  }
}

/// ═══ Dialog تفصيلي لحضور الموظف اليومي ═══
class _EmployeeDetailDialog extends StatefulWidget {
  final String employeeName;
  final String userId;
  final int month;
  final int year;
  final AttendanceApiService api;
  final String Function(int) arabicMonth;

  const _EmployeeDetailDialog({
    required this.employeeName,
    required this.userId,
    required this.month,
    required this.year,
    required this.api,
    required this.arabicMonth,
  });

  @override
  State<_EmployeeDetailDialog> createState() => _EmployeeDetailDialogState();
}

class _EmployeeDetailDialogState extends State<_EmployeeDetailDialog> {
  bool _loading = true;
  List<dynamic> _dailyRecords = [];
  Map<String, dynamic>? _attendance;
  int _daysInMonth = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final res = await widget.api.getEmployeeReport(
        userId: widget.userId,
        month: widget.month,
        year: widget.year,
      );
      if (res['success'] == true && mounted) {
        final data = res['data'];
        final att = data?['Attendance'];
        setState(() {
          _attendance = att;
          _dailyRecords = (att?['DailyRecords'] as List?) ?? [];
          _daysInMonth = DateTime(widget.year, widget.month + 1, 0).day;
          _loading = false;
        });
      } else {
        if (mounted) setState(() => _loading = false);
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _statusArabic(String? status) {
    switch (status) {
      case 'Present':
        return 'حاضر';
      case 'Late':
        return 'متأخر';
      case 'Absent':
        return 'غائب';
      case 'HalfDay':
        return 'نصف يوم';
      case 'EarlyDeparture':
        return 'مغادرة مبكرة';
      default:
        return status ?? '-';
    }
  }

  Color _statusColor(String? status) {
    switch (status) {
      case 'Present':
        return Colors.green;
      case 'Late':
        return Colors.orange;
      case 'Absent':
        return Colors.red;
      case 'HalfDay':
        return Colors.blue;
      case 'EarlyDeparture':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  String _dayName(int year, int month, int day) {
    final date = DateTime(year, month, day);
    const days = [
      'الاثنين',
      'الثلاثاء',
      'الأربعاء',
      'الخميس',
      'الجمعة',
      'السبت',
      'الأحد'
    ];
    return days[date.weekday - 1];
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          width: 900,
          height: 650,
          padding: const EdgeInsets.all(0),
          child: Column(
            children: [
              // العنوان
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                decoration: const BoxDecoration(
                  color: Color(0xFF1A237E),
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(16),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.person, color: Colors.white, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${widget.employeeName} - ${widget.arabicMonth(widget.month)} ${widget.year}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close,
                          color: Colors.white, size: 20),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              // الملخص
              if (_attendance != null && !_loading)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  color: Colors.grey.shade100,
                  child: Row(
                    children: [
                      _summaryChip('حضور',
                          '${_attendance!['PresentDays'] ?? 0}', Colors.green),
                      _summaryChip('تأخير', '${_attendance!['LateDays'] ?? 0}',
                          Colors.orange),
                      _summaryChip('غياب', '${_attendance!['AbsentDays'] ?? 0}',
                          Colors.red),
                      _summaryChip('نصف يوم',
                          '${_attendance!['HalfDays'] ?? 0}', Colors.blue),
                      _summaryChip(
                          'دقائق تأخير',
                          '${_attendance!['TotalLateMinutes'] ?? 0}',
                          Colors.deepOrange),
                      _summaryChip(
                          'ساعات عمل',
                          '${((_attendance!['TotalWorkedMinutes'] ?? 0) / 60).toStringAsFixed(1)}',
                          Colors.teal),
                    ],
                  ),
                ),
              // الجدول اليومي
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _buildDailyTable(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _summaryChip(String label, String value, Color color) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        padding: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Text(value,
                style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.bold, color: color)),
            Text(label, style: const TextStyle(fontSize: 10)),
          ],
        ),
      ),
    );
  }

  Widget _buildDailyTable() {
    // بناء قائمة كل أيام الشهر
    final Map<String, Map<String, dynamic>> recordMap = {};
    for (final r in _dailyRecords) {
      recordMap[r['Date'] ?? ''] = r as Map<String, dynamic>;
    }

    return SingleChildScrollView(
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 960),
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(const Color(0xFFE8EAF6)),
          columnSpacing: 10,
          dataRowMinHeight: 36,
          dataRowMaxHeight: 42,
          columns: const [
            DataColumn(
                label: Text('اليوم',
                    style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(
                label: Text('التاريخ',
                    style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(
                label: Text('الحالة',
                    style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(
                label: Text('وقت الدخول',
                    style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(
                label: Text('وقت الخروج',
                    style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(
                label: Text('ساعات العمل',
                    style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(
                label: Text('تأخير (د)',
                    style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(
                label: Text('إضافي (د)',
                    style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(
                label: Text('إجراءات',
                    style: TextStyle(fontWeight: FontWeight.bold))),
          ],
          rows: List.generate(_daysInMonth, (i) {
            final day = i + 1;
            final dateStr =
                '${widget.year}-${widget.month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
            final record = recordMap[dateStr];
            final dayName = _dayName(widget.year, widget.month, day);
            final isFriday = DateTime(widget.year, widget.month, day).weekday ==
                DateTime.friday;

            final status = record?['Status'];
            final checkIn = record?['CheckIn'] ?? '-';
            final checkOut = record?['CheckOut'] ?? '-';
            final worked = record?['WorkedMinutes'];
            final workedHours =
                worked != null ? (worked / 60).toStringAsFixed(1) : '-';
            final late = record?['LateMinutes'];
            final overtime = record?['OvertimeMinutes'];

            // تلوين الصف
            final rowColor = isFriday && record == null
                ? Colors.grey.shade200
                : record == null
                    ? Colors.red.withValues(alpha: 0.04)
                    : null;

            return DataRow(
              color:
                  rowColor != null ? WidgetStateProperty.all(rowColor) : null,
              cells: [
                DataCell(Text(dayName,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight:
                            isFriday ? FontWeight.bold : FontWeight.normal,
                        color: isFriday ? Colors.red : null))),
                DataCell(Text(dateStr, style: const TextStyle(fontSize: 12))),
                DataCell(record != null
                    ? Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: _statusColor(status).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          _statusArabic(status),
                          style: TextStyle(
                              fontSize: 11,
                              color: _statusColor(status),
                              fontWeight: FontWeight.bold),
                        ),
                      )
                    : Text(
                        isFriday ? 'عطلة' : 'لا بصمة',
                        style: TextStyle(
                            fontSize: 11,
                            color:
                                isFriday ? Colors.grey : Colors.red.shade300),
                      )),
                DataCell(Text(checkIn,
                    style: TextStyle(
                        fontSize: 12,
                        color: checkIn == '-' ? Colors.grey : Colors.black))),
                DataCell(Text(checkOut,
                    style: TextStyle(
                        fontSize: 12,
                        color: checkOut == '-' ? Colors.grey : Colors.black))),
                DataCell(Text(workedHours,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color:
                            workedHours == '-' ? Colors.grey : Colors.black))),
                DataCell(Text(late != null && late > 0 ? '$late' : '-',
                    style: TextStyle(
                        fontSize: 12,
                        color: late != null && late > 0
                            ? Colors.orange
                            : Colors.grey))),
                DataCell(Text(
                    overtime != null && overtime > 0 ? '$overtime' : '-',
                    style: TextStyle(
                        fontSize: 12,
                        color: overtime != null && overtime > 0
                            ? Colors.teal
                            : Colors.grey))),
                // زر التعديل/الإنشاء
                DataCell(Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(
                        record != null ? Icons.edit : Icons.add_circle_outline,
                        size: 18,
                        color: record != null
                            ? Colors.blue
                            : Colors.green.shade600,
                      ),
                      tooltip: record != null ? 'تعديل' : 'إضافة بصمة',
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 28, minHeight: 28),
                      onPressed: () =>
                          _showEditAttendanceDialog(dateStr, record),
                    ),
                    if (record != null)
                      IconButton(
                        icon: Icon(Icons.delete_outline,
                            size: 18, color: Colors.red.shade400),
                        tooltip: 'حذف',
                        padding: EdgeInsets.zero,
                        constraints:
                            const BoxConstraints(minWidth: 28, minHeight: 28),
                        onPressed: () =>
                            _confirmDeleteAttendance(record['Id'], dateStr),
                      ),
                  ],
                )),
              ],
            );
          }),
        ),
      ),
    );
  }

  // ==================== دايالوج تعديل/إنشاء سجل حضور ====================

  void _showEditAttendanceDialog(
      String dateStr, Map<String, dynamic>? existingRecord) {
    final isEdit = existingRecord != null;
    final statusOptions = [
      {'value': 0, 'label': 'حاضر', 'key': 'Present'},
      {'value': 1, 'label': 'متأخر', 'key': 'Late'},
      {'value': 2, 'label': 'غائب', 'key': 'Absent'},
      {'value': 3, 'label': 'نصف يوم', 'key': 'HalfDay'},
      {'value': 4, 'label': 'مغادرة مبكرة', 'key': 'EarlyDeparture'},
    ];

    int statusToInt(String? s) {
      switch (s) {
        case 'Present':
          return 0;
        case 'Late':
          return 1;
        case 'Absent':
          return 2;
        case 'HalfDay':
          return 3;
        case 'EarlyDeparture':
          return 4;
        default:
          return 0;
      }
    }

    int selectedStatus =
        isEdit ? statusToInt(existingRecord?['Status']) : 0;
    final checkInCtrl =
        TextEditingController(text: existingRecord?['CheckIn'] ?? '');
    final checkOutCtrl =
        TextEditingController(text: existingRecord?['CheckOut'] ?? '');
    final lateCtrl = TextEditingController(
        text: (existingRecord?['LateMinutes'] ?? 0).toString());
    final overtimeCtrl = TextEditingController(
        text: (existingRecord?['OvertimeMinutes'] ?? 0).toString());
    final earlyDepCtrl = TextEditingController(
        text: (existingRecord?['EarlyDepartureMinutes'] ?? 0).toString());
    final notesCtrl =
        TextEditingController(text: existingRecord?['Notes'] ?? '');
    bool saving = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: Row(
              children: [
                Icon(isEdit ? Icons.edit : Icons.add_circle,
                    color: isEdit ? Colors.blue : Colors.green),
                const SizedBox(width: 8),
                Text(
                  isEdit
                      ? 'تعديل بصمة - $dateStr'
                      : 'إضافة بصمة - $dateStr',
                  style: const TextStyle(fontSize: 16),
                ),
              ],
            ),
            content: SizedBox(
              width: 450,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // الحالة
                    DropdownButtonFormField<int>(
                      value: selectedStatus,
                      decoration: const InputDecoration(
                        labelText: 'الحالة',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                      ),
                      items: statusOptions
                          .map((s) => DropdownMenuItem<int>(
                                value: s['value'] as int,
                                child: Text(s['label'] as String),
                              ))
                          .toList(),
                      onChanged: (v) {
                        if (v != null) {
                          setDialogState(() => selectedStatus = v);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    // وقت الدخول والخروج
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: checkInCtrl,
                            decoration: InputDecoration(
                              labelText: 'وقت الدخول (HH:mm)',
                              border: const OutlineInputBorder(),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                              suffixIcon: IconButton(
                                icon: const Icon(Icons.access_time, size: 20),
                                onPressed: () async {
                                  final time = await showTimePicker(
                                    context: ctx,
                                    initialTime: _parseTime(checkInCtrl.text),
                                  );
                                  if (time != null) {
                                    checkInCtrl.text =
                                        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
                                  }
                                },
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: checkOutCtrl,
                            decoration: InputDecoration(
                              labelText: 'وقت الخروج (HH:mm)',
                              border: const OutlineInputBorder(),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                              suffixIcon: IconButton(
                                icon: const Icon(Icons.access_time, size: 20),
                                onPressed: () async {
                                  final time = await showTimePicker(
                                    context: ctx,
                                    initialTime: _parseTime(checkOutCtrl.text),
                                  );
                                  if (time != null) {
                                    checkOutCtrl.text =
                                        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
                                  }
                                },
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // دقائق التأخير والإضافي والمغادرة المبكرة
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: lateCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'دقائق التأخير',
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: overtimeCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'دقائق إضافية',
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: earlyDepCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'مغادرة مبكرة (د)',
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // ملاحظات
                    TextFormField(
                      controller: notesCtrl,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'ملاحظات',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: saving ? null : () => Navigator.pop(ctx),
                child: const Text('إلغاء'),
              ),
              ElevatedButton.icon(
                onPressed: saving
                    ? null
                    : () async {
                        setDialogState(() => saving = true);
                        try {
                          if (isEdit) {
                            final recordId = existingRecord!['Id'];
                            if (recordId == null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text('خطأ: لا يوجد معرف للسجل')),
                              );
                              setDialogState(() => saving = false);
                              return;
                            }
                            await widget.api.updateAttendanceRecord(
                              recordId is int ? recordId : int.parse(recordId.toString()),
                              status: selectedStatus,
                              checkInTime: checkInCtrl.text.isNotEmpty
                                  ? checkInCtrl.text
                                  : null,
                              checkOutTime: checkOutCtrl.text.isNotEmpty
                                  ? checkOutCtrl.text
                                  : null,
                              clearCheckIn: checkInCtrl.text.isEmpty,
                              clearCheckOut: checkOutCtrl.text.isEmpty,
                              lateMinutes:
                                  int.tryParse(lateCtrl.text) ?? 0,
                              overtimeMinutes:
                                  int.tryParse(overtimeCtrl.text) ?? 0,
                              earlyDepartureMinutes:
                                  int.tryParse(earlyDepCtrl.text) ?? 0,
                              notes: notesCtrl.text,
                            );
                          } else {
                            await widget.api.createAttendanceRecord(
                              userId: widget.userId,
                              date: dateStr,
                              status: selectedStatus,
                              checkInTime: checkInCtrl.text.isNotEmpty
                                  ? checkInCtrl.text
                                  : null,
                              checkOutTime: checkOutCtrl.text.isNotEmpty
                                  ? checkOutCtrl.text
                                  : null,
                              lateMinutes:
                                  int.tryParse(lateCtrl.text) ?? 0,
                              overtimeMinutes:
                                  int.tryParse(overtimeCtrl.text) ?? 0,
                              earlyDepartureMinutes:
                                  int.tryParse(earlyDepCtrl.text) ?? 0,
                              notes: notesCtrl.text.isNotEmpty
                                  ? notesCtrl.text
                                  : null,
                            );
                          }
                          if (ctx.mounted) Navigator.pop(ctx);
                          // إعادة تحميل البيانات
                          _loadData();
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(isEdit
                                    ? 'تم تعديل سجل الحضور بنجاح'
                                    : 'تم إضافة سجل الحضور بنجاح'),
                                backgroundColor: Colors.green,
                              ),
                            );
                          }
                        } catch (e) {
                          setDialogState(() => saving = false);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('خطأ: $e'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        }
                      },
                icon: saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : Icon(isEdit ? Icons.save : Icons.add),
                label: Text(isEdit ? 'حفظ التعديلات' : 'إضافة'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isEdit ? Colors.blue : Colors.green,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  TimeOfDay _parseTime(String text) {
    if (text.isEmpty) return TimeOfDay.now();
    final parts = text.split(':');
    if (parts.length != 2) return TimeOfDay.now();
    return TimeOfDay(
      hour: int.tryParse(parts[0]) ?? 0,
      minute: int.tryParse(parts[1]) ?? 0,
    );
  }

  void _confirmDeleteAttendance(dynamic recordId, String dateStr) {
    if (recordId == null) return;
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.red),
              SizedBox(width: 8),
              Text('تأكيد الحذف', style: TextStyle(fontSize: 16)),
            ],
          ),
          content: Text('هل تريد حذف سجل حضور $dateStr؟'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(ctx);
                try {
                  final id =
                      recordId is int ? recordId : int.parse(recordId.toString());
                  await widget.api.deleteAttendanceRecord(id);
                  _loadData();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('تم حذف سجل الحضور'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('خطأ في الحذف: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child:
                  const Text('حذف', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }
}
