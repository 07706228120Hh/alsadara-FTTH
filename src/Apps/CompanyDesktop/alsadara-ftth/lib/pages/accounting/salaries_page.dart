import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/accounting_service.dart';
import '../../services/attendance_api_service.dart';
import '../../theme/accounting_theme.dart';

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
      _errorMessage = 'خطأ: $e';
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
        body: Column(
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
    );
  }

  Widget _buildPageToolbar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
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
            style: IconButton.styleFrom(
                foregroundColor: AccountingTheme.textSecondary),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: AccountingTheme.neonPinkGradient,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.payments_rounded,
                color: Colors.white, size: 18),
          ),
          const SizedBox(width: 12),
          Text('الرواتب',
              style: GoogleFonts.cairo(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AccountingTheme.textPrimary)),
          const Spacer(),
          IconButton(
            onPressed: _loadData,
            icon: const Icon(Icons.refresh, size: 18),
            tooltip: 'تحديث',
            style: IconButton.styleFrom(
                foregroundColor: AccountingTheme.textSecondary),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: _generateSalaries,
            icon: const Icon(Icons.auto_fix_high, size: 18),
            label: const Text('توليد رواتب'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AccountingTheme.neonPink,
              side: const BorderSide(color: AccountingTheme.neonPink),
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: _payAllSalaries,
            icon: const Icon(Icons.payment, size: 18),
            label: const Text('صرف الكل'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AccountingTheme.neonPink,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMonthSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
              style: const TextStyle(
                  color: AccountingTheme.textPrimary,
                  fontSize: 18,
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
              child: _summaryChip(
                  'إجمالي صافي', _fmt(totalNet), const Color(0xFF2196F3))),
          const SizedBox(width: 8),
          Expanded(
              child: _summaryChip(
                  'الخصومات', _fmt(totalDeductions), AccountingTheme.danger)),
          const SizedBox(width: 8),
          Expanded(
              child: _summaryChip(
                  'مصروفة', '$paidCount', const Color(0xFF4CAF50))),
          const SizedBox(width: 8),
          Expanded(
              child: _summaryChip(
                  'معلقة', '$pendingCount', const Color(0xFFF39C12))),
        ],
      ),
    );
  }

  Widget _summaryChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Column(
        children: [
          Text(label,
              style:
                  TextStyle(color: color.withValues(alpha: 0.8), fontSize: 11)),
          const SizedBox(height: 2),
          Text(value,
              style: TextStyle(
                  color: color, fontWeight: FontWeight.bold, fontSize: 15)),
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
            const Icon(Icons.payments_outlined,
                color: AccountingTheme.textMuted, size: 64),
            const SizedBox(height: 16),
            const Text('لا توجد رواتب لهذا الشهر',
                style: TextStyle(color: AccountingTheme.textMuted)),
            const SizedBox(height: 12),
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: SizedBox(
        width: double.infinity,
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
          columns: const [
            DataColumn(
                label: Text('الموظف',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12))),
            DataColumn(
                numeric: true,
                label: Text('الأساسي',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12))),
            DataColumn(
                numeric: true,
                label: Text('البدلات',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12))),
            DataColumn(
                numeric: true,
                label: Text('المكافآت',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12))),
            DataColumn(
                numeric: true,
                label: Text('الخصومات',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12))),
            DataColumn(
                numeric: true,
                label: Text('الصافي',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12))),
            DataColumn(
                label: Text('الحالة',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12))),
            DataColumn(
                numeric: true,
                label: Text('أيام حضور',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12))),
            DataColumn(
                numeric: true,
                label: Text('غياب',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12))),
            DataColumn(
                numeric: true,
                label: Text('خصم تأخير',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12))),
            DataColumn(
                numeric: true,
                label: Text('خصم غياب',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12))),
            DataColumn(
                numeric: true,
                label: Text('مكافأة إضافي',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12))),
            DataColumn(
                numeric: true,
                label: Text('أجر الأيام',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12))),
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
                  style: const TextStyle(
                      color: AccountingTheme.textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 12),
                )),
                DataCell(Text(_fmt(s['BaseSalary']),
                    style: const TextStyle(
                        color: AccountingTheme.textSecondary, fontSize: 12))),
                DataCell(Text(_fmt(s['Allowances']),
                    style: const TextStyle(
                        color: AccountingTheme.textSecondary, fontSize: 12))),
                DataCell(Text(_fmt(s['Bonuses']),
                    style: const TextStyle(
                        color: AccountingTheme.info, fontSize: 12))),
                DataCell(Text(_fmt(s['Deductions']),
                    style: const TextStyle(
                        color: AccountingTheme.danger, fontSize: 12))),
                DataCell(Text(_fmt(s['NetSalary']),
                    style: const TextStyle(
                        color: AccountingTheme.textPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 12))),
                DataCell(Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    _statusLabels[status] ?? status,
                    style: TextStyle(
                        color: statusColor,
                        fontSize: 10,
                        fontWeight: FontWeight.bold),
                  ),
                )),
                DataCell(Text('${s['AttendanceDays'] ?? 0}',
                    style: const TextStyle(
                        color: AccountingTheme.textSecondary, fontSize: 12))),
                DataCell(Text('${s['AbsentDays'] ?? 0}',
                    style: const TextStyle(
                        color: AccountingTheme.textSecondary, fontSize: 12))),
                DataCell(Text(_fmt(s['LateDeduction']),
                    style: const TextStyle(
                        color: AccountingTheme.danger, fontSize: 12))),
                DataCell(Text(_fmt(s['AbsentDeduction']),
                    style: const TextStyle(
                        color: AccountingTheme.danger, fontSize: 12))),
                DataCell(Text(_fmt(s['OvertimeBonus']),
                    style: const TextStyle(
                        color: AccountingTheme.success, fontSize: 12))),
                DataCell(Text(_fmt(earnedByDays),
                    style: const TextStyle(
                        color: Color(0xFF2196F3),
                        fontWeight: FontWeight.bold,
                        fontSize: 12))),
              ],
            );
          }).toList(),
        ),
      ),
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
              const Icon(Icons.schedule, color: AccountingTheme.info, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'سجل حضور: $employeeName - ${_months[_selectedMonth - 1]} $_selectedYear',
                  style: const TextStyle(
                      color: AccountingTheme.textPrimary, fontSize: 16),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 900,
            height: 500,
            child: _AttendanceDetailWidget(
              userId: userId.toString(),
              month: _selectedMonth,
              year: _selectedYear,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إغلاق',
                  style: TextStyle(color: AccountingTheme.textMuted)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _generateSalaries() async {
    final confirm = await _confirmAction('توليد الرواتب',
        'سيتم توليد رواتب شهر ${_months[_selectedMonth - 1]} $_selectedYear لجميع الموظفين. متابعة؟');
    if (confirm != true) return;

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
        _loadData();
      } else {
        _snack(result['message'] ?? 'خطأ', AccountingTheme.danger);
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      _snack('خطأ: $e', AccountingTheme.danger);
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
        _loadData();
      } else {
        _snack(result['message'] ?? 'خطأ', AccountingTheme.danger);
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      _snack('خطأ: $e', AccountingTheme.danger);
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _paySalary(dynamic salary) async {
    setState(() {
      _isLoading = true;
    });
    try {
      final result =
          await AccountingService.instance.paySalary(salary['Id'].toString());
      if (result['success'] == true) {
        _snack('تم صرف الراتب', AccountingTheme.success);
        _loadData();
      } else {
        _snack(result['message'] ?? 'خطأ', AccountingTheme.danger);
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      _snack('خطأ: $e', AccountingTheme.danger);
      setState(() {
        _isLoading = false;
      });
    }
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
            width: 350,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _textField('البدلات', allowCtrl, isNumber: true),
                const SizedBox(height: 10),
                _textField('الخصومات', deductCtrl, isNumber: true),
                const SizedBox(height: 10),
                _textField('المكافآت', bonusCtrl, isNumber: true),
                const SizedBox(height: 10),
                _textField('ملاحظات', notesCtrl),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('إلغاء',
                    style: TextStyle(color: AccountingTheme.textMuted))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AccountingTheme.neonGreen,
                  foregroundColor: Colors.white),
              onPressed: () async {
                Navigator.pop(ctx);
                final result = await AccountingService.instance.updateSalary(
                  salary['Id'].toString(),
                  allowances: double.tryParse(allowCtrl.text),
                  deductions: double.tryParse(deductCtrl.text),
                  bonuses: double.tryParse(bonusCtrl.text),
                  notes: notesCtrl.text.isEmpty ? null : notesCtrl.text,
                );
                if (result['success'] == true) {
                  _snack('تم التعديل', AccountingTheme.success);
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
                child: const Text('إلغاء',
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
          title: const Text('تأكيد الحذف',
              style: TextStyle(color: AccountingTheme.danger)),
          content: Text(
            'هل تريد حذف راتب "${s['EmployeeName'] ?? ''}" بمبلغ ${_fmt(s['NetSalary'])} د.ع؟',
            style: const TextStyle(color: AccountingTheme.textPrimary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء',
                  style: TextStyle(color: AccountingTheme.textMuted)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AccountingTheme.danger,
                  foregroundColor: Colors.white),
              onPressed: () async {
                Navigator.pop(ctx);
                final result = await AccountingService.instance
                    .deleteSalary(s['Id'].toString());
                if (result['success'] == true) {
                  _snack('تم حذف الراتب', AccountingTheme.success);
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
      _error = 'خطأ في جلب البيانات: $e';
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
      child: SizedBox(
        width: double.infinity,
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
          columns: const [
            DataColumn(
                label: Text('التاريخ',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12))),
            DataColumn(
                label: Text('وقت الحضور',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12))),
            DataColumn(
                label: Text('وقت الانصراف',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12))),
            DataColumn(
                label: Text('الحالة',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12))),
            DataColumn(
                numeric: true,
                label: Text('ساعات العمل',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12))),
            DataColumn(
                numeric: true,
                label: Text('تأخير (دقيقة)',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12))),
            DataColumn(
                numeric: true,
                label: Text('إضافي (دقيقة)',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12))),
            DataColumn(
                label: Text('ملاحظات',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12))),
          ],
          rows: _records.map((r) {
            final status = r['status'] ?? '';
            final color = _statusColors[status] ?? AccountingTheme.textMuted;
            final workedMin = (r['workedMinutes'] ?? 0) as num;
            final hours = (workedMin / 60).toStringAsFixed(1);

            return DataRow(cells: [
              DataCell(Text(r['date'] ?? '',
                  style: const TextStyle(
                      color: AccountingTheme.textPrimary, fontSize: 12))),
              DataCell(Text(r['checkInTime'] ?? '-',
                  style: const TextStyle(
                      color: AccountingTheme.success,
                      fontWeight: FontWeight.bold,
                      fontSize: 12))),
              DataCell(Text(r['checkOutTime'] ?? '-',
                  style: const TextStyle(
                      color: AccountingTheme.danger,
                      fontWeight: FontWeight.bold,
                      fontSize: 12))),
              DataCell(Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _statusAr[status] ?? status,
                  style: TextStyle(
                      color: color, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              )),
              DataCell(Text(hours,
                  style: const TextStyle(
                      color: AccountingTheme.textSecondary, fontSize: 12))),
              DataCell(Text('${r['lateMinutes'] ?? 0}',
                  style: TextStyle(
                      color: (r['lateMinutes'] ?? 0) > 0
                          ? AccountingTheme.danger
                          : AccountingTheme.textMuted,
                      fontSize: 12))),
              DataCell(Text('${r['overtimeMinutes'] ?? 0}',
                  style: TextStyle(
                      color: (r['overtimeMinutes'] ?? 0) > 0
                          ? AccountingTheme.success
                          : AccountingTheme.textMuted,
                      fontSize: 12))),
              DataCell(Text(r['notes'] ?? '',
                  style: const TextStyle(
                      color: AccountingTheme.textMuted, fontSize: 11))),
            ]);
          }).toList(),
        ),
      ),
    );
  }
}
