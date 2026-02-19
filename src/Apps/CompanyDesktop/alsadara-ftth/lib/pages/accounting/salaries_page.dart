import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/accounting_service.dart';
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
    final paidCount = _salaries.where((s) => s['Status'] == 'Paid').length;

    return Container(
      padding: const EdgeInsets.all(12),
      child: Wrap(
        spacing: 12,
        children: [
          _summaryChip(
              'عدد الموظفين', '${_salaries.length}', AccountingTheme.info),
          _summaryChip(
              'إجمالي الأساسي', _fmt(totalBase), AccountingTheme.accent),
          _summaryChip(
              'إجمالي الصافي', _fmt(totalNet), AccountingTheme.success),
          _summaryChip('مدفوع', '$paidCount / ${_salaries.length}',
              AccountingTheme.neonGreen),
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

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _salaries.length,
      itemBuilder: (_, i) {
        final s = _salaries[i];
        final status = s['Status'] ?? 'Pending';
        final statusColor = AccountingTheme.salaryStatusColors[status] ??
            AccountingTheme.textMuted;

        return Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AccountingTheme.bgCard,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              // اسم الموظف
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s['EmployeeName'] ?? s['UserId'] ?? '',
                      style: const TextStyle(
                          color: AccountingTheme.textPrimary,
                          fontWeight: FontWeight.bold,
                          fontSize: 14),
                    ),
                    if (s['Notes'] != null && s['Notes'].toString().isNotEmpty)
                      Text(s['Notes'],
                          style: const TextStyle(
                              color: AccountingTheme.textMuted, fontSize: 11)),
                  ],
                ),
              ),
              // الأساسي
              _salaryColumn(
                  'الأساسي', s['BaseSalary'], AccountingTheme.textMuted),
              // البدلات
              _salaryColumn('بدلات', s['Allowances'], AccountingTheme.accent),
              // الخصومات
              _salaryColumn('خصومات', s['Deductions'], AccountingTheme.danger),
              // المكافآت
              _salaryColumn('مكافآت', s['Bonuses'], AccountingTheme.info),
              // الصافي
              _salaryColumn('الصافي', s['NetSalary'], AccountingTheme.accent),
              const SizedBox(width: 8),
              // الحالة
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _statusLabels[status] ?? status,
                  style: TextStyle(
                      color: statusColor,
                      fontSize: 11,
                      fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 8),
              // أزرار
              if (status == 'Pending') ...[
                IconButton(
                  icon: const Icon(Icons.edit,
                      color: AccountingTheme.textMuted, size: 18),
                  onPressed: () => _showEditDialog(s),
                  tooltip: 'تعديل',
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline,
                      color: AccountingTheme.danger, size: 18),
                  onPressed: () => _confirmDeleteSalary(s),
                  tooltip: 'حذف',
                ),
                IconButton(
                  icon: const Icon(Icons.payment,
                      color: AccountingTheme.success, size: 18),
                  onPressed: () => _paySalary(s),
                  tooltip: 'صرف',
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _salaryColumn(String label, dynamic value, Color color) {
    return SizedBox(
      width: 80,
      child: Column(
        children: [
          Text(label,
              style: const TextStyle(
                  color: AccountingTheme.textMuted, fontSize: 10)),
          Text(_fmt(value),
              style: TextStyle(
                  color: color, fontSize: 12, fontWeight: FontWeight.bold)),
        ],
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
