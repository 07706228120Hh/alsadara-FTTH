/// تبويب بيانات HR — المعلومات الشخصية والوظيفية
/// مقسّم إلى بطاقات: الحساب، الوظيفة، الشخصية، المالية، الطوارئ، FTTH، ملاحظات
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../services/employee_profile_service.dart';

class HrInfoTab extends StatefulWidget {
  final Map<String, dynamic> employee;
  final String companyId;
  final bool canEdit;
  final VoidCallback onSaved;

  const HrInfoTab({
    super.key,
    required this.employee,
    required this.companyId,
    required this.canEdit,
    required this.onSaved,
  });

  @override
  State<HrInfoTab> createState() => _HrInfoTabState();
}

class _HrInfoTabState extends State<HrInfoTab> {
  bool _editing = false;
  bool _saving = false;
  bool _showPassword = false;
  bool _showFtthPassword = false;

  // Controllers
  late TextEditingController _fullNameCtrl;
  late TextEditingController _phoneCtrl;
  late TextEditingController _deptCtrl;
  late TextEditingController _empCodeCtrl;
  late TextEditingController _centerCtrl;
  late TextEditingController _salaryCtrl;
  late TextEditingController _nationalIdCtrl;
  late TextEditingController _bankAccCtrl;
  late TextEditingController _bankNameCtrl;
  late TextEditingController _emergNameCtrl;
  late TextEditingController _emergPhoneCtrl;
  late TextEditingController _hrNotesCtrl;

  String? _contractType;
  DateTime? _dateOfBirth;
  DateTime? _hireDate;

  // ═══ ألوان ═══
  static const _cardBg = Colors.white;
  static const _accent = Color(0xFF3498DB);
  static const _headerDark = Color(0xFF2C3E50);
  static const _labelColor = Color(0xFF7F8C8D);
  static const _valueColor = Color(0xFF2D3436);
  static const _success = Color(0xFF27AE60);
  static const _warning = Color(0xFFFF9800);
  static const _ftthColor = Color(0xFF00BCD4);

  @override
  void initState() {
    super.initState();
    _initControllers();
  }

  void _initControllers() {
    final e = widget.employee;
    _fullNameCtrl =
        TextEditingController(text: e['fullName'] ?? e['FullName'] ?? '');
    _phoneCtrl =
        TextEditingController(text: e['phoneNumber'] ?? e['PhoneNumber'] ?? '');
    _deptCtrl =
        TextEditingController(text: e['department'] ?? e['Department'] ?? '');
    _empCodeCtrl = TextEditingController(
        text: e['employeeCode'] ?? e['EmployeeCode'] ?? '');
    _centerCtrl = TextEditingController(text: e['center'] ?? e['Center'] ?? '');
    _salaryCtrl = TextEditingController(
        text: (e['salary'] ?? e['Salary'] ?? 0).toString());
    _nationalIdCtrl =
        TextEditingController(text: e['nationalId'] ?? e['NationalId'] ?? '');
    _bankAccCtrl = TextEditingController(
        text: e['bankAccountNumber'] ?? e['BankAccountNumber'] ?? '');
    _bankNameCtrl =
        TextEditingController(text: e['bankName'] ?? e['BankName'] ?? '');
    _emergNameCtrl = TextEditingController(
        text: e['emergencyContactName'] ?? e['EmergencyContactName'] ?? '');
    _emergPhoneCtrl = TextEditingController(
        text: e['emergencyContactPhone'] ?? e['EmergencyContactPhone'] ?? '');
    _hrNotesCtrl =
        TextEditingController(text: e['hrNotes'] ?? e['HrNotes'] ?? '');

    _contractType = e['contractType'] ?? e['ContractType'];

    final dob = e['dateOfBirth'] ?? e['DateOfBirth'];
    _dateOfBirth = dob != null ? DateTime.tryParse(dob.toString()) : null;

    final hire = e['hireDate'] ?? e['HireDate'];
    _hireDate = hire != null ? DateTime.tryParse(hire.toString()) : null;
  }

  @override
  void dispose() {
    _fullNameCtrl.dispose();
    _phoneCtrl.dispose();
    _deptCtrl.dispose();
    _empCodeCtrl.dispose();
    _centerCtrl.dispose();
    _salaryCtrl.dispose();
    _nationalIdCtrl.dispose();
    _bankAccCtrl.dispose();
    _bankNameCtrl.dispose();
    _emergNameCtrl.dispose();
    _emergPhoneCtrl.dispose();
    _hrNotesCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final empId =
          (widget.employee['id'] ?? widget.employee['Id'] ?? '').toString();
      final data = {
        'fullName': _fullNameCtrl.text,
        'phoneNumber': _phoneCtrl.text,
        'department': _deptCtrl.text,
        'employeeCode': _empCodeCtrl.text,
        'center': _centerCtrl.text,
        'salary': double.tryParse(_salaryCtrl.text) ?? 0,
        'nationalId': _nationalIdCtrl.text,
        'bankAccountNumber': _bankAccCtrl.text,
        'bankName': _bankNameCtrl.text,
        'emergencyContactName': _emergNameCtrl.text,
        'emergencyContactPhone': _emergPhoneCtrl.text,
        'hrNotes': _hrNotesCtrl.text,
        'contractType': _contractType,
        if (_dateOfBirth != null)
          'dateOfBirth': _dateOfBirth!.toIso8601String(),
        if (_hireDate != null) 'hireDate': _hireDate!.toIso8601String(),
      };

      final ok = await EmployeeProfileService.instance
          .updateEmployee(widget.companyId, empId, data);
      if (ok && mounted) {
        setState(() => _editing = false);
        widget.onSaved();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم الحفظ بنجاح', style: GoogleFonts.cairo()),
            backgroundColor: _success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ: $e', style: GoogleFonts.cairo()),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ═══════════════ الحصول على بيانات FTTH ═══════════════
  String get _ftthUsername => (widget.employee['ftthUsername'] ??
          widget.employee['FtthUsername'] ??
          widget.employee['fTthUsername'] ??
          '')
      .toString();

  String get _ftthPassword => (widget.employee['ftthPasswordEncrypted'] ??
          widget.employee['FtthPasswordEncrypted'] ??
          widget.employee['ftthPassword'] ??
          widget.employee['FtthPassword'] ??
          '')
      .toString();

  String get _role =>
      (widget.employee['role'] ?? widget.employee['Role'] ?? '').toString();

  String get _password =>
      (widget.employee['password'] ?? widget.employee['Password'] ?? '')
          .toString();

  // ═══════════════ البناء ═══════════════

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              // ═══ صف أول: الحساب + الوظيفة ═══
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _sectionCard(
                      'معلومات الحساب',
                      Icons.person_outline_rounded,
                      _accent,
                      [
                        _field('الاسم الكامل', _fullNameCtrl, Icons.person),
                        _field('رقم الهاتف', _phoneCtrl, Icons.phone_android),
                        _passwordField(),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _sectionCard(
                      'المعلومات الوظيفية',
                      Icons.work_outline_rounded,
                      const Color(0xFF8E44AD),
                      [
                        _readOnlyField('الدور', _getRoleLabel(_role),
                            Icons.admin_panel_settings, _getRoleColor(_role)),
                        _field('القسم', _deptCtrl, Icons.business),
                        _field('كود الموظف', _empCodeCtrl, Icons.badge),
                        _field('المركز', _centerCtrl, Icons.location_on),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // ═══ صف ثاني: الشخصية + المالية ═══
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _sectionCard(
                      'المعلومات الشخصية',
                      Icons.account_circle_outlined,
                      const Color(0xFFE67E22),
                      [
                        _field(
                            'رقم الهوية', _nationalIdCtrl, Icons.credit_card),
                        _dateField('تاريخ الميلاد', _dateOfBirth, (d) {
                          setState(() => _dateOfBirth = d);
                        }),
                        _dateField('تاريخ التعيين', _hireDate, (d) {
                          setState(() => _hireDate = d);
                        }),
                        _contractTypeField(),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _sectionCard(
                      'المعلومات المالية',
                      Icons.account_balance_outlined,
                      _success,
                      [
                        _field('الراتب الأساسي', _salaryCtrl, Icons.payments,
                            isNumber: true),
                        _field(
                            'اسم البنك', _bankNameCtrl, Icons.account_balance),
                        _field(
                            'رقم الحساب البنكي', _bankAccCtrl, Icons.numbers),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // ═══ صف ثالث: الطوارئ + FTTH ═══
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _sectionCard(
                      'جهة اتصال الطوارئ',
                      Icons.emergency_outlined,
                      Colors.red,
                      [
                        _field('اسم جهة الطوارئ', _emergNameCtrl,
                            Icons.person_pin),
                        _field('هاتف الطوارئ', _emergPhoneCtrl,
                            Icons.phone_callback),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(child: _ftthCard()),
                ],
              ),
              const SizedBox(height: 16),
              // ═══ ملاحظات HR ═══
              _sectionCard(
                'ملاحظات HR',
                Icons.notes_rounded,
                _labelColor,
                [_notesField()],
              ),
              const SizedBox(height: 80), // مسافة للزر العائم
            ],
          ),
        ),
        // زر التعديل / الحفظ
        if (widget.canEdit)
          Positioned(
            left: 20,
            bottom: 20,
            child: Row(
              children: [
                if (_editing) ...[
                  FloatingActionButton.extended(
                    heroTag: 'cancel',
                    onPressed: () {
                      setState(() => _editing = false);
                      _initControllers();
                    },
                    backgroundColor: Colors.grey,
                    icon: const Icon(Icons.close, color: Colors.white),
                    label: Text('إلغاء',
                        style: GoogleFonts.cairo(color: Colors.white)),
                  ),
                  const SizedBox(width: 12),
                  FloatingActionButton.extended(
                    heroTag: 'save',
                    onPressed: _saving ? null : _save,
                    backgroundColor: _success,
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ))
                        : const Icon(Icons.save, color: Colors.white),
                    label: Text('حفظ',
                        style: GoogleFonts.cairo(color: Colors.white)),
                  ),
                ] else
                  FloatingActionButton.extended(
                    heroTag: 'edit',
                    onPressed: () => setState(() => _editing = true),
                    backgroundColor: _accent,
                    icon: const Icon(Icons.edit, color: Colors.white),
                    label: Text('تعديل',
                        style: GoogleFonts.cairo(color: Colors.white)),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  // ═══════════════ بطاقة القسم ═══════════════

  Widget _sectionCard(
      String title, IconData icon, Color color, List<Widget> children) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 10,
              offset: const Offset(0, 3)),
        ],
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // الرأس
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [color.withOpacity(0.08), color.withOpacity(0.02)],
                begin: Alignment.centerRight,
                end: Alignment.centerLeft,
              ),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(14)),
              border: Border(
                bottom: BorderSide(color: color.withOpacity(0.15)),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: color, size: 18),
                ),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: GoogleFonts.cairo(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: _headerDark,
                  ),
                ),
              ],
            ),
          ),
          // المحتوى
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(children: children),
          ),
        ],
      ),
    );
  }

  // ═══════════════ حقل عادي ═══════════════

  Widget _field(String label, TextEditingController ctrl, IconData icon,
      {bool isNumber = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          SizedBox(
            width: 150,
            child: Row(
              children: [
                Icon(icon, size: 15, color: _labelColor),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(label,
                      style:
                          GoogleFonts.cairo(color: _labelColor, fontSize: 12)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _editing
                ? TextField(
                    controller: ctrl,
                    keyboardType:
                        isNumber ? TextInputType.number : TextInputType.text,
                    style: GoogleFonts.cairo(fontSize: 13),
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Color(0xFFDDDDDD)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Color(0xFFDDDDDD)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide:
                            const BorderSide(color: _accent, width: 1.5),
                      ),
                    ),
                  )
                : Container(
                    width: double.infinity,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8F9FA),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFEEEEEE)),
                    ),
                    child: Text(
                      ctrl.text.isEmpty ? '—' : ctrl.text,
                      style: GoogleFonts.cairo(
                        fontSize: 13,
                        color: ctrl.text.isEmpty ? _labelColor : _valueColor,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  // ═══════════════ حقل للقراءة فقط (الدور) ═══════════════

  Widget _readOnlyField(
      String label, String value, IconData icon, Color badgeColor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          SizedBox(
            width: 150,
            child: Row(
              children: [
                Icon(icon, size: 15, color: _labelColor),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(label,
                      style:
                          GoogleFonts.cairo(color: _labelColor, fontSize: 12)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: badgeColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: badgeColor.withOpacity(0.3)),
            ),
            child: Text(
              value,
              style: GoogleFonts.cairo(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: badgeColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════ حقل كلمة المرور ═══════════════

  Widget _passwordField() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          SizedBox(
            width: 150,
            child: Row(
              children: [
                const Icon(Icons.lock_outline, size: 15, color: _labelColor),
                const SizedBox(width: 6),
                Expanded(
                  child: Text('كلمة المرور',
                      style:
                          GoogleFonts.cairo(color: _labelColor, fontSize: 12)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF8E1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _warning.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _password.isEmpty
                          ? '—'
                          : _showPassword
                              ? _password
                              : '•' * _password.length.clamp(6, 16),
                      style: _password.isNotEmpty
                          ? TextStyle(
                              fontSize: 13,
                              fontFamily: _showPassword ? 'monospace' : null,
                              color: _valueColor,
                              letterSpacing: _showPassword ? 0 : 2,
                            )
                          : GoogleFonts.cairo(
                              fontSize: 13,
                              color: _labelColor,
                            ),
                    ),
                  ),
                  if (_password.isNotEmpty) ...[
                    InkWell(
                      onTap: () =>
                          setState(() => _showPassword = !_showPassword),
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.all(2),
                        child: Icon(
                          _showPassword
                              ? Icons.visibility_off_rounded
                              : Icons.visibility_rounded,
                          size: 16,
                          color: _warning.withOpacity(0.7),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    InkWell(
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: _password));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('تم نسخ كلمة المرور',
                                style: GoogleFonts.cairo()),
                            duration: const Duration(seconds: 1),
                          ),
                        );
                      },
                      child: Icon(Icons.copy_rounded,
                          size: 16, color: _warning.withOpacity(0.7)),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════ بطاقة FTTH ═══════════════

  Widget _ftthCard() {
    final isLinked = _ftthUsername.isNotEmpty;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 10,
              offset: const Offset(0, 3)),
        ],
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // الرأس
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  _ftthColor.withOpacity(0.08),
                  _ftthColor.withOpacity(0.02)
                ],
                begin: Alignment.centerRight,
                end: Alignment.centerLeft,
              ),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(14)),
              border: Border(
                bottom: BorderSide(color: _ftthColor.withOpacity(0.15)),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: _ftthColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.router, color: _ftthColor, size: 18),
                ),
                const SizedBox(width: 10),
                Text(
                  'معلومات نظام FTTH',
                  style: GoogleFonts.cairo(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: _headerDark,
                  ),
                ),
                const Spacer(),
                // شارة حالة الربط
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: isLinked
                        ? _success.withOpacity(0.1)
                        : _warning.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isLinked
                          ? _success.withOpacity(0.3)
                          : _warning.withOpacity(0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: isLinked ? _success : _warning,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        isLinked ? 'مربوط' : 'غير مربوط',
                        style: GoogleFonts.cairo(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: isLinked ? _success : _warning,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // المحتوى
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: isLinked
                ? Column(
                    children: [
                      _ftthRow(
                        'اسم المستخدم FTTH',
                        _ftthUsername,
                        Icons.person_outline,
                      ),
                      const SizedBox(height: 12),
                      _ftthRow(
                        'كلمة مرور FTTH',
                        _ftthPassword.isNotEmpty ? _ftthPassword : '—',
                        Icons.vpn_key_outlined,
                        isSensitive: true,
                      ),
                    ],
                  )
                : Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Column(
                        children: [
                          Icon(Icons.link_off_rounded,
                              size: 36, color: _labelColor.withOpacity(0.4)),
                          const SizedBox(height: 8),
                          Text(
                            'هذا الموظف غير مربوط بنظام FTTH',
                            style: GoogleFonts.cairo(
                              color: _labelColor,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'يمكنك ربطه من شاشة حسابات ← ربط المشغلين',
                            style: GoogleFonts.cairo(
                              color: _labelColor.withOpacity(0.7),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _ftthRow(String label, String value, IconData icon,
      {bool isSensitive = false}) {
    final showVal = isSensitive ? _showFtthPassword : true;
    final displayText = value.isEmpty
        ? '—'
        : showVal
            ? value
            : '•' * value.length.clamp(6, 16);

    return Row(
      children: [
        SizedBox(
          width: 150,
          child: Row(
            children: [
              Icon(icon, size: 15, color: _ftthColor),
              const SizedBox(width: 6),
              Expanded(
                child: Text(label,
                    style: GoogleFonts.cairo(color: _labelColor, fontSize: 12)),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: _ftthColor.withOpacity(0.04),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _ftthColor.withOpacity(0.15)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: SelectableText(
                    displayText,
                    style: (isSensitive && showVal && value.isNotEmpty)
                        ? TextStyle(
                            fontSize: 13,
                            fontFamily: 'monospace',
                            color: _valueColor,
                          )
                        : GoogleFonts.cairo(
                            fontSize: 13,
                            color: value.isNotEmpty ? _valueColor : _labelColor,
                          ),
                  ),
                ),
                if (isSensitive && value.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: InkWell(
                      onTap: () => setState(
                          () => _showFtthPassword = !_showFtthPassword),
                      borderRadius: BorderRadius.circular(4),
                      child: Icon(
                        _showFtthPassword
                            ? Icons.visibility_off_rounded
                            : Icons.visibility_rounded,
                        size: 14,
                        color: _ftthColor.withOpacity(0.5),
                      ),
                    ),
                  ),
                if (value.isNotEmpty)
                  InkWell(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: value));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('تم النسخ', style: GoogleFonts.cairo()),
                          duration: const Duration(seconds: 1),
                        ),
                      );
                    },
                    child: Icon(Icons.copy_rounded,
                        size: 14, color: _ftthColor.withOpacity(0.5)),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ═══════════════ حقل التاريخ ═══════════════

  Widget _dateField(
      String label, DateTime? value, ValueChanged<DateTime?> onChanged) {
    final display = value != null
        ? '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}'
        : '—';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          SizedBox(
            width: 150,
            child: Row(
              children: [
                const Icon(Icons.calendar_today, size: 15, color: _labelColor),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(label,
                      style:
                          GoogleFonts.cairo(color: _labelColor, fontSize: 12)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _editing
                ? InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: value ?? DateTime(1990),
                        firstDate: DateTime(1950),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (picked != null) onChanged(picked);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFFDDDDDD)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(display, style: GoogleFonts.cairo(fontSize: 13)),
                          const Icon(Icons.calendar_today,
                              size: 14, color: _accent),
                        ],
                      ),
                    ),
                  )
                : Container(
                    width: double.infinity,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8F9FA),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFEEEEEE)),
                    ),
                    child: Text(display,
                        style: GoogleFonts.cairo(
                            fontSize: 13,
                            color: value != null ? _valueColor : _labelColor)),
                  ),
          ),
        ],
      ),
    );
  }

  // ═══════════════ حقل نوع العقد ═══════════════

  Widget _contractTypeField() {
    const types = [
      ('permanent', 'دائم'),
      ('contract', 'عقد'),
      ('partTime', 'جزئي'),
    ];

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          SizedBox(
            width: 150,
            child: Row(
              children: [
                const Icon(Icons.work, size: 15, color: _labelColor),
                const SizedBox(width: 6),
                Text('نوع العقد',
                    style: GoogleFonts.cairo(color: _labelColor, fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _editing
                ? DropdownButtonFormField<String>(
                    value: _contractType,
                    items: types
                        .map((t) => DropdownMenuItem(
                              value: t.$1,
                              child: Text(t.$2,
                                  style: GoogleFonts.cairo(fontSize: 13)),
                            ))
                        .toList(),
                    onChanged: (v) => setState(() => _contractType = v),
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  )
                : Container(
                    width: double.infinity,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8F9FA),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFEEEEEE)),
                    ),
                    child: Text(
                      types
                              .where((t) => t.$1 == _contractType)
                              .map((t) => t.$2)
                              .firstOrNull ??
                          '—',
                      style: GoogleFonts.cairo(
                          fontSize: 13,
                          color: _contractType != null
                              ? _valueColor
                              : _labelColor),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  // ═══════════════ حقل الملاحظات ═══════════════

  Widget _notesField() {
    return _editing
        ? TextField(
            controller: _hrNotesCtrl,
            maxLines: 4,
            style: GoogleFonts.cairo(fontSize: 13),
            decoration: InputDecoration(
              hintText: 'ملاحظات HR...',
              hintStyle: GoogleFonts.cairo(color: _labelColor),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          )
        : Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFF8F9FA),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFEEEEEE)),
            ),
            child: Text(
              _hrNotesCtrl.text.isEmpty ? 'لا توجد ملاحظات' : _hrNotesCtrl.text,
              style: GoogleFonts.cairo(
                fontSize: 13,
                color: _hrNotesCtrl.text.isEmpty ? _labelColor : _valueColor,
              ),
            ),
          );
  }

  // ═══════════════ Helpers ═══════════════

  Color _getRoleColor(String role) {
    switch (role) {
      case 'SuperAdmin':
        return const Color(0xFFE74C3C);
      case 'CompanyAdmin':
        return const Color(0xFF8E44AD);
      case 'Manager':
        return const Color(0xFF2980B9);
      case 'TechnicalLeader':
        return const Color(0xFF16A085);
      case 'Technician':
        return const Color(0xFF27AE60);
      case 'Viewer':
        return const Color(0xFF95A5A6);
      case 'Employee':
        return const Color(0xFF3498DB);
      default:
        return const Color(0xFF7F8C8D);
    }
  }

  String _getRoleLabel(String role) {
    switch (role) {
      case 'SuperAdmin':
        return 'مدير النظام';
      case 'CompanyAdmin':
        return 'مدير الشركة';
      case 'Manager':
        return 'مدير';
      case 'TechnicalLeader':
        return 'ليدر فني';
      case 'Technician':
        return 'فني';
      case 'Viewer':
        return 'مشاهد';
      case 'Employee':
        return 'موظف';
      default:
        return role.isEmpty ? 'غير محدد' : role;
    }
  }
}
