import 'package:flutter/material.dart';
import '../../frontend/frontend.dart'; // نظام تصميم الصدارة الموحّد (sd)
import '../../services/accounting_service.dart';
import '../../services/vps_auth_service.dart';
import '../../services/period_closing_service.dart';
import '../../services/audit_trail_service.dart';
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
    return SdTheme.scope(
      child: Scaffold(
        backgroundColor: SdColors.ground,
        appBar: SdAppBar(
          title: 'المصروفات',
          actions: [
            SdAppBarAction(
              icon: Icons.refresh,
              label: 'تحديث',
              onPressed: () => _loadData(),
            ),
            if (PermissionManager.instance.canAdd('accounting.expenses'))
              SdAppBarAction(
                icon: Icons.add,
                label: 'إضافة مصروف',
                onPressed: _showAddDialog,
              ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              _buildSummary(),
              Expanded(
                child: _isLoading
                    ? const AccountingSkeleton(rows: 8, columns: 4)
                    : _errorMessage != null
                        ? Center(
                            child: Text(_errorMessage!,
                                style: const TextStyle(
                                    color: SdColors.danger)))
                        : _buildList(),
              ),
              _buildPaginationBar(),
            ],
          ),
        ),
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
      padding: const EdgeInsets.all(SdSpace.md),
      child: Wrap(
        spacing: SdSpace.sm,
        runSpacing: SdSpace.xs,
        children: [
          _chip('الإجمالي', '${_fmt(total)} د.ع', SdStatus.danger.tone),
          _chip('العدد', '${_expenses.length}', SdGroup.admin.tone),
          if (topCategory != null)
            _chip('أكبر فئة', '${topCategory.key}: ${_fmt(topCategory.value)}',
                SdStatus.warning.tone),
        ],
      ),
    );
  }

  Widget _chip(String label, String value, SdTone tone) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: SdSpace.sm, vertical: 6),
      decoration: BoxDecoration(
        color: tone.tint,
        borderRadius: BorderRadius.circular(SdRadius.xs),
        boxShadow: [BoxShadow(color: tone.tintEdge, offset: const Offset(0, SdDepth.chip))],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: TextStyle(
                  fontFamily: SdText.family,
                  color: tone.text,
                  fontWeight: FontWeight.w700,
                  fontSize: 11.5)),
          const SizedBox(width: SdSpace.xs),
          Text(value,
              style: TextStyle(
                  fontFamily: SdText.family,
                  color: tone.text,
                  fontWeight: FontWeight.w900,
                  fontSize: 13.5)),
        ],
      ),
    );
  }

  Widget _buildList() {
    if (_expenses.isEmpty) {
      return const SingleChildScrollView(
        child: SdEmptyState(
          title: 'لا توجد مصروفات',
          icon: Icons.money_off,
        ),
      );
    }

    final isMob = MediaQuery.of(context).size.width < 700;

    return ListView.builder(
      padding:
          EdgeInsets.fromLTRB(isMob ? 8 : SdSpace.md, SdSpace.xs, isMob ? 8 : SdSpace.md, SdSpace.md),
      itemCount: _expenses.length,
      itemBuilder: (_, i) {
        final e = _expenses[i];
        if (isMob) {
          return _buildMobileExpenseCard(e);
        }
        return Container(
          margin: const EdgeInsets.only(bottom: SdSpace.xs),
          padding: const EdgeInsets.all(SdSpace.md),
          decoration: BoxDecoration(
            color: SdColors.surface,
            borderRadius: BorderRadius.circular(SdRadius.md),
            boxShadow: SdDepth.raised(depth: SdDepth.small),
            border: const Border(
                right: BorderSide(color: SdColors.danger, width: 3)),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: SdStatus.danger.tone.tint,
                  borderRadius: BorderRadius.circular(SdRadius.xs),
                ),
                child: Icon(_categoryIcon(e['Category']),
                    color: SdStatus.danger.tone.base, size: 20),
              ),
              const SizedBox(width: SdSpace.sm),
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      e['Description'] ?? 'بدون وصف',
                      style: SdText.label,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _expenseCategoryLabel(e['Category']),
                      style: TextStyle(
                          fontFamily: SdText.family,
                          color: SdStatus.danger.tone.text,
                          fontWeight: FontWeight.w700,
                          fontSize: 11.5),
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
                      fontFamily: SdText.family,
                      color: SdStatus.danger.tone.base,
                      fontWeight: FontWeight.w900,
                      fontSize: 14),
                  textAlign: TextAlign.center,
                ),
              ),
              // التاريخ
              SizedBox(
                width: 100,
                child: Text(
                  _formatDate(e['ExpenseDate'] ?? e['CreatedAt']),
                  style: SdText.bodySm,
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
                        fontFamily: SdText.family,
                        color: SdStatus.info.tone.text,
                        fontWeight: FontWeight.w600,
                        fontSize: 11.5),
                    textAlign: TextAlign.center,
                  ),
                ),
              // ملاحظات
              if (e['Notes'] != null)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Tooltip(
                    message: e['Notes'],
                    child: const Icon(Icons.notes,
                        color: SdColors.faint, size: 20),
                  ),
                ),
              // أزرار تعديل وحذف
              const SizedBox(width: SdSpace.xs),
              if (PermissionManager.instance.canEdit('accounting.expenses'))
                _actionBtn(Icons.edit, SdStatus.info.tone.base,
                    () => _showEditExpenseDialog(e)),
              const SizedBox(width: SdSpace.xxs),
              if (PermissionManager.instance.canDelete('accounting.expenses'))
                _actionBtn(Icons.delete_outline, SdStatus.danger.tone.base,
                    () => _confirmDeleteExpense(e)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMobileExpenseCard(Map<String, dynamic> e) {
    return Container(
      margin: const EdgeInsets.only(bottom: SdSpace.xs),
      padding: const EdgeInsets.all(SdSpace.sm),
      decoration: BoxDecoration(
        color: SdColors.surface,
        borderRadius: BorderRadius.circular(SdRadius.md),
        boxShadow: SdDepth.raised(depth: SdDepth.small),
        border: const Border(
            right: BorderSide(color: SdColors.danger, width: 3)),
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
                  style: SdText.label.copyWith(fontSize: 13),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: SdSpace.xs),
              Text(
                '${_fmt(e['Amount'])} د.ع',
                style: TextStyle(
                    fontFamily: SdText.family,
                    color: SdStatus.danger.tone.base,
                    fontWeight: FontWeight.w900,
                    fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: SdSpace.xxs),
          // الصف الثاني: الفئة + التاريخ + الحساب
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: SdStatus.danger.tone.tint,
                  borderRadius: BorderRadius.circular(SdRadius.xs),
                ),
                child: Text(
                  _expenseCategoryLabel(e['Category']),
                  style: TextStyle(
                      fontFamily: SdText.family,
                      color: SdStatus.danger.tone.text,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: SdSpace.xs),
              Text(
                _formatDate(e['ExpenseDate'] ?? e['CreatedAt']),
                style: SdText.caption,
              ),
              if (e['AccountName'] != null) ...[
                const SizedBox(width: SdSpace.xs),
                Expanded(
                  child: Text(
                    e['AccountName'] ?? '',
                    style: SdText.caption.copyWith(color: SdStatus.info.tone.text),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ] else
                const Spacer(),
              // أزرار التعديل والحذف
              const SizedBox(width: 6),
              if (PermissionManager.instance.canEdit('accounting.expenses'))
                _actionBtn(Icons.edit, SdStatus.info.tone.base,
                    () => _showEditExpenseDialog(e)),
              const SizedBox(width: SdSpace.xxs),
              if (PermissionManager.instance.canDelete('accounting.expenses'))
                _actionBtn(Icons.delete_outline, SdStatus.danger.tone.base,
                    () => _confirmDeleteExpense(e)),
            ],
          ),
          // ملاحظات إن وجدت
          if (e['Notes'] != null && e['Notes'].toString().isNotEmpty) ...[
            const SizedBox(height: SdSpace.xxs),
            Text(
              e['Notes'].toString(),
              style: SdText.caption,
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
      padding: const EdgeInsets.symmetric(horizontal: SdSpace.md, vertical: SdSpace.xs),
      decoration: const BoxDecoration(
        color: SdColors.surface,
        border: Border(top: BorderSide(color: SdColors.divider)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            onPressed: _currentPage > 1 ? () => _loadData(page: _currentPage - 1) : null,
            icon: const Icon(Icons.chevron_right, color: SdColors.muted),
          ),
          Text(
            'صفحة $_currentPage من $_totalPages ($_total سجل)',
            style: SdText.bodySm,
          ),
          IconButton(
            onPressed: _currentPage < _totalPages ? () => _loadData(page: _currentPage + 1) : null,
            icon: const Icon(Icons.chevron_left, color: SdColors.muted),
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
            backgroundColor: SdColors.surface,
            title: Text('إضافة مصروف',
                style: TextStyle(color: SdColors.ink)),
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
                      dropdownColor: SdColors.surface,
                      style:
                          const TextStyle(color: SdColors.ink),
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
                            const TextStyle(color: SdColors.faint),
                        filled: true,
                        fillColor: SdColors.surfaceAlt,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide.none),
                      ),
                    ),
                    SizedBox(height: context.accR.spaceM),
                    DropdownButtonFormField<String>(
                      value: selectedCategory,
                      dropdownColor: SdColors.surface,
                      style:
                          const TextStyle(color: SdColors.ink),
                      items: categories.map((c) {
                        return DropdownMenuItem(
                            value: c['value'], child: Text(c['label']!));
                      }).toList(),
                      onChanged: (v) =>
                          ss(() => selectedCategory = v ?? 'General'),
                      decoration: InputDecoration(
                        labelText: 'الفئة',
                        labelStyle:
                            const TextStyle(color: SdColors.faint),
                        filled: true,
                        fillColor: SdColors.surfaceAlt,
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
                      style: TextStyle(color: SdColors.faint))),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: SdColors.danger,
                    foregroundColor: Colors.white),
                onPressed: () async {
                  if (descCtrl.text.isEmpty ||
                      amountCtrl.text.isEmpty ||
                      selectedAccountId == null) {
                    _snack(
                        'الرجاء ملء الحقول المطلوبة', SdColors.warning);
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
                    _snack('تم إضافة المصروف', SdColors.success);
                    AuditTrailService.instance.log(
                      action: AuditAction.create,
                      entityType: AuditEntityType.expense,
                      entityId: result['data']?['Id']?.toString() ?? '',
                      entityDescription: 'مصروف: ${descCtrl.text}',
                    );
                    _loadData();
                  } else {
                    _snack(result['message'] ?? 'خطأ', SdColors.danger);
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
      style: const TextStyle(color: SdColors.ink),
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: SdColors.faint),
        filled: true,
        fillColor: SdColors.surfaceAlt,
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
          backgroundColor: SdColors.surface,
          title: Text('تعديل مصروف',
              style: TextStyle(color: SdColors.ink)),
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
                  style: TextStyle(color: SdColors.faint)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: SdColors.info,
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
                  _snack('تم تحديث المصروف', SdColors.success);
                  AuditTrailService.instance.log(
                    action: AuditAction.edit,
                    entityType: AuditEntityType.expense,
                    entityId: e['Id']?.toString() ?? '',
                    entityDescription: 'مصروف: ${descCtrl.text}',
                  );
                  _loadData();
                } else {
                  _snack(result['message'] ?? 'خطأ', SdColors.danger);
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
          backgroundColor: SdColors.surface,
          title: Text('تأكيد الحذف',
              style: TextStyle(color: SdColors.danger)),
          content: Text(
            'هل تريد حذف المصروف "${e['Description']}" بمبلغ ${_fmt(e['Amount'])} د.ع؟\nسيتم إلغاء القيد المحاسبي المرتبط أيضاً.',
            style: const TextStyle(color: SdColors.ink),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('إلغاء',
                  style: TextStyle(color: SdColors.faint)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: SdColors.danger,
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
                  _snack('تم حذف المصروف', SdColors.success);
                  AuditTrailService.instance.log(
                    action: AuditAction.delete,
                    entityType: AuditEntityType.expense,
                    entityId: e['Id']?.toString() ?? '',
                    entityDescription: 'مصروف: ${e['Description'] ?? ''}',
                  );
                  _loadData();
                } else {
                  _snack(result['message'] ?? 'خطأ', SdColors.danger);
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
      final d = DateTime.parse(date.toString()).toLocal();
      return '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';
    } catch (_) {
      return '';
    }
  }
}
