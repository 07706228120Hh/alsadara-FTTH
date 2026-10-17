import 'package:flutter/material.dart';
import '../../frontend/frontend.dart'; // نظام تصميم الصدارة الموحّد (sd)
import '../../services/accounting_service.dart';
import '../../theme/accounting_theme.dart';
import '../../theme/accounting_responsive.dart';
import '../../permissions/permissions.dart';

/// صفحة إدارة سياسات الرواتب
class SalaryPolicyPage extends StatefulWidget {
  final String? companyId;

  const SalaryPolicyPage({super.key, this.companyId});

  @override
  State<SalaryPolicyPage> createState() => _SalaryPolicyPageState();
}

class _SalaryPolicyPageState extends State<SalaryPolicyPage> {
  bool _isLoading = true;
  String? _errorMessage;
  List<dynamic> _policies = [];

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
          .getSalaryPolicies(companyId: widget.companyId);
      if (result['success'] == true) {
        _policies = (result['data'] is List) ? result['data'] : [];
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
    return SdTheme.scope(
      child: Scaffold(
        backgroundColor: SdColors.ground,
        appBar: SdAppBar(
          title: 'سياسات الرواتب',
          actions: [
            SdAppBarAction(
              icon: Icons.refresh,
              label: 'تحديث',
              onPressed: _loadData,
            ),
            if (PermissionManager.instance.canAdd('accounting.salaries'))
              SdAppBarAction(
                icon: Icons.add,
                label: 'سياسة جديدة',
                onPressed: () => _showPolicyDialog(null),
              ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _errorMessage != null
                  ? Center(
                      child: Text(_errorMessage!,
                          style: const TextStyle(
                              color: SdColors.danger)))
                  : _policies.isEmpty
                      ? _buildEmpty()
                      : _buildPoliciesList(isMobile),
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return SingleChildScrollView(
      child: SdEmptyState(
        title: 'لا توجد سياسات رواتب',
        icon: Icons.policy_outlined,
        action: PermissionManager.instance.canAdd('accounting.salaries')
            ? SdButton(
                label: 'إنشاء سياسة',
                icon: Icons.add,
                onPressed: () => _showPolicyDialog(null),
              )
            : null,
      ),
    );
  }

  Widget _buildPoliciesList(bool isMobile) {
    return ListView.builder(
      padding: EdgeInsets.all(isMobile ? 8 : context.accR.paddingH),
      itemCount: _policies.length,
      itemBuilder: (_, i) => _buildPolicyCard(_policies[i], isMobile),
    );
  }

  Widget _buildPolicyCard(dynamic policy, bool isMobile) {
    final isDefault = policy['IsDefault'] == true;
    final name = policy['Name'] ?? 'سياسة';

    return Container(
      margin: EdgeInsets.only(bottom: context.accR.spaceM),
      decoration: BoxDecoration(
        color: SdColors.surface,
        borderRadius: BorderRadius.circular(SdRadius.md),
        boxShadow: SdDepth.raised(depth: SdDepth.small),
        border: isDefault
            ? Border.all(color: SdStatus.success.tone.tintEdge)
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: EdgeInsets.symmetric(
                horizontal: context.accR.paddingH,
                vertical: context.accR.spaceM),
            decoration: BoxDecoration(
              color: isDefault
                  ? SdStatus.success.tone.tint
                  : SdColors.surfaceAlt,
              borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(SdRadius.md)),
            ),
            child: Row(
              children: [
                Icon(Icons.policy,
                    color: isDefault
                        ? SdStatus.success.tone.base
                        : SdColors.muted,
                    size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(name, style: SdText.label),
                ),
                if (isDefault)
                  const SdStatusChip('افتراضية', status: SdStatus.success),
                const SizedBox(width: 8),
                if (PermissionManager.instance
                    .canEdit('accounting.salaries'))
                  InkWell(
                    onTap: () => _showPolicyDialog(policy),
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(Icons.edit,
                          size: 18, color: SdStatus.info.tone.base),
                    ),
                  ),
                if (PermissionManager.instance
                    .canDelete('accounting.salaries'))
                  InkWell(
                    onTap: () => _confirmDelete(policy),
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(Icons.delete_outline,
                          size: 18, color: SdStatus.danger.tone.base),
                    ),
                  ),
              ],
            ),
          ),
          // Body - settings grid
          Padding(
            padding: EdgeInsets.all(context.accR.paddingH),
            child: Wrap(
              spacing: isMobile ? 8 : 16,
              runSpacing: isMobile ? 6 : 12,
              children: [
                _settingChip('خصم التأخير/دقيقة',
                    '${policy['DeductionPerLateMinute'] ?? 0}', Icons.timer),
                _settingChip(
                    'سقف خصم التأخير %',
                    '${policy['MaxLateDeductionPercent'] ?? 0}%',
                    Icons.vertical_align_top),
                _settingChip('مضاعف الغياب',
                    '${policy['AbsentDayMultiplier'] ?? 0}x', Icons.event_busy),
                _settingChip(
                    'خصم المغادرة المبكرة/دقيقة',
                    '${policy['DeductionPerEarlyDepartureMinute'] ?? 0}',
                    Icons.exit_to_app),
                _settingChip(
                    'مضاعف الإضافي',
                    '${policy['OvertimeHourlyMultiplier'] ?? 1.5}x',
                    Icons.more_time),
                _settingChip(
                    'سقف ساعات إضافية/شهر',
                    '${policy['MaxOvertimeHoursPerMonth'] ?? 0}',
                    Icons.hourglass_top),
                _settingChip(
                    'مضاعف إجازة غير مدفوعة',
                    '${policy['UnpaidLeaveDayMultiplier'] ?? 0}x',
                    Icons.beach_access),
                _settingChip('أيام العمل/شهر',
                    '${policy['WorkDaysPerMonth'] ?? 26}', Icons.calendar_month),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _settingChip(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: SdColors.groundAlt,
        borderRadius: BorderRadius.circular(SdRadius.xs),
        border: Border.all(color: SdColors.edge),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: SdColors.faint),
          const SizedBox(width: 4),
          Text(label,
              style: SdText.caption),
          const SizedBox(width: 6),
          Text(value,
              style: const TextStyle(
                  fontFamily: SdText.family,
                  color: SdColors.ink,
                  fontWeight: FontWeight.w900,
                  fontSize: 12.5)),
        ],
      ),
    );
  }

  void _showPolicyDialog(dynamic existing) {
    final isEdit = existing != null;
    final nameCtrl =
        TextEditingController(text: existing?['Name'] ?? 'سياسة افتراضية');
    final lateMinCtrl = TextEditingController(
        text: '${existing?['DeductionPerLateMinute'] ?? 0}');
    final maxLateCtrl = TextEditingController(
        text: '${existing?['MaxLateDeductionPercent'] ?? 10}');
    final absentCtrl = TextEditingController(
        text: '${existing?['AbsentDayMultiplier'] ?? 1}');
    final earlyCtrl = TextEditingController(
        text: '${existing?['DeductionPerEarlyDepartureMinute'] ?? 0}');
    final overtimeCtrl = TextEditingController(
        text: '${existing?['OvertimeHourlyMultiplier'] ?? 1.5}');
    final maxOtCtrl = TextEditingController(
        text: '${existing?['MaxOvertimeHoursPerMonth'] ?? 40}');
    final unpaidCtrl = TextEditingController(
        text: '${existing?['UnpaidLeaveDayMultiplier'] ?? 1}');
    final workDaysCtrl = TextEditingController(
        text: '${existing?['WorkDaysPerMonth'] ?? 26}');
    bool isDefault = existing?['IsDefault'] ?? false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setDialogState) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            backgroundColor: AccountingTheme.bgCard,
            title: Text(isEdit ? 'تعديل السياسة' : 'إنشاء سياسة جديدة',
                style: const TextStyle(color: AccountingTheme.textPrimary)),
            content: SizedBox(
              width: context.accR.isMobile
                  ? MediaQuery.of(context).size.width * 0.9
                  : 450,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _field('اسم السياسة', nameCtrl),
                    const SizedBox(height: 12),
                    CheckboxListTile(
                      value: isDefault,
                      activeColor: AccountingTheme.neonGreen,
                      onChanged: (v) =>
                          setDialogState(() => isDefault = v ?? false),
                      title: const Text('سياسة افتراضية',
                          style:
                              TextStyle(color: AccountingTheme.textPrimary)),
                      subtitle: const Text('تُطبق تلقائياً عند توليد الرواتب',
                          style: TextStyle(
                              color: AccountingTheme.textMuted, fontSize: 12)),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                    const Divider(color: AccountingTheme.borderColor),
                    const SizedBox(height: 8),
                    _field('خصم لكل دقيقة تأخير', lateMinCtrl, isNum: true),
                    const SizedBox(height: 10),
                    _field('سقف خصم التأخير (%)', maxLateCtrl, isNum: true),
                    const SizedBox(height: 10),
                    _field('مضاعف يوم الغياب', absentCtrl, isNum: true),
                    const SizedBox(height: 10),
                    _field('خصم لكل دقيقة مغادرة مبكرة', earlyCtrl,
                        isNum: true),
                    const SizedBox(height: 10),
                    _field('مضاعف الساعة الإضافية', overtimeCtrl, isNum: true),
                    const SizedBox(height: 10),
                    _field('سقف ساعات إضافية/شهر', maxOtCtrl, isNum: true),
                    const SizedBox(height: 10),
                    _field('مضاعف إجازة غير مدفوعة', unpaidCtrl, isNum: true),
                    const SizedBox(height: 10),
                    _field('أيام العمل بالشهر', workDaysCtrl, isNum: true),
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
                  await _savePolicy(
                    id: existing?['Id'],
                    name: nameCtrl.text,
                    isDefault: isDefault,
                    deductionPerLateMinute:
                        double.tryParse(lateMinCtrl.text) ?? 0,
                    maxLateDeductionPercent:
                        double.tryParse(maxLateCtrl.text) ?? 10,
                    absentDayMultiplier:
                        double.tryParse(absentCtrl.text) ?? 1,
                    deductionPerEarlyDepartureMinute:
                        double.tryParse(earlyCtrl.text) ?? 0,
                    overtimeHourlyMultiplier:
                        double.tryParse(overtimeCtrl.text) ?? 1.5,
                    maxOvertimeHoursPerMonth:
                        int.tryParse(maxOtCtrl.text) ?? 40,
                    unpaidLeaveDayMultiplier:
                        double.tryParse(unpaidCtrl.text) ?? 1,
                    workDaysPerMonth:
                        int.tryParse(workDaysCtrl.text) ?? 26,
                  );
                },
                child: Text(isEdit ? 'تحديث' : 'إنشاء'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _savePolicy({
    dynamic id,
    required String name,
    required bool isDefault,
    required double deductionPerLateMinute,
    required double maxLateDeductionPercent,
    required double absentDayMultiplier,
    required double deductionPerEarlyDepartureMinute,
    required double overtimeHourlyMultiplier,
    required int maxOvertimeHoursPerMonth,
    required double unpaidLeaveDayMultiplier,
    required int workDaysPerMonth,
  }) async {
    setState(() => _isLoading = true);
    try {
      final svc = AccountingService.instance;
      final Map<String, dynamic> result;
      if (id != null) {
        result = await svc.updateSalaryPolicy(id,
            companyId: widget.companyId ?? '',
            name: name,
            isDefault: isDefault,
            deductionPerLateMinute: deductionPerLateMinute,
            maxLateDeductionPercent: maxLateDeductionPercent,
            absentDayMultiplier: absentDayMultiplier,
            deductionPerEarlyDepartureMinute: deductionPerEarlyDepartureMinute,
            overtimeHourlyMultiplier: overtimeHourlyMultiplier,
            maxOvertimeHoursPerMonth: maxOvertimeHoursPerMonth,
            unpaidLeaveDayMultiplier: unpaidLeaveDayMultiplier,
            workDaysPerMonth: workDaysPerMonth);
      } else {
        result = await svc.createSalaryPolicy(
            companyId: widget.companyId ?? '',
            name: name,
            isDefault: isDefault,
            deductionPerLateMinute: deductionPerLateMinute,
            maxLateDeductionPercent: maxLateDeductionPercent,
            absentDayMultiplier: absentDayMultiplier,
            deductionPerEarlyDepartureMinute: deductionPerEarlyDepartureMinute,
            overtimeHourlyMultiplier: overtimeHourlyMultiplier,
            maxOvertimeHoursPerMonth: maxOvertimeHoursPerMonth,
            unpaidLeaveDayMultiplier: unpaidLeaveDayMultiplier,
            workDaysPerMonth: workDaysPerMonth);
      }
      if (result['success'] == true) {
        _snack(result['message'] ?? 'تم الحفظ', AccountingTheme.success);
        _loadData();
      } else {
        _snack(result['message'] ?? 'خطأ', AccountingTheme.danger);
        setState(() => _isLoading = false);
      }
    } catch (e) {
      _snack('خطأ', AccountingTheme.danger);
      setState(() => _isLoading = false);
    }
  }

  void _confirmDelete(dynamic policy) {
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: AccountingTheme.bgCard,
          title: const Text('تأكيد الحذف',
              style: TextStyle(color: AccountingTheme.danger)),
          content: Text('هل تريد حذف سياسة "${policy['Name']}"؟',
              style: const TextStyle(color: AccountingTheme.textPrimary)),
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
                    .deleteSalaryPolicy(policy['Id']);
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

  Widget _field(String label, TextEditingController ctrl,
      {bool isNum = false}) {
    return TextField(
      controller: ctrl,
      style: const TextStyle(color: AccountingTheme.textPrimary),
      keyboardType: isNum ? TextInputType.number : TextInputType.text,
      decoration: InputDecoration(
        labelText: label,
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
}
