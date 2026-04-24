import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/accounting_service.dart';
import '../../services/attendance_api_service.dart';
import '../../services/period_closing_service.dart';
import '../../services/audit_trail_service.dart';
import '../../theme/accounting_theme.dart';
import '../../theme/accounting_responsive.dart';
import '../../permissions/permissions.dart';

/// صفحة إدارة الرواتب
class SalariesPage extends StatefulWidget {
  final String? companyId;

  const SalariesPage({super.key, this.companyId});

  @override
  State<SalariesPage> createState() => _SalariesPageState();
}

class _SalariesPageState extends State<SalariesPage> {
  bool _isLoading = true;
  String? _errorMessage;
  List<dynamic> _salaries = [];
  int _selectedMonth = DateTime.now().month;
  int _selectedYear = DateTime.now().year;

  final _statusLabels = {
    'Pending': 'معلق',
    'Paid': 'مدفوع',
    'PartiallyPaid': 'مدفوع جزئياً',
    'Cancelled': 'ملغي',
  };

  final _months = [
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
      final result = await AccountingService.instance.getSalaries(
        companyId: widget.companyId,
        month: _selectedMonth,
        year: _selectedYear,
      );
      if (result['success'] == true) {
        _salaries = (result['data'] is List) ? result['data'] : [];
      } else {
        _errorMessage = result['message'] ?? 'خطأ';
      }
    } catch (e) {
      _errorMessage = 'خطأ';
    }
    setState(() {
      _isLoading = false;
    });
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
              _buildPageToolbar(),
              _buildMonthSelector(),
              _buildSummaryBar(),
              Expanded(
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(
                            color: AccountingTheme.neonGreen))
                    : _errorMessage != null
                        ? Center(
                            child: Text(_errorMessage!,
                                style: const TextStyle(
                                    color: AccountingTheme.danger)))
                        : _buildSalariesList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPageToolbar() {
    final isMobile = context.accR.isMobile;
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
            child: Icon(Icons.payments_rounded,
                color: Colors.white, size: isMobile ? 16 : context.accR.iconM),
          ),
          SizedBox(width: isMobile ? 6 : context.accR.spaceM),
          Expanded(
            child: Text('الرواتب',
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.cairo(
                    fontSize: isMobile ? 14 : context.accR.headingMedium,
                    fontWeight: FontWeight.bold,
                    color: AccountingTheme.textPrimary)),
          ),
          IconButton(
            onPressed: _loadData,
            icon: Icon(Icons.refresh, size: isMobile ? 18 : context.accR.iconM),
            tooltip: 'تحديث',
            style: IconButton.styleFrom(
                foregroundColor: AccountingTheme.textSecondary),
          ),
          if (isMobile) ...[
            if (PermissionManager.instance.canAdd('accounting.salaries'))
            SizedBox(
              height: 28,
              child: OutlinedButton(
                onPressed: _showSalaryRosterDialog,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AccountingTheme.info,
                  side: const BorderSide(color: AccountingTheme.info),
                  padding: EdgeInsets.symmetric(horizontal: 6),
                  minimumSize: Size(28, 28),
                ),
                child: Icon(Icons.group, size: 14),
              ),
            ),
            if (PermissionManager.instance.canAdd('accounting.salaries'))
            SizedBox(width: 4),
            if (PermissionManager.instance.canAdd('accounting.salaries'))
            SizedBox(
              height: 28,
              child: OutlinedButton(
                onPressed: _generateSalaries,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AccountingTheme.neonPink,
                  side: const BorderSide(color: AccountingTheme.neonPink),
                  padding: EdgeInsets.symmetric(horizontal: 6),
                  minimumSize: Size(28, 28),
                ),
                child: Icon(Icons.auto_fix_high, size: 14),
              ),
            ),
            if (PermissionManager.instance.canAdd('accounting.salaries'))
            SizedBox(width: 4),
            if (PermissionManager.instance.canAdd('accounting.salaries'))
            SizedBox(
              height: 28,
              child: ElevatedButton(
                onPressed: _payAllSalaries,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AccountingTheme.neonPink,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(horizontal: 6),
                  minimumSize: Size(28, 28),
                ),
                child: Icon(Icons.payment, size: 14),
              ),
            ),
          ] else ...[
            if (PermissionManager.instance.canAdd('accounting.salaries')) ...[
            SizedBox(width: context.accR.spaceS),
            OutlinedButton.icon(
              onPressed: _showSalaryRosterDialog,
              icon: Icon(Icons.group, size: context.accR.iconM),
              label: const Text('كادر الرواتب'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AccountingTheme.info,
                side: const BorderSide(color: AccountingTheme.info),
              ),
            ),
            ],
            if (PermissionManager.instance.canAdd('accounting.salaries')) ...[
            SizedBox(width: context.accR.spaceS),
            OutlinedButton.icon(
              onPressed: _generateSalaries,
              icon: Icon(Icons.auto_fix_high, size: context.accR.iconM),
              label: const Text('توليد رواتب'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AccountingTheme.neonPink,
                side: const BorderSide(color: AccountingTheme.neonPink),
              ),
            ),
            ],
            if (PermissionManager.instance.canAdd('accounting.salaries')) ...[
            SizedBox(width: context.accR.spaceS),
            ElevatedButton.icon(
              onPressed: _payAllSalaries,
              icon: Icon(Icons.payment, size: context.accR.iconM),
              label: Text('صرف الكل'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AccountingTheme.neonPink,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(
                    horizontal: context.accR.paddingH,
                    vertical: context.accR.spaceM),
              ),
            ),
            ],
          ],
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
              _loadData();
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
              _loadData();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryBar() {
    final totalBase = _salaries.fold<double>(
        0, (s, e) => s + ((e['BaseSalary'] ?? 0) as num).toDouble());
    final totalNet = _salaries.fold<double>(
        0, (s, e) => s + ((e['NetSalary'] ?? 0) as num).toDouble());
    final totalDeductions = _salaries.fold<double>(
        0, (s, e) => s + ((e['Deductions'] ?? 0) as num).toDouble());
    final paidCount = _salaries.where((s) => s['Status'] == 'Paid').length;
    final pendingCount =
        _salaries.where((s) => s['Status'] == 'Pending').length;

    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: context.accR.paddingH, vertical: context.accR.spaceS),
      child: Row(
        children: [
          Expanded(
              child: _summaryChip(
                  'إجمالي صافي', _fmt(totalNet), Color(0xFF2196F3))),
          SizedBox(width: context.accR.spaceS),
          Expanded(
              child: _summaryChip(
                  'الخصومات', _fmt(totalDeductions), AccountingTheme.danger)),
          SizedBox(width: context.accR.spaceS),
          Expanded(
              child: _summaryChip('مصروفة', '$paidCount', Color(0xFF4CAF50))),
          SizedBox(width: context.accR.spaceS),
          Expanded(
              child: _summaryChip(
                  'معلقة', '$pendingCount', const Color(0xFFF39C12))),
        ],
      ),
    );
  }

  Widget _summaryChip(String label, String value, Color color) {
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: context.accR.spaceL, vertical: context.accR.spaceS),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Column(
        children: [
          Text(label,
              style: TextStyle(
                  color: color.withValues(alpha: 0.8),
                  fontSize: context.accR.small)),
          SizedBox(height: 2),
          Text(value,
              style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: context.accR.body)),
        ],
      ),
    );
  }

  Widget _buildSalariesList() {
    if (_salaries.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.payments_outlined,
                color: AccountingTheme.textMuted, size: context.accR.iconEmpty),
            SizedBox(height: context.accR.spaceXL),
            Text('لا توجد رواتب لهذا الشهر',
                style: TextStyle(color: AccountingTheme.textMuted)),
            SizedBox(height: context.accR.spaceM),
            ElevatedButton.icon(
              onPressed: _generateSalaries,
              icon: const Icon(Icons.auto_fix_high),
              label: const Text('توليد رواتب الشهر'),
              style: ElevatedButton.styleFrom(
                  backgroundColor: AccountingTheme.neonGreen,
                  foregroundColor: Colors.white),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints:
              BoxConstraints(minWidth: MediaQuery.of(context).size.width - 24),
          child: DataTable(
            headingRowColor: WidgetStateProperty.all(const Color(0xFF1E293B)),
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
            horizontalMargin: 12,
            headingRowHeight: 42,
            dataRowMinHeight: 40,
            dataRowMaxHeight: 44,
            showCheckboxColumn: false,
            columns: [
              DataColumn(
                  label: Text('الموظف',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: context.accR.small))),
              DataColumn(
                  numeric: true,
                  label: Text('الأساسي',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: context.accR.small))),
              DataColumn(
                  numeric: true,
                  label: Text('البدلات',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: context.accR.small))),
              DataColumn(
                  numeric: true,
                  label: Text('المكافآت',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: context.accR.small))),
              DataColumn(
                  numeric: true,
                  label: Text('الخصومات',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: context.accR.small))),
              DataColumn(
                  numeric: true,
                  label: Text('الصافي',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: context.accR.small))),
              DataColumn(
                  numeric: true,
                  label: Text('ذمم الفني',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: context.accR.small))),
              DataColumn(
                  label: Text('الحالة',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: context.accR.small))),
              DataColumn(
                  numeric: true,
                  label: Text('أيام حضور',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: context.accR.small))),
              DataColumn(
                  numeric: true,
                  label: Text('غياب',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: context.accR.small))),
              DataColumn(
                  numeric: true,
                  label: Text('خصم تأخير',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: context.accR.small))),
              DataColumn(
                  numeric: true,
                  label: Text('خصم غياب',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: context.accR.small))),
              DataColumn(
                  numeric: true,
                  label: Text('مكافأة إضافي',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: context.accR.small))),
              DataColumn(
                  numeric: true,
                  label: Text('أجر الأيام',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: context.accR.small))),
              DataColumn(
                  label: Text('إجراءات',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: context.accR.small))),
            ],
            rows: _salaries.map((s) {
              final status = s['Status'] ?? 'Pending';
              final statusColor = AccountingTheme.salaryStatusColors[status] ??
                  AccountingTheme.textMuted;
              final attendanceDays = (s['AttendanceDays'] ?? 0) as num;
              final expectedWorkDays = (s['ExpectedWorkDays'] ?? 26) as num;
              final baseSalary = (s['BaseSalary'] ?? 0) as num;
              final dailyWage =
                  expectedWorkDays > 0 ? baseSalary / expectedWorkDays : 0;
              final earnedByDays = (dailyWage * attendanceDays.toDouble());

              return DataRow(
                onSelectChanged: (_) => _showAttendanceDetail(s),
                cells: [
                  DataCell(Text(
                    s['EmployeeName'] ?? s['UserName'] ?? s['UserId'] ?? '',
                    style: TextStyle(
                        color: AccountingTheme.textPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: context.accR.small),
                  )),
                  DataCell(Text(_fmt(s['BaseSalary']),
                      style: TextStyle(
                          color: AccountingTheme.textSecondary,
                          fontSize: context.accR.small))),
                  DataCell(Text(_fmt(s['Allowances']),
                      style: TextStyle(
                          color: AccountingTheme.textSecondary,
                          fontSize: context.accR.small))),
                  DataCell(Text(_fmt(s['Bonuses']),
                      style: TextStyle(
                          color: AccountingTheme.info,
                          fontSize: context.accR.small))),
                  DataCell(Text(_fmt(s['Deductions']),
                      style: TextStyle(
                          color: AccountingTheme.danger,
                          fontSize: context.accR.small))),
                  DataCell(Text(_fmt(s['NetSalary']),
                      style: TextStyle(
                          color: AccountingTheme.textPrimary,
                          fontWeight: FontWeight.bold,
                          fontSize: context.accR.small))),
                  DataCell(_buildTechDuesCell(s)),
                  DataCell(Container(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.15),
                      borderRadius:
                          BorderRadius.circular(context.accR.cardRadius),
                    ),
                    child: Text(
                      _statusLabels[status] ?? status,
                      style: TextStyle(
                          color: statusColor,
                          fontSize: context.accR.caption,
                          fontWeight: FontWeight.bold),
                    ),
                  )),
                  DataCell(Text('${s['AttendanceDays'] ?? 0}',
                      style: TextStyle(
                          color: AccountingTheme.textSecondary,
                          fontSize: context.accR.small))),
                  DataCell(Text('${s['AbsentDays'] ?? 0}',
                      style: TextStyle(
                          color: AccountingTheme.textSecondary,
                          fontSize: context.accR.small))),
                  DataCell(Text(_fmt(s['LateDeduction']),
                      style: TextStyle(
                          color: AccountingTheme.danger,
                          fontSize: context.accR.small))),
                  DataCell(Text(_fmt(s['AbsentDeduction']),
                      style: TextStyle(
                          color: AccountingTheme.danger,
                          fontSize: context.accR.small))),
                  DataCell(Text(_fmt(s['OvertimeBonus']),
                      style: TextStyle(
                          color: AccountingTheme.success,
                          fontSize: context.accR.small))),
                  DataCell(Text(_fmt(earnedByDays),
                      style: TextStyle(
                          color: Color(0xFF2196F3),
                          fontWeight: FontWeight.bold,
                          fontSize: context.accR.small))),
                  DataCell(Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (status == 'Pending' && PermissionManager.instance.canAdd('accounting.salaries'))
                        InkWell(
                          onTap: () => _paySalary(s),
                          borderRadius: BorderRadius.circular(4),
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: Icon(Icons.payment, size: 18, color: AccountingTheme.success),
                          ),
                        ),
                      if (PermissionManager.instance.canEdit('accounting.salaries'))
                        InkWell(
                          onTap: () => _showEditDialog(s),
                          borderRadius: BorderRadius.circular(4),
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: Icon(Icons.edit, size: 18, color: AccountingTheme.info),
                          ),
                        ),
                      if (PermissionManager.instance.canDelete('accounting.salaries'))
                        InkWell(
                          onTap: () => _confirmDeleteSalary(Map<String, dynamic>.from(s)),
                          borderRadius: BorderRadius.circular(4),
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: Icon(Icons.delete_outline, size: 18, color: AccountingTheme.danger),
                          ),
                        ),
                    ],
                  )),
                ],
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  Widget _buildTechDuesCell(dynamic s) {
    final techBalance = ((s['TechNetBalance'] ?? 0) as num).toDouble();
    if (techBalance == 0) {
      return Text('0', style: TextStyle(color: AccountingTheme.textMuted, fontSize: context.accR.small));
    }
    // سالب = عليه مبلغ (أحمر)، موجب = له رصيد (أخضر)
    final color = techBalance < 0 ? AccountingTheme.danger : AccountingTheme.success;
    return Text(
      _fmt(techBalance.abs()),
      style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: context.accR.small),
    );
  }

  /// عرض تفاصيل حضور الموظف عند الضغط على الصف
  Future<void> _showAttendanceDetail(dynamic salary) async {
    final userId = salary['UserId'];
    if (userId == null) return;

    final employeeName =
        salary['EmployeeName'] ?? salary['UserName'] ?? salary['UserId'] ?? '';

    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: AccountingTheme.bgCard,
          title: Row(
            children: [
              Icon(Icons.schedule,
                  color: AccountingTheme.info, size: context.accR.iconM),
              SizedBox(width: context.accR.spaceS),
              Expanded(
                child: Text(
                  'سجل حضور: $employeeName - ${_months[_selectedMonth - 1]} $_selectedYear',
                  style: TextStyle(
                      color: AccountingTheme.textPrimary,
                      fontSize: context.accR.headingSmall),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: context.accR.isMobile
                ? MediaQuery.of(context).size.width * 0.92
                : 900,
            height: context.accR.isMobile
                ? MediaQuery.of(context).size.height * 0.6
                : 500,
            child: _AttendanceDetailWidget(
              userId: userId.toString(),
              month: _selectedMonth,
              year: _selectedYear,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('إغلاق',
                  style: TextStyle(color: AccountingTheme.textMuted)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showSalaryRosterDialog() async {
    final companyId = widget.companyId ?? '';
    if (companyId.isEmpty) return;

    // جلب كادر الرواتب
    final result = await AccountingService.instance.getSalaryRoster(companyId);
    if (result['success'] != true || !mounted) return;

    final employees = (result['data'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    if (employees.isEmpty) {
      _snack('لا يوجد موظفون', AccountingTheme.warning);
      return;
    }

    // نسخة محلية من حالة الكادر
    final selected = <String>{};
    for (final emp in employees) {
      if (emp['IsInSalaryRoster'] == true) {
        selected.add(emp['Id'].toString());
      }
    }

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx2, setDialogState) {
            return Directionality(
              textDirection: TextDirection.rtl,
              child: AlertDialog(
                backgroundColor: AccountingTheme.bgCard,
                title: Row(
                  children: [
                    Icon(Icons.group, color: AccountingTheme.info, size: 22),
                    const SizedBox(width: 8),
                    Text('كادر الرواتب',
                        style: TextStyle(color: AccountingTheme.textPrimary, fontSize: context.accR.headingSmall)),
                    const Spacer(),
                    Text('${selected.length}/${employees.length}',
                        style: TextStyle(color: AccountingTheme.textMuted, fontSize: 14)),
                  ],
                ),
                content: SizedBox(
                  width: min(450, MediaQuery.of(context).size.width * 0.85),
                  height: min(400, MediaQuery.of(context).size.height * 0.6),
                  child: ListView.builder(
                    itemCount: employees.length,
                    itemBuilder: (_, i) {
                      final emp = employees[i];
                      final id = emp['Id'].toString();
                      final name = emp['FullName'] ?? '';
                      final role = emp['Role'] ?? '';
                      final salary = emp['Salary'];
                      final isSelected = selected.contains(id);

                      return CheckboxListTile(
                        value: isSelected,
                        activeColor: AccountingTheme.neonGreen,
                        checkColor: Colors.white,
                        onChanged: (val) {
                          setDialogState(() {
                            if (val == true) {
                              selected.add(id);
                            } else {
                              selected.remove(id);
                            }
                          });
                        },
                        title: Text(name,
                            style: TextStyle(
                                color: AccountingTheme.textPrimary,
                                fontWeight: FontWeight.bold,
                                fontSize: 14)),
                        subtitle: Text(
                          '${_roleLabel(role)}${salary != null ? ' • ${_fmt(salary)}' : ''}',
                          style: TextStyle(
                              color: AccountingTheme.textMuted, fontSize: 12),
                        ),
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                      );
                    },
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      setDialogState(() {
                        selected.clear();
                        for (final emp in employees) {
                          selected.add(emp['Id'].toString());
                        }
                      });
                    },
                    child: Text('تحديد الكل', style: TextStyle(color: AccountingTheme.info)),
                  ),
                  TextButton(
                    onPressed: () {
                      setDialogState(() => selected.clear());
                    },
                    child: Text('إلغاء التحديد', style: TextStyle(color: AccountingTheme.textMuted)),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, null),
                    child: Text('إلغاء', style: TextStyle(color: AccountingTheme.textMuted)),
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AccountingTheme.neonGreen,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('حفظ'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (saved != true || !mounted) return;

    // حفظ التغييرات
    final updateResult = await AccountingService.instance.updateSalaryRoster(
      companyId: companyId,
      userIds: selected.toList(),
    );
    if (updateResult['success'] == true) {
      _snack(updateResult['message'] ?? 'تم تحديث الكادر', AccountingTheme.success);
      _loadData();
    } else {
      _snack(updateResult['message'] ?? 'خطأ', AccountingTheme.danger);
    }
  }

  String _roleLabel(String role) {
    const labels = {
      'Employee': 'موظف',
      'Technician': 'فني',
      'Manager': 'مدير',
      'CompanyAdmin': 'مدير شركة',
      'Agent': 'وكيل',
    };
    return labels[role] ?? role;
  }

  Future<void> _generateSalaries() async {
    final hasExisting = _salaries.isNotEmpty;
    final confirm = await _confirmAction('توليد الرواتب',
        hasExisting
            ? 'سيتم حذف الرواتب المعلقة وإعادة حساب رواتب شهر ${_months[_selectedMonth - 1]} $_selectedYear من جديد. متابعة؟'
            : 'سيتم توليد رواتب شهر ${_months[_selectedMonth - 1]} $_selectedYear لموظفي الكادر. متابعة؟');
    if (confirm != true) return;

    // فحص الفترة المحاسبية
    final genDate = DateTime(_selectedYear, _selectedMonth, 1);
    final periodOk = await PeriodClosingService.checkAndWarnIfClosed(
      context, date: genDate, companyId: widget.companyId ?? '',
    );
    if (!periodOk) return;

    setState(() {
      _isLoading = true;
    });
    try {
      final result = await AccountingService.instance.generateSalaries(
        month: _selectedMonth,
        year: _selectedYear,
        companyId: widget.companyId ?? '',
      );
      if (result['success'] == true) {
        _snack('تم توليد الرواتب بنجاح', AccountingTheme.success);
        AuditTrailService.instance.log(
          action: AuditAction.create,
          entityType: AuditEntityType.salary,
          entityId: '$_selectedYear-$_selectedMonth',
          entityDescription: 'توليد رواتب ${_months[_selectedMonth - 1]} $_selectedYear',
        );
        _loadData();
      } else {
        _snack(result['message'] ?? 'خطأ', AccountingTheme.danger);
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      _snack('خطأ', AccountingTheme.danger);
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _payAllSalaries() async {
    final pending = _salaries.where((s) => s['Status'] == 'Pending').length;
    if (pending == 0) {
      _snack('لا توجد رواتب معلقة', AccountingTheme.warning);
      return;
    }
    final confirm = await _confirmAction(
        'صرف الكل', 'سيتم صرف $pending راتب معلق. متابعة؟');
    if (confirm != true) return;

    // فحص الفترة المحاسبية
    final payAllDate = DateTime(_selectedYear, _selectedMonth, 1);
    final payAllOk = await PeriodClosingService.checkAndWarnIfClosed(
      context, date: payAllDate, companyId: widget.companyId ?? '',
    );
    if (!payAllOk) return;

    setState(() {
      _isLoading = true;
    });
    try {
      final result = await AccountingService.instance.payAllSalaries(
        month: _selectedMonth,
        year: _selectedYear,
        companyId: widget.companyId ?? '',
      );
      if (result['success'] == true) {
        _snack('تم صرف جميع الرواتب', AccountingTheme.success);
        AuditTrailService.instance.log(
          action: AuditAction.edit,
          entityType: AuditEntityType.salary,
          entityId: '$_selectedYear-$_selectedMonth',
          entityDescription: 'صرف جميع رواتب ${_months[_selectedMonth - 1]} $_selectedYear',
          details: '$pending راتب',
        );
        _loadData();
      } else {
        _snack(result['message'] ?? 'خطأ', AccountingTheme.danger);
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      _snack('خطأ', AccountingTheme.danger);
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _paySalary(dynamic salary) async {
    // فحص الفترة المحاسبية
    final salDate = DateTime(_selectedYear, _selectedMonth, 1);
    final allowed = await PeriodClosingService.checkAndWarnIfClosed(
      context, date: salDate, companyId: widget.companyId ?? '',
    );
    if (!allowed) return;

    final techBalance = ((salary['TechNetBalance'] ?? 0) as num).toDouble();
    final netSalary = ((salary['NetSalary'] ?? 0) as num).toDouble();
    final empName = salary['EmployeeName'] ?? salary['UserName'] ?? '';
    bool deductDues = false;

    // إذا كان فني وعليه ذمم (رصيد سالب)
    if (techBalance < 0) {
      final duesAmount = techBalance.abs();
      final afterDeduction = netSalary - (duesAmount > netSalary ? netSalary : duesAmount);
      final deducted = duesAmount > netSalary ? netSalary : duesAmount;

      final choice = await showDialog<bool>(
        context: context,
        builder: (ctx) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            backgroundColor: AccountingTheme.bgCard,
            title: Text('صرف راتب: $empName',
                style: const TextStyle(color: AccountingTheme.textPrimary)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _duesInfoRow('صافي الراتب', _fmt(netSalary), AccountingTheme.textPrimary),
                const SizedBox(height: 8),
                _duesInfoRow('ذمم الفني', _fmt(duesAmount), AccountingTheme.danger),
                const Divider(color: AccountingTheme.borderColor, height: 20),
                _duesInfoRow('المبلغ المخصوم', _fmt(deducted), const Color(0xFFF39C12)),
                const SizedBox(height: 4),
                _duesInfoRow('المبلغ المصروف نقداً', _fmt(afterDeduction), AccountingTheme.success),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, null),
                child: Text('إلغاء', style: TextStyle(color: AccountingTheme.textMuted)),
              ),
              OutlinedButton(
                onPressed: () => Navigator.pop(ctx, false),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AccountingTheme.info,
                  side: const BorderSide(color: AccountingTheme.info),
                ),
                child: const Text('صرف بدون خصم'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AccountingTheme.neonGreen,
                  foregroundColor: Colors.white,
                ),
                child: const Text('صرف مع خصم الذمم'),
              ),
            ],
          ),
        ),
      );

      if (choice == null) return;
      deductDues = choice;
    }

    setState(() {
      _isLoading = true;
    });
    try {
      final result = await AccountingService.instance.paySalary(
        salary['Id'].toString(),
        deductTechDues: deductDues,
      );
      if (result['success'] == true) {
        _snack(result['message'] ?? 'تم صرف الراتب', AccountingTheme.success);
        AuditTrailService.instance.log(
          action: AuditAction.edit,
          entityType: AuditEntityType.salary,
          entityId: salary['Id']?.toString() ?? '',
          entityDescription: 'صرف راتب: $empName${deductDues ? ' (مع خصم ذمم)' : ''}',
        );
        _loadData();
      } else {
        _snack(result['message'] ?? 'خطأ', AccountingTheme.danger);
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      _snack('خطأ', AccountingTheme.danger);
      setState(() {
        _isLoading = false;
      });
    }
  }

  Widget _duesInfoRow(String label, String value, Color valueColor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: AccountingTheme.textSecondary)),
        Text('$value د.ع', style: TextStyle(color: valueColor, fontWeight: FontWeight.bold)),
      ],
    );
  }

  void _showEditDialog(dynamic salary) {
    final allowCtrl =
        TextEditingController(text: (salary['Allowances'] ?? 0).toString());
    final deductCtrl =
        TextEditingController(text: (salary['Deductions'] ?? 0).toString());
    final bonusCtrl =
        TextEditingController(text: (salary['Bonuses'] ?? 0).toString());
    final notesCtrl = TextEditingController(text: salary['Notes'] ?? '');

    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: AccountingTheme.bgCard,
          title: Text('تعديل راتب: ${salary['EmployeeName'] ?? ''}',
              style: const TextStyle(color: AccountingTheme.textPrimary)),
          content: SizedBox(
            width: context.accR.isMobile
                ? MediaQuery.of(context).size.width * 0.85
                : 350,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _textField('البدلات', allowCtrl, isNumber: true),
                SizedBox(height: context.accR.spaceM),
                _textField('الخصومات', deductCtrl, isNumber: true),
                SizedBox(height: context.accR.spaceM),
                _textField('المكافآت', bonusCtrl, isNumber: true),
                SizedBox(height: context.accR.spaceM),
                _textField('ملاحظات', notesCtrl),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('إلغاء',
                    style: TextStyle(color: AccountingTheme.textMuted))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AccountingTheme.neonGreen,
                  foregroundColor: Colors.white),
              onPressed: () async {
                Navigator.pop(ctx);
                // فحص الفترة المحاسبية
                final editDate = DateTime(_selectedYear, _selectedMonth, 1);
                final editOk = await PeriodClosingService.checkAndWarnIfClosed(
                  context, date: editDate, companyId: widget.companyId ?? '',
                );
                if (!editOk) return;
                final result = await AccountingService.instance.updateSalary(
                  salary['Id'].toString(),
                  allowances: double.tryParse(allowCtrl.text),
                  deductions: double.tryParse(deductCtrl.text),
                  bonuses: double.tryParse(bonusCtrl.text),
                  notes: notesCtrl.text.isEmpty ? null : notesCtrl.text,
                );
                if (result['success'] == true) {
                  _snack('تم التعديل', AccountingTheme.success);
                  AuditTrailService.instance.log(
                    action: AuditAction.edit,
                    entityType: AuditEntityType.salary,
                    entityId: salary['Id']?.toString() ?? '',
                    entityDescription: 'تعديل راتب: ${salary['EmployeeName'] ?? ''}',
                  );
                  _loadData();
                } else {
                  _snack(result['message'] ?? 'خطأ', AccountingTheme.danger);
                }
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool?> _confirmAction(String title, String msg) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: AccountingTheme.bgCard,
          title: Text(title,
              style: const TextStyle(color: AccountingTheme.textPrimary)),
          content: Text(msg,
              style: const TextStyle(color: AccountingTheme.textSecondary)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('إلغاء',
                    style: TextStyle(color: AccountingTheme.textMuted))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AccountingTheme.neonGreen,
                  foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('متابعة'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _textField(String label, TextEditingController ctrl,
      {bool isNumber = false}) {
    return TextField(
      controller: ctrl,
      style: const TextStyle(color: AccountingTheme.textPrimary),
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: AccountingTheme.textMuted),
        filled: true,
        fillColor: AccountingTheme.bgCardHover,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide.none),
      ),
    );
  }

  void _confirmDeleteSalary(Map<String, dynamic> s) {
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: AccountingTheme.bgCard,
          title: Text('تأكيد الحذف',
              style: TextStyle(color: AccountingTheme.danger)),
          content: Text(
            'هل تريد حذف راتب "${s['EmployeeName'] ?? ''}" بمبلغ ${_fmt(s['NetSalary'])} د.ع؟',
            style: const TextStyle(color: AccountingTheme.textPrimary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('إلغاء',
                  style: TextStyle(color: AccountingTheme.textMuted)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AccountingTheme.danger,
                  foregroundColor: Colors.white),
              onPressed: () async {
                Navigator.pop(ctx);
                // فحص الفترة المحاسبية
                final delDate = DateTime(_selectedYear, _selectedMonth, 1);
                final delOk = await PeriodClosingService.checkAndWarnIfClosed(
                  context, date: delDate, companyId: widget.companyId ?? '',
                );
                if (!delOk) return;
                final result = await AccountingService.instance
                    .deleteSalary(s['Id'].toString());
                if (result['success'] == true) {
                  _snack('تم حذف الراتب', AccountingTheme.success);
                  AuditTrailService.instance.log(
                    action: AuditAction.delete,
                    entityType: AuditEntityType.salary,
                    entityId: s['Id']?.toString() ?? '',
                    entityDescription: 'حذف راتب: ${s['EmployeeName'] ?? ''}',
                  );
                  _loadData();
                } else {
                  _snack(result['message'] ?? 'خطأ', AccountingTheme.danger);
                }
              },
              child: const Text('حذف'),
            ),
          ],
        ),
      ),
    );
  }

  void _snack(String msg, Color color) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg), backgroundColor: color));
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

/// ويدجت تفاصيل حضور الموظف (يُستخدم داخل Dialog)
class _AttendanceDetailWidget extends StatefulWidget {
  final String userId;
  final int month;
  final int year;

  const _AttendanceDetailWidget({
    required this.userId,
    required this.month,
    required this.year,
  });

  @override
  State<_AttendanceDetailWidget> createState() =>
      _AttendanceDetailWidgetState();
}

class _AttendanceDetailWidgetState extends State<_AttendanceDetailWidget> {
  bool _loading = true;
  String? _error;
  List<dynamic> _records = [];

  final _statusAr = {
    'Present': 'حاضر',
    'Late': 'متأخر',
    'Absent': 'غائب',
    'HalfDay': 'نصف يوم',
    'EarlyDeparture': 'مغادرة مبكرة',
    'OnLeave': 'إجازة',
    'Holiday': 'عطلة',
  };

  final _statusColors = {
    'Present': const Color(0xFF4CAF50),
    'Late': const Color(0xFFF39C12),
    'Absent': const Color(0xFFE74C3C),
    'HalfDay': const Color(0xFF9B59B6),
    'EarlyDeparture': const Color(0xFFE67E22),
    'OnLeave': const Color(0xFF3498DB),
    'Holiday': const Color(0xFF1ABC9C),
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await AttendanceApiService.instance.getMonthlyAttendance(
        userId: widget.userId,
        month: widget.month,
        year: widget.year,
      );
      _records = (data['records'] is List) ? data['records'] : [];
    } catch (e) {
      _error = 'خطأ في جلب البيانات';
    }
    setState(() {
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: AccountingTheme.neonGreen));
    }
    if (_error != null) {
      return Center(
          child: Text(_error!,
              style: const TextStyle(color: AccountingTheme.danger)));
    }
    if (_records.isEmpty) {
      return const Center(
          child: Text('لا توجد سجلات حضور لهذا الشهر',
              style: TextStyle(color: AccountingTheme.textMuted)));
    }

    return SingleChildScrollView(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: min(600, MediaQuery.of(context).size.width - 32)),
          child: DataTable(
            headingRowColor: WidgetStateProperty.all(const Color(0xFF1E293B)),
            dataRowColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.hovered)) {
                return const Color(0xFF1E293B).withValues(alpha: 0.3);
              }
              return AccountingTheme.bgCard;
            }),
            border: TableBorder.all(
                color: AccountingTheme.borderColor.withValues(alpha: 0.3),
                width: 0.5),
            columnSpacing: 16,
            horizontalMargin: 10,
            headingRowHeight: 38,
            dataRowMinHeight: 34,
            dataRowMaxHeight: 38,
            columns: [
              DataColumn(
                  label: Text('التاريخ',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: context.accR.small))),
              DataColumn(
                  label: Text('وقت الحضور',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: context.accR.small))),
              DataColumn(
                  label: Text('وقت الانصراف',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: context.accR.small))),
              DataColumn(
                  label: Text('الحالة',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: context.accR.small))),
              DataColumn(
                  numeric: true,
                  label: Text('ساعات العمل',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: context.accR.small))),
              DataColumn(
                  numeric: true,
                  label: Text('تأخير (دقيقة)',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: context.accR.small))),
              DataColumn(
                  numeric: true,
                  label: Text('إضافي (دقيقة)',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: context.accR.small))),
              DataColumn(
                  label: Text('ملاحظات',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: context.accR.small))),
            ],
            rows: _records.map((r) {
              final status = r['status'] ?? '';
              final color = _statusColors[status] ?? AccountingTheme.textMuted;
              final workedMin = (r['workedMinutes'] ?? 0) as num;
              final hours = (workedMin / 60).toStringAsFixed(1);

              return DataRow(cells: [
                DataCell(Text(r['date'] ?? '',
                    style: TextStyle(
                        color: AccountingTheme.textPrimary,
                        fontSize: context.accR.small))),
                DataCell(Text(r['checkInTime'] ?? '-',
                    style: TextStyle(
                        color: AccountingTheme.success,
                        fontWeight: FontWeight.bold,
                        fontSize: context.accR.small))),
                DataCell(Text(r['checkOutTime'] ?? '-',
                    style: TextStyle(
                        color: AccountingTheme.danger,
                        fontWeight: FontWeight.bold,
                        fontSize: context.accR.small))),
                DataCell(Container(
                  padding: EdgeInsets.symmetric(
                      horizontal: context.accR.spaceXS, vertical: 2),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _statusAr[status] ?? status,
                    style: TextStyle(
                        color: color,
                        fontSize: context.accR.caption,
                        fontWeight: FontWeight.bold),
                  ),
                )),
                DataCell(Text(hours,
                    style: TextStyle(
                        color: AccountingTheme.textSecondary,
                        fontSize: context.accR.small))),
                DataCell(Text('${r['lateMinutes'] ?? 0}',
                    style: TextStyle(
                        color: (r['lateMinutes'] ?? 0) > 0
                            ? AccountingTheme.danger
                            : AccountingTheme.textMuted,
                        fontSize: context.accR.small))),
                DataCell(Text('${r['overtimeMinutes'] ?? 0}',
                    style: TextStyle(
                        color: (r['overtimeMinutes'] ?? 0) > 0
                            ? AccountingTheme.success
                            : AccountingTheme.textMuted,
                        fontSize: context.accR.small))),
                DataCell(Text(r['notes'] ?? '',
                    style: TextStyle(
                        color: AccountingTheme.textMuted,
                        fontSize: context.accR.small))),
              ]);
            }).toList(),
          ),
        ),
      ),
    );
  }
}
