import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/accounting_service.dart';
import '../../services/vps_auth_service.dart';
import '../../services/period_closing_service.dart';
import '../../services/audit_trail_service.dart';
import '../../theme/accounting_theme.dart';
import '../../theme/accounting_responsive.dart';
import '../../widgets/accounting_skeleton.dart';
import '../../permissions/permissions.dart';

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
  int _currentPage = 1;
  int _totalPages = 1;
  int _total = 0;
  static const int _pageSize = 50;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData({int page = 1}) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final result = await AccountingService.instance
          .getExpenses(companyId: widget.companyId);
      if (result['success'] == true) {
        if (result['data'] is Map) {
          final dataMap = result['data'] as Map<String, dynamic>;
          _expenses = ((dataMap['items'] ?? dataMap['entries'] ?? []) as List);
          _currentPage = (dataMap['page'] ?? page) as int;
          _totalPages = (dataMap['totalPages'] ?? 1) as int;
          _total = (dataMap['total'] ?? _expenses.length) as int;
        } else {
          _expenses = (result['data'] is List) ? result['data'] : [];
          _currentPage = 1;
          _totalPages = 1;
          _total = _expenses.length;
        }
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
              _buildSummary(),
              Expanded(
                child: _isLoading
                    ? const AccountingSkeleton(rows: 8, columns: 4)
                    : _errorMessage != null
                        ? Center(
                            child: Text(_errorMessage!,
                                style: const TextStyle(
                                    color: AccountingTheme.danger)))
                        : _buildList(),
              ),
              _buildPaginationBar(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPageToolbar() {
    final ar = context.accR;
    final isMob = MediaQuery.of(context).size.width < 700;
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: isMob ? 8 : ar.spaceXL, vertical: isMob ? 6 : ar.spaceL),
      decoration: const BoxDecoration(
        color: AccountingTheme.bgCard,
        border: Border(bottom: BorderSide(color: AccountingTheme.borderColor)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_forward_rounded, size: 20),
            tooltip: 'رجوع',
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            padding: EdgeInsets.zero,
            style: IconButton.styleFrom(
                foregroundColor: AccountingTheme.textSecondary),
          ),
          SizedBox(width: isMob ? 4 : ar.spaceS),
          Container(
            padding: EdgeInsets.all(isMob ? 4 : ar.spaceS),
            decoration: BoxDecoration(
              gradient: AccountingTheme.neonOrangeGradient,
              borderRadius: BorderRadius.circular(ar.btnRadius),
            ),
            child: Icon(Icons.receipt_rounded,
                color: Colors.white, size: isMob ? 18 : ar.iconM),
          ),
          SizedBox(width: isMob ? 6 : ar.spaceM),
          Text('المصروفات',
              style: GoogleFonts.cairo(
                  fontSize: isMob ? 14 : ar.headingMedium,
                  fontWeight: FontWeight.bold,
                  color: AccountingTheme.textPrimary)),
          const Spacer(),
          IconButton(
            onPressed: _loadData,
            icon: Icon(Icons.refresh, size: isMob ? 18 : ar.iconM),
            tooltip: 'تحديث',
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            padding: EdgeInsets.zero,
            style: IconButton.styleFrom(
                foregroundColor: AccountingTheme.textSecondary),
          ),
          SizedBox(width: isMob ? 4 : ar.spaceS),
          if (PermissionManager.instance.canAdd('accounting.expenses'))
            ElevatedButton.icon(
              onPressed: _showAddDialog,
              icon: Icon(Icons.add, size: isMob ? 16 : ar.iconM),
              label: Text(isMob ? 'إضافة مصروف' : 'إضافة مصروف',
                  style: GoogleFonts.cairo(fontSize: isMob ? 11 : ar.buttonText)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AccountingTheme.neonOrange,
                foregroundColor: Colors.white,
                padding: isMob
                    ? const EdgeInsets.symmetric(horizontal: 8, vertical: 4)
                    : ar.buttonPadding,
                minimumSize: isMob ? const Size(0, 30) : null,
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
      padding: EdgeInsets.all(context.accR.spaceM),
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
      padding: EdgeInsets.symmetric(
          horizontal: context.accR.spaceM, vertical: context.accR.spaceXS),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: TextStyle(
                  color: color.withValues(alpha: 0.7),
                  fontSize: context.accR.small)),
          SizedBox(width: context.accR.spaceXS),
          Text(value,
              style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: context.accR.body)),
        ],
      ),
    );
  }

  Widget _buildList() {
    if (_expenses.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.money_off,
                color: AccountingTheme.textMuted, size: context.accR.iconEmpty),
            SizedBox(height: context.accR.spaceXL),
            Text('لا توجد مصروفات',
                style: TextStyle(color: AccountingTheme.textMuted)),
          ],
        ),
      );
    }

    final isMob = MediaQuery.of(context).size.width < 700;

    return ListView.builder(
      padding:
          EdgeInsets.symmetric(horizontal: isMob ? 8 : context.accR.spaceM),
      itemCount: _expenses.length,
      itemBuilder: (_, i) {
        final e = _expenses[i];
        if (isMob) {
          return _buildMobileExpenseCard(e);
        }
        return Container(
          margin: EdgeInsets.only(bottom: 6),
          padding: EdgeInsets.all(context.accR.spaceL),
          decoration: BoxDecoration(
            color: AccountingTheme.bgCard,
            borderRadius: BorderRadius.circular(context.accR.cardRadius),
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
                    color: AccountingTheme.danger, size: context.accR.iconM),
              ),
              SizedBox(width: context.accR.spaceM),
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      e['Description'] ?? 'بدون وصف',
                      style: TextStyle(
                          color: AccountingTheme.textPrimary,
                          fontWeight: FontWeight.bold,
                          fontSize: context.accR.body),
                    ),
                    SizedBox(height: 2),
                    Text(
                      _expenseCategoryLabel(e['Category']),
                      style: TextStyle(
                          color: AccountingTheme.danger,
                          fontSize: context.accR.small),
                    ),
                  ],
                ),
              ),
              // المبلغ
              SizedBox(
                width: 100,
                child: Text(
                  '${_fmt(e['Amount'])} د.ع',
                  style: TextStyle(
                      color: AccountingTheme.danger,
                      fontWeight: FontWeight.bold,
                      fontSize: context.accR.body),
                  textAlign: TextAlign.center,
                ),
              ),
              // التاريخ
              SizedBox(
                width: 100,
                child: Text(
                  _formatDate(e['ExpenseDate'] ?? e['CreatedAt']),
                  style: TextStyle(
                      color: AccountingTheme.textSecondary,
                      fontSize: context.accR.small),
                  textAlign: TextAlign.center,
                ),
              ),
              // الحساب
              if (e['AccountName'] != null)
                SizedBox(
                  width: 100,
                  child: Text(
                    e['AccountName'],
                    style: TextStyle(
                        color: AccountingTheme.info,
                        fontSize: context.accR.small),
                    textAlign: TextAlign.center,
                  ),
                ),
              // ملاحظات
              if (e['Notes'] != null)
                Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: Tooltip(
                    message: e['Notes'],
                    child: Icon(Icons.notes,
                        color: AccountingTheme.textMuted,
                        size: context.accR.iconM),
                  ),
                ),
              // أزرار تعديل وحذف
              SizedBox(width: context.accR.spaceS),
              if (PermissionManager.instance.canEdit('accounting.expenses'))
                _actionBtn(Icons.edit, AccountingTheme.info,
                    () => _showEditExpenseDialog(e)),
              SizedBox(width: context.accR.spaceXS),
              if (PermissionManager.instance.canDelete('accounting.expenses'))
                _actionBtn(Icons.delete_outline, AccountingTheme.danger,
                    () => _confirmDeleteExpense(e)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMobileExpenseCard(Map<String, dynamic> e) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AccountingTheme.bgCard,
        borderRadius: BorderRadius.circular(10),
        border: const Border(
            right: BorderSide(color: AccountingTheme.danger, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // الصف الأول: الوصف + المبلغ
          Row(
            children: [
              Expanded(
                child: Text(
                  e['Description'] ?? 'بدون وصف',
                  style: GoogleFonts.cairo(
                      color: Colors.black,
                      fontWeight: FontWeight.bold,
                      fontSize: 13),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${_fmt(e['Amount'])} د.ع',
                style: GoogleFonts.cairo(
                    color: AccountingTheme.danger,
                    fontWeight: FontWeight.bold,
                    fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // الصف الثاني: الفئة + التاريخ + الحساب
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: AccountingTheme.danger.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  _expenseCategoryLabel(e['Category']),
                  style: GoogleFonts.cairo(
                      color: AccountingTheme.danger,
                      fontSize: 10,
                      fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _formatDate(e['ExpenseDate'] ?? e['CreatedAt']),
                style: GoogleFonts.cairo(
                    color: AccountingTheme.textSecondary, fontSize: 10),
              ),
              if (e['AccountName'] != null) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    e['AccountName'] ?? '',
                    style: GoogleFonts.cairo(
                        color: AccountingTheme.info, fontSize: 10),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ] else
                const Spacer(),
              // أزرار التعديل والحذف
              const SizedBox(width: 6),
              if (PermissionManager.instance.canEdit('accounting.expenses'))
                _actionBtn(Icons.edit, AccountingTheme.info,
                    () => _showEditExpenseDialog(e)),
              const SizedBox(width: 4),
              if (PermissionManager.instance.canDelete('accounting.expenses'))
                _actionBtn(Icons.delete_outline, AccountingTheme.danger,
                    () => _confirmDeleteExpense(e)),
            ],
          ),
          // ملاحظات إن وجدت
          if (e['Notes'] != null && e['Notes'].toString().isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              e['Notes'].toString(),
              style: GoogleFonts.cairo(
                  color: AccountingTheme.textMuted, fontSize: 10),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPaginationBar() {
    if (_totalPages <= 1) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
        color: AccountingTheme.bgCard,
        border: Border(top: BorderSide(color: AccountingTheme.borderColor)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            onPressed: _currentPage > 1 ? () => _loadData(page: _currentPage - 1) : null,
            icon: const Icon(Icons.chevron_right, color: AccountingTheme.textSecondary),
          ),
          Text(
            'صفحة $_currentPage من $_totalPages ($_total سجل)',
            style: GoogleFonts.cairo(color: AccountingTheme.textSecondary, fontSize: 13),
          ),
          IconButton(
            onPressed: _currentPage < _totalPages ? () => _loadData(page: _currentPage + 1) : null,
            icon: const Icon(Icons.chevron_left, color: AccountingTheme.textSecondary),
          ),
        ],
      ),
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
            title: Text('إضافة مصروف',
                style: TextStyle(color: AccountingTheme.textPrimary)),
            content: SizedBox(
              width: context.accR.dialogSmallW,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _field('الوصف', descCtrl),
                    SizedBox(height: context.accR.spaceM),
                    _field('المبلغ', amountCtrl, isNumber: true),
                    SizedBox(height: context.accR.spaceM),
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
                    SizedBox(height: context.accR.spaceM),
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
                    SizedBox(height: context.accR.spaceM),
                    _field('ملاحظات', notesCtrl),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('إلغاء',
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
                  // فحص الفترة المحاسبية
                  final periodOk = await PeriodClosingService.checkAndWarnIfClosed(
                    context, date: DateTime.now(), companyId: widget.companyId ?? '',
                  );
                  if (!periodOk) return;
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
                    AuditTrailService.instance.log(
                      action: AuditAction.create,
                      entityType: AuditEntityType.expense,
                      entityId: result['data']?['Id']?.toString() ?? '',
                      entityDescription: 'مصروف: ${descCtrl.text}',
                    );
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
        padding: EdgeInsets.all(context.accR.spaceXS),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(icon, color: color, size: context.accR.iconS),
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
          title: Text('تعديل مصروف',
              style: TextStyle(color: AccountingTheme.textPrimary)),
          content: SizedBox(
            width: context.accR.dialogSmallW,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _field('الوصف', descCtrl),
                SizedBox(height: context.accR.spaceM),
                _field('المبلغ', amountCtrl, isNumber: true),
                SizedBox(height: context.accR.spaceM),
                _field('ملاحظات', notesCtrl),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('إلغاء',
                  style: TextStyle(color: AccountingTheme.textMuted)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AccountingTheme.info,
                  foregroundColor: Colors.white),
              onPressed: () async {
                Navigator.pop(ctx);
                // فحص الفترة المحاسبية
                final expDate = DateTime.tryParse(e['ExpenseDate']?.toString() ?? e['CreatedAt']?.toString() ?? '');
                if (expDate != null) {
                  final allowed = await PeriodClosingService.checkAndWarnIfClosed(
                    context, date: expDate, companyId: widget.companyId ?? '',
                  );
                  if (!allowed) return;
                }
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
                  AuditTrailService.instance.log(
                    action: AuditAction.edit,
                    entityType: AuditEntityType.expense,
                    entityId: e['Id']?.toString() ?? '',
                    entityDescription: 'مصروف: ${descCtrl.text}',
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

  void _confirmDeleteExpense(Map<String, dynamic> e) {
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: AccountingTheme.bgCard,
          title: Text('تأكيد الحذف',
              style: TextStyle(color: AccountingTheme.danger)),
          content: Text(
            'هل تريد حذف المصروف "${e['Description']}" بمبلغ ${_fmt(e['Amount'])} د.ع؟\nسيتم إلغاء القيد المحاسبي المرتبط أيضاً.',
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
                final expDate = DateTime.tryParse(e['ExpenseDate']?.toString() ?? e['CreatedAt']?.toString() ?? '');
                if (expDate != null) {
                  final allowed = await PeriodClosingService.checkAndWarnIfClosed(
                    context, date: expDate, companyId: widget.companyId ?? '',
                  );
                  if (!allowed) return;
                }
                final result = await AccountingService.instance
                    .deleteExpense(e['Id'].toString());
                if (result['success'] == true) {
                  _snack('تم حذف المصروف', AccountingTheme.success);
                  AuditTrailService.instance.log(
                    action: AuditAction.delete,
                    entityType: AuditEntityType.expense,
                    entityId: e['Id']?.toString() ?? '',
                    entityDescription: 'مصروف: ${e['Description'] ?? ''}',
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
