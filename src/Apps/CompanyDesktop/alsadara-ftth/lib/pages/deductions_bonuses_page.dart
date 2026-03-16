/// صفحة الخصومات والمكافآت - Deductions & Bonuses Page
/// إدارة الخصومات والمكافآت والبدلات اليدوية للموظفين
library;

import 'package:flutter/material.dart';
import '../utils/responsive_helper.dart';
import '../services/attendance_api_service.dart';
import '../services/vps_auth_service.dart';

class DeductionsBonusesPage extends StatefulWidget {
  final String? companyId;

  const DeductionsBonusesPage({super.key, this.companyId});

  @override
  State<DeductionsBonusesPage> createState() => _DeductionsBonusesPageState();
}

class _DeductionsBonusesPageState extends State<DeductionsBonusesPage> {
  final AttendanceApiService _api = AttendanceApiService.instance;

  List<Map<String, dynamic>> _adjustments = [];
  Map<String, dynamic>? _summary;
  bool _loading = true;
  int _selectedMonth = DateTime.now().month;
  int _selectedYear = DateTime.now().year;
  int? _filterType; // null=الكل, 0=خصم, 1=مكافأة, 2=بدل

  String? get _companyId =>
      widget.companyId ?? VpsAuthService.instance.currentCompanyId;
  String? get _userId => VpsAuthService.instance.currentUser?.id;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final data = await _api.getEmployeeAdjustments(
        companyId: _companyId,
        month: _selectedMonth,
        year: _selectedYear,
        type: _filterType,
      );
      setState(() {
        _adjustments = List<Map<String, dynamic>>.from(data['data'] ?? []);
        _summary = data['summary'] as Map<String, dynamic>?;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في تحميل البيانات')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = context.responsive;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text('الخصومات والمكافآت',
              style: TextStyle(fontSize: r.appBarTitleSize)),
          backgroundColor: Colors.teal[700],
          foregroundColor: Colors.white,
          elevation: 0,
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loadData,
              tooltip: 'تحديث',
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _showAddDialog(context),
          backgroundColor: Colors.teal[700],
          foregroundColor: Colors.white,
          icon: const Icon(Icons.add),
          label: const Text('إضافة'),
        ),
        body: Column(
          children: [
            _buildFilters(),
            if (_summary != null) _buildSummaryCards(),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _adjustments.isEmpty
                      ? _buildEmptyState()
                      : _buildList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilters() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // الشهر
          Expanded(
            child: DropdownButtonFormField<int>(
              value: _selectedMonth,
              decoration: InputDecoration(
                labelText: 'الشهر',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                isDense: true,
              ),
              items: List.generate(
                12,
                (i) => DropdownMenuItem(
                    value: i + 1, child: Text(_monthName(i + 1))),
              ),
              onChanged: (v) {
                setState(() => _selectedMonth = v!);
                _loadData();
              },
            ),
          ),
          const SizedBox(width: 12),
          // السنة
          Expanded(
            child: DropdownButtonFormField<int>(
              value: _selectedYear,
              decoration: InputDecoration(
                labelText: 'السنة',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                isDense: true,
              ),
              items: List.generate(
                5,
                (i) => DropdownMenuItem(
                  value: DateTime.now().year - 2 + i,
                  child: Text('${DateTime.now().year - 2 + i}'),
                ),
              ),
              onChanged: (v) {
                setState(() => _selectedYear = v!);
                _loadData();
              },
            ),
          ),
          const SizedBox(width: 12),
          // النوع
          Expanded(
            child: DropdownButtonFormField<int?>(
              value: _filterType,
              decoration: InputDecoration(
                labelText: 'النوع',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                isDense: true,
              ),
              items: const [
                DropdownMenuItem(value: null, child: Text('الكل')),
                DropdownMenuItem(value: 0, child: Text('خصومات')),
                DropdownMenuItem(value: 1, child: Text('مكافآت')),
                DropdownMenuItem(value: 2, child: Text('بدلات')),
              ],
              onChanged: (v) {
                setState(() => _filterType = v);
                _loadData();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCards() {
    final totalDeductions = (_summary?['TotalDeductions'] ?? 0).toDouble();
    final totalBonuses = (_summary?['TotalBonuses'] ?? 0).toDouble();
    final totalAllowances = (_summary?['TotalAllowances'] ?? 0).toDouble();
    final count = _summary?['Count'] ?? 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          _summaryCard('خصومات', totalDeductions, Colors.red,
              Icons.remove_circle_outline),
          const SizedBox(width: 8),
          _summaryCard(
              'مكافآت', totalBonuses, Colors.green, Icons.card_giftcard),
          const SizedBox(width: 8),
          _summaryCard('بدلات', totalAllowances, Colors.blue,
              Icons.account_balance_wallet),
          const SizedBox(width: 8),
          _summaryCard('إجمالي', count.toDouble(), Colors.teal, Icons.list_alt,
              isCurrency: false),
        ],
      ),
    );
  }

  Widget _summaryCard(String title, double value, Color color, IconData icon,
      {bool isCurrency = true}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 4),
            Text(
              isCurrency ? _formatCurrency(value) : value.toInt().toString(),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
                color: color,
              ),
            ),
            Text(title,
                style: TextStyle(fontSize: 11, color: Colors.grey[600])),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.receipt_long_outlined, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            'لا توجد خصومات أو مكافآت لهذا الشهر',
            style: TextStyle(fontSize: 16, color: Colors.grey[500]),
          ),
          const SizedBox(height: 8),
          Text(
            'اضغط على + لإضافة خصم أو مكافأة جديدة',
            style: TextStyle(fontSize: 13, color: Colors.grey[400]),
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _adjustments.length,
      itemBuilder: (context, index) {
        final adj = _adjustments[index];
        return _buildAdjustmentCard(adj);
      },
    );
  }

  Widget _buildAdjustmentCard(Map<String, dynamic> adj) {
    final typeValue = adj['TypeValue'] ?? 0;
    final typeName = _getTypeName(typeValue);
    final typeColor = _getTypeColor(typeValue);
    final typeIcon = _getTypeIcon(typeValue);
    final isApplied = adj['IsApplied'] ?? false;
    final isRecurring = adj['IsRecurring'] ?? false;
    final amount = (adj['Amount'] ?? 0).toDouble();

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 1,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: typeColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(typeIcon, color: typeColor, size: 24),
        ),
        title: Row(
          children: [
            Text(
              adj['UserName'] ?? '',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: typeColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(typeName,
                  style: TextStyle(color: typeColor, fontSize: 11)),
            ),
            if (isRecurring) ...[
              const SizedBox(width: 4),
              Tooltip(
                message: 'متكرر شهرياً',
                child: Icon(Icons.repeat, size: 16, color: Colors.blue[400]),
              ),
            ],
            if (isApplied) ...[
              const SizedBox(width: 4),
              Tooltip(
                message: 'تم التطبيق على الراتب',
                child: Icon(Icons.check_circle,
                    size: 16, color: Colors.green[400]),
              ),
            ],
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if ((adj['Description'] ?? '').toString().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(adj['Description'] ?? '',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              ),
            if ((adj['Category'] ?? '').toString().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text('الفئة: ${adj['Category']}',
                    style: TextStyle(fontSize: 11, color: Colors.grey[500])),
              ),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '${typeValue == 0 ? "-" : "+"}${_formatCurrency(amount)}',
              style: TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 15, color: typeColor),
            ),
            Text('${adj['Month']}/${adj['Year']}',
                style: TextStyle(fontSize: 11, color: Colors.grey[500])),
          ],
        ),
        onTap: isApplied ? null : () => _showEditDialog(context, adj),
        onLongPress: isApplied ? null : () => _showDeleteDialog(context, adj),
      ),
    );
  }

  void _showAddDialog(BuildContext context) {
    final formKey = GlobalKey<FormState>();
    String? selectedUserId;
    String? selectedUserName;
    int selectedType = 0;
    final amountCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    final categoryCtrl = TextEditingController();
    bool isRecurring = false;

    // Fetch employees for dropdown
    List<Map<String, dynamic>> employees = [];
    bool loadingEmployees = true;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setDialogState) {
          // Load employees on first build
          if (loadingEmployees) {
            _loadEmployees().then((data) {
              setDialogState(() {
                employees = data;
                loadingEmployees = false;
              });
            });
          }

          return AlertDialog(
            title: Row(
              children: [
                Icon(Icons.add_circle, color: Colors.teal[700]),
                const SizedBox(width: 8),
                const Text('إضافة خصم / مكافأة'),
              ],
            ),
            content: SizedBox(
              width: 480,
              child: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // الموظف
                      loadingEmployees
                          ? const LinearProgressIndicator()
                          : DropdownButtonFormField<String>(
                              value: selectedUserId,
                              decoration: _inputDecor('الموظف'),
                              items: employees
                                  .map((e) => DropdownMenuItem(
                                      value: e['Id']?.toString() ??
                                          e['id']?.toString(),
                                      child: Text(e['FullName']?.toString() ??
                                          e['fullName']?.toString() ??
                                          '')))
                                  .toList(),
                              onChanged: (v) {
                                setDialogState(() {
                                  selectedUserId = v;
                                  selectedUserName = employees
                                      .firstWhere(
                                          (e) =>
                                              (e['Id']?.toString() ??
                                                  e['id']?.toString()) ==
                                              v,
                                          orElse: () => {})['FullName']
                                      ?.toString();
                                });
                              },
                              validator: (v) => v == null ? 'اختر موظف' : null,
                            ),
                      const SizedBox(height: 12),
                      // النوع
                      DropdownButtonFormField<int>(
                        value: selectedType,
                        decoration: _inputDecor('النوع'),
                        items: const [
                          DropdownMenuItem(value: 0, child: Text('خصم')),
                          DropdownMenuItem(value: 1, child: Text('مكافأة')),
                          DropdownMenuItem(value: 2, child: Text('بدل')),
                        ],
                        onChanged: (v) =>
                            setDialogState(() => selectedType = v!),
                      ),
                      const SizedBox(height: 12),
                      // الفئة
                      TextFormField(
                        controller: categoryCtrl,
                        decoration: _inputDecor('الفئة (اختياري)',
                            hint: 'مثال: سلفة، غرامة، بدل نقل...'),
                      ),
                      const SizedBox(height: 12),
                      // المبلغ
                      TextFormField(
                        controller: amountCtrl,
                        decoration: _inputDecor('المبلغ'),
                        keyboardType: TextInputType.number,
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'أدخل المبلغ';
                          if (double.tryParse(v) == null ||
                              double.parse(v) <= 0) {
                            return 'أدخل مبلغ صحيح';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      // الوصف
                      TextFormField(
                        controller: descCtrl,
                        decoration: _inputDecor('الوصف/السبب'),
                        maxLines: 2,
                      ),
                      const SizedBox(height: 12),
                      // ملاحظات
                      TextFormField(
                        controller: notesCtrl,
                        decoration: _inputDecor('ملاحظات (اختياري)'),
                      ),
                      const SizedBox(height: 12),
                      // متكرر
                      SwitchListTile(
                        title: const Text('متكرر شهرياً'),
                        subtitle: const Text(
                            'يُطبق تلقائياً كل شهر عند إنشاء المسيّر',
                            style: TextStyle(fontSize: 11)),
                        value: isRecurring,
                        onChanged: (v) => setDialogState(() => isRecurring = v),
                        activeColor: Colors.teal,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('إلغاء'),
              ),
              FilledButton.icon(
                onPressed: () async {
                  if (!formKey.currentState!.validate()) return;
                  try {
                    Navigator.pop(ctx);
                    await _api.createEmployeeAdjustment(
                      userId: selectedUserId!,
                      companyId: _companyId!,
                      type: selectedType,
                      category: categoryCtrl.text.isNotEmpty
                          ? categoryCtrl.text
                          : null,
                      amount: double.parse(amountCtrl.text),
                      month: _selectedMonth,
                      year: _selectedYear,
                      description: descCtrl.text,
                      notes: notesCtrl.text.isNotEmpty ? notesCtrl.text : null,
                      createdById: _userId!,
                      isRecurring: isRecurring,
                    );
                    _loadData();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('تم الإضافة بنجاح')),
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('خطأ')),
                      );
                    }
                  }
                },
                icon: const Icon(Icons.save),
                label: const Text('حفظ'),
                style:
                    FilledButton.styleFrom(backgroundColor: Colors.teal[700]),
              ),
            ],
          );
        });
      },
    );
  }

  void _showEditDialog(BuildContext context, Map<String, dynamic> adj) {
    final formKey = GlobalKey<FormState>();
    int selectedType = adj['TypeValue'] ?? 0;
    final amountCtrl =
        TextEditingController(text: (adj['Amount'] ?? 0).toString());
    final descCtrl =
        TextEditingController(text: adj['Description']?.toString() ?? '');
    final notesCtrl =
        TextEditingController(text: adj['Notes']?.toString() ?? '');
    final categoryCtrl =
        TextEditingController(text: adj['Category']?.toString() ?? '');
    bool isRecurring = adj['IsRecurring'] ?? false;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setDialogState) {
          return AlertDialog(
            title: Row(
              children: [
                Icon(Icons.edit, color: Colors.teal[700]),
                const SizedBox(width: 8),
                const Text('تعديل'),
              ],
            ),
            content: SizedBox(
              width: 420,
              child: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('الموظف: ${adj['UserName'] ?? ''}',
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<int>(
                        value: selectedType,
                        decoration: _inputDecor('النوع'),
                        items: const [
                          DropdownMenuItem(value: 0, child: Text('خصم')),
                          DropdownMenuItem(value: 1, child: Text('مكافأة')),
                          DropdownMenuItem(value: 2, child: Text('بدل')),
                        ],
                        onChanged: (v) =>
                            setDialogState(() => selectedType = v!),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: categoryCtrl,
                        decoration: _inputDecor('الفئة'),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: amountCtrl,
                        decoration: _inputDecor('المبلغ'),
                        keyboardType: TextInputType.number,
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'أدخل المبلغ';
                          if (double.tryParse(v) == null ||
                              double.parse(v) <= 0) {
                            return 'أدخل مبلغ صحيح';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: descCtrl,
                        decoration: _inputDecor('الوصف/السبب'),
                        maxLines: 2,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: notesCtrl,
                        decoration: _inputDecor('ملاحظات'),
                      ),
                      const SizedBox(height: 12),
                      SwitchListTile(
                        title: const Text('متكرر شهرياً'),
                        value: isRecurring,
                        onChanged: (v) => setDialogState(() => isRecurring = v),
                        activeColor: Colors.teal,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('إلغاء'),
              ),
              FilledButton.icon(
                onPressed: () async {
                  if (!formKey.currentState!.validate()) return;
                  try {
                    Navigator.pop(ctx);
                    final id = adj['Id'] ?? adj['id'];
                    await _api.updateEmployeeAdjustment(
                      id is int ? id : int.parse(id.toString()),
                      type: selectedType,
                      category: categoryCtrl.text,
                      amount: double.parse(amountCtrl.text),
                      description: descCtrl.text,
                      notes: notesCtrl.text,
                      isRecurring: isRecurring,
                    );
                    _loadData();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('تم التعديل بنجاح')),
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('خطأ')),
                      );
                    }
                  }
                },
                icon: const Icon(Icons.save),
                label: const Text('حفظ'),
                style:
                    FilledButton.styleFrom(backgroundColor: Colors.teal[700]),
              ),
            ],
          );
        });
      },
    );
  }

  void _showDeleteDialog(BuildContext context, Map<String, dynamic> adj) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: Text(
            'هل تريد حذف ${_getTypeName(adj['TypeValue'] ?? 0)} بمبلغ ${_formatCurrency((adj['Amount'] ?? 0).toDouble())} للموظف ${adj['UserName'] ?? ''}؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                final id = adj['Id'] ?? adj['id'];
                await _api.deleteEmployeeAdjustment(
                    id is int ? id : int.parse(id.toString()));
                _loadData();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('تم الحذف')),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('خطأ')),
                  );
                }
              }
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
  }

  Future<List<Map<String, dynamic>>> _loadEmployees() async {
    try {
      final data = await _api.getCompanyEmployees(_companyId!);
      final list = data['data'];
      if (list is List) {
        return list.cast<Map<String, dynamic>>();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  InputDecoration _inputDecor(String label, {String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      isDense: true,
    );
  }

  String _getTypeName(int type) {
    switch (type) {
      case 0:
        return 'خصم';
      case 1:
        return 'مكافأة';
      case 2:
        return 'بدل';
      default:
        return 'غير محدد';
    }
  }

  Color _getTypeColor(int type) {
    switch (type) {
      case 0:
        return Colors.red;
      case 1:
        return Colors.green;
      case 2:
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  IconData _getTypeIcon(int type) {
    switch (type) {
      case 0:
        return Icons.remove_circle_outline;
      case 1:
        return Icons.card_giftcard;
      case 2:
        return Icons.account_balance_wallet;
      default:
        return Icons.help_outline;
    }
  }

  String _formatCurrency(double amount) {
    if (amount == 0) return '0';
    return amount.round().toString();
  }

  String _monthName(int month) {
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
      'ديسمبر'
    ];
    return months[month - 1];
  }
}
