import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/accounting_service.dart';
import '../../services/vps_auth_service.dart';
import '../../theme/accounting_theme.dart';

/// صفحة المصروفات
class ExpensesPage extends StatefulWidget {
  final String? companyId;

  const ExpensesPage({super.key, this.companyId});

  @override
  State<ExpensesPage> createState() => _ExpensesPageState();
}

class _ExpensesPageState extends State<ExpensesPage> {
  bool _isLoading = true;
  String? _errorMessage;
  List<dynamic> _expenses = [];

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
      final result = await AccountingService.instance
          .getExpenses(companyId: widget.companyId);
      if (result['success'] == true) {
        _expenses = (result['data'] is List) ? result['data'] : [];
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
            _buildSummary(),
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
                      : _buildList(),
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
              gradient: AccountingTheme.neonOrangeGradient,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.receipt_rounded,
                color: Colors.white, size: 18),
          ),
          const SizedBox(width: 12),
          Text('المصروفات',
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
          ElevatedButton.icon(
            onPressed: _showAddDialog,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('إضافة مصروف'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AccountingTheme.neonOrange,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummary() {
    final total = _expenses.fold<double>(
      0,
      (s, e) => s + ((e['Amount'] ?? 0) as num).toDouble(),
    );
    final categories = <String, double>{};
    for (final e in _expenses) {
      final cat = e['Category']?.toString() ?? 'أخرى';
      categories[cat] =
          (categories[cat] ?? 0) + ((e['Amount'] ?? 0) as num).toDouble();
    }
    final topCategory = categories.isNotEmpty
        ? categories.entries.reduce((a, b) => a.value >= b.value ? a : b)
        : null;

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Wrap(
        spacing: 12,
        children: [
          _chip('الإجمالي', '${_fmt(total)} د.ع', AccountingTheme.danger),
          _chip('العدد', '${_expenses.length}', AccountingTheme.accent),
          if (topCategory != null)
            _chip('أكبر فئة', '${topCategory.key}: ${_fmt(topCategory.value)}',
                AccountingTheme.warning),
        ],
      ),
    );
  }

  Widget _chip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style:
                  TextStyle(color: color.withValues(alpha: 0.7), fontSize: 12)),
          const SizedBox(width: 6),
          Text(value,
              style: TextStyle(
                  color: color, fontWeight: FontWeight.bold, fontSize: 14)),
        ],
      ),
    );
  }

  Widget _buildList() {
    if (_expenses.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.money_off, color: AccountingTheme.textMuted, size: 64),
            SizedBox(height: 16),
            Text('لا توجد مصروفات',
                style: TextStyle(color: AccountingTheme.textMuted)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      itemCount: _expenses.length,
      itemBuilder: (_, i) {
        final e = _expenses[i];
        return Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AccountingTheme.bgCard,
            borderRadius: BorderRadius.circular(10),
            border: const Border(
                right: BorderSide(color: AccountingTheme.danger, width: 3)),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AccountingTheme.danger.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(_categoryIcon(e['Category']),
                    color: AccountingTheme.danger, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      e['Description'] ?? 'بدون وصف',
                      style: const TextStyle(
                          color: AccountingTheme.textPrimary,
                          fontWeight: FontWeight.bold,
                          fontSize: 14),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _expenseCategoryLabel(e['Category']),
                      style: const TextStyle(
                          color: AccountingTheme.danger, fontSize: 11),
                    ),
                  ],
                ),
              ),
              // المبلغ
              SizedBox(
                width: 100,
                child: Text(
                  '${_fmt(e['Amount'])} د.ع',
                  style: const TextStyle(
                      color: AccountingTheme.danger,
                      fontWeight: FontWeight.bold,
                      fontSize: 14),
                  textAlign: TextAlign.center,
                ),
              ),
              // التاريخ
              SizedBox(
                width: 100,
                child: Text(
                  _formatDate(e['ExpenseDate'] ?? e['CreatedAt']),
                  style: const TextStyle(
                      color: AccountingTheme.textSecondary, fontSize: 11),
                  textAlign: TextAlign.center,
                ),
              ),
              // الحساب
              if (e['AccountName'] != null)
                SizedBox(
                  width: 100,
                  child: Text(
                    e['AccountName'],
                    style: const TextStyle(
                        color: AccountingTheme.info, fontSize: 11),
                    textAlign: TextAlign.center,
                  ),
                ),
              // ملاحظات
              if (e['Notes'] != null)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Tooltip(
                    message: e['Notes'],
                    child: Icon(Icons.notes,
                        color: AccountingTheme.textMuted, size: 18),
                  ),
                ),
              // أزرار تعديل وحذف
              const SizedBox(width: 8),
              _actionBtn(Icons.edit, AccountingTheme.info,
                  () => _showEditExpenseDialog(e)),
              const SizedBox(width: 4),
              _actionBtn(Icons.delete_outline, AccountingTheme.danger,
                  () => _confirmDeleteExpense(e)),
            ],
          ),
        );
      },
    );
  }

  void _showAddDialog() async {
    // جلب الحسابات أولاً
    final accountsResult = await AccountingService.instance
        .getAccounts(companyId: widget.companyId);
    final accounts = (accountsResult['data'] as List?) ?? [];
    // فلترة حسابات المصروفات فقط (AccountType == 'Expenses') والحسابات الفرعية فقط
    final expenseAccounts = accounts
        .where((a) =>
            a['AccountType']?.toString() == 'Expenses' && a['IsLeaf'] == true)
        .toList();
    final accountsList = expenseAccounts;

    if (!mounted) return;

    final descCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    String selectedCategory = 'General';
    String? selectedAccountId =
        accountsList.isNotEmpty ? accountsList.first['Id']?.toString() : null;

    final categories = [
      {'value': 'General', 'label': 'عام'},
      {'value': 'Rent', 'label': 'إيجار'},
      {'value': 'Utilities', 'label': 'خدمات'},
      {'value': 'Salaries', 'label': 'رواتب'},
      {'value': 'Maintenance', 'label': 'صيانة'},
      {'value': 'Equipment', 'label': 'معدات'},
      {'value': 'Fuel', 'label': 'وقود'},
      {'value': 'Internet', 'label': 'إنترنت'},
      {'value': 'Marketing', 'label': 'تسويق'},
    ];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, ss) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            backgroundColor: AccountingTheme.bgCard,
            title: const Text('إضافة مصروف',
                style: TextStyle(color: AccountingTheme.textPrimary)),
            content: SizedBox(
              width: 400,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _field('الوصف', descCtrl),
                    const SizedBox(height: 10),
                    _field('المبلغ', amountCtrl, isNumber: true),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: selectedAccountId,
                      dropdownColor: AccountingTheme.bgCard,
                      style:
                          const TextStyle(color: AccountingTheme.textPrimary),
                      isExpanded: true,
                      items: accountsList.map<DropdownMenuItem<String>>((a) {
                        return DropdownMenuItem(
                          value: a['Id']?.toString(),
                          child: Text('${a['Code'] ?? ''} - ${a['Name'] ?? ''}',
                              overflow: TextOverflow.ellipsis),
                        );
                      }).toList(),
                      onChanged: (v) => ss(() => selectedAccountId = v),
                      decoration: InputDecoration(
                        labelText: 'الحساب',
                        labelStyle:
                            const TextStyle(color: AccountingTheme.textMuted),
                        filled: true,
                        fillColor: AccountingTheme.bgCardHover,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: selectedCategory,
                      dropdownColor: AccountingTheme.bgCard,
                      style:
                          const TextStyle(color: AccountingTheme.textPrimary),
                      items: categories.map((c) {
                        return DropdownMenuItem(
                            value: c['value'], child: Text(c['label']!));
                      }).toList(),
                      onChanged: (v) =>
                          ss(() => selectedCategory = v ?? 'General'),
                      decoration: InputDecoration(
                        labelText: 'الفئة',
                        labelStyle:
                            const TextStyle(color: AccountingTheme.textMuted),
                        filled: true,
                        fillColor: AccountingTheme.bgCardHover,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 10),
                    _field('ملاحظات', notesCtrl),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('إلغاء',
                      style: TextStyle(color: AccountingTheme.textMuted))),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: AccountingTheme.danger,
                    foregroundColor: Colors.white),
                onPressed: () async {
                  if (descCtrl.text.isEmpty ||
                      amountCtrl.text.isEmpty ||
                      selectedAccountId == null) {
                    _snack(
                        'الرجاء ملء الحقول المطلوبة', AccountingTheme.warning);
                    return;
                  }
                  Navigator.pop(ctx);
                  final result = await AccountingService.instance.createExpense(
                    accountId: selectedAccountId!,
                    description: descCtrl.text,
                    amount: double.tryParse(amountCtrl.text) ?? 0,
                    category: selectedCategory,
                    notes: notesCtrl.text.isEmpty ? null : notesCtrl.text,
                    companyId: widget.companyId ?? '',
                    createdById: VpsAuthService.instance.currentUser?.id,
                  );
                  if (result['success'] == true) {
                    _snack('تم إضافة المصروف', AccountingTheme.success);
                    _loadData();
                  } else {
                    _snack(result['message'] ?? 'خطأ', AccountingTheme.danger);
                  }
                },
                child: const Text('إضافة'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(String label, TextEditingController ctrl,
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

  IconData _categoryIcon(dynamic category) {
    switch (category?.toString()) {
      case 'Rent':
        return Icons.home;
      case 'Utilities':
        return Icons.electrical_services;
      case 'Salaries':
        return Icons.people;
      case 'Maintenance':
        return Icons.build;
      case 'Equipment':
        return Icons.devices;
      case 'Fuel':
        return Icons.local_gas_station;
      case 'Internet':
        return Icons.wifi;
      case 'Marketing':
        return Icons.campaign;
      default:
        return Icons.receipt_long;
    }
  }

  String _expenseCategoryLabel(dynamic category) {
    switch (category?.toString()) {
      case 'General':
        return 'عام';
      case 'Rent':
        return 'إيجار';
      case 'Utilities':
        return 'خدمات';
      case 'Salaries':
        return 'رواتب';
      case 'Maintenance':
        return 'صيانة';
      case 'Equipment':
        return 'معدات';
      case 'Fuel':
        return 'وقود';
      case 'Internet':
        return 'إنترنت';
      case 'Marketing':
        return 'تسويق';
      default:
        return category?.toString() ?? 'عام';
    }
  }

  Widget _actionBtn(IconData icon, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(icon, color: color, size: 16),
      ),
    );
  }

  void _showEditExpenseDialog(Map<String, dynamic> e) {
    final descCtrl = TextEditingController(text: e['Description'] ?? '');
    final amountCtrl =
        TextEditingController(text: e['Amount']?.toString() ?? '');
    final notesCtrl = TextEditingController(text: e['Notes'] ?? '');
    final categoryCtrl =
        TextEditingController(text: e['Category'] ?? 'General');

    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: AccountingTheme.bgCard,
          title: const Text('تعديل مصروف',
              style: TextStyle(color: AccountingTheme.textPrimary)),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _field('الوصف', descCtrl),
                const SizedBox(height: 10),
                _field('المبلغ', amountCtrl, isNumber: true),
                const SizedBox(height: 10),
                _field('ملاحظات', notesCtrl),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء',
                  style: TextStyle(color: AccountingTheme.textMuted)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AccountingTheme.info,
                  foregroundColor: Colors.white),
              onPressed: () async {
                Navigator.pop(ctx);
                final result = await AccountingService.instance.updateExpense(
                  e['Id'].toString(),
                  {
                    'Description': descCtrl.text,
                    'Amount': double.tryParse(amountCtrl.text),
                    'Notes': notesCtrl.text.isEmpty ? null : notesCtrl.text,
                    'Category': categoryCtrl.text,
                  },
                );
                if (result['success'] == true) {
                  _snack('تم تحديث المصروف', AccountingTheme.success);
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

  void _confirmDeleteExpense(Map<String, dynamic> e) {
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: AccountingTheme.bgCard,
          title: const Text('تأكيد الحذف',
              style: TextStyle(color: AccountingTheme.danger)),
          content: Text(
            'هل تريد حذف المصروف "${e['Description']}" بمبلغ ${_fmt(e['Amount'])} د.ع؟\nسيتم إلغاء القيد المحاسبي المرتبط أيضاً.',
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
                    .deleteExpense(e['Id'].toString());
                if (result['success'] == true) {
                  _snack('تم حذف المصروف', AccountingTheme.success);
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

  String _formatDate(dynamic date) {
    if (date == null) return '';
    try {
      final d = DateTime.parse(date.toString());
      return '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';
    } catch (_) {
      return '';
    }
  }
}
