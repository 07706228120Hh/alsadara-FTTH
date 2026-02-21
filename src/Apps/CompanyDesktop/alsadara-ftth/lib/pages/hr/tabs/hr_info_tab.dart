/// تبويب بيانات HR — المعلومات الشخصية والوظيفية
/// يعرض ويعدل: الاسم، الهاتف، القسم، الكود، الراتب الأساسي
/// + الحقول الجديدة: الجنسية، تاريخ الميلاد، التعيين، العقد، البنك، الطوارئ
library;

import 'package:flutter/material.dart';
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

  static const _accent = Color(0xFF3498DB);
  static const _labelColor = Color(0xFF7F8C8D);
  static const _cardShadow = [
    BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2)),
  ];

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
            backgroundColor: Colors.green,
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

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              _sectionCard('المعلومات الأساسية', Icons.person, [
                _fieldRow('الاسم الكامل', _fullNameCtrl, Icons.person),
                _fieldRow('رقم الهاتف', _phoneCtrl, Icons.phone),
                _fieldRow('القسم', _deptCtrl, Icons.business),
                _fieldRow('كود الموظف', _empCodeCtrl, Icons.badge),
                _fieldRow('المركز', _centerCtrl, Icons.location_on),
              ]),
              const SizedBox(height: 16),
              _sectionCard('المعلومات الشخصية', Icons.account_circle, [
                _fieldRow('رقم الهوية', _nationalIdCtrl, Icons.credit_card),
                _dateField('تاريخ الميلاد', _dateOfBirth, (d) {
                  setState(() => _dateOfBirth = d);
                }),
                _dateField('تاريخ التعيين', _hireDate, (d) {
                  setState(() => _hireDate = d);
                }),
                _contractTypeField(),
              ]),
              const SizedBox(height: 16),
              _sectionCard('المعلومات المالية', Icons.account_balance, [
                _fieldRow('الراتب الأساسي', _salaryCtrl, Icons.payments,
                    isNumber: true),
                _fieldRow('اسم البنك', _bankNameCtrl, Icons.account_balance),
                _fieldRow('رقم الحساب البنكي', _bankAccCtrl, Icons.numbers),
              ]),
              const SizedBox(height: 16),
              _sectionCard('جهة اتصال الطوارئ', Icons.emergency, [
                _fieldRow('اسم جهة الطوارئ', _emergNameCtrl, Icons.person_pin),
                _fieldRow(
                    'هاتف الطوارئ', _emergPhoneCtrl, Icons.phone_callback),
              ]),
              const SizedBox(height: 16),
              _sectionCard('ملاحظات HR', Icons.notes, [
                _notesField(),
              ]),
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
                    backgroundColor: Colors.green,
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

  Widget _sectionCard(String title, IconData icon, List<Widget> children) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: _cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: _accent.withOpacity(0.08),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                Icon(icon, color: _accent, size: 20),
                const SizedBox(width: 8),
                Text(title,
                    style: GoogleFonts.cairo(
                        fontWeight: FontWeight.bold, fontSize: 14)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: children),
          ),
        ],
      ),
    );
  }

  Widget _fieldRow(String label, TextEditingController ctrl, IconData icon,
      {bool isNumber = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          SizedBox(
            width: 160,
            child: Row(
              children: [
                Icon(icon, size: 16, color: _labelColor),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(label,
                      style:
                          GoogleFonts.cairo(color: _labelColor, fontSize: 13)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8F9FA),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      ctrl.text.isEmpty ? '—' : ctrl.text,
                      style: GoogleFonts.cairo(
                          fontSize: 13,
                          color:
                              ctrl.text.isEmpty ? _labelColor : Colors.black87),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

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
            width: 160,
            child: Row(
              children: [
                const Icon(Icons.calendar_today, size: 16, color: _labelColor),
                const SizedBox(width: 6),
                Text(label,
                    style: GoogleFonts.cairo(color: _labelColor, fontSize: 13)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _editing
                ? InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: value ?? DateTime(1990),
                        firstDate: DateTime(1950),
                        lastDate: DateTime.now(),
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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8F9FA),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(display,
                        style: GoogleFonts.cairo(
                            fontSize: 13,
                            color:
                                value != null ? Colors.black87 : _labelColor)),
                  ),
          ),
        ],
      ),
    );
  }

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
            width: 160,
            child: Row(
              children: [
                const Icon(Icons.work, size: 16, color: _labelColor),
                const SizedBox(width: 6),
                Text('نوع العقد',
                    style: GoogleFonts.cairo(color: _labelColor, fontSize: 13)),
              ],
            ),
          ),
          const SizedBox(width: 12),
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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8F9FA),
                      borderRadius: BorderRadius.circular(6),
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
                              ? Colors.black87
                              : _labelColor),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

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
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              _hrNotesCtrl.text.isEmpty ? 'لا توجد ملاحظات' : _hrNotesCtrl.text,
              style: GoogleFonts.cairo(
                fontSize: 13,
                color: _hrNotesCtrl.text.isEmpty ? _labelColor : Colors.black87,
              ),
            ),
          );
  }
}
