import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/app_theme.dart';
import '../models/sas_account.dart';
import 'sas_metrics.dart';

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
      child: Dialog(
        insetPadding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 24.h),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20.r)),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: 440.w,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _header(),
              Padding(
                padding: EdgeInsets.fromLTRB(20.w, 18.h, 20.w, 4.h),
                child: _body(),
              ),
              _actions(),
            ],
          ),
        ),
      ),
    );
  }

  /// رأس متدرّج بلون المنصّة مع أيقونة وعنوان.
  Widget _header() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 18.h),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: AppTheme.blueGradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 42.w,
            height: 42.w,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(12.r),
              border: Border.all(color: Colors.white.withValues(alpha: 0.30)),
            ),
            child: Icon(
              _isEdit ? Icons.edit_rounded : Icons.add_link_rounded,
              color: Colors.white,
              size: 22.sp,
            ),
          ),
          SizedBox(width: 12.w),
          Text(
            _isEdit ? 'تعديل حساب الساس' : 'ربط حساب ساس',
            style: GoogleFonts.cairo(
              fontWeight: FontWeight.w800,
              fontSize: 16.sp,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _actions() {
    return Padding(
      padding: EdgeInsets.fromLTRB(20.w, 6.h, 20.w, 16.h),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.grey[700],
                side: BorderSide(color: Colors.grey.withValues(alpha: 0.35)),
                padding: EdgeInsets.symmetric(vertical: 13.h),
              ),
              child: Text('إلغاء',
                  style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
            ),
          ),
          SizedBox(width: 12.w),
          Expanded(
            flex: 2,
            child: FilledButton.icon(
              onPressed: _submit,
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                padding: EdgeInsets.symmetric(vertical: 13.h),
              ),
              icon: Icon(_isEdit ? Icons.save_rounded : Icons.link_rounded,
                  size: 18.sp),
              label: Text(_isEdit ? 'حفظ التعديلات' : 'ربط الحساب',
                  style: GoogleFonts.cairo(
                      fontWeight: FontWeight.w800, fontSize: 13.5.sp)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body() {
    return Form(
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
                      hintStyle: GoogleFonts.cairo(color: Colors.grey[400]),
                      prefixIcon: Icon(Icons.lock_outline_rounded,
                          color: AppTheme.primaryColor, size: 20.sp),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscure
                              ? Icons.visibility_off_rounded
                              : Icons.visibility_rounded,
                          color: Colors.grey[500],
                        ),
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
                      prefixIcon: Icon(Icons.category_outlined,
                          color: AppTheme.primaryColor, size: 20.sp),
                      labelStyle: GoogleFonts.cairo(),
                    ),
                    style: GoogleFonts.cairo(
                        fontWeight: FontWeight.w600, color: Colors.black87),
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
              activeThumbColor: AppTheme.primaryColor,
              contentPadding: EdgeInsets.zero,
            ),
          ],
        ),
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
      style: GoogleFonts.cairo(fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        hintStyle: GoogleFonts.cairo(color: Colors.grey[400]),
        prefixIcon: Icon(icon, color: AppTheme.primaryColor, size: 20.sp),
        labelStyle: GoogleFonts.cairo(),
      ),
      validator: validator,
    );
  }
}
