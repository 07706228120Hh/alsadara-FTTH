import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/accounting_service.dart';
import '../../services/vps_auth_service.dart';
import '../../theme/accounting_theme.dart';
import '../../theme/accounting_responsive.dart';
import '../../permissions/permissions.dart';

/// صفحة التعديلات اليدوية — خصومات / مكافآت / بدلات
class EmployeeAdjustmentsPage extends StatefulWidget {
  final String? companyId;

  const EmployeeAdjustmentsPage({super.key, this.companyId});

  @override
  State<EmployeeAdjustmentsPage> createState() =>
      _EmployeeAdjustmentsPageState();
}

class _EmployeeAdjustmentsPageState extends State<EmployeeAdjustmentsPage> {
  bool _isLoading = true;
  String? _errorMessage;
  List<dynamic> _adjustments = [];
  Map<String, dynamic> _summary = {};
  int _selectedMonth = DateTime.now().month;
  int _selectedYear = DateTime.now().year;
  int? _filterType; // null = الكل, 0 = خصم, 1 = مكافأة, 2 = بدل

  // قائمة الموظفين للاختيار عند الإضافة
  List<Map<String, dynamic>> _employees = [];

  final _months = [
    'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
    'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر',
  ];

  final _typeLabels = {0: 'خصم', 1: 'مكافأة', 2: 'بدل'};
  final _typeColors = {
    0: AccountingTheme.danger,
    1: AccountingTheme.success,
    2: const Color(0xFF2196F3),
  };
  final _typeIcons = {
    0: Icons.remove_circle_outline,
    1: Icons.card_giftcard,
    2: Icons.account_balance_wallet,
  };

  @override
  void initState() {
    super.initState();
    _loadData();
    _loadEmployees();
  }

  Future<void> _loadEmployees() async {
    if (widget.companyId == null) return;
    try {
      final emps = await AccountingService.instance
          .getCompanyEmployees(widget.companyId!);
      if (mounted) setState(() => _employees = emps);
    } catch (_) {}
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final result = await AccountingService.instance.getEmployeeAdjustments(
        companyId: widget.companyId,
        month: _selectedMonth,
        year: _selectedYear,
        type: _filterType,
      );
      if (result['success'] == true) {
        _adjustments = (result['data'] is List) ? result['data'] : [];
        _summary = (result['summary'] is Map)
            ? Map<String, dynamic>.from(result['summary'] as Map)
            : {};
      } else {
        _errorMessage = result['message'] ?? 'خطأ';
      }
    } catch (e) {
      _errorMessage = 'خطأ في جلب البيانات';
    }
    setState(() => _isLoading = false);
  }

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
              _buildSummaryBar(),
              _buildTypeFilter(),
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
                        : _adjustments.isEmpty
                            ? _buildEmpty()
                            : _buildList(isMobile),
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
            child: Icon(Icons.tune_rounded,
                color: Colors.white, size: isMobile ? 16 : context.accR.iconM),
          ),
          SizedBox(width: isMobile ? 6 : context.accR.spaceM),
          Expanded(
            child: Text('الخصومات والمكافآت',
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
          if (PermissionManager.instance.canAdd('accounting.salaries')) ...[
            SizedBox(width: context.accR.spaceS),
            isMobile
                ? SizedBox(
                    height: 28,
                    child: ElevatedButton(
                      onPressed: () => _showAddDialog(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AccountingTheme.neonGreen,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: const Size(28, 28),
                      ),
                      child: const Icon(Icons.add, size: 16),
                    ),
                  )
                : ElevatedButton.icon(
                    onPressed: () => _showAddDialog(),
                    icon: Icon(Icons.add, size: context.accR.iconM),
                    label: const Text('إضافة'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AccountingTheme.neonGreen,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(
                          horizontal: context.accR.paddingH,
                          vertical: context.accR.spaceM),
                    ),
                  ),
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
    final totalDeductions =
        ((_summary['TotalDeductions'] ?? 0) as num).toDouble();
    final totalBonuses = ((_summary['TotalBonuses'] ?? 0) as num).toDouble();
    final totalAllowances =
        ((_summary['TotalAllowances'] ?? 0) as num).toDouble();
    final count = (_summary['Count'] ?? _adjustments.length) as num;

    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: context.accR.paddingH, vertical: context.accR.spaceS),
      child: Row(
        children: [
          Expanded(
              child: _summaryChip(
                  'خصومات', _fmt(totalDeductions), AccountingTheme.danger)),
          SizedBox(width: context.accR.spaceS),
          Expanded(
              child: _summaryChip(
                  'مكافآت', _fmt(totalBonuses), AccountingTheme.success)),
          SizedBox(width: context.accR.spaceS),
          Expanded(
              child: _summaryChip(
                  'بدلات', _fmt(totalAllowances), const Color(0xFF2196F3))),
          SizedBox(width: context.accR.spaceS),
          Expanded(
              child:
                  _summaryChip('العدد', '$count', AccountingTheme.textPrimary)),
        ],
      ),
    );
  }

  Widget _summaryChip(String label, String value, Color color) {
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

  Widget _buildTypeFilter() {
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: context.accR.paddingH, vertical: 4),
      child: Row(
        children: [
          _filterChip('الكل', null),
          const SizedBox(width: 6),
          _filterChip('خصومات', 0),
          const SizedBox(width: 6),
          _filterChip('مكافآت', 1),
          const SizedBox(width: 6),
          _filterChip('بدلات', 2),
        ],
      ),
    );
  }

  Widget _filterChip(String label, int? type) {
    final selected = _filterType == type;
    return GestureDetector(
      onTap: () {
        setState(() => _filterType = type);
        _loadData();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: selected
              ? AccountingTheme.neonGreen.withValues(alpha: 0.2)
              : AccountingTheme.bgCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: selected
                  ? AccountingTheme.neonGreen
                  : AccountingTheme.borderColor),
        ),
        child: Text(label,
            style: TextStyle(
                color: selected
                    ? AccountingTheme.neonGreen
                    : AccountingTheme.textSecondary,
                fontSize: context.accR.small,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal)),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.tune_outlined,
              color: AccountingTheme.textMuted, size: context.accR.iconEmpty),
          SizedBox(height: context.accR.spaceXL),
          const Text('لا توجد تعديلات لهذا الشهر',
              style: TextStyle(color: AccountingTheme.textMuted)),
          SizedBox(height: context.accR.spaceM),
          ElevatedButton.icon(
            onPressed: () => _showAddDialog(),
            icon: const Icon(Icons.add),
            label: const Text('إضافة تعديل'),
            style: ElevatedButton.styleFrom(
                backgroundColor: AccountingTheme.neonGreen,
                foregroundColor: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildList(bool isMobile) {
    return ListView.builder(
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 8 : 16, vertical: 4),
      itemCount: _adjustments.length,
      itemBuilder: (_, i) => _buildAdjustmentTile(_adjustments[i]),
    );
  }

  Widget _buildAdjustmentTile(dynamic adj) {
    final typeVal = (adj['TypeValue'] ?? 0) as int;
    final color = _typeColors[typeVal] ?? AccountingTheme.textMuted;
    final icon = _typeIcons[typeVal] ?? Icons.help;
    final label = _typeLabels[typeVal] ?? '';
    final isApplied = adj['IsApplied'] == true;
    final isRecurring = adj['IsRecurring'] == true;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: AccountingTheme.bgCard,
        borderRadius: BorderRadius.circular(context.accR.cardRadius),
        border: Border.all(
            color: isApplied
                ? color.withValues(alpha: 0.3)
                : AccountingTheme.borderColor),
      ),
      child: ListTile(
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                adj['UserName'] ?? '',
                style: TextStyle(
                    color: AccountingTheme.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: context.accR.body),
              ),
            ),
            Text('${_fmt(adj['Amount'])} د.ع',
                style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
                    fontSize: context.accR.body)),
          ],
        ),
        subtitle: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(label,
                  style: TextStyle(
                      color: color,
                      fontSize: context.accR.caption,
                      fontWeight: FontWeight.bold)),
            ),
            if (adj['Category'] != null &&
                (adj['Category'] as String).isNotEmpty) ...[
              const SizedBox(width: 6),
              Text(adj['Category'],
                  style: TextStyle(
                      color: AccountingTheme.textMuted,
                      fontSize: context.accR.caption)),
            ],
            if (isRecurring) ...[
              const SizedBox(width: 6),
              Icon(Icons.repeat, size: 12, color: AccountingTheme.info),
              const SizedBox(width: 2),
              Text('متكرر',
                  style: TextStyle(
                      color: AccountingTheme.info,
                      fontSize: context.accR.caption)),
            ],
            if (isApplied) ...[
              const SizedBox(width: 6),
              Icon(Icons.check_circle, size: 12, color: AccountingTheme.success),
              const SizedBox(width: 2),
              Text('مُطبّق',
                  style: TextStyle(
                      color: AccountingTheme.success,
                      fontSize: context.accR.caption)),
            ],
          ],
        ),
        trailing: isApplied
            ? null
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (PermissionManager.instance
                      .canEdit('accounting.salaries'))
                    InkWell(
                      onTap: () => _showEditDialog(adj),
                      borderRadius: BorderRadius.circular(4),
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(Icons.edit,
                            size: 18, color: AccountingTheme.info),
                      ),
                    ),
                  if (PermissionManager.instance
                      .canDelete('accounting.salaries'))
                    InkWell(
                      onTap: () => _confirmDelete(adj),
                      borderRadius: BorderRadius.circular(4),
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(Icons.delete_outline,
                            size: 18, color: AccountingTheme.danger),
                      ),
                    ),
                ],
              ),
        dense: true,
      ),
    );
  }

  void _showAddDialog() {
    if (_employees.isEmpty) {
      _snack('لا يوجد موظفون — جاري التحميل', AccountingTheme.warning);
      _loadEmployees();
      return;
    }

    String? selectedUserId;
    int selectedType = 0;
    final amountCtrl = TextEditingController();
    final categoryCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    bool isRecurring = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setDialogState) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            backgroundColor: AccountingTheme.bgCard,
            title: const Text('إضافة تعديل جديد',
                style: TextStyle(color: AccountingTheme.textPrimary)),
            content: SizedBox(
              width: context.accR.isMobile
                  ? MediaQuery.of(context).size.width * 0.9
                  : 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // اختيار الموظف
                    DropdownButtonFormField<String>(
                      value: selectedUserId,
                      dropdownColor: AccountingTheme.bgCard,
                      style: const TextStyle(
                          color: AccountingTheme.textPrimary),
                      decoration: _inputDecor('الموظف'),
                      items: _employees.map((e) {
                        return DropdownMenuItem<String>(
                          value: e['Id']?.toString(),
                          child: Text(e['FullName'] ?? e['UserName'] ?? ''),
                        );
                      }).toList(),
                      onChanged: (v) =>
                          setDialogState(() => selectedUserId = v),
                    ),
                    const SizedBox(height: 12),
                    // نوع التعديل
                    const Text('النوع',
                        style: TextStyle(
                            color: AccountingTheme.textMuted, fontSize: 13)),
                    const SizedBox(height: 4),
                    Row(
                      children: [0, 1, 2].map((t) {
                        final sel = selectedType == t;
                        final c =
                            _typeColors[t] ?? AccountingTheme.textMuted;
                        return Expanded(
                          child: GestureDetector(
                            onTap: () =>
                                setDialogState(() => selectedType = t),
                            child: Container(
                              margin: const EdgeInsets.symmetric(
                                  horizontal: 3),
                              padding: const EdgeInsets.symmetric(
                                  vertical: 8),
                              decoration: BoxDecoration(
                                color: sel
                                    ? c.withValues(alpha: 0.2)
                                    : AccountingTheme.bgCardHover,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                    color: sel
                                        ? c
                                        : AccountingTheme.borderColor),
                              ),
                              child: Center(
                                child: Text(_typeLabels[t]!,
                                    style: TextStyle(
                                        color: sel
                                            ? c
                                            : AccountingTheme.textSecondary,
                                        fontWeight: sel
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                        fontSize: 13)),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 12),
                    _field('المبلغ', amountCtrl, isNum: true),
                    const SizedBox(height: 10),
                    _field('التصنيف (اختياري)', categoryCtrl,
                        hint: 'سلفة، غرامة، مكافأة أداء...'),
                    const SizedBox(height: 10),
                    _field('الوصف (اختياري)', descCtrl),
                    const SizedBox(height: 10),
                    _field('ملاحظات (اختياري)', notesCtrl),
                    const SizedBox(height: 8),
                    CheckboxListTile(
                      value: isRecurring,
                      activeColor: AccountingTheme.neonGreen,
                      onChanged: (v) =>
                          setDialogState(() => isRecurring = v ?? false),
                      title: const Text('تكرار شهري',
                          style:
                              TextStyle(color: AccountingTheme.textPrimary)),
                      subtitle: const Text('يُطبق تلقائياً كل شهر',
                          style: TextStyle(
                              color: AccountingTheme.textMuted, fontSize: 12)),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ],
                ),
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
                    backgroundColor: AccountingTheme.neonGreen,
                    foregroundColor: Colors.white),
                onPressed: () async {
                  if (selectedUserId == null) {
                    _snack('اختر الموظف', AccountingTheme.warning);
                    return;
                  }
                  final amount = double.tryParse(amountCtrl.text);
                  if (amount == null || amount <= 0) {
                    _snack('أدخل مبلغ صحيح', AccountingTheme.warning);
                    return;
                  }
                  Navigator.pop(ctx);
                  setState(() => _isLoading = true);
                  try {
                    final result = await AccountingService.instance
                        .createEmployeeAdjustment(
                      userId: selectedUserId!,
                      companyId: widget.companyId ?? '',
                      type: selectedType,
                      category: categoryCtrl.text.isEmpty
                          ? null
                          : categoryCtrl.text,
                      amount: amount,
                      month: _selectedMonth,
                      year: _selectedYear,
                      description: descCtrl.text.isEmpty
                          ? null
                          : descCtrl.text,
                      notes:
                          notesCtrl.text.isEmpty ? null : notesCtrl.text,
                      createdById: VpsAuthService.instance.currentUser?.id ?? '',
                      isRecurring: isRecurring,
                    );
                    if (result['success'] == true) {
                      _snack(
                          result['message'] ?? 'تمت الإضافة',
                          AccountingTheme.success);
                      _loadData();
                    } else {
                      _snack(result['message'] ?? 'خطأ',
                          AccountingTheme.danger);
                      setState(() => _isLoading = false);
                    }
                  } catch (e) {
                    _snack('خطأ', AccountingTheme.danger);
                    setState(() => _isLoading = false);
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

  void _showEditDialog(dynamic adj) {
    final amountCtrl =
        TextEditingController(text: '${adj['Amount'] ?? 0}');
    final categoryCtrl =
        TextEditingController(text: adj['Category'] ?? '');
    final descCtrl =
        TextEditingController(text: adj['Description'] ?? '');
    final notesCtrl =
        TextEditingController(text: adj['Notes'] ?? '');
    int selectedType = (adj['TypeValue'] ?? 0) as int;
    bool isRecurring = adj['IsRecurring'] == true;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setDialogState) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            backgroundColor: AccountingTheme.bgCard,
            title: Text(
                'تعديل: ${adj['UserName'] ?? ''}',
                style: const TextStyle(color: AccountingTheme.textPrimary)),
            content: SizedBox(
              width: context.accR.isMobile
                  ? MediaQuery.of(context).size.width * 0.85
                  : 380,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('النوع',
                        style: TextStyle(
                            color: AccountingTheme.textMuted, fontSize: 13)),
                    const SizedBox(height: 4),
                    Row(
                      children: [0, 1, 2].map((t) {
                        final sel = selectedType == t;
                        final c =
                            _typeColors[t] ?? AccountingTheme.textMuted;
                        return Expanded(
                          child: GestureDetector(
                            onTap: () =>
                                setDialogState(() => selectedType = t),
                            child: Container(
                              margin: const EdgeInsets.symmetric(
                                  horizontal: 3),
                              padding: const EdgeInsets.symmetric(
                                  vertical: 8),
                              decoration: BoxDecoration(
                                color: sel
                                    ? c.withValues(alpha: 0.2)
                                    : AccountingTheme.bgCardHover,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                    color: sel
                                        ? c
                                        : AccountingTheme.borderColor),
                              ),
                              child: Center(
                                child: Text(_typeLabels[t]!,
                                    style: TextStyle(
                                        color: sel
                                            ? c
                                            : AccountingTheme.textSecondary,
                                        fontWeight: sel
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                        fontSize: 13)),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 12),
                    _field('المبلغ', amountCtrl, isNum: true),
                    const SizedBox(height: 10),
                    _field('التصنيف', categoryCtrl),
                    const SizedBox(height: 10),
                    _field('الوصف', descCtrl),
                    const SizedBox(height: 10),
                    _field('ملاحظات', notesCtrl),
                    const SizedBox(height: 8),
                    CheckboxListTile(
                      value: isRecurring,
                      activeColor: AccountingTheme.neonGreen,
                      onChanged: (v) =>
                          setDialogState(() => isRecurring = v ?? false),
                      title: const Text('تكرار شهري',
                          style:
                              TextStyle(color: AccountingTheme.textPrimary)),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ],
                ),
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
                    backgroundColor: AccountingTheme.neonGreen,
                    foregroundColor: Colors.white),
                onPressed: () async {
                  Navigator.pop(ctx);
                  setState(() => _isLoading = true);
                  try {
                    final result = await AccountingService.instance
                        .updateEmployeeAdjustment(
                      adj['Id'],
                      type: selectedType,
                      category: categoryCtrl.text,
                      amount: double.tryParse(amountCtrl.text),
                      description: descCtrl.text,
                      notes: notesCtrl.text,
                      isRecurring: isRecurring,
                    );
                    if (result['success'] == true) {
                      _snack('تم التحديث', AccountingTheme.success);
                      _loadData();
                    } else {
                      _snack(result['message'] ?? 'خطأ',
                          AccountingTheme.danger);
                      setState(() => _isLoading = false);
                    }
                  } catch (e) {
                    _snack('خطأ', AccountingTheme.danger);
                    setState(() => _isLoading = false);
                  }
                },
                child: const Text('تحديث'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmDelete(dynamic adj) {
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: AccountingTheme.bgCard,
          title: const Text('تأكيد الحذف',
              style: TextStyle(color: AccountingTheme.danger)),
          content: Text(
            'حذف ${_typeLabels[adj['TypeValue'] ?? 0]} بمبلغ ${_fmt(adj['Amount'])} للموظف ${adj['UserName']}؟',
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
                setState(() => _isLoading = true);
                final result = await AccountingService.instance
                    .deleteEmployeeAdjustment(adj['Id']);
                if (result['success'] == true) {
                  _snack('تم الحذف', AccountingTheme.success);
                  _loadData();
                } else {
                  _snack(result['message'] ?? 'خطأ', AccountingTheme.danger);
                  setState(() => _isLoading = false);
                }
              },
              child: const Text('حذف'),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDecor(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: AccountingTheme.textMuted),
      filled: true,
      fillColor: AccountingTheme.bgCardHover,
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    );
  }

  Widget _field(String label, TextEditingController ctrl,
      {bool isNum = false, String? hint}) {
    return TextField(
      controller: ctrl,
      style: const TextStyle(color: AccountingTheme.textPrimary),
      keyboardType: isNum ? TextInputType.number : TextInputType.text,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        hintStyle:
            const TextStyle(color: AccountingTheme.textMuted, fontSize: 12),
        labelStyle: const TextStyle(color: AccountingTheme.textMuted),
        filled: true,
        fillColor: AccountingTheme.bgCardHover,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide.none),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
