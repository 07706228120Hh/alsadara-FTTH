import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/sas_account.dart';

/// نتيجة نموذج حساب الساس (إنشاء/تعديل).
class SasAccountFormResult {
  final String label;
  final String serverUrl;
  final String username;

  /// كلمة المرور — إدخال فقط؛ فارغة في التعديل تعني «بلا تغيير».
  final String password;
  final SasAccountType accountType;
  final bool isActive;

  const SasAccountFormResult({
    required this.label,
    required this.serverUrl,
    required this.username,
    required this.password,
    required this.accountType,
    required this.isActive,
  });
}

/// حوار ربط/تعديل حساب ساس بثيم الصدارة.
///
/// ⚠️ كلمة المرور حقل إدخال فقط؛ لا تُعرَض قيمة قائمة ولا تُطبَع في أي مكان.
class SasAccountFormDialog extends StatefulWidget {
  /// الحساب المراد تعديله (null = إنشاء جديد).
  final SasAccount? existing;

  const SasAccountFormDialog({super.key, this.existing});

  @override
  State<SasAccountFormDialog> createState() => _SasAccountFormDialogState();
}

class _SasAccountFormDialogState extends State<SasAccountFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _labelCtrl;
  late final TextEditingController _serverCtrl;
  late final TextEditingController _userCtrl;
  final _passCtrl = TextEditingController();

  late SasAccountType _accountType;
  late bool _isActive;
  bool _obscure = true;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _labelCtrl = TextEditingController(text: e?.label ?? '');
    _serverCtrl = TextEditingController(text: e?.serverUrl ?? '');
    _userCtrl = TextEditingController(text: e?.username ?? '');
    _accountType = e?.accountType ?? SasAccountType.sasManager;
    _isActive = e?.isActive ?? true;
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    _serverCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(
      SasAccountFormResult(
        label: _labelCtrl.text.trim(),
        serverUrl: _serverCtrl.text.trim(),
        username: _userCtrl.text.trim(),
        password: _passCtrl.text,
        accountType: _accountType,
        isActive: _isActive,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: Text(
          _isEdit ? 'تعديل حساب الساس' : 'ربط حساب ساس',
          style: GoogleFonts.cairo(fontWeight: FontWeight.w800),
        ),
        content: SizedBox(
          width: 420.w,
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _field(
                    controller: _labelCtrl,
                    label: 'التسمية',
                    icon: Icons.label_outline_rounded,
                    hint: 'اسم يميّز الحساب (اختياري)',
                  ),
                  SizedBox(height: 12.h),
                  _field(
                    controller: _serverCtrl,
                    label: 'عنوان خادم الساس',
                    icon: Icons.dns_rounded,
                    hint: 'https://sas.example.com',
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'عنوان الخادم مطلوب'
                        : null,
                  ),
                  SizedBox(height: 12.h),
                  _field(
                    controller: _userCtrl,
                    label: 'اسم المستخدم',
                    icon: Icons.person_outline_rounded,
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'اسم المستخدم مطلوب'
                        : null,
                  ),
                  SizedBox(height: 12.h),
                  TextFormField(
                    controller: _passCtrl,
                    obscureText: _obscure,
                    style: GoogleFonts.cairo(),
                    decoration: InputDecoration(
                      labelText: 'كلمة المرور',
                      hintText: _isEdit ? 'اتركها فارغة لعدم التغيير' : null,
                      prefixIcon: const Icon(Icons.lock_outline_rounded),
                      suffixIcon: IconButton(
                        icon: Icon(_obscure
                            ? Icons.visibility_off_rounded
                            : Icons.visibility_rounded),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                    validator: (v) {
                      // في الإنشاء كلمة المرور مطلوبة؛ في التعديل اختيارية.
                      if (!_isEdit && (v == null || v.isEmpty)) {
                        return 'كلمة المرور مطلوبة';
                      }
                      return null;
                    },
                  ),
                  SizedBox(height: 12.h),
                  DropdownButtonFormField<SasAccountType>(
                    initialValue: _accountType,
                    decoration: InputDecoration(
                      labelText: 'نوع الحساب',
                      prefixIcon: const Icon(Icons.category_outlined),
                      labelStyle: GoogleFonts.cairo(),
                    ),
                    items: SasAccountType.values
                        .map((t) => DropdownMenuItem(
                              value: t,
                              child: Text(t.labelAr, style: GoogleFonts.cairo()),
                            ))
                        .toList(),
                    onChanged: (v) =>
                        setState(() => _accountType = v ?? _accountType),
                  ),
                  SizedBox(height: 4.h),
                  SwitchListTile(
                    value: _isActive,
                    onChanged: (v) => setState(() => _isActive = v),
                    title: Text('الحساب مُفعَّل', style: GoogleFonts.cairo()),
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('إلغاء', style: GoogleFonts.cairo()),
          ),
          FilledButton.icon(
            onPressed: _submit,
            icon: Icon(_isEdit ? Icons.save_rounded : Icons.link_rounded),
            label: Text(_isEdit ? 'حفظ' : 'ربط',
                style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? hint,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      style: GoogleFonts.cairo(),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon),
        labelStyle: GoogleFonts.cairo(),
      ),
      validator: validator,
    );
  }
}
