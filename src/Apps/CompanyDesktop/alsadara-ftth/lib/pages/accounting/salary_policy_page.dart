import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
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
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AccountingTheme.bgPrimary,
        body: SafeArea(
          child: Column(
            children: [
              _buildToolbar(isMobile),
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
                        : _policies.isEmpty
                            ? _buildEmpty()
                            : _buildPoliciesList(isMobile),
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
            child: Icon(Icons.policy_rounded,
                color: Colors.white, size: isMobile ? 16 : context.accR.iconM),
          ),
          SizedBox(width: isMobile ? 6 : context.accR.spaceM),
          Expanded(
            child: Text('سياسات الرواتب',
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
                      onPressed: () => _showPolicyDialog(null),
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
                    onPressed: () => _showPolicyDialog(null),
                    icon: Icon(Icons.add, size: context.accR.iconM),
                    label: const Text('سياسة جديدة'),
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

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.policy_outlined,
              color: AccountingTheme.textMuted, size: context.accR.iconEmpty),
          SizedBox(height: context.accR.spaceXL),
          const Text('لا توجد سياسات رواتب',
              style: TextStyle(color: AccountingTheme.textMuted)),
          SizedBox(height: context.accR.spaceM),
          ElevatedButton.icon(
            onPressed: () => _showPolicyDialog(null),
            icon: const Icon(Icons.add),
            label: const Text('إنشاء سياسة'),
            style: ElevatedButton.styleFrom(
                backgroundColor: AccountingTheme.neonGreen,
                foregroundColor: Colors.white),
          ),
        ],
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
        color: AccountingTheme.bgCard,
        borderRadius: BorderRadius.circular(context.accR.cardRadius),
        border: Border.all(
          color: isDefault
              ? AccountingTheme.neonGreen.withValues(alpha: 0.5)
              : AccountingTheme.borderColor,
        ),
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
                  ? AccountingTheme.neonGreen.withValues(alpha: 0.1)
                  : AccountingTheme.bgCardHover,
              borderRadius: BorderRadius.vertical(
                  top: Radius.circular(context.accR.cardRadius)),
            ),
            child: Row(
              children: [
                Icon(Icons.policy,
                    color: isDefault
                        ? AccountingTheme.neonGreen
                        : AccountingTheme.textSecondary,
                    size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(name,
                      style: TextStyle(
                          color: AccountingTheme.textPrimary,
                          fontWeight: FontWeight.bold,
                          fontSize: context.accR.body)),
                ),
                if (isDefault)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AccountingTheme.neonGreen.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text('افتراضية',
                        style: TextStyle(
                            color: AccountingTheme.neonGreen,
                            fontSize: context.accR.caption,
                            fontWeight: FontWeight.bold)),
                  ),
                const SizedBox(width: 8),
                if (PermissionManager.instance
                    .canEdit('accounting.salaries'))
                  InkWell(
                    onTap: () => _showPolicyDialog(policy),
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
                    onTap: () => _confirmDelete(policy),
                    borderRadius: BorderRadius.circular(4),
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(Icons.delete_outline,
                          size: 18, color: AccountingTheme.danger),
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
        color: AccountingTheme.bgPrimary,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AccountingTheme.borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AccountingTheme.textMuted),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  color: AccountingTheme.textMuted,
                  fontSize: context.accR.caption)),
          const SizedBox(width: 6),
          Text(value,
              style: TextStyle(
                  color: AccountingTheme.textPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: context.accR.small)),
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
